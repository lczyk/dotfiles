// mosaic displays every image matching a glob in a scrollable thumbnail
// grid. like funnel, it watches the filesystem: new matches appear, deleted
// ones vanish, and modified files re-decode -- the grid stays live. glob
// matching, dir walking and the `--allow` token guards are reused from the
// funnel lib.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime};

use eframe::egui;
use funnel::{ALLOW_TOKENS, Glob, walk, watch_root};
use notify::{RecursiveMode, Watcher};

// thumbnails are decoded to a fixed pixel box and displayed scaled, so zoom
// only re-lays-out -- it never re-decodes.
const THUMB_PX: u32 = 256;
// single mode decodes its one image to the window's physical pixel size so it
// isn't upscaled. clamp that to a sane ceiling to bound texture size / decode
// cost on huge windows or hidpi displays.
const SINGLE_MAX_PX: u32 = 8192;
// quantise the single-mode decode box to this step so a slow drag-resize doesn't
// re-decode on every pixel -- only when it crosses a step boundary.
const SINGLE_STEP_PX: u32 = 256;
const N_WORKERS: usize = 4;

const HELP: &str = r#"Usage: mosaic <glob> [OPTIONS]

Display every image matching <glob> in a scrollable thumbnail grid. Watches
the filesystem live: new matches appear, deleted ones vanish, modified files
re-decode.

Examples:
  mosaic '~/pics/*.png'
  mosaic '~/shots/**/*.jpg'

Options:
  -h, --help              Print help information
  -v, --version           Print version information
  -c, --cols=<n>          Fixed number of columns (default: auto-fit to width)
  -s, --size=<px>         Thumbnail display size in px (default: 192).
                          Also adjustable live with +/- / scroll.
  -m, --mode=<mode>       View mode: grid (default), single. `single` shows
                          only the newest matching image, maximised to the
                          window (aspect-fit), and updates live as new
                          matches land.
      --sort=<key>        Sort order: name (default), mtime, size
      --allow=<tokens>    Opt in to hard-to-reason-about glob shapes.
                          Comma-separated, repeatable. Use `-name` to remove.
                          Tokens:
                            multi-doublestar     >1 `**` segment
                            mixed-doublestar     `**` mixed w/ other chars
                            classes              `[abc]` / `{a,b}`
                            bare-wild            wildcard in first segment
                            trailing-doublestar  pattern ends in `**`
                            interleaved          >1 wildcard in one segment
                          Also honors $MOSAIC_ALLOW.
"#;

#[derive(Clone, Copy, PartialEq)]
enum Sort {
    Name,
    Mtime,
    Size,
}

// grid: the scrollable thumbnail grid. single: just the newest matching image,
// blown up to fill the window (aspect-fit), refreshed live as matches change.
#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Grid,
    Single,
}

struct Args {
    pattern: String,
    cols: Option<usize>,
    size: f32,
    sort: Sort,
    mode: Mode,
    allow_values: Vec<String>,
}

fn die(msg: &str) -> ! {
    eprintln!("mosaic: {msg}");
    eprint!("{HELP}");
    std::process::exit(2);
}

fn parse_args(argv: &[String]) -> Args {
    let mut pattern: Option<String> = None;
    let mut cols: Option<usize> = None;
    let mut size: f32 = 192.0;
    let mut sort = Sort::Name;
    let mut mode = Mode::Grid;
    let mut allow_values: Vec<String> = Vec::new();

    let mut i = 1;
    while i < argv.len() {
        let arg = argv[i].as_str();
        // pull the value for `--flag=val` or `--flag val` / `-f val` forms.
        let split_value = |key: &str| -> Option<String> {
            if let Some(v) = arg.strip_prefix(key).and_then(|r| r.strip_prefix('=')) {
                return Some(v.to_string());
            }
            None
        };
        let take_next = |i: &mut usize| -> String {
            *i += 1;
            match argv.get(*i) {
                Some(v) => v.clone(),
                None => die(&format!("{arg} requires a value")),
            }
        };

        match arg {
            "-v" | "--version" => {
                println!("mosaic {}", version::version!());
                std::process::exit(0);
            }
            "-h" | "--help" => {
                print!("{HELP}");
                std::process::exit(0);
            }
            "-c" | "--cols" => cols = Some(parse_cols(&take_next(&mut i))),
            "-s" | "--size" => size = parse_size(&take_next(&mut i)),
            _ if split_value("--cols").is_some() => {
                cols = Some(parse_cols(&split_value("--cols").unwrap()))
            }
            _ if split_value("--size").is_some() => {
                size = parse_size(&split_value("--size").unwrap())
            }
            _ if split_value("--sort").is_some() => {
                sort = parse_sort(&split_value("--sort").unwrap())
            }
            "--sort" => sort = parse_sort(&take_next(&mut i)),
            "-m" | "--mode" => mode = parse_mode(&take_next(&mut i)),
            _ if split_value("--mode").is_some() => {
                mode = parse_mode(&split_value("--mode").unwrap())
            }
            _ if split_value("--allow").is_some() => {
                allow_values.push(split_value("--allow").unwrap())
            }
            "--allow" => allow_values.push(take_next(&mut i)),
            s if s.starts_with('-') && s != "-" => die(&format!("unknown flag: {s}")),
            _ => {
                if pattern.is_some() {
                    die("more than one glob pattern given");
                }
                pattern = Some(arg.to_string());
            }
        }
        i += 1;
    }

    let Some(pattern) = pattern else {
        die("missing glob pattern");
    };
    Args {
        pattern,
        cols,
        size,
        sort,
        mode,
        allow_values,
    }
}

fn parse_cols(v: &str) -> usize {
    match v.parse::<usize>() {
        Ok(n) if n >= 1 => n,
        _ => die(&format!("invalid --cols value: {v}")),
    }
}

fn parse_size(v: &str) -> f32 {
    match v.parse::<f32>() {
        Ok(n) if n >= 16.0 => n,
        _ => die(&format!("invalid --size value: {v}")),
    }
}

fn parse_sort(v: &str) -> Sort {
    match v {
        "name" => Sort::Name,
        "mtime" => Sort::Mtime,
        "size" => Sort::Size,
        other => die(&format!("invalid --sort value: {other}")),
    }
}

fn parse_mode(v: &str) -> Mode {
    match v {
        "grid" => Mode::Grid,
        "single" => Mode::Single,
        other => die(&format!("invalid --mode value: {other}")),
    }
}

// expand a leading `~` to the home dir; leaves everything else untouched.
fn expand_tilde(pat: &str) -> String {
    if let Some(rest) = pat.strip_prefix("~/")
        && let Some(home) = std::env::var_os("HOME")
    {
        return format!("{}/{rest}", home.to_string_lossy());
    }
    pat.to_string()
}

// ----------------------------------------------------------------------
// decode workers: a fixed pool pulls paths off a shared queue, decodes +
// downscales to a THUMB_PX box, and ships the cpu-side rgba back to the ui
// thread (only the ui thread may touch the egui context to upload textures).

// a unit of work for a decode worker. the SystemTime is the source file's mtime
// at dispatch -- a generation token echoed back in the result so a decode of a
// since-overwritten file can be dropped instead of clobbering the live version.
enum Job {
    // decode just the first frame (fast) + detect whether it's a gif. the u32 is
    // the decode box: THUMB_PX for grid cells, the window's physical pixel size
    // for single mode (so the maximised image isn't upscaled / blurred).
    Thumb(PathBuf, SystemTime, u32),
    // decode every frame of a gif (on demand, when a gif is hovered).
    Frames(PathBuf, SystemTime),
}

struct DecodeResult {
    path: PathBuf,
    // the mtime the job was dispatched against; matched against the thumb's
    // current mtime to reject results for a stale version of the file.
    mtime: SystemTime,
    // the decode box this job was dispatched at (the `Thumb` job's u32). single
    // mode reads it back to know whether the result is already as detailed as
    // the source can give, vs capped and worth re-decoding bigger.
    box_px: u32,
    payload: Payload,
}

// `None` on decode failure.
enum Payload {
    Thumb(Option<ThumbData>),
    Frames(Option<FramesData>),
}

struct ThumbData {
    image: egui::ColorImage,
    swatch: Swatch,
    is_gif: bool,
}

struct FramesData {
    frames: Vec<egui::ColorImage>,
    delays: Vec<f32>, // seconds per frame
}

// per-image dominant colours, computed once at decode time. `bg` is the
// darker of the two dominant clusters, `fg` the lighter. drives the window
// tint (avg bg) + the hover glow colour.
#[derive(Clone, Copy)]
struct Swatch {
    fg: [u8; 3],
    bg: [u8; 3],
}

