//! Font Matrix classification engine.
//!
//! Analyzes glyph outlines via skrifa to classify fonts into skeleton types:
//! "dynamic", "rational", or "geometric".
//!
//! Signals (in priority order):
//! 1. Aperture openness (e, c, s glyphs)
//! 2. Stress angle (o glyph)
//! 3. Stroke contrast (o glyph)
//! 4. Construction geometry (o, n glyphs)
//! 5. Name keywords (fallback)

use std::path::Path;

use skrifa::{FontRef, MetadataProvider};
use skrifa::outline::{DrawSettings, OutlinePen};

use serde::Serialize;

// ── Result type ───────────────────────────────────────────────────────────────

#[derive(Serialize, Clone, Debug)]
pub struct ClassificationResult {
    pub skeleton: String,
    pub flesh_contrast: String,
    pub flesh_serif: i32,
    /// Serif detected from outlines ('l' foot vs stem). None = couldn't measure.
    pub serif: Option<bool>,
    pub stroke_contrast_ratio: Option<f64>,
    pub reason: String,
}

// ── Contour collection ────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
struct Point {
    x: f32,
    y: f32,
}

#[derive(Clone, Debug, Default)]
struct Contour {
    points: Vec<Point>,
}

#[derive(Default)]
struct ContourPen {
    contours: Vec<Contour>,
    current: Contour,
}

impl ContourPen {
    fn sample_cubic(pts: &[Point; 4], samples: &mut Vec<Point>) {
        for i in 1..=8 {
            let t = i as f32 / 8.0;
            let u = 1.0 - t;
            let x = u * u * u * pts[0].x
                + 3.0 * u * u * t * pts[1].x
                + 3.0 * u * t * t * pts[2].x
                + t * t * t * pts[3].x;
            let y = u * u * u * pts[0].y
                + 3.0 * u * u * t * pts[1].y
                + 3.0 * u * t * t * pts[2].y
                + t * t * t * pts[3].y;
            samples.push(Point { x, y });
        }
    }

    fn sample_quad(pts: &[Point; 3], samples: &mut Vec<Point>) {
        for i in 1..=8 {
            let t = i as f32 / 8.0;
            let u = 1.0 - t;
            let x = u * u * pts[0].x + 2.0 * u * t * pts[1].x + t * t * pts[2].x;
            let y = u * u * pts[0].y + 2.0 * u * t * pts[1].y + t * t * pts[2].y;
            samples.push(Point { x, y });
        }
    }

    fn last_point(&self) -> Point {
        self.current
            .points
            .last()
            .cloned()
            .unwrap_or(Point { x: 0.0, y: 0.0 })
    }
}

impl OutlinePen for ContourPen {
    fn move_to(&mut self, x: f32, y: f32) {
        if !self.current.points.is_empty() {
            self.contours.push(std::mem::take(&mut self.current));
        }
        self.current.points.push(Point { x, y });
    }

    fn line_to(&mut self, x: f32, y: f32) {
        self.current.points.push(Point { x, y });
    }

    fn quad_to(&mut self, cx: f32, cy: f32, x: f32, y: f32) {
        let p0 = self.last_point();
        let pts = [p0, Point { x: cx, y: cy }, Point { x, y }];
        Self::sample_quad(&pts, &mut self.current.points);
    }

    fn curve_to(&mut self, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x: f32, y: f32) {
        let p0 = self.last_point();
        let pts = [
            p0,
            Point { x: cx0, y: cy0 },
            Point { x: cx1, y: cy1 },
            Point { x, y },
        ];
        Self::sample_cubic(&pts, &mut self.current.points);
    }

    fn close(&mut self) {
        if !self.current.points.is_empty() {
            self.contours.push(std::mem::take(&mut self.current));
        }
    }
}

// ── Glyph outline extraction ─────────────────────────────────────────────────

