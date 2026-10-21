//! COPY of src-tauri/src/pairing.rs (scoring, unfit_for_reading, bucket_pairs),
//! with the Tauri command, serde and the unit tests removed. Spike only: in the
//! real port this file moves to core/ and src-tauri depends on core.

use rusqlite::Connection;
use std::collections::HashSet;
/// Placeholder foundry assigned by Google Fonts enrichment when no specific
/// foundry/designer is known (see google_fonts.rs). It marks a font as
/// "enriched" but carries no real shared-origin signal, so the pairing scorer
/// must NOT treat two fonts sharing this value as a meaningful shared foundry.
const GENERIC_FOUNDRY: &str = "Google Fonts";

// ── Output type ───────────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
pub struct PairScore {
    pub font_id: String,
    pub score: u8,
    /// Unrounded score, used to rank so candidates don't tie.
    pub precise: f32,
    pub pair_type: String, // "harmonious" | "bold" | "conflict" | "uncertain" | "superfamily"
    pub reason: String,
    pub evidence: Vec<Evidence>,
}

/// One piece of reasoning behind a score: which lens, what was measured, who
/// says it matters and how strongly. Shown to the designer as "why", never as
/// a verdict. Sources key: docs/research/pairing-from-books.md section 1.
#[derive(Clone, Debug)]
pub struct Evidence {
    pub lens: String,
    pub detail: String,
    pub source: String,
    /// rule | guideline | shortcut | caveat (the source's own strength)
    pub strength: String,
    /// +1 helped the pair, -1 counted against it
    pub effect: i8,
}

#[derive(Clone, Debug)]
pub(crate) struct PairBucket {
    pub label: String,
    pub description: String,
    pub pairs: Vec<PairScore>,
}

// ── Internal row for scoring ──────────────────────────────────────────────────

#[allow(dead_code)] // loaded whole from the DB; not every column scores today
pub(crate) struct FontData {
    pub(crate) font_id: String,
    pub(crate) font_family: String,
    skeleton: String,
    flesh_contrast: String,
    flesh_serif: i32,
    weight: u16,
    x_height_ratio: Option<f64>,
    cap_height_ratio: Option<f64>,
    ascender_descender_ratio: Option<f64>,
    foundry: Option<String>,
    designer: Option<String>,
    file_name: String,
    optical_role: Option<String>,
    superfamily_group: Option<String>,
    superfamily_role: Option<String>,
    weight_range_min: Option<i32>,
    weight_range_max: Option<i32>,
    spacing_personality: Option<String>,
    width_class: Option<String>,
    vendor_id: Option<String>,
}




fn width_str(f: &FontData) -> &str {
    f.width_class.as_deref().unwrap_or("normal")
}




// ── Scoring (v2) ──────────────────────────────────────────────────────────────
//
// Built on the type-set skill's pairing rules (references/pairing.md):
//   - A pair works by being clearly contrasting or clearly uniform. The middle,
//     different enough to look like a mistake, fails.
//   - x-height is the most useful mechanical lens: similar x-heights hold a pair
//     together even when everything else differs.
//   - Shared foundry or designer is a reliable shortcut.
//   - Superfamilies are the safest pair and the least distinctive, so they get
//     their own group instead of first place.
// Scores are continuous (f32) so thousands of candidates don't tie.

fn pct_diff(a: Option<f64>, b: Option<f64>) -> Option<f64> {
    match (a, b) {
        (Some(a), Some(b)) if a > 0.0 => Some(((a - b).abs() / a * 100.0).min(100.0)),
        _ => None,
    }
}

/// True when two designer credits name at least one person in common
/// ("Andrea Biggio & Mathieu Desjardins" vs "Mathieu Desjardins").
fn shares_a_designer(a: &Option<String>, b: &Option<String>) -> bool {
    let split = |s: &str| -> Vec<String> {
        s.split(|c| c == ',' || c == '&' || c == '/' || c == ';')
            .flat_map(|p| p.split(" and "))
            .map(|p| p.trim().to_lowercase())
            .filter(|p| p.len() > 2)
            .collect()
    };
    match (a, b) {
        (Some(a), Some(b)) => {
            let bs = split(b);
            split(a).iter().any(|x| bs.contains(x))
        }
        _ => false,
    }
}