// only ever downscale. upscaling a small image here (thumbnail fits it to the
// box) would bake in interpolation blur that no sampler can undo; keep it at
// native res and let the grid pass upscale it crisply (nearest).
fn downscale_only(img: image::DynamicImage, max_px: u32) -> image::DynamicImage {
    if img.width() > max_px || img.height() > max_px {
        img.thumbnail(max_px, max_px)
    } else {
        img
    }
}

fn to_color_image(rgba: &image::RgbaImage) -> egui::ColorImage {
    let (w, h) = rgba.dimensions();
    egui::ColorImage::from_rgba_unmultiplied([w as usize, h as usize], rgba.as_raw())
}

// fast path: decode only the first frame + the colour swatch, and flag whether
// the file is a gif (so the grid can show a play badge / preload on hover).
fn decode_thumb(path: &Path, max_px: u32) -> Option<ThumbData> {
    let reader = image::ImageReader::open(path)
        .ok()?
        .with_guessed_format()
        .ok()?;
    let is_gif = reader.format() == Some(image::ImageFormat::Gif);
    let img = downscale_only(reader.decode().ok()?, max_px);
    let rgba = img.to_rgba8();
    let swatch = dominant_colors(&rgba);
    Some(ThumbData {
        image: to_color_image(&rgba),
        swatch,
        is_gif,
    })
}

// slow path: decode all gif frames + their delays. only run when a gif is
// actually hovered, so the initial grid load stays fast.
fn decode_gif_frames(path: &Path) -> Option<FramesData> {
    use image::AnimationDecoder as _;
    let file = std::fs::File::open(path).ok()?;
    let frames = image::codecs::gif::GifDecoder::new(std::io::BufReader::new(file))
        .ok()?
        .into_frames()
        .collect_frames()
        .ok()?;
    let mut imgs = Vec::with_capacity(frames.len());
    let mut delays = Vec::with_capacity(frames.len());
    for f in frames {
        let (num, den) = f.delay().numer_denom_ms();
        let ms = if den == 0 {
            100.0
        } else {
            num as f32 / den as f32
        };
        // clamp absurdly fast / zero delays to keep playback sane.
        delays.push(ms.max(20.0) / 1000.0);
        let rgba =
            downscale_only(image::DynamicImage::ImageRgba8(f.into_buffer()), THUMB_PX).to_rgba8();
        imgs.push(to_color_image(&rgba));
    }
    Some(FramesData {
        frames: imgs,
        delays,
    })
}

// which frame is showing at time `t` (seconds) into a looping animation.
fn frame_at(delays: &[f32], t: f32) -> usize {
    let total: f32 = delays.iter().sum();
    if total <= 0.0 {
        return 0;
    }
    let mut x = t.rem_euclid(total);
    for (i, d) in delays.iter().enumerate() {
        if x < *d {
            return i;
        }
        x -= d;
    }
    delays.len() - 1
}

// k-means dominant-colour extraction, ported from mojitos/knitting. samples
// the image down to ~64px on its long side, clusters into k=6 colours, keeps
// clusters with >=3% of the pixels, then picks the lightest and darkest by
// luminance as fg / bg.
fn dominant_colors(img: &image::RgbaImage) -> Swatch {
    const K: usize = 6;
    const ITERS: usize = 12;
    let (w, h) = img.dimensions();
    let step = (w.max(h) / 64).max(1);

    let mut pixels: Vec<[f32; 3]> = Vec::new();
    let mut y = 0;
    while y < h {
        let mut x = 0;
        while x < w {
            let p = img.get_pixel(x, y);
            if p[3] >= 128 {
                pixels.push([p[0] as f32, p[1] as f32, p[2] as f32]);
            }
            x += step;
        }
        y += step;
    }
    if pixels.is_empty() {
        return Swatch {
            fg: [235, 235, 235],
            bg: [18, 18, 18],
        };
    }

    let k = K.min(pixels.len());
    // deterministic init: evenly spaced pixels.
    let mut centroids: Vec<[f32; 3]> = (0..k).map(|i| pixels[i * pixels.len() / k]).collect();
    let mut assign = vec![0usize; pixels.len()];
    for _ in 0..ITERS {
        let mut changed = false;
        for (p, px) in pixels.iter().enumerate() {
            let mut best = 0;
            let mut best_d = f32::INFINITY;
            for (j, c) in centroids.iter().enumerate() {
                let d = (px[0] - c[0]).powi(2) + (px[1] - c[1]).powi(2) + (px[2] - c[2]).powi(2);
                if d < best_d {
                    best_d = d;
                    best = j;
                }
            }
            if assign[p] != best {
                assign[p] = best;
                changed = true;
            }
        }
        if !changed {
            break;
        }
        let mut sums = vec![[0f32; 4]; k];
        for (p, px) in pixels.iter().enumerate() {
            let s = &mut sums[assign[p]];
            s[0] += px[0];
            s[1] += px[1];
            s[2] += px[2];
            s[3] += 1.0;
        }
        for (j, c) in centroids.iter_mut().enumerate() {
            if sums[j][3] > 0.0 {
                c[0] = sums[j][0] / sums[j][3];
                c[1] = sums[j][1] / sums[j][3];
                c[2] = sums[j][2] / sums[j][3];
            }
        }
    }

    let mut counts = vec![0usize; k];
    for &a in &assign {
        counts[a] += 1;
    }
    let min_size = (pixels.len() as f32 * 0.03).max(1.0);
    let lum = |c: &[f32; 3]| 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
    let mut viable: Vec<[f32; 3]> = centroids
        .iter()
        .enumerate()
        .filter(|(i, _)| counts[*i] as f32 >= min_size)
        .map(|(_, c)| *c)
        .collect();
    if viable.is_empty() {
        viable = centroids;
    }
    viable.sort_by(|a, b| lum(a).total_cmp(&lum(b)));
    let to_u8 = |c: [f32; 3]| {
        [
            c[0].round().clamp(0.0, 255.0) as u8,
            c[1].round().clamp(0.0, 255.0) as u8,
            c[2].round().clamp(0.0, 255.0) as u8,
        ]
    };
    Swatch {
        bg: to_u8(viable[0]),
        fg: to_u8(viable[viable.len() - 1]),
    }
}

fn spawn_workers(ctx: egui::Context) -> (Sender<Job>, Receiver<DecodeResult>) {
    let (job_tx, job_rx) = mpsc::channel::<Job>();
    let (res_tx, res_rx) = mpsc::channel::<DecodeResult>();
    let job_rx = Arc::new(Mutex::new(job_rx));
    for _ in 0..N_WORKERS {
        let job_rx = Arc::clone(&job_rx);
        let res_tx = res_tx.clone();
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            loop {
                // hold the lock only across recv, not across the decode.
                let job = {
                    let guard = job_rx.lock().unwrap();
                    match guard.recv() {
                        Ok(j) => j,
                        Err(_) => return,
                    }
                };
                let result = match job {
                    Job::Thumb(path, mtime, max_px) => {
                        let payload = Payload::Thumb(decode_thumb(&path, max_px));
                        DecodeResult { path, mtime, box_px: max_px, payload }
                    }
                    Job::Frames(path, mtime) => {
                        let payload = Payload::Frames(decode_gif_frames(&path));
                        DecodeResult { path, mtime, box_px: 0, payload }
                    }
                };
                if res_tx.send(result).is_err() {
                    return;
                }
                ctx.request_repaint();
            }
        });
    }
    (job_tx, res_rx)
}

// ----------------------------------------------------------------------

#[derive(PartialEq)]
enum State {
    New,
    Requested,
    Ready,
    Failed,
    // file overwritten after a successful decode: needs re-decode, but the old
    // frames stay on screen until the new ones land (no placeholder flash).
    Stale,
}

// loading state for a gif's full frame set (separate from the fast first-frame
// decode tracked by `Thumb::state`).
#[derive(PartialEq)]
enum GifLoad {
    Unloaded,
    Loading,
    Loaded,
}

struct Thumb {
    state: State,
    // decoded frames + per-frame durations (seconds). after the fast decode
    // this holds just the first frame; the full set is loaded lazily on hover.
    // `frames[0]` is the still shown in the grid.
    frames: Vec<egui::TextureHandle>,
    delays: Vec<f32>,
    // whether the source is a (multi-frame) gif, and how far its frame load has
    // got. a gif proven to be single-frame flips `is_gif` back to false.
    is_gif: bool,
    gif_load: GifLoad,
    mtime: SystemTime,
    // the decode box the current frames came back at (0 until first decode).
    // single mode compares it against the window size to decide whether a
    // bigger re-decode would actually buy more detail. unused by the grid.
    decoded_px: u32,
    // dominant fg/bg colours, set once the image decodes. drives the window
    // tint (avg bg) + the hover glow colour.
    swatch: Option<Swatch>,
}