fn get_glyph_contours(font: &FontRef, ch: char) -> Option<Vec<Contour>> {
    let charmap = font.charmap();
    let glyph_id = charmap.map(ch)?;
    let outlines = font.outline_glyphs();
    let glyph = outlines.get(glyph_id)?;
    // Variable fonts: measure at Regular (wght 400), not the file's default
    // instance, which is often Thin or Black and skews every signal.
    let location = font.axes().location([("wght", 400.0)]);
    let settings = DrawSettings::unhinted(skrifa::instance::Size::new(1000.0), &location);
    let mut pen = ContourPen::default();
    glyph.draw(settings, &mut pen).ok()?;
    // flush any remaining open contour
    if !pen.current.points.is_empty() {
        pen.contours.push(pen.current);
    }
    if pen.contours.is_empty() {
        None
    } else {
        Some(pen.contours)
    }
}

// ── Signal 1: Aperture openness ───────────────────────────────────────────────
//
// For 'e': measure how open the counter is.
// We find the bounding box of the outermost contour, then look at the gap on
// the right side of the counter. Open apertures have a large vertical gap
// between the terminal endpoints of the inner counter.

fn measure_aperture(font: &FontRef) -> Option<f64> {
    // Try 'e' first, fall back to 'c'
    let contours = get_glyph_contours(font, 'e')
        .or_else(|| get_glyph_contours(font, 'c'))?;

    if contours.len() < 2 {
        // 'e' should have at least 2 contours (outer + counter)
        // If only 1, try measuring the opening on that contour
        return measure_single_contour_aperture(&contours[0]);
    }

    // The inner contour (counter) is usually the smaller one
    let inner = contours
        .iter()
        .min_by(|a, b| {
            let area_a = contour_area(a).abs();
            let area_b = contour_area(b).abs();
            area_a.partial_cmp(&area_b).unwrap_or(std::cmp::Ordering::Equal)
        })?;

    let outer = contours
        .iter()
        .max_by(|a, b| {
            let area_a = contour_area(a).abs();
            let area_b = contour_area(b).abs();
            area_a.partial_cmp(&area_b).unwrap_or(std::cmp::Ordering::Equal)
        })?;

    // Get bounding heights
    let outer_bbox = bounding_box(outer);
    let total_height = outer_bbox.max_y - outer_bbox.min_y;
    if total_height < 1.0 { return None; }

    // Find the rightmost gap in the inner contour
    // Sort inner points by x coordinate, look at the rightmost cluster
    let inner_bbox = bounding_box(inner);
    let right_threshold = inner_bbox.max_x - (inner_bbox.max_x - inner_bbox.min_x) * 0.15;

    // Points near the right edge of the counter
    let right_points: Vec<&Point> = inner.points.iter()
        .filter(|p| p.x >= right_threshold)
        .collect();

    if right_points.is_empty() { return None; }

    let min_y = right_points.iter().map(|p| p.y).fold(f32::INFINITY, f32::min);
    let max_y = right_points.iter().map(|p| p.y).fold(f32::NEG_INFINITY, f32::max);

    // The gap is the vertical span of right-edge points relative to total height
    // A closed 'e' has right points spanning most of the counter height
    // An open 'e' has right points clustered at just the top or bottom
    let gap_span = max_y - min_y;
    let inner_height = inner_bbox.max_y - inner_bbox.min_y;

    if inner_height < 1.0 { return None; }

    // Openness: 1.0 = fully open (right points clustered), 0.0 = fully closed
    let openness = 1.0 - (gap_span / inner_height).min(1.0) as f64;
    Some(openness.max(0.0))
}

/// Even-odd point-in-polygon over every contour of a glyph.
fn inside(contours: &[Contour], x: f32, y: f32) -> bool {
    let mut hit = false;
    for c in contours {
        let pts = &c.points;
        let n = pts.len();
        if n < 3 { continue; }
        let mut j = n - 1;
        for i in 0..n {
            let (pi, pj) = (&pts[i], &pts[j]);
            if (pi.y > y) != (pj.y > y) && x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x {
                hit = !hit;
            }
            j = i;
        }
    }
    hit
}

/// Total ink width along a horizontal line through the glyph.
fn ink_width(contours: &[Contour], y: f32, min_x: f32, max_x: f32) -> f32 {
    let steps = 300;
    let dx = (max_x - min_x) / steps as f32;
    (0..steps).filter(|i| inside(contours, min_x + dx * (*i as f32 + 0.5), y)).count() as f32 * dx
}

