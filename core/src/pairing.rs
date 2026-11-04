//! Font pairing engine.
//!
//! Given a primary font, scores every other font in the SQLite
//! database and returns the top matches ranked by structural
//! compatibility using the Font Matrix skeleton/flesh model,
//! supplemented by optical role, superfamily, metric harmony,
//! and spacing personality signals.

use rusqlite::Connection;
use std::collections::HashSet;
use serde::Serialize;

/// Placeholder foundry assigned by Google Fonts enrichment when no specific
/// foundry/designer is known (see google_fonts.rs). It marks a font as
/// "enriched" but carries no real shared-origin signal, so the pairing scorer
/// must NOT treat two fonts sharing this value as a meaningful shared foundry.
const GENERIC_FOUNDRY: &str = "Google Fonts";

// ── Output type ───────────────────────────────────────────────────────────────

#[derive(Serialize, Clone, Debug)]
pub struct PairScore {
    pub font_id: String,
    pub score: u8,
    /// Unrounded score, used to rank so candidates don't tie.
    #[serde(skip)]
    pub precise: f32,
    /// "contrast" | "uniform" | "middle" | "uncertain" | "superfamily" | "same_family"
    pub pair_type: String,
    pub reason: String,
    pub evidence: Vec<Evidence>,
    /// Only for `same_family`: the style of that family to set the body text in.
    pub suggested_body_style: Option<BodyStyle>,
}

/// A style of a family, by the file that holds it, with a designer-readable label ("Regular", "Text").
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct BodyStyle {
    pub font_id: String,
    pub label: String,
}

/// One piece of reasoning behind a score: which lens, what was measured, who
/// says it matters and how strongly. Shown to the designer as "why", never as
/// a verdict. Sources key: docs/research/pairing-from-books.md section 1.
#[derive(Serialize, Clone, Debug)]
pub struct Evidence {
    pub lens: String,
    pub detail: String,
    pub source: String,
    /// rule | guideline | shortcut | caveat (the source's own strength)
    pub strength: String,
    /// +1 helped the pair, -1 counted against it
    pub effect: i8,
}

#[derive(Serialize, Clone, Debug)]
pub struct PairBucket {
    pub label: String,
    pub description: String,
    pub pairs: Vec<PairScore>,
}

// ── Internal row for scoring ──────────────────────────────────────────────────

#[allow(dead_code)] // loaded whole from the DB; not every column scores today
pub struct FontData {
    pub font_id: String,
    pub font_family: String,
    pub skeleton: String,
    pub flesh_contrast: String,
    pub flesh_serif: i32,
    pub weight: u16,
    pub x_height_ratio: Option<f64>,
    pub cap_height_ratio: Option<f64>,
    pub ascender_descender_ratio: Option<f64>,
    pub foundry: Option<String>,
    pub designer: Option<String>,
    pub file_name: String,
    pub optical_role: Option<String>,
    pub superfamily_group: Option<String>,
    pub superfamily_role: Option<String>,
    pub weight_range_min: Option<i32>,
    pub weight_range_max: Option<i32>,
    pub spacing_personality: Option<String>,
    pub width_class: Option<String>,
    pub vendor_id: Option<String>,
    pub file_path: String,
    /// "normal" | "italic" (from the file's own style flags)
    pub style: String,
    pub is_variable: bool,
    /// Top of the `wght` axis of a variable file (0 = none, or not read yet).
    pub wght_axis_max: i64,
    /// A variable file with an `ital` or `slnt` axis.
    pub ital_axis: bool,
    /// Thickest over thinnest stroke of the "O", measured from the outlines (classifier.rs). None = not measured.
    pub stroke_contrast_ratio: Option<f64>,
    /// Mean advance of "n", "o" and "H" over the em (classifier.rs). None = not measured.
    pub advance_ratio: Option<f64>,
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
        suggested_body_style: None,
    })
}

// ── Query + score ─────────────────────────────────────────────────────────────

pub fn load_all_fonts(conn: &Connection) -> Result<Vec<FontData>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, font_family, skeleton, flesh_contrast, flesh_serif,
                    weight, x_height_ratio, cap_height_ratio, ascender_descender_ratio,
                    foundry, designer, file_name,
                    optical_role, superfamily_group, superfamily_role,
                    weight_range_min, weight_range_max, spacing_personality, width_class,
                    vendor_id, file_path, style, COALESCE(is_variable, 0),
                    COALESCE(wght_axis_max, 0), COALESCE(ital_axis, 0), stroke_contrast_ratio, advance_ratio
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
            file_path: row.get(20)?,
            style: row.get(21)?,
            is_variable: row.get::<_, i64>(22)? != 0,
            wght_axis_max: row.get(23)?,
            ital_axis: row.get::<_, i64>(24)? != 0,
            stroke_contrast_ratio: row.get(25)?,
            advance_ratio: row.get(26)?,
        })
    })
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    Ok(rows)
}

// ── Entry point ───────────────────────────────────────────────────────────────

/// Matches for one font, in buckets. `excluded_ids`: fonts the user has hidden; they never take a match slot.
/// Browse filters (search, category, Starred) are deliberately NOT applied here:
/// matches come from the whole visible library, not the left panel's current view.
pub fn font_pairs(
    conn: &Connection,
    font_id: &str,
    excluded_ids: Vec<String>,
    job: Option<&str>,
) -> Result<Vec<PairBucket>, String> {
    let all = load_all_fonts(conn)?;

    let primary = all
        .iter()
        .find(|f| f.font_id == font_id)
        .ok_or_else(|| format!("Font {} not found", font_id))?;

    let mut excluded: HashSet<String> = excluded_ids.into_iter().collect();
    excluded.extend(crate::finder::hidden_font_ids(conn)); // junk list and the user's hides
    // The Display family's own offer ignores the long-text rule: it is shown with a caveat instead.
    let same_family = crate::same_family::offer(primary, &all, &excluded);
    if job == Some("reading") {
        excluded.extend(unfit_for_reading(&all));
    }
    Ok(bucket_pairs_with(primary, &all, &excluded, same_family))
}

/// Font ids whose family can't do the Reading job. Sources: a body face must
/// ship regular, italic, bold and bold italic (Typewolf 18/19/36, Stocks);
/// never a display cut in a text role (Typewolf 21, Reynolds); condensed and
/// mono faces fail for long text (Typewolf 22/81, Refactoring UI).
/// Italic here is "has a slanted file" (`names::is_slanted`: italic, oblique, kursiv, slanted),
/// a proxy until true-italic is checked. A variable file counts for what its axes reach:
/// a `wght` axis that tops out at 600 or more is a bold, an `ital` or `slnt` axis is an italic.
pub fn unfit_for_reading(all: &[FontData]) -> HashSet<String> {
    unfit_ids(all, true)
}

