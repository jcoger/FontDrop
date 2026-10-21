use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{parse_family, parse_font_meta, read_family_name, read_name_meta, Classification};
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

// ── Managed state ─────────────────────────────────────────────────────────────

pub struct DbState(pub Mutex<Connection>);
pub struct AppDataDir(pub PathBuf);

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
    let data = std::fs::read(path).ok()?;
    let chunk = if data.len() > 65_536 { &data[..65_536] } else { &data };
    let mut hasher = Sha256::new();
    hasher.update(chunk);
    Some(format!("{:x}", hasher.finalize()))
}

fn now_iso() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

/// Public alias for other modules.
pub fn now_iso_pub() -> String {
    now_iso()
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
];

/// Apply any migrations with index >= the DB's current user_version, then
/// stamp user_version to MIGRATIONS.len(). Tolerates "duplicate column"
/// (existing DBs already have these columns) but surfaces any other error.
pub(crate) fn run_migrations(conn: &Connection) {
    let current: i64 = conn
        .query_row("PRAGMA user_version;", [], |r| r.get(0))
        .unwrap_or(0);

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
                panic!("schema migration {} failed: {}", i, e);
            }
        }
    }

    // Stamp the new version. PRAGMA doesn't accept bound params, so format it
    // (the value is MIGRATIONS.len(), not user input).
    let target = MIGRATIONS.len();
    conn.execute_batch(&format!("PRAGMA user_version = {};", target))
        .expect("failed to set user_version");
}

// ── DB init ───────────────────────────────────────────────────────────────────

pub fn open_db(app_data_dir: &Path) -> Connection {
    std::fs::create_dir_all(app_data_dir).ok();
    let db_path = app_data_dir.join("fontdrop.db");
    let conn = Connection::open(db_path).expect("failed to open font database");
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        .expect("failed to set pragmas");
    conn.execute_batch(CREATE_TABLE)
        .expect("failed to create fonts table");
    run_migrations(&conn);
    conn
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

fn scan_dir_for_db(dir: &PathBuf, source: &str, results: &mut Vec<ScannedFont>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan_dir_for_db(&path, source, results);
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
    let rows: Vec<(String, String)> = match conn.prepare("SELECT font_id, file_path FROM fonts WHERE vendor_id IS NULL") {
        Ok(mut st) => st
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => return,
    };
    for (font_id, path) in rows {
        let meta = read_name_meta(Path::new(&path));
        let (vendor, manufacturer, designer) = match meta {
            Some(m) => (m.vendor.unwrap_or_default(), m.manufacturer, m.designer),
            None => (String::new(), None, None),
        };
        conn.execute(
            "UPDATE fonts SET vendor_id = ?1, \
             foundry = COALESCE(NULLIF(foundry, ''), ?2), \
             designer = COALESCE(NULLIF(designer, ''), ?3) WHERE font_id = ?4",
            params![vendor, manufacturer, designer, font_id],
        )
        .ok();
    }
}

/// Bump when the classifier's rules change: every non-override font is then
/// reclassified once on the next launch instead of only the 'unknown' ones.
pub const CLASSIFIER_VERSION: i64 = 5;

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

    for (font_id, file_path, family_name, category) in &rows {
        let result = classifier::classify_font(Path::new(file_path), family_name);

        // Serif from the outlines when measurable; the category field says
        // "other" for ~64% of fonts, so it's only the fallback.
        let flesh_serif: i32 = match result.serif {
            Some(serif) => serif as i32,
            None => (category == "serif") as i32,
        };

        conn.execute(
            "UPDATE fonts SET skeleton = ?1, flesh_contrast = ?2, flesh_serif = ?3, \
             stroke_contrast_ratio = ?4, classification_reason = ?5, updated_at = ?6 \
             WHERE font_id = ?7",
            params![
                result.skeleton,
                result.flesh_contrast,
                flesh_serif,
                result.stroke_contrast_ratio,
                result.reason,
                now,
                font_id,
            ],
        )
        .ok();
    }

    unify_family_skeletons(conn);
    if rerun_all {
        meta_set(conn, "classifier_version", &CLASSIFIER_VERSION.to_string());
    }
}

