use std::path::Path;

use criterion::{Criterion, criterion_group, criterion_main};
use funnel::{Glob, build_prefix, fnv1a, path_color, watch_root};

fn bench_fnv1a(c: &mut Criterion) {
    let short = b"foo.log";
    let medium = b"/tmp/ai/log/session-2026-05-18/agent-42.log";
    let long: Vec<u8> = (0..1024).map(|i| (i % 256) as u8).collect();

    c.bench_function("fnv1a/short", |b| {
        b.iter(|| fnv1a(std::hint::black_box(short)))
    });
    c.bench_function("fnv1a/medium", |b| {
        b.iter(|| fnv1a(std::hint::black_box(medium)))
    });
    c.bench_function("fnv1a/1KB", |b| {
        b.iter(|| fnv1a(std::hint::black_box(&long)))
    });
}

fn bench_path_color(c: &mut Criterion) {
    let short = Path::new("a.log");
    let medium = Path::new("/tmp/ai/log/agent-42.log");
    let many: Vec<_> = (0..16)
        .map(|i| format!("/tmp/funnel/bench-{i}.log"))
        .collect();

    c.bench_function("path_color/short", |b| {
        b.iter(|| path_color(std::hint::black_box(short)))
    });
    c.bench_function("path_color/medium", |b| {
        b.iter(|| path_color(std::hint::black_box(medium)))
    });
    c.bench_function("path_color/sweep_16", |b| {
        b.iter(|| {
            for p in &many {
                std::hint::black_box(path_color(Path::new(p)));
            }
        })
    });
}

fn bench_build_prefix(c: &mut Criterion) {
    let path = Path::new("/tmp/ai/log/agent-42.log");
    c.bench_function("build_prefix/no_color", |b| {
        b.iter(|| {
            build_prefix(
                std::hint::black_box("agent-42"),
                std::hint::black_box(path),
                false,
            )
        })
    });
    c.bench_function("build_prefix/color", |b| {
        b.iter(|| {
            build_prefix(
                std::hint::black_box("agent-42"),
                std::hint::black_box(path),
                true,
            )
        })
    });
}

fn bench_watch_root(c: &mut Criterion) {
    c.bench_function("watch_root/simple", |b| {
        b.iter(|| watch_root(std::hint::black_box("/tmp/ai/log/*.log")))
    });
    c.bench_function("watch_root/recursive", |b| {
        b.iter(|| watch_root(std::hint::black_box("/tmp/ai/log/**/*.log")))
    });
}

fn bench_glob_compile(c: &mut Criterion) {
    c.bench_function("glob_compile/simple", |b| {
        b.iter(|| Glob::compile(std::hint::black_box("/tmp/ai/log/*.log")))
    });
    c.bench_function("glob_compile/recursive", |b| {
        b.iter(|| Glob::compile(std::hint::black_box("/tmp/**/*.log")))
    });
}

fn bench_glob_match(c: &mut Criterion) {
    let simple = Glob::compile("/tmp/ai/log/*.log").unwrap();
    let recursive = Glob::compile("/tmp/**/*.log").unwrap();
    let path_hit = "/tmp/ai/log/agent-42.log";
    let path_deep = "/tmp/a/b/c/d/e/f/g/h/i/agent-42.log";
    let path_miss = "/tmp/ai/other/agent-42.txt";

    c.bench_function("glob_match/simple_hit", |b| {
        b.iter(|| simple.is_match(std::hint::black_box(path_hit)))
    });
    c.bench_function("glob_match/simple_miss", |b| {
        b.iter(|| simple.is_match(std::hint::black_box(path_miss)))
    });
    c.bench_function("glob_match/recursive_shallow", |b| {
        b.iter(|| recursive.is_match(std::hint::black_box(path_hit)))
    });
    c.bench_function("glob_match/recursive_deep", |b| {
        b.iter(|| recursive.is_match(std::hint::black_box(path_deep)))
    });
}

fn bench_glob_label(c: &mut Criterion) {
    let simple = Glob::compile("/tmp/ai/log/*.log").unwrap();
    let recursive = Glob::compile("/tmp/**/*.log").unwrap();
    let path_simple = "/tmp/ai/log/agent-42.log";
    let path_deep = "/tmp/a/b/c/d/e/f/g/h/i/agent-42.log";

    c.bench_function("glob_label/simple", |b| {
        b.iter(|| simple.label(std::hint::black_box(path_simple)))
    });
    c.bench_function("glob_label/recursive_deep", |b| {
        b.iter(|| recursive.label(std::hint::black_box(path_deep)))
    });
}

criterion_group!(
    benches,
    bench_fnv1a,
    bench_path_color,
    bench_build_prefix,
    bench_watch_root,
    bench_glob_compile,
    bench_glob_match,
    bench_glob_label,
);
criterion_main!(benches);
