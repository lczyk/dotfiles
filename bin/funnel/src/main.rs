// funnel watches files matching a glob and streams their appended content
// to stdout, prefixing each line with `[label] ` where label is the part
// of the path filled in by the glob's wildcards. handles rotation /
// truncation / unlink-recreate like `tail -F`. prefix is colorized per-file
// via a hash of the full path, so the same file always gets the same color.

use std::collections::{HashMap, HashSet, VecDeque};
use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::mpsc;
use std::time::{Duration, Instant};

const IDLE_CLOSE: Duration = Duration::from_secs(60);

use notify::{EventKind, RecursiveMode, Watcher};

use funnel::{ALLOW_TOKENS, Glob, build_prefix, watch_root};

const HELP: &str = r#"Usage: funnel <glob> [OPTIONS]

Watch files matching <glob> and stream appended lines to stdout, prefixed
with `[label] ` (label = path portion filled in by wildcards). Tracks
rotation/truncation like `tail -F`.

Examples:
  funnel '/tmp/claude/log/*.log'
  funnel '~/logs/**/*.log'

Options:
  -h, --help              Print help information
  -v, --version           Print version information
  --no-color              Disable colored prefixes (also honors NO_COLOR env)
  -m, --mode=<mode>       How to handle lines wider than terminal:
                            wrap         pass through, terminal wraps
                            indent       split at width, indent continuation
                            trim         truncate to terminal width
                          Default: trim on tty, wrap otherwise.
  -s, --scrollback=<n>    Number of lines kept in the scrollback ring (alt-
                          screen mode only). Default: 10000.
  --allow=<tokens>        Opt in to hard-to-reason-about glob shapes.
                          Comma-separated, repeatable. Use `-name` to remove.
                          Tokens:
                            multi-doublestar     >1 `**` segment
                            mixed-doublestar     `**` mixed w/ other chars
                            classes              `[abc]` / `{a,b}`
                            bare-wild            wildcard in first segment
                            trailing-doublestar  pattern ends in `**`
                            interleaved          >1 wildcard in one segment
                          Also honors $FUNNEL_ALLOW.
"#;

#[derive(Clone, Copy)]
enum LongLines {
    Wrap,
    Indent,
    Trim,
}

struct Args {
    pattern: String,
    no_color: bool,
    long_lines: Option<LongLines>,
    allow_values: Vec<String>,
    scrollback: usize,
}

fn parse_args(argv: &[String]) -> Args {
    let mut pattern: Option<String> = None;
    let mut no_color = false;
    let mut long_lines: Option<LongLines> = None;
    let mut allow_values: Vec<String> = Vec::new();
    let mut scrollback: usize = 10_000;
    let parse_scrollback = |val: &str| -> usize {
        match val.parse::<usize>() {
            Ok(n) if n >= 1 => n,
            _ => {
                eprintln!("funnel: invalid --scrollback value: {val}");
                eprint!("{}", HELP);
                std::process::exit(2);
            }
        }
    };
    let parse_mode = |val: &str| -> LongLines {
        match val {
            "wrap" => LongLines::Wrap,
            "indent" => LongLines::Indent,
            "trim" => LongLines::Trim,
            other => {
                eprintln!("funnel: invalid --mode value: {other}");
                eprint!("{}", HELP);
                std::process::exit(2);
            }
        }
    };
    let mut i = 1;
    while i < argv.len() {
        let arg = argv[i].as_str();
        match arg {
            "-v" | "--version" => {
                println!("funnel {}", version::version!());
                std::process::exit(0);
            }
            "-h" | "--help" => {
                print!("{}", HELP);
                std::process::exit(0);
            }
            "--no-color" => no_color = true,
            "-m" | "--mode" => {
                i += 1;
                let Some(val) = argv.get(i) else {
                    eprintln!("funnel: {arg} requires a value");
                    eprint!("{}", HELP);
                    std::process::exit(2);
                };
                long_lines = Some(parse_mode(val));
            }
            s if s.starts_with("--mode=") => {
                long_lines = Some(parse_mode(&s["--mode=".len()..]));
            }
            s if s.starts_with("-m=") => {
                long_lines = Some(parse_mode(&s["-m=".len()..]));
            }
            "-s" | "--scrollback" => {
                i += 1;
                let Some(val) = argv.get(i) else {
                    eprintln!("funnel: {arg} requires a value");
                    eprint!("{}", HELP);
                    std::process::exit(2);
                };
                scrollback = parse_scrollback(val);
            }
            s if s.starts_with("--scrollback=") => {
                scrollback = parse_scrollback(&s["--scrollback=".len()..]);
            }
            s if s.starts_with("-s=") => {
                scrollback = parse_scrollback(&s["-s=".len()..]);
            }
            s if s.starts_with("--allow=") => {
                allow_values.push(s["--allow=".len()..].to_string());
            }
            s if s.starts_with('-') => {
                eprintln!("funnel: unknown flag: {s}");
                eprint!("{}", HELP);
                std::process::exit(2);
            }
            s => {
                if pattern.is_some() {
                    eprintln!("funnel: extra positional argument: {s}");
                    std::process::exit(2);
                }
                pattern = Some(s.to_string());
            }
        }
        i += 1;
    }
    let pattern = pattern.unwrap_or_else(|| {
        eprint!("{}", HELP);
        std::process::exit(2);
    });
    Args {
        pattern,
        no_color,
        long_lines,
        allow_values,
        scrollback,
    }
}

fn use_color(no_color_flag: bool) -> bool {
    if no_color_flag {
        return false;
    }
    if std::env::var_os("NO_COLOR").is_some_and(|v| !v.is_empty()) {
        return false;
    }
    // SAFETY: isatty on stdout fd is always safe to call.
    unsafe { libc::isatty(libc::STDOUT_FILENO) == 1 }
}

struct Tracked {
    // None when idle-closed; reopened lazily on next drain w/ growth.
    file: Option<File>,
    inode: u64,
    size: u64,
    partial: Vec<u8>,
    prefix: Vec<u8>,
    // visible width of prefix (`[basename] `), excludes ANSI color escapes.
    prefix_width: usize,
    last_activity: Instant,
}

// stat_tracked: build a Tracked entry w/o opening the file. start_offset=Some(0)
// means "treat as new, read existing content from start" (notify Create / rescan);
// None means "start from current EOF" (seed). no fd is held until drain opens one.
fn stat_tracked(
    path: &Path,
    glob: &Glob,
    color: bool,
    start_offset: Option<u64>,
) -> io::Result<Tracked> {
    let meta = fs::metadata(path)?;
    let cur_size = meta.len();
    let size = match start_offset {
        Some(o) => o.min(cur_size),
        None => cur_size,
    };
    let label = glob.label(&path.to_string_lossy());
    let label_width = label.chars().count();
    Ok(Tracked {
        file: None,
        inode: meta.ino(),
        size,
        partial: Vec::new(),
        prefix: build_prefix(&label, path, color),
        prefix_width: label_width + 3, // `[` + label + `]` + ` `
        last_activity: Instant::now(),
    })
}