struct Mosaic {
    glob: Glob,
    root: PathBuf,
    recursive: bool,
    sort: Sort,
    mode: Mode,
    user_cols: Option<usize>,
    thumb_size: f32,

    paths: Vec<PathBuf>,
    thumbs: HashMap<PathBuf, Thumb>,

    // per-path hover-lift animation, eased toward 1.0 while hovered, 0.0
    // otherwise. purely a visual term -- never feeds the layout.
    hover_anim: HashMap<PathBuf, f32>,
    // the currently-hovered path and when the hover began, so the lift only
    // kicks in after the cursor dwells for DWELL seconds.
    hover_dwell: Option<(PathBuf, Instant)>,
    // the gif currently playing (clicked) and its clock (seconds since play
    // started). only one plays at a time; clicking it again stops it.
    play: Option<(PathBuf, f32)>,

    // custom gl renderers (thumbnail grid + text overlay). lazily built inside
    // the paint callback (needs the live glow context). shared so the callback
    // closure (Send + Sync + 'static) can reach them.
    gl: Arc<Mutex<Option<Renderers>>>,

    fs_rx: Receiver<()>,
    job_tx: Sender<Job>,
    res_rx: Receiver<DecodeResult>,

    // keep the watcher alive for the lifetime of the app.
    _watcher: notify::RecommendedWatcher,
}

fn mtime_of(p: &Path) -> SystemTime {
    std::fs::metadata(p)
        .and_then(|m| m.modified())
        .unwrap_or(SystemTime::UNIX_EPOCH)
}

fn size_of(p: &Path) -> u64 {
    std::fs::metadata(p).map(|m| m.len()).unwrap_or(0)
}

impl Mosaic {
    // walk the root, collect glob matches, sort, and diff against the current
    // set: drop removed entries, insert new ones, and invalidate any whose
    // mtime advanced so they re-decode.
    fn rescan(&mut self) {
        let mut found: Vec<PathBuf> = Vec::new();
        walk(
            &self.root,
            self.recursive,
            &mut |p| {
                if self.glob.is_match_path(p) {
                    found.push(p.to_path_buf());
                }
            },
            &mut |p, e| eprintln!("mosaic: {}: {e}", p.display()),
        );

        match self.sort {
            Sort::Name => found.sort(),
            Sort::Mtime => found.sort_by_key(|p| std::cmp::Reverse(mtime_of(p))),
            Sort::Size => found.sort_by_key(|p| std::cmp::Reverse(size_of(p))),
        }

        // drop thumbs no longer matching.
        let present: std::collections::HashSet<&PathBuf> = found.iter().collect();
        self.thumbs.retain(|p, _| present.contains(p));

        // insert / invalidate.
        for p in &found {
            let m = mtime_of(p);
            match self.thumbs.get_mut(p) {
                // overwritten: re-decode, but keep the old frames/swatch on
                // screen until the new decode lands so the tile updates in place
                // instead of flashing back to a placeholder like a new image.
                Some(t) if t.mtime != m => {
                    t.state = State::Stale;
                    t.gif_load = GifLoad::Unloaded;
                    t.mtime = m;
                }
                Some(_) => {}
                None => {
                    self.thumbs.insert(
                        p.clone(),
                        Thumb {
                            state: State::New,
                            frames: Vec::new(),
                            delays: Vec::new(),
                            is_gif: false,
                            gif_load: GifLoad::Unloaded,
                            mtime: m,
                            decoded_px: 0,
                            swatch: None,
                        },
                    );
                }
            }
        }

        self.paths = found;
    }

    // adjust thumbnail size, clamped to a sane range.
    fn zoom(&mut self, delta: f32) {
        self.thumb_size = (self.thumb_size + delta).clamp(48.0, 512.0);
    }

    // window tint: average background colour over all decoded images. falls
    // back to a neutral dark before anything has loaded.
    fn avg_bg(&self) -> egui::Color32 {
        let (mut r, mut g, mut b, mut n) = (0u32, 0u32, 0u32, 0u32);
        for t in self.thumbs.values() {
            if let Some(s) = t.swatch {
                r += s.bg[0] as u32;
                g += s.bg[1] as u32;
                b += s.bg[2] as u32;
                n += 1;
            }
        }
        if n == 0 {
            egui::Color32::from_rgb(18, 18, 18)
        } else {
            egui::Color32::from_rgb((r / n) as u8, (g / n) as u8, (b / n) as u8)
        }
    }

    // single-image view: blow the newest matching image up to fill the window,
    // aspect-fit (letterboxed, never cropped). decoded to the window's physical
    // pixel size so it isn't upscaled / blurred, and re-decoded bigger (only
    // bigger) as the window grows. the newest match is re-picked every frame, so
    // a freshly written file takes over the view as soon as the watcher reports.
    fn render_single(&mut self, ui: &mut egui::Ui) {
        // newest by mtime, independent of --sort.
        let Some(path) = self.paths.iter().max_by_key(|p| mtime_of(p)).cloned() else {
            return;
        };

        let area = ui.max_rect();
        // the box we want: the window's longer side in *physical* pixels (points
        // x dpi scale), quantised + clamped. that's the most detail the display
        // can show, so decoding to it avoids upscaling without overshooting.
        let phys = area.width().max(area.height()) * ui.ctx().pixels_per_point();
        let want = ((phys.ceil() as u32).div_ceil(SINGLE_STEP_PX) * SINGLE_STEP_PX)
            .clamp(SINGLE_STEP_PX, SINGLE_MAX_PX);

        // decide whether to (re)decode. cases:
        //  - New / Stale: first sight or overwritten -> decode (keep any old
        //    frame up meanwhile so the view updates in place, no placeholder).
        //  - upgrade: the window now wants more pixels than we have, and the
        //    source wasn't the limiting factor last time (decoded long side hit
        //    the box we asked for -> it was capped, so a bigger box buys detail).
        let info = self.thumbs.get(&path).map(|t| {
            let have = t
                .frames
                .first()
                .map(|f| f.size().into_iter().max().unwrap_or(0) as u32)
                .unwrap_or(0);
            (matches!(t.state, State::New | State::Stale), t.mtime, have, t.decoded_px)
        });
        if let Some((fresh, mtime, have, decoded)) = info {
            let upgrade = have > 0 && want > have && have >= decoded;
            if fresh || upgrade {
                if let Some(t) = self.thumbs.get_mut(&path) {
                    t.state = State::Requested;
                }
                let _ = self.job_tx.send(Job::Thumb(path.clone(), mtime, want));
            }
        }

        let Some(t) = self.thumbs.get(&path) else {
            return;
        };
        let Some(tex) = t.frames.first() else {
            paint_placeholder(ui.painter(), area);
            return;
        };
        let [tw, th] = tex.size();
        let rect = fit_rect(area, tw as f32, th as f32);
        let fg = t
            .swatch
            .map(|s| {
                [
                    s.fg[0] as f32 / 255.0,
                    s.fg[1] as f32 / 255.0,
                    s.fg[2] as f32 / 255.0,
                ]
            })
            .unwrap_or([1.0, 1.0, 1.0]);
        let quad = Quad {
            tex: tex.id(),
            rect,
            fg,
            glow: 0.0,
            nearest: tw.max(th) <= NEAREST_MAX_PX,
        };
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let status = format!("{name}   {tw}x{th}   q/esc quit");

        // same two-pass gl callback as the grid, just with a single quad.
        let renderers = self.gl.clone();
        let clip = ui.clip_rect();
        ui.painter().add(egui::PaintCallback {
            rect: clip,
            callback: std::sync::Arc::new(egui_glow::CallbackFn::new(move |info, painter| {
                let mut r = renderers.lock().unwrap();
                if r.is_none() {
                    *r = Some(Renderers::new(painter.gl()));
                }
                let r = r.as_ref().unwrap();
                r.grid.paint(painter, &info, std::slice::from_ref(&quad));
                r.text.paint(painter, &info, &status, 8.0, 6.0, 22.5);
            })),
        });
    }
}

// ----------------------------------------------------------------------
// pure layout. given the viewport width, the set zoom (`base_size`), an
// optional fixed column count and the image count, this derives the whole
// grid geometry as an immutable value -- no egui, no state, no side effects.
//
// the column count is decided by the *base* zoom, exactly as the unzoomed
// grid would lay out. `cell_size` then stretches each cell to divide the
// width evenly, soaking up the right-hand remainder so no gap is left.
// `fill_factor = cell_size / base_size >= 1.0` is the extra, purely-visual
// zoom layer: it climbs as the window widens, then snaps back to ~1.0 the
// moment a wider window admits another column and `cols` recomputes.