/// The font declares fixed pitch (post.isFixedPitch), or its lowercase
/// advances are all equal.
fn is_monospaced(font: &FontRef) -> bool {
    use skrifa::raw::TableProvider;
    if font.post().map(|p| p.is_fixed_pitch() != 0).unwrap_or(false) {
        return true;
    }
    let metrics = font.glyph_metrics(skrifa::instance::Size::unscaled(), skrifa::instance::LocationRef::default());
    let charmap = font.charmap();
    let advances: Vec<f32> = ['i', 'm', 'l', 'w']
        .iter()
        .filter_map(|c| charmap.map(*c).and_then(|g| metrics.advance_width(g)))
        .collect();
    advances.len() == 4 && advances.iter().all(|a| (a - advances[0]).abs() < 0.5)
}

/// Serif test on 'l' (fallback 'I'): ink just above the baseline vs ink at
/// mid-height. A serif foot is much wider than the stem; a sans foot isn't.
/// Slab and bracketed serifs both read wide; flared (Optima) reads sans.
fn measure_serif(font: &FontRef) -> Option<bool> {
    // Monospaced faces do the Mono job and aren't judged as serif or sans for
    // pairing. Their 'l' carries a foot bar that reads as a serif.
    if is_monospaced(font) {
        return Some(false);
    }
    let contours = get_glyph_contours(font, 'l').or_else(|| get_glyph_contours(font, 'I'))?;
    let pts: Vec<&Point> = contours.iter().flat_map(|c| c.points.iter()).collect();
    if pts.is_empty() { return None; }
    let (min_x, max_x) = pts.iter().fold((f32::MAX, f32::MIN), |(a, b), p| (a.min(p.x), b.max(p.x)));
    let (min_y, max_y) = pts.iter().fold((f32::MAX, f32::MIN), |(a, b), p| (a.min(p.y), b.max(p.y)));
    let h = max_y - min_y;
    if h < 1.0 { return None; }
    let stem = ink_width(&contours, min_y + h * 0.5, min_x, max_x);
    if stem < 1.0 { return None; }
    // Several heights: Didone hairline serifs are thinner than any one sample.
    let foot = [0.004_f32, 0.01, 0.02, 0.035]
        .iter()
        .map(|f| ink_width(&contours, min_y + h * f, min_x, max_x))
        .fold(0.0_f32, f32::max);
    Some(foot / stem > 1.6)
}

/// Aperture of 'c': how far apart the two stroke ends sit. From mid-height,
/// cast up and down at a few columns on the right side and measure the empty
/// run before ink; average, normalised by glyph height. Open (Gill, Verdana)
/// reads high, closed (Helvetica) low. Replaces the old 'e' counter check,
/// which measured the eye of the e, closed in every typeface.
fn measure_c_aperture(font: &FontRef) -> Option<f64> {
    let contours = get_glyph_contours(font, 'c')?;
    let all: Vec<&Point> = contours.iter().flat_map(|c| c.points.iter()).collect();
    if all.is_empty() { return None; }
    let (min_x, max_x) = all.iter().fold((f32::MAX, f32::MIN), |(a, b), p| (a.min(p.x), b.max(p.x)));
    let (min_y, max_y) = all.iter().fold((f32::MAX, f32::MIN), |(a, b), p| (a.min(p.y), b.max(p.y)));
    let (w, h) = (max_x - min_x, max_y - min_y);
    if w < 1.0 || h < 1.0 { return None; }
    let mid = min_y + h / 2.0;
    let step = h / 400.0;
    let mut sum = 0.0;
    let mut n = 0.0;
    for frac in [0.70_f32, 0.78, 0.86] {
        let x = min_x + w * frac;
        if inside(&contours, x, mid) { continue; } // column runs through ink at mid-height
        let mut up = mid;
        while up < max_y && !inside(&contours, x, up) { up += step; }
        let mut down = mid;
        while down > min_y && !inside(&contours, x, down) { down -= step; }
        sum += ((up - down) / h) as f64;
        n += 1.0;
    }
    (n > 0.0).then(|| sum / n)
}