fn score_pair(primary: &FontData, candidate: &FontData) -> Option<PairScore> {
    if primary.font_id == candidate.font_id || primary.font_family == candidate.font_family {
        return None;
    }

    let (p_skel, c_skel) = (primary.skeleton.as_str(), candidate.skeleton.as_str());
    let known = p_skel != "unknown" && c_skel != "unknown";
    let form_differs = primary.flesh_serif != candidate.flesh_serif;

    let is_superfamily = match (&primary.superfamily_group, &candidate.superfamily_group) {
        (Some(a), Some(b)) if !a.is_empty() && a == b => {
            primary.superfamily_role.as_deref().unwrap_or("") != candidate.superfamily_role.as_deref().unwrap_or("")
        }
        _ => false,
    };

    let mut parts: Vec<String> = Vec::new();
    let mut evidence: Vec<Evidence> = Vec::new();
    let mut ev = |lens: &str, detail: String, source: &str, strength: &str, effect: i8| {
        evidence.push(Evidence { lens: lens.into(), detail, source: source.into(), strength: strength.into(), effect });
    };
    let (mut score, pair_type, label): (f32, &str, String) = if is_superfamily {
        let group = primary.superfamily_group.as_deref().unwrap_or("one superfamily");
        (60.0, "superfamily", format!("Designed together ({group})"))
    } else if form_differs {
        let p = if primary.flesh_serif == 1 { "serif" } else { "sans" };
        let c = if candidate.flesh_serif == 1 { "serif" } else { "sans" };
        (if known { 70.0 } else { 62.0 }, "contrast", format!("{p} + {c}"))
    } else if !known {
        (30.0, "uncertain", "Unclassified structure".to_string())
    } else if p_skel == c_skel {
        (60.0, "uniform", format!("Both {p_skel}"))
    } else {
        (25.0, "middle", format!("{p_skel} vs {c_skel}, same form"))
    };

    match pair_type {
        "superfamily" => ev("Designed together", label.clone(), "STO pp.40-41; LAT ch.5; TWC 68", "rule", 1),
        "contrast" => ev("Clear contrast", label.clone(), "LAT ch.5; TWC 69-70; BON p.145; MAY", "guideline", 1),
        "uniform" => ev("Uniform", label.clone(), "LAT ch.5 (hard to do well); TWC 69-70", "guideline", 1),
        "middle" => ev("The middle", label.clone(), "LAT ch.5; TWC 72; STO p.47; MAY", "rule", -1),
        _ => ev("Unclassified", label.clone(), "", "caveat", 0),
    }

    // Same hand (Typewolf 73-78): pen-made faces (dynamic: humanist, old style)
    // sit with pen-made; constructed faces (geometric, rational) with constructed.
    // A shared skeleton is the closest version of the same match (Kupferschmid).
    let camp = |sk: &str| if sk == "dynamic" { "pen-made" } else { "constructed" };
    if pair_type == "contrast" && known {
        // Shown as evidence, not scored: "same hand or crossed" is the designer's
        // call (lens control). Benchmark: no signal (AUC 0.51); cost 2 of
        // Jarrett's shipped pairs when scored. Shared skeleton keeps +5.
        if p_skel == c_skel {
            score += 5.0;
            parts.push(format!("shared {p_skel} skeleton"));
            ev("Skeleton", format!("both {p_skel}"), "STO p.44 (Kupferschmid)", "shortcut", 1);
        } else if camp(p_skel) == camp(c_skel) {
            parts.push(format!("both {}", camp(p_skel)));
            ev("Same hand", format!("both {}", camp(p_skel)), "TWC 73-78", "guideline", 0);
        }
    }

    // x-height: up to +20, fading to 0 at a 25% difference
    if let Some(d) = pct_diff(primary.x_height_ratio, candidate.x_height_ratio) {
        score += 20.0 * (1.0 - d as f32 / 25.0).max(0.0);
        if d <= 10.0 {
            parts.push(format!("x-height within {d:.0}%"));
            ev("x-height", format!("within {d:.0}%"), "LAT ch.5 (not definitive); Typekit; Monotype", "guideline", 1);
        }
    }
    // cap height: up to +5, fading to 0 at 15%
    if let Some(d) = pct_diff(primary.cap_height_ratio, candidate.cap_height_ratio) {
        score += 5.0 * (1.0 - d as f32 / 15.0).max(0.0);
    }
    // texture: stroke contrast differs inside a contrast pair
    if pair_type == "contrast" && primary.flesh_contrast != candidate.flesh_contrast {
        score += 4.0;
        parts.push("textural contrast".into());
        ev("Texture", format!("{} vs {}", primary.flesh_contrast, candidate.flesh_contrast), "BRO ch.3 (texture)", "guideline", 1);
    }
    // shared foundry or designer (the generic Google placeholder doesn't count)
    if !is_superfamily {
        let shared_designer = matches!((&primary.designer, &candidate.designer), (Some(a), Some(b)) if !a.is_empty() && a == b);
        let shared_foundry = matches!((&primary.foundry, &candidate.foundry),
            (Some(a), Some(b)) if !a.is_empty() && a == b && a != GENERIC_FOUNDRY);
        let shared_vendor = matches!((&primary.vendor_id, &candidate.vendor_id), (Some(a), Some(b)) if !a.is_empty() && a == b);
        // A light nudge: "raises odds, no guarantee" (Stocks, Latin, Typewolf 71);
        // the web sources call it a weak proxy. +10 was tuned to one designer.
        if shared_vendor || shared_foundry {
            score += 4.0;
            let who = candidate.foundry.as_deref().filter(|f| !f.is_empty()).or(candidate.vendor_id.as_deref()).unwrap_or("");
            parts.push(format!("shared foundry ({who})"));
            ev("Foundry", who.to_string(), "STO p.43; LAT ch.5; TWC 71", "shortcut", 1);
        }
        if shared_designer || shares_a_designer(&primary.designer, &candidate.designer) {
            score += 3.0;
            parts.push("shared designer".into());
            ev("Designer", candidate.designer.clone().unwrap_or_default(), "STO p.43; TWC 71", "shortcut", 1);
        }
    }
    // two non-normal widths rarely share a page
    match (width_str(primary), width_str(candidate)) {
        ("condensed", "condensed") | ("expanded", "expanded") => score -= 4.0,
        // too far apart also fails (Bonneville: Antique Olive Nord + Garamond Narrow)
        ("condensed", "expanded") | ("expanded", "condensed") => {
            parts.push("widths too far apart".into());
            ev("Width", "condensed vs expanded".into(), "BON p.153", "guideline", 0);
        }
        _ => {}
    }
    // Near-duplicate: same form, skeleton and texture with matching metrics reads
    // as a mistake, not as uniformity (Typewolf 72, Typekit: "too alike").
    if pair_type == "uniform" && primary.flesh_contrast == candidate.flesh_contrast {
        let x = pct_diff(primary.x_height_ratio, candidate.x_height_ratio).unwrap_or(100.0);
        let cap = pct_diff(primary.cap_height_ratio, candidate.cap_height_ratio).unwrap_or(100.0);
        if x <= 3.0 && cap <= 3.0 && width_str(primary) == width_str(candidate) {
            // Lens, not score (contrast-level control). Shown as a warning.
            parts.push("near-duplicate".into());
            ev("Near-duplicate", format!("x-height {x:.0}%, cap {cap:.0}% apart"), "TWC 72; Typekit", "rule", 0);
        }
    }

    // Rank on the raw score; clamp only what's shown. Clamping first made
    // every strong candidate tie at 100.
    let score = score.max(0.0);
    let mut reason = label;
    for part in &parts {
        let next = format!("{reason} · {part}");
        if next.len() > 80 { break; }
        reason = next;
    }

    Some(PairScore {
        font_id: candidate.font_id.clone(),
        score: score.min(100.0).round() as u8,
        precise: score,
        pair_type: pair_type.into(),
        reason,
        evidence,
    })
}

