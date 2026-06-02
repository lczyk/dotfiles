// pure helpers extracted from the funnel binary so benches + tests can
// import them without going through main.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use polyflag::{KnownToken, token};

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

// build_prefix renders `[label] ` w/ optional ANSI truecolor. label is the
// glob-derived display name; color_seed is whatever bytes drive the hue
// (typically the full path, so the same file always gets the same color).
pub fn build_prefix(label: &str, color_seed: &Path, color: bool) -> Vec<u8> {
    if color {
        let (r, g, b) = path_color(color_seed);
        format!("\x1b[38;2;{r};{g};{b}m[{label}]\x1b[0m ").into_bytes()
    } else {
        format!("[{label}] ").into_bytes()
    }
}

// ----------------------------------------------------------------------
// glob: handrolled matcher supporting `*`, `?`, and `**` (recursive
// segment). good enough for funnel: anchored full-path match plus label
// extraction (the substring of the path filled in by wildcards).

#[derive(Debug, Clone)]
pub struct Glob {
    segs: Vec<Seg>,
    // byte lengths of the leading / trailing literal regions of the
    // pattern, used by label() to strip fixed prefix/suffix from a path.
    lit_prefix_len: usize,
    lit_suffix_len: usize,
}

#[derive(Debug, Clone)]
enum Seg {
    DoubleStar,
    Parts(Vec<Part>),
}

#[derive(Debug, Clone)]
enum Part {
    Lit(String),
    Star,
    Question,
}

// known tokens for the `--allow=` polyflag. each toggles a class of
// glob pattern that's rejected by default for being hard-to-reason-about.
pub const ALLOW_TOKENS: &[KnownToken] = &[
    token!("multi-doublestar"),
    token!("mixed-doublestar"),
    token!("classes"),
    token!("bare-wild"),
    token!("trailing-doublestar"),
    token!("interleaved"),
];

impl Glob {
    pub fn compile(pattern: &str) -> Result<Self, String> {
        Self::compile_with(pattern, &HashSet::new())
    }

    pub fn compile_with(
        pattern: &str,
        allow: &HashSet<&'static str>,
    ) -> Result<Self, String> {
        // char classes / brace alternation: not implemented in the matcher
        // and `literal_prefix_len` treats `[`/`{` as wildcards, so a quiet
        // mismatch would silently misbehave. reject unless opted in.
        if !allow.contains("classes") && pattern.contains(['[', ']', '{', '}']) {
            return Err(
                "char classes / brace alternation not supported; pass --allow=classes to enable"
                    .into(),
            );
        }
        // mixed-doublestar: a segment contains `**` substring but isn't
        // exactly `**`. ambiguous semantics across glob implementations.
        if !allow.contains("mixed-doublestar") {
            for seg in pattern.split('/') {
                if seg != "**" && seg.contains("**") {
                    return Err(format!(
                        "`**` mixed with other chars in segment `{seg}`; \
                         pass --allow=mixed-doublestar to enable"
                    ));
                }
            }
        }
        // bare-wild: a wildcard in the first non-empty segment. label
        // would drag the whole leading dir tree; usually not what you want.
        if !allow.contains("bare-wild") {
            for seg in pattern.split('/') {
                if seg.is_empty() {
                    continue;
                }
                if seg.contains(['*', '?']) {
                    return Err(
                        "wildcard in first path segment; pass --allow=bare-wild to enable"
                            .into(),
                    );
                }
                break;
            }
        }

        let segs = parse_segs(pattern);

        // multi-doublestar: more than one `**` segment. label cannot tell
        // which `**` filled which path region.
        if !allow.contains("multi-doublestar") {
            let n = segs.iter().filter(|s| matches!(s, Seg::DoubleStar)).count();
            if n > 1 {
                return Err(
                    "multiple `**` segments make labels ambiguous; \
                     pass --allow=multi-doublestar to enable"
                        .into(),
                );
            }
        }
        // trailing-doublestar: pattern ends in `**`. matches everything
        // recursively w/ no filename constraint; very spammy.
        if !allow.contains("trailing-doublestar")
            && matches!(segs.last(), Some(Seg::DoubleStar))
        {
            return Err(
                "trailing `**` matches anything recursively; \
                 pass --allow=trailing-doublestar to enable"
                    .into(),
            );
        }
        // interleaved: a single segment has more than one wildcard part
        // (e.g. `log-*-prod-*.txt`). label contains the middle literal,
        // reads weird.
        if !allow.contains("interleaved") {
            for seg in &segs {
                if let Seg::Parts(parts) = seg {
                    let wild = parts
                        .iter()
                        .filter(|p| matches!(p, Part::Star | Part::Question))
                        .count();
                    if wild > 1 {
                        return Err(
                            "multiple wildcards in a single segment make labels ambiguous; \
                             pass --allow=interleaved to enable"
                                .into(),
                        );
                    }
                }
            }
        }

        let lit_prefix_len = literal_prefix_len(pattern);
        let lit_suffix_len = literal_suffix_len(pattern);
        Ok(Glob {
            segs,
            lit_prefix_len,
            lit_suffix_len,
        })
    }