fn measure_single_contour_aperture(contour: &Contour) -> Option<f64> {
    // For single-contour glyphs, look for a gap (discontinuity or narrow passage)
    let bbox = bounding_box(contour);
    let total_height = bbox.max_y - bbox.min_y;
    if total_height < 1.0 { return None; }

    // Find the rightmost point and measure vertical coverage near it
    let right_threshold = bbox.max_x - (bbox.max_x - bbox.min_x) * 0.1;
    let right_points: Vec<&Point> = contour.points.iter()
        .filter(|p| p.x >= right_threshold)
        .collect();

    if right_points.len() < 2 { return Some(0.8); } // very few right points = likely open

    let min_y = right_points.iter().map(|p| p.y).fold(f32::INFINITY, f32::min);
    let max_y = right_points.iter().map(|p| p.y).fold(f32::NEG_INFINITY, f32::max);
    let coverage = (max_y - min_y) / total_height;

    Some((1.0 - coverage as f64).max(0.0))
}

// ── Signal 2: Stress angle ────────────────────────────────────────────────────
//
// Analyze the 'o' glyph: find the thinnest points on the outer contour.
// The angle from center to thinnest point indicates stress direction.

fn measure_stress_angle(font: &FontRef) -> Option<f64> {
    let contours = get_glyph_contours(font, 'o')?;

    // Use the largest contour (outer)
    let outer = contours
        .iter()
        .max_by(|a, b| {
            let area_a = contour_area(a).abs();
            let area_b = contour_area(b).abs();
            area_a.partial_cmp(&area_b).unwrap_or(std::cmp::Ordering::Equal)
        })?;

    if outer.points.len() < 16 { return None; }

    let bbox = bounding_box(outer);
    let cx = (bbox.min_x + bbox.max_x) / 2.0;
    let cy = (bbox.min_y + bbox.max_y) / 2.0;

    // For each point on the outer contour, measure the "thickness" at that angle
    // by finding the distance to the opposite side of the contour.
    // The thinnest points tell us the stress angle.

    let n = outer.points.len();
    let mut min_width = f32::INFINITY;
    let mut min_angle = 0.0f32;

    // Sample opposing points: for each point, find the point roughly 180° across
    for i in 0..n {
        let p = &outer.points[i];

        // Find the opposing point (approximately 180° around the contour)
        let opp_idx = (i + n / 2) % n;
        let opp = &outer.points[opp_idx];

        let dx = p.x - opp.x;
        let dy = p.y - opp.y;
        let width = (dx * dx + dy * dy).sqrt();

        if width < min_width {
            min_width = width;
            // Angle from center to this point (the thinnest axis)
            let ax = p.x - cx;
            let ay = p.y - cy;
            min_angle = ay.atan2(ax).to_degrees();
        }
    }

    // Normalize angle to 0–90° range (we care about the axis, not direction)
    let mut angle = min_angle.abs() % 180.0;
    if angle > 90.0 {
        angle = 180.0 - angle;
    }

    Some(angle as f64)
}

// ── Signal 3: Stroke contrast ─────────────────────────────────────────────────
//
// Ratio of thickest to thinnest stroke in 'o' or 'O'.
// High contrast → "contrasting", low → "linear"

