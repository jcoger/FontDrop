//! Google's public family list (no API key).
//!
//! `https://fonts.google.com/metadata/fonts` lists every family with its category
//! and a popularity rank. We keep family, category and rank in `google_families`
//! and mark installed families whose name matches. It is a membership flag on
//! what you have installed, never a catalogue of uninstalled fonts.
//!
//! The raw response is cached next to the DB for a week. Offline with no cache
//! stores nothing and the Google filter shows 0. (`google_fonts.rs` is the older
//! API-key path for foundry and designer; this one needs no key.)

use std::collections::{HashMap, HashSet};
use std::path::Path;

use rusqlite::{params, Connection};
use serde::Deserialize;

const METADATA_URL: &str = "https://fonts.google.com/metadata/fonts";
const METADATA_CACHE_FILE: &str = "google_fonts_metadata.json";
const METADATA_MAX_AGE_SECS: u64 = 7 * 24 * 60 * 60;

/// One family from Google's list.
#[derive(Debug, Clone, PartialEq)]
pub struct GoogleFamily {
    pub family: String,
    /// "Sans Serif" | "Serif" | "Display" | "Handwriting" | "Monospace"
    pub category: Option<String>,
    /// Rank, 1 = most popular.
    pub popularity: Option<u32>,
}

#[derive(Deserialize)]
struct MetadataEntry {
    family: String,
    category: Option<String>,
    popularity: Option<u32>,
}

#[derive(Deserialize)]
struct Metadata {
    #[serde(rename = "familyMetadataList")]
    family_metadata_list: Vec<MetadataEntry>,
}

/// Case and whitespace insensitive key: "Open Sans" and "opensans" are one family.
pub fn normalize_family(name: &str) -> String {
    name.chars().filter(|c| !c.is_whitespace()).flat_map(|c| c.to_lowercase()).collect()
}

/// Parse the response body. Google's JSON endpoints may start with `)]}'`; strip it.
pub fn parse_metadata(body: &str) -> Result<Vec<GoogleFamily>, String> {
    let trimmed = body.trim_start();
    let json = trimmed.strip_prefix(")]}'").unwrap_or(trimmed);
    let parsed: Metadata = serde_json::from_str(json).map_err(|e| e.to_string())?;
    Ok(parsed
        .family_metadata_list
        .into_iter()
        .map(|e| GoogleFamily { family: e.family, category: e.category, popularity: e.popularity })
        .collect())
}

/// Replace the stored list. One transaction, so readers never see half a list.
pub fn store_catalog(conn: &Connection, list: &[GoogleFamily]) -> Result<(), String> {
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    tx.execute("DELETE FROM google_families", []).map_err(|e| e.to_string())?;
    {
        let mut st = tx
            .prepare("INSERT OR REPLACE INTO google_families (norm, family, category, popularity) VALUES (?1, ?2, ?3, ?4)")
            .map_err(|e| e.to_string())?;
        for g in list {
            st.execute(params![normalize_family(&g.family), g.family, g.category, g.popularity])
                .map_err(|e| e.to_string())?;
        }
    }
    tx.commit().map_err(|e| e.to_string())
}

/// The `google_families` key for an installed family, if Google lists it: the name as written,
/// then with trailing weight, width and size words removed ("Inter Variable" is Inter).
pub fn match_key(family: &str, known: &HashSet<String>) -> Option<String> {
    let exact = normalize_family(family);
    if known.contains(&exact) {
        return Some(exact);
    }
    let stripped = normalize_family(&crate::names::strip_instance_words(family));
    known.contains(&stripped).then_some(stripped)
}

/// Fill `fonts.google_category` for every installed family Google lists.
/// Returns how many installed families matched.
pub fn match_installed(conn: &Connection) -> usize {
    let mut cats: HashMap<String, Option<String>> = HashMap::new();
    if let Ok(mut st) = conn.prepare("SELECT norm, category FROM google_families") {
        if let Ok(rows) = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?))) {
            cats.extend(rows.flatten());
        }
    }
    if cats.is_empty() {
        return 0;
    }
    let known: HashSet<String> = cats.keys().cloned().collect();
    let families: Vec<String> = match conn.prepare("SELECT DISTINCT font_family FROM fonts") {
        Ok(mut st) => st.query_map([], |r| r.get(0)).map(|it| it.flatten().collect()).unwrap_or_default(),
        Err(_) => return 0,
    };
    let mut matched = 0;
    let Ok(tx) = conn.unchecked_transaction() else { return 0 };
    for fam in families {
        if let Some(key) = match_key(&fam, &known) {
            matched += 1;
            tx.execute(
                "UPDATE fonts SET google_category = ?1 WHERE font_family = ?2",
                params![cats.get(&key).cloned().flatten(), fam],
            )
            .ok();
        }
    }
    tx.commit().ok();
    matched
}

fn fetch_metadata() -> Option<String> {
    let response = ureq::get(METADATA_URL).timeout(std::time::Duration::from_secs(10)).call().ok()?;
    response.into_string().ok()
}

/// Refresh the stored Google list: use the cache when it is under 7 days old, else
/// try the network, else fall back to the old cache. Runs in the background refresh
/// (10 s network timeout) and never fails.
pub fn sync_catalog(conn: &Connection, data_dir: &Path) {
    sync_catalog_with(conn, data_dir, &fetch_metadata, METADATA_MAX_AGE_SECS);
}

