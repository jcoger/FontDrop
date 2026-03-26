use std::path::PathBuf;
use serde::Serialize;
use ttf_parser::{Face, Tag, Style, Width};

#[derive(Serialize)]
pub struct Classification {
    pub category: String, // "sans-serif" | "serif" | "script" | "decorative" | "monospace"
    pub style: String,    // "normal" | "italic"
    pub width: String,    // "condensed" | "normal" | "extended"
}

#[derive(Serialize)]
pub struct FontInfo {
    pub file_name: String,
    pub file_path: String,
    pub font_family: String,
    pub weight: u16,       // numeric weight: 100–900, default 400
    pub source: String,    // "system" | "library" | "user"
    pub classification: Classification,
}

fn parse_family(stem: &str) -> String {
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

struct FontMeta {
    classification: Classification,
    weight: u16,
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

fn parse_font_meta(path: &std::path::Path, family_name: &str) -> FontMeta {
    // ttf-parser only handles TTF/OTF — WOFF/WOFF2 are compressed, use defaults
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    if !matches!(ext.as_deref(), Some("ttf") | Some("otf")) {
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
        // bFamilyKind: 2=LatinText, 3=Script, 4=Decorative, 5=Symbol
        // For LatinText: bSerifStyle byte 1: 2–10=serif, 11–15=sans-serif
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
            // "serif" without "sans" before it
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

        // Priority: Panose > name keywords > sFamilyClass > "other"
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

fn scan_dir(dir: &PathBuf, source: &str, results: &mut Vec<FontInfo>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan_dir(&path, source, results);
            continue;
        }

        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());

        if !matches!(ext.as_deref(), Some("ttf") | Some("otf") | Some("woff") | Some("woff2")) {
            continue;
        }

        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();

        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(&file_name);

        let family = parse_family(stem);
        let meta = parse_font_meta(&path, &family);

        results.push(FontInfo {
            font_family: family,
            file_name,
            file_path: path.to_string_lossy().to_string(),
            weight: meta.weight,
            source: source.to_string(),
            classification: meta.classification,
        });
    }
}

#[tauri::command]
fn get_system_fonts() -> Vec<FontInfo> {
    let mut fonts: Vec<FontInfo> = Vec::new();

    let scan_targets: Vec<(PathBuf, &str)> = vec![
        (PathBuf::from("/System/Library/Fonts"), "system"),
        (PathBuf::from("/Library/Fonts"), "library"),
        (
            dirs::home_dir()
                .map(|h| h.join("Library/Fonts"))
                .unwrap_or_default(),
            "user",
        ),
    ];

    for (dir, source) in &scan_targets {
        scan_dir(dir, source, &mut fonts);
    }

    fonts
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![get_system_fonts])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
