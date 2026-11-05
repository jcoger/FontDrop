use std::path::{Path, PathBuf};

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::names::{is_private_face, is_slanted, parse_family, parse_font_meta, read_family_name, read_name_meta, upright_distance, Classification};
use crate::classifier;
use crate::metrics;

// ── Row shape returned to the frontend ────────────────────────────────────────

#[derive(Serialize, Clone)]
pub struct FontRow {
    pub font_id: String,
    pub name: String,
    pub file_path: String,
    pub file_name: String,
    pub source: String,
    pub foundry: Option<String>,
    pub designer: Option<String>,
    pub skeleton: String,
    pub flesh_contrast: String,
    pub flesh_serif: i32,
    pub x_height_ratio: Option<f64>,
    pub cap_height_ratio: Option<f64>,
    pub stroke_contrast_ratio: Option<f64>,
    pub classification_source: String,
    pub user_override: i32,
    pub google_category: Option<String>,
    pub classification_reason: Option<String>,
    pub optical_role: Option<String>,
    pub superfamily_group: Option<String>,
    pub superfamily_role: Option<String>,
    pub ascender_descender_ratio: Option<f64>,
    pub weight_range_min: Option<i32>,
    pub weight_range_max: Option<i32>,
    pub spacing_personality: Option<String>,
    pub width_class: Option<String>,
    /// 1 = trial / test / demo build (name or licence text), 0 = not, None = not read yet
    pub is_trial: Option<i32>,
    /// Foundry or licence page from the file, for "get the licence" links
    pub foundry_url: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    // carry forward the existing fields so the UI doesn't break
    pub font_family: String,
    pub weight: u16,
    pub classification: Classification,
}

#[derive(Deserialize)]
pub struct FontUpdate {
    pub foundry: Option<String>,
    pub designer: Option<String>,
    pub skeleton: Option<String>,
    pub flesh_contrast: Option<String>,
    pub flesh_serif: Option<i32>,
    pub x_height_ratio: Option<f64>,
    pub cap_height_ratio: Option<f64>,
    pub stroke_contrast_ratio: Option<f64>,
    pub classification_source: Option<String>,
    pub user_override: Option<i32>,
    pub google_category: Option<String>,
    pub category: Option<String>,
    pub classification_reason: Option<String>,
}

// ── Schema ────────────────────────────────────────────────────────────────────

pub(crate) const CREATE_TABLE: &str = "
CREATE TABLE IF NOT EXISTS fonts (
    font_id              TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    file_path            TEXT NOT NULL,
    file_name            TEXT NOT NULL,
    source               TEXT NOT NULL,
    font_family          TEXT NOT NULL,
    weight               INTEGER NOT NULL DEFAULT 400,
    category             TEXT NOT NULL DEFAULT 'sans-serif',
    style                TEXT NOT NULL DEFAULT 'normal',
    width                TEXT NOT NULL DEFAULT 'normal',
    foundry              TEXT,
    designer             TEXT,
    skeleton             TEXT NOT NULL DEFAULT 'unknown',
    flesh_contrast       TEXT NOT NULL DEFAULT 'linear',
    flesh_serif          INTEGER NOT NULL DEFAULT 0,
    x_height_ratio       REAL,
    cap_height_ratio     REAL,
    stroke_contrast_ratio REAL,
    classification_source TEXT NOT NULL DEFAULT 'file',
    user_override        INTEGER NOT NULL DEFAULT 0,
    google_category      TEXT,
    classification_reason TEXT,
    created_at           TEXT NOT NULL,
    updated_at           TEXT NOT NULL
);
";

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Hash the first 64 KB of a font file with SHA-256 to get a stable font_id.
fn hash_font_file(path: &Path) -> Option<String> {
    use std::io::Read;
    // Read only the 64 KB that is hashed, not the whole file (some are 190 MB).
    // The bytes hashed are the same as before, so every font_id stays the same.
    let mut chunk = Vec::with_capacity(65_536);
    std::fs::File::open(path).ok()?.take(65_536).read_to_end(&mut chunk).ok()?;
    let mut hasher = Sha256::new();
    hasher.update(&chunk);
    Some(format!("{:x}", hasher.finalize()))
}

pub(crate) fn now_iso() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}


// ── Schema migrations ─────────────────────────────────────────────────────────