    pub fn is_match(&self, path: &str) -> bool {
        let path_segs: Vec<&str> = path.split('/').collect();
        match_segs(&self.segs, &path_segs)
    }

    pub fn is_match_path(&self, path: &Path) -> bool {
        self.is_match(&path.to_string_lossy())
    }

    // label: substring of path filled in by wildcards. derived by stripping
    // the literal prefix and literal suffix of the pattern from the path.
    pub fn label(&self, path: &str) -> String {
        let len = path.len();
        let start = self.lit_prefix_len.min(len);
        let end = len.saturating_sub(self.lit_suffix_len).max(start);
        path[start..end].to_string()
    }
}

fn parse_segs(pat: &str) -> Vec<Seg> {
    let mut out = Vec::new();
    for seg in pat.split('/') {
        if seg == "**" {
            out.push(Seg::DoubleStar);
            continue;
        }
        let mut parts = Vec::new();
        let mut lit = String::new();
        for ch in seg.chars() {
            match ch {
                '*' => {
                    if !lit.is_empty() {
                        parts.push(Part::Lit(std::mem::take(&mut lit)));
                    }
                    parts.push(Part::Star);
                }
                '?' => {
                    if !lit.is_empty() {
                        parts.push(Part::Lit(std::mem::take(&mut lit)));
                    }
                    parts.push(Part::Question);
                }
                c => lit.push(c),
            }
        }
        if !lit.is_empty() {
            parts.push(Part::Lit(lit));
        }
        out.push(Seg::Parts(parts));
    }
    out
}

fn literal_prefix_len(pat: &str) -> usize {
    pat.find(['*', '?', '[', '{']).unwrap_or(pat.len())
}

fn literal_suffix_len(pat: &str) -> usize {
    match pat.rfind(['*', '?', ']', '}']) {
        Some(i) => pat.len() - i - 1,
        None => 0,
    }
}

fn match_segs(pat: &[Seg], path: &[&str]) -> bool {
    if pat.is_empty() {
        return path.is_empty();
    }
    match &pat[0] {
        Seg::DoubleStar => {
            // `**` matches zero or more path segments.
            for i in 0..=path.len() {
                if match_segs(&pat[1..], &path[i..]) {
                    return true;
                }
            }
            false
        }
        Seg::Parts(parts) => {
            if path.is_empty() {
                return false;
            }
            if match_parts(parts, path[0]) {
                match_segs(&pat[1..], &path[1..])
            } else {
                false
            }
        }
    }
}

fn match_parts(parts: &[Part], s: &str) -> bool {
    if parts.is_empty() {
        return s.is_empty();
    }
    match &parts[0] {
        Part::Lit(l) => {
            if s.starts_with(l.as_str()) {
                match_parts(&parts[1..], &s[l.len()..])
            } else {
                false
            }
        }
        Part::Star => {
            for i in 0..=s.len() {
                if !s.is_char_boundary(i) {
                    continue;
                }
                if match_parts(&parts[1..], &s[i..]) {
                    return true;
                }
            }
            false
        }
        Part::Question => {
            let mut iter = s.char_indices();
            if iter.next().is_some() {
                let next = iter.next().map(|(i, _)| i).unwrap_or(s.len());
                match_parts(&parts[1..], &s[next..])
            } else {
                false
            }
        }
    }
}

