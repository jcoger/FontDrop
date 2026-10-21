//! Name-table and file-metadata helpers: what a font file says about itself
//! (family, vendor, trial flag, foundry URL, OS/2 weight and Panose class).

use serde::Serialize;
use ttf_parser::{Face, Style, Tag, Width};

#[derive(Serialize, Clone)]
pub struct Classification {
    pub category: String, // "sans-serif" | "serif" | "script" | "decorative" | "monospace"
    pub style: String,    // "normal" | "italic"
    pub width: String,    // "condensed" | "normal" | "extended"
}

#[cfg(test)]
mod name_tests {
    use super::{looks_trial, strip_instance_words, trial_from_names};
    #[test]
    fn spots_trial_builds() {
        assert!(looks_trial("TestSöhne"));
        assert!(looks_trial("GT Flexa Trial"));
        assert!(looks_trial("This is a demo font for testing only"));
        assert!(!looks_trial("Contest Sans"));
        assert!(!looks_trial("Timeless Serif"));
    }
    #[test]
    fn trial_reads_the_file_name_too() {
        // GT Flexa Var Trial.ttf: every name-table entry is "GT Flexa Var"; the file name carries the word.
        assert!(!trial_from_names(["GT Flexa Var", "GT Flexa Var", "Version 3.000;FEAKit 1.0"]));
        assert!(trial_from_names(["GT Flexa Var", "GT Flexa Var Trial"])); // file stem
        assert!(trial_from_names(["GT Flexa Var", "GT-Flexa-Var-Trial"])); // hyphenated stem
        assert!(!trial_from_names(["Timeless Serif", "Timeless Serif Regular"]));
    }
    #[test]
    fn strips_default_instance_words() {
        assert_eq!(strip_instance_words("Montserrat Thin"), "Montserrat");
        assert_eq!(strip_instance_words("Nunito Sans 12pt ExtraLight 12pt"), "Nunito Sans");
        assert_eq!(strip_instance_words("Merriweather Light 18pt"), "Merriweather");
        assert_eq!(strip_instance_words("Rubik Mono One"), "Rubik Mono One");
        assert_eq!(strip_instance_words("Black"), "Black");
    }
}

pub fn parse_family(stem: &str) -> String {
    let suffixes = [
        "Black", "Bold", "BoldItalic", "ExtraBold", "ExtraLight",
        "Heavy", "Italic", "Light", "Medium", "Regular", "SemiBold",
        "Thin", "Oblique", "Condensed", "Expanded",
    ];

    let mut name = stem.to_string();
    name = name.replace('-', " ").replace('_', " ");

    for suffix in &suffixes {
        let with_space = format!(" {}", suffix);
        if name.ends_with(&with_space) {
            name = name[..name.len() - with_space.len()].to_string();
        }
    }

    name.trim().to_string()
}

/// The family name the font file declares about itself: the typographic family
/// (name ID 16) if present, else the legacy family (name ID 1). File names are
/// unreliable ("TestSöhne-BuchKursiv.otf" is a style of Söhne, not a family), so
/// this is the source of truth; `parse_family` is only the fallback.
/// Collections (.ttc) use their first face.
pub fn read_family_name(path: &std::path::Path) -> Option<String> {
    use skrifa::{string::StringId, FontRef, MetadataProvider};
    let data = std::fs::read(path).ok()?;
    let font = FontRef::from_index(&data, 0).ok()?;
    let name = [StringId::TYPOGRAPHIC_FAMILY_NAME, StringId::FAMILY_NAME]
        .into_iter()
        .find_map(|id| {
            let name = font.localized_strings(id).english_or_first()?.to_string();
            let name = name.trim().to_string();
            (!name.is_empty()).then_some(name)
        })?;
    // A variable font's name often carries its default instance
    // ("Montserrat Thin", "Merriweather Light 18pt"). The family is the rest.
    if font.axes().len() > 0 {
        return Some(strip_instance_words(&name));
    }
    Some(name)
}

