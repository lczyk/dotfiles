// funnel watches files matching a glob and streams their appended content to
// stdout, prefixing each line with `[basename] `. handles rotation /
// truncation / unlink-recreate like `tail -F`. prefix is colorized per-file
// via a hash of the full path, so the same file always gets the same color.

use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::Duration;

use globset::{Glob, GlobMatcher};
use notify::{EventKind, RecursiveMode, Watcher};

use funnel::{build_prefix, watch_root};

const HELP: &str = r#"Usage: funnel <glob> [OPTIONS]

Watch files matching <glob> and stream appended lines to stdout, prefixed
with `[basename] `. Tracks rotation/truncation like `tail -F`.

Examples:
  funnel '/tmp/claude/log/*.log'
  funnel '~/logs/**/*.log'

Options:
  -h, --help        Print help information
  -v, --version     Print version information
  --no-color        Disable colored prefixes (also honors NO_COLOR env)
"#;

struct Args {
    pattern: String,
    no_color: bool,
}

fn parse_args(argv: &[String]) -> Args {
    let mut pattern: Option<String> = None;
    let mut no_color = false;
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
    Args { pattern, no_color }
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
    file: File,
    inode: u64,
    size: u64,
    partial: Vec<u8>,
    prefix: Vec<u8>,
}

fn open_tracked(path: &Path, color: bool, seek_end: bool) -> io::Result<Tracked> {
    let mut file = File::open(path)?;
    let meta = file.metadata()?;
    let size = meta.len();
    let inode = meta.ino();
    if seek_end {
        file.seek(SeekFrom::End(0))?;
    }
    Ok(Tracked {
        file,
        inode,
        size,
        partial: Vec::new(),
        prefix: build_prefix(path, color),
    })
}

// drain newly-available bytes from t.file, emit complete lines to stdout
// w/ prefix. returns Err on broken stdout (caller exits).
fn drain(t: &mut Tracked, stdout: &mut io::StdoutLock) -> io::Result<()> {
    let meta = t.file.metadata()?;
    let cur_size = meta.len();
    let cur_inode = meta.ino();
    if cur_inode != t.inode || cur_size < t.size {
        // truncation or inode swap detected during read: reset to start.
        t.file.seek(SeekFrom::Start(0))?;
        t.inode = cur_inode;
        t.partial.clear();
    }
    let mut buf = Vec::new();
    t.file.read_to_end(&mut buf)?;
    t.size = t.file.stream_position().unwrap_or(cur_size);
    if buf.is_empty() {
        return Ok(());
    }
    t.partial.extend_from_slice(&buf);
    let mut start = 0usize;
    for (i, &b) in t.partial.iter().enumerate() {
        if b == b'\n' {
            stdout.write_all(&t.prefix)?;
            stdout.write_all(&t.partial[start..=i])?;
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

fn run() -> io::Result<()> {
    let args = parse_args(&std::env::args().collect::<Vec<_>>());
    let color = use_color(args.no_color);

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
    let glob = Glob::new(&canon_pattern)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, format!("bad glob: {e}")))?
        .compile_matcher();
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

    // initial flush of any seed-time content (none, since seek-to-end).
    // main event loop.
    loop {
        // tick = 100ms. on each tick, poll-drain every tracked file in
        // addition to processing notify events. macOS fsevents can coalesce
        // / delay events server-side; polling makes latency bounded and
        // predictable (matches multitail's snappiness w/out the 1s ceiling).
        let res = match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(r) => r,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // poll-drain known files.
                let mut stale = Vec::new();
                for (path, t) in tracked.iter_mut() {
                    match drain(t, &mut stdout) {
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
                // rescan dir for newly-appeared files notify may have missed.
                let mut new_paths: Vec<PathBuf> = Vec::new();
                walk(&root, recursive, &mut |p| {
                    if glob.is_match(p) && !tracked.contains_key(p) {
                        new_paths.push(p.to_path_buf());
                    }
                });
                for p in new_paths {
                    match open_tracked(&p, color, false) {
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
            if !glob.is_match(&path) {
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
                        match open_tracked(&path, color, false) {
                            Ok(t) => {
                                tracked.insert(path.clone(), t);
                            }
                            Err(e) => {
                                warn(&path, &e);
                                continue;
                            }
                        }
                    }
                    if let Some(t) = tracked.get_mut(&path)
                        && let Err(e) = drain(t, &mut stdout)
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
    glob: &GlobMatcher,
    color: bool,
    tracked: &mut HashMap<PathBuf, Tracked>,
) {
    walk(root, recursive, &mut |p| {
        if glob.is_match(p) {
            match open_tracked(p, color, true) {
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