// raise RLIMIT_NOFILE soft limit toward hard. macOS default soft is small
// (often 256-2560); funnel may track thousands of files, so bump for headroom
// even though we now idle-close.
fn bump_nofile() {
    // SAFETY: rlimit is plain data; getrlimit fills it, setrlimit reads it.
    unsafe {
        let mut rl: libc::rlimit = std::mem::zeroed();
        if libc::getrlimit(libc::RLIMIT_NOFILE, &mut rl) != 0 {
            return;
        }
        // macOS reports rlim_max as RLIM_INFINITY but kernel caps at
        // kern.maxfilesperproc (typically 10240-49152). step down on failure.
        for target in [rl.rlim_max, 65536, 16384, 8192, 4096] {
            if target <= rl.rlim_cur {
                break;
            }
            let mut new = rl;
            new.rlim_cur = target;
            if libc::setrlimit(libc::RLIMIT_NOFILE, &new) == 0 {
                break;
            }
        }
    }
}

fn term_size() -> (usize, usize) {
    // SAFETY: ioctl on stdout fd writing into a stack winsize struct.
    let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
    if unsafe { libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut ws) } == 0
        && ws.ws_col > 0
        && ws.ws_row > 0
    {
        (ws.ws_col as usize, ws.ws_row as usize)
    } else {
        let w = std::env::var("COLUMNS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(80);
        let h = std::env::var("LINES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(24);
        (w, h)
    }
}

// LineRec: ring buffer element. Plain emit record; no gap markers (alacritty-
// style offset anchoring handles eviction silently, see Renderer).
#[derive(Clone)]
struct LineRec {
    prefix: Vec<u8>,
    pw: usize,
    content: Vec<u8>,
}

// Renderer: alt-screen TUI pager when stdout-tty AND mode=Trim. Ring buffer of
// last `cap` emits; scroll position is a single `display_offset` -- lines
// above the live bottom (0 = follow). When an emit arrives while paused
// (display_offset > 0), the offset auto-bumps so the visible content stays
// anchored to the same lines as the ring ages. Mirrors alacritty's grid
// scroll model. Non-alt path: streams emit_line directly.
struct Renderer {
    mode: LongLines,
    alt: bool,
    width: usize,
    height: usize,
    ring: VecDeque<LineRec>,
    cap: usize,
    display_offset: usize,
    dirty: bool,
}

impl Renderer {
    fn new(mode: LongLines, alt: bool, cap: usize) -> Self {
        let (w, h) = term_size();
        Renderer {
            mode,
            alt,
            width: w,
            height: h,
            ring: VecDeque::new(),
            cap,
            display_offset: 0,
            dirty: false,
        }
    }

    fn max_offset(&self) -> usize {
        self.ring.len().saturating_sub(self.view_size())
    }

    // visible content rows = total height - 1 (status row reserved at bottom).
    fn view_size(&self) -> usize {
        self.height.saturating_sub(1).max(1)
    }

    fn emit<W: Write>(
        &mut self,
        out: &mut W,
        prefix: &[u8],
        pw: usize,
        content: &[u8],
    ) -> io::Result<()> {
        if !self.alt {
            return emit_line(out, prefix, pw, content, self.mode, self.width);
        }
        while self.ring.len() >= self.cap {
            self.ring.pop_front();
        }
        self.ring.push_back(LineRec {
            prefix: prefix.to_vec(),
            pw,
            content: content.to_vec(),
        });
        // Paused: bump offset so visible window stays anchored on same content
        // as the ring grows. Saturates at max_offset -- once there, content
        // silently ages out of the top of the view (matches alacritty).
        if self.display_offset > 0 {
            self.display_offset = (self.display_offset + 1).min(self.max_offset());
        }
        self.dirty = true;
        Ok(())
    }

    fn check_resize(&mut self) {
        let (w, h) = term_size();
        if w != self.width || h != self.height {
            self.width = w;
            self.height = h;
            let max = self.ring.len().saturating_sub(view_size_h(h));
            if self.display_offset > max {
                self.display_offset = max;
            }
            self.dirty = true;
        }
    }

    fn scroll_up(&mut self, lines: usize) {
        if !self.alt {
            return;
        }
        let max = self.max_offset();
        let new_off = (self.display_offset + lines).min(max);
        if new_off != self.display_offset {
            self.display_offset = new_off;
            self.dirty = true;
        }
    }

    fn scroll_down(&mut self, lines: usize) {
        if !self.alt {
            return;
        }
        let new_off = self.display_offset.saturating_sub(lines);
        if new_off != self.display_offset {
            self.display_offset = new_off;
            self.dirty = true;
        }
    }

    // Flicker-free paint: render entire frame into an in-memory buffer, then
    // issue a single write_all to stdout. Per-row positioning via CUP +
    // `\x1b[K` clear-to-eol instead of `\x1b[2J` full-screen clear -- avoids
    // the visible blank flash that 2J causes every frame during scrolling.
    fn paint<W: Write>(&mut self, out: &mut W) -> io::Result<()> {
        if !self.alt || !self.dirty {
            return Ok(());
        }
        let vs = self.view_size();
        let end = self.ring.len().saturating_sub(self.display_offset);
        let start = end.saturating_sub(vs);
        let entries: Vec<LineRec> = self.ring.range(start..end).cloned().collect();
        let status = if self.display_offset == 0 {
            "-- following (scroll up to pause) --".to_string()
        } else {
            format!(
                "-- paused: {} below | {} above --",
                self.display_offset, start
            )
        };

        let mut buf: Vec<u8> = Vec::with_capacity(8 * 1024);
        // body rows (1..=vs). cursor_to(row, 1) + clear_eol + content.
        let mut any_overflow = false;
        for i in 0..vs {
            write!(buf, "\x1b[{};1H\x1b[K", i + 1)?;
            if let Some(rec) = entries.get(i) {
                if matches!(self.mode, LongLines::Trim)
                    && line_overflows(rec.pw, &rec.content, self.width)
                {
                    any_overflow = true;
                }
                emit_line_inner(
                    &mut buf,
                    &rec.prefix,
                    rec.pw,
                    &rec.content,
                    self.mode,
                    self.width,
                    false,
                )?;
            }
        }
        // status row at the very last terminal row. last cell shows `>` when
        // any visible line had content trimmed; same fg/bg as the rest of
        // the bar (no separate color escape -- whole row is inverse video).
        write!(buf, "\x1b[{};1H\x1b[K\x1b[7m", self.height.max(1))?;
        let indicator = if any_overflow { b'>' } else { b' ' };
        // status text capped at width-1 so the indicator always fits
        let st = truncate_to_width(&status, self.width.saturating_sub(1));
        let st_cols = st.chars().count();
        buf.extend_from_slice(st.as_bytes());
        let target = self.width.saturating_sub(1);
        buf.extend(std::iter::repeat_n(b' ', target.saturating_sub(st_cols)));
        if self.width >= 1 {
            buf.push(indicator);
        }
        buf.extend_from_slice(b"\x1b[0m");

        out.write_all(&buf)?;
        out.flush()?;
        self.dirty = false;
        Ok(())
    }
}

// helper for resize-time clamp (view_size depends on height; this lets us
// compute against an arbitrary height in scope where self isn't available).
fn view_size_h(h: usize) -> usize {
    h.saturating_sub(1).max(1)
}

// Returns true iff rendering this content in trim mode at the given width
// would drop one or more visible cells from the right. Walks the same
// tab/control-char accounting as `emit_line_inner` so the answer matches
// what actually gets rendered.
fn line_overflows(prefix_width: usize, content: &[u8], width: usize) -> bool {
    if prefix_width >= width {
        // line entirely skipped at this width -- treat as overflow so the
        // user knows there's content they're not seeing.
        return !content.is_empty();
    }
    let s = String::from_utf8_lossy(content);
    let mut col = prefix_width;
    for c in s.chars() {
        let w = if c == '\t' {
            8 - (col % 8)
        } else if (c as u32) < 0x20 || c == '\x7f' {
            continue;
        } else {
            1
        };
        if col + w > width {
            return true;
        }
        col += w;
    }
    false
}

fn truncate_to_width(s: &str, width: usize) -> String {
    s.chars().take(width).collect()
}

// AltScreenGuard: enters alt-screen + hides cursor on construction; restores
// on drop. construct BEFORE acquiring the stdout lock in run() so that Drop
// (which re-locks stdout) doesn't deadlock -- drops run in reverse construction
// order, so the long-lived stdout lock is released first.
struct AltScreenGuard;

impl AltScreenGuard {
    fn new() -> io::Result<Self> {
        let stdout = io::stdout();
        let mut lock = stdout.lock();
        // alt-screen + hide cursor + clear + enable SGR mouse tracking
        // (1000 = press events, 1006 = SGR encoding for >223 col/row).
        lock.write_all(b"\x1b[?1049h\x1b[?25l\x1b[H\x1b[2J\x1b[?1000h\x1b[?1006h")?;
        lock.flush()?;
        Ok(AltScreenGuard)
    }
}

impl Drop for AltScreenGuard {
    fn drop(&mut self) {
        let stdout = io::stdout();
        let mut lock = stdout.lock();
        let _ = lock.write_all(b"\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l");
        let _ = lock.flush();
    }
}

// signal handling: SIGINT/SIGTERM/SIGHUP bump a counter. main loop polls it
// and returns Ok(()) so Drop chains run (alt-screen exit, termios restore).
// second signal forces `_exit` -- terminal stays dirty, cost of impatience.
static SIGNAL_COUNT: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(0);

extern "C" fn on_signal(_sig: libc::c_int) {
    let prev = SIGNAL_COUNT.fetch_add(1, Ordering::SeqCst);
    if prev >= 1 {
        // SAFETY: _exit is async-signal-safe; skips Drop chains by design.
        unsafe { libc::_exit(130); }
    }
}

fn install_signal_handlers() {
    // SAFETY: installing handler for std termination signals. handler is
    // async-signal-safe (atomic add + maybe _exit).
    unsafe {
        libc::signal(libc::SIGINT, on_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGTERM, on_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGHUP, on_signal as *const () as libc::sighandler_t);
    }
}

// emit one line (content excludes trailing newline) per long-line mode.
// When newline=true a trailing `\n` is appended after the line content.
// When false, no terminator is written -- used by the alt-screen paint path
// which positions each row via CUP escapes (`\x1b[<row>;1H`).
fn emit_line<W: Write>(
    out: &mut W,
    prefix: &[u8],
    prefix_width: usize,
    content: &[u8],
    mode: LongLines,
    width: usize,
) -> io::Result<()> {
    emit_line_inner(out, prefix, prefix_width, content, mode, width, true)
}

fn emit_line_inner<W: Write>(
    out: &mut W,
    prefix: &[u8],
    prefix_width: usize,
    content: &[u8],
    mode: LongLines,
    width: usize,
    newline: bool,
) -> io::Result<()> {
    match mode {
        LongLines::Wrap => {
            out.write_all(prefix)?;
            out.write_all(content)?;
            if newline {
                out.write_all(b"\n")?;
            }
        }
        LongLines::Trim => {
            // narrow terminal: label alone wouldn't fit, so skip rendering
            // this line entirely. ring buffer still holds it; on widening,
            // check_resize re-emits at the new width.
            if prefix_width >= width {
                return Ok(());
            }
            let s = String::from_utf8_lossy(content);
            let mut cut = String::new();
            let mut col = prefix_width;
            for c in s.chars() {
                // tab expands to next 8-col stop in terminal coords
                let w = if c == '\t' {
                    8 - (col % 8)
                } else if (c as u32) < 0x20 || c == '\x7f' {
                    // control chars: skip, no width
                    continue;
                } else {
                    1
                };
                if col + w > width {
                    break;
                }
                if c == '\t' {
                    for _ in 0..w {
                        cut.push(' ');
                    }
                } else {
                    cut.push(c);
                }
                col += w;
            }
            out.write_all(prefix)?;
            out.write_all(cut.as_bytes())?;
            if newline {
                out.write_all(b"\n")?;
            }
        }
        LongLines::Indent => {
            let avail = width.saturating_sub(prefix_width).max(1);
            let s = String::from_utf8_lossy(content);
            let chars: Vec<char> = s.chars().collect();
            if chars.len() <= avail {
                out.write_all(prefix)?;
                out.write_all(content)?;
                if newline {
                    out.write_all(b"\n")?;
                }
            } else {
                let indent = vec![b' '; prefix_width];
                let mut i = 0;
                let mut first = true;
                let last_idx = chars.len();
                while i < chars.len() {
                    let end = (i + avail).min(chars.len());
                    let chunk: String = chars[i..end].iter().collect();
                    if first {
                        out.write_all(prefix)?;
                        first = false;
                    } else {
                        out.write_all(&indent)?;
                    }
                    out.write_all(chunk.as_bytes())?;
                    let is_last_chunk = end >= last_idx;
                    if newline || !is_last_chunk {
                        out.write_all(b"\n")?;
                    }
                    i = end;
                }
            }
        }
    }
    Ok(())
}

// drain newly-available bytes from path, emit complete lines to stdout
// w/ prefix. stat-first: skips opening when size unchanged + inode same,
// so closed-idle entries stay closed. returns Err on broken stdout (caller exits).
fn drain(
    t: &mut Tracked,
    path: &Path,
    stdout: &mut io::StdoutLock,
    renderer: &mut Renderer,
) -> io::Result<()> {
    let meta = fs::metadata(path)?;
    let cur_size = meta.len();
    let cur_inode = meta.ino();
    let rotated = cur_inode != t.inode || cur_size < t.size;
    if !rotated && cur_size == t.size {
        return Ok(());
    }
    if t.file.is_none() {
        t.file = Some(File::open(path)?);
    }
    let f = t.file.as_mut().unwrap();
    if rotated {
        f.seek(SeekFrom::Start(0))?;
        t.inode = cur_inode;
        t.size = 0;
        t.partial.clear();
    } else {
        // newly-opened or position may have drifted; align to stored offset.
        f.seek(SeekFrom::Start(t.size))?;
    }
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)?;
    t.size = f.stream_position().unwrap_or(cur_size);
    if buf.is_empty() {
        return Ok(());
    }
    t.last_activity = Instant::now();
    t.partial.extend_from_slice(&buf);
    let mut start = 0usize;
    let len = t.partial.len();
    for i in 0..len {
        if t.partial[i] == b'\n' {
            let content = &t.partial[start..i];
            renderer.emit(stdout, &t.prefix, t.prefix_width, content)?;
            start = i + 1;
        }
    }
    if start > 0 {
        t.partial.drain(..start);
    }
    stdout.flush()?;
    Ok(())
}