/// `sync_catalog` with the network and the cache age injected, for tests.
/// Returns how many families Google's list holds after the sync (0 = nothing known).
pub fn sync_catalog_with(conn: &Connection, data_dir: &Path, fetch: &dyn Fn() -> Option<String>, max_age_secs: u64) -> usize {
    let path = data_dir.join(METADATA_CACHE_FILE);
    let cached = std::fs::read_to_string(&path).ok();
    let age = std::fs::metadata(&path).and_then(|m| m.modified()).ok().and_then(|t| t.elapsed().ok());
    let fresh = cached.is_some() && age.map_or(false, |a| a.as_secs() < max_age_secs);

    let body = if fresh {
        cached
    } else {
        match fetch().filter(|b| parse_metadata(b).is_ok()) {
            Some(b) => {
                std::fs::write(&path, &b).ok();
                Some(b)
            }
            None => cached, // offline: a stale list beats none
        }
    };
    let Some(list) = body.and_then(|b| parse_metadata(&b).ok()) else {
        return conn.query_row("SELECT COUNT(*) FROM google_families", [], |r| r.get::<_, i64>(0)).unwrap_or(0) as usize;
    };
    if store_catalog(conn, &list).is_ok() {
        match_installed(conn);
    }
    list.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{run_migrations, CREATE_TABLE};
    use std::cell::Cell;

    /// A trimmed copy of Google's response (6 families), with the `)]}'` prefix some endpoints add.
    const FIXTURE: &str = include_str!("fixtures/google_metadata.json");

    fn mem() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        conn
    }

    fn add_font(conn: &Connection, id: &str, family: &str) {
        conn.execute(
            "INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, created_at, updated_at)
             VALUES (?1, ?1, '/x/' || ?1 || '.otf', ?1 || '.otf', 'user', ?2, 'x', 'x')",
            params![id, family],
        )
        .unwrap();
    }

    fn tmp(tag: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("fontdrop-google-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn parses_the_fixture_with_its_prefix() {
        assert!(FIXTURE.trim_start().starts_with(")]}'"));
        let list = parse_metadata(FIXTURE).unwrap();
        assert_eq!(list.len(), 6);
        let inter = list.iter().find(|g| g.family == "Inter").unwrap();
        assert_eq!(inter.category.as_deref(), Some("Sans Serif"));
        assert_eq!(inter.popularity, Some(2));
        // and without the prefix
        assert_eq!(parse_metadata(FIXTURE.trim_start().strip_prefix(")]}'").unwrap()).unwrap().len(), 6);
        assert!(parse_metadata("<html>not json</html>").is_err());
    }

    #[test]
    fn matches_installed_families_by_normalized_name() {
        let conn = mem();
        store_catalog(&conn, &parse_metadata(FIXTURE).unwrap()).unwrap();
        add_font(&conn, "a", "Inter Variable"); // instance word stripped
        add_font(&conn, "b", "OPEN  sans"); // case and spacing folded
        add_font(&conn, "c", "Fraunces 9pt"); // optical-size word stripped
        add_font(&conn, "d", "Roboto Condensed"); // its own entry, not "Roboto"
        add_font(&conn, "e", "Neue Haas Grotesk"); // not on Google
        let n = match_installed(&conn);
        assert_eq!(n, 4, "Inter, Open Sans, Fraunces, Roboto Condensed");
        let cat = |fam: &str| -> Option<String> {
            conn.query_row("SELECT google_category FROM fonts WHERE font_family = ?1", [fam], |r| r.get(0)).unwrap()
        };
        assert_eq!(cat("Inter Variable").as_deref(), Some("Sans Serif"));
        assert_eq!(cat("OPEN  sans").as_deref(), Some("Sans Serif"));
        assert_eq!(cat("Roboto Condensed").as_deref(), Some("Sans Serif"));
        assert_eq!(cat("Fraunces 9pt").as_deref(), Some("Serif"));
        assert_eq!(cat("Neue Haas Grotesk"), None);
    }

    #[test]
    fn caches_for_a_week_and_falls_back_offline() {
        let dir = tmp("cache");
        let conn = mem();
        let calls = Cell::new(0);
        let online = || {
            calls.set(calls.get() + 1);
            Some(FIXTURE.to_string())
        };
        // first run fetches and writes the cache
        assert_eq!(sync_catalog_with(&conn, &dir, &online, 3600), 6);
        assert_eq!(calls.get(), 1);
        assert!(dir.join(METADATA_CACHE_FILE).exists());
        // second run within the window uses the cache
        assert_eq!(sync_catalog_with(&conn, &dir, &online, 3600), 6);
        assert_eq!(calls.get(), 1);
        // zero max age counts as stale: tries the network again
        assert_eq!(sync_catalog_with(&conn, &dir, &online, 0), 6);
        assert_eq!(calls.get(), 2);
        // offline with a stale cache: keeps using it
        let offline = || None;
        assert_eq!(sync_catalog_with(&conn, &dir, &offline, 0), 6);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn offline_with_no_cache_stores_nothing_and_does_not_break() {
        let dir = tmp("offline");
        let conn = mem();
        add_font(&conn, "a", "Inter");
        let offline = || None;
        assert_eq!(sync_catalog_with(&conn, &dir, &offline, 3600), 0);
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM google_families", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 0);
        // garbage from the network is ignored too
        let junk = || Some("<html>captive portal</html>".to_string());
        assert_eq!(sync_catalog_with(&conn, &dir, &junk, 3600), 0);
        assert!(!dir.join(METADATA_CACHE_FILE).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