/// Drop trailing weight, width and optical-size words from a family name.
pub fn strip_instance_words(name: &str) -> String {
    const WORDS: &[&str] = &[
        "thin", "hairline", "extralight", "ultralight", "light", "book", "regular", "normal",
        "medium", "semibold", "demibold", "bold", "extrabold", "ultrabold", "black", "heavy",
        "italic", "condensed", "expanded", "variable", "vf",
    ];
    let mut words: Vec<&str> = name.split_whitespace().collect();
    while words.len() > 1 {
        let last = words[words.len() - 1].to_lowercase();
        let opsz = last.ends_with("pt") && last[..last.len() - 2].chars().all(|c| c.is_ascii_digit());
        if WORDS.contains(&last.as_str()) || opsz {
            words.pop();
        } else {
            break;
        }
    }
    words.join(" ")
}

/// Who made the font, from inside the file: OS/2 vendor code (the cleanest
/// foundry key, e.g. "PP", "ITFO", "KLIM"), name ID 8 (manufacturer) and
/// name ID 9 (designer). Placeholder vendor codes come back as None.
pub struct NameMeta {
    pub vendor: Option<String>,
    pub manufacturer: Option<String>,
    pub designer: Option<String>,
    /// Trial / test / demo build, from the family name or licence text (IDs 1, 16, 13).
    /// Not a warning: trials are how designers explore and how clients end up
    /// buying fonts. The app flags them at hand-off with a link to the foundry.
    pub trial: bool,
    /// Where to get the font: vendor URL (ID 11), else licence URL (ID 14).
    pub foundry_url: Option<String>,
    /// The file has variation axes (an `fvar` table).
    pub variable: bool,
}

/// Does any of these strings (name-table entries, the file name) read as a trial build?
/// The family names (IDs 1, 16) and the licence text (13) are not enough. "GT Flexa Var Trial.ttf"
/// has no trial word in any of its name-table entries (family, full name, PostScript name,
/// unique ID are all "GT Flexa Var"); only the file name says so. Foundries ship trials
/// with "Trial" in the file name, so the file name counts.
pub fn trial_from_names<'a>(names: impl IntoIterator<Item = &'a str>) -> bool {
    names.into_iter().any(looks_trial)
}

/// Words foundries use for trial builds ("TestSöhne", "GT Flexa Trial", "... Demo").
pub fn looks_trial(text: &str) -> bool {
    let t = text.to_lowercase();
    t.split(|c: char| !c.is_alphanumeric()).any(|w| matches!(w, "trial" | "demo" | "test" | "evaluation" | "testing"))
        || t.starts_with("test")
}

pub fn read_name_meta(path: &std::path::Path) -> Option<NameMeta> {
    use skrifa::raw::TableProvider;
    use skrifa::{string::StringId, FontRef, MetadataProvider};
    let data = std::fs::read(path).ok()?;
    let font = FontRef::from_index(&data, 0).ok()?;
    let text = |id| {
        font.localized_strings(id)
            .english_or_first()
            .map(|s| s.to_string().trim().to_string())
            .filter(|s| !s.is_empty())
    };
    let vendor = font.os2().ok().map(|t| t.ach_vend_id().to_string().trim().to_string()).filter(|v| {
        !v.is_empty() && !matches!(v.to_uppercase().as_str(), "UKWN" | "NONE" | "XXXX" | "----" | "PFED" | "\0\0\0\0")
    });
    let mut names: Vec<String> = [StringId::TYPOGRAPHIC_FAMILY_NAME, StringId::FAMILY_NAME, StringId::FULL_NAME, StringId::LICENSE_DESCRIPTION]
        .into_iter()
        .filter_map(text)
        .collect();
    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
        names.push(stem.to_string());
    }
    let trial = trial_from_names(names.iter().map(String::as_str));
    let foundry_url = [StringId::VENDOR_URL, StringId::LICENSE_URL]
        .into_iter()
        .filter_map(text)
        .find(|u| u.starts_with("http"));
    Some(NameMeta { vendor, manufacturer: text(StringId::MANUFACTURER), designer: text(StringId::DESIGNER), trial, foundry_url, variable: font.axes().len() > 0 })
}