#[derive(Debug, Clone, Copy, PartialEq)]
struct Layout {
    cols: usize,
    rows: usize,
    base_size: f32,
    cell_size: f32,
    fill_factor: f32,
}

impl Layout {
    fn compute(avail_width: f32, base_size: f32, fixed_cols: Option<usize>, n: usize) -> Layout {
        let base = base_size.max(1.0);
        // cols from the base zoom -- the layout decision is unaffected by the
        // fill-to-width stretch below.
        let cols = match fixed_cols {
            Some(c) => c.max(1),
            None => ((avail_width / base).floor() as usize).max(1),
        };
        // stretch cells to fill the width exactly; fall back to the base size
        // before the first real frame gives us a width.
        let cell_size = if avail_width > 0.0 {
            avail_width / cols as f32
        } else {
            base
        };
        let fill_factor = cell_size / base;
        let rows = n.div_ceil(cols);
        Layout {
            cols,
            rows,
            base_size: base,
            cell_size,
            fill_factor,
        }
    }
}

// ----------------------------------------------------------------------
// custom gl renderer. egui already draws everything else through its glow
// backend; here we take over just the thumbnail quads via an egui paint
// callback, so we can lift the hovered quad toward the viewer (scaled + drawn
// last, overlapping its neighbours). textures stay owned by egui -- we look up
// the underlying glow texture per quad and draw a unit quad per cell.

// one quad to draw, produced by the (pure) render-prep pass. `rect` is the
// aspect-fitted, hover-expanded screen rect in egui points. instances are
// drawn in array order, so the prep pass sorts hovered-last for correct
// overlap. `glow` (0..1) drives the hover highlight, `fg` is its colour, and
// `nearest` selects pixel-crisp sampling for small images.
#[derive(Clone, Copy)]
struct Quad {
    tex: egui::TextureId,
    rect: egui::Rect,
    fg: [f32; 3],
    glow: f32,
    nearest: bool,
}

// glow geometry: the highlight quad is this much bigger than the image, and
// the fg colour fades from the image edge (`1/GLOW_EXPAND` of the quad) out to
// the quad rim, so it reads as a soft halo behind every edge.
const GLOW_EXPAND: f32 = 1.28;
const GLOW_STRENGTH: f32 = 0.07;
// images at or below this pixel size sample with nearest (crisp pixels);
// larger ones use linear (antialiased).
const NEAREST_MAX_PX: usize = 128;

// shared vertex shader: a unit quad as a triangle strip, positions from
// gl_VertexID (no vertex buffer). `v_uv` is 0..1 for the image pass; the glow
// pass remaps it to -1..1 itself.
const QUAD_VS: &str = r#"#version 330
uniform vec4 u_rect; // ndc: (x0, y_top, x1, y_bottom)
out vec2 v_uv;
void main() {
    float cx = (gl_VertexID == 1 || gl_VertexID == 3) ? 1.0 : 0.0;
    float cy = (gl_VertexID >= 2) ? 1.0 : 0.0;
    vec2 p = vec2(mix(u_rect.x, u_rect.z, cx), mix(u_rect.y, u_rect.w, cy));
    v_uv = vec2(cx, cy); // texture row 0 is the top of the image
    gl_Position = vec4(p, 0.0, 1.0);
}
"#;

fn compile_program(gl: &glow::Context, vs: &str, fs: &str) -> glow::Program {
    use glow::HasContext as _;
    unsafe {
        let program = gl.create_program().expect("create program");
        let mut shaders = Vec::new();
        for (kind, src) in [(glow::VERTEX_SHADER, vs), (glow::FRAGMENT_SHADER, fs)] {
            let sh = gl.create_shader(kind).expect("create shader");
            gl.shader_source(sh, src);
            gl.compile_shader(sh);
            assert!(
                gl.get_shader_compile_status(sh),
                "shader compile failed: {}",
                gl.get_shader_info_log(sh)
            );
            gl.attach_shader(program, sh);
            shaders.push(sh);
        }
        gl.link_program(program);
        assert!(
            gl.get_program_link_status(program),
            "program link failed: {}",
            gl.get_program_info_log(program)
        );
        for sh in shaders {
            gl.detach_shader(program, sh);
            gl.delete_shader(sh);
        }
        program
    }
}

struct GridRenderer {
    img: glow::Program,
    img_u_rect: glow::UniformLocation,
    img_u_tex: glow::UniformLocation,
    glow: glow::Program,
    glow_u_rect: glow::UniformLocation,
    glow_u_color: glow::UniformLocation,
    glow_u_alpha: glow::UniformLocation,
    glow_u_inner: glow::UniformLocation,
    vao: glow::VertexArray,
}

impl GridRenderer {
    fn new(gl: &glow::Context) -> Self {
        use glow::HasContext as _;
        // egui uploads thumbnails as SRGB8_ALPHA8, so the sampler hands us
        // linear values, and egui runs with FRAMEBUFFER_SRGB disabled (it
        // encodes in its own shader). we bypass that shader, so we must encode
        // linear -> srgb ourselves, else everything reads dark/burned.
        let img_fs = r#"#version 330
in vec2 v_uv;
uniform sampler2D u_tex;
out vec4 frag;
vec3 srgb_from_linear(vec3 c) {
    bvec3 cutoff = lessThan(c, vec3(0.0031308));
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
    return mix(hi, lo, vec3(cutoff));
}
void main() {
    vec4 c = texture(u_tex, v_uv);
    frag = vec4(srgb_from_linear(c.rgb), c.a);
}
"#;
        // glow: a soft fg-coloured halo behind a lifted quad. alpha is full
        // across the image footprint and fades from the image edge (u_inner)
        // out to the quad rim, so only the ring around the image edges shows.
        let glow_fs = r#"#version 330
in vec2 v_uv;
uniform vec3 u_color;
uniform float u_alpha;
uniform float u_inner;
out vec4 frag;
void main() {
    vec2 p = v_uv * 2.0 - 1.0;           // -1..1 from the quad's 0..1
    float e = max(abs(p.x), abs(p.y));   // box distance: 0 centre, 1 rim
    float a = (1.0 - smoothstep(u_inner, 1.0, e)) * u_alpha;
    frag = vec4(u_color * a, a);         // additive blend uses rgb
}
"#;
        let img = compile_program(gl, QUAD_VS, img_fs);
        let glow = compile_program(gl, QUAD_VS, glow_fs);
        unsafe {
            let img_u_rect = gl.get_uniform_location(img, "u_rect").unwrap();
            let img_u_tex = gl.get_uniform_location(img, "u_tex").unwrap();
            let glow_u_rect = gl.get_uniform_location(glow, "u_rect").unwrap();
            let glow_u_color = gl.get_uniform_location(glow, "u_color").unwrap();
            let glow_u_alpha = gl.get_uniform_location(glow, "u_alpha").unwrap();
            let glow_u_inner = gl.get_uniform_location(glow, "u_inner").unwrap();
            let vao = gl.create_vertex_array().expect("create vao");
            GridRenderer {
                img,
                img_u_rect,
                img_u_tex,
                glow,
                glow_u_rect,
                glow_u_color,
                glow_u_alpha,
                glow_u_inner,
                vao,
            }
        }
    }