/// Ordered schema migrations applied on top of CREATE_TABLE (the v0 baseline).
/// Append-only: never reorder or edit an existing entry once shipped, or
/// installed databases will skip or double-apply it. To change the schema,
/// add a new entry at the end.
const MIGRATIONS: &[&str] = &[
    "ALTER TABLE fonts ADD COLUMN classification_reason TEXT;",
    "ALTER TABLE fonts ADD COLUMN optical_role TEXT;",
    "ALTER TABLE fonts ADD COLUMN superfamily_group TEXT;",
    "ALTER TABLE fonts ADD COLUMN superfamily_role TEXT;",
    "ALTER TABLE fonts ADD COLUMN ascender_descender_ratio REAL;",
    "ALTER TABLE fonts ADD COLUMN weight_range_min INTEGER;",
    "ALTER TABLE fonts ADD COLUMN weight_range_max INTEGER;",
    "ALTER TABLE fonts ADD COLUMN spacing_personality TEXT;",
    "ALTER TABLE fonts ADD COLUMN width_class TEXT;",
    "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
    "ALTER TABLE fonts ADD COLUMN vendor_id TEXT;",
    // User data (userdata.rs): brands, a shortlist per job, chosen faces.
    "CREATE TABLE IF NOT EXISTS brands (id INTEGER PRIMARY KEY, name TEXT NOT NULL, logo_svg TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')));",
    "CREATE TABLE IF NOT EXISTS shortlist (brand_id INTEGER NOT NULL REFERENCES brands(id) ON DELETE CASCADE, job TEXT NOT NULL, font_family TEXT NOT NULL, added_at TEXT NOT NULL DEFAULT (datetime('now')), PRIMARY KEY (brand_id, job, font_family));",
    "CREATE TABLE IF NOT EXISTS choices (brand_id INTEGER NOT NULL REFERENCES brands(id) ON DELETE CASCADE, job TEXT NOT NULL, font_family TEXT NOT NULL, chosen_at TEXT NOT NULL DEFAULT (datetime('now')), PRIMARY KEY (brand_id, job));",
    "ALTER TABLE fonts ADD COLUMN is_trial INTEGER;",
    "ALTER TABLE fonts ADD COLUMN foundry_url TEXT;",
    // Finding fonts (finder.rs). Variable-font flag, read from the file's fvar table.
    "ALTER TABLE fonts ADD COLUMN is_variable INTEGER;",
    // Trial detection now also reads the full name (ID 4); re-read every file once.
    "UPDATE fonts SET is_trial = NULL;",
    // Google's public family list: normalized name -> category and popularity rank (1 = most popular).
    "CREATE TABLE IF NOT EXISTS google_families (norm TEXT PRIMARY KEY, family TEXT NOT NULL, category TEXT, popularity INTEGER);",
    // Per-user hides. hidden = 1: the user hid it. hidden = 0: the user showed a built-in junk family again.
    "CREATE TABLE IF NOT EXISTS hidden (family TEXT PRIMARY KEY COLLATE NOCASE, hidden INTEGER NOT NULL DEFAULT 1);",
    // Saved families (a star), global; separate from per-brand shortlists.
    "CREATE TABLE IF NOT EXISTS favorites (family TEXT PRIMARY KEY COLLATE NOCASE, added_at TEXT NOT NULL DEFAULT (datetime('now')));",
    // Does the file's cmap cover basic Latin (A-Z, a-z, 0-9)? NULL = not read yet, so every existing
    // row is read once on the next scan. To change the rule later, add a migration that sets it to NULL.
    "ALTER TABLE fonts ADD COLUMN covers_latin INTEGER;",
    // The font's own style name (name ID 17, else 2). NULL = not read yet, so every existing row is
    // read once on the next scan. '' = read, the file has none.
    "ALTER TABLE fonts ADD COLUMN style_name TEXT;",
    // Variable fonts: top of the wght axis (0 = no such axis) and whether an ital or slnt axis exists,
    // so one file can count as bold and italic for the Reading rule. NULL = not read yet; only
    // variable rows are re-read for it.
    "ALTER TABLE fonts ADD COLUMN wght_axis_max INTEGER;",
    "ALTER TABLE fonts ADD COLUMN ital_axis INTEGER;",
    // Mean advance of "n", "o" and "H" over the em (classifier.rs), a measured width. NULL = not measured; the
    // classifier version bump measures every file once.
    "ALTER TABLE fonts ADD COLUMN advance_ratio REAL;",
    // Round R5. brands.id becomes AUTOINCREMENT so a deleted brand's id is never handed to the next brand
    // (a reused id would inherit the old brand's rows). SQLite cannot add AUTOINCREMENT in place, so the table
    // is rebuilt. foreign_keys is switched off for the rebuild: with it on, DROP TABLE would delete the brand
    // rows one by one and cascade into the shortlist and choices. The pragma is a no-op inside a transaction,
    // so it sits outside BEGIN/COMMIT.
    "PRAGMA foreign_keys=OFF;
     BEGIN;
     CREATE TABLE brands_new (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, logo_svg TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')));
     INSERT INTO brands_new (id, name, logo_svg, created_at) SELECT id, name, logo_svg, created_at FROM brands;
     DROP TABLE brands;
     ALTER TABLE brands_new RENAME TO brands;
     COMMIT;
     PRAGMA foreign_keys=ON;",
    // Per-brand type settings (brand_settings.rs). Each table cascades from brands. They replace the side files
    // <db>.scale.json, <db>.colors.json and <db>.playground.json, which are imported once and then left alone.
    // measure (characters per line) and line_height are NULL until the designer sets them: NULL means "follow the type rules".
    "CREATE TABLE IF NOT EXISTS brand_scale (brand_id INTEGER PRIMARY KEY REFERENCES brands(id) ON DELETE CASCADE, body REAL NOT NULL, ratio REAL NOT NULL, locked INTEGER NOT NULL DEFAULT 0, measure INTEGER, line_height REAL);",
    "CREATE TABLE IF NOT EXISTS brand_colors (brand_id INTEGER PRIMARY KEY REFERENCES brands(id) ON DELETE CASCADE, background TEXT NOT NULL, text TEXT NOT NULL, accent TEXT NOT NULL);",
    "CREATE TABLE IF NOT EXISTS face_settings (brand_id INTEGER NOT NULL REFERENCES brands(id) ON DELETE CASCADE, job TEXT NOT NULL, family TEXT NOT NULL, style_path TEXT, tracking REAL NOT NULL DEFAULT 0, line_height REAL NOT NULL, trim REAL NOT NULL DEFAULT 1, axes_json TEXT NOT NULL DEFAULT '{}', features_json TEXT NOT NULL DEFAULT '{}', PRIMARY KEY (brand_id, job, family));",
];

/// The migrations that shipped before the `brands` rebuild (test seam: an install from before round R5).
#[cfg(test)]
pub(crate) fn migrations_before_brands_rebuild() -> &'static [&'static str] {
    &MIGRATIONS[..MIGRATIONS.len() - 4]
}

/// The marker in the error text when the library was written by a newer build ("newer-library:<its version>:<ours>").
/// The Mac app looks for it to show a plain message instead of the raw database error.
pub const NEWER_LIBRARY: &str = "newer-library";

/// Apply any migrations with index >= the DB's current user_version, then
/// stamp user_version to MIGRATIONS.len(). Tolerates "duplicate column"
/// (existing DBs already have these columns) but surfaces any other error.
#[cfg(test)]
pub(crate) fn run_migrations(conn: &Connection) {
    try_run_migrations(conn).expect("schema migration failed");
}

/// Same as `run_migrations`, but reports failure instead of panicking.
pub fn try_run_migrations(conn: &Connection) -> Result<(), rusqlite::Error> {
    // A failed read is an error, not "version 0": treating it as 0 would re-run
    // every migration and then stamp the version down.
    let current: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0))?;

    // A library written by a newer build is not ours to touch: this build does not know its schema, and an older
    // build writing to it could damage what the newer one stored. Refuse it with a message the app can name.
    if current > MIGRATIONS.len() as i64 {
        return Err(rusqlite::Error::InvalidParameterName(format!("{NEWER_LIBRARY}:{current}:{}", MIGRATIONS.len())));
    }

    for (i, stmt) in MIGRATIONS.iter().enumerate() {
        if (i as i64) < current {
            continue; // already applied on this DB
        }
        if let Err(e) = conn.execute_batch(stmt) {
            let msg = e.to_string().to_lowercase();
            // Existing installs already have these columns: a duplicate-column
            // error here is expected and safe to ignore. Anything else is a
            // real failure we must not hide.
            if !msg.contains("duplicate column") {
                return Err(e);
            }
        }
    }

    // Stamp the new version, never lower. A DB written by a newer build carries
    // a higher number; an older build must leave it alone, or the newer build
    // re-runs migrations it already applied. PRAGMA doesn't accept bound
    // params, so format it (the value is MIGRATIONS.len(), not user input).
    let target = MIGRATIONS.len();
    if current < target as i64 {
        conn.execute_batch(&format!("PRAGMA user_version = {};", target))?;
    }
    Ok(())
}

