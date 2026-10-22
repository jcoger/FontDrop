//! "Same family" pairing: the Display family offered as its own partner.
//!
//! Designers often set headline and body in one family, changing width or weight
//! between them. The ranked list is one entry per family and excludes the Display
//! family, so it never offered this. A family qualifies when it has range: at least
//! two of these four signals.
//!   - more than one width (separate width styles, or a `wdth` axis);
//!   - a text or optical cut (a style named Text, Caption, Micro or Book, or an `opsz` axis);
//!   - four or more weights (or a `wght` axis spanning 300 units or more);
//!   - an italic.
//!
//! The offer carries a suggested style for body text. It is shown even when the family
//! would fail the long-text rule, with evidence that says why it may be weak.
//! Sources: STO pp.40-41; LAT ch.5; TWC 68 (the superfamily sources).

use std::collections::{BTreeSet, HashSet};

use crate::pairing::{BodyStyle, Evidence, FontData, PairScore};

/// What a family's variable fonts add beyond its file names. Read from the files.
#[derive(Default, Clone, Debug)]
pub struct AxisInfo {
    /// Widest `wght` range seen: (min, max).
    pub wght: Option<(f32, f32)>,
    /// Widest `wdth` range seen: (min, max).
    pub wdth: Option<(f32, f32)>,
    pub opsz: bool,
    /// An `ital` or `slnt` axis.
    pub italic: bool,
}

impl AxisInfo {
    fn wght_span(&self) -> f32 { self.wght.map_or(0.0, |(a, b)| b - a) }
    fn wdth_span(&self) -> f32 { self.wdth.map_or(0.0, |(a, b)| b - a) }
}

/// Reads the axes of every variable file in `files`. Files that cannot be read add nothing.
pub fn read_axes(files: &[&FontData]) -> AxisInfo {
    use skrifa::{FontRef, MetadataProvider};
    let mut info = AxisInfo::default();
    let widen = |slot: &mut Option<(f32, f32)>, lo: f32, hi: f32| {
        *slot = Some(match *slot { Some((a, b)) => (a.min(lo), b.max(hi)), None => (lo, hi) });
    };
    for f in files.iter().filter(|f| f.is_variable) {
        let Ok(data) = std::fs::read(&f.file_path) else { continue };
        let Ok(font) = FontRef::from_index(&data, 0) else { continue };
        for axis in font.axes().iter() {
            match axis.tag().to_string().as_str() {
                "wght" => widen(&mut info.wght, axis.min_value(), axis.max_value()),
                "wdth" => widen(&mut info.wdth, axis.min_value(), axis.max_value()),
                "opsz" => info.opsz = true,
                "ital" | "slnt" => info.italic = true,
                _ => {}
            }
        }
    }
    info
}

// ── Reading a style from its file name ───────────────────────────────────────

/// Words of a file name or family name: "Agrandir-TextBold.otf" -> [agrandir, text, bold].
fn words(name: &str) -> Vec<String> {
    let stem = match name.rfind('.') {
        Some(i) if name.len() - i <= 6 => &name[..i],
        _ => name,
    };
    let mut out: Vec<String> = Vec::new();
    for chunk in stem.split(|c: char| !c.is_alphanumeric()) {
        let chars: Vec<char> = chunk.chars().collect();
        let mut cur = String::new();
        for (i, &c) in chars.iter().enumerate() {
            let prev = if i > 0 { Some(chars[i - 1]) } else { None };
            let next = chars.get(i + 1).copied();
            let boundary = match prev {
                Some(p) if c.is_uppercase() => p.is_lowercase() || p.is_ascii_digit() || (p.is_uppercase() && next.is_some_and(|n| n.is_lowercase())),
                Some(p) if c.is_ascii_digit() => p.is_alphabetic(),
                Some(p) if c.is_lowercase() => p.is_ascii_digit(),
                _ => false,
            };
            if boundary && !cur.is_empty() {
                out.push(cur.to_lowercase());
                cur.clear();
            }
            cur.push(c);
        }
        if !cur.is_empty() { out.push(cur.to_lowercase()); }
    }
    out
}

/// The words that name the style: the file name's words minus the family's own words.
fn style_words(file_name: &str, family: &str) -> Vec<String> {
    let family_words: HashSet<String> = words(family).into_iter().collect();
    words(file_name).into_iter().filter(|w| !family_words.contains(w)).collect()
}