/// One skeleton per family. Files of one family were classified one by one and
/// disagreed (29% of multi-file families). The family's upright face nearest
/// weight 400 decides; every non-override file in the family takes its answer.
fn unify_family_skeletons(conn: &Connection) {
    let rows: Vec<(String, String, i64, String, String, String)> = match conn.prepare(
        "SELECT font_family, file_name, weight, skeleton, flesh_contrast, COALESCE(classification_reason, '') FROM fonts",
    ) {
        Ok(mut stmt) => stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)))
            .map(|it| it.filter_map(|r| r.ok()).collect())
            .unwrap_or_default(),
        Err(_) => return,
    };

    // family -> (distance from an upright 400, skeleton, flesh_contrast, reason)
    let mut best: std::collections::HashMap<String, (i64, String, String, String)> = std::collections::HashMap::new();
    for (family, file_name, weight, skeleton, flesh, reason) in rows {
        if skeleton == "unknown" { continue; }
        let lower = file_name.to_lowercase();
        let slanted = lower.contains("italic") || lower.contains("oblique") || lower.contains("kursiv");
        let dist = (weight - 400).abs() + if slanted { 1000 } else { 0 };
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

    for (font_id, file_path, family_name, stroke_contrast, x_height) in &rows {
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
    for (dir, source) in scan_targets {
        scan_dir_for_db(dir, source, &mut scanned);
    }

    let now = now_iso();

    for font in &scanned {
        // Check if row exists and whether it has a user override
        let existing: Option<i32> = conn
            .query_row(
                "SELECT user_override FROM fonts WHERE font_id = ?1",
                params![font.font_id],
                |row| row.get(0),
            )
            .ok();

        match existing {
            Some(1) => {
                // User override — keep their classification; refresh path and family name
                conn.execute(
                    "UPDATE fonts SET file_path = ?1, file_name = ?2, font_family = ?3, updated_at = ?4 WHERE font_id = ?5",
                    params![font.file_path, font.file_name, font.font_family, now, font.font_id],
                )
                .ok();
            }
            Some(_) => {
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
}

// ── Tauri commands ────────────────────────────────────────────────────────────

#[tauri::command]
pub fn get_font_db(state: tauri::State<'_, DbState>) -> Result<Vec<FontRow>, String> {
    let conn = state.0.lock().map_err(|e| e.to_string())?;

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
                    created_at, updated_at
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
            })
        })
        .map_err(|e| e.to_string())?;

    let mut result = Vec::new();
    for row in rows {
        result.push(row.map_err(|e| e.to_string())?);
    }
    Ok(result)
}

#[tauri::command]
pub fn update_font_classification(
    state: tauri::State<'_, DbState>,
    font_id: String,
    updates: FontUpdate,
) -> Result<(), String> {
    let conn = state.0.lock().map_err(|e| e.to_string())?;
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

#[tauri::command]
pub fn classify_single_font(
    state: tauri::State<'_, DbState>,
    font_id: String,
) -> Result<classifier::ClassificationResult, String> {
    let conn = state.0.lock().map_err(|e| e.to_string())?;

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

#[tauri::command]
pub fn refresh_google_fonts(
    state: tauri::State<'_, DbState>,
    data_dir: tauri::State<'_, AppDataDir>,
) -> Result<u32, String> {
    let conn = state.0.lock().map_err(|e| e.to_string())?;

    // Count fonts before enrichment
    let before: u32 = conn
        .query_row("SELECT COUNT(*) FROM fonts WHERE foundry IS NOT NULL", [], |r| r.get(0))
        .unwrap_or(0);

    crate::google_fonts::enrich_from_google(&conn, &data_dir.0, true);

    let after: u32 = conn
        .query_row("SELECT COUNT(*) FROM fonts WHERE foundry IS NOT NULL", [], |r| r.get(0))
        .unwrap_or(0);

    Ok(after - before)
}

#[tauri::command]
pub fn set_google_api_key(
    data_dir: tauri::State<'_, AppDataDir>,
    key: String,
) -> Result<(), String> {
    crate::google_fonts::save_api_key(&data_dir.0, &key);
    Ok(())
}

#[tauri::command]
pub fn get_google_api_key(
    data_dir: tauri::State<'_, AppDataDir>,
) -> Result<Option<String>, String> {
    Ok(crate::google_fonts::get_api_key(&data_dir.0))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

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

    /// Re-run the startup scan against a COPY of a real database, so a data fix
    /// can be measured without touching the live one. Run on demand:
    ///   cp "<app support>/fontdrop.db" /tmp/fd-copy.db
    ///   FONTDROP_DB=/tmp/fd-copy.db cargo test --lib rescan_copy -- --ignored --nocapture
    #[test]
    #[ignore]
    fn rescan_copy() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
        assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy, not the live DB");
        let conn = Connection::open(&path).unwrap();
        run_migrations(&conn);
        populate_db(&conn);
        enrich_from_name_tables(&conn);
        classify_all(&conn);
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

    /// Build a fresh benchmark DB from a folder of fonts (one subfolder per family):
    ///   BENCH_FONTS=<dir> BENCH_DB=<new.db> cargo test --lib build_bench_db -- --ignored --nocapture
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