// ── DB init ───────────────────────────────────────────────────────────────────

/// File name of the library database inside the app data dir.
pub const DB_FILE: &str = "fontdrop.db";

/// Open (creating if needed) the library DB at `db_path`, in WAL mode with a
/// busy timeout, and bring its schema up to date. Every app that opens the DB
/// through here gets the current schema, whatever wrote the file before.
pub fn try_open_db_at(db_path: &Path) -> Result<Connection, rusqlite::Error> {
    if let Some(dir) = db_path.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    let conn = Connection::open(db_path)?;
    // busy_timeout: the background scan writes while the UI reads and edits.
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;")?;
    conn.execute_batch(CREATE_TABLE)?;
    try_run_migrations(&conn)?;
    Ok(conn)
}

/// Panicking convenience for the app shell, which has no way to run without a DB.
pub fn open_db(app_data_dir: &Path) -> Connection {
    try_open_db_at(&app_data_dir.join(DB_FILE)).expect("failed to open font database")
}

// ── Scan + upsert ─────────────────────────────────────────────────────────────

struct ScannedFont {
    font_id: String,
    file_name: String,
    file_path: String,
    font_family: String,
    weight: u16,
    source: String,
    category: String,
    style: String,
    width: String,
}

/// `private` collects the paths of Apple's private system faces the scan skipped,
/// so rows an older scan stored under their file-name family can be dropped.
fn scan_dir_for_db(dir: &PathBuf, source: &str, results: &mut Vec<ScannedFont>, private: &mut Vec<String>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan_dir_for_db(&path, source, results, private);
            continue;
        }

        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());

        if !matches!(ext.as_deref(), Some("ttf") | Some("otf") | Some("ttc") | Some("woff") | Some("woff2")) {
            continue;
        }

        let font_id = match hash_font_file(&path) {
            Some(h) => h,
            None => continue,
        };

        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();

        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(&file_name);

        let family = read_family_name(&path).unwrap_or_else(|| parse_family(stem));
        // Apple's private system faces (".SF Arabic", ".LastResort") are hidden
        // from Font Book and every font menu; hide them here too.
        if is_private_face(&family) {
            private.push(path.to_string_lossy().to_string());
            continue;
        }
        let meta = parse_font_meta(&path, &family);

        results.push(ScannedFont {
            font_id,
            file_name,
            file_path: path.to_string_lossy().to_string(),
            font_family: family,
            weight: meta.weight,
            source: source.to_string(),
            category: meta.classification.category.clone(),
            style: meta.classification.style.clone(),
            width: meta.classification.width.clone(),
        });
    }
}

/// Run the Font Matrix classifier on all unclassified fonts.
/// Fill vendor, foundry and designer from each file's own name tables, once per
/// font (vendor_id NULL = not read yet; '' = read, no real vendor code). Foundry
/// and designer only fill gaps; existing values (Google enrichment, edits) stay.
pub fn enrich_from_name_tables(conn: &Connection) {
    let rows: Vec<(String, String)> = match conn.prepare("SELECT font_id, file_path FROM fonts WHERE vendor_id IS NULL OR is_trial IS NULL OR foundry_url IS NULL OR is_variable IS NULL OR covers_latin IS NULL OR style_name IS NULL OR (is_variable = 1 AND wght_axis_max IS NULL)") {
        Ok(mut st) => st
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => return,
    };
    crate::progress::begin(1, rows.len() as u32);
    let tx = conn.unchecked_transaction().ok(); // one commit for the loop
    for (font_id, path) in rows {
        crate::progress::tick();
        let meta = read_name_meta(Path::new(&path));
        // A file we cannot open counts as covering Latin: never hide what we could not check.
        let (vendor, manufacturer, designer, trial, url, variable, latin, style, wght_max, ital_axis) = match meta {
            Some(m) => (m.vendor.unwrap_or_default(), m.manufacturer, m.designer, m.trial, m.foundry_url, m.variable, m.covers_latin, m.style_name.unwrap_or_default(), m.wght_axis_max, m.ital_axis),
            None => (String::new(), None, None, false, None, false, true, String::new(), 0, false),
        };
        conn.execute(
            "UPDATE fonts SET vendor_id = ?1, \
             foundry = COALESCE(NULLIF(foundry, ''), ?2), \
             designer = COALESCE(NULLIF(designer, ''), ?3), is_trial = ?4, foundry_url = ?5, is_variable = ?7, covers_latin = ?8, style_name = ?9, \
             wght_axis_max = ?10, ital_axis = ?11 WHERE font_id = ?6",
            params![vendor, manufacturer, designer, trial as i32, url.unwrap_or_default(), font_id, variable as i32, latin as i32, style, wght_max, ital_axis as i32], // '' = read, none
        )
        .ok();
    }
    // Where the name table named no manufacturer, the vendor code names the foundry. Runs on every call, so it also
    // reaches rows read by an older build.
    let unnamed: Vec<(String, String)> = match conn.prepare("SELECT font_id, vendor_id FROM fonts WHERE (foundry IS NULL OR foundry = '') AND vendor_id IS NOT NULL AND vendor_id != ''") {
        Ok(mut st) => st
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => Vec::new(),
    };
    for (font_id, vendor) in unnamed {
        if let Some(foundry) = crate::names::foundry_for_vendor(&vendor) {
            conn.execute("UPDATE fonts SET foundry = ?1 WHERE font_id = ?2", params![foundry, font_id]).ok();
        }
    }
    if let Some(tx) = tx {
        tx.commit().ok();
    }
}

/// Drop rows whose font file is gone (uninstalled since the last scan) and
/// Apple's private system faces. The scan only ever added and updated rows, so
/// removed fonts stayed in the library forever.
///
/// A row the user classified by hand (`user_override = 1`) is kept even when its
/// file is missing: a font manager that turns a font off and on again, or an
/// unmounted volume, must not erase the correction.
fn prune_missing(conn: &Connection, private_paths: &[String]) {
    let private: std::collections::HashSet<&str> = private_paths.iter().map(|p| p.as_str()).collect();
    let rows: Vec<(String, String, String, i64)> = match conn.prepare("SELECT font_id, file_path, font_family, user_override FROM fonts") {
        Ok(mut st) => st
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => return,
    };
    for (id, path, family, user_override) in rows {
        let hidden = is_private_face(&family);
        // A private face stored under its file name by an older scan ("SFCompact"
        // for ".SF Compact"): the file is there, but the scan now skips it.
        let now_private = private.contains(path.as_str());
        let missing = !Path::new(&path).exists();
        if hidden || ((missing || now_private) && user_override == 0) {
            conn.execute("DELETE FROM fonts WHERE font_id = ?1", params![id]).ok();
        }
    }
}

