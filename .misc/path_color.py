#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "matplotlib",
# ]
# ///
"""Stable per-path ANSI truecolor labels, blended from a palette.

Each palette color sits on a vertex of an (N-1)-simplex. The path is hashed
to N Dirichlet(1)-style barycentric weights, picking a coordinate inside
the simplex. The blend is done in YCbCr (BT.601) for perceptually smoother
mixes; only input palette and final output are in RGB.

Default palette: gruvbox dark (normal-bright mix).

Usage:
    ./path_color.py [PATH ...]        # terminal demo
    ./path_color.py --plot            # matplotlib swatch grid
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

FNV_OFFSET = 0x811C9DC5
FNV_PRIME = 0x01000193
MASK32 = 0xFFFFFFFF

def _hex(*codes: str) -> list[tuple[int, int, int]]:
    return [(int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)) for c in codes]


# popular terminal/editor palettes, accent colors only (no bg/fg).
PALETTES: dict[str, list[tuple[int, int, int]]] = {
    "gruvbox": _hex(
        "cc241d",  # red
        "98971a",  # green
        "d79921",  # yellow
        "458588",  # blue
        "b16286",  # purple
        "689d6a",  # aqua
        "d65d03",  # orange
    ),
    "solarized": _hex(
        "dc322f",  # red
        "859900",  # green
        "b58900",  # yellow
        "268bd2",  # blue
        "d33682",  # magenta
        "2aa198",  # cyan
        "cb4b16",  # orange
        "6c71c4",  # violet
    ),
    "nord": _hex(
        "bf616a",  # red
        "a3be8c",  # green
        "ebcb8b",  # yellow
        "5e81ac",  # blue
        "b48ead",  # purple
        "88c0d0",  # cyan
        "d08770",  # orange
    ),
    "catppuccin": _hex(  # mocha
        "f38ba8",  # pink
        "a6e3a1",  # green
        "f9e2af",  # yellow
        "89b4fa",  # blue
        "cba6f7",  # mauve
        "94e2d5",  # teal
        "fab387",  # peach
        "f5c2e7",  # rosewater
    ),
    "dracula": _hex(
        "ff5555",  # red
        "50fa7b",  # green
        "f1fa8c",  # yellow
        "bd93f9",  # purple
        "ff79c6",  # pink
        "8be9fd",  # cyan
        "ffb86c",  # orange
    ),
    "tokyonight": _hex(
        "f7768e",  # red
        "9ece6a",  # green
        "e0af68",  # yellow
        "7aa2f7",  # blue
        "bb9af7",  # magenta
        "7dcfff",  # cyan
        "ff9e64",  # orange
    ),
    "monokai": _hex(
        "f92672",  # pink
        "a6e22e",  # green
        "e6db74",  # yellow
        "66d9ef",  # blue
        "ae81ff",  # purple
        "fd971f",  # orange
    ),
}

GRUVBOX = PALETTES["gruvbox"]  # back-compat default


def fnv1a(data: bytes) -> int:
    h = FNV_OFFSET
    for b in data:
        h ^= b
        h = (h * FNV_PRIME) & MASK32
    return h


def rgb_to_ycbcr(r: float, g: float, b: float) -> tuple[float, float, float]:
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = -0.168736 * r - 0.331264 * g + 0.5 * b + 128.0
    cr = 0.5 * r - 0.418688 * g - 0.081312 * b + 128.0
    return y, cb, cr


def ycbcr_to_rgb(y: float, cb: float, cr: float) -> tuple[int, int, int]:
    cb -= 128.0
    cr -= 128.0
    r = y + 1.402 * cr
    g = y - 0.344136 * cb - 0.714136 * cr
    b = y + 1.772 * cb
    return (
        max(0, min(255, round(r))),
        max(0, min(255, round(g))),
        max(0, min(255, round(b))),
    )


SHARPNESS = 2.0  # >1 pushes mass toward vertices, <1 toward centroid
SEED = b""       # global rng salt; empty = original palette ordering


def seeded_permutation(palette: list[tuple[int, int, int]], salt: bytes) -> list[tuple[int, int, int]]:
    """Deterministic Fisher-Yates shuffle keyed by salt; empty salt = identity."""
    items = list(palette)
    if not salt:
        return items
    for i in range(len(items) - 1, 0, -1):
        h = fnv1a(salt + b":perm:" + str(i).encode())
        j = h % (i + 1)
        items[i], items[j] = items[j], items[i]
    return items


def barycentric(
    seed: bytes,
    n: int,
    sharpness: float | None = None,
) -> list[float]:
    """N hash-derived weights on the simplex.

    Sample uniform Dirichlet(1) via -log(uniform), normalize, then sharpen
    by raising to `sharpness` and renormalizing. Without sharpening, the
    blend of many vertices collapses to the palette centroid; sharpening
    biases each path toward 1-2 dominant palette colors while keeping it
    a proper N-way blend.
    """
    if sharpness is None:
        sharpness = SHARPNESS
    raw = []
    for i in range(n):
        # index goes first so FNV-1a's multiplicative chain avalanches it
        # across all subsequent bytes; appending the index gives near-
        # identical hashes for different i and collapses the blend.
        h = fnv1a(str(i).encode() + b":" + seed)
        u = (h + 1) / (MASK32 + 1)  # (0, 1]
        raw.append(-math.log(u))
    total = sum(raw)
    w = [r / total for r in raw]
    w = [wi ** sharpness for wi in w]
    total = sum(w)
    return [wi / total for wi in w]


def path_color(
    path: str | Path,
    palette: list[tuple[int, int, int]] | None = None,
) -> tuple[int, int, int]:
    if palette is None:
        palette = seeded_permutation(GRUVBOX, SEED)
    seed = str(path).encode("utf-8", "replace")
    w = barycentric(seed, len(palette))
    palette_ycc = [rgb_to_ycbcr(*c) for c in palette]
    y = sum(wi * yi for wi, (yi, _, _) in zip(w, palette_ycc))
    cb = sum(wi * cbi for wi, (_, cbi, _) in zip(w, palette_ycc))
    cr = sum(wi * cri for wi, (_, _, cri) in zip(w, palette_ycc))
    return ycbcr_to_rgb(y, cb, cr)


def colorize(label: str, seed: str | Path, palette=None) -> str:
    r, g, b = path_color(seed, palette)
    return f"\x1b[38;2;{r};{g};{b}m[{label}]\x1b[0m"


SAMPLE_PATHS = [
    "src/main.rs",
    "src/lib.rs",
    "src/parser/lexer.rs",
    "src/parser/ast.rs",
    "src/parser/token.rs",
    "src/runtime/scheduler.rs",
    "src/runtime/executor.rs",
    "src/runtime/waker.rs",
    "src/net/tcp.rs",
    "src/net/udp.rs",
    "src/net/dns.rs",
    "src/io/buf.rs",
    "src/io/reader.rs",
    "src/io/writer.rs",
    "tests/integration.rs",
    "tests/parser_test.rs",
    "tests/runtime_test.rs",
    "benches/throughput.rs",
    "benches/latency.rs",
    "examples/echo.rs",
    "examples/proxy.rs",
    "examples/chat.rs",
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "Cargo.toml",
    "Cargo.lock",
    ".gitignore",
    "/var/log/syslog",
    "/var/log/auth.log",
    "/var/log/kern.log",
    "/var/log/nginx/access.log",
    "/var/log/nginx/error.log",
    "/tmp/scratch.txt",
    "/tmp/build.log",
    "/etc/hosts",
]


BG = "#1d2021"   # near-black for figure bg
FG = "#ebdbb2"   # warm off-white for titles


def _draw_palette_block(
    fig, gs_slot, name: str, palette: list[tuple[int, int, int]], paths: list[str], cols: int,
) -> None:
    from matplotlib.gridspec import GridSpecFromSubplotSpec
    from matplotlib.patches import Rectangle

    palette = seeded_permutation(palette, SEED)
    n_pal = len(palette)
    n_samp = len(paths)
    rows = (n_samp + cols - 1) // cols

    inner = GridSpecFromSubplotSpec(
        2, 1, subplot_spec=gs_slot, height_ratios=[1, rows], hspace=0.15,
    )
    ax_pal = fig.add_subplot(inner[0])
    ax_samp = fig.add_subplot(inner[1])

    ax_pal.set_xlim(0, n_pal)
    ax_pal.set_ylim(0, 1)
    ax_pal.set_facecolor(BG)
    for i, (r, g, b) in enumerate(palette):
        ax_pal.add_patch(Rectangle((i, 0), 1, 1, color=(r / 255, g / 255, b / 255)))
        ax_pal.text(
            i + 0.5, 0.5, f"#{r:02x}{g:02x}{b:02x}",
            ha="center", va="center", color=BG,
            fontsize=8, fontweight="bold", family="monospace",
        )
    ax_pal.set_title(f"{name}  (N={n_pal})", color=FG, fontsize=11, loc="left")
    ax_pal.set_xticks([])
    ax_pal.set_yticks([])

    ax_samp.set_xlim(0, cols)
    ax_samp.set_ylim(0, rows)
    ax_samp.invert_yaxis()
    ax_samp.set_facecolor(BG)
    for idx, p in enumerate(paths):
        col = idx % cols
        row = idx // cols
        r, g, b = path_color(p, palette)
        ax_samp.add_patch(Rectangle((col, row), 1, 1, color=(r / 255, g / 255, b / 255)))
        luma = (2126 * r + 7152 * g + 722 * b) / 10000 / 255
        txt = BG if luma > 0.5 else FG
        ax_samp.text(
            col + 0.5, row + 0.5, p,
            ha="center", va="center", color=txt,
            fontsize=7, family="monospace",
        )
    ax_samp.set_xticks([])
    ax_samp.set_yticks([])


def plot_samples(
    paths: list[str],
    out: str = "path_color_demo.png",
    cols: int = 4,
    palettes: list[str] | None = None,
) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.gridspec import GridSpec

    names = palettes or list(PALETTES.keys())
    n_samp = len(paths)
    grid_rows = (n_samp + cols - 1) // cols

    # square-ish grid of palette blocks: ceil(sqrt(N)) columns
    block_cols = math.ceil(math.sqrt(len(names)))
    block_rows = math.ceil(len(names) / block_cols)

    block_w = 8.0
    block_h = 1.0 + grid_rows * 0.55
    fig = plt.figure(figsize=(block_w * block_cols, block_h * block_rows + 0.5))
    fig.patch.set_facecolor(BG)
    gs = GridSpec(block_rows, block_cols, figure=fig, hspace=0.5, wspace=0.15)

    for i, name in enumerate(names):
        r, c = divmod(i, block_cols)
        _draw_palette_block(fig, gs[r, c], name, PALETTES[name], paths, cols)

    plt.savefig(out, dpi=120, facecolor=fig.get_facecolor())
    print(f"wrote {out}")


def print_terminal(paths: list[str], palette_name: str) -> None:
    palette = seeded_permutation(PALETTES[palette_name], SEED)
    width = max(len(p) for p in paths)
    print(f"palette ({palette_name} vertices):")
    for r, g, b in palette:
        swatch = f"\x1b[38;2;{r};{g};{b}m##\x1b[0m"
        print(f"  {swatch} rgb({r:3d},{g:3d},{b:3d})")
    print()
    for p in paths:
        r, g, b = path_color(p, palette)
        print(f"{colorize(p, p, palette):<{width + 20}}  rgb({r:3d},{g:3d},{b:3d})")


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="path_color",
        description="Stable per-path ANSI truecolor labels via simplex blend over a palette.",
    )
    p.add_argument(
        "paths",
        nargs="*",
        help="paths to colorize (default: built-in sample list)",
    )
    p.add_argument(
        "--plot",
        action="store_true",
        help="render matplotlib swatch grid instead of printing to terminal",
    )
    p.add_argument(
        "-o", "--output",
        default="path_color_demo.png",
        help="output filename for --plot (default: %(default)s)",
    )
    p.add_argument(
        "-s", "--sharpness",
        type=float,
        default=SHARPNESS,
        help="weight exponent; >1 pushes toward vertices, <1 toward centroid (default: %(default)s)",
    )
    p.add_argument(
        "--cols",
        type=int,
        default=4,
        help="number of columns in --plot grid (default: %(default)s)",
    )
    p.add_argument(
        "-p", "--palette",
        choices=list(PALETTES.keys()),
        default="gruvbox",
        help="palette for terminal output (default: %(default)s); --plot shows all",
    )
    p.add_argument(
        "--only",
        nargs="+",
        choices=list(PALETTES.keys()),
        help="restrict --plot to these palettes",
    )
    p.add_argument(
        "--seed",
        default="",
        help="rng salt to explore alternate arrangements; empty = default",
    )
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv[1:])

    global SHARPNESS, SEED
    SHARPNESS = args.sharpness
    SEED = args.seed.encode("utf-8") if args.seed else b""

    paths = args.paths or (SAMPLE_PATHS if args.plot else SAMPLE_PATHS[:8])
    if args.plot:
        plot_samples(paths, out=args.output, cols=args.cols, palettes=args.only)
    else:
        print_terminal(paths, args.palette)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
