//! Google Fonts API enrichment.
//!
//! Fetches the full Google Fonts catalog once, caches it as JSON
//! in the app data directory, then matches installed fonts by
//! family name to fill in foundry, designer, and google_category.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};

// ── API response types ────────────────────────────────────────────────────────

#[derive(Deserialize, Debug)]
struct GoogleFontsResponse {
    items: Option<Vec<GoogleFontEntry>>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
struct GoogleFontEntry {
    family: String,
    category: Option<String>,
    variants: Option<Vec<String>>,
    subsets: Option<Vec<String>>,
    // The API doesn't return designer/foundry directly in the webfonts
    // endpoint, but some fonts include it in the "menu" or "files" fields.
    // We'll use the family name as a lookup key for the metadata.
}

// ── Cached catalog ────────────────────────────────────────────────────────────

#[derive(Serialize, Deserialize, Debug)]
struct CachedCatalog {
    fetched_at: String,
    entries: Vec<GoogleFontEntry>,
}

const CACHE_FILE: &str = "google_fonts_cache.json";
const CACHE_MAX_AGE_SECS: i64 = 7 * 24 * 60 * 60; // 1 week

fn cache_path(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join(CACHE_FILE)
}

fn now_iso() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

/// Load the cached catalog if it exists and isn't stale.
fn load_cache(app_data_dir: &Path) -> Option<CachedCatalog> {
    let path = cache_path(app_data_dir);
    let data = std::fs::read_to_string(&path).ok()?;
    let catalog: CachedCatalog = serde_json::from_str(&data).ok()?;

    // Check freshness
    if let Ok(fetched) = chrono::DateTime::parse_from_rfc3339(&catalog.fetched_at) {
        let age = chrono::Utc::now().signed_duration_since(fetched);
        if age.num_seconds() < CACHE_MAX_AGE_SECS {
            return Some(catalog);
        }
    }

    // Stale but still usable as fallback
    Some(catalog)
}

/// Fetch the full Google Fonts list from the API.
/// Returns None if no API key or network fails — never blocks the app.
fn fetch_catalog(api_key: &str) -> Option<Vec<GoogleFontEntry>> {
    let url = format!(
        "https://www.googleapis.com/webfonts/v1/webfonts?key={}&sort=alpha",
        api_key
    );

    let response = ureq::get(&url)
        .timeout(std::time::Duration::from_secs(10))
        .call()
        .ok()?;

    let body: GoogleFontsResponse = response.into_json().ok()?;
    body.items
}

/// Save the catalog to disk.
fn save_cache(app_data_dir: &Path, entries: &[GoogleFontEntry]) {
    let catalog = CachedCatalog {
        fetched_at: now_iso(),
        entries: entries.to_vec(),
    };
    if let Ok(json) = serde_json::to_string(&catalog) {
        std::fs::write(cache_path(app_data_dir), json).ok();
    }
}

// ── API key management ────────────────────────────────────────────────────────

const KEY_FILE: &str = "google_fonts_api_key.txt";

/// Read the API key from a file in the app data dir, or from env.
pub fn get_api_key(app_data_dir: &Path) -> Option<String> {
    // Try file first
    let key_path = app_data_dir.join(KEY_FILE);
    if let Ok(key) = std::fs::read_to_string(&key_path) {
        let trimmed = key.trim().to_string();
        if !trimmed.is_empty() {
            return Some(trimmed);
        }
    }
    // Fall back to env var
    std::env::var("GOOGLE_FONTS_API_KEY").ok()
}

/// Save an API key to the app data dir for future use.
pub fn save_api_key(app_data_dir: &Path, key: &str) {
    let key_path = app_data_dir.join(KEY_FILE);
    std::fs::write(key_path, key.trim()).ok();
}

// ── Enrichment logic ──────────────────────────────────────────────────────────

/// Build a case-insensitive lookup map from the catalog.
fn build_lookup(entries: &[GoogleFontEntry]) -> HashMap<String, &GoogleFontEntry> {
    let mut map = HashMap::new();
    for entry in entries {
        map.insert(entry.family.to_lowercase(), entry);
    }
    map
}

/// Known foundry/designer mappings for common Google Fonts.
/// The webfonts API doesn't expose designer directly, so we use a curated list.
fn known_designer(family: &str) -> Option<(&'static str, &'static str)> {
    // (foundry, designer)
    let n = family.to_lowercase();
    match n.as_str() {
        "roboto" | "roboto slab" | "roboto mono" | "roboto condensed" | "roboto flex" => {
            Some(("Google", "Christian Robertson"))
        }
        "open sans" => Some(("Google", "Steve Matteson")),
        "lato" => Some(("tyPoland", "Łukasz Dziedzic")),
        "montserrat" => Some(("Google", "Julieta Ulanovsky")),
        "poppins" => Some(("Indian Type Foundry", "Indian Type Foundry")),
        "inter" => Some(("Google", "Rasmus Andersson")),
        "raleway" => Some(("The League of Moveable Type", "Matt McInerney")),
        "playfair display" => Some(("Google", "Claus Eggers Sørensen")),
        "merriweather" => Some(("Sorkin Type", "Eben Sorkin")),
        "source sans 3" | "source sans pro" => Some(("Adobe", "Paul D. Hunt")),
        "source serif 4" | "source serif pro" => Some(("Adobe", "Frank Grießhammer")),
        "source code pro" => Some(("Adobe", "Paul D. Hunt")),
        "nunito" | "nunito sans" => Some(("Google", "Vernon Adams")),
        "oswald" => Some(("Google", "Vernon Adams")),
        "pt sans" | "pt serif" | "pt mono" => Some(("ParaType", "Alexandra Korolkova")),
        "work sans" => Some(("Google", "Wei Huang")),
        "fira sans" | "fira code" | "fira mono" => Some(("Mozilla", "Carrois Apostrophe")),
        "ibm plex sans" | "ibm plex serif" | "ibm plex mono" => Some(("IBM", "Mike Abbink")),
        "dm sans" | "dm serif display" | "dm serif text" | "dm mono" => {
            Some(("Google", "Colophon Foundry"))
        }
        "space grotesk" | "space mono" => Some(("Google", "Florian Karsten")),
        "manrope" => Some(("Google", "Mikhail Sharanda")),
        "jetbrains mono" => Some(("JetBrains", "Philipp Nurullin")),
        "geist" | "geist mono" => Some(("Vercel", "Vercel")),
        "outfit" => Some(("Google", "Rodrigo Fuenzalida")),
        "plus jakarta sans" => Some(("Tokotype", "Gumpita Rahayu")),
        "commissioner" => Some(("Google", "Kostas Bartsokas")),
        "instrument sans" | "instrument serif" => Some(("Google", "Rodrigo Fuenzalida")),
        "gabarito" => Some(("Google", "Rodrigo Fuenzalida")),
        "bricolage grotesque" => Some(("Google", "Mathieu Triay")),
        "sora" => Some(("Google", "Jonathan Barnbrook")),
        "bebas neue" => Some(("Google", "Ryoichi Tsunekawa")),
        "bitter" => Some(("Google", "Sol Matas")),
        "cabin" => Some(("Impallari Type", "Pablo Impallari")),
        "crimson text" | "crimson pro" => Some(("Google", "Sebastian Kosch")),
        "libre baskerville" | "libre franklin" | "libre caslon text" => {
            Some(("Impallari Type", "Pablo Impallari"))
        }
        "quicksand" => Some(("Google", "Andrew Paglinawan")),
        "barlow" | "barlow condensed" | "barlow semi condensed" => {
            Some(("Google", "Jeremy Tribby"))
        }
        "lexend" => Some(("Google", "Thomas Jockin")),
        "archivo" | "archivo narrow" | "archivo black" => {
            Some(("Omnibus-Type", "Héctor Gatti"))
        }
        "karla" => Some(("Google", "Jonathan Pinhorn")),
        "mulish" => Some(("Google", "Vernon Adams")),
        "noto sans" | "noto serif" | "noto sans mono" => Some(("Google", "Google")),
        "ubuntu" | "ubuntu mono" => Some(("Dalton Maag", "Dalton Maag")),
        "zilla slab" => Some(("Mozilla", "Typotheque")),
        "atkinson hyperlegible" => Some(("Braille Institute", "Applied Design Works")),
        "fraunces" => Some(("Google", "Undercase Type")),
        "cormorant" | "cormorant garamond" => Some(("Google", "Christian Thalmann")),
        _ => None,
    }
}

/// Enrich fonts in the database with Google Fonts metadata.
/// Only updates rows where foundry is NULL (never re-enriches).
pub fn enrich_from_google(conn: &Connection, app_data_dir: &Path, force_refresh: bool) {
    // Try to get API key
    let api_key = match get_api_key(app_data_dir) {
        Some(k) => k,
        None => {
            // No API key — still try to apply known designers
            enrich_known_designers(conn);
            return;
        }
    };

    // Load or fetch catalog
    let entries = if force_refresh {
        match fetch_catalog(&api_key) {
            Some(e) => {
                save_cache(app_data_dir, &e);
                e
            }
            None => {
                // Network failed — use stale cache if available
                match load_cache(app_data_dir) {
                    Some(c) => c.entries,
                    None => {
                        enrich_known_designers(conn);
                        return;
                    }
                }
            }
        }
    } else {
        match load_cache(app_data_dir) {
            Some(c) => c.entries,
            None => {
                // No cache — try fetching
                match fetch_catalog(&api_key) {
                    Some(e) => {
                        save_cache(app_data_dir, &e);
                        e
                    }
                    None => {
                        enrich_known_designers(conn);
                        return;
                    }
                }
            }
        }
    };

    let lookup = build_lookup(&entries);

    // Get all fonts needing enrichment (foundry is NULL)
    let mut stmt = conn
        .prepare("SELECT font_id, font_family FROM fonts WHERE foundry IS NULL")
        .unwrap_or_else(|_| panic!("failed to prepare enrich query"));

    let rows: Vec<(String, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap_or_else(|_| panic!("failed to query for enrichment"))
        .filter_map(|r| r.ok())
        .collect();

    let now = crate::db::now_iso_pub();

    for (font_id, family_name) in &rows {
        let family_lower = family_name.to_lowercase();

        // Try exact match first, then common variations
        let matched = lookup.get(&family_lower)
            .or_else(|| {
                // Try without "Variable" suffix
                let trimmed = family_lower.trim_end_matches(" variable").trim();
                lookup.get(trimmed)
            })
            .or_else(|| {
                // Try adding/removing "Pro"
                if family_lower.ends_with(" pro") {
                    lookup.get(family_lower.trim_end_matches(" pro"))
                } else {
                    lookup.get(&format!("{} pro", family_lower))
                }
            });

        if let Some(entry) = matched {
            let google_cat = entry.category.as_deref().unwrap_or("");

            // Get designer from our curated list (API doesn't expose it)
            let (foundry, designer) = known_designer(&entry.family)
                .unwrap_or(("Google Fonts", ""));

            conn.execute(
                "UPDATE fonts SET google_category = ?1, foundry = ?2, designer = ?3, \
                 classification_source = CASE WHEN classification_source = 'file' THEN 'google' ELSE classification_source END, \
                 updated_at = ?4 WHERE font_id = ?5",
                params![google_cat, foundry, designer, now, font_id],
            )
            .ok();
        } else {
            // No Google match — try known designers table anyway
            if let Some((foundry, designer)) = known_designer(family_name) {
                conn.execute(
                    "UPDATE fonts SET foundry = ?1, designer = ?2, updated_at = ?3 WHERE font_id = ?4",
                    params![foundry, designer, now, font_id],
                )
                .ok();
            }
        }
    }
}

/// Apply known designer mappings without needing the API.
fn enrich_known_designers(conn: &Connection) {
    let mut stmt = match conn.prepare("SELECT font_id, font_family FROM fonts WHERE foundry IS NULL") {
        Ok(s) => s,
        Err(_) => return,
    };

    let rows: Vec<(String, String)> = match stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?))) {
        Ok(r) => r.filter_map(|r| r.ok()).collect(),
        Err(_) => return,
    };

    let now = crate::db::now_iso_pub();

    for (font_id, family_name) in &rows {
        if let Some((foundry, designer)) = known_designer(family_name) {
            conn.execute(
                "UPDATE fonts SET foundry = ?1, designer = ?2, updated_at = ?3 WHERE font_id = ?4",
                params![foundry, designer, now, font_id],
            )
            .ok();
        }
    }
}