/// A font file replaced in place gets a new font_id (the id hashes the file's
/// first 64 KB), so the scan inserts a new row and leaves the old one with the
/// same path. The path is the identity of an installed font: for every scanned
/// path, drop the other rows that share it. A hand classification on the old
/// row moves to the new one first.
fn drop_stale_twins(conn: &Connection, scanned: &[ScannedFont]) {
    let live: std::collections::HashSet<&str> = scanned.iter().map(|f| f.font_id.as_str()).collect();
    // path -> the id the scan just wrote for it
    let current: std::collections::HashMap<&str, &str> =
        scanned.iter().map(|f| (f.file_path.as_str(), f.font_id.as_str())).collect();
    let rows: Vec<(String, String, i64)> =
        match conn.prepare("SELECT font_id, file_path, user_override FROM fonts ORDER BY updated_at") {
            Ok(mut st) => st
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                .map(|it| it.filter_map(|r| r.ok()).collect())
                .unwrap_or_default(),
            Err(_) => return,
        };
    for (id, path, user_override) in &rows {
        if live.contains(id.as_str()) {
            continue;
        }
        let Some(new_id) = current.get(path.as_str()) else { continue };
        if *user_override == 1 {
            let new_overridden: i64 = conn
                .query_row("SELECT user_override FROM fonts WHERE font_id = ?1", params![new_id], |r| r.get(0))
                .unwrap_or(0);
            if new_overridden == 0 {
                conn.execute(
                    "UPDATE fonts SET \
                       foundry = old.foundry, designer = old.designer, skeleton = old.skeleton, \
                       flesh_contrast = old.flesh_contrast, flesh_serif = old.flesh_serif, \
                       x_height_ratio = old.x_height_ratio, cap_height_ratio = old.cap_height_ratio, \
                       stroke_contrast_ratio = old.stroke_contrast_ratio, \
                       classification_source = old.classification_source, user_override = 1, \
                       google_category = old.google_category, category = old.category, \
                       classification_reason = old.classification_reason \
                     FROM (SELECT * FROM fonts WHERE font_id = ?2) AS old \
                     WHERE fonts.font_id = ?1",
                    params![new_id, id],
                )
                .ok();
            }
        }
        conn.execute("DELETE FROM fonts WHERE font_id = ?1", params![id]).ok();
    }
}

/// Bump when the classifier's rules change: every non-override font is then
/// reclassified once on the next launch instead of only the 'unknown' ones.
pub const CLASSIFIER_VERSION: i64 = 10;     // 10: serif needs a foot on a body stem too (a sans with a serifed I/l/i is sans)

fn meta_get(conn: &Connection, key: &str) -> Option<String> {
    conn.query_row("SELECT value FROM meta WHERE key = ?1", params![key], |r| r.get(0)).ok()
}