fn measure_stroke_contrast(font: &FontRef) -> Option<f64> {
    let contours = get_glyph_contours(font, 'O')
        .or_else(|| get_glyph_contours(font, 'o'))?;

    if contours.len() < 2 { return None; }

    // Sort by area: largest = outer, second = inner
    let mut sorted: Vec<&Contour> = contours.iter().collect();
    sorted.sort_by(|a, b| {
        contour_area(b).abs().partial_cmp(&contour_area(a).abs())
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let outer = sorted[0];
    let inner = sorted[1];

    if outer.points.len() < 16 || inner.points.len() < 16 { return None; }

    // Sample stroke widths at various angles around the glyph
    let outer_bbox = bounding_box(outer);
    let cx = (outer_bbox.min_x + outer_bbox.max_x) / 2.0;
    let cy = (outer_bbox.min_y + outer_bbox.max_y) / 2.0;

    let mut widths: Vec<f32> = Vec::new();

    // Cast rays from center at various angles, find distance between
    // outer and inner contour intersections
    for deg in (0..360).step_by(15) {
        let angle = (deg as f32).to_radians();
        let dx = angle.cos();
        let dy = angle.sin();

        let outer_dist = ray_contour_distance(cx, cy, dx, dy, outer);
        let inner_dist = ray_contour_distance(cx, cy, dx, dy, inner);

        if let (Some(od), Some(id)) = (outer_dist, inner_dist) {
            let thickness = (od - id).abs();
            if thickness > 0.5 {
                widths.push(thickness);
            }
        }
    }

    if widths.len() < 4 { return None; }

    let max_w = widths.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    let min_w = widths.iter().cloned().fold(f32::INFINITY, f32::min);

    if min_w < 0.5 { return None; }

    Some((max_w / min_w) as f64)
}

/// Cast a ray from (ox, oy) in direction (dx, dy) and find the closest
/// intersection distance with the contour.
fn ray_contour_distance(ox: f32, oy: f32, dx: f32, dy: f32, contour: &Contour) -> Option<f32> {
    let pts = &contour.points;
    let n = pts.len();
    if n < 3 { return None; }

    let mut best: Option<f32> = None;

    for i in 0..n {
        let j = (i + 1) % n;
        let (p1, p2) = (&pts[i], &pts[j]);

        // Line segment: p1 + s*(p2-p1)
        // Ray: o + t*(dx, dy)
        let ex = p2.x - p1.x;
        let ey = p2.y - p1.y;

        let denom = dx * ey - dy * ex;
        if denom.abs() < 1e-6 { continue; }

        let t = ((p1.x - ox) * ey - (p1.y - oy) * ex) / denom;
        let s = ((p1.x - ox) * dy - (p1.y - oy) * dx) / denom;

        if t > 0.0 && s >= 0.0 && s <= 1.0 {
            match best {
                None => best = Some(t),
                Some(b) if t < b => best = Some(t),
                _ => {}
            }
        }
    }

    best
}

// ── Signal 4: Construction geometry ───────────────────────────────────────────
//
// Measure how circular the 'o' is. Perfect circle = geometric.

fn measure_circularity(font: &FontRef) -> Option<f64> {
    let contours = get_glyph_contours(font, 'o')?;

    let outer = contours
        .iter()
        .max_by(|a, b| {
            contour_area(a).abs().partial_cmp(&contour_area(b).abs())
                .unwrap_or(std::cmp::Ordering::Equal)
        })?;

    if outer.points.len() < 16 { return None; }

    let bbox = bounding_box(outer);
    let cx = (bbox.min_x + bbox.max_x) / 2.0;
    let cy = (bbox.min_y + bbox.max_y) / 2.0;
    let w = bbox.max_x - bbox.min_x;
    let h = bbox.max_y - bbox.min_y;

    if w < 1.0 || h < 1.0 { return None; }

    // Aspect ratio: 1.0 = perfect circle
    let aspect = if w > h { h / w } else { w / h };

    // Measure deviation from a perfect ellipse
    let rx = w / 2.0;
    let ry = h / 2.0;

    let mut total_deviation = 0.0f64;
    let mut count = 0;

    for p in &outer.points {
        let nx = (p.x - cx) / rx;
        let ny = (p.y - cy) / ry;
        // For a perfect ellipse, nx² + ny² = 1.0
        let r = (nx * nx + ny * ny) as f64;
        let dev = (r - 1.0).abs();
        total_deviation += dev;
        count += 1;
    }

    if count == 0 { return None; }

    let avg_deviation = total_deviation / count as f64;

    // Combine aspect ratio and deviation into a circularity score
    // High score = more geometric (circular/elliptical)
    let score = (aspect as f64) * (1.0 - avg_deviation.min(1.0));
    Some(score.max(0.0).min(1.0))
}

// ── Name keyword fallback ─────────────────────────────────────────────────────

fn name_keyword_skeleton(family_name: &str) -> Option<&'static str> {
    let n = family_name.to_lowercase();

    // Dynamic: humanist tradition
    let dynamic_keywords = [
        "garamond", "caslon", "bembo", "palatino", "jenson",
        "humanist", "gill", "frutiger", "optima", "lucida",
        "calibri", "candara", "corbel", "myriad", "syntax",
    ];
    for kw in &dynamic_keywords {
        if n.contains(kw) { return Some("dynamic"); }
    }

    // Rational: transitional + modern
    let rational_keywords = [
        "bodoni", "didot", "walbaum", "modern", "grotesk",
        "helvetica", "arial", "univers", "akzidenz", "roboto",
        "baskerville", "times", "transitional",
    ];
    for kw in &rational_keywords {
        if n.contains(kw) { return Some("rational"); }
    }

    // Geometric
    let geometric_keywords = [
        "futura", "avenir", "century gothic", "montserrat",
        "geometric", "gotham", "proxima", "poppins", "comfortaa",
        "circular", "brandon",
    ];
    for kw in &geometric_keywords {
        if n.contains(kw) { return Some("geometric"); }
    }

    None
}

// ── Geometry helpers ──────────────────────────────────────────────────────────

struct BBox {
    min_x: f32,
    max_x: f32,
    min_y: f32,
    max_y: f32,
}

fn bounding_box(contour: &Contour) -> BBox {
    let mut bb = BBox {
        min_x: f32::INFINITY,
        max_x: f32::NEG_INFINITY,
        min_y: f32::INFINITY,
        max_y: f32::NEG_INFINITY,
    };
    for p in &contour.points {
        bb.min_x = bb.min_x.min(p.x);
        bb.max_x = bb.max_x.max(p.x);
        bb.min_y = bb.min_y.min(p.y);
        bb.max_y = bb.max_y.max(p.y);
    }
    bb
}

fn contour_area(contour: &Contour) -> f64 {
    let pts = &contour.points;
    let n = pts.len();
    if n < 3 { return 0.0; }
    let mut area = 0.0f64;
    for i in 0..n {
        let j = (i + 1) % n;
        area += (pts[i].x as f64) * (pts[j].y as f64);
        area -= (pts[j].x as f64) * (pts[i].y as f64);
    }
    area / 2.0
}

// ── Main classifier ──────────────────────────────────────────────────────────

pub fn classify_font(file_path: &Path, family_name: &str) -> ClassificationResult {
    let default = ClassificationResult {
        skeleton: "unknown".into(),
        flesh_contrast: "linear".into(),
        flesh_serif: 0,
        stroke_contrast_ratio: None,
        serif: None,
        reason: "Could not parse font file".into(),
    };

    let ext = file_path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    // skrifa handles TTF, OTF, and some WOFF; skip woff2
    if !matches!(ext.as_deref(), Some("ttf") | Some("otf") | Some("ttc")) {
        // Try name keywords for non-parseable formats
        let skeleton = name_keyword_skeleton(family_name).unwrap_or("unknown");
        return ClassificationResult {
            skeleton: skeleton.into(),
            flesh_contrast: "linear".into(),
            flesh_serif: 0,
            stroke_contrast_ratio: None,
            serif: None,
            reason: format!("Non-parseable format, name fallback → {}", skeleton),
        };
    }

    let data = match std::fs::read(file_path) {
        Ok(d) => d,
        Err(_) => return default,
    };

    // from_index(0) reads plain fonts and the first face of a .ttc collection
    let font = match FontRef::from_index(&data, 0) {
        Ok(f) => f,
        Err(_) => return default,
    };

    // Gather all signals
    let aperture = measure_aperture(&font);
    let stress = measure_stress_angle(&font);
    let contrast_ratio = measure_stroke_contrast(&font);
    let circularity = measure_circularity(&font);

    // Determine flesh_contrast from stroke contrast ratio
    let flesh_contrast = match contrast_ratio {
        Some(r) if r > 1.5 => "contrasting",
        _ => "linear",
    };

    // Detect serifs from the category (already classified in the DB)
    // We'll leave flesh_serif as-is from the DB; the caller merges it
    let flesh_serif = 0; // will be set from DB category

    // ── Rules (v3) ─────────────────────────────────────────────────────────
    // Calibrated on skeleton_answer_set, checked on its held-out half.
    // Low-contrast faces split on aperture (open = dynamic, closed = rational)
    // unless the 'o' is near-circular (geometric). High-contrast faces are
    // dynamic unless the contrast is extreme (Didone = rational). Stress angle
    // and the old 'e' aperture proved to be noise and no longer vote.
    let c_aperture = measure_c_aperture(&font);
    let _ = (aperture, stress); // still measured for future signals; no vote
    let mut reasons: Vec<String> = Vec::new();
    let skeleton: &str = match (contrast_ratio, c_aperture) {
        (Some(contrast), Some(ap)) if contrast < 1.5 => {
            reasons.push(format!("low contrast {contrast:.2}"));
            if contrast < 1.25 && circularity.is_some_and(|c| c >= 0.96) {
                reasons.push(format!("circular o {:.2}", circularity.unwrap()));
                "geometric"
            } else if ap >= 0.55 {
                reasons.push(format!("open aperture {ap:.2}"));
                "dynamic"
            } else {
                reasons.push(format!("closed aperture {ap:.2}"));
                "rational"
            }
        }
        (Some(contrast), _) if contrast > 5.0 => {
            reasons.push(format!("extreme contrast {contrast:.2} (Didone)"));
            "rational"
        }
        (Some(contrast), _) => {
            reasons.push(format!("modulated stroke {contrast:.2}"));
            "dynamic"
        }
        _ => {
            reasons.push("no outline signals".into());
            name_keyword_skeleton(family_name).unwrap_or("unknown")
        }
    };

    let reason = if reasons.is_empty() {
        format!("No outline signals available → {}", skeleton)
    } else {
        format!("{} → {}", reasons.join(", "), skeleton)
    };

    ClassificationResult {
        skeleton: skeleton.into(),
        flesh_contrast: flesh_contrast.into(),
        flesh_serif,
        stroke_contrast_ratio: contrast_ratio,
        serif: measure_serif(&font),
        reason,
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    // A ".woff2" path is treated as non-parseable, so classification falls back
    // to name keywords without ever reading the file (path need not exist).
    fn classify_by_name(family: &str) -> ClassificationResult {
        classify_font(Path::new("/nonexistent/font.woff2"), family)
    }

    #[test]
    fn name_keyword_dynamic() {
        assert_eq!(classify_by_name("Garamond").skeleton, "dynamic");
    }

    #[test]
    fn name_keyword_rational() {
        assert_eq!(classify_by_name("Helvetica Neue").skeleton, "rational");
    }

    #[test]
    fn name_keyword_geometric() {
        assert_eq!(classify_by_name("Futura").skeleton, "geometric");
    }

    #[test]
    fn unknown_name_is_unknown_skeleton() {
        assert_eq!(classify_by_name("Zzqwx Plain").skeleton, "unknown");
    }

    // ── Skeleton answer set (system fonts with an established skeleton) ────
    //   cd core && cargo test --lib skeleton_answer_set -- --ignored --nocapture
    const ANSWERS: &[(&str, &str, &str)] = &[
        ("/System/Library/Fonts/Supplemental/GillSans.ttc", "Gill Sans", "dynamic"),
        ("/System/Library/Fonts/Palatino.ttc", "Palatino", "dynamic"),
        ("/System/Library/Fonts/Supplemental/Hoefler Text.ttc", "Hoefler Text", "dynamic"),
        ("/System/Library/Fonts/Optima.ttc", "Optima", "dynamic"),
        ("/System/Library/Fonts/Supplemental/Verdana.ttf", "Verdana", "dynamic"),
        ("/System/Library/Fonts/Supplemental/Trebuchet MS.ttf", "Trebuchet MS", "dynamic"),
        ("/System/Library/Fonts/Supplemental/Seravek.ttc", "Seravek", "dynamic"),
        ("/System/Library/Fonts/Supplemental/Iowan Old Style.ttc", "Iowan Old Style", "dynamic"),
        ("/System/Library/Fonts/Supplemental/BigCaslon.ttf", "Big Caslon", "dynamic"),
        ("/System/Library/Fonts/Helvetica.ttc", "Helvetica", "rational"),
        ("/System/Library/Fonts/HelveticaNeue.ttc", "Helvetica Neue", "rational"),
        ("/System/Library/Fonts/Supplemental/Didot.ttc", "Didot", "rational"),
        ("/System/Library/Fonts/Supplemental/Bodoni 72.ttc", "Bodoni 72", "rational"),
        ("/System/Library/Fonts/Supplemental/Arial.ttf", "Arial", "rational"),
        ("/System/Library/Fonts/Supplemental/Futura.ttc", "Futura", "geometric"),
        ("/System/Library/Fonts/Avenir.ttc", "Avenir", "geometric"),
        ("/System/Library/Fonts/Avenir Next.ttc", "Avenir Next", "geometric"),
    ];

    /// Never used to set thresholds. Reported separately to catch overfitting.
    const HOLDOUT: &[(&str, &str)] = &[
        ("/System/Library/Fonts/LucidaGrande.ttc", "dynamic"),
        ("/System/Library/Fonts/Supplemental/Tahoma.ttf", "dynamic"),
        ("~/Library/Fonts/TestSignifier-Regular.otf", "dynamic"),
        ("/System/Library/Fonts/SFNS.ttf", "rational"),
        ("~/Library/Fonts/TestSöhne-Buch.otf", "rational"),
        ("~/Library/Fonts/NeueMontreal-Regular.otf", "rational"),
        ("~/Library/Fonts/TestFoundersGrotesk-Regular.otf", "rational"),
        ("~/Library/Fonts/TestUntitledSans-Regular.otf", "rational"),
        ("~/Library/Fonts/Brown-Regular.otf", "geometric"),
        ("~/Library/Fonts/PlusJakartaSans-Regular.otf", "geometric"),
    ];

    #[test]
    #[ignore]
    fn skeleton_holdout() {
        let home = std::env::var("HOME").unwrap();
        let (mut right, mut total) = (0, 0);
        for (path, want) in HOLDOUT {
            let path = path.replacen('~', &home, 1);
            if !Path::new(&path).exists() { println!("skip   {path}"); continue; }
            total += 1;
            let r = classify_font(Path::new(&path), "Zzz");
            if r.skeleton == *want { right += 1; }
            println!("{:<6} {:<48} want {:<9} got {:<9} serif {:<5} {}", if r.skeleton == *want { "ok" } else { "MISS" },
                path.rsplit('/').next().unwrap(), want, r.skeleton, r.serif.map(|b| b.to_string()).unwrap_or("-".into()), r.reason);
        }
        println!("\nholdout: {right} of {total}");
    }

    #[test]
    #[ignore]
    fn skeleton_answer_set() {
        let mut right = 0;
        for (path, family, want) in ANSWERS {
            // Neutral name: measure the outlines alone. Most user fonts aren't in
            // the name-keyword list, so this is the accuracy that matters.
            let _ = family;
            let r = classify_font(Path::new(path), "Zzz");
            let ok = r.skeleton == *want;
            if ok { right += 1; }
            let data = std::fs::read(path).unwrap();
            let f = FontRef::from_index(&data, 0).unwrap();
            println!("{:<6} {:<16} want {:<9} got {:<9} serif {:<5} capert {:>5} contrast {:>5} circ {:>5} stress {:>4}",
                if ok { "ok" } else { "MISS" }, family, want, r.skeleton,
                r.serif.map(|b| b.to_string()).unwrap_or("-".into()),
                measure_c_aperture(&f).map(|v| format!("{v:.2}")).unwrap_or("-".into()),
                measure_stroke_contrast(&f).map(|v| format!("{v:.2}")).unwrap_or("-".into()),
                measure_circularity(&f).map(|v| format!("{v:.2}")).unwrap_or("-".into()),
                measure_stress_angle(&f).map(|v| format!("{v:.0}")).unwrap_or("-".into()));
        }
        println!("\nskeleton answer set: {right} of {}", ANSWERS.len());
    }
}