pub struct FontMeta {
    pub classification: Classification,
    pub weight: u16,
}

fn default_meta() -> FontMeta {
    FontMeta {
        classification: Classification {
            category: "sans-serif".to_string(),
            style: "normal".to_string(),
            width: "normal".to_string(),
        },
        weight: 400,
    }
}

pub fn parse_font_meta(path: &std::path::Path, family_name: &str) -> FontMeta {
    // ttf-parser only handles TTF/OTF — WOFF/WOFF2 are compressed, use defaults
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    if !matches!(ext.as_deref(), Some("ttf") | Some("otf") | Some("ttc")) {
        return default_meta();
    }

    let data = match std::fs::read(path) {
        Ok(d) => d,
        Err(_) => return default_meta(),
    };

    let face = match Face::parse(&data, 0) {
        Ok(f) => f,
        Err(_) => return default_meta(),
    };

    let os2 = face.raw_face().table(Tag::from_bytes(b"OS/2"));

    // usWeightClass: OS/2 bytes 4–5 (u16 big-endian)
    let weight = os2
        .and_then(|d| if d.len() >= 6 { Some(u16::from_be_bytes([d[4], d[5]])) } else { None })
        .unwrap_or(400)
        .clamp(100, 900);

    let is_monospace = face.is_monospaced();

    // Style: italic/oblique vs normal
    let style = match face.style() {
        Style::Italic | Style::Oblique => "italic",
        Style::Normal => "normal",
    };

    // Width: condensed / normal / extended
    let width = match face.width() {
        Width::UltraCondensed
        | Width::ExtraCondensed
        | Width::Condensed
        | Width::SemiCondensed => "condensed",
        Width::Normal => "normal",
        Width::SemiExpanded
        | Width::Expanded
        | Width::ExtraExpanded
        | Width::UltraExpanded => "extended",
    };

    // Category: multi-signal heuristic (monospace → Panose → name → sFamilyClass → "other")
    let category = if is_monospace {
        "monospace"
    } else {
        // Signal 1: Panose (OS/2 bytes 32–41, 10-byte array)
        let panose_cat: Option<&str> = os2
            .and_then(|d| if d.len() >= 42 { Some(&d[32..42]) } else { None })
            .and_then(|p| match p[0] {
                2 => match p[1] {
                    2..=10 => Some("serif"),
                    11..=15 => Some("sans-serif"),
                    _ => None,
                },
                3 => Some("script"),
                4 | 5 => Some("decorative"),
                _ => None,
            });

        // Signal 2: Family name keywords (case-insensitive)
        let n = family_name.to_lowercase();
        let name_cat: Option<&str> = if n.contains("mono") || n.contains("code") || n.contains("console") || n.contains("terminal") {
            Some("monospace")
        } else if n.contains("script") || n.contains("hand") || n.contains("brush") || n.contains("callig") || n.contains("cursive") {
            Some("script")
        } else if n.contains("display") || n.contains("ornament") || n.contains("dingbat") || n.contains("symbol") || n.contains("emoji") {
            Some("decorative")
        } else if n.contains("sans") || n.contains("grotesk") || n.contains("gothic") {
            Some("sans-serif")
        } else if n.contains("serif") {
            if !n.contains("sans") { Some("serif") } else { Some("sans-serif") }
        } else {
            None
        };

        // Signal 3: sFamilyClass high byte at OS/2 offset 30
        let class_id = os2.and_then(|d| d.get(30)).copied().unwrap_or(0);
        let sfc_cat: Option<&str> = match class_id {
            1 | 2 | 3 | 4 | 5 | 7 => Some("serif"),
            8 => Some("sans-serif"),
            9 | 12 => Some("decorative"),
            10 => Some("script"),
            _ => None,
        };

        panose_cat.or(name_cat).or(sfc_cat).unwrap_or("other")
    };

    FontMeta {
        classification: Classification {
            category: category.to_string(),
            style: style.to_string(),
            width: width.to_string(),
        },
        weight,
    }
}
