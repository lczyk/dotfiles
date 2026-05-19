// funnel watches files matching a glob and streams their appended content
// to stdout, prefixing each line with `[label] ` where label is the part
// of the path filled in by the glob's wildcards. handles rotation /
// truncation / unlink-recreate like `tail -F`. prefix is colorized per-file
// via a hash of the full path, so the same file always gets the same color.

use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
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
  --long-lines=<mode>     How to handle lines wider than terminal:
                            wrap         pass through, terminal wraps
                            wrap-indent  split at width, indent continuation
                            trim         truncate to terminal width (default)
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
    WrapIndent,
    Trim,
}

struct Args {
    pattern: String,
    no_color: bool,
    long_lines: LongLines,
    allow_values: Vec<String>,
}

fn parse_args(argv: &[String]) -> Args {
    let mut pattern: Option<String> = None;
    let mut no_color = false;
    let mut long_lines = LongLines::Trim;
    let mut allow_values: Vec<String> = Vec::new();
    for arg in argv.iter().skip(1) {
        match arg.as_str() {
            "-v" | "--version" => {
                println!("funnel {}", version::version!());
                std::process::exit(0);
            }
            "-h" | "--help" => {
                print!("{}", HELP);
                std::process::exit(0);
            }
            "--no-color" => no_color = true,
            s if s.starts_with("--allow=") => {
                allow_values.push(s["--allow=".len()..].to_string());
            }
            s if s.starts_with("--long-lines=") => {
                long_lines = match &s["--long-lines=".len()..] {
                    "wrap" => LongLines::Wrap,
                    "wrap-indent" => LongLines::WrapIndent,
                    "trim" => LongLines::Trim,
                    other => {
                        eprintln!("funnel: invalid --long-lines value: {other}");
                        eprint!("{}", HELP);
                        std::process::exit(2);
                    }
                };
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

fn term_width() -> usize {
    // SAFETY: ioctl on stdout fd writing into a stack winsize struct.
    let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
    if unsafe { libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut ws) } == 0 && ws.ws_col > 0
    {
        ws.ws_col as usize
    } else {
        std::env::var("COLUMNS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(80)
    }
}

// emit one line (content excludes trailing newline) per long-line mode.
fn emit_line<W: Write>(
    out: &mut W,
    prefix: &[u8],
    prefix_width: usize,
    content: &[u8],
    mode: LongLines,
    width: usize,
) -> io::Result<()> {
    match mode {
        LongLines::Wrap => {
            out.write_all(prefix)?;
            out.write_all(content)?;
            out.write_all(b"\n")?;
        }
        LongLines::Trim => {
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
            out.write_all(b"\n")?;
        }
        LongLines::WrapIndent => {
            let avail = width.saturating_sub(prefix_width).max(1);
            let s = String::from_utf8_lossy(content);
            let chars: Vec<char> = s.chars().collect();
            if chars.len() <= avail {
                out.write_all(prefix)?;
                out.write_all(content)?;
                out.write_all(b"\n")?;
            } else {
                let indent = vec![b' '; prefix_width];
                let mut i = 0;
                let mut first = true;
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
                    out.write_all(b"\n")?;
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
    mode: LongLines,
    width: usize,
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
            emit_line(stdout, &t.prefix, t.prefix_width, content, mode, width)?;
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

fn spawn_quit_watcher(quit: Arc<AtomicBool>) {
    std::thread::spawn(move || {
        use std::io::Read;
        let mut byte = [0u8; 1];
        let mut stdin = io::stdin();
        loop {
            match stdin.read(&mut byte) {
                Ok(0) => return,
                Ok(_) => {
                    if byte[0] == b'q' || byte[0] == 3 {
                        quit.store(true, Ordering::SeqCst);
                        return;
                    }
                }
                Err(_) => return,
            }
        }
    });
}

fn run() -> io::Result<()> {
    bump_nofile();
    let args = parse_args(&std::env::args().collect::<Vec<_>>());
    let color = use_color(args.no_color);
    let long_mode = args.long_lines;

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

    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |res| {
        let _ = tx.send(res);
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

    let stdout = io::stdout();
    let mut stdout = stdout.lock();

    // raw stdin so we can detect 'q' (or ctrl-c) w/out a newline. _guard
    // restores termios on drop. when stdin isn't a tty, no guard, no watcher.
    let quit = Arc::new(AtomicBool::new(false));
    let _guard = RawGuard::new();
    if _guard.is_some() {
        spawn_quit_watcher(quit.clone());
    }

    // initial flush of any seed-time content (none, since seek-to-end).
    // main event loop.
    loop {
        if quit.load(Ordering::SeqCst) {
            return Ok(());
        }
        // tick = 100ms. on each tick, poll-drain every tracked file in
        // addition to processing notify events. macOS fsevents can coalesce
        // / delay events server-side; polling makes latency bounded and
        // predictable (matches multitail's snappiness w/out the 1s ceiling).
        let res = match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(r) => r,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // refresh terminal width each tick (cheap ioctl, handles
                // SIGWINCH w/out wiring a signal handler).
                let width = term_width();
                // poll-drain known files. drain stat-first; closed entries
                // stay closed unless growth detected.
                let mut stale = Vec::new();
                for (path, t) in tracked.iter_mut() {
                    match drain(t, path, &mut stdout, long_mode, width) {
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
                continue;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        };
        let event = match res {
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
                    let width = term_width();
                    if let Some(t) = tracked.get_mut(&path)
                        && let Err(e) = drain(t, &path, &mut stdout, long_mode, width)
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
    }
    Ok(())
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