// ── Query + score ─────────────────────────────────────────────────────────────

pub(crate) fn load_all_fonts(conn: &Connection) -> Result<Vec<FontData>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, font_family, skeleton, flesh_contrast, flesh_serif,
                    weight, x_height_ratio, cap_height_ratio, ascender_descender_ratio,
                    foundry, designer, file_name,
                    optical_role, superfamily_group, superfamily_role,
                    weight_range_min, weight_range_max, spacing_personality, width_class,
                    vendor_id
             FROM fonts",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
        Ok(FontData {
            font_id: row.get(0)?,
            font_family: row.get(1)?,
            skeleton: row.get(2)?,
            flesh_contrast: row.get(3)?,
            flesh_serif: row.get(4)?,
            weight: row.get(5)?,
            x_height_ratio: row.get(6)?,
            cap_height_ratio: row.get(7)?,
            ascender_descender_ratio: row.get(8)?,
            foundry: row.get(9)?,
            designer: row.get(10)?,
            file_name: row.get(11)?,
            optical_role: row.get(12)?,
            superfamily_group: row.get(13)?,
            superfamily_role: row.get(14)?,
            weight_range_min: row.get(15)?,
            weight_range_max: row.get(16)?,
            spacing_personality: row.get(17)?,
            width_class: row.get(18)?,
            vendor_id: row.get(19)?,
        })
    })
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    Ok(rows)
}


