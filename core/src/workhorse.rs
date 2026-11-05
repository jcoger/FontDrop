//! Is this family a dependable text face? A workhorse: the kind a designer sets a paragraph in without a second
//! thought. Reading ranks these first, so the top of the list is a safe choice and the characterful faces come after.
//!
//! The answer is a few named signals, not a score, so it can be explained in one line:
//!   text family   4 or more weights (or a `wght` range that spans 300 to 700) and a true italic
//!   normal width  measured: the mean advance of "n", "o" and "H" over the em is 0.56 to 0.72 (a condensed face is
//!                 under 0.5, an extended one over 0.75). The width class and the name can only fail it.
//!   text cut      no Display, Poster, Headline, Deck or Banner in the name, and none of the width words
//!   text x-height measured: 0.44 to 0.58 of the em
//!   moderate contrast   measured: the thickest stroke of the "O" is at most 4.5 times the thinnest. Didone and
//!                 other high-contrast faces are over 5.
//!   widely used   in the top of Google Fonts' popularity rank (a lift, see below)
//!
//! A signal is passed, failed or UNKNOWN. A file that was not measured is unknown, and unknown is never a pass:
//! a family with an unknown core signal is not a workhorse, and says which signal it could not read.
//!
//! A family is a workhorse when every signal above except "widely used" passes. A widely used family may be a
//! workhorse on a fuller list of weights alone: two weights and an italic are enough for a face most sites trust.
//! Faces not on Google (most of a designer's library) get no lift; they stand on the measured signals.

use crate::pairing::FontData;
use rusqlite::Connection;
use std::collections::HashMap;

/// The Google popularity rank (1 = most used) at or under which a face counts as widely used.
pub const WIDELY_USED_RANK: u32 = 150;
/// The x-height range of a text face, as a fraction of the em.
pub const TEXT_X_HEIGHT: std::ops::RangeInclusive<f64> = 0.44..=0.58;
/// The mean advance of "n", "o" and "H" over the em for a text width: from the library's lower quartile (0.56) to its 90th
/// percentile (0.72). The median is 0.61; the 10th percentile is 0.48 (condensed). Times New Roman measures 0.57.
pub const TEXT_ADVANCE: std::ops::RangeInclusive<f64> = 0.56..=0.72;
/// The middle of the library's advance measure; the tie-break for a family with several widths.
pub const LIBRARY_MEDIAN_ADVANCE: f64 = 0.61;
/// The most contrast (thickest over thinnest stroke) a text face has. Library median 1.4, 75th percentile 2.9, 90th 5.5.
/// The usual text serifs measure 2 to 3.5 (Source Serif 4 2.2, Timeless Serif 3.2, Times New Roman 3.2); 4 and over is a
/// high-contrast (Didone-like) cut.
pub const TEXT_CONTRAST_MAX: f64 = 4.0;

/// Words in a family or file name that mark a cut for display sizes or a width a paragraph cannot use.
const DISPLAY_WORDS: &[&str] = &["display", "poster", "headline", "deck", "banner"];
const WIDTH_WORDS: &[&str] = &["compressed", "condensed", "extended", "expanded", "schmal", "narrow", "wide"];

