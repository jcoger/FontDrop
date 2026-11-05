//! Extended font metrics for pairing signals.
//!
//! Extracts optical role, superfamily membership, spacing personality,
//! and proportional harmony data from font files.

use std::path::Path;

use skrifa::{FontRef, MetadataProvider};
use skrifa::raw::TableProvider;
use serde::Serialize;

// ── Result type ───────────────────────────────────────────────────────────────

#[derive(Serialize, Clone, Debug, Default)]
pub struct ExtendedMetrics {
    pub optical_role: String,
    pub superfamily_group: Option<String>,
    pub superfamily_role: Option<String>,
    pub cap_height_ratio: Option<f64>,
    pub x_height_ratio: Option<f64>,
    pub ascender_descender_ratio: Option<f64>,
    pub weight_range_min: Option<i32>,
    pub weight_range_max: Option<i32>,
    pub spacing_personality: Option<String>,
    pub width_class: Option<String>,
}

// ── Signal 1: Optical role detection ──────────────────────────────────────────

fn detect_optical_role(family_name: &str, stroke_contrast: Option<f64>, x_height: Option<f64>) -> String {
    let n = family_name.to_lowercase();

    // Primary: name keywords
    let name_keywords: &[(&[&str], &str)] = &[
        (&["display", "deck", "banner", "poster", "headline"], "display"),
        (&["text", "reading", "book", "small"], "text"),
        (&["caption", "micro", "fine"], "caption"),
        (&["mono", "code", "terminal"], "mono"),
    ];

    for (keywords, role) in name_keywords {
        for kw in *keywords {
            if n.contains(kw) {
                return role.to_string();
            }
        }
    }

    // Secondary: metric heuristics
    if let Some(sc) = stroke_contrast {
        if sc > 2.0 { return "display".into(); }
    }
    if let Some(xh) = x_height {
        if xh < 0.55 { return "display".into(); }
        if xh > 0.72 { return "text".into(); }
    }

    "general".into()
}

// ── Signal 2: Superfamily detection ───────────────────────────────────────────

/// Known superfamily lookup table.
const SUPERFAMILIES: &[(&str, &[&str])] = &[
    ("IBM Plex", &["IBM Plex Serif", "IBM Plex Sans", "IBM Plex Mono", "IBM Plex Sans Condensed"]),
    ("Source", &["Source Serif", "Source Sans", "Source Code", "Source Serif Pro", "Source Sans Pro", "Source Code Pro", "Source Serif 4", "Source Sans 3"]),
    ("PT", &["PT Serif", "PT Sans", "PT Mono", "PT Sans Narrow"]),
    ("Roboto", &["Roboto", "Roboto Slab", "Roboto Mono", "Roboto Condensed", "Roboto Flex"]),
    ("Noto", &["Noto Serif", "Noto Sans", "Noto Sans Mono"]),
    ("DM", &["DM Sans", "DM Serif Display", "DM Serif Text", "DM Mono"]),
    ("Libre", &["Libre Baskerville", "Libre Franklin", "Libre Caslon Text", "Libre Caslon Display"]),
    ("Freight", &["Freight Text", "Freight Sans", "Freight Display", "Freight Micro", "Freight Big"]),
    ("Alegreya", &["Alegreya", "Alegreya Sans", "Alegreya SC", "Alegreya Sans SC"]),
    ("FF Meta", &["FF Meta", "FF Meta Serif"]),
    ("Cormorant", &["Cormorant", "Cormorant Garamond", "Cormorant Infant", "Cormorant SC"]),
    ("Spectral", &["Spectral", "Spectral SC"]),
    ("Playfair", &["Playfair Display", "Playfair Display SC", "Playfair"]),
    ("Chivo", &["Chivo", "Chivo Mono"]),
    ("Piazzolla", &["Piazzolla", "Piazzolla SC"]),
    ("Work Sans", &["Work Sans"]),
    ("Fira", &["Fira Sans", "Fira Code", "Fira Mono"]),
    ("Merriweather", &["Merriweather", "Merriweather Sans"]),
    ("Josefin", &["Josefin Sans", "Josefin Slab"]),
    ("Nunito", &["Nunito", "Nunito Sans"]),
    ("Raleway", &["Raleway"]), // no superfamily partner
    ("Crimson", &["Crimson Text", "Crimson Pro"]),
    ("Barlow", &["Barlow", "Barlow Condensed", "Barlow Semi Condensed"]),
    ("Archivo", &["Archivo", "Archivo Narrow", "Archivo Black"]),
    ("Ubuntu", &["Ubuntu", "Ubuntu Mono", "Ubuntu Condensed"]),
    ("Iowan", &["Iowan Old Style"]),
    ("Space", &["Space Grotesk", "Space Mono"]),
    ("Instrument", &["Instrument Sans", "Instrument Serif"]),
    ("Geist", &["Geist", "Geist Mono"]),
];

