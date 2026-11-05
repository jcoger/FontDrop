//! Is this family a dependable text face? A workhorse: the kind a designer sets a paragraph in without a second
//! thought. Reading ranks these first, so the top of the list is a safe choice and the characterful faces come after.
//!
//! The answer is a few named signals, not a score, so it can be explained in one line:
//!   text family   4 or more weights (or a `wght` range that spans 300 to 700) and a true italic
//!   normal width  not condensed, compressed, extended or expanded (width class, or the name)
//!   text cut      no Display, Poster, Headline, Deck or Banner in the name, and none of the width words
//!   x-height      in the comfortable text range (0.44 to 0.58 of the em), where it was measured
//!   moderate contrast   not a high-contrast face, where it was measured
//!   normal spacing      not tight or open: faces drawn for display sizes are spaced for them, where it was measured
//!   widely used   in the top of Google Fonts' popularity rank (a lift, see below)
//!
//! A family is a workhorse when it has all of the signals above except "widely used". A widely used family may be a workhorse
//! on a fuller list of weights alone: two weights and an italic are enough for a face most sites already trust.

use crate::pairing::FontData;
use rusqlite::Connection;
use std::collections::HashMap;

/// The Google popularity rank (1 = most used) at or under which a face counts as widely used.
pub const WIDELY_USED_RANK: u32 = 150;
/// The x-height range of a text face, as a fraction of the em.
pub const TEXT_X_HEIGHT: std::ops::RangeInclusive<f64> = 0.44..=0.58;

/// Words in a family or file name that mark a cut for display sizes or a width a paragraph cannot use.
const DISPLAY_WORDS: &[&str] = &["display", "poster", "headline", "deck", "banner"];
const WIDTH_WORDS: &[&str] = &["compressed", "condensed", "extended", "expanded", "schmal", "narrow", "wide"];

#[derive(Debug, Clone, PartialEq)]
pub struct Workhorse {
    /// A dependable text face.
    pub is: bool,
    /// The signals the family has, by name, in a fixed order.
    pub passed: Vec<&'static str>,
    /// The signals it lacks.
    pub failed: Vec<&'static str>,
}

fn words(name: &str) -> Vec<String> {
    name.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).map(|w| w.to_lowercase()).collect()
}

fn has_word(text: &str, list: &[&str]) -> bool {
    // Words and their glued forms: "SemiCondensed", "TestSöhneSchmal".
    let lower = text.to_lowercase();
    words(text).iter().any(|w| list.contains(&w.as_str())) || list.iter().any(|k| lower.contains(k))
}

/// The assessment of one family from all its files. `popularity` is Google's rank for it, when Google lists it.
pub fn assess(files: &[&FontData], popularity: Option<u32>) -> Workhorse {
    let mut passed: Vec<&'static str> = Vec::new();
    let mut failed: Vec<&'static str> = Vec::new();
    let mut put = |ok: bool, name: &'static str| if ok { passed.push(name) } else { failed.push(name) };
    if files.is_empty() {
        return Workhorse { is: false, passed, failed: vec!["text family"] };
    }

    // The regular, upright file stands for the family: nearest weight 400, not slanted.
    let upright = |f: &&&FontData| !crate::names::is_slanted(&f.file_name, &f.style);
    let rep = files.iter().filter(upright).min_by_key(|f| (f.weight as i32 - 400).abs()).or_else(|| files.first()).copied().unwrap();

    // Text family: enough weights and a real italic.
    let mut weights: Vec<u16> = files.iter().map(|f| f.weight).collect();
    weights.sort_unstable();
    weights.dedup();
    let span = files.iter().any(|f| {
        let (lo, hi) = (f.weight_range_min.unwrap_or(f.weight as i32), f.weight_range_max.unwrap_or(f.weight as i32));
        (lo <= 350 && hi >= 650) || (f.is_variable && f.wght_axis_max >= 700)
    });
    let full_weights = weights.len() >= 4 || span;
    let italic = files.iter().any(|f| crate::names::is_slanted(&f.file_name, &f.style) || f.ital_axis);
    let text_family = full_weights && italic;

    // Width: the measured class where there is one, and the names.
    let width_ok = !matches!(rep.width_class.as_deref(), Some("condensed" | "compressed" | "expanded" | "extended"))
        && !has_word(&rep.font_family, WIDTH_WORDS)
        && !has_word(&rep.file_name, WIDTH_WORDS);
    let not_display = !has_word(&rep.font_family, DISPLAY_WORDS) && !has_word(&rep.file_name, DISPLAY_WORDS);
    let x_height_ok = rep.x_height_ratio.map_or(true, |x| TEXT_X_HEIGHT.contains(&x));
    let contrast_ok = rep.flesh_contrast != "high";
    let spacing_ok = rep.spacing_personality.as_deref().map_or(true, |s| s == "normal");
    let widely_used = popularity.map_or(false, |r| r <= WIDELY_USED_RANK);

    put(text_family, "text family");
    put(width_ok, "normal width");
    put(not_display, "text cut");
    put(x_height_ok, "text x-height");
    put(contrast_ok, "moderate contrast");
    put(spacing_ok, "normal spacing");
    put(widely_used, "widely used");

    let core = width_ok && not_display && x_height_ok && contrast_ok && spacing_ok;
    let lifted = widely_used && weights.len() >= 2 && italic;
    Workhorse { is: core && (text_family || lifted), passed, failed }
}

/// Google's popularity rank by normalised family name. Empty when the list was never fetched.
pub fn popularity(conn: &Connection) -> HashMap<String, u32> {
    let mut out = HashMap::new();
    if let Ok(mut st) = conn.prepare("SELECT norm, popularity FROM google_families WHERE popularity IS NOT NULL") {
        if let Ok(rows) = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))) {
            for (norm, rank) in rows.flatten() {
                out.insert(norm, rank.max(0) as u32);
            }
        }
    }
    out
}