fn meta_set(conn: &Connection, key: &str, value: &str) {
    conn.execute(
        "INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )
    .ok();
}

pub fn classify_all(conn: &Connection) {
    let stamped: i64 = meta_get(conn, "classifier_version").and_then(|v| v.parse().ok()).unwrap_or(0);
    let rerun_all = stamped < CLASSIFIER_VERSION;
    let query = if rerun_all {
        "SELECT font_id, file_path, font_family, category FROM fonts WHERE user_override = 0"
    } else {
        "SELECT font_id, file_path, font_family, category FROM fonts WHERE skeleton = 'unknown' AND user_override = 0"
    };
    let mut stmt = conn
        .prepare(query)
        .expect("failed to prepare classify query");

    let rows: Vec<(String, String, String, String)> = stmt
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("failed to query fonts for classification")
        .filter_map(|r| r.ok())
        .collect();

    let now = now_iso();
    let tx = conn.unchecked_transaction().ok(); // one commit for the loop

    crate::progress::begin(2, rows.len() as u32);
    for (font_id, file_path, family_name, category) in &rows {
        crate::progress::tick();
        let result = classifier::classify_font(Path::new(file_path), family_name);

        // Serif from the outlines when measurable; the category field says
        // "other" for ~64% of fonts, so it's only the fallback.
        let flesh_serif: i32 = match result.serif {
            Some(serif) => serif as i32,
            None => (category == "serif") as i32,
        };

        conn.execute(
            "UPDATE fonts SET skeleton = ?1, flesh_contrast = ?2, flesh_serif = ?3, \
             stroke_contrast_ratio = ?4, classification_reason = ?5, updated_at = ?6, advance_ratio = ?8 \
             WHERE font_id = ?7",
            params![
                result.skeleton,
                result.flesh_contrast,
                flesh_serif,
                result.stroke_contrast_ratio,
                result.reason,
                now,
                font_id,
                result.advance_ratio,
            ],
        )
        .ok();
    }

    unify_family_skeletons(conn);
    if rerun_all {
        meta_set(conn, "classifier_version", &CLASSIFIER_VERSION.to_string());
    }
    if let Some(tx) = tx {
        tx.commit().ok();
    }
}

/// One skeleton per family. Files of one family were classified one by one and
/// disagreed (29% of multi-file families). The family's upright face nearest
/// weight 400 decides; every non-override file in the family takes its answer.
fn unify_family_skeletons(conn: &Connection) {
    let rows: Vec<(String, String, String, i64, String, String, String)> = match conn.prepare(
        "SELECT font_family, file_name, style, weight, skeleton, flesh_contrast, COALESCE(classification_reason, '') FROM fonts",
    ) {
        Ok(mut stmt) => stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => return,
    };

    // family -> (distance from an upright 400, skeleton, flesh_contrast, reason)
    let mut best: std::collections::HashMap<String, (i64, String, String, String)> = std::collections::HashMap::new();
    for (family, file_name, style, weight, skeleton, flesh, reason) in rows {
        if skeleton == "unknown" { continue; }
        let dist = upright_distance(weight, is_slanted(&file_name, &style));
        let entry = best.entry(family).or_insert((i64::MAX, String::new(), String::new(), String::new()));
        if dist < entry.0 {
            *entry = (dist, skeleton, flesh, reason);
        }
    }

    for (family, (_, skeleton, flesh, reason)) in best {
        conn.execute(
            "UPDATE fonts SET skeleton = ?1, flesh_contrast = ?2, classification_reason = ?3 \
             WHERE font_family = ?4 AND user_override = 0",
            params![skeleton, flesh, format!("family Regular: {}", reason.trim_start_matches("family Regular: ")), family],
        )
        .ok();
    }
    unify_family_serif(conn);
}

/// Serif or sans is a family trait too. Italics end in curves, not foot
/// serifs, so an italic file of a serif family measured as sans. The upright
/// face nearest weight 400 decides for the whole family.
fn unify_family_serif(conn: &Connection) {
    let rows: Vec<(String, String, String, i64, i32)> = match conn.prepare("SELECT font_family, file_name, style, weight, flesh_serif FROM fonts") {
        Ok(mut stmt) => stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => return,
    };
    // A family whose files all carry style "italic" (Test Heldane) ties on distance. The tie goes to a file whose
    // name is not slanted, never to whichever row came first: row order moves between scans.
    let mut best: std::collections::HashMap<String, (i64, i32)> = std::collections::HashMap::new();
    for (family, file_name, style, weight, serif) in rows {
        let name_slanted = is_slanted(&file_name, "");
        let dist = upright_distance(weight, is_slanted(&file_name, &style)) * 2 + name_slanted as i64;
        let entry = best.entry(family).or_insert((i64::MAX, 0));
        if dist < entry.0 {
            *entry = (dist, serif);
        }
    }
    for (family, (_, serif)) in best {
        conn.execute(
            "UPDATE fonts SET flesh_serif = ?1 WHERE font_family = ?2 AND user_override = 0",
            params![serif, family],
        )
        .ok();
    }
}

/// Extract extended metrics (optical role, superfamily, spacing, proportions)
/// for fonts that don't have them yet.
pub fn enrich_metrics(conn: &Connection) {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, file_path, font_family, stroke_contrast_ratio, x_height_ratio \
             FROM fonts WHERE optical_role IS NULL",
        )
        .expect("failed to prepare metrics query");

    let rows: Vec<(String, String, String, Option<f64>, Option<f64>)> = stmt
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?))
        })
        .expect("failed to query fonts for metrics")
        .filter_map(|r| r.ok())
        .collect();

    let now = now_iso();
    let tx = conn.unchecked_transaction().ok(); // one commit for the loop

    crate::progress::begin(3, rows.len() as u32);
    for (font_id, file_path, family_name, stroke_contrast, x_height) in &rows {
        crate::progress::tick();
        let m = metrics::extract_extended_metrics(
            Path::new(file_path),
            family_name,
            *stroke_contrast,
            *x_height,
        );

        conn.execute(
            "UPDATE fonts SET optical_role = ?1, superfamily_group = ?2, superfamily_role = ?3, \
             cap_height_ratio = COALESCE(cap_height_ratio, ?4), \
             x_height_ratio = COALESCE(x_height_ratio, ?5), \
             ascender_descender_ratio = ?6, \
             weight_range_min = ?7, weight_range_max = ?8, \
             spacing_personality = ?9, width_class = ?10, updated_at = ?11 \
             WHERE font_id = ?12",
            params![
                m.optical_role,
                m.superfamily_group,
                m.superfamily_role,
                m.cap_height_ratio,
                m.x_height_ratio,
                m.ascender_descender_ratio,
                m.weight_range_min,
                m.weight_range_max,
                m.spacing_personality,
                m.width_class,
                now,
                font_id,
            ],
        )
        .ok();
    }

    // Consolidate weight ranges per superfamily group
    // (a superfamily's weight range is the union of all its members' ranges)
    conn.execute_batch(
        "UPDATE fonts SET weight_range_min = (
            SELECT MIN(f2.weight_range_min) FROM fonts f2
            WHERE f2.font_family = fonts.font_family AND f2.weight_range_min IS NOT NULL
         ), weight_range_max = (
            SELECT MAX(f2.weight_range_max) FROM fonts f2
            WHERE f2.font_family = fonts.font_family AND f2.weight_range_max IS NOT NULL
         ) WHERE weight_range_min IS NOT NULL;"
    ).ok();
    if let Some(tx) = tx {
        tx.commit().ok();
    }
}

pub fn populate_db(conn: &Connection) {
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
    populate_from(conn, &scan_targets);
}

/// Scan the given folders into the fonts table. The app uses the three macOS
/// font folders; the benchmark builds a separate DB from a folder of
/// downloaded Google Fonts.
pub fn populate_from(conn: &Connection, scan_targets: &[(PathBuf, &str)]) {
    let mut scanned: Vec<ScannedFont> = Vec::new();
    let mut private: Vec<String> = Vec::new();
    for (dir, source) in scan_targets {
        scan_dir_for_db(dir, source, &mut scanned, &mut private);
    }
    {
        let families: std::collections::HashSet<&str> = scanned.iter().map(|f| f.font_family.as_str()).collect();
        crate::progress::found(scanned.len() as u32, families.len() as u32);
    }

    let now = now_iso();

    // What the table holds now, read once: the loop below then touches only rows
    // that are new or changed (about 6,000 UPDATEs on every launch otherwise).
    type Stored = (i32, String, String, String, String, u16, String, String, String);
    let mut stored: std::collections::HashMap<String, Stored> = std::collections::HashMap::new();
    if let Ok(mut st) = conn.prepare(
        "SELECT font_id, user_override, file_path, file_name, source, font_family, weight, category, style, width FROM fonts",
    ) {
        if let Ok(it) = st.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, (r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?)))
        }) {
            stored.extend(it.flatten());
        }
    }

    // One transaction for the whole loop, as google_list.rs does: one commit
    // instead of one per row. If it cannot start, the writes run unbatched.
    let tx = conn.unchecked_transaction().ok();

    for font in &scanned {
        let existing: Option<i32> = stored.get(&font.font_id).map(|s| s.0);

        match existing {
            Some(1) => {
                let s = &stored[&font.font_id];
                if s.1 == font.file_path && s.2 == font.file_name && s.4 == font.font_family {
                    continue;
                }
                // User override — keep their classification; refresh path and family name
                conn.execute(
                    "UPDATE fonts SET file_path = ?1, file_name = ?2, font_family = ?3, updated_at = ?4 WHERE font_id = ?5",
                    params![font.file_path, font.file_name, font.font_family, now, font.font_id],
                )
                .ok();
            }
            Some(_) => {
                let s = &stored[&font.font_id];
                if s.1 == font.file_path
                    && s.2 == font.file_name
                    && s.3 == font.source
                    && s.4 == font.font_family
                    && s.5 == font.weight
                    && s.6 == font.category
                    && s.7 == font.style
                    && s.8 == font.width
                {
                    continue;
                }
                // Exists, no override — update classification + path
                conn.execute(
                    "UPDATE fonts SET file_path = ?1, file_name = ?2, source = ?3, \
                     font_family = ?4, weight = ?5, category = ?6, style = ?7, width = ?8, \
                     updated_at = ?9 WHERE font_id = ?10",
                    params![
                        font.file_path, font.file_name, font.source,
                        font.font_family, font.weight, font.category,
                        font.style, font.width, now, font.font_id
                    ],
                )
                .ok();
            }
            None => {
                // New font — insert
                let flesh_serif: i32 = if font.category == "serif" { 1 } else { 0 };
                conn.execute(
                    "INSERT INTO fonts (
                        font_id, name, file_path, file_name, source,
                        font_family, weight, category, style, width,
                        skeleton, flesh_contrast, flesh_serif,
                        classification_source, user_override,
                        created_at, updated_at
                    ) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17)",
                    params![
                        font.font_id, font.font_family, font.file_path, font.file_name,
                        font.source, font.font_family, font.weight,
                        font.category, font.style, font.width,
                        "unknown", "linear", flesh_serif,
                        "file", 0, now, now
                    ],
                )
                .ok();
            }
        }
    }
    drop_stale_twins(conn, &scanned);
    prune_missing(conn, &private);
    if let Some(tx) = tx {
        tx.commit().ok();
    }
}