/// A named width, from the style words. None means no width word (the normal width).
fn width_word(style: &[String]) -> Option<&'static str> {
    style.iter().find_map(|w| match w.as_str() {
        "compressed" | "extracondensed" | "ultracondensed" => Some("compressed"),
        "tight" => Some("tight"),
        "narrow" => Some("narrow"),
        "compact" => Some("compact"),
        "semicondensed" => Some("semicondensed"),
        "condensed" | "cond" => Some("condensed"),
        "wide" => Some("wide"),
        "grand" => Some("grand"),
        "extended" | "expanded" | "ext" | "extraexpanded" | "ultraexpanded" | "semiexpanded" => Some("extended"),
        _ => None,
    })
}

fn is_narrow(label: &str) -> bool {
    matches!(label, "compressed" | "tight" | "narrow" | "compact" | "semicondensed" | "condensed")
}

fn is_italic(f: &FontData, style: &[String]) -> bool {
    f.style == "italic" || style.iter().any(|w| matches!(w.as_str(), "italic" | "oblique" | "kursiv" | "slanted" | "ital"))
}

fn has_text_cut_word(style: &[String]) -> bool {
    style.iter().any(|w| matches!(w.as_str(), "text" | "caption" | "micro" | "book"))
}

/// One file with what we read from its name.
struct Style<'a> {
    f: &'a FontData,
    words: Vec<String>,
    /// "normal" or a named width.
    width: String,
    italic: bool,
}

fn styles<'a>(files: &[&'a FontData]) -> Vec<Style<'a>> {
    let named: Vec<(&FontData, Vec<String>)> = files.iter().map(|f| (*f, style_words(&f.file_name, &f.font_family))).collect();
    // No width word anywhere in the family: trust the width flags in the files instead.
    let any_word = named.iter().any(|(_, w)| width_word(w).is_some());
    named
        .into_iter()
        .map(|(f, words)| {
            let width = match width_word(&words) {
                Some(w) => w.to_string(),
                None if !any_word && f.width_class.as_deref() == Some("condensed") => "condensed".into(),
                None if !any_word && matches!(f.width_class.as_deref(), Some("expanded")) => "extended".into(),
                None => "normal".into(),
            };
            let italic = is_italic(f, &words);
            Style { f, words, width, italic }
        })
        .collect()
}

// ── Range ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub struct Range {
    pub widths: usize,
    pub styles: usize,
    pub weights: usize,
    pub text_cut: bool,
    pub optical: bool,
    pub italic: bool,
    pub several_widths: bool,
    pub many_weights: bool,
    /// How many of the four signals the family has.
    pub signals: usize,
}

impl Range {
    pub fn has_range(&self) -> bool { self.signals >= 2 }

    /// "5 widths, 16 styles, 6 weights, italic, text cut"
    pub fn detail(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if self.several_widths { parts.push(if self.widths > 1 { format!("{} widths", self.widths) } else { "variable width".into() }); }
        parts.push(format!("{} {}", self.styles, if self.styles == 1 { "style" } else { "styles" }));
        if self.many_weights { parts.push(if self.weights >= 4 { format!("{} weights", self.weights) } else { "variable weight".into() }); }
        if self.italic { parts.push("italic".into()); }
        if self.optical { parts.push("optical sizes".into()); } else if self.text_cut { parts.push("text cut".into()); }
        parts.join(", ")
    }
}

fn measure(styles: &[Style], axes: &AxisInfo) -> Range {
    let widths: BTreeSet<&str> = styles.iter().map(|s| s.width.as_str()).collect();
    let weights: BTreeSet<u16> = styles.iter().map(|s| s.f.weight).collect();
    let stems: BTreeSet<String> = styles
        .iter()
        .map(|s| match s.f.file_name.rfind('.') { Some(i) => s.f.file_name[..i].to_lowercase(), None => s.f.file_name.to_lowercase() })
        .collect();
    let several_widths = widths.len() > 1 || axes.wdth_span() >= 20.0;
    let optical = axes.opsz;
    let text_cut = optical || styles.iter().any(|s| has_text_cut_word(&s.words));
    let many_weights = weights.len() >= 4 || axes.wght_span() >= 300.0;
    let italic = styles.iter().any(|s| s.italic) || axes.italic;
    let signals = [several_widths, text_cut, many_weights, italic].iter().filter(|b| **b).count();
    Range { widths: widths.len(), styles: stems.len().max(1), weights: weights.len(), text_cut, optical, italic, several_widths, many_weights, signals }
}

// ── Long text ────────────────────────────────────────────────────────────────