fn warn(path: &Path, err: &dyn std::fmt::Display) {
    eprintln!("funnel: {}: {err}", path.display());
}

// raw-mode guard for stdin: disables canonical + echo so we can read 'q'
// without waiting for newline. restores original termios on drop.
struct RawGuard {
    saved: libc::termios,
    fd: i32,
}

impl RawGuard {
    fn new() -> Option<Self> {
        // SAFETY: isatty on stdin fd is always safe to call.
        if unsafe { libc::isatty(libc::STDIN_FILENO) } != 1 {
            return None;
        }
        let fd = libc::STDIN_FILENO;
        // SAFETY: termios is plain-data; tcgetattr fills it.
        let mut saved: libc::termios = unsafe { std::mem::zeroed() };
        if unsafe { libc::tcgetattr(fd, &mut saved) } != 0 {
            return None;
        }
        let mut raw = saved;
        raw.c_lflag &= !(libc::ICANON | libc::ECHO);
        raw.c_cc[libc::VMIN] = 1;
        raw.c_cc[libc::VTIME] = 0;
        if unsafe { libc::tcsetattr(fd, libc::TCSANOW, &raw) } != 0 {
            return None;
        }
        Some(RawGuard { saved, fd })
    }
}

impl Drop for RawGuard {
    fn drop(&mut self) {
        // SAFETY: restoring saved termios.
        unsafe {
            libc::tcsetattr(self.fd, libc::TCSANOW, &self.saved);
        }
    }
}