fn detect_superfamily_role(family_name: &str) -> &'static str {
    let n = family_name.to_lowercase();
    if n.contains("mono") || n.contains("code") { return "mono"; }
    if n.contains("display") || n.contains("headline") || n.contains("banner") { return "display"; }
    if n.contains("serif") && !n.contains("sans") { return "serif"; }
    if n.contains("sans") || n.contains("grotesk") { return "sans"; }
    if n.contains("slab") { return "serif"; }
    if n.contains("condensed") || n.contains("narrow") { return "sans"; }
    "sans" // default for fonts like "Roboto" (which is sans)
}

/// Check if a font belongs to a known superfamily.
/// Returns (group_name, role) or None.
pub fn detect_superfamily(family_name: &str) -> Option<(String, String)> {
    let n_lower = family_name.to_lowercase();

    // Pass 1: Known superfamily lookup
    for (group, members) in SUPERFAMILIES {
        for member in *members {
            if member.to_lowercase() == n_lower {
                let role = detect_superfamily_role(family_name);
                return Some((group.to_string(), role.to_string()));
            }
        }
    }

    // Pass 3: Name prefix cross-reference
    // Check for common patterns: "X Sans", "X Serif", "X Slab", "X Mono"
    let suffixes = [" sans", " serif", " slab", " mono", " display", " text", " code"];
    for suffix in &suffixes {
        if n_lower.ends_with(suffix) {
            let base = &family_name[..family_name.len() - suffix.len()];
            if base.len() >= 3 {
                let role = detect_superfamily_role(family_name);
                return Some((base.to_string(), role.to_string()));
            }
        }
    }

    None
}

// ── Signal 3: Proportional harmony metrics ────────────────────────────────────

fn extract_proportional_metrics(data: &[u8]) -> (Option<f64>, Option<f64>, Option<f64>) {
    let font = match FontRef::from_index(data, 0) {
        Ok(f) => f,
        Err(_) => return (None, None, None),
    };

    let head = font.head().ok();
    let upm = head.map(|h| h.units_per_em() as f64).unwrap_or(1000.0);
    if upm < 1.0 { return (None, None, None); }

    let os2 = font.os2().ok();

    // Cap height ratio
    let cap_height_ratio = os2.as_ref().and_then(|o| {
        let cap = o.s_cap_height().unwrap_or(0) as f64;
        if cap > 0.0 { Some(cap / upm) } else { None }
    });

    // x-height ratio
    let x_height_ratio = os2.as_ref().and_then(|o| {
        let xh = o.sx_height().unwrap_or(0) as f64;
        if xh > 0.0 { Some(xh / upm) } else { None }
    });

    // Ascender/descender ratio
    let asc_desc_ratio = os2.as_ref().map(|o| {
        let asc = o.s_typo_ascender() as f64;
        let desc = o.s_typo_descender() as f64; // negative value
        (asc - desc) / upm
    });

    (cap_height_ratio, x_height_ratio, asc_desc_ratio)
}