    fn paint(&self, painter: &egui_glow::Painter, info: &egui::PaintCallbackInfo, quads: &[Quad]) {
        use glow::HasContext as _;
        let gl = painter.gl();
        let ppp = info.pixels_per_point;
        let [fbw, fbh] = info.screen_size_px;
        let (fbw, fbh) = (fbw as f32, fbh as f32);
        // map an egui point to normalized device coords (y flips: points grow
        // downward, ndc grows upward).
        let to_ndc = |x: f32, y: f32| -> (f32, f32) {
            ((x * ppp) / fbw * 2.0 - 1.0, 1.0 - (y * ppp) / fbh * 2.0)
        };
        let inner = 1.0 / GLOW_EXPAND;
        unsafe {
            // clip to the callback's rect so lifted quads don't spill past the
            // grid (e.g. up under the status bar).
            let vp = info.clip_rect_in_pixels();
            gl.enable(glow::SCISSOR_TEST);
            gl.scissor(vp.left_px, vp.from_bottom_px, vp.width_px, vp.height_px);
            gl.enable(glow::BLEND);
            gl.bind_vertex_array(Some(self.vao));
            gl.active_texture(glow::TEXTURE0);

            for q in quads {
                let Some(tex) = painter.texture(q.tex) else {
                    continue;
                };

                // glow first (behind this image), drawn additively so it reads
                // as a gentle highlight around every edge of the lifted quad.
                if q.glow > 0.0 {
                    let gr = expand_rect(q.rect, GLOW_EXPAND);
                    let (gx0, gyt) = to_ndc(gr.min.x, gr.min.y);
                    let (gx1, gyb) = to_ndc(gr.max.x, gr.max.y);
                    gl.use_program(Some(self.glow));
                    gl.blend_func(glow::ONE, glow::ONE);
                    gl.uniform_4_f32(Some(&self.glow_u_rect), gx0, gyt, gx1, gyb);
                    gl.uniform_3_f32(Some(&self.glow_u_color), q.fg[0], q.fg[1], q.fg[2]);
                    gl.uniform_1_f32(Some(&self.glow_u_alpha), q.glow * GLOW_STRENGTH);
                    gl.uniform_1_f32(Some(&self.glow_u_inner), inner);
                    gl.draw_arrays(glow::TRIANGLE_STRIP, 0, 4);
                }

                // image on top, normal alpha blend.
                let (x0, yt) = to_ndc(q.rect.min.x, q.rect.min.y);
                let (x1, yb) = to_ndc(q.rect.max.x, q.rect.max.y);
                gl.use_program(Some(self.img));
                gl.blend_func(glow::SRC_ALPHA, glow::ONE_MINUS_SRC_ALPHA);
                gl.uniform_1_i32(Some(&self.img_u_tex), 0);
                gl.uniform_4_f32(Some(&self.img_u_rect), x0, yt, x1, yb);
                gl.bind_texture(glow::TEXTURE_2D, Some(tex));
                // our pipeline owns its sampling: nearest magnification for
                // small images (crisp pixels), linear for larger ones
                // (antialiased). egui's TextureOptions don't reach this draw.
                let mag = if q.nearest {
                    glow::NEAREST
                } else {
                    glow::LINEAR
                };
                gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER, mag as i32);
                gl.tex_parameter_i32(
                    glow::TEXTURE_2D,
                    glow::TEXTURE_MIN_FILTER,
                    glow::LINEAR as i32,
                );
                gl.draw_arrays(glow::TRIANGLE_STRIP, 0, 4);
            }
            gl.disable(glow::SCISSOR_TEST);
            gl.bind_vertex_array(None);
        }
    }
}

// the two gl programs, built together. pass 1 (grid) and pass 2 (text) each
// keep a single, single-purpose shader.
struct Renderers {
    grid: GridRenderer,
    text: TextRenderer,
}

impl Renderers {
    fn new(gl: &glow::Context) -> Self {
        Renderers {
            grid: GridRenderer::new(gl),
            text: TextRenderer::new(gl),
        }
    }
}

// ----------------------------------------------------------------------
// text overlay. UbuntuMono is rasterised once (fontdue) into a uniform-cell
// R8 ASCII atlas; each glyph is a textured quad whose fragment shader samples
// the atlas coverage. drawn in screen points, in its own pass over the grid.

const FONT_TTF: &[u8] = include_bytes!("../vendor/ubuntu-font/UbuntuMono-Regular.ttf");
const FONT_RASTER_PX: f32 = 64.0; // atlas rasterisation size (not display size)

struct TextRenderer {
    program: glow::Program,
    vao: glow::VertexArray,
    vbo: glow::Buffer,
    atlas: glow::Texture,
    u_screen: glow::UniformLocation,
    u_offset: glow::UniformLocation,
    u_color: glow::UniformLocation,
    u_atlas: glow::UniformLocation,
    tex_size: u32,
    glyph_w: u32,
    glyph_h: u32,
    cols: u32,
}

impl TextRenderer {
    fn new(gl: &glow::Context) -> Self {
        use glow::HasContext as _;
        let vs = r#"#version 330
layout(location = 0) in vec2 a_pos; // egui points
layout(location = 1) in vec2 a_uv;
uniform vec2 u_screen; // window size in points
uniform vec2 u_offset; // points
out vec2 v_uv;
void main() {
    vec2 p = a_pos + u_offset;
    vec2 ndc = vec2(p.x / u_screen.x * 2.0 - 1.0, 1.0 - p.y / u_screen.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    v_uv = a_uv;
}
"#;
        // the atlas is single-channel coverage (R8), so no srgb dance -- we
        // just tint by u_color and modulate alpha by coverage.
        let fs = r#"#version 330
in vec2 v_uv;
uniform sampler2D u_atlas;
uniform vec4 u_color;
out vec4 frag;
void main() {
    float a = texture(u_atlas, v_uv).r;
    frag = vec4(u_color.rgb, u_color.a * a);
}
"#;
        let (tex_size, glyph_w, glyph_h, cols, pixels) = build_atlas_pixels();
        unsafe {
            let program = gl.create_program().expect("create program");
            let mut shaders = Vec::new();
            for (kind, src) in [(glow::VERTEX_SHADER, vs), (glow::FRAGMENT_SHADER, fs)] {
                let sh = gl.create_shader(kind).expect("create shader");
                gl.shader_source(sh, src);
                gl.compile_shader(sh);
                assert!(
                    gl.get_shader_compile_status(sh),
                    "text shader compile failed: {}",
                    gl.get_shader_info_log(sh)
                );
                gl.attach_shader(program, sh);
                shaders.push(sh);
            }
            gl.link_program(program);
            assert!(
                gl.get_program_link_status(program),
                "text program link failed: {}",
                gl.get_program_info_log(program)
            );
            for sh in shaders {
                gl.detach_shader(program, sh);
                gl.delete_shader(sh);
            }

            // upload the atlas. R8, width may be non-multiple-of-4 -> set tight
            // unpack alignment.
            let atlas = gl.create_texture().expect("atlas tex");
            gl.bind_texture(glow::TEXTURE_2D, Some(atlas));
            gl.pixel_store_i32(glow::UNPACK_ALIGNMENT, 1);
            gl.tex_image_2d(
                glow::TEXTURE_2D,
                0,
                glow::R8 as i32,
                tex_size as i32,
                tex_size as i32,
                0,
                glow::RED,
                glow::UNSIGNED_BYTE,
                glow::PixelUnpackData::Slice(Some(&pixels)),
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_MIN_FILTER,
                glow::LINEAR as i32,
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_MAG_FILTER,
                glow::LINEAR as i32,
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_WRAP_S,
                glow::CLAMP_TO_EDGE as i32,
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_WRAP_T,
                glow::CLAMP_TO_EDGE as i32,
            );

            let vao = gl.create_vertex_array().expect("text vao");
            let vbo = gl.create_buffer().expect("text vbo");
            gl.bind_vertex_array(Some(vao));
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(vbo));
            // interleaved [x, y, u, v] f32, stride 16.
            gl.enable_vertex_attrib_array(0);
            gl.vertex_attrib_pointer_f32(0, 2, glow::FLOAT, false, 16, 0);
            gl.enable_vertex_attrib_array(1);
            gl.vertex_attrib_pointer_f32(1, 2, glow::FLOAT, false, 16, 8);
            gl.bind_vertex_array(None);

            let u_screen = gl.get_uniform_location(program, "u_screen").unwrap();
            let u_offset = gl.get_uniform_location(program, "u_offset").unwrap();
            let u_color = gl.get_uniform_location(program, "u_color").unwrap();
            let u_atlas = gl.get_uniform_location(program, "u_atlas").unwrap();
            TextRenderer {
                program,
                vao,
                vbo,
                atlas,
                u_screen,
                u_offset,
                u_color,
                u_atlas,
                tex_size,
                glyph_w,
                glyph_h,
                cols,
            }
        }
    }

    fn glyph_uv(&self, ch: char) -> Option<[f32; 4]> {
        let idx = ch as u32;
        if !(32..=126).contains(&idx) {
            return None;
        }
        let i = idx - 32;
        let (col, row) = (i % self.cols, i / self.cols);
        let u0 = (col * self.glyph_w) as f32 / self.tex_size as f32;
        let v0 = (row * self.glyph_h) as f32 / self.tex_size as f32;
        let u1 = ((col + 1) * self.glyph_w) as f32 / self.tex_size as f32;
        let v1 = ((row + 1) * self.glyph_h) as f32 / self.tex_size as f32;
        Some([u0, v0, u1, v1])
    }