#[derive(Clone, Copy, Debug)]
enum InputEvent {
    Quit,
    ScrollUp,
    ScrollDown,
}

// unified event for the main loop: file change notifications and input events
// share the same channel so the loop wakes on either w/out separate polling.
enum Event {
    Notify(notify::Result<notify::Event>),
    Input(InputEvent),
}

// parse a single input event from the front of `buf`. returns
// Some((maybe_event, bytes_consumed)) if a complete token was found, else
// None (need more bytes). bytes_consumed > 0 even when no event of interest
// (lets us skip unknown sequences).
fn parse_input(buf: &[u8]) -> Option<(Option<InputEvent>, usize)> {
    if buf.is_empty() {
        return None;
    }
    match buf[0] {
        b'q' | 0x03 => Some((Some(InputEvent::Quit), 1)),
        0x1b => {
            if buf.len() < 2 {
                return None;
            }
            if buf[1] != b'[' {
                // bare ESC or non-CSI escape: consume ESC + next byte, ignore
                return Some((None, 2));
            }
            if buf.len() < 3 {
                return None;
            }
            // SGR mouse: ESC [ < button ; x ; y (M|m)
            if buf[2] == b'<' {
                let mut i = 3;
                while i < buf.len() && buf[i] != b'M' && buf[i] != b'm' {
                    i += 1;
                }
                if i >= buf.len() {
                    return None;
                }
                let inner = &buf[3..i];
                let parts: Vec<&[u8]> = inner.split(|&b| b == b';').collect();
                if parts.len() < 3 {
                    return Some((None, i + 1));
                }
                let button: u32 = std::str::from_utf8(parts[0])
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
                // wheel: 64 = up, 65 = down. modifier bits (4/8/16) may be set.
                let basic = button & 0b11_00011;
                let evt = match basic {
                    64 => Some(InputEvent::ScrollUp),
                    65 => Some(InputEvent::ScrollDown),
                    _ => None,
                };
                return Some((evt, i + 1));
            }
            // other CSI: consume until alphabetic terminator (or ~)
            let mut i = 2;
            while i < buf.len() {
                let b = buf[i];
                if b.is_ascii_alphabetic() || b == b'~' {
                    return Some((None, i + 1));
                }
                i += 1;
            }
            None
        }
        _ => Some((None, 1)),
    }
}

fn spawn_input_watcher(tx: mpsc::Sender<Event>) {
    std::thread::spawn(move || {
        use std::io::Read;
        let mut chunk = [0u8; 64];
        let mut acc: Vec<u8> = Vec::with_capacity(128);
        let mut stdin = io::stdin();
        loop {
            match stdin.read(&mut chunk) {
                Ok(0) => return,
                Ok(n) => {
                    acc.extend_from_slice(&chunk[..n]);
                    while let Some((evt_opt, consumed)) = parse_input(&acc) {
                        acc.drain(..consumed);
                        if let Some(evt) = evt_opt
                            && tx.send(Event::Input(evt)).is_err()
                        {
                            return;
                        }
                        if acc.is_empty() {
                            break;
                        }
                    }
                }
                Err(_) => return,
            }
        }
    });
}