/// `unfit_for_reading`, with the name rule (Compressed, Condensed, Schmal) switched on or off. Off is how it was before
/// that rule: the eval prints both.
fn unfit_ids(all: &[FontData], name_rule: bool) -> HashSet<String> {
    #[derive(Default)]
    struct Cover { regular: bool, italic: bool, bold: bool, bold_italic: bool }
    let mut cover: std::collections::HashMap<&str, Cover> = Default::default();
    for f in all {
        let slanted = crate::names::is_slanted(&f.file_name, &f.style);
        let reaches_bold = f.is_variable && f.wght_axis_max >= 600;
        let has_regular = f.weight < 600 || reaches_bold;
        let has_bold = f.weight >= 600 || reaches_bold;
        // Upright, slanted, or both when one variable file carries an italic axis.
        let slants: &[bool] = if slanted { &[true] } else if f.is_variable && f.ital_axis { &[false, true] } else { &[false] };
        let c = cover.entry(f.font_family.as_str()).or_default();
        for &italic in slants {
            match italic {
                false => { c.regular |= has_regular; c.bold |= has_bold; }
                true => { c.italic |= has_regular; c.bold_italic |= has_bold; }
            }
        }
    }
    all.iter()
        .filter(|f| {
            let fam = f.font_family.to_lowercase();
            let c = &cover[f.font_family.as_str()];
            let incomplete = !(c.regular && c.italic && c.bold && c.bold_italic);
            let display_cut = ["display", "poster", "headline", "deck", "banner"].iter().any(|k| fam.contains(k));
            // Most files carry no measured width class, so the names count too: "Compressed", "Condensed", and the
            // German "Schmal" (narrow), in the family or in the file's own name.
            let narrow_name = |s: &str| {
                let s = s.to_lowercase();
                ["compressed", "condensed", "schmal"].iter().any(|k| s.contains(k))
            };
            let narrow = matches!(width_str(f), "condensed" | "compressed") || (name_rule && (narrow_name(&f.font_family) || narrow_name(&f.file_name)));
            let mono = fam.contains("mono") || f.optical_role.as_deref() == Some("mono");
            incomplete || display_cut || narrow || mono
        })
        .map(|f| f.font_id.clone())
        .collect()
}

/// Score every non-hidden candidate against `primary`, best first, one per
/// family (each family's best file). The slots should be different typefaces,
/// not several weights of one. Shared by the buckets and the flat list.
fn rank_by_family(primary: &FontData, all: &[FontData], excluded: &HashSet<String>) -> Vec<PairScore> {
    let mut scores: Vec<(PairScore, &str)> = all
        .iter()
        .filter(|c| !excluded.contains(&c.font_id))
        .filter_map(|c| score_pair(primary, c).map(|s| (s, c.font_family.as_str())))
        .filter(|(s, _)| s.precise > 0.0)
        .collect();
    scores.sort_by(|a, b| b.0.precise.partial_cmp(&a.0.precise).unwrap_or(std::cmp::Ordering::Equal));
    let mut seen: HashSet<&str> = HashSet::new();
    scores
        .into_iter()
        .filter(|(_, fam)| seen.insert(*fam))
        .map(|(s, _)| s)
        .collect()
}

/// A flat ranked list, best first, one entry per family, at most `limit`.
/// No bucket caps: the caller decides how many to show and filters client-side.
pub fn ranked_candidates(
    primary: &FontData,
    all: &[FontData],
    excluded: &HashSet<String>,
    limit: usize,
) -> Vec<PairScore> {
    let mut ranked = rank_by_family(primary, all, excluded);
    ranked.truncate(limit);
    ranked
}

/// Same exclusions as `font_pairs` (hidden fonts; unfit-for-reading when `job`
/// is "reading"), but one flat ranked list instead of three capped buckets.
pub fn font_candidates(
    conn: &Connection,
    font_id: &str,
    excluded_ids: Vec<String>,
    excluded_families: Vec<String>,
    job: Option<&str>,
    limit: usize,
) -> Result<Vec<PairScore>, String> {
    let all = load_all_fonts(conn)?;
    let primary = all
        .iter()
        .find(|f| f.font_id == font_id)
        .ok_or_else(|| format!("Font {} not found", font_id))?;
    let mut excluded: HashSet<String> = excluded_ids.into_iter().collect();
    excluded.extend(crate::finder::hidden_font_ids(conn)); // junk list and the user's hides
    excluded.extend(ids_of_families(&all, &excluded_families));
    let same_family = crate::same_family::offer(primary, &all, &excluded);
    if job == Some("reading") {
        excluded.extend(unfit_for_reading(&all));
    }
    Ok(crate::same_family::put_first(ranked_candidates(primary, &all, &excluded, limit), same_family, limit))
}

/// `font_candidates` for the Reading list: workhorses (dependable text faces, see `workhorse.rs`) first, the rest
/// after, each group in the engine's own order (best match first). `character_first` flips the groups.
/// Returns the page and the font ids of its workhorses, so the app can tell them apart without a badge.
/// The grouping happens before the page is cut, so a first page of 40 is the 40 best workhorses.
pub fn reading_candidates(
    conn: &Connection,
    font_id: &str,
    excluded_ids: Vec<String>,
    excluded_families: Vec<String>,
    character_first: bool,
    limit: usize,
) -> Result<(Vec<PairScore>, HashSet<String>), String> {
    let all = load_all_fonts(conn)?;
    let primary = all
        .iter()
        .find(|f| f.font_id == font_id)
        .ok_or_else(|| format!("Font {} not found", font_id))?;
    let mut excluded: HashSet<String> = excluded_ids.into_iter().collect();
    excluded.extend(crate::finder::hidden_font_ids(conn));
    excluded.extend(ids_of_families(&all, &excluded_families));
    let same_family = crate::same_family::offer(primary, &all, &excluded);
    excluded.extend(unfit_for_reading(&all));
    let horses = crate::workhorse::assess_all(&all, &crate::workhorse::popularity(conn));
    let family_of: std::collections::HashMap<&str, &str> = all.iter().map(|f| (f.font_id.as_str(), f.font_family.as_str())).collect();
    let is_horse = |id: &str| family_of.get(id).and_then(|f| horses.get(*f)).map_or(false, |h| h.is);
    let mut ranked = rank_by_family(primary, &all, &excluded);
    // Faces the published guides recommend for body text get the same small boost the other shortcuts get, and say why.
    // Only here, in Reading: the pair score the eval measures is not touched.
    for s in &mut ranked {
        let Some(rec) = family_of.get(s.font_id.as_str()).and_then(|f| crate::recommendations::for_family(f)) else { continue };
        let n = rec.sources.len();
        let mut codes: Vec<&str> = rec.sources.iter().map(|x| crate::recommendations::source_code(x)).collect();
        codes.dedup();
        s.precise += crate::recommendations::BOOST;
        s.score = s.precise.min(100.0).round() as u8;
        s.evidence.push(Evidence {
            lens: "Recommended for text".into(),
            detail: format!("{n} source{}", if n == 1 { "" } else { "s" }),
            source: codes.join("; "),
            strength: if n >= 2 { "guideline" } else { "shortcut" }.into(),
            effect: 1,
        });
    }
    ranked.sort_by(|a, b| b.precise.partial_cmp(&a.precise).unwrap_or(std::cmp::Ordering::Equal)); // stable: ties keep their order
    let (mut first, mut second): (Vec<PairScore>, Vec<PairScore>) = ranked.into_iter().partition(|s| is_horse(&s.font_id));
    if character_first { std::mem::swap(&mut first, &mut second); }
    first.extend(second);
    first.truncate(limit);
    let ids: HashSet<String> = first.iter().filter(|s| is_horse(&s.font_id)).map(|s| s.font_id.clone()).collect();
    Ok((crate::same_family::put_first(first, same_family, limit), ids))
}