    // draw `text` with its top-left at (x, y) in egui points, glyphs `px` tall.
    fn paint(
        &self,
        painter: &egui_glow::Painter,
        info: &egui::PaintCallbackInfo,
        text: &str,
        x: f32,
        y: f32,
        px: f32,
    ) {
        use glow::HasContext as _;
        let gl = painter.gl();
        let gh = px;
        let gw = px * self.glyph_w as f32 / self.glyph_h as f32;

        // build the glyph quads in egui points: two triangles per glyph.
        let mut verts: Vec<f32> = Vec::with_capacity(text.len() * 24);
        for (ci, ch) in text.chars().enumerate() {
            let Some(uv) = self.glyph_uv(ch) else {
                continue;
            };
            let cx = x + ci as f32 * gw;
            let (x0, y0, x1, y1) = (cx, y, cx + gw, y + gh);
            let q = [
                (x0, y0, uv[0], uv[1]),
                (x1, y0, uv[2], uv[1]),
                (x1, y1, uv[2], uv[3]),
                (x0, y0, uv[0], uv[1]),
                (x1, y1, uv[2], uv[3]),
                (x0, y1, uv[0], uv[3]),
            ];
            for (vx, vy, vu, vv) in q {
                verts.extend_from_slice(&[vx, vy, vu, vv]);
            }
        }
        if verts.is_empty() {
            return;
        }
        let n = (verts.len() / 4) as i32;

        let screen = info.screen_size_px;
        let ppp = info.pixels_per_point;
        let (sw, sh) = (screen[0] as f32 / ppp, screen[1] as f32 / ppp);
        unsafe {
            gl.enable(glow::BLEND);
            gl.blend_func(glow::SRC_ALPHA, glow::ONE_MINUS_SRC_ALPHA);
            gl.use_program(Some(self.program));
            gl.bind_vertex_array(Some(self.vao));
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(self.vbo));
            gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, f32_bytes(&verts), glow::DYNAMIC_DRAW);
            gl.active_texture(glow::TEXTURE0);
            gl.bind_texture(glow::TEXTURE_2D, Some(self.atlas));
            gl.uniform_1_i32(Some(&self.u_atlas), 0);
            gl.uniform_2_f32(Some(&self.u_screen), sw, sh);
            // dark drop-shadow first, then white on top, so the readout stays
            // legible over any thumbnail. the shadow is drawn at several
            // offsets to spread it into a soft, slightly larger blob.
            gl.uniform_4_f32(Some(&self.u_color), 0.0, 0.0, 0.0, 0.5);
            for (ox, oy) in [(2.5, 2.5), (1.5, 2.5), (2.5, 1.5), (1.5, 1.5)] {
                gl.uniform_2_f32(Some(&self.u_offset), ox, oy);
                gl.draw_arrays(glow::TRIANGLES, 0, n);
            }
            gl.uniform_2_f32(Some(&self.u_offset), 0.0, 0.0);
            gl.uniform_4_f32(Some(&self.u_color), 1.0, 1.0, 1.0, 1.0);
            gl.draw_arrays(glow::TRIANGLES, 0, n);
            gl.bind_vertex_array(None);
        }
    }
}

// reinterpret an &[f32] as the &[u8] glow wants for buffer uploads. little-
// endian, tightly packed -- no padding in a Vec<f32>.
fn f32_bytes(v: &[f32]) -> &[u8] {
    // SAFETY: f32 has no invalid bit patterns and the slice stays borrowed for
    // the call; len is exact.
    unsafe { std::slice::from_raw_parts(v.as_ptr() as *const u8, std::mem::size_of_val(v)) }
}

// rasterise UbuntuMono into a uniform-cell R8 atlas, ASCII 32..=126. ported
// from dep-graph-rs. returns (tex_size, glyph_w, glyph_h, cols, pixels).
fn build_atlas_pixels() -> (u32, u32, u32, u32, Vec<u8>) {
    let font = fontdue::Font::from_bytes(FONT_TTF, fontdue::FontSettings::default())
        .expect("UbuntuMono ttf parse");
    let m = font.metrics('M', FONT_RASTER_PX);
    let g = font.metrics('g', FONT_RASTER_PX);
    let glyph_w = m.advance_width.ceil() as u32 + 1;
    let line = font
        .horizontal_line_metrics(FONT_RASTER_PX)
        .expect("line metrics");
    let glyph_h =
        (line.new_line_size.ceil() as u32).max(((m.height + g.height) as f32 * 0.9).ceil() as u32);

    let cols = 16u32;
    let rows = ((126 - 32 + 1) as u32).div_ceil(cols);
    let tex_size = (cols * glyph_w).max(rows * glyph_h).next_power_of_two();
    let mut pixels = vec![0u8; (tex_size * tex_size) as usize];
    let baseline = line.ascent.ceil() as i32;

    for i in 0u32..(126 - 32 + 1) {
        let ch = (32 + i) as u8 as char;
        let (metrics, bitmap) = font.rasterize(ch, FONT_RASTER_PX);
        let (col, row) = (i % cols, i / cols);
        let cell_x = (col * glyph_w) as i32;
        let cell_y = (row * glyph_h) as i32;
        let dx0 = cell_x + (glyph_w as i32 - metrics.width as i32) / 2;
        let dy0 = cell_y + baseline - metrics.height as i32 - metrics.ymin;
        for gy in 0..metrics.height {
            for gx in 0..metrics.width {
                let v = bitmap[gy * metrics.width + gx];
                if v == 0 {
                    continue;
                }
                let (dx, dy) = (dx0 + gx as i32, dy0 + gy as i32);
                if dx < 0 || dy < 0 || dx as u32 >= tex_size || dy as u32 >= tex_size {
                    continue;
                }
                let idx = (dy as u32 * tex_size + dx as u32) as usize;
                if v > pixels[idx] {
                    pixels[idx] = v;
                }
            }
        }
    }
    (tex_size, glyph_w, glyph_h, cols, pixels)
}

impl eframe::App for Mosaic {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // drain filesystem pings -> at most one rescan per frame.
        let mut dirty = false;
        while self.fs_rx.try_recv().is_ok() {
            dirty = true;
        }
        if dirty {
            self.rescan();
        }

        // drain decode results -> upload textures on the ui thread.
        // filtering is set by the grid pass at draw time, so the options here
        // don't matter.
        while let Ok(res) = self.res_rx.try_recv() {
            let Some(t) = self.thumbs.get_mut(&res.path) else {
                continue;
            };
            // drop results for a version that's since been overwritten.
            if res.mtime != t.mtime {
                continue;
            }
            let name = res.path.to_string_lossy().into_owned();
            match res.payload {
                Payload::Thumb(Some(d)) => {
                    t.frames = vec![ctx.load_texture(name, d.image, egui::TextureOptions::LINEAR)];
                    t.swatch = Some(d.swatch);
                    t.is_gif = d.is_gif;
                    t.decoded_px = res.box_px;
                    t.state = State::Ready;
                }
                Payload::Thumb(None) => t.state = State::Failed,
                Payload::Frames(Some(d)) if d.frames.len() > 1 => {
                    t.frames = d
                        .frames
                        .into_iter()
                        .enumerate()
                        .map(|(i, img)| {
                            ctx.load_texture(
                                format!("{name}#{i}"),
                                img,
                                egui::TextureOptions::LINEAR,
                            )
                        })
                        .collect();
                    t.delays = d.delays;
                    t.gif_load = GifLoad::Loaded;
                }
                // a gif that turned out to be a single frame (or failed to load
                // its frames): treat as a still, no play badge.
                Payload::Frames(_) => {
                    t.is_gif = false;
                    t.gif_load = GifLoad::Loaded;
                }
            }
        }