fn run() -> io::Result<()> {
    bump_nofile();
    install_signal_handlers();
    let args = parse_args(&std::env::args().collect::<Vec<_>>());
    let color = use_color(args.no_color);
    // SAFETY: isatty on stdout fd is always safe to call.
    let stdout_tty = unsafe { libc::isatty(libc::STDOUT_FILENO) == 1 };
    let long_mode = args
        .long_lines
        .unwrap_or(if stdout_tty { LongLines::Trim } else { LongLines::Wrap });
    let use_alt = stdout_tty && matches!(long_mode, LongLines::Trim);

    let (root, recursive) = watch_root(&args.pattern);
    if !root.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("watch root does not exist: {}", root.display()),
        ));
    }
    // canonicalize root + rewrite glob to use canonical prefix. macOS
    // resolves /tmp -> /private/tmp; notify events come back canonical,
    // so the glob must also be in canonical form to match.
    let canon_root = root
        .canonicalize()
        .map_err(|e| io::Error::new(e.kind(), format!("canonicalize {}: {e}", root.display())))?;
    let tail = args
        .pattern
        .strip_prefix(&root.to_string_lossy().into_owned())
        .unwrap_or(&args.pattern);
    let canon_pattern = format!("{}{}", canon_root.display(), tail);
    // build the allow-set: env var first, then cli occurrences layered on top.
    let mut allow: HashSet<&'static str> = HashSet::new();
    polyflag::apply_env_for_flag("funnel", "allow", ALLOW_TOKENS, &mut allow)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, format!("$FUNNEL_ALLOW: {e}")))?;
    for v in &args.allow_values {
        polyflag::apply(v, ALLOW_TOKENS, &mut allow)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, format!("--allow: {e}")))?;
    }

    let glob = Glob::compile_with(&canon_pattern, &allow)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, format!("bad glob: {e}")))?;
    let root = canon_root;

    // unified event channel: notify file events + stdin input events share
    // the same receiver so the main loop wakes on either source w/out polling.
    let (tx, rx) = mpsc::channel::<Event>();
    let notify_tx = tx.clone();
    let mut watcher = notify::recommended_watcher(move |res| {
        let _ = notify_tx.send(Event::Notify(res));
    })
    .map_err(|e| io::Error::other(format!("watcher init: {e}")))?;
    let mode = if recursive {
        RecursiveMode::Recursive
    } else {
        RecursiveMode::NonRecursive
    };
    watcher
        .watch(&root, mode)
        .map_err(|e| io::Error::other(format!("watch {}: {e}", root.display())))?;

    let mut tracked: HashMap<PathBuf, Tracked> = HashMap::new();

    // seed: existing files matching glob, tail from end.
    seed_existing(&root, recursive, &glob, color, &mut tracked);

    // AltScreenGuard constructed BEFORE acquiring the long-lived stdout lock
    // so its Drop (which re-locks stdout to emit exit sequences) runs after
    // the lock is released. drops run in reverse construction order.
    let _alt = if use_alt { Some(AltScreenGuard::new()?) } else { None };
    let stdout = io::stdout();
    let mut stdout = stdout.lock();
    let mut renderer = Renderer::new(long_mode, use_alt, args.scrollback);

    // Prefill ring with tail content from existing files (alt-screen only).
    // Streaming path leaves stdout untouched -- no historical content shown
    // there, matching the pre-TUI behaviour of starting from current EOF.
    if use_alt {
        prefill_renderer(
            &mut stdout,
            &mut renderer,
            &tracked,
            &glob,
            color,
            args.scrollback,
        );
    }

    // raw stdin so we can detect 'q' / ctrl-c / SGR mouse wheel events w/out
    // line buffering. when stdin isn't a tty, no guard, no input watcher
    // (signal handlers still cover SIGINT/SIGTERM/SIGHUP via SIGNAL_COUNT).
    let _guard = RawGuard::new();
    if _guard.is_some() {
        spawn_input_watcher(tx.clone());
    }
    drop(tx);
    const WHEEL_LINES: usize = 1;

    // main event loop.
    loop {
        if SIGNAL_COUNT.load(Ordering::SeqCst) > 0 {
            return Ok(());
        }
        // tick = 100ms. on each tick, poll-drain every tracked file in
        // addition to processing notify events. macOS fsevents can coalesce
        // / delay events server-side; polling makes latency bounded and
        // predictable (matches multitail's snappiness w/out the 1s ceiling).
        // Input events arrive on the same channel so the loop wakes on them
        // immediately -- no scroll lag.
        let event = match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(Event::Input(InputEvent::Quit)) => return Ok(()),
            Ok(Event::Input(InputEvent::ScrollUp)) => {
                renderer.scroll_up(WHEEL_LINES);
                if let Err(e) = renderer.paint(&mut stdout)
                    && e.kind() == io::ErrorKind::BrokenPipe
                {
                    return Ok(());
                }
                continue;
            }
            Ok(Event::Input(InputEvent::ScrollDown)) => {
                renderer.scroll_down(WHEEL_LINES);
                if let Err(e) = renderer.paint(&mut stdout)
                    && e.kind() == io::ErrorKind::BrokenPipe
                {
                    return Ok(());
                }
                continue;
            }
            Ok(Event::Notify(res)) => res,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // refresh terminal size each tick (cheap ioctl, handles
                // SIGWINCH w/out wiring a signal handler).
                renderer.check_resize();
                // poll-drain known files. drain stat-first; closed entries
                // stay closed unless growth detected.
                let mut stale = Vec::new();
                for (path, t) in tracked.iter_mut() {
                    match drain(t, path, &mut stdout, &mut renderer) {
                        Ok(()) => {}
                        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => return Ok(()),
                        Err(e) if e.kind() == io::ErrorKind::NotFound => {
                            stale.push(path.clone());
                        }
                        Err(e) => warn(path, &e),
                    }
                }
                for p in stale {
                    tracked.remove(&p);
                }
                // idle-close: drop fds for entries quiet > IDLE_CLOSE. state
                // (inode/size/partial) retained so next growth reopens cleanly.
                for t in tracked.values_mut() {
                    if t.file.is_some() && t.last_activity.elapsed() > IDLE_CLOSE {
                        t.file = None;
                    }
                }
                // rescan dir for newly-appeared files notify may have missed.
                let mut new_paths: Vec<PathBuf> = Vec::new();
                walk(&root, recursive, &mut |p| {
                    if glob.is_match_path(p) && !tracked.contains_key(p) {
                        new_paths.push(p.to_path_buf());
                    }
                });
                for p in new_paths {
                    match stat_tracked(&p, &glob, color, Some(0)) {
                        Ok(t) => {
                            tracked.insert(p, t);
                        }
                        Err(e) => warn(&p, &e),
                    }
                }
                if let Err(e) = renderer.paint(&mut stdout)
                    && e.kind() == io::ErrorKind::BrokenPipe
                {
                    return Ok(());
                }
                continue;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        };
        let event = match event {
            Ok(e) => e,
            Err(e) => {
                eprintln!("funnel: watch error: {e}");
                continue;
            }
        };
        for path in event.paths {
            if !glob.is_match_path(&path) {
                continue;
            }
            match event.kind {
                EventKind::Remove(_) => {
                    tracked.remove(&path);
                }
                EventKind::Create(_) | EventKind::Modify(_) | EventKind::Any | EventKind::Other => {
                    // path may be new (recreated after unlink) or known.
                    let needs_open = match tracked.get(&path) {
                        None => true,
                        Some(t) => match path.metadata() {
                            Ok(m) => m.ino() != t.inode,
                            Err(_) => true,
                        },
                    };
                    if needs_open {
                        tracked.remove(&path);
                        match stat_tracked(&path, &glob, color, Some(0)) {
                            Ok(t) => {
                                tracked.insert(path.clone(), t);
                            }
                            Err(e) => {
                                warn(&path, &e);
                                continue;
                            }
                        }
                    }
                    renderer.check_resize();
                    if let Some(t) = tracked.get_mut(&path)
                        && let Err(e) = drain(t, &path, &mut stdout, &mut renderer)
                    {
                        if e.kind() == io::ErrorKind::BrokenPipe {
                            return Ok(());
                        }
                        warn(&path, &e);
                    }
                }
                EventKind::Access(_) => {}
            }
        }
        if let Err(e) = renderer.paint(&mut stdout)
            && e.kind() == io::ErrorKind::BrokenPipe
        {
            return Ok(());
        }
    }
    Ok(())
}