/// Why the family may be weak for long text, or None when one style set carries it.
/// A set is regular, italic, bold and bold italic at a normal width, or a variable
/// equivalent (a `wght` axis from 400 to 700 with an italic). Display cuts and mono faces
/// fail on their own, whatever they ship (Typewolf 21, 22, 81; Reynolds).
fn long_text_issue(files: &[&FontData], styles: &[Style], axes: &AxisInfo) -> Option<String> {
    let family = files.first().map(|f| f.font_family.to_lowercase()).unwrap_or_default();
    if ["display", "poster", "headline", "deck", "banner"].iter().any(|k| family.contains(k)) {
        return Some("The name says display cut".into());
    }
    if family.contains("mono") || files.iter().any(|f| f.optical_role.as_deref() == Some("mono")) {
        return Some("Monospaced".into());
    }
    let mut groups: Vec<&str> = styles.iter().map(|s| s.width.as_str()).filter(|w| !is_narrow(w)).collect();
    groups.sort();
    groups.dedup();
    let complete = groups.iter().any(|g| {
        let at = |italic: bool, bold: bool| styles.iter().any(|s| s.width == *g && s.italic == italic && (s.f.weight >= 600) == bold);
        at(false, false) && at(true, false) && at(false, true) && at(true, true)
    });
    let variable = axes.wght.is_some_and(|(lo, hi)| lo <= 400.0 && hi >= 700.0)
        && (axes.italic || styles.iter().any(|s| s.italic));
    if complete || variable {
        None
    } else {
        Some("No regular, italic, bold and bold italic set at a normal width".into())
    }
}

// ── Body style ───────────────────────────────────────────────────────────────

fn label(s: &Style) -> String {
    // A variable file is named after its axes ("VariableFont_opsz,wght"); say what it is.
    if s.f.is_variable { return "Variable".into(); }
    if s.words.is_empty() { return "Regular".into(); }
    s.words.iter().map(|w| w.chars().next().map(|c| c.to_uppercase().collect::<String>() + &w[c.len_utf8()..]).unwrap_or_default()).collect::<Vec<_>>().join(" ")
}

/// Which style to set body text in: a text or optical cut first, then Regular or Book at the
/// normal width. Never italic, and never a text cut that is bold (TextBold is not body).
fn suggest(styles: &[Style], axes: &AxisInfo, excluded: &HashSet<String>) -> Option<BodyStyle> {
    let usable: Vec<&Style> = styles.iter().filter(|s| !excluded.contains(&s.f.font_id)).collect();
    // Nearest to weight 400; a .otf beats a .ttf of the same style.
    let key = |s: &&Style| (((s.f.weight as i32) - 400).abs(), s.f.file_name.to_lowercase().ends_with(".ttf") as u8, s.f.file_name.clone());
    let upright = |s: &&Style| !s.italic;
    let body_weight = |s: &&Style| (300..=500).contains(&s.f.weight);
    let normal_width = |s: &&Style| s.width == "normal";
    let text_cut = |s: &&Style| s.words.iter().any(|w| matches!(w.as_str(), "text" | "caption" | "micro"));

    let pick = usable.iter().copied().filter(upright).filter(body_weight).filter(normal_width).filter(text_cut)
        .min_by_key(key)
        // An optical-size variable font carries its own text setting.
        .or_else(|| if axes.opsz { usable.iter().copied().filter(upright).filter(|s| s.f.is_variable).min_by_key(key) } else { None })
        .or_else(|| usable.iter().copied().filter(upright).filter(body_weight).filter(normal_width).min_by_key(key))
        .or_else(|| usable.iter().copied().filter(upright).min_by_key(key))
        .or_else(|| usable.iter().copied().min_by_key(key))?;
    Some(BodyStyle { font_id: pick.f.font_id.clone(), label: label(pick) })
}

// ── The offer ────────────────────────────────────────────────────────────────

/// The Display family as a candidate, or None when it has no range (or every file is hidden).
/// `user_excluded` is the user's own exclusions and hides, NOT the long-text rule: the
/// family is shown even when it fails that rule, with evidence saying so.
pub fn offer(primary: &FontData, all: &[FontData], user_excluded: &HashSet<String>) -> Option<PairScore> {
    let family: Vec<&FontData> = all.iter().filter(|f| f.font_family == primary.font_family).collect();
    if family.len() < 2 && !primary.is_variable {
        return None; // one file cannot have range, unless it is a variable font
    }
    offer_with_axes(primary, &family, user_excluded, &read_axes(&family))
}