        // keyboard / scroll zoom + quit.
        let mut quit = false;
        ctx.input(|i| {
            if i.key_pressed(egui::Key::Plus) || i.key_pressed(egui::Key::Equals) {
                self.zoom(2.0);
            }
            if i.key_pressed(egui::Key::Minus) {
                self.zoom(-2.0);
            }
            if i.modifiers.ctrl && i.raw_scroll_delta.y != 0.0 {
                self.zoom(i.raw_scroll_delta.y);
            }
            if i.key_pressed(egui::Key::Escape) || i.key_pressed(egui::Key::Q) {
                quit = true;
            }
        });
        if quit {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        // strip the central panel's default inner margin so the grid runs
        // edge-to-edge (no border around the images). the only chrome is the
        // text overlay drawn in-shader at the top-left.
        // fill the window with the average background of the loaded images
        // instead of the default (unpleasant white) panel colour.
        let panel_frame = egui::Frame::central_panel(&ctx.style())
            .inner_margin(0.0)
            .outer_margin(0.0)
            .fill(self.avg_bg());
        egui::CentralPanel::default()
            .frame(panel_frame)
            .show(ctx, |ui| {
                if self.paths.is_empty() {
                    ui.centered_and_justified(|ui| {
                        ui.label("no images match the glob (yet)");
                    });
                    return;
                }

                if self.mode == Mode::Single {
                    self.render_single(ui);
                    return;
                }

                // no gaps between thumbnails: zero the item spacing so cells abut.
                // floating scrollbar so it overlays rather than insetting the
                // content width -- otherwise it would carve a gap back out on the
                // right and the fill-to-width math would be off by its thickness.
                ui.spacing_mut().item_spacing = egui::Vec2::ZERO;
                ui.spacing_mut().scroll.floating = true;

                // pure layout from the current width + set zoom. everything below
                // this line is the impure rendering pass.
                let avail = ui.available_width();
                let n = self.paths.len();
                let layout = Layout::compute(avail, self.thumb_size, self.user_cols, n);
                let dt = ctx.input(|i| i.stable_dt).min(0.1);
                // the top-left readout, drawn in-shader over the grid.
                let status = format!(
                    "{n} images   {} cols   {}px x{:.2}   q/esc quit",
                    layout.cols, self.thumb_size as u32, layout.fill_factor
                );

                // destructure so the closure can borrow these fields disjointly.
                let Mosaic {
                    paths,
                    thumbs,
                    job_tx,
                    hover_anim,
                    hover_dwell,
                    play,
                    gl,
                    ..
                } = self;

                egui::ScrollArea::vertical()
                    .auto_shrink([false, false])
                    .show_viewport(ui, |ui, viewport| {
                        let cell = layout.cell_size;
                        ui.set_height(layout.rows as f32 * cell);
                        // content (0,0) in screen points; a cell at (row,col) sits
                        // at origin + (col,row)*cell.
                        let origin = ui.min_rect().min;
                        let clip = ui.clip_rect();

                        // which cell is under the pointer (pure: pointer -> grid).
                        let hovered: Option<usize> =
                            ui.input(|i| i.pointer.hover_pos()).and_then(|p| {
                                if !clip.contains(p) {
                                    return None;
                                }
                                let (cx, cy) = (p.x - origin.x, p.y - origin.y);
                                if cx < 0.0 || cy < 0.0 {
                                    return None;
                                }
                                let col = (cx / cell) as usize;
                                if col >= layout.cols {
                                    return None;
                                }
                                let idx = (cy / cell) as usize * layout.cols + col;
                                (idx < n).then_some(idx)
                            });
                        let hovered_path = hovered.map(|i| paths[i].clone());

                        // dwell gate: the lift only engages once the cursor has
                        // rested on the same image for DWELL seconds. moving to a
                        // new image (or off the grid) restarts the clock.
                        let lift_active = match (&hovered_path, &mut *hover_dwell) {
                            (Some(p), Some((dp, since))) if dp == p => {
                                since.elapsed().as_secs_f32() >= DWELL
                            }
                            (Some(p), slot) => {
                                *slot = Some((p.clone(), Instant::now()));
                                false
                            }
                            (None, slot) => {
                                *slot = None;
                                false
                            }
                        };

                        // pressing anywhere on a gif toggles its playback. the
                        // play badge is decoration only -- the whole image is
                        // the hit target.
                        let clicked = ui.input(|i| i.pointer.primary_clicked());
                        if clicked
                            && let Some(hp) = &hovered_path
                            && thumbs.get(hp).is_some_and(|t| t.is_gif)
                        {
                            match &*play {
                                Some((pp, _)) if pp == hp => *play = None,
                                _ => *play = Some((hp.clone(), 0.0)),
                            }
                        }

                        // hovering a gif eagerly loads all its frames (so a
                        // later press plays instantly), but does not start it.
                        if let Some(hp) = &hovered_path
                            && let Some(t) = thumbs.get_mut(hp)
                            && t.is_gif
                            && t.state == State::Ready
                            && t.gif_load == GifLoad::Unloaded
                        {
                            t.gif_load = GifLoad::Loading;
                            let _ = job_tx.send(Job::Frames(hp.clone(), t.mtime));
                        }

                        // advance the playing gif's clock.
                        if let Some((_, t)) = play.as_mut() {
                            *t += dt;
                        }

                        // visible row span.
                        let first = (viewport.min.y / cell).floor().max(0.0) as usize;
                        let last = ((viewport.max.y / cell).ceil() as usize).min(layout.rows);

                        // build the draw list. placeholders (undecoded) go straight
                        // to the egui painter, *under* the gl pass; decoded thumbs
                        // become gl quads. each cell's hover anim is eased here.
                        let mut quads: Vec<(f32, Quad)> = Vec::new();
                        // bottom-right play badges for gifs not lifted / playing.
                        let mut badges: Vec<egui::Rect> = Vec::new();
                        let mut animating = false;
                        for row in first..last {
                            for col in 0..layout.cols {
                                let idx = row * layout.cols + col;
                                if idx >= n {
                                    break;
                                }
                                let path = &paths[idx];
                                let cell_rect = egui::Rect::from_min_size(
                                    egui::pos2(
                                        origin.x + col as f32 * cell,
                                        origin.y + row as f32 * cell,
                                    ),
                                    egui::vec2(cell, cell),
                                );

                                // ease this cell's hover-lift toward its target.
                                // only the dwelt-on cell lifts.
                                let target = if lift_active
                                    && hovered_path.as_deref() == Some(path.as_path())
                                {
                                    1.0
                                } else {
                                    0.0
                                };
                                let cur = hover_anim.entry(path.clone()).or_insert(0.0);
                                *cur += (target - *cur) * (dt * HOVER_SPEED).min(1.0);
                                if target == 0.0 && *cur < 0.001 {
                                    *cur = 0.0;
                                }
                                let anim = *cur;
                                if anim > 0.0 {
                                    animating = true;
                                }

                                match thumbs.get_mut(path) {
                                    Some(t) => {
                                        // queue a decode when first visible (New)
                                        // or after an overwrite (Stale). a Stale
                                        // tile keeps its old frames on screen
                                        // (drawn below) until the new ones land.
                                        if t.state == State::New || t.state == State::Stale {
                                            t.state = State::Requested;
                                            let _ = job_tx.send(Job::Thumb(
                                                path.to_path_buf(),
                                                t.mtime,
                                                THUMB_PX,
                                            ));
                                        }
                                        if t.frames.is_empty() {
                                            paint_placeholder(ui.painter(), cell_rect);
                                            continue;
                                        }
                                        // play the clicked gif; otherwise show
                                        // the first frame.
                                        let playing_this = matches!(
                                            &*play, Some((pp, _)) if pp == path
                                        );
                                        let fi = match &*play {
                                            Some((pp, clk)) if pp == path && t.frames.len() > 1 => {
                                                frame_at(&t.delays, *clk)
                                            }
                                            _ => 0,
                                        };
                                        let tex = &t.frames[fi];
                                        let [tw, th] = tex.size();
                                        let fitted = fit_rect(cell_rect, tw as f32, th as f32);
                                        let rect = expand_rect(fitted, 1.0 + HOVER_LIFT * anim);
                                        let fg = t
                                            .swatch
                                            .map(|s| {
                                                [
                                                    s.fg[0] as f32 / 255.0,
                                                    s.fg[1] as f32 / 255.0,
                                                    s.fg[2] as f32 / 255.0,
                                                ]
                                            })
                                            .unwrap_or([1.0, 1.0, 1.0]);
                                        // play badge: a gif, not lifted, not
                                        // playing -> show a hint bottom-right.
                                        if t.is_gif && anim < 0.05 && !playing_this {
                                            let bs = (cell * 0.16).clamp(14.0, 30.0);
                                            let bm = bs * 0.35;
                                            badges.push(egui::Rect::from_min_max(
                                                egui::pos2(
                                                    fitted.max.x - bm - bs,
                                                    fitted.max.y - bm - bs,
                                                ),
                                                egui::pos2(fitted.max.x - bm, fitted.max.y - bm),
                                            ));
                                        }
                                        quads.push((
                                            anim,
                                            Quad {
                                                tex: tex.id(),
                                                rect,
                                                fg,
                                                glow: anim,
                                                nearest: tw.max(th) <= NEAREST_MAX_PX,
                                            },
                                        ));
                                    }
                                    None => paint_placeholder(ui.painter(), cell_rect),
                                }
                            }
                        }
                        // drop fully-decayed anims so the map stays bounded.
                        hover_anim.retain(|_, v| *v > 0.0);

                        // hovered-last so the lifted quad overlaps its neighbours.
                        quads.sort_by(|a, b| {
                            a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal)
                        });
                        let quads: Vec<Quad> = quads.into_iter().map(|(_, q)| q).collect();

                        // hand it all to the gl callback (the only impure-gpu
                        // bit). two passes, single-purpose shaders each: pass 1
                        // draws the thumbnail grid, pass 2 the text overlay.
                        // renderers are built lazily on first paint.
                        let renderers = gl.clone();
                        let status = status.clone();
                        ui.painter().add(egui::PaintCallback {
                            rect: clip,
                            callback: std::sync::Arc::new(egui_glow::CallbackFn::new(
                                move |info, painter| {
                                    let mut r = renderers.lock().unwrap();
                                    if r.is_none() {
                                        *r = Some(Renderers::new(painter.gl()));
                                    }
                                    let r = r.as_ref().unwrap();
                                    r.grid.paint(painter, &info, &quads);
                                    r.text.paint(painter, &info, &status, 8.0, 6.0, 22.5);
                                },
                            )),
                        });

                        // play badges, drawn with the egui painter *over* the gl
                        // grid (callbacks paint before later shapes in the layer).
                        for b in &badges {
                            let painter = ui.painter();
                            painter.rect_filled(
                                *b,
                                b.width() * 0.22,
                                egui::Color32::from_black_alpha(110),
                            );
                            let c = b.center();
                            let r = b.width() * 0.26;
                            painter.add(egui::Shape::convex_polygon(
                                vec![
                                    egui::pos2(c.x - r * 0.7, c.y - r),
                                    egui::pos2(c.x - r * 0.7, c.y + r),
                                    egui::pos2(c.x + r, c.y),
                                ],
                                egui::Color32::from_white_alpha(220),
                                egui::Stroke::NONE,
                            ));
                        }

                        // keep ticking while easing, while a hover is dwelling
                        // (a still cursor emits no events, so the dwell timer
                        // would never elapse), and while a gif is playing.
                        if animating || play.is_some() || (hovered_path.is_some() && !lift_active) {
                            ctx.request_repaint();
                        }
                    });
            });
    }
}