/// The assessment of every family in `all`, by family name.
pub fn assess_all(all: &[FontData], popularity: &HashMap<String, u32>) -> HashMap<String, Workhorse> {
    let mut by_family: HashMap<&str, Vec<&FontData>> = HashMap::new();
    for f in all {
        by_family.entry(f.font_family.as_str()).or_default().push(f);
    }
    by_family
        .into_iter()
        .map(|(family, files)| {
            let rank = popularity.get(&crate::google_list::normalize_family(family)).copied();
            (family.to_string(), assess(&files, rank))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(family: &str, name: &str, weight: u16, style: &str) -> FontData {
        FontData {
            font_id: format!("{family}-{name}"),
            font_family: family.into(),
            skeleton: "geometric".into(),
            flesh_contrast: "linear".into(),
            flesh_serif: 0,
            weight,
            x_height_ratio: Some(0.5),
            cap_height_ratio: Some(0.7),
            ascender_descender_ratio: None,
            foundry: None,
            designer: None,
            file_name: name.into(),
            optical_role: None,
            superfamily_group: None,
            superfamily_role: None,
            weight_range_min: None,
            weight_range_max: None,
            spacing_personality: None,
            width_class: None,
            vendor_id: None,
            file_path: format!("/x/{name}"),
            style: style.into(),
            is_variable: false,
            wght_axis_max: 0,
            ital_axis: false,
        }
    }

    fn text_family(family: &str) -> Vec<FontData> {
        vec![
            file(family, "Text-Regular.otf", 400, "normal"),
            file(family, "Text-Italic.otf", 400, "italic"),
            file(family, "Text-Medium.otf", 500, "normal"),
            file(family, "Text-Bold.otf", 700, "normal"),
            file(family, "Text-Light.otf", 300, "normal"),
        ]
    }

    fn assess_owned(files: &[FontData], rank: Option<u32>) -> Workhorse {
        let refs: Vec<&FontData> = files.iter().collect();
        assess(&refs, rank)
    }

    #[test]
    fn a_full_text_family_is_a_workhorse() {
        let w = assess_owned(&text_family("Acme Text"), None);
        assert!(w.is, "{w:?}");
        assert!(w.passed.contains(&"text family") && w.passed.contains(&"normal width"));
    }

    #[test]
    fn one_weight_and_no_italic_is_not() {
        let w = assess_owned(&[file("Acme Mono Display", "Acme-Regular.otf", 400, "normal")], None);
        assert!(!w.is);
        assert!(w.failed.contains(&"text family"));
    }

    #[test]
    fn condensed_compressed_and_extended_are_out() {
        for name in ["Test National 2 Compressed", "Test Söhne Schmal", "Acme Condensed", "Acme Extended"] {
            let w = assess_owned(&text_family(name), Some(10));
            assert!(!w.is, "{name}");
            assert!(w.failed.contains(&"normal width"), "{name}");
        }
        let mut wide = text_family("Acme Sans");
        for f in &mut wide { f.width_class = Some("expanded".into()); }
        assert!(!assess_owned(&wide, None).is);
    }

    #[test]
    fn display_cuts_are_out() {
        assert!(!assess_owned(&text_family("Acme Display"), None).is);
        assert!(!assess_owned(&text_family("Acme Poster"), None).is);
    }

    #[test]
    fn x_height_and_contrast_need_to_be_moderate() {
        let mut tiny = text_family("Acme Small");
        for f in &mut tiny { f.x_height_ratio = Some(0.36); }
        assert!(!assess_owned(&tiny, None).is);
        let mut didone = text_family("Acme Didone");
        for f in &mut didone { f.flesh_contrast = "high".into(); }
        assert!(!assess_owned(&didone, None).is);
    }

    #[test]
    fn tight_or_open_spacing_marks_a_display_face() {
        for spacing in ["tight", "open"] {
            let mut fam = text_family("Acme Spaced");
            for f in &mut fam { f.spacing_personality = Some(spacing.into()); }
            let w = assess_owned(&fam, None);
            assert!(!w.is, "{spacing}");
            assert!(w.failed.contains(&"normal spacing"));
        }
        let mut normal = text_family("Acme Normal");
        for f in &mut normal { f.spacing_personality = Some("normal".into()); }
        assert!(assess_owned(&normal, None).is);
    }

    #[test]
    fn a_variable_family_with_a_weight_range_counts() {
        let mut vf = file("Acme Var", "AcmeVar[wght].ttf", 400, "normal");
        vf.is_variable = true;
        vf.wght_axis_max = 900;
        vf.weight_range_min = Some(100);
        vf.weight_range_max = Some(900);
        let mut it = file("Acme Var", "AcmeVar-Italic[wght].ttf", 400, "italic");
        it.is_variable = true;
        it.wght_axis_max = 900;
        assert!(assess_owned(&[vf, it], None).is);
    }

    #[test]
    fn popularity_lifts_a_smaller_family_but_not_a_bad_fit() {
        let small = vec![file("Acme Pop", "Pop-Regular.otf", 400, "normal"), file("Acme Pop", "Pop-Italic.otf", 400, "italic"),
                         file("Acme Pop", "Pop-Bold.otf", 700, "normal")];
        assert!(!assess_owned(&small, None).is, "three weights, unknown to Google");
        assert!(assess_owned(&small, Some(40)).is, "three weights and in the top 150");
        assert!(!assess_owned(&small, Some(900)).is, "listed, but not widely used");
        assert!(!assess_owned(&text_family("Acme Compressed"), Some(1)).is, "popularity never rescues a bad width");
    }
}