/// How many families the Reading rule (`unfit_for_reading`) removes from the candidate list:
/// families that would rank without it and do not with it. Same other exclusions as
/// `font_candidates` (the given ids and families, hidden families). Counts families, not files, and is
/// not capped by the page size, so "N not made for long text" matches what "Show them" adds.
pub fn unfit_family_count(
    conn: &Connection,
    font_id: &str,
    excluded_ids: Vec<String>,
    excluded_families: Vec<String>,
) -> Result<u32, String> {
    let all = load_all_fonts(conn)?;
    let primary = all
        .iter()
        .find(|f| f.font_id == font_id)
        .ok_or_else(|| format!("Font {} not found", font_id))?;
    let mut base: HashSet<String> = excluded_ids.into_iter().collect();
    base.extend(crate::finder::hidden_font_ids(conn));
    base.extend(ids_of_families(&all, &excluded_families));
    let family_of: std::collections::HashMap<&str, &str> =
        all.iter().map(|f| (f.font_id.as_str(), f.font_family.as_str())).collect();
    let families = |excluded: &HashSet<String>| -> HashSet<String> {
        rank_by_family(primary, &all, excluded)
            .iter()
            .filter_map(|s| family_of.get(s.font_id.as_str()).map(|f| f.to_string()))
            .collect()
    };
    let without_rule = families(&base);
    let mut with_rule = base;
    with_rule.extend(unfit_for_reading(&all));
    let kept = families(&with_rule);
    Ok(without_rule.difference(&kept).count() as u32)
}

/// Reading before a Display face exists: one entry per family, (font_id, family), in library order.
/// With `only_fit` the long-text rule (`unfit_for_reading`) applies, as it does for pairs. The second value
/// is how many families that rule removes ("N not made for long text"), whatever `only_fit` is: only
/// families with no fit file, so it equals what "Show them" adds.
/// Hidden families, `excluded_ids` and every file of `excluded_families` stay out.
pub fn reading_families(
    conn: &Connection,
    excluded_ids: Vec<String>,
    excluded_families: Vec<String>,
    only_fit: bool,
) -> Result<(Vec<(String, String)>, u32), String> {
    let all = load_all_fonts(conn)?;
    let mut base: HashSet<String> = excluded_ids.into_iter().collect();
    base.extend(crate::finder::hidden_font_ids(conn));
    base.extend(ids_of_families(&all, &excluded_families));
    Ok(reading_list(&all, &base, only_fit))
}

/// The list and the count behind `reading_families`, on rows already loaded.
fn reading_list(all: &[FontData], base: &HashSet<String>, only_fit: bool) -> (Vec<(String, String)>, u32) {
    let unfit = unfit_for_reading(all);
    let mut seen: HashSet<&str> = HashSet::new();
    let mut families: HashSet<&str> = HashSet::new();
    let mut fit_families: HashSet<&str> = HashSet::new();
    let mut out: Vec<(String, String)> = Vec::new();
    for f in all.iter().filter(|f| !base.contains(&f.font_id)) {
        families.insert(f.font_family.as_str());
        let is_unfit = unfit.contains(&f.font_id);
        if !is_unfit { fit_families.insert(f.font_family.as_str()); }
        if (is_unfit && only_fit) || !seen.insert(f.font_family.as_str()) { continue; }
        out.push((f.font_id.clone(), f.font_family.clone()));
    }
    (out, (families.len() - fit_families.len()) as u32)
}

/// Every font id of the named families. The caller names families (the unit a designer
/// thinks in); the core expands them, so a twin .ttf/.otf file or a hidden-style file
/// can never slip past a family-level exclusion.
fn ids_of_families(all: &[FontData], families: &[String]) -> HashSet<String> {
    if families.is_empty() {
        return HashSet::new();
    }
    let names: HashSet<&str> = families.iter().map(String::as_str).collect();
    all.iter().filter(|f| names.contains(f.font_family.as_str())).map(|f| f.font_id.clone()).collect()
}

/// Score every non-hidden candidate against `primary` and fill the Contrast, Uniform and Designed together buckets.
pub fn bucket_pairs(
    primary: &FontData,
    all: &[FontData],
    excluded: &HashSet<String>,
) -> Vec<PairBucket> {
    bucket_pairs_with(primary, all, excluded, None)
}