const HOVER_LIFT: f32 = 0.15; // hovered quad grows 15% at full lift
const HOVER_SPEED: f32 = 12.0; // ease rate toward the hover target
const DWELL: f32 = 0.1; // seconds the cursor must rest before the lift engages

// aspect-fit a texture (tw x th) centered inside a square cell.
fn fit_rect(cell: egui::Rect, tw: f32, th: f32) -> egui::Rect {
    let s = (cell.width() / tw).min(cell.height() / th);
    egui::Rect::from_center_size(cell.center(), egui::vec2(tw * s, th * s))
}

// scale a rect about its center (for the hover lift).
fn expand_rect(r: egui::Rect, f: f32) -> egui::Rect {
    egui::Rect::from_center_size(r.center(), r.size() * f)
}

// a flat tile drawn for cells whose thumbnail hasn't decoded yet.
fn paint_placeholder(painter: &egui::Painter, cell: egui::Rect) {
    painter.rect_filled(cell.shrink(1.0), 4.0, egui::Color32::from_gray(28));
}

fn main() -> eframe::Result<()> {
    let argv: Vec<String> = std::env::args().collect();
    let args = parse_args(&argv);

    let pattern = expand_tilde(&args.pattern);
    let (root, recursive) = watch_root(&pattern);
    if !root.exists() {
        die(&format!("watch root does not exist: {}", root.display()));
    }
    // canonicalize root + rewrite the glob to its canonical prefix. macOS
    // resolves /tmp -> /private/tmp and notify reports canonical paths, so
    // the glob must be canonical too or nothing matches.
    let canon_root = match root.canonicalize() {
        Ok(r) => r,
        Err(e) => die(&format!("canonicalize {}: {e}", root.display())),
    };
    let tail = pattern
        .strip_prefix(&root.to_string_lossy().into_owned())
        .unwrap_or(&pattern);
    let canon_pattern = format!("{}{}", canon_root.display(), tail);

    // allow-set: env var first, then cli occurrences layered on top.
    let mut allow = std::collections::HashSet::new();
    if let Err(e) = polyflag::apply_env_for_flag("mosaic", "allow", ALLOW_TOKENS, &mut allow) {
        die(&format!("$MOSAIC_ALLOW: {e}"));
    }
    for v in &args.allow_values {
        if let Err(e) = polyflag::apply(v, ALLOW_TOKENS, &mut allow) {
            die(&format!("--allow: {e}"));
        }
    }

    let glob = match Glob::compile_with(&canon_pattern, &allow) {
        Ok(g) => g,
        Err(e) => die(&format!("bad glob: {e}")),
    };

    // filesystem watcher: every event pings the ui thread to rescan.
    let (fs_tx, fs_rx) = mpsc::channel::<()>();
    // NOTE: eframe would otherwise inject a default egui app icon, whose png
    // bytes crash macOS 26's ImageIO (SIGBUS in NSImage::initWithData). handing
    // it an empty IconData makes eframe skip the icon path entirely. see
    // eframe NativeOptions::viewport docs.
    let native = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("mosaic")
            .with_decorations(false)
            .with_icon(egui::IconData::default()),
        ..Default::default()
    };
    let root = canon_root;

    eframe::run_native(
        "mosaic",
        native,
        Box::new(move |cc| {
            egui_extras_install(cc);
            let ctx = cc.egui_ctx.clone();
            let watch_ctx = ctx.clone();
            let mut watcher = notify::recommended_watcher(move |_res| {
                let _ = fs_tx.send(());
                watch_ctx.request_repaint();
            })
            .map_err(|e| format!("watcher init: {e}"))?;
            let mode = if recursive {
                RecursiveMode::Recursive
            } else {
                RecursiveMode::NonRecursive
            };
            watcher
                .watch(&root, mode)
                .map_err(|e| format!("watch {}: {e}", root.display()))?;

            let (job_tx, res_rx) = spawn_workers(ctx);

            let mut app = Mosaic {
                glob,
                root,
                recursive,
                sort: args.sort,
                mode: args.mode,
                user_cols: args.cols,
                thumb_size: args.size,
                paths: Vec::new(),
                thumbs: HashMap::new(),
                hover_anim: HashMap::new(),
                hover_dwell: None,
                play: None,
                gl: Arc::new(Mutex::new(None)),
                fs_rx,
                job_tx,
                res_rx,
                _watcher: watcher,
            };
            app.rescan();
            Ok(Box::new(app))
        }),
    )
}

// image loaders aren't needed (we decode + upload textures ourselves), but
// keeping a hook here makes it obvious where to add egui_extras later if we
// want svg / animated-gif support.
fn egui_extras_install(_cc: &eframe::CreationContext<'_>) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cols_from_base_zoom() {
        // 1000px wide, 192px base -> floor(1000/192) = 5 cols.
        let l = Layout::compute(1000.0, 192.0, None, 100);
        assert_eq!(l.cols, 5);
    }

    #[test]
    fn cells_fill_width_exactly() {
        // whatever the cols, cell_size * cols covers the full width (no gap).
        let l = Layout::compute(1000.0, 192.0, None, 100);
        assert!((l.cell_size * l.cols as f32 - 1000.0).abs() < 1e-3);
    }

    #[test]
    fn fill_factor_is_visual_zoom() {
        // 5 cols at 192 base = 960px of "natural" width; the 40px remainder is
        // soaked up by stretching each cell -> fill_factor = 1000/960.
        let l = Layout::compute(1000.0, 192.0, None, 100);
        assert!((l.fill_factor - 1000.0 / 960.0).abs() < 1e-4);
        assert!(l.fill_factor >= 1.0);
    }

    #[test]
    fn new_column_snaps_fill_back() {
        // widening from just-under to just-over the 6-column threshold
        // (6*192 = 1152) drops the fill factor back toward 1.0.
        let before = Layout::compute(1151.0, 192.0, None, 100);
        let after = Layout::compute(1153.0, 192.0, None, 100);
        assert_eq!(before.cols, 5);
        assert_eq!(after.cols, 6);
        assert!(after.fill_factor < before.fill_factor);
    }

    #[test]
    fn fixed_cols_overrides_width() {
        let l = Layout::compute(1000.0, 192.0, Some(4), 100);
        assert_eq!(l.cols, 4);
        assert!((l.cell_size - 250.0).abs() < 1e-3);
    }

    #[test]
    fn rows_round_up() {
        let l = Layout::compute(1000.0, 192.0, None, 11); // 5 cols -> 3 rows
        assert_eq!(l.cols, 5);
        assert_eq!(l.rows, 3);
    }

    #[test]
    fn zero_width_falls_back_to_base() {
        // before the first real frame we have no width; don't divide by it.
        let l = Layout::compute(0.0, 192.0, None, 10);
        assert_eq!(l.cols, 1);
        assert_eq!(l.cell_size, 192.0);
        assert_eq!(l.fill_factor, 1.0);
    }
}