#[derive(Debug, Clone, PartialEq)]
pub struct Workhorse {
    /// A dependable text face.
    pub is: bool,
    /// The signals the family has, by name, in a fixed order.
    pub passed: Vec<&'static str>,
    /// The signals it fails.
    pub failed: Vec<&'static str>,
    /// The signals that could not be read, because the file was never measured. Never counted as a pass.
    pub unknown: Vec<&'static str>,
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
    let mut unknown: Vec<&'static str> = Vec::new();
    // Some(true) passes, Some(false) fails, None is unknown: never a pass.
    let mut put = |sig: Option<bool>, name: &'static str| match sig {
        Some(true) => passed.push(name),
        Some(false) => failed.push(name),
        None => unknown.push(name),
    };
    if files.is_empty() {
        return Workhorse { is: false, passed, failed: vec!["text family"], unknown };
    }

    // The regular, upright file stands for the family: nearest weight 400, not slanted.
    let upright = |f: &&&FontData| !crate::names::is_slanted(&f.file_name, &f.style);
    // A family with several widths (PP Right Grotesk: Tall, Compact, Spatial) is judged by its width nearest the
    // library's median, since that is the style a paragraph would use.
    let by_width = |f: &&&FontData| f.advance_ratio.map_or(f64::MAX, |a| (a - LIBRARY_MEDIAN_ADVANCE).abs());
    let rep = files
        .iter()
        .filter(upright)
        .min_by(|a, b| {
            ((a.weight as i32 - 400).abs(), by_width(a)).partial_cmp(&((b.weight as i32 - 400).abs(), by_width(b))).unwrap_or(std::cmp::Ordering::Equal)
        })
        .or_else(|| files.first())
        .copied()
        .unwrap();

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
    // The four text styles (regular, italic, bold, bold italic) are enough too: Times New Roman and Georgia ship
    // exactly those, and nobody doubts them for a paragraph.
    let style = |slanted: bool, bold: bool| {
        files.iter().any(|f| {
            let is_slanted = crate::names::is_slanted(&f.file_name, &f.style);
            let reaches_bold = f.is_variable && f.wght_axis_max >= 600;
            let slant_ok = if slanted { is_slanted || (f.is_variable && f.ital_axis) } else { !is_slanted || (f.is_variable && f.ital_axis) };
            slant_ok && if bold { f.weight >= 600 || reaches_bold } else { f.weight < 600 || reaches_bold }
        })
    };
    let four_styles = style(false, false) && style(false, true) && style(true, false) && style(true, true);
    let text_family = (full_weights && italic) || four_styles;

    // Width: measured. The class and the names can fail it (a face named Condensed is not normal width whatever
    // the outlines say), but only a measurement passes it.
    let named_wide_or_narrow = matches!(rep.width_class.as_deref(), Some("condensed" | "compressed" | "expanded" | "extended"))
        || has_word(&rep.font_family, WIDTH_WORDS)
        || has_word(&rep.file_name, WIDTH_WORDS);
    let width = if named_wide_or_narrow { Some(false) } else { rep.advance_ratio.map(|a| TEXT_ADVANCE.contains(&a)) };
    let not_display = !has_word(&rep.font_family, DISPLAY_WORDS) && !has_word(&rep.file_name, DISPLAY_WORDS);
    let x_height = rep.x_height_ratio.map(|x| TEXT_X_HEIGHT.contains(&x));
    let contrast = rep.stroke_contrast_ratio.map(|c| c <= TEXT_CONTRAST_MAX);
    let widely_used = popularity.map_or(false, |r| r <= WIDELY_USED_RANK);

    put(Some(text_family), "text family");
    put(width, "normal width");
    put(Some(not_display), "text cut");
    put(x_height, "text x-height");
    put(contrast, "moderate contrast");
    put(Some(widely_used), "widely used");

    let core = width == Some(true) && not_display && x_height == Some(true) && contrast == Some(true);
    let lifted = widely_used && weights.len() >= 2 && italic;
    Workhorse { is: core && (text_family || lifted), passed, failed, unknown }
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
            spacing_personality: Some("normal".into()),
            width_class: None,
            vendor_id: None,
            file_path: format!("/x/{name}"),
            style: style.into(),
            is_variable: false,
            wght_axis_max: 0,
            ital_axis: false,
            stroke_contrast_ratio: Some(1.5),
            advance_ratio: Some(0.62),
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
        for f in &mut didone { f.stroke_contrast_ratio = Some(6.0); }
        assert!(!assess_owned(&didone, None).is);
    }

    /// Missing data is unknown, and unknown is never a pass: a family whose file was never measured is not a workhorse.
    #[test]
    fn an_unmeasured_signal_is_unknown_and_never_a_pass() {
        let measures: [(&str, fn(&mut FontData)); 3] = [
            ("moderate contrast", |f| f.stroke_contrast_ratio = None),
            ("normal width", |f| f.advance_ratio = None),
            ("text x-height", |f| f.x_height_ratio = None),
        ];
        for (signal, clear) in measures {
            let mut fam = text_family("Acme Unread");
            for f in &mut fam { clear(f); }
            let w = assess_owned(&fam, Some(1));
            assert!(!w.is, "{signal}: unknown must not pass, even for a popular family");
            assert!(w.unknown.contains(&signal), "{signal}");
            assert!(!w.passed.contains(&signal) && !w.failed.contains(&signal), "{signal}");
        }
        assert!(assess_owned(&text_family("Acme Read"), None).unknown.is_empty());
    }

    #[test]
    fn width_and_contrast_thresholds_come_from_the_measures() {
        let at = |advance: f64, contrast: f64| {
            let mut fam = text_family("Acme Measured");
            for f in &mut fam { f.advance_ratio = Some(advance); f.stroke_contrast_ratio = Some(contrast); }
            assess_owned(&fam, None)
        };
        assert!(at(0.62, 1.2).is && at(0.62, 3.2).is, "a Times-like contrast of 3.2 is moderate");
        assert!(at(0.62, 4.0).is, "the limit is included");
        assert!(!at(0.62, 4.36).is && !at(0.62, 8.3).is, "4.4 and 8.3 are high-contrast cuts");
        assert!(!at(0.357, 1.2).is, "a compressed face (0.36) is not normal width");
        assert!(!at(0.80, 1.2).is, "an extended face (0.80) is not");
        assert!(!at(0.54, 1.2).is, "0.54 is narrower than a quarter of the library");
        assert!(at(0.56, 1.2).is && at(0.72, 1.2).is, "the band includes its ends");
    }

    #[test]
    fn the_four_text_styles_make_a_text_family() {
        // Regular, italic, bold, bold italic: two weights, as Times New Roman ships.
        let fam = vec![
            file("Acme Classic", "Classic-Regular.otf", 400, "normal"),
            file("Acme Classic", "Classic-Italic.otf", 400, "italic"),
            file("Acme Classic", "Classic-Bold.otf", 700, "normal"),
            file("Acme Classic", "Classic-BoldItalic.otf", 700, "italic"),
        ];
        assert!(assess_owned(&fam, None).is);
        assert!(!assess_owned(&fam[..3], None).is, "no bold italic, and not enough weights");
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