// walk: recursively visit regular files under `dir`, calling `cb` with each
// file path. recurses into subdirs only when `recursive`. `on_err` is called
// with (path, err) for dirs that can't be read; pass a no-op closure to ignore.
pub fn walk(
    dir: &Path,
    recursive: bool,
    cb: &mut dyn FnMut(&Path),
    on_err: &mut dyn FnMut(&Path, &dyn std::fmt::Display),
) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            on_err(dir, &e);
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
                walk(&path, recursive, cb, on_err);
            }
        } else if ft.is_file() {
            cb(&path);
        }
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
        let p = build_prefix("foo", Path::new("/tmp/foo.log"), false);
        assert_eq!(p, b"[foo] ");
    }

    #[test]
    fn prefix_with_color() {
        let p = build_prefix("foo", Path::new("/tmp/foo.log"), true);
        let s = String::from_utf8(p).unwrap();
        assert!(s.starts_with("\x1b[38;2;"));
        assert!(s.contains("[foo]"));
        assert!(s.ends_with("\x1b[0m "));
    }

    // glob tests --------------------------------------------------------

    #[test]
    fn glob_match_star_segment() {
        let g = Glob::compile("/tmp/claude/log/*.log").unwrap();
        assert!(g.is_match("/tmp/claude/log/mylog.log"));
        assert!(g.is_match("/tmp/claude/log/a.log"));
        assert!(!g.is_match("/tmp/claude/log/nested/x.log"));
        assert!(!g.is_match("/tmp/claude/log/mylog.txt"));
        assert!(!g.is_match("/tmp/claude/other/mylog.log"));
    }

    #[test]
    fn glob_match_double_star() {
        let g = Glob::compile("/tmp/**/*.log").unwrap();
        assert!(g.is_match("/tmp/claude/log/mylog.log"));
        assert!(g.is_match("/tmp/foo/other_log.log"));
        assert!(g.is_match("/tmp/a/b/c/d.log"));
        // `**` matches zero segments too, so this also matches.
        assert!(g.is_match("/tmp/mylog.log"));
        assert!(!g.is_match("/other/x.log"));
    }

    #[test]
    fn glob_match_question() {
        let g = Glob::compile("/tmp/?.log").unwrap();
        assert!(g.is_match("/tmp/a.log"));
        assert!(g.is_match("/tmp/Z.log"));
        assert!(!g.is_match("/tmp/ab.log"));
    }

    #[test]
    fn glob_match_literal_only() {
        let g = Glob::compile("/tmp/foo.log").unwrap();
        assert!(g.is_match("/tmp/foo.log"));
        assert!(!g.is_match("/tmp/foo2.log"));
    }

    #[test]
    fn glob_label_single_star() {
        let g = Glob::compile("/tmp/claude/log/*.log").unwrap();
        assert_eq!(g.label("/tmp/claude/log/mylog.log"), "mylog");
    }

    #[test]
    fn glob_label_double_star() {
        let g = Glob::compile("/tmp/**/*.log").unwrap();
        assert_eq!(g.label("/tmp/claude/log/mylog.log"), "claude/log/mylog");
        assert_eq!(g.label("/tmp/foo/other_log.log"), "foo/other_log");
    }

    #[test]
    fn glob_label_no_suffix() {
        let g = Glob::compile("/tmp/*").unwrap();
        assert_eq!(g.label("/tmp/foo"), "foo");
        assert_eq!(g.label("/tmp/foo.log"), "foo.log");
    }

    #[test]
    fn glob_label_no_wildcards() {
        let g = Glob::compile("/tmp/foo.log").unwrap();
        assert_eq!(g.label("/tmp/foo.log"), "");
    }

    // glob validation -------------------------------------------------

    fn allow(tokens: &[&'static str]) -> HashSet<&'static str> {
        tokens.iter().copied().collect()
    }

    #[test]
    fn reject_multi_doublestar() {
        assert!(Glob::compile("/tmp/**/foo/**/*.log").is_err());
        assert!(
            Glob::compile_with("/tmp/**/foo/**/*.log", &allow(&["multi-doublestar"])).is_ok()
        );
    }

    #[test]
    fn reject_mixed_doublestar() {
        assert!(Glob::compile("/tmp/a**b/x.log").is_err());
        assert!(
            Glob::compile_with("/tmp/a**b/x.log", &allow(&["mixed-doublestar", "interleaved"]))
                .is_ok()
        );
    }

    #[test]
    fn reject_char_classes() {
        assert!(Glob::compile("/tmp/[ab].log").is_err());
        assert!(Glob::compile("/tmp/{a,b}.log").is_err());
        assert!(Glob::compile_with("/tmp/[ab].log", &allow(&["classes"])).is_ok());
    }

    #[test]
    fn reject_bare_wild() {
        assert!(Glob::compile("*/*.log").is_err());
        assert!(Glob::compile("*.log").is_err());
        assert!(Glob::compile_with("*.log", &allow(&["bare-wild"])).is_ok());
    }

    #[test]
    fn reject_trailing_doublestar() {
        assert!(Glob::compile("/tmp/**").is_err());
        assert!(Glob::compile_with("/tmp/**", &allow(&["trailing-doublestar"])).is_ok());
    }

    #[test]
    fn reject_interleaved() {
        assert!(Glob::compile("/tmp/log-*-prod-*.txt").is_err());
        assert!(
            Glob::compile_with("/tmp/log-*-prod-*.txt", &allow(&["interleaved"])).is_ok()
        );
    }

    #[test]
    fn allow_no_wildcards() {
        // #4 from the original list -- intentionally not gated.
        assert!(Glob::compile("/tmp/foo.log").is_ok());
    }

    #[test]
    fn glob_unicode_path() {
        let g = Glob::compile("/tmp/*.log").unwrap();
        assert!(g.is_match("/tmp/caf\u{00e9}.log"));
        assert_eq!(g.label("/tmp/caf\u{00e9}.log"), "caf\u{00e9}");
    }
}