/// `bucket_pairs`, with the Display family's own "Same family" offer (if it has one) as the first group.
pub fn bucket_pairs_with(
    primary: &FontData,
    all: &[FontData],
    excluded: &HashSet<String>,
    same_family: Option<PairScore>,
) -> Vec<PairBucket> {
    let ranked = rank_by_family(primary, all, excluded);

    // 11 slots: up to 3 uniform and 2 designed-together; contrast fills the rest.
    let take = |ty: &str, cap: usize| -> Vec<PairScore> {
        ranked.iter().filter(|s| s.pair_type == ty).take(cap).cloned().collect()
    };
    let uniform = take("uniform", 3);
    let together = take("superfamily", 2);
    let contrast = take("contrast", 11 - uniform.len() - together.len());

    let same: Vec<PairScore> = same_family.into_iter().collect();
    [
        ("Same family", "Use this family for both. Pick a different width or weight for the body.", same),
        ("Clear contrast", "Serif against sans. Reads as intent.", contrast),
        ("Uniform", "Same form, same structure. Reads as one voice.", uniform),
        ("Designed together", "Made as a set. Safest, least distinctive.", together),
    ]
    .into_iter()
    .filter(|(_, _, pairs)| !pairs.is_empty())
    .map(|(label, desc, pairs)| PairBucket { label: label.into(), description: desc.into(), pairs })
    .collect()
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// A neutral baseline font. Tests clone it and override individual fields
    /// so each test isolates one rule.
    fn font(id: &str, family: &str) -> FontData {
        FontData {
            font_id: id.to_string(),
            font_family: family.to_string(),
            skeleton: "geometric".to_string(),
            flesh_contrast: "linear".to_string(),
            flesh_serif: 0,
            weight: 400,
            x_height_ratio: None,
            cap_height_ratio: None,
            ascender_descender_ratio: None,
            foundry: None,
            designer: None,
            file_name: "Test-Regular.ttf".to_string(),
            optical_role: Some("general".to_string()),
            superfamily_group: None,
            superfamily_role: None,
            weight_range_min: None,
            weight_range_max: None,
            spacing_personality: Some("normal".to_string()),
            width_class: Some("normal".to_string()),
            vendor_id: None,
            file_path: format!("/x/{id}.ttf"),
            style: "normal".to_string(),
            is_variable: false,
            wght_axis_max: 0,
            ital_axis: false,
            stroke_contrast_ratio: None,
            advance_ratio: None,
        }
    }

    // ── Bucketing: hidden fonts never take a match slot ────────────────────

    /// Primary is geometric sans; every candidate is a geometric serif, so each
    /// one scores as a harmonious pair and competes for bucket 1's four slots.
    fn harmonious_pool(n: usize) -> (FontData, Vec<FontData>) {
        let p = font("p", "Primary");
        let mut all = vec![font("p", "Primary")];
        for i in 0..n {
            let mut c = font(&format!("c{i}"), &format!("Cand{i}"));
            c.flesh_serif = 1;
            all.push(c);
        }
        (p, all)
    }

    fn bucket_ids(buckets: &[PairBucket]) -> Vec<String> {
        buckets.iter().flat_map(|b| b.pairs.iter().map(|p| p.font_id.clone())).collect()
    }

    #[test]
    fn hidden_fonts_are_never_matches() {
        let (p, all) = harmonious_pool(8);
        let hidden: HashSet<String> = ["c0", "c1", "c2", "c3"].iter().map(|s| s.to_string()).collect();
        let ids = bucket_ids(&bucket_pairs(&p, &all, &hidden));
        assert!(ids.iter().all(|id| !hidden.contains(id)), "hidden font in results: {ids:?}");
    }

    // ── Flat ranked candidates ─────────────────────────────────────────────

    #[test]
    fn candidates_respect_the_limit_and_beat_the_bucket_cap() {
        let (p, all) = harmonious_pool(30);
        let none = HashSet::new();
        assert_eq!(ranked_candidates(&p, &all, &none, 25).len(), 25);
        assert_eq!(ranked_candidates(&p, &all, &none, 5).len(), 5);
        assert!(ranked_candidates(&p, &all, &none, 100).len() > 11, "buckets cap at 11; the flat list must not");
    }

    #[test]
    fn candidates_are_one_per_family() {
        let (p, mut all) = harmonious_pool(6);
        // Three more files of Cand0 (other weights): still one entry for the family.
        for (i, w) in [300u16, 700, 900].iter().enumerate() {
            let mut c = font(&format!("extra{i}"), "Cand0");
            c.flesh_serif = 1;
            c.weight = *w;
            all.push(c);
        }
        let ranked = ranked_candidates(&p, &all, &HashSet::new(), 50);
        let fam_of = |id: &str| all.iter().find(|f| f.font_id == id).unwrap().font_family.clone();
        let families: Vec<String> = ranked.iter().map(|s| fam_of(&s.font_id)).collect();
        let unique: HashSet<&String> = families.iter().collect();
        assert_eq!(families.len(), unique.len(), "duplicate family in {families:?}");
        assert_eq!(families.len(), 6);
    }

    #[test]
    fn candidates_exclude_hidden_fonts() {
        let (p, all) = harmonious_pool(8);
        let hidden: HashSet<String> = ["c0", "c1", "c2"].iter().map(|s| s.to_string()).collect();
        let ranked = ranked_candidates(&p, &all, &hidden, 50);
        assert_eq!(ranked.len(), 5);
        assert!(ranked.iter().all(|s| !hidden.contains(&s.font_id)));
    }

    #[test]
    fn candidates_for_reading_drop_unfit_families() {
        // Cand0 ships all four styles; Cand1 has only a regular, so it is unfit for body text.
        let p = font("p", "Primary");
        let mut all = vec![font("p", "Primary")];
        for (id, file, w) in [
            ("a1", "A-Regular.ttf", 400u16), ("a2", "A-Italic.ttf", 400),
            ("a3", "A-Bold.ttf", 700), ("a4", "A-BoldItalic.ttf", 700),
        ] {
            let mut c = font(id, "Cand0");
            c.flesh_serif = 1;
            c.file_name = file.to_string();
            c.weight = w;
            all.push(c);
        }
        let mut thin = font("b1", "Cand1");
        thin.flesh_serif = 1;
        all.push(thin);
        let unfit = unfit_for_reading(&all);
        assert!(unfit.contains("b1") && !unfit.contains("a1"));
        let ranked = ranked_candidates(&p, &all, &unfit, 50);
        assert_eq!(ranked.len(), 1);
        assert!(ranked[0].font_id.starts_with('a'));
    }

    fn styled(id: &str, family: &str, file: &str, weight: u16) -> FontData {
        let mut f = font(id, family);
        f.file_name = file.to_string();
        f.weight = weight;
        f
    }

    /// Regular, italic, bold and bold italic as four files.
    fn full_set(family: &str, tag: &str, italic_word: &str) -> Vec<FontData> {
        vec![
            styled(&format!("{tag}1"), family, "R-Regular.otf", 400),
            styled(&format!("{tag}2"), family, &format!("R-{italic_word}.otf"), 400),
            styled(&format!("{tag}3"), family, "R-Bold.otf", 700),
            styled(&format!("{tag}4"), family, &format!("R-Bold{italic_word}.otf"), 700),
        ]
    }

    #[test]
    fn oblique_files_count_as_italic_for_reading() {
        // The same rule Display uses: an Oblique set is a full set, not "not made for long text".
        let mut all = full_set("Obl", "o", "Oblique");
        all.extend(full_set("Ita", "i", "Italic"));
        assert!(unfit_for_reading(&all).is_empty());
    }

    #[test]
    fn a_variable_file_that_reaches_bold_and_italic_is_fit_for_reading() {
        let mut vf = styled("v1", "Vari", "Vari[wght].ttf", 400);
        vf.is_variable = true;
        vf.wght_axis_max = 900;
        // Upright only: bold is reached, italic is not.
        assert!(unfit_for_reading(&[vf.clone_for_test()]).contains("v1"));
        // An ital axis supplies the italic.
        let mut with_ital = vf.clone_for_test();
        with_ital.ital_axis = true;
        assert!(unfit_for_reading(&[with_ital]).is_empty());
        // An italic variable file beside the upright one does the same.
        let mut italic_vf = styled("v2", "Vari", "Vari-Italic[wght].ttf", 400);
        italic_vf.is_variable = true;
        italic_vf.wght_axis_max = 900;
        assert!(unfit_for_reading(&[vf.clone_for_test(), italic_vf]).is_empty());
        // A variable file whose wght axis stops below 600 has no bold.
        let mut light = styled("v3", "Lite", "Lite[wght].ttf", 400);
        light.is_variable = true;
        light.wght_axis_max = 500;
        light.ital_axis = true;
        assert!(unfit_for_reading(&[light]).contains("v3"));
    }

    /// A complete family (regular, italic, bold, bold italic) under this family name.
    fn complete(family: &str) -> Vec<FontData> {
        vec![
            styled("a", family, "Face-Regular.otf", 400),
            styled("b", family, "Face-Italic.otf", 400),
            styled("c", family, "Face-Bold.otf", 700),
            styled("d", family, "Face-BoldItalic.otf", 700),
        ]
    }

    /// Most files have no measured width class, so the family name decides: Compressed, Condensed and the German
    /// Schmal (narrow) are not for long text. A complete family with an ordinary name is fine.
    #[test]
    fn compressed_condensed_and_schmal_names_are_not_for_long_text() {
        for name in ["Test National 2 Compressed", "Test Söhne Schmal", "Acme Condensed"] {
            let fam = complete(name);
            assert_eq!(unfit_for_reading(&fam).len(), 4, "{name}");
        }
        assert!(unfit_for_reading(&complete("Acme Text")).is_empty());
        // A narrow cut among ordinary files drops only that file.
        let mut mixed = complete("Acme Sans");
        mixed.push(styled("e", "Acme Sans", "Acme-CondensedRegular.otf", 400));
        let unfit = unfit_for_reading(&mixed);
        assert!(unfit.contains("e") && unfit.len() == 1);
    }

    impl FontData {
        fn clone_for_test(&self) -> FontData {
            let mut f = font(&self.font_id, &self.font_family);
            f.file_name = self.file_name.clone();
            f.weight = self.weight;
            f.is_variable = self.is_variable;
            f.wght_axis_max = self.wght_axis_max;
            f.ital_axis = self.ital_axis;
            f.stroke_contrast_ratio = self.stroke_contrast_ratio;
            f.advance_ratio = self.advance_ratio;
            f.style = self.style.clone();
            f
        }
    }

    #[test]
    fn long_text_count_counts_only_families_with_no_fit_file() {
        // Mixed: a full set plus a condensed file. Its other files are fit, so the family is not "unfit".
        let mut all = full_set("Mixed", "m", "Italic");
        let mut narrow = styled("m5", "Mixed", "R-Cond.otf", 400);
        narrow.width_class = Some("condensed".into());
        all.push(narrow);
        // Thin: one regular file, no italic or bold: unfit.
        all.push(styled("t1", "Thin", "T-Regular.otf", 400));
        // Whole: a full set, fit.
        all.extend(full_set("Whole", "w", "Italic"));
        let (list, unfit) = reading_list(&all, &HashSet::new(), true);
        let names: Vec<&str> = list.iter().map(|(_, f)| f.as_str()).collect();
        assert_eq!(names, vec!["Mixed", "Whole"]);
        assert_eq!(unfit, 1, "only Thin has no fit file");
        // "Show them" adds exactly the counted families.
        let (everything, _) = reading_list(&all, &HashSet::new(), false);
        assert_eq!(everything.len() - list.len(), unfit as usize);
    }

    fn db_with(rows: &[(&str, &str, &str, i64)]) -> (Connection, std::path::PathBuf) {
        let dir = std::env::temp_dir().join(format!("fontdrop-pairing-{}-{}", std::process::id(), rows.len()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.db");
        let _ = std::fs::remove_file(&path);
        let conn = crate::db::try_open_db_at(&path).unwrap();
        for (id, family, file, weight) in rows {
            conn.execute(
                "INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, weight, category, style, width, skeleton, flesh_contrast, flesh_serif, classification_source, user_override, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, 'user', ?2, ?5, 'other', 'normal', 'normal', 'geometric', 'linear', 0, 'file', 0, 'x', 'x')",
                rusqlite::params![id, family, format!("/x/{file}"), file, weight],
            )
            .unwrap();
        }
        (conn, dir)
    }

    #[test]
    fn excluding_a_family_by_name_removes_every_one_of_its_files() {
        // Beta ships its regular as .otf and .ttf twins; excluding by file id would miss the twin.
        let mut rows = vec![];
        for (tag, fam) in [("a", "Alpha"), ("b", "Beta")] {
            for (i, (file, w)) in [("Regular.otf", 400), ("Regular.ttf", 400), ("Italic.otf", 400), ("Bold.otf", 700), ("BoldItalic.otf", 700)].iter().enumerate() {
                rows.push((format!("{tag}{i}"), fam.to_string(), format!("{fam}-{file}"), *w));
            }
        }
        let borrowed: Vec<(&str, &str, &str, i64)> = rows.iter().map(|(a, b, c, d)| (a.as_str(), b.as_str(), c.as_str(), *d)).collect();
        let (conn, dir) = db_with(&borrowed);
        let (all, _) = reading_families(&conn, vec![], vec![], true).map(|(l, c)| (l, c)).unwrap();
        assert_eq!(all.len(), 2);
        // The old way: only the de-duplicated file id. The .ttf twin stays in the library's list of files.
        let (list, _) = reading_families(&conn, vec!["b0".into()], vec![], true).unwrap();
        assert_eq!(list.len(), 2, "excluding one file of Beta does not remove Beta");
        let (list, unfit) = reading_families(&conn, vec![], vec!["Beta".into()], true).unwrap();
        assert_eq!(list.iter().map(|(_, f)| f.as_str()).collect::<Vec<_>>(), vec!["Alpha"]);
        assert_eq!(unfit, 0);
        // Candidates and the count honour it too.
        let primary = "a0";
        let ranked = font_candidates(&conn, primary, vec![], vec!["Beta".into()], None, 50).unwrap();
        assert!(ranked.iter().all(|s| !s.font_id.starts_with('b')));
        let n = unfit_family_count(&conn, primary, vec![], vec!["Beta".into()]).unwrap();
        assert_eq!(n, 0);
        drop(conn);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// How many variable families reach Reading, on a COPY of a real database:
    ///   FONTDROP_DB=<copy> cargo test --lib variable_reading_report -- --ignored --nocapture
    /// Run it before and after a rescan: the rescan reads the axes the rule needs.
    #[test]
    #[ignore]
    fn variable_reading_report() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
        assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy, not the live DB");
        let conn = Connection::open(&path).unwrap();
        let all = load_all_fonts(&conn).unwrap();
        let unfit = unfit_for_reading(&all);
        let mut fam: std::collections::HashMap<&str, (bool, bool)> = Default::default();
        for f in &all {
            let e = fam.entry(f.font_family.as_str()).or_default();
            e.0 |= f.is_variable;
            e.1 |= !unfit.contains(&f.font_id);
        }
        let variable = fam.values().filter(|e| e.0).count();
        let reach = fam.values().filter(|e| e.0 && e.1).count();
        let with_axes = all.iter().filter(|f| f.is_variable && f.wght_axis_max > 0).count();
        println!("variable families: {variable}; reach Reading: {reach}; variable files with a read wght axis: {with_axes}");
    }

    // ── Ground-truth eval (real DB; run on demand) ─────────────────────────
    //
    // Pairings Jarrett actually shipped, scored both directions against the
    // live font database. Not a pass/fail gate: it prints a hit-rate table.
    //   (use a COPY: sqlite3 <live db> ".backup /tmp/fd-copy.db")
    //   cd core && FONTDROP_DB=/tmp/fd-copy.db \
    //     cargo test --lib eval_ground_truth -- --ignored --nocapture

    /// (key a, key b, tokens that disqualify a family from matching key a / key b)
    const GROUND_TRUTH: &[(&str, &str, &[&str], &[&str])] = &[
        ("otjubileegolden", "ppmori", &[], &[]),
        ("rhetorikserif", "brown", &[], &[]),
        ("ppmuseum", "ppneuemontreal", &[], &["mono", "arabic", "text"]),
        ("pprightslab", "ppneuemontreal", &[], &["mono", "arabic", "text"]),
        ("pprightserif", "pprightgrotesk", &["mono"], &["mono"]),
        ("ppframa", "ppframatext", &["text"], &[]),
        ("otjubileeplatinum", "ppmuseum", &[], &[]),
        // Gambarino + Satoshi retired from this set (2026-10): the brand moved to
        // Timeless; skinny high-contrast serifs now read as a trend marker.
        ("timelessserif", "timelesssans", &[], &[]),
    ];

    fn norm(s: &str) -> String {
        s.to_lowercase().chars().filter(|c| !c.is_whitespace()).collect()
    }

    fn matches(f: &FontData, key: &str, not: &[&str]) -> bool {
        let n = norm(&f.font_family);
        n.starts_with(key) && !not.iter().any(|t| n[key.len()..].contains(t))
    }

    /// The upright file nearest weight 400: what a person would click first.
    fn pick_primary<'a>(all: &'a [FontData], key: &str, not: &[&str]) -> Option<&'a FontData> {
        all.iter()
            .filter(|f| matches(f, key, not) && !crate::names::is_slanted(&f.file_name, &f.style))
            .min_by_key(|f| (f.weight as i32 - 400).abs())
    }

    #[test]
    #[ignore]
    fn eval_ground_truth() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB");
        let conn = Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let all = load_all_fonts(&conn).unwrap();
        let none = HashSet::new();
        let (mut hits, mut runs) = (0, 0);
        println!("\n{:<38} {:>6} {:>6} {:>9} {:>10}", "primary -> partner", "rank", "top11", "families", "skeleton");
        for (a, b, na, nb) in GROUND_TRUTH {
            for (pk, pn, ck, cn) in [(*a, *na, *b, *nb), (*b, *nb, *a, *na)] {
                let Some(primary) = pick_primary(&all, pk, pn) else {
                    println!("{:<38} primary not installed", format!("{pk} -> {ck}"));
                    continue;
                };
                runs += 1;
                let mut scores: Vec<PairScore> = all.iter().filter_map(|c| score_pair(primary, c)).filter(|s| s.score > 0).collect();
                scores.sort_by(|x, y| y.precise.partial_cmp(&x.precise).unwrap_or(std::cmp::Ordering::Equal));
                let by_id: std::collections::HashMap<&str, &FontData> = all.iter().map(|f| (f.font_id.as_str(), f)).collect();
                let mut seen_fams: HashSet<String> = HashSet::new();
                let rank = scores
                    .iter()
                    .filter(|s| seen_fams.insert(by_id[s.font_id.as_str()].font_family.clone()))
                    .position(|s| matches(by_id[s.font_id.as_str()], ck, cn))
                    .map(|i| i + 1);
                let buckets = bucket_pairs(primary, &all, &none);
                let shown: Vec<&FontData> = buckets.iter().flat_map(|b| b.pairs.iter()).map(|p| by_id[p.font_id.as_str()]).collect();
                let hit = shown.iter().any(|f| matches(f, ck, cn));
                let fams: HashSet<String> = shown.iter().map(|f| norm(&f.font_family)).collect();
                if hit { hits += 1; }
                println!("{:<38} {:>6} {:>6} {:>4} of {:<3} {:>10}",
                    format!("{} -> {ck}", primary.font_family),
                    rank.map(|r| r.to_string()).unwrap_or("0-score".into()),
                    if hit { "HIT" } else { "-" }, fams.len(), shown.len(), primary.skeleton);
            }
        }
        println!("\nreal partner shown in top 11: {hits} of {runs}  (rank = position among families)");
    }

    // Workhorses and the Reading list, on a DB copy:
    //   FONTDROP_DB=<copy> cargo test --lib eval_workhorse_reading -- --ignored --nocapture
    // Prints, for the Reading face of each shipped pair, whether it counts as a workhorse and why not; then the top 10
    // Reading candidates for three Display faces, before (the old rules, engine order) and after (workhorses first).
    #[test]
    #[ignore]
    fn eval_workhorse_reading() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB");
        let conn = Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let all = load_all_fonts(&conn).unwrap();
        let horses = crate::workhorse::assess_all(&all, &crate::workhorse::popularity(&conn));
        println!("\nReading faces of the shipped pairs");
        let (mut yes, mut total) = (0, 0);
        for (_, b, _, nb) in GROUND_TRUTH {
            let Some(f) = pick_primary(&all, b, nb) else { println!("  {b}: not installed"); continue };
            let w = &horses[&f.font_family];
            total += 1;
            if w.is { yes += 1; }
            println!("  {:<24} {}  passed: {}  | failed: {}", f.font_family, if w.is { "WORKHORSE" } else { "no       " }, w.passed.join(", "), w.failed.join(", "));
        }
        println!("  {yes} of {total} are workhorses");
        println!("\nMeasures of the regular face (advance = mean of n, o, H over the em; contrast = thickest / thinnest stroke)");
        println!("  {:<22} {:>7} {:>8} {:>8} {:>8}  {:<9}  {}", "family", "advance", "contrast", "x-height", "spacing", "workhorse", "failed | unknown");
        for name in ["Timeless Sans", "Timeless Serif", "PP Museum", "PP Neue Montreal", "PP Mori", "Source Serif 4", "Times New Roman",
                     "PP Pangaia", "Zodiak", "PP Neue Machina", "OT Jubilee Sapphire", "OT Jubilee Platinum", "OT Jubilee Diamond",
                     "OT Jubilee Golden", "Agrandir", "Asap", "Georgia", "Test Domaine Text"] {
            let files: Vec<&FontData> = all.iter().filter(|f| f.font_family == name).collect();
            let Some(rep) = files.iter().filter(|f| !crate::names::is_slanted(&f.file_name, &f.style)).min_by_key(|f| (f.weight as i32 - 400).abs()) else {
                println!("  {name:<22} not installed");
                continue;
            };
            let w = &horses[name];
            let fmt = |v: Option<f64>| v.map(|x| format!("{x:.3}")).unwrap_or("-".into());
            println!("  {:<22} {:>7} {:>8} {:>8} {:>8}  {:<9}  {} | {}", name, fmt(rep.advance_ratio),
                     rep.stroke_contrast_ratio.map(|c| format!("{c:.2}")).unwrap_or("-".into()), fmt(rep.x_height_ratio),
                     rep.spacing_personality.clone().unwrap_or("-".into()), if w.is { "WORKHORSE" } else { "no" },
                     w.failed.join(", "), w.unknown.join(", "));
        }
        let families: HashSet<&str> = all.iter().map(|f| f.font_family.as_str()).collect();
        let unknown_families = families.iter().filter(|f| !horses[**f].unknown.is_empty()).count();
        println!("\n{unknown_families} of {} families have a signal that could not be read (counted as not a workhorse)", families.len());
        for signal in ["normal width", "text x-height", "moderate contrast"] {
            let n = families.iter().filter(|f| horses[**f].unknown.contains(&signal)).count();
            println!("  unread {signal}: {n} families");
        }
        let hidden = crate::finder::hidden_font_ids(&conn);
        let horse_count = families.iter().filter(|f| horses[**f].is).count();
        println!("\n{horse_count} of {} families are workhorses", families.len());
        let old_unfit = unfit_ids(&all, false);
        for key in ["agrandir", "ppmuseum", "timelessserif"] {
            let Some(primary) = pick_primary(&all, key, &[]) else { println!("{key}: not installed"); continue };
            let mut before_excl: HashSet<String> = hidden.clone();
            before_excl.extend(old_unfit.iter().cloned());
            let before = ranked_candidates(primary, &all, &before_excl, 10);
            let fam = |id: &str| all.iter().find(|f| f.font_id == id).map(|f| f.font_family.clone()).unwrap_or_default();
            println!("\nDisplay = {}: top 10 Reading candidates", primary.font_family);
            println!("  BEFORE (best match only)");
            for (i, s) in before.iter().enumerate() {
                let f = fam(&s.font_id);
                println!("   {:>2}. {:<34} {}", i + 1, f, if horses[&f].is { "workhorse" } else { "" });
            }
            let (after, _) = reading_candidates(&conn, &primary.font_id, vec![], vec![], false, 10).unwrap();
            println!("  AFTER (workhorses first, then best match)");
            for (i, s) in after.iter().enumerate() {
                let f = fam(&s.font_id);
                let rec = crate::recommendations::for_family(&f).map(|r| format!(" | recommended ({})", r.sources.join(", "))).unwrap_or_default();
                println!("   {:>2}. {:<34} {}{}", i + 1, f, if horses[&f].is { "workhorse" } else { "" }, rec);
            }
        }
        let recommended: Vec<&str> = {
            let mut v: Vec<&str> = families.iter().copied().filter(|f| crate::recommendations::for_family(f).is_some()).collect();
            v.sort();
            v
        };
        println!("\n{} of {} library families match a recommendation: {}", recommended.len(), families.len(), recommended.join(", "));
    }

    // ── Broad benchmark (Google Fonts pairs mined from real sites + books) ──
    //   cd core && BENCH_DB=<bench.db> BENCH_PAIRS=../docs/research/benchmarks/web-pairs.csv \
    //     cargo test --lib eval_benchmark -- --ignored --nocapture
    // AUC = chance a real pair outscores a fake one (0.5 = coin flip).
    // Negatives are popularity-matched, so popularity alone scores ~0.5.

    fn auc(pos: &[f32], neg: &[f32]) -> f64 {
        if pos.is_empty() || neg.is_empty() { return f64::NAN; }
        let mut wins = 0.0;
        for p in pos { for n in neg { wins += if p > n { 1.0 } else if p == n { 0.5 } else { 0.0 }; } }
        wins / (pos.len() * neg.len()) as f64
    }

    #[test]
    #[ignore]
    fn eval_benchmark() {
        let db = std::env::var("BENCH_DB").expect("set BENCH_DB");
        let pairs = std::env::var("BENCH_PAIRS").expect("set BENCH_PAIRS");
        let conn = Connection::open_with_flags(&db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let all = load_all_fonts(&conn).unwrap();
        // Exact family first. Fallback: Google's CSS-API static files all claim
        // their default instance as family ("Montserrat Thin" even for Bold),
        // so match on the family with instance words stripped.
        let rep = |fam: &str| -> Option<&FontData> {
            let fam = fam.to_lowercase();
            let upright = |f: &&FontData| !crate::names::is_slanted(&f.file_name, &f.style);
            let exact = all.iter().filter(|f| f.font_family.to_lowercase() == fam).filter(upright)
                .min_by_key(|f| (f.weight as i32 - 400).abs());
            exact.or_else(|| {
                all.iter()
                    .filter(|f| crate::names::strip_instance_words(&f.font_family).to_lowercase() == fam)
                    .filter(upright)
                    .min_by_key(|f| (f.weight as i32 - 400).abs())
            })
        };
        let text = std::fs::read_to_string(&pairs).unwrap();
        let mut by_source: std::collections::BTreeMap<String, (Vec<f32>, Vec<f32>)> = Default::default();
        let (mut used, mut missing) = (0, 0);
        let mut types: std::collections::BTreeMap<String, (u32, u32)> = Default::default();
        for line in text.lines().skip(1) {
            let c: Vec<&str> = line.split(',').collect();
            if c.len() < 4 { continue; }
            let (a, b, label, source) = (c[0].trim(), c[1].trim(), c[2].trim() == "1", c[3].trim());
            let (Some(fa), Some(fb)) = (rep(a), rep(b)) else { missing += 1; continue; };
            used += 1;
            let ab = score_pair(fa, fb);
            let ba = score_pair(fb, fa);
            let best = [ab, ba].into_iter().flatten().max_by(|x, y| x.precise.partial_cmp(&y.precise).unwrap());
            let score = best.as_ref().map(|s| s.precise).unwrap_or(0.0);
            let ty = best.map(|s| s.pair_type).unwrap_or_else(|| "none".into());
            let t = types.entry(ty).or_default();
            if label { t.0 += 1 } else { t.1 += 1 }
            let group = if source == "books" { "books" } else { "github+neg" };
            let e = by_source.entry(group.into()).or_default();
            if label { e.0.push(score) } else { e.1.push(score) }
        }
        let (mut pos, mut neg) = (vec![], vec![]);
        for (k, (p, n)) in &by_source {
            println!("{k:<12} pos {:>4} neg {:>4} AUC {:.3}", p.len(), n.len(), auc(p, n));
            pos.extend(p); neg.extend(n);
        }
        println!("pair types (pos, neg): {types:?}");
        println!("pairs used {used}, missing fonts {missing}");
        println!("OVERALL AUC {:.3}", auc(&pos, &neg));
    }

    // ── Base-score / pair_type matrix (scoring v2) ────────────────────────
    #[test]
    fn serif_with_sans_is_contrast() {
        let p = font("p", "Primary");
        let mut c = font("c", "Cand");
        c.flesh_serif = 1;
        assert_eq!(score_pair(&p, &c).unwrap().pair_type, "contrast");
    }

    #[test]
    fn same_form_same_skeleton_is_uniform() {
        let p = font("p", "Primary");
        let c = font("c", "Cand");
        assert_eq!(score_pair(&p, &c).unwrap().pair_type, "uniform");
    }

    #[test]
    fn the_middle_scores_below_contrast_and_uniform() {
        let p = font("p", "Primary"); // geometric sans
        let mut middle = font("m", "Middle");
        middle.skeleton = "rational".into(); // same form, different structure
        let uniform = font("u", "Uniform");
        let mut contrast = font("c", "Contrast");
        contrast.flesh_serif = 1;
        let m = score_pair(&p, &middle).unwrap();
        assert_eq!(m.pair_type, "middle");
        assert!(m.precise < score_pair(&p, &uniform).unwrap().precise);
        assert!(m.precise < score_pair(&p, &contrast).unwrap().precise);
    }

    #[test]
    fn superfamily_scores_below_an_equal_contrast_pair() {
        let mut p = font("p", "Source Serif");
        p.flesh_serif = 1;
        let mut sf = font("s", "Source Sans");
        p.superfamily_group = Some("Source".into());
        sf.superfamily_group = Some("Source".into());
        p.superfamily_role = Some("serif".into());
        sf.superfamily_role = Some("sans".into());
        let other = font("o", "Other Sans");
        assert!(score_pair(&p, &sf).unwrap().precise < score_pair(&p, &other).unwrap().precise);
    }

    #[test]
    fn results_show_one_file_per_family() {
        let p = font("p", "Primary");
        let mut all = vec![font("p", "Primary")];
        for i in 0..6 {
            let mut c = font(&format!("a{i}"), "Same Family");
            c.flesh_serif = 1;
            all.push(c);
        }
        let mut other = font("b", "Other Family");
        other.flesh_serif = 1;
        all.push(other);
        let ids = bucket_ids(&bucket_pairs(&p, &all, &HashSet::new()));
        assert_eq!(ids.len(), 2, "one per family: {ids:?}");
    }


    #[test]
    fn self_pair_is_skipped() {
        let a = font("x", "Alpha");
        assert!(score_pair(&a, &a).is_none());
    }

    #[test]
    fn same_family_is_skipped() {
        let mut a = font("a", "Alpha");
        let mut b = font("b", "Alpha"); // same family, different id
        a.skeleton = "geometric".into();
        b.skeleton = "rational".into();
        assert!(score_pair(&a, &b).is_none());
    }






    // ── Same-flesh penalty ─────────────────────────────────────────────────


    // ── Superfamily override ───────────────────────────────────────────────

    #[test]
    fn confirmed_superfamily_is_designed_together() {
        let mut p = font("p", "Source Serif");
        let mut c = font("c", "Source Sans");
        p.superfamily_group = Some("Source".into());
        c.superfamily_group = Some("Source".into());
        p.superfamily_role = Some("serif".into());
        c.superfamily_role = Some("sans".into());
        let s = score_pair(&p, &c).expect("scores");
        assert_eq!(s.pair_type, "superfamily");
    }

    #[test]
    fn same_superfamily_same_role_is_not_superfamily() {
        let mut p = font("p", "Source Sans");
        let mut c = font("c", "Source Sans Caption");
        p.superfamily_group = Some("Source".into());
        c.superfamily_group = Some("Source".into());
        p.superfamily_role = Some("sans".into());
        c.superfamily_role = Some("sans".into());
        let s = score_pair(&p, &c).expect("scores");
        assert_ne!(s.pair_type, "superfamily");
    }

    // ── Additive modifiers (assert direction of the delta) ─────────────────




    // ── Foundry catch-all (plan 002) ──────────────────────────────────────

    #[test]
    fn generic_google_foundry_grants_no_shared_foundry_bonus() {
        // Generic placeholder foundry on both -> no shared-foundry reason.
        let mut p = font("p", "Primary");
        let mut generic = font("g", "GenericCand");
        p.flesh_serif = 0;
        generic.flesh_serif = 1; // keep flesh differing so base is stable
        p.foundry = Some("Google Fonts".into());
        generic.foundry = Some("Google Fonts".into());
        let s_generic = score_pair(&p, &generic).expect("scores");
        assert!(
            !s_generic.reason.contains("shared foundry"),
            "generic placeholder must not produce a shared-foundry reason: {}",
            s_generic.reason
        );

        // Real shared foundry -> +4 and a correctly-labeled reason.
        let mut p2 = font("p2", "Primary2");
        let mut real2 = font("r2", "RealCand2");
        p2.flesh_serif = 0;
        real2.flesh_serif = 1;
        p2.foundry = Some("Adobe".into());
        real2.foundry = Some("Adobe".into());
        let s_real = score_pair(&p2, &real2).expect("scores");
        assert!(
            s_real.reason.contains("shared foundry (Adobe)"),
            "real shared foundry should be labeled: {}",
            s_real.reason
        );
    }

    // ── load_all_fonts error handling (plan 003) ──────────────────────────

    #[test]
    fn load_all_fonts_returns_ok_on_valid_schema() {
        use rusqlite::Connection;
        let conn = Connection::open_in_memory().expect("in-memory db");
        conn.execute_batch(
            "CREATE TABLE fonts (
                font_id TEXT, font_family TEXT, skeleton TEXT, flesh_contrast TEXT,
                flesh_serif INTEGER, weight INTEGER, x_height_ratio REAL,
                cap_height_ratio REAL, ascender_descender_ratio REAL, foundry TEXT,
                designer TEXT, file_name TEXT, optical_role TEXT, superfamily_group TEXT,
                superfamily_role TEXT, weight_range_min INTEGER, weight_range_max INTEGER,
                spacing_personality TEXT, width_class TEXT, vendor_id TEXT,
                file_path TEXT, style TEXT, is_variable INTEGER,
                wght_axis_max INTEGER, ital_axis INTEGER, stroke_contrast_ratio REAL, advance_ratio REAL
            );
            INSERT INTO fonts (font_id, font_family, skeleton, flesh_contrast, flesh_serif, weight, file_name, file_path, style)
            VALUES ('a','Alpha','geometric','linear',0,400,'Alpha.ttf','/x/Alpha.ttf','normal');",
        )
        .expect("create+insert");

        let result = load_all_fonts(&conn);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().len(), 1);
    }

    #[test]
    fn load_all_fonts_returns_err_on_missing_table() {
        use rusqlite::Connection;
        let conn = Connection::open_in_memory().expect("in-memory db");
        // No `fonts` table -> prepare fails -> Err, not panic.
        assert!(load_all_fonts(&conn).is_err());
    }

    #[test]
    fn closer_x_height_scores_at_least_as_high() {
        let mut p = font("p", "Primary");
        p.flesh_serif = 0;
        p.x_height_ratio = Some(0.70);

        let mut close = font("cl", "CloseCand");
        close.flesh_serif = 1;
        close.x_height_ratio = Some(0.70); // identical -> within 5%

        let mut far = font("fa", "FarCand");
        far.flesh_serif = 1;
        far.x_height_ratio = Some(0.40); // far

        let s_close = score_pair(&p, &close).expect("scores");
        let s_far = score_pair(&p, &far).expect("scores");
        assert!(
            s_close.score >= s_far.score,
            "close x-height {} should be >= far {}",
            s_close.score,
            s_far.score
        );
    }
}