// ── Signal 4: Spacing personality ─────────────────────────────────────────────

fn detect_spacing_personality(data: &[u8]) -> Option<String> {
    let font = match FontRef::from_index(data, 0) {
        Ok(f) => f,
        Err(_) => return None,
    };

    let head = font.head().ok()?;
    let upm = head.units_per_em() as f64;
    if upm < 1.0 { return None; }

    let charmap = font.charmap();
    let hmtx = font.hmtx().ok()?;

    // Compute average advance width for lowercase a-z
    let mut total_advance = 0.0f64;
    let mut count = 0u32;

    for ch in 'a'..='z' {
        if let Some(gid) = charmap.map(ch) {
            let advance = hmtx.advance(gid).unwrap_or(0) as f64;
            total_advance += advance;
            count += 1;
        }
    }

    if count < 10 { return None; } // not enough glyphs

    let avg_advance = total_advance / count as f64;
    let normalized = avg_advance / upm;

    // Classify spacing personality based on normalized average advance
    // Tight fonts: < 0.45 normalized advance (narrow)
    // Normal: 0.45 - 0.60
    // Open: > 0.60 (wide)
    let personality = if normalized < 0.45 {
        "tight"
    } else if normalized <= 0.60 {
        "normal"
    } else {
        "open"
    };

    Some(personality.to_string())
}

// ── Main extraction function ──────────────────────────────────────────────────

pub fn extract_extended_metrics(
    file_path: &Path,
    family_name: &str,
    stroke_contrast: Option<f64>,
    existing_x_height: Option<f64>,
) -> ExtendedMetrics {
    let ext = file_path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    if !matches!(ext.as_deref(), Some("ttf") | Some("otf")) {
        // Non-parseable format — name-based detection only
        let optical_role = detect_optical_role(family_name, stroke_contrast, existing_x_height);
        let sf = detect_superfamily(family_name);
        return ExtendedMetrics {
            optical_role,
            superfamily_group: sf.as_ref().map(|(g, _)| g.clone()),
            superfamily_role: sf.map(|(_, r)| r),
            ..Default::default()
        };
    }

    let data = match std::fs::read(file_path) {
        Ok(d) => d,
        Err(_) => {
            let optical_role = detect_optical_role(family_name, stroke_contrast, existing_x_height);
            let sf = detect_superfamily(family_name);
            return ExtendedMetrics {
                optical_role,
                superfamily_group: sf.as_ref().map(|(g, _)| g.clone()),
                superfamily_role: sf.map(|(_, r)| r),
                ..Default::default()
            };
        }
    };

    let (cap_height, x_height, asc_desc) = extract_proportional_metrics(&data);
    let spacing = detect_spacing_personality(&data);
    let optical_role = detect_optical_role(
        family_name,
        stroke_contrast,
        x_height.or(existing_x_height),
    );
    let sf = detect_superfamily(family_name);

    // Weight range + width class from OS/2
    let font = FontRef::from_index(&data, 0).ok();
    let os2 = font.as_ref().and_then(|f| f.os2().ok());

    let weight = os2.as_ref()
        .map(|o| o.us_weight_class() as i32)
        .unwrap_or(400);

    let width_class = os2.as_ref().map(|o| {
        let w = o.us_width_class();
        match w {
            1..=3 => "condensed",
            4..=6 => "normal",
            7..=9 => "expanded",
            _ => "normal",
        }
        .to_string()
    });

    ExtendedMetrics {
        optical_role,
        superfamily_group: sf.as_ref().map(|(g, _)| g.clone()),
        superfamily_role: sf.map(|(_, r)| r),
        cap_height_ratio: cap_height,
        x_height_ratio: x_height,
        ascender_descender_ratio: asc_desc,
        weight_range_min: Some(weight),
        weight_range_max: Some(weight),
        spacing_personality: spacing,
        width_class,
    }
}