/// `offer`, with the axes given. The seam for tests, which have no font files.
pub fn offer_with_axes(_primary: &FontData, family: &[&FontData], user_excluded: &HashSet<String>, axes: &AxisInfo) -> Option<PairScore> {
    let styles = styles(family);
    let range = measure(&styles, axes);
    if !range.has_range() {
        return None;
    }
    let body = suggest(&styles, axes, user_excluded)?;
    let detail = range.detail();
    let mut evidence = vec![Evidence {
        lens: "Same family".into(),
        detail: detail.clone(),
        source: "STO pp.40-41; LAT ch.5; TWC 68".into(),
        strength: "guideline".into(),
        effect: 1,
    }];
    if let Some(issue) = long_text_issue(family, &styles, axes) {
        evidence.push(Evidence {
            lens: "Long text".into(),
            detail: issue,
            source: "TWC 18/19/36; STO".into(),
            strength: "guideline".into(),
            effect: -1,
        });
    }
    Some(PairScore {
        font_id: body.font_id.clone(),
        score: 100,
        precise: 1000.0,
        pair_type: "same_family".into(),
        reason: format!("Same family \u{00B7} {detail}"),
        evidence,
        suggested_body_style: Some(body),
    })
}

/// Puts the offer first in a ranked list, then trims to `limit`.
pub fn put_first(mut ranked: Vec<PairScore>, offer: Option<PairScore>, limit: usize) -> Vec<PairScore> {
    if let Some(o) = offer {
        ranked.insert(0, o);
        ranked.truncate(limit);
    }
    ranked
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(id: &str, family: &str, file_name: &str, weight: u16, italic: bool) -> FontData {
        FontData {
            font_id: id.into(),
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
            file_name: file_name.into(),
            optical_role: Some("general".into()),
            superfamily_group: None,
            superfamily_role: None,
            weight_range_min: None,
            weight_range_max: None,
            spacing_personality: None,
            width_class: Some("normal".into()),
            vendor_id: None,
            file_path: format!("/x/{file_name}"),
            style: if italic { "italic" } else { "normal" }.into(),
            is_variable: false,
        }
    }

    /// A made-up family with range: five widths, a text cut, many weights, italics.
    fn wide_family() -> Vec<FontData> {
        let name = "Acme";
        [
            ("Tight.otf", 400, false), ("TightBlack.otf", 900, false), ("Narrow.otf", 400, false),
            ("Regular.otf", 400, false), ("Regular.ttf", 400, false), ("Italic.otf", 400, true),
            ("Wide.otf", 400, false), ("WideLight.otf", 300, false), ("Grand.otf", 400, false),
            ("GrandHeavy.otf", 800, false), ("TextBold.otf", 700, false), ("Text.otf", 400, false),
        ]
        .iter()
        .enumerate()
        .map(|(i, (f, w, it))| file(&format!("a{i}"), name, &format!("Acme-{f}"), *w, *it))
        .collect()
    }

    fn refs(v: &[FontData]) -> Vec<&FontData> { v.iter().collect() }

    #[test]
    fn a_family_with_range_is_offered_first_with_its_range_as_evidence() {
        let fam = wide_family();
        let o = offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &AxisInfo::default()).expect("has range");
        assert_eq!(o.pair_type, "same_family");
        let e = &o.evidence[0];
        assert_eq!(e.lens, "Same family");
        assert_eq!(e.strength, "guideline");
        assert_eq!(e.source, "STO pp.40-41; LAT ch.5; TWC 68");
        // Tight, Narrow, Wide, Grand and the normal width.
        assert!(e.detail.starts_with("5 widths, "), "{}", e.detail);
        assert!(e.detail.contains("styles") && e.detail.contains("italic") && e.detail.contains("text cut"), "{}", e.detail);
        // Complete set is not there (no bold italic), so the long-text caveat rides along.
        assert!(o.evidence.iter().any(|x| x.lens == "Long text" && x.effect < 0), "{:?}", o.evidence);
        // It leads the flat list and the buckets.
        let rest = vec![PairScore { font_id: "z".into(), score: 70, precise: 70.0, pair_type: "contrast".into(), reason: String::new(), evidence: vec![], suggested_body_style: None }];
        let list = put_first(rest, Some(o), 5);
        assert_eq!(list[0].pair_type, "same_family");
        assert_eq!(list.len(), 2);
        assert_eq!(put_first(vec![], None, 5).len(), 0, "no offer, no change");
    }

    #[test]
    fn one_signal_is_not_range() {
        // Only weights: five of them, one width, no italic, no text cut.
        let fam: Vec<FontData> = [("Light", 300), ("Regular", 400), ("Medium", 500), ("Bold", 700), ("Black", 900)]
            .iter()
            .enumerate()
            .map(|(i, (n, w))| file(&format!("p{i}"), "Plain Sans", &format!("PlainSans-{n}.otf"), *w, false))
            .collect();
        assert!(offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &AxisInfo::default()).is_none());
        // One file, nothing variable: no range either.
        let one = vec![file("o", "Lonely", "Lonely-Regular.otf", 400, false)];
        assert!(offer(&one[0], &one, &HashSet::new()).is_none());
    }

    #[test]
    fn a_variable_font_gets_range_from_its_axes() {
        let mut vf = file("v", "Acme Flex", "AcmeFlex[wdth,wght].ttf", 400, false);
        vf.is_variable = true;
        let fam = vec![vf];
        let axes = AxisInfo { wght: Some((100.0, 900.0)), wdth: Some((75.0, 125.0)), opsz: false, italic: false };
        let o = offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &axes).expect("width + weight axes");
        assert!(o.evidence[0].detail.contains("variable width") && o.evidence[0].detail.contains("variable weight"), "{}", o.evidence[0].detail);
        // wght 100-900 with no italic: not a full long-text set.
        assert!(o.evidence.iter().any(|x| x.lens == "Long text"));
        // With an italic axis the variable equivalent carries long text.
        let axes = AxisInfo { italic: true, ..axes };
        let o = offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &axes).unwrap();
        assert!(!o.evidence.iter().any(|x| x.lens == "Long text"));
    }

    #[test]
    fn suggested_body_style_prefers_a_text_cut_then_regular_at_normal_width() {
        let fam = wide_family();
        let o = offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &AxisInfo::default()).unwrap();
        let body = o.suggested_body_style.unwrap();
        assert_eq!(body.label, "Text", "a regular-weight text cut wins");
        assert_eq!(o.font_id, body.font_id);

        // Without the regular-weight text cut: Regular at normal width (never TextBold, never a narrow cut), .otf over .ttf.
        let fam: Vec<FontData> = wide_family().into_iter().filter(|f| f.file_name != "Acme-Text.otf").collect();
        let o = offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &AxisInfo::default()).unwrap();
        let body = o.suggested_body_style.unwrap();
        assert_eq!(body.label, "Regular");
        let chosen = fam.iter().find(|f| f.font_id == body.font_id).unwrap();
        assert_eq!(chosen.file_name, "Acme-Regular.otf");

        // A hidden file is never suggested.
        let hidden: HashSet<String> = [chosen.font_id.clone()].into_iter().collect();
        let o = offer_with_axes(&fam[0], &refs(&fam), &hidden, &AxisInfo::default()).unwrap();
        assert_ne!(o.suggested_body_style.unwrap().font_id, chosen.font_id);

        // An optical-size variable font suggests itself.
        let mut vf = file("v", "Acme Opsz", "AcmeOpsz[opsz,wght].ttf", 400, false);
        vf.is_variable = true;
        let fam = vec![vf];
        let axes = AxisInfo { wght: Some((300.0, 700.0)), opsz: true, ..AxisInfo::default() };
        let o = offer_with_axes(&fam[0], &refs(&fam), &HashSet::new(), &axes).unwrap();
        assert_eq!(o.suggested_body_style.unwrap().font_id, "v");
        assert!(o.evidence[0].detail.contains("optical sizes"));
    }

    #[test]
    fn style_words_drop_the_family_name() {
        assert_eq!(style_words("Agrandir-TextBold.otf", "Agrandir"), vec!["text", "bold"]);
        assert_eq!(style_words("SourceSerif4Text-Regular.otf", "Source Serif 4"), vec!["text", "regular"]);
        assert_eq!(style_words("Acme Variable.ttf", "Acme"), vec!["variable"]);
        assert_eq!(style_words("AcmeText-Regular.otf", "Acme Text"), vec!["regular"]);
    }

    /// What the offer says for a family in a real library COPY:
    ///   FONTDROP_DB=<copy> FAMILY=Agrandir cargo test --lib same_family_report -- --ignored --nocapture
    #[test]
    #[ignore]
    fn same_family_report() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
        assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy");
        let family = std::env::var("FAMILY").expect("set FAMILY");
        let conn = rusqlite::Connection::open(&path).unwrap();
        let all = crate::pairing::load_all_fonts(&conn).unwrap();
        let primary = all.iter().find(|f| f.font_family == family).expect("family not found");
        match offer(primary, &all, &HashSet::new()) {
            Some(o) => {
                let id = &o.suggested_body_style.as_ref().unwrap().font_id;
                let file = &all.iter().find(|f| &f.font_id == id).unwrap().file_name;
                println!("OFFER {} | body: {:?} ({file})", o.reason, o.suggested_body_style);
                for e in &o.evidence { println!("  {} | {} | {} | {}", e.lens, e.detail, e.strength, e.effect); }
            }
            None => println!("NO OFFER"),
        }
    }
}
