use std::path::Path;

use criterion::{Criterion, criterion_group, criterion_main};
use funnel::{build_prefix, fnv1a, path_color, watch_root};

fn bench_fnv1a(c: &mut Criterion) {
    let short = b"foo.log";
    let medium = b"/tmp/claude/log/session-2026-05-18/agent-42.log";
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
    let medium = Path::new("/tmp/claude/log/agent-42.log");
    // crafted path that hashes to a dark color, forcing the luma-bump loop:
    // we don't actually know which path hits worst-case, so just sweep some.
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
    let path = Path::new("/tmp/claude/log/agent-42.log");
    c.bench_function("build_prefix/no_color", |b| {
        b.iter(|| build_prefix(std::hint::black_box(path), false))
    });
    c.bench_function("build_prefix/color", |b| {
        b.iter(|| build_prefix(std::hint::black_box(path), true))
    });
}

fn bench_watch_root(c: &mut Criterion) {
    c.bench_function("watch_root/simple", |b| {
        b.iter(|| watch_root(std::hint::black_box("/tmp/claude/log/*.log")))
    });
    c.bench_function("watch_root/recursive", |b| {
        b.iter(|| watch_root(std::hint::black_box("/tmp/claude/log/**/*.log")))
    });
}

criterion_group!(
    benches,
    bench_fnv1a,
    bench_path_color,
    bench_build_prefix,
    bench_watch_root
);
criterion_main!(benches);