/// Font ids whose family can't do the Reading job. Sources: a body face must
/// ship regular, italic, bold and bold italic (Typewolf 18/19/36, Stocks);
/// never a display cut in a text role (Typewolf 21, Reynolds); condensed and
/// mono faces fail for long text (Typewolf 22/81, Refactoring UI).
/// Italic here is "has an italic file", a proxy until true-italic is checked.
pub(crate) fn unfit_for_reading(all: &[FontData]) -> HashSet<String> {
    #[derive(Default)]
    struct Cover { regular: bool, italic: bool, bold: bool, bold_italic: bool }
    let mut cover: std::collections::HashMap<&str, Cover> = Default::default();
    for f in all {
        let name = f.file_name.to_lowercase();
        let italic = name.contains("italic") || name.contains("kursiv");
        let bold = f.weight >= 600;
        let c = cover.entry(f.font_family.as_str()).or_default();
        match (italic, bold) {
            (false, false) => c.regular = true,
            (true, false) => c.italic = true,
            (false, true) => c.bold = true,
            (true, true) => c.bold_italic = true,
        }
    }
    all.iter()
        .filter(|f| {
            let fam = f.font_family.to_lowercase();
            let c = &cover[f.font_family.as_str()];
            let incomplete = !(c.regular && c.italic && c.bold && c.bold_italic);
            let display_cut = ["display", "poster", "headline", "deck", "banner"].iter().any(|k| fam.contains(k));
            let narrow = matches!(width_str(f), "condensed" | "compressed");
            let mono = fam.contains("mono") || f.optical_role.as_deref() == Some("mono");
            incomplete || display_cut || narrow || mono
        })
        .map(|f| f.font_id.clone())
        .collect()
}

/// Score every non-hidden candidate against `primary` and fill the three buckets.
pub(crate) fn bucket_pairs(
    primary: &FontData,
    all: &[FontData],
    excluded: &HashSet<String>,
) -> Vec<PairBucket> {
    // Score, best first, then keep only each family's best file: the slots
    // should be different typefaces, not four weights of one.
    let mut scores: Vec<(PairScore, &str)> = all
        .iter()
        .filter(|c| !excluded.contains(&c.font_id))
        .filter_map(|c| score_pair(primary, c).map(|s| (s, c.font_family.as_str())))
        .filter(|(s, _)| s.precise > 0.0)
        .collect();
    scores.sort_by(|a, b| b.0.precise.partial_cmp(&a.0.precise).unwrap_or(std::cmp::Ordering::Equal));
    let mut seen: HashSet<&str> = HashSet::new();
    let ranked: Vec<PairScore> = scores
        .into_iter()
        .filter(|(_, fam)| seen.insert(*fam))
        .map(|(s, _)| s)
        .collect();

    // 11 slots: up to 3 uniform and 2 designed-together; contrast fills the rest.
    let take = |ty: &str, cap: usize| -> Vec<PairScore> {
        ranked.iter().filter(|s| s.pair_type == ty).take(cap).cloned().collect()
    };
    let uniform = take("uniform", 3);
    let together = take("superfamily", 2);
    let contrast = take("contrast", 11 - uniform.len() - together.len());

    [
        ("Clear contrast", "Serif against sans. Reads as intent.", contrast),
        ("Uniform", "Same form, same structure. Reads as one voice.", uniform),
        ("Designed together", "Made as a set. Safest, least distinctive.", together),
    ]
    .into_iter()
    .filter(|(_, _, pairs)| !pairs.is_empty())
    .map(|(label, desc, pairs)| PairBucket { label: label.into(), description: desc.into(), pairs })
    .collect()
}