// ── Queries the apps call ─────────────────────────────────────────────────────

/// Every font row, sorted by family (what the Tauri UI loads on start).
pub fn get_font_rows(conn: &Connection) -> Result<Vec<FontRow>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, name, file_path, file_name, source,
                    font_family, weight, category, style, width,
                    foundry, designer, skeleton, flesh_contrast, flesh_serif,
                    x_height_ratio, cap_height_ratio, stroke_contrast_ratio,
                    classification_source, user_override, google_category,
                    classification_reason,
                    optical_role, superfamily_group, superfamily_role,
                    ascender_descender_ratio, weight_range_min, weight_range_max,
                    spacing_personality, width_class,
                    created_at, updated_at, is_trial, foundry_url
             FROM fonts ORDER BY font_family COLLATE NOCASE",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let category: String = row.get(7)?;
            let style: String = row.get(8)?;
            let width: String = row.get(9)?;

            Ok(FontRow {
                font_id: row.get(0)?,
                name: row.get(1)?,
                file_path: row.get(2)?,
                file_name: row.get(3)?,
                source: row.get(4)?,
                font_family: row.get(5)?,
                weight: row.get(6)?,
                classification: Classification {
                    category: category.clone(),
                    style: style.clone(),
                    width: width.clone(),
                },
                foundry: row.get(10)?,
                designer: row.get(11)?,
                skeleton: row.get(12)?,
                flesh_contrast: row.get(13)?,
                flesh_serif: row.get(14)?,
                x_height_ratio: row.get(15)?,
                cap_height_ratio: row.get(16)?,
                stroke_contrast_ratio: row.get(17)?,
                classification_source: row.get(18)?,
                user_override: row.get(19)?,
                google_category: row.get(20)?,
                classification_reason: row.get(21)?,
                optical_role: row.get(22)?,
                superfamily_group: row.get(23)?,
                superfamily_role: row.get(24)?,
                ascender_descender_ratio: row.get(25)?,
                weight_range_min: row.get(26)?,
                weight_range_max: row.get(27)?,
                spacing_personality: row.get(28)?,
                width_class: row.get(29)?,
                created_at: row.get(30)?,
                updated_at: row.get(31)?,
                is_trial: row.get(32)?,
                foundry_url: row.get(33)?,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut result = Vec::new();
    for row in rows {
        result.push(row.map_err(|e| e.to_string())?);
    }
    Ok(result)
}

pub fn update_font_classification(
    conn: &Connection,
    font_id: String,
    updates: FontUpdate,
) -> Result<(), String> {
    let now = now_iso();

    // Build dynamic SET clauses
    let mut sets: Vec<String> = Vec::new();
    let mut values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    macro_rules! add_field {
        ($field:ident, $col:expr) => {
            if let Some(v) = updates.$field {
                sets.push(format!("{} = ?{}", $col, values.len() + 1));
                values.push(Box::new(v));
            }
        };
    }

    add_field!(foundry, "foundry");
    add_field!(designer, "designer");
    add_field!(skeleton, "skeleton");
    add_field!(flesh_contrast, "flesh_contrast");
    add_field!(flesh_serif, "flesh_serif");
    add_field!(x_height_ratio, "x_height_ratio");
    add_field!(cap_height_ratio, "cap_height_ratio");
    add_field!(stroke_contrast_ratio, "stroke_contrast_ratio");
    add_field!(classification_source, "classification_source");
    add_field!(user_override, "user_override");
    add_field!(google_category, "google_category");
    add_field!(category, "category");
    add_field!(classification_reason, "classification_reason");

    if sets.is_empty() {
        return Ok(());
    }

    sets.push(format!("updated_at = ?{}", values.len() + 1));
    values.push(Box::new(now));

    sets.push(format!("font_id = font_id")); // no-op anchor for WHERE

    let sql = format!(
        "UPDATE fonts SET {} WHERE font_id = ?{}",
        sets[..sets.len() - 1].join(", "),
        values.len() + 1
    );
    values.push(Box::new(font_id));

    let params: Vec<&dyn rusqlite::types::ToSql> = values.iter().map(|v| v.as_ref()).collect();
    conn.execute(&sql, params.as_slice())
        .map_err(|e| e.to_string())?;

    Ok(())
}

pub fn classify_single_font(
    conn: &Connection,
    font_id: String,
) -> Result<classifier::ClassificationResult, String> {

    let (file_path, family_name, category): (String, String, String) = conn
        .query_row(
            "SELECT file_path, font_family, category FROM fonts WHERE font_id = ?1",
            params![font_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|e| e.to_string())?;

    let mut result = classifier::classify_font(Path::new(&file_path), &family_name);
    result.flesh_serif = if category == "serif" { 1 } else { 0 };

    // Persist to DB
    let now = now_iso();
    conn.execute(
        "UPDATE fonts SET skeleton = ?1, flesh_contrast = ?2, flesh_serif = ?3, \
         stroke_contrast_ratio = ?4, classification_reason = ?5, updated_at = ?6 \
         WHERE font_id = ?7",
        params![
            result.skeleton,
            result.flesh_contrast,
            result.flesh_serif,
            result.stroke_contrast_ratio,
            result.reason,
            now,
            font_id,
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(result)
}

/// Re-pull the Google Fonts catalogue and return how many fonts gained a foundry.
pub fn refresh_google_fonts(conn: &Connection, data_dir: &Path) -> Result<u32, String> {
    // Count fonts before enrichment
    let before: u32 = conn
        .query_row("SELECT COUNT(*) FROM fonts WHERE foundry IS NOT NULL", [], |r| r.get(0))
        .unwrap_or(0);

    crate::google_fonts::enrich_from_google(conn, data_dir, true);

    let after: u32 = conn
        .query_row("SELECT COUNT(*) FROM fonts WHERE foundry IS NOT NULL", [], |r| r.get(0))
        .unwrap_or(0);

    Ok(after - before)
}

/// The startup sequence both apps run off the main thread: scan the disk,
/// read name tables, classify, measure, enrich from Google Fonts. Opens its own
/// connection (WAL), so readers elsewhere are never blocked for long. Returns
/// the number of font rows afterwards.
pub fn refresh_library(db_path: &Path) -> Result<u32, String> {
    refresh_library_in(db_path, None)
}

/// `refresh_library` with an optional list of folders to scan instead of the three macOS
/// font folders. A scan of given folders is the test seam: the rows get source "user" and the
/// Google steps (network) are skipped, so a test scans a fixture folder and nothing else.
pub fn refresh_library_in(db_path: &Path, folders: Option<&[PathBuf]>) -> Result<u32, String> {
    let conn = try_open_db_at(db_path).map_err(|e| e.to_string())?;
    crate::progress::start();
    match folders {
        Some(dirs) => {
            let targets: Vec<(PathBuf, &str)> = dirs.iter().map(|d| (d.clone(), "user")).collect();
            populate_from(&conn, &targets);
        }
        None => populate_db(&conn),
    }
    enrich_from_name_tables(&conn);
    classify_all(&conn);
    enrich_metrics(&conn);
    crate::progress::finish();
    if folders.is_none() {
        let data_dir = db_path.parent().unwrap_or_else(|| Path::new("."));
        crate::google_fonts::enrich_from_google(&conn, data_dir, false);
        // Google's public family list (no key). Last, and never fatal: offline keeps the last stored list.
        crate::google_list::sync_catalog(&conn, data_dir);
    }
    conn.query_row("SELECT COUNT(*) FROM fonts", [], |r| r.get(0)).map_err(|e| e.to_string())
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod scan_tests;

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn migrations_apply_from_scratch_and_set_version() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
        // every added column should now be selectable
        conn.execute_batch("SELECT width_class, spacing_personality, optical_role FROM fonts;")
            .unwrap();
    }

    #[test]
    fn migrations_are_idempotent_on_existing_db() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        run_migrations(&conn); // second run must be a no-op, not a panic
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
    }

    #[test]
    fn legacy_db_with_columns_but_version_zero_converges() {
        // Simulate an installed DB: columns already added by the OLD ad-hoc
        // ALTERs, but user_version still 0.
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        // Replicate the OLD ad-hoc init: each ALTER ran with .ok(), tolerating
        // the duplicate-column case (classification_reason is already in
        // CREATE_TABLE, so its ALTER was always a no-op).
        for stmt in MIGRATIONS {
            conn.execute_batch(stmt).ok(); // pre-add columns, ignore duplicates
        }
        // user_version is still 0 here.
        run_migrations(&conn); // must tolerate the duplicate-column errors and stamp version
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
    }

    /// An install written by an older build: fonts table without vendor_id,
    /// is_trial, foundry_url, and no userdata tables. Opening it through the
    /// core must migrate it in place and keep its rows.
    #[test]
    fn opening_an_old_schema_db_migrates_it() {
        let dir = std::env::temp_dir().join(format!("fontdrop-core-old-schema-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("old.db");
        let _ = std::fs::remove_file(&path);
        {
            let old = Connection::open(&path).unwrap();
            old.execute_batch(CREATE_TABLE).unwrap();
            // The first nine migrations had shipped; vendor_id and everything after had not.
            for stmt in &MIGRATIONS[..9] {
                old.execute_batch(stmt).ok(); // classification_reason is already in CREATE_TABLE
            }
            old.execute_batch("PRAGMA user_version = 9;").unwrap();
            old.execute(
                "INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, created_at, updated_at)
                 VALUES ('a', 'Sample Regular', '/tmp/Sample-Regular.otf', 'Sample-Regular.otf', 'user', 'Sample', 'x', 'x')",
                [],
            )
            .unwrap();
            assert!(old.prepare("SELECT vendor_id FROM fonts").is_err());
            assert!(old.prepare("SELECT is_trial FROM fonts").is_err());
            assert!(old.prepare("SELECT foundry_url FROM fonts").is_err());
            assert!(old.prepare("SELECT * FROM brands").is_err());
        }

        let conn = try_open_db_at(&path).unwrap();
        conn.execute_batch("SELECT vendor_id, is_trial, foundry_url FROM fonts;").unwrap();
        conn.execute_batch("SELECT * FROM brands; SELECT * FROM shortlist; SELECT * FROM choices; SELECT * FROM meta;").unwrap();
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
        let kept: i64 = conn.query_row("SELECT COUNT(*) FROM fonts WHERE font_id = 'a'", [], |r| r.get(0)).unwrap();
        assert_eq!(kept, 1);
        // user data works on the migrated DB
        let b = crate::userdata::create_brand(&conn, "Sample Brand").unwrap();
        assert_eq!(crate::userdata::list_brands(&conn).unwrap(), vec![b]);
        drop(conn);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A library stamped by a newer build is refused untouched: its version stays, and nothing is written.
    #[test]
    fn newer_library_is_refused_and_its_version_is_kept() {
        let dir = std::env::temp_dir().join(format!("fontdrop-core-newer-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("new.db");
        let _ = std::fs::remove_file(&path);
        let newer = MIGRATIONS.len() + 3;
        {
            let c = Connection::open(&path).unwrap();
            c.execute_batch(CREATE_TABLE).unwrap();
            c.execute_batch(&format!("PRAGMA user_version = {newer};")).unwrap();
        }
        let err = try_open_db_at(&path).expect_err("a newer library must not open");
        assert!(err.to_string().contains(NEWER_LIBRARY), "{err}");
        let c = Connection::open(&path).unwrap();
        let v: i64 = c.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, newer, "an older build never lowers the version");
        drop(c);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Opening twice never lowers user_version, and an install behind us is raised to the current one.
    #[test]
    fn version_only_moves_up() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        let v1: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        run_migrations(&conn);
        let v2: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v1, v2);
        assert_eq!(v2 as usize, MIGRATIONS.len());
    }

    /// An install that already stamped is_trial = 0 with the old check (family names and licence
    /// text only) must be re-read once: the finding-fonts migrations reset the flag.
    #[test]
    fn migration_makes_old_trial_flags_get_re_read() {
        let dir = std::env::temp_dir().join(format!("fontdrop-core-trial-reset-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("old.db");
        let _ = std::fs::remove_file(&path);
        {
            let old = Connection::open(&path).unwrap();
            old.execute_batch(CREATE_TABLE).unwrap();
            for stmt in &MIGRATIONS[..16] {
                old.execute_batch(stmt).ok();
            }
            old.execute_batch("PRAGMA user_version = 16;").unwrap();
            old.execute(
                "INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, is_trial, created_at, updated_at)
                 VALUES ('v', 'GT Flexa Var Trial', '/tmp/GT Flexa Var Trial.ttf', 'GT Flexa Var Trial.ttf', 'user', 'GT Flexa Var', 0, 'x', 'x')",
                [],
            )
            .unwrap();
        }
        let conn = try_open_db_at(&path).unwrap();
        let trial: Option<i64> = conn.query_row("SELECT is_trial FROM fonts WHERE font_id = 'v'", [], |r| r.get(0)).unwrap();
        assert_eq!(trial, None, "NULL means 'read the file again'");
        conn.execute_batch("SELECT style_name FROM fonts;").unwrap();
        conn.execute_batch("SELECT is_variable FROM fonts; SELECT * FROM google_families; SELECT * FROM hidden; SELECT * FROM favorites;").unwrap();
        drop(conn);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Re-run the startup scan against a COPY of a real database, so a data fix
    /// can be measured without touching the live one. Run on demand:
    ///   cp "<app support>/fontdrop.db" /tmp/fd-copy.db
    ///   cd core && FONTDROP_DB=/tmp/fd-copy.db cargo test --lib rescan_copy -- --ignored --nocapture
    #[test]
    #[ignore]
    fn rescan_copy() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
        assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy, not the live DB");
        let conn = Connection::open(&path).unwrap();
        run_migrations(&conn);
        let dup_paths = |c: &Connection| -> i64 {
            c.query_row("SELECT COUNT(*) FROM (SELECT file_path FROM fonts GROUP BY file_path HAVING COUNT(*) > 1)", [], |r| r.get(0)).unwrap()
        };
        println!("paths with two rows before: {}", dup_paths(&conn));
        let t = std::time::Instant::now();
        populate_db(&conn);
        println!("populate_db: {:.2}s", t.elapsed().as_secs_f64());
        enrich_from_name_tables(&conn);
        classify_all(&conn);
        println!("full rescan (scan, name tables, classify): {:.2}s", t.elapsed().as_secs_f64());
        println!("paths with two rows after: {}", dup_paths(&conn));
        let fams: i64 = conn.query_row("SELECT COUNT(DISTINCT font_family) FROM fonts WHERE source='user'", [], |r| r.get(0)).unwrap();
        let singles: i64 = conn.query_row(
            "SELECT COUNT(*) FROM (SELECT font_family FROM fonts WHERE source='user' GROUP BY font_family HAVING COUNT(*)=1)",
            [], |r| r.get(0)).unwrap();
        println!("user families: {fams}; one-file families: {singles}");
        let mut st = conn.prepare("SELECT skeleton, COUNT(*) FROM fonts GROUP BY skeleton").unwrap();
        for row in st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))).unwrap().flatten() {
            println!("  skeleton {:<10} {}", row.0, row.1);
        }
    }

    /// Which families the Latin check newly hides, on a COPY of a real database:
    ///   FONTDROP_DB=<copy> cargo test --lib latin_report -- --ignored --nocapture
    /// Prints each family where no style covers basic Latin (not already junk-listed), its
    /// A-Z / a-z / 0-9 counts, and the near misses that the rule keeps (partial coverage).
    #[test]
    #[ignore]
    fn latin_report() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
        assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy, not the live DB");
        let conn = Connection::open(&path).unwrap();
        run_migrations(&conn);
        conn.execute("UPDATE fonts SET covers_latin = NULL", []).unwrap(); // measure with the current rule
        enrich_from_name_tables(&conn);
        let none = crate::finder::no_latin_families(&conn);
        let mut st = conn.prepare("SELECT font_family, file_path, source, covers_latin FROM fonts").unwrap();
        let rows: Vec<(String, String, String, Option<i64>)> =
            st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).unwrap().flatten().collect();
        let mut caught = 0;
        let mut seen = std::collections::BTreeSet::new();
        for (fam, file, source, _) in &rows {
            let lower = fam.to_lowercase();
            let Some(data) = std::fs::read(file).ok() else { continue };
            let Ok(font) = skrifa::FontRef::from_index(&data, 0) else { continue };
            let (u, l, d) = crate::names::latin_coverage(&font);
            let full = crate::names::covers_latin(u, l, d);
            let partial = !full && (u + l + d) > 0;
            if none.contains(&lower) && seen.insert(("caught", fam.clone())) {
                let junk = crate::finder::is_junk_family(fam);
                println!("CAUGHT {fam:<40} [{source}] A-Z {u}/26 a-z {l}/26 0-9 {d}/10{}", if junk { "  (already junk-listed)" } else { "" });
                if !junk { caught += 1; }
            } else if partial && !none.contains(&lower) && seen.insert(("kept", fam.clone())) {
                println!("PARTIAL-KEPT {fam:<34} [{source}] A-Z {u}/26 a-z {l}/26 0-9 {d}/10");
            }
        }
        println!("newly hidden (not junk-listed): {caught}");
    }

    /// Build a fresh benchmark DB from a folder of fonts (one subfolder per family):
    ///   cd core && BENCH_FONTS=<dir> BENCH_DB=<new.db> cargo test --lib build_bench_db -- --ignored --nocapture
    #[test]
    #[ignore]
    fn build_bench_db() {
        let fonts = std::env::var("BENCH_FONTS").expect("set BENCH_FONTS");
        let db = std::env::var("BENCH_DB").expect("set BENCH_DB");
        let _ = std::fs::remove_file(&db);
        let conn = Connection::open(&db).unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        populate_from(&conn, &[(PathBuf::from(&fonts), "user")]);
        enrich_from_name_tables(&conn);
        classify_all(&conn);
        enrich_metrics(&conn);
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM fonts", [], |r| r.get(0)).unwrap();
        let f: i64 = conn.query_row("SELECT COUNT(DISTINCT font_family) FROM fonts", [], |r| r.get(0)).unwrap();
        println!("bench db: {n} fonts, {f} families");
    }
}