// Read up to `max_lines` complete lines from the tail of `path`. Reads at
// most `max_bytes` from the end (skips a leading partial line if the read
// started mid-line). Used by prefill to populate the ring on startup w/out
// loading large files in full.
fn read_tail_lines(path: &Path, max_bytes: u64, max_lines: usize) -> io::Result<Vec<Vec<u8>>> {
    let mut file = File::open(path)?;
    let size = file.metadata()?.len();
    let start = size.saturating_sub(max_bytes);
    file.seek(SeekFrom::Start(start))?;
    let mut buf = Vec::new();
    file.read_to_end(&mut buf)?;
    if buf.last() == Some(&b'\n') {
        buf.pop();
    }
    let mut lines: Vec<Vec<u8>> = if start > 0 {
        // dropped into middle of a line; discard the leading partial fragment
        let mut it = buf.split(|&b| b == b'\n');
        it.next();
        it.map(|l| l.to_vec()).collect()
    } else {
        buf.split(|&b| b == b'\n').map(|l| l.to_vec()).collect()
    };
    if lines.len() > max_lines {
        let drop_n = lines.len() - max_lines;
        lines.drain(..drop_n);
    }
    Ok(lines)
}

// Pure planner for the prefill: given a set of files (with mtimes), the total
// line budget, and the current time, decide how many lines to read from each.
//
// Algorithm:
// - sqrt-decay budget per file based on age relative to `now`:
//     take = clamp(PER_FILE_MAX / sqrt(1 + age_hours), 1, PER_FILE_MAX)
//   so 30 lines at age 0, ~21 at 1h, ~13 at 4h, ~6 at 24h, ~2 at 1wk.
//   floor 1 keeps even ancient files in the buffer.
// - iterate newest-first, deducting from the budget; newest files always get
//   their share even if the budget runs out before the oldest.
// - return plan in emit order (oldest-first) so newest content lands at the
//   bottom of the view.
//
// Files with `take == 0` (budget exhausted before reaching them) are omitted.
const PREFILL_PER_FILE_MAX: usize = 30;

fn plan_prefill(
    files: &[(PathBuf, std::time::SystemTime)],
    total_budget: usize,
    now: std::time::SystemTime,
) -> Vec<(PathBuf, usize)> {
    let mut by_age: Vec<&(PathBuf, std::time::SystemTime)> = files.iter().collect();
    by_age.sort_by(|a, b| b.1.cmp(&a.1)); // newest first
    let mut taken = 0usize;
    let mut plan_rev: Vec<(PathBuf, usize)> = Vec::new();
    for (path, mtime) in by_age {
        let remaining = total_budget.saturating_sub(taken);
        if remaining == 0 {
            break;
        }
        let age_secs = now
            .duration_since(*mtime)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0);
        let age_hours = age_secs / 3600.0;
        let weighted = (PREFILL_PER_FILE_MAX as f64 / (1.0 + age_hours).sqrt())
            .round()
            .clamp(1.0, PREFILL_PER_FILE_MAX as f64) as usize;
        let take = weighted.min(remaining);
        if take == 0 {
            continue;
        }
        taken += take;
        plan_rev.push((path.clone(), take));
    }
    plan_rev.reverse(); // emit order = oldest first
    plan_rev
}

// Prefill the renderer ring with tail content from already-existing files,
// sorted oldest-first (so newest content lands at the bottom of the view).
// No per-line timestamp interleave -- not generally derivable from log bytes;
// we just concatenate file tails in mtime order. Each file's tail is capped
// by per-file budget so a single large file doesn't crowd out the others.
fn prefill_renderer<W: Write>(
    out: &mut W,
    renderer: &mut Renderer,
    tracked: &HashMap<PathBuf, Tracked>,
    glob: &Glob,
    color: bool,
    cap: usize,
) {
    // gather (path, mtime), drop entries w/out mtime metadata
    let files: Vec<(PathBuf, std::time::SystemTime)> = tracked
        .keys()
        .filter_map(|p| {
            std::fs::metadata(p)
                .ok()
                .and_then(|m| m.modified().ok())
                .map(|t| (p.clone(), t))
        })
        .collect();
    if files.is_empty() {
        return;
    }
    // Total budget capped at min(scrollback, 10 * terminal_height) -- beyond
    // that, content is unreachable by scrolling and just delays first paint.
    let (_, h) = term_size();
    let total_budget = cap.min(h.saturating_mul(10).max(1));
    let plan = plan_prefill(&files, total_budget, std::time::SystemTime::now());
    for (path, take) in &plan {
        let lines = match read_tail_lines(path, (*take as u64) * 1024, *take) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if lines.is_empty() {
            continue;
        }
        let label = glob.label(&path.to_string_lossy());
        let label_width = label.chars().count();
        let prefix = build_prefix(&label, path, color);
        let pw = label_width + 3;
        for line in &lines {
            let _ = renderer.emit(out, &prefix, pw, line);
        }
        // Paint per file so the user sees content appearing progressively
        // rather than a blank screen until all files are read.
        let _ = renderer.paint(out);
    }
}

