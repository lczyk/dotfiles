// pure helpers extracted from the funnel binary so benches + tests can
// import them without going through main.

use std::path::{Path, PathBuf};

// derive watch root from glob pattern: longest leading path of literal
// components (no wildcard chars). returns (root, recursive).
pub fn watch_root(pattern: &str) -> (PathBuf, bool) {
    let recursive = pattern.contains("**");
    let mut root = PathBuf::new();
    let mut saw_any = false;
    for comp in Path::new(pattern).components() {
        let s = comp.as_os_str().to_string_lossy();
        if s.contains('*') || s.contains('?') || s.contains('[') || s.contains('{') {
            break;
        }
        root.push(comp);
        saw_any = true;
    }
    if !saw_any {
        root = PathBuf::from(".");
    }
    (root, recursive)
}

// fnv-1a 32-bit hash. NOTE: not cryptographic -- visual hash only, do not
// use for security. just needs to look random enough that distinct paths
// get distinct colors.
pub fn fnv1a(bytes: &[u8]) -> u32 {
    let mut h: u32 = 0x811c_9dc5;
    for &b in bytes {
        h ^= b as u32;
        h = h.wrapping_mul(0x0100_0193);
    }
    h
}

pub fn path_color(path: &Path) -> (u8, u8, u8) {
    let bytes = path.as_os_str().to_string_lossy().into_owned().into_bytes();
    let h = fnv1a(&bytes);
    let mut r = (h >> 16) & 0xff;
    let mut g = (h >> 8) & 0xff;
    let mut b = h & 0xff;
    // luma-bump loop: ported from container-throwaway. bump one channel
    // (chosen by re-hashing path + iter) by 60 until luma > 100 or 10 iters.
    for iter in 0..10u32 {
        let luma = (2126 * r + 7152 * g + 722 * b) / 10000;
        if luma > 100 {
            break;
        }
        let mut seed = bytes.clone();
        seed.extend_from_slice(iter.to_string().as_bytes());
        let pick = fnv1a(&seed) % 3;
        match pick {
            0 => r = (r + 60).min(255),
            1 => g = (g + 60).min(255),
            _ => b = (b + 60).min(255),
        }
    }
    (r as u8, g as u8, b as u8)
}

pub fn build_prefix(path: &Path, color: bool) -> Vec<u8> {
    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned());
    if color {
        let (r, g, b) = path_color(path);
        format!("\x1b[38;2;{r};{g};{b}m[{name}]\x1b[0m ").into_bytes()
    } else {
        format!("[{name}] ").into_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn watch_root_simple() {
        let (r, rec) = watch_root("/tmp/foo/*.log");
        assert_eq!(r, PathBuf::from("/tmp/foo"));
        assert!(!rec);
    }

    #[test]
    fn watch_root_recursive() {
        let (r, rec) = watch_root("/tmp/foo/**/*.log");
        assert_eq!(r, PathBuf::from("/tmp/foo"));
        assert!(rec);
    }

    #[test]
    fn watch_root_no_wildcard() {
        let (r, _) = watch_root("/tmp/foo/bar.log");
        assert_eq!(r, PathBuf::from("/tmp/foo/bar.log"));
    }

    #[test]
    fn watch_root_relative() {
        let (r, _) = watch_root("*.log");
        assert_eq!(r, PathBuf::from("."));
    }

    #[test]
    fn fnv_deterministic() {
        assert_eq!(fnv1a(b"hello"), fnv1a(b"hello"));
        assert_ne!(fnv1a(b"hello"), fnv1a(b"world"));
    }

    #[test]
    fn color_meets_luma_threshold() {
        for s in &["a", "foo.log", "/tmp/x/y.log", "zzz"] {
            let (r, g, b) = path_color(Path::new(s));
            let luma = (2126 * r as u32 + 7152 * g as u32 + 722 * b as u32) / 10000;
            assert!(luma > 50, "luma too low for {s}: {luma}");
        }
    }

    #[test]
    fn prefix_no_color() {
        let p = build_prefix(Path::new("/tmp/foo.log"), false);
        assert_eq!(p, b"[foo.log] ");
    }

    #[test]
    fn prefix_with_color() {
        let p = build_prefix(Path::new("/tmp/foo.log"), true);
        let s = String::from_utf8(p).unwrap();
        assert!(s.starts_with("\x1b[38;2;"));
        assert!(s.contains("[foo.log]"));
        assert!(s.ends_with("\x1b[0m "));
    }
}