fn seed_existing(
    root: &Path,
    recursive: bool,
    glob: &Glob,
    color: bool,
    tracked: &mut HashMap<PathBuf, Tracked>,
) {
    walk(root, recursive, &mut |p| {
        if glob.is_match_path(p) {
            // seed = start_offset None = start tailing from current EOF.
            match stat_tracked(p, glob, color, None) {
                Ok(t) => {
                    tracked.insert(p.to_path_buf(), t);
                }
                Err(e) => warn(p, &e),
            }
        }
    });
}

fn walk(dir: &Path, recursive: bool, cb: &mut dyn FnMut(&Path)) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            warn(dir, &e);
            return;
        }
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let ft = match entry.file_type() {
            Ok(f) => f,
            Err(_) => continue,
        };
        if ft.is_dir() {
            if recursive {
                walk(&path, recursive, cb);
            }
        } else if ft.is_file() {
            cb(&path);
        }
    }
}

fn main() {
    if let Err(e) = run() {
        if e.kind() == io::ErrorKind::BrokenPipe {
            return;
        }
        eprintln!("funnel: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn emit(content: &[u8], mode: LongLines, width: usize) -> String {
        let prefix = b"[lbl] ";
        let prefix_width = 6;
        let mut out = Vec::new();
        emit_line(&mut out, prefix, prefix_width, content, mode, width).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn trim_plain_fits() {
        assert_eq!(emit(b"hello", LongLines::Trim, 20), "[lbl] hello\n");
    }

    #[test]
    fn trim_plain_overflow() {
        // width 12, prefix 6, avail 6
        assert_eq!(emit(b"abcdefghij", LongLines::Trim, 12), "[lbl] abcdef\n");
    }

    #[test]
    fn trim_tab_expands_to_stop() {
        // prefix col=6, tab -> 2 spaces (to col 8), then "x"
        // width 20, plenty of room
        assert_eq!(emit(b"\tx", LongLines::Trim, 20), "[lbl]   x\n");
    }

    #[test]
    fn trim_tab_blocks_overflow() {
        // regression: prior impl counted tab as 1 char so "\txxx" with avail=3
        // emitted "\txxx" raw -> terminal renders as 2+3=5 cols, wrapping.
        // now tab eats 2 cols (6 -> 8), only 2 chars fit (width 12 -> col<=12).
        // expansion: tab=2 spaces (col 6->8), x (8->9), x (9->10), x (10->11) -> all fit
        assert_eq!(emit(b"\txxx", LongLines::Trim, 12), "[lbl]   xxx\n");
        // tighter: width 9 -> after tab col=8, room for 1 x
        assert_eq!(emit(b"\txxx", LongLines::Trim, 9), "[lbl]   x\n");
        // width 7 -> tab would push col to 8 > 7, drop tab and rest
        assert_eq!(emit(b"\txxx", LongLines::Trim, 7), "[lbl] \n");
    }

    #[test]
    fn trim_drops_control_chars() {
        assert_eq!(emit(b"a\x01b\x7fc", LongLines::Trim, 20), "[lbl] abc\n");
    }

    #[test]
    fn trim_tab_midline_stop() {
        // col 6: "ab" -> 8, tab -> col 8 already at stop, expands to next: 8->16 (8 spaces)
        assert_eq!(
            emit(b"ab\tcd", LongLines::Trim, 30),
            "[lbl] ab        cd\n"
        );
    }

    #[test]
    fn trim_skips_when_prefix_too_wide() {
        // prefix_width=6, width=6 -> prefix alone fills/overflows, skip.
        assert_eq!(emit(b"hello", LongLines::Trim, 6), "");
        assert_eq!(emit(b"hello", LongLines::Trim, 5), "");
        assert_eq!(emit(b"hello", LongLines::Trim, 0), "");
        // width=7 leaves 1 col for content
        assert_eq!(emit(b"hello", LongLines::Trim, 7), "[lbl] h\n");
    }

    #[test]
    fn parse_input_quit() {
        assert!(matches!(
            parse_input(b"q"),
            Some((Some(InputEvent::Quit), 1))
        ));
        assert!(matches!(
            parse_input(b"\x03"),
            Some((Some(InputEvent::Quit), 1))
        ));
    }

    #[test]
    fn parse_input_wheel() {
        // ESC [ < 64 ; 10 ; 5 M  -> wheel up
        assert!(matches!(
            parse_input(b"\x1b[<64;10;5M"),
            Some((Some(InputEvent::ScrollUp), 11))
        ));
        // ESC [ < 65 ; 10 ; 5 M  -> wheel down
        assert!(matches!(
            parse_input(b"\x1b[<65;10;5M"),
            Some((Some(InputEvent::ScrollDown), 11))
        ));
    }

    #[test]
    fn parse_input_incomplete() {
        assert!(parse_input(b"\x1b").is_none());
        assert!(parse_input(b"\x1b[").is_none());
        assert!(parse_input(b"\x1b[<64;10;5").is_none());
    }

    #[test]
    fn parse_input_other_csi_skipped() {
        // arrow key (ESC [ A) -- not a wheel event in our scheme but consumed
        let r = parse_input(b"\x1b[A");
        assert!(matches!(r, Some((None, 3))));
    }

    #[test]
    fn plan_prefill_orders_oldest_first() {
        let now = std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_000_000);
        let old = now - std::time::Duration::from_secs(7 * 24 * 3600);
        let mid = now - std::time::Duration::from_secs(4 * 3600);
        let new = now - std::time::Duration::from_secs(60);
        let files = vec![
            (PathBuf::from("a-old"), old),
            (PathBuf::from("c-new"), new),
            (PathBuf::from("b-mid"), mid),
        ];
        let plan = plan_prefill(&files, 1000, now);
        // emit order = oldest first
        assert_eq!(plan.len(), 3);
        assert_eq!(plan[0].0, PathBuf::from("a-old"));
        assert_eq!(plan[1].0, PathBuf::from("b-mid"));
        assert_eq!(plan[2].0, PathBuf::from("c-new"));
        // newest has the largest take; oldest the smallest
        assert!(plan[2].1 > plan[1].1);
        assert!(plan[1].1 > plan[0].1);
        // all takes within [1, 30]
        for (_, t) in &plan {
            assert!(*t >= 1 && *t <= 30);
        }
    }

    #[test]
    fn plan_prefill_recent_file_caps_at_30() {
        let now = std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_000_000);
        let files = vec![(PathBuf::from("recent"), now)];
        let plan = plan_prefill(&files, 1000, now);
        assert_eq!(plan, vec![(PathBuf::from("recent"), 30)]);
    }

    #[test]
    fn plan_prefill_ancient_file_floors_at_1() {
        let now = std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_000_000_000);
        let ancient = now - std::time::Duration::from_secs(365 * 24 * 3600);
        let files = vec![(PathBuf::from("ancient"), ancient)];
        let plan = plan_prefill(&files, 1000, now);
        assert_eq!(plan, vec![(PathBuf::from("ancient"), 1)]);
    }

    #[test]
    fn plan_prefill_respects_total_budget() {
        let now = std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_000_000);
        // many recent files; each would want 30, but budget is 50.
        let files: Vec<(PathBuf, std::time::SystemTime)> = (0..10)
            .map(|i| (PathBuf::from(format!("f{i}")), now))
            .collect();
        let plan = plan_prefill(&files, 50, now);
        let total: usize = plan.iter().map(|(_, t)| *t).sum();
        assert!(total <= 50);
        // only the newest few files appear (all share `now`; sort stable by path)
        assert!(plan.len() <= 2); // 30 + 20 fits, 30 + 30 would overshoot
    }

    #[test]
    fn plan_prefill_empty() {
        let plan = plan_prefill(
            &[],
            100,
            std::time::SystemTime::UNIX_EPOCH,
        );
        assert!(plan.is_empty());
    }

    // ---------- line_overflows ----------

    #[test]
    fn line_overflows_fits_exactly() {
        // prefix_width=6, "abcdef" = 6 chars, width=12 -> col reaches 12, no break
        assert!(!line_overflows(6, b"abcdef", 12));
    }

    #[test]
    fn line_overflows_one_over() {
        assert!(line_overflows(6, b"abcdefg", 12));
    }

    #[test]
    fn line_overflows_tab_pushes_past() {
        // prefix=6, width=10. tab from col 6 -> col 8 (next 8-stop). Then
        // "ab" fits (col 9,10); "abc" overflows (col 11 > 10).
        assert!(!line_overflows(6, b"\tab", 10));
        assert!(line_overflows(6, b"\tabc", 10));
    }

    #[test]
    fn line_overflows_control_chars_ignored() {
        // controls don't count: a,b,c -> 3 visible cells
        assert!(!line_overflows(6, b"a\x01b\x7fc", 9));
        assert!(line_overflows(6, b"a\x01b\x7fc", 8));
    }

    #[test]
    fn line_overflows_prefix_too_wide_with_content() {
        assert!(line_overflows(10, b"hello", 8));
    }

    #[test]
    fn line_overflows_prefix_too_wide_empty_content() {
        // empty content: line is the prefix alone -- nothing trimmed off content
        assert!(!line_overflows(10, b"", 8));
    }

    // ---------- Renderer state machine ----------

    fn make_renderer(cap: usize) -> Renderer {
        let mut r = Renderer::new(LongLines::Trim, true, cap);
        r.width = 80;
        // small height -> view_size = 4 -> few entries trigger scrolling
        r.height = 5;
        r
    }

    fn push(r: &mut Renderer, content: &[u8]) {
        let _ = r.emit(&mut std::io::sink(), b"[x] ", 4, content);
    }

    // top visible content for a given Renderer (first row in view).
    fn top_visible(r: &Renderer) -> Vec<u8> {
        let vs = r.view_size();
        let end = r.ring.len().saturating_sub(r.display_offset);
        let start = end.saturating_sub(vs);
        r.ring[start].content.clone()
    }

    #[test]
    fn scroll_up_from_follow_sets_offset() {
        let mut r = make_renderer(100);
        for i in 0..30 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        assert_eq!(r.display_offset, 0);
        r.scroll_up(1);
        assert_eq!(r.display_offset, 1);
    }

    #[test]
    fn scroll_up_clamps_at_max_offset() {
        let mut r = make_renderer(100);
        for i in 0..30 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        // view_size = height-1 = 4; max_offset = 30 - 4 = 26
        r.scroll_up(1000);
        assert_eq!(r.display_offset, 26);
    }

    #[test]
    fn scroll_up_noop_when_view_covers_ring() {
        let mut r = make_renderer(100);
        for i in 0..3 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        // ring(3) <= view_size(4); nothing to scroll up to -> stay in Follow
        r.scroll_up(10);
        assert_eq!(r.display_offset, 0);
    }

    #[test]
    fn scroll_down_to_zero_returns_to_follow() {
        let mut r = make_renderer(100);
        for i in 0..30 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        r.scroll_up(5);
        assert_eq!(r.display_offset, 5);
        r.scroll_down(10);
        assert_eq!(r.display_offset, 0);
    }

    #[test]
    fn paused_view_anchors_on_emit_within_cap() {
        // ring has slack: emits bump offset 1:1 so visible content stays put.
        let mut r = make_renderer(100);
        for i in 0..10 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        r.scroll_up(3); // offset=3, view shows ring[3..7] = l3..l6, top=l3
        assert_eq!(top_visible(&r), b"l3");
        for i in 10..20 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        // offset bumped 10 times -> 13. ring.len=20, view_size=4, end=20-13=7,
        // start=3 -> top still l3.
        assert_eq!(r.display_offset, 13);
        assert_eq!(top_visible(&r), b"l3");
    }

    #[test]
    fn paused_view_evicts_silently_past_cap() {
        // cap=10, view_size=4 -> max_offset=6. fill, scroll to top, then emit:
        // offset is already at max, so further emits silently age content out
        // of the top of the view (matches alacritty -- no gap marker).
        let mut r = make_renderer(10);
        for i in 0..10 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        r.scroll_up(100); // clamps to 6 (max_offset)
        assert_eq!(r.display_offset, 6);
        assert_eq!(top_visible(&r), b"l0");
        for i in 10..15 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        // ring still holds last 10 (l5..l14). offset stays at max_offset=6.
        // top of view = ring[0] = l5 -- l0..l4 silently aged out.
        assert_eq!(r.ring.len(), 10);
        assert_eq!(r.display_offset, 6);
        assert_eq!(top_visible(&r), b"l5");
    }

    #[test]
    fn resize_clamps_offset() {
        let mut r = make_renderer(100);
        for i in 0..30 {
            push(&mut r, format!("l{i}").as_bytes());
        }
        r.scroll_up(20); // offset=20; max=26 at height=5
        // shrink terminal: height=10 -> view_size=9 -> max_offset=21 (still ok)
        // but height=25 -> view_size=24 -> max_offset=6 (clamps)
        r.height = 25;
        let max = r.ring.len().saturating_sub(view_size_h(r.height));
        if r.display_offset > max {
            r.display_offset = max;
        }
        assert_eq!(r.display_offset, 6);
    }

    #[test]
    fn wrap_passes_through() {
        assert_eq!(
            emit(b"long line here", LongLines::Wrap, 10),
            "[lbl] long line here\n"
        );
    }
}
