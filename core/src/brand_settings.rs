//! Per-brand type settings: the scale (body, ratio, lock, measure, line height), the three template colors, and
//! the settings of each face (style file, axes, tracking, trim, features).
//!
//! Until round R5 the SwiftUI app kept these in three JSON files next to the library
//! (`<db>.scale.json`, `<db>.colors.json`, `<db>.playground.json`). They now live in tables that cascade from
//! `brands`, so deleting a brand deletes them and a brand id can never inherit them.
//! `import_legacy_json` copies the old files in once, records that it ran, and never touches the files.

use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use serde_json::{Map, Value};

/// The meta row that says the one-time import of the JSON side files has run.
pub const IMPORT_META_KEY: &str = "brand_settings_json_import";

#[derive(Serialize, Clone, Debug, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct BrandScale {
    pub brand_id: i64,
    pub body: f64,
    pub ratio: f64,
    pub locked: bool,
    /// Characters per line for body text. None: follow the type rules.
    pub measure: Option<u32>,
    /// Body line height as a multiple of the size. None: follow the measure.
    pub line_height: Option<f64>,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct BrandColors {
    pub brand_id: i64,
    /// "#RRGGBB"
    pub background: String,
    pub text: String,
    pub accent: String,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct FaceSettings {
    pub brand_id: i64,
    pub job: String,
    pub family: String,
    pub style_path: Option<String>,
    pub tracking: f64,
    pub line_height: f64,
    pub trim: f64,
    /// JSON object, axis tag to value ({"opsz": 14}).
    pub axes_json: String,
    /// JSON object, feature key to selector ({"35.2": 1}).
    pub features_json: String,
}

// ── Scale ─────────────────────────────────────────────────────────────────────

pub fn scales(conn: &Connection) -> Result<Vec<BrandScale>, String> {
    let mut st = conn
        .prepare("SELECT brand_id, body, ratio, locked, measure, line_height FROM brand_scale ORDER BY brand_id")
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map([], |r| {
            Ok(BrandScale {
                brand_id: r.get(0)?,
                body: r.get(1)?,
                ratio: r.get(2)?,
                locked: r.get::<_, i64>(3)? != 0,
                measure: r.get::<_, Option<i64>>(4)?.map(|m| m.max(0) as u32),
                line_height: r.get(5)?,
            })
        })
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

pub fn set_scale(conn: &Connection, s: &BrandScale) -> Result<(), String> {
    conn.execute(
        "INSERT INTO brand_scale (brand_id, body, ratio, locked, measure, line_height) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT(brand_id) DO UPDATE SET body = excluded.body, ratio = excluded.ratio, locked = excluded.locked,
         measure = excluded.measure, line_height = excluded.line_height",
        params![s.brand_id, s.body, s.ratio, s.locked as i64, s.measure.map(|m| m as i64), s.line_height],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

// ── Colors ────────────────────────────────────────────────────────────────────

pub fn colors(conn: &Connection) -> Result<Vec<BrandColors>, String> {
    let mut st = conn
        .prepare("SELECT brand_id, background, text, accent FROM brand_colors ORDER BY brand_id")
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map([], |r| Ok(BrandColors { brand_id: r.get(0)?, background: r.get(1)?, text: r.get(2)?, accent: r.get(3)? }))
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

pub fn set_colors(conn: &Connection, c: &BrandColors) -> Result<(), String> {
    conn.execute(
        "INSERT INTO brand_colors (brand_id, background, text, accent) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(brand_id) DO UPDATE SET background = excluded.background, text = excluded.text, accent = excluded.accent",
        params![c.brand_id, c.background, c.text, c.accent],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn clear_colors(conn: &Connection, brand: i64) -> Result<(), String> {
    conn.execute("DELETE FROM brand_colors WHERE brand_id = ?1", params![brand]).map_err(|e| e.to_string())?;
    Ok(())
}

// ── Face settings ─────────────────────────────────────────────────────────────

pub fn faces(conn: &Connection) -> Result<Vec<FaceSettings>, String> {
    let mut st = conn
        .prepare(
            "SELECT brand_id, job, family, style_path, tracking, line_height, trim, axes_json, features_json
             FROM face_settings ORDER BY brand_id, job, family",
        )
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map([], |r| {
            Ok(FaceSettings {
                brand_id: r.get(0)?,
                job: r.get(1)?,
                family: r.get(2)?,
                style_path: r.get(3)?,
                tracking: r.get(4)?,
                line_height: r.get(5)?,
                trim: r.get(6)?,
                axes_json: r.get(7)?,
                features_json: r.get(8)?,
            })
        })
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

pub fn set_face(conn: &Connection, f: &FaceSettings) -> Result<(), String> {
    conn.execute(
        "INSERT INTO face_settings (brand_id, job, family, style_path, tracking, line_height, trim, axes_json, features_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(brand_id, job, family) DO UPDATE SET style_path = excluded.style_path, tracking = excluded.tracking,
         line_height = excluded.line_height, trim = excluded.trim, axes_json = excluded.axes_json,
         features_json = excluded.features_json",
        params![f.brand_id, f.job, f.family, f.style_path, f.tracking, f.line_height, f.trim, f.axes_json, f.features_json],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn clear_face(conn: &Connection, brand: i64, job: &str, family: &str) -> Result<(), String> {
    conn.execute(
        "DELETE FROM face_settings WHERE brand_id = ?1 AND job = ?2 AND family = ?3",
        params![brand, job, family],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

// ── One-time import of the JSON side files ────────────────────────────────────

/// What the import copied, and what it left out.
#[derive(Serialize, Clone, Debug, Default, PartialEq)]
pub struct ImportReport {
    pub scales: u32,
    pub colors: u32,
    pub faces: u32,
    /// Entries for a brand that does not exist (including the "no brand" key 0): not importable.
    pub skipped: u32,
}

/// The side file for `db_path`: `<db>.scale.json` and so on.
fn side_file(db_path: &Path, suffix: &str) -> std::path::PathBuf {
    let mut name = db_path.as_os_str().to_owned();
    name.push(format!(".{suffix}.json"));
    name.into()
}

fn read_object(path: &Path) -> Map<String, Value> {
    std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .and_then(|v| if let Value::Object(m) = v { Some(m) } else { None })
        .unwrap_or_default()
}

fn brand_exists(conn: &Connection, id: i64) -> bool {
    conn.query_row("SELECT 1 FROM brands WHERE id = ?1", params![id], |_| Ok(())).optional().ok().flatten().is_some()
}

fn num(v: &Value, key: &str) -> Option<f64> {
    v.get(key).and_then(Value::as_f64)
}

fn json_object(v: &Value, key: &str) -> String {
    match v.get(key) {
        Some(Value::Object(m)) => Value::Object(m.clone()).to_string(),
        _ => "{}".into(),
    }
}

/// Copies `<db>.scale.json`, `<db>.colors.json` and `<db>.playground.json` into the tables, once.
/// Returns None when it already ran. The files are only read: never rewritten, renamed or deleted.
/// Existing rows win (INSERT OR IGNORE), so a second run, or a run after the designer used the new build, changes nothing.
pub fn import_legacy_json(conn: &Connection, db_path: &Path) -> Result<Option<ImportReport>, String> {
    let done: Option<String> = conn
        .query_row("SELECT value FROM meta WHERE key = ?1", params![IMPORT_META_KEY], |r| r.get(0))
        .optional()
        .map_err(|e| e.to_string())?;
    if done.is_some() {
        return Ok(None);
    }
    let mut report = ImportReport::default();
    conn.execute_batch("BEGIN").map_err(|e| e.to_string())?;
    let result = (|| -> Result<(), String> {
        // Scale: {"<brand>": {"body": 15, "ratio": 1.333, "locked": true}}
        for (key, v) in read_object(&side_file(db_path, "scale")) {
            let Some(id) = key.parse::<i64>().ok().filter(|id| brand_exists(conn, *id)) else { report.skipped += 1; continue };
            let n = conn
                .execute(
                    "INSERT OR IGNORE INTO brand_scale (brand_id, body, ratio, locked) VALUES (?1, ?2, ?3, ?4)",
                    params![id, num(&v, "body").unwrap_or(15.0).clamp(9.0, 24.0), num(&v, "ratio").unwrap_or(1.333),
                            v.get("locked").and_then(Value::as_bool).unwrap_or(false) as i64],
                )
                .map_err(|e| e.to_string())?;
            report.scales += n as u32;
        }
        // Colors: {"<brand>": {"background": "#FFFFFF", "text": "#0A0A0A", "accent": "#E5341D"}}
        for (key, v) in read_object(&side_file(db_path, "colors")) {
            let Some(id) = key.parse::<i64>().ok().filter(|id| brand_exists(conn, *id)) else { report.skipped += 1; continue };
            let (Some(b), Some(t), Some(a)) = (
                v.get("background").and_then(Value::as_str),
                v.get("text").and_then(Value::as_str),
                v.get("accent").and_then(Value::as_str),
            ) else { report.skipped += 1; continue };
            let n = conn
                .execute(
                    "INSERT OR IGNORE INTO brand_colors (brand_id, background, text, accent) VALUES (?1, ?2, ?3, ?4)",
                    params![id, b, t, a],
                )
                .map_err(|e| e.to_string())?;
            report.colors += n as u32;
        }
        // Face settings: {"<brand>/<job>/<family>": {...}}. A family name can hold a slash, so split into three.
        for (key, v) in read_object(&side_file(db_path, "playground")) {
            let parts: Vec<&str> = key.splitn(3, '/').collect();
            let id = parts.first().and_then(|p| p.parse::<i64>().ok()).filter(|id| brand_exists(conn, *id));
            let (Some(id), 3) = (id, parts.len()) else { report.skipped += 1; continue };
            let n = conn
                .execute(
                    "INSERT OR IGNORE INTO face_settings
                     (brand_id, job, family, style_path, tracking, line_height, trim, axes_json, features_json)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                    params![id, parts[1], parts[2], v.get("stylePath").and_then(Value::as_str),
                            num(&v, "tracking").unwrap_or(0.0), num(&v, "lineHeight").unwrap_or(1.3),
                            num(&v, "trim").unwrap_or(1.0).clamp(0.75, 1.35),
                            json_object(&v, "axes"), json_object(&v, "features")],
                )
                .map_err(|e| e.to_string())?;
            report.faces += n as u32;
        }
        conn.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO NOTHING",
            params![IMPORT_META_KEY, crate::db::now_iso()],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    })();
    match result {
        Ok(()) => conn.execute_batch("COMMIT").map_err(|e| e.to_string())?,
        Err(e) => {
            conn.execute_batch("ROLLBACK").ok();
            return Err(e);
        }
    }
    Ok(Some(report))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::userdata;

    /// A migrated in-memory DB with foreign keys ON, as the app opens it (the cascade is what is under test).
    fn db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        conn.execute_batch(crate::db::CREATE_TABLE).unwrap();
        crate::db::run_migrations(&conn);
        conn.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        conn
    }

    fn scale(brand: i64) -> BrandScale {
        BrandScale { brand_id: brand, body: 17.0, ratio: 1.25, locked: true, measure: Some(60), line_height: Some(1.45) }
    }
    fn face(brand: i64) -> FaceSettings {
        FaceSettings { brand_id: brand, job: "display".into(), family: "Acme Serif".into(), style_path: None, tracking: 0.01,
                       line_height: 1.1, trim: 1.1, axes_json: r#"{"opsz":14.0}"#.into(), features_json: "{}".into() }
    }
    fn count(conn: &Connection, table: &str) -> i64 {
        conn.query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get(0)).unwrap()
    }
    fn fill(conn: &Connection, brand: i64) {
        set_scale(conn, &scale(brand)).unwrap();
        set_colors(conn, &BrandColors { brand_id: brand, background: "#101312".into(), text: "#E8E8E4".into(), accent: "#E5341D".into() }).unwrap();
        set_face(conn, &face(brand)).unwrap();
        userdata::choose(conn, brand, "display", "Acme Serif").unwrap();
        userdata::shortlist_add(conn, brand, "reading", "Satoshi").unwrap();
    }

    #[test]
    fn settings_round_trip_and_update_in_place() {
        let c = db();
        let b = userdata::create_brand(&c, "A").unwrap().id;
        fill(&c, b);
        assert_eq!(scales(&c).unwrap(), vec![scale(b)]);
        let mut s = scale(b);
        s.measure = None;
        s.locked = false;
        set_scale(&c, &s).unwrap();
        assert_eq!(scales(&c).unwrap(), vec![s]);
        assert_eq!(faces(&c).unwrap(), vec![face(b)]);
        clear_face(&c, b, "display", "Acme Serif").unwrap();
        clear_colors(&c, b).unwrap();
        assert!(faces(&c).unwrap().is_empty() && colors(&c).unwrap().is_empty());
    }

    #[test]
    fn deleting_a_brand_takes_every_per_brand_row_with_it() {
        let c = db();
        let a = userdata::create_brand(&c, "A").unwrap().id;
        let keep = userdata::create_brand(&c, "B").unwrap().id;
        fill(&c, a);
        fill(&c, keep);
        userdata::delete_brand(&c, a).unwrap();
        for table in ["brand_scale", "brand_colors", "face_settings", "choices", "shortlist"] {
            assert_eq!(count(&c, table), 1, "{table}: only the other brand's row is left");
            let n: i64 = c.query_row(&format!("SELECT COUNT(*) FROM {table} WHERE brand_id = ?1"), params![a], |r| r.get(0)).unwrap();
            assert_eq!(n, 0, "{table}");
        }
    }

    /// The cascade alone (no explicit deletes) removes the rows: the foreign keys are real.
    #[test]
    fn the_cascade_removes_the_rows_by_itself() {
        let c = db();
        let a = userdata::create_brand(&c, "A").unwrap().id;
        fill(&c, a);
        c.execute("DELETE FROM brands WHERE id = ?1", params![a]).unwrap();
        for table in ["brand_scale", "brand_colors", "face_settings", "choices", "shortlist"] {
            assert_eq!(count(&c, table), 0, "{table}");
        }
    }

    /// Delete the newest brand, make another: the new one gets a new id and starts with nothing.
    #[test]
    fn a_new_brand_never_reuses_a_deleted_id_and_starts_clean() {
        let c = db();
        let a = userdata::create_brand(&c, "A").unwrap().id;
        fill(&c, a);
        userdata::delete_brand(&c, a).unwrap();
        let b = userdata::create_brand(&c, "B").unwrap().id;
        assert!(b > a, "AUTOINCREMENT: {b} is past {a}");
        assert!(scales(&c).unwrap().is_empty() && faces(&c).unwrap().is_empty() && colors(&c).unwrap().is_empty());
        assert!(userdata::choices(&c, b).unwrap().is_empty());
        assert!(userdata::shortlist(&c, b, "reading").unwrap().is_empty());
    }

    /// An install from before the rebuild keeps its brands, ids and children.
    #[test]
    fn the_brands_rebuild_keeps_existing_brands_and_their_children() {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        c.execute_batch(crate::db::CREATE_TABLE).unwrap();
        // The old brands table, as migration 11 made it, plus children, before the rebuild migration.
        let old = crate::db::migrations_before_brands_rebuild();
        for stmt in old { c.execute_batch(stmt).ok(); }
        c.execute_batch(&format!("PRAGMA user_version = {};", old.len())).unwrap();
        c.execute("INSERT INTO brands (id, name) VALUES (7, 'Seven'), (9, 'Nine')", []).unwrap();
        c.execute("INSERT INTO choices (brand_id, job, font_family) VALUES (9, 'display', 'X')", []).unwrap();
        c.execute("INSERT INTO shortlist (brand_id, job, font_family) VALUES (7, 'reading', 'Y')", []).unwrap();
        crate::db::try_run_migrations(&c).unwrap();
        let ids: Vec<i64> = userdata::list_brands(&c).unwrap().iter().map(|b| b.id).collect();
        assert_eq!(ids, vec![7, 9]);
        assert_eq!(count(&c, "choices"), 1, "the rebuild did not cascade");
        assert_eq!(count(&c, "shortlist"), 1);
        let next = userdata::create_brand(&c, "Next").unwrap().id;
        assert_eq!(next, 10);
    }

    // ── Import ────────────────────────────────────────────────────────────────

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("fontdrop-core-import-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    const SCALE_JSON: &str = r#"{"1":{"body":17,"ratio":1.25,"locked":true},"0":{"body":12,"ratio":1.2,"locked":false},"99":{"body":12,"ratio":1.2,"locked":true}}"#;
    const COLORS_JSON: &str = r##"{"1":{"background":"#101312","text":"#E8E8E4","accent":"#E5341D"}}"##;
    const PLAY_JSON: &str = r#"{"1\/display\/Acme Serif":{"size":41.6,"axes":{"opsz":14},"lineHeight":1.2,"tracking":0.015,"features":{"35.2":1},"stylePath":"\/Fonts\/Acme-Heavy.otf","trim":1.1},
        "1\/reading\/AC\/DC Sans":{"axes":{},"lineHeight":1.5,"tracking":0,"features":{}},
        "0\/reading\/Orphan":{"axes":{},"lineHeight":1.5,"tracking":0,"features":{}}}"#;

    #[test]
    fn import_copies_the_json_once_and_leaves_the_files_alone() {
        let dir = temp_dir("once");
        let path = dir.join("lib.db");
        let files = [("scale", SCALE_JSON), ("colors", COLORS_JSON), ("playground", PLAY_JSON)];
        for (name, body) in files {
            std::fs::write(dir.join(format!("lib.db.{name}.json")), body).unwrap();
        }
        let conn = crate::db::try_open_db_at(&path).unwrap();
        assert_eq!(userdata::create_brand(&conn, "Acme").unwrap().id, 1);

        let report = import_legacy_json(&conn, &path).unwrap().expect("first run imports");
        assert_eq!(report, ImportReport { scales: 1, colors: 1, faces: 2, skipped: 3 });
        let s = scales(&conn).unwrap();
        assert_eq!((s[0].brand_id, s[0].body, s[0].ratio, s[0].locked, s[0].measure), (1, 17.0, 1.25, true, None));
        assert_eq!(colors(&conn).unwrap()[0].background, "#101312");
        let f = faces(&conn).unwrap();
        let acme = f.iter().find(|f| f.family == "Acme Serif").unwrap();
        assert_eq!((acme.job.as_str(), acme.style_path.as_deref(), acme.trim, acme.tracking), ("display", Some("/Fonts/Acme-Heavy.otf"), 1.1, 0.015));
        assert_eq!(acme.axes_json, r#"{"opsz":14}"#);
        assert_eq!(acme.features_json, r#"{"35.2":1}"#);
        assert!(f.iter().any(|f| f.family == "AC/DC Sans" && f.job == "reading"), "a slash in the family name survives");
        let meta: i64 = conn.query_row("SELECT COUNT(*) FROM meta WHERE key = ?1", params![IMPORT_META_KEY], |r| r.get(0)).unwrap();
        assert_eq!(meta, 1);

        // The designer changes a value in the database. A second launch must not undo it.
        let mut changed = s[0].clone();
        changed.body = 20.0;
        set_scale(&conn, &changed).unwrap();
        assert_eq!(import_legacy_json(&conn, &path).unwrap(), None, "second run is a no-op");
        drop(conn);
        let conn = crate::db::try_open_db_at(&path).unwrap();
        assert_eq!(import_legacy_json(&conn, &path).unwrap(), None, "and so is a run after reopening");
        assert_eq!(scales(&conn).unwrap()[0].body, 20.0);
        assert_eq!((count(&conn, "brand_scale"), count(&conn, "brand_colors"), count(&conn, "face_settings")), (1, 1, 2));

        for (name, body) in files {
            let on_disk = std::fs::read_to_string(dir.join(format!("lib.db.{name}.json"))).unwrap();
            assert_eq!(on_disk, body, "{name}.json is untouched");
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn import_with_no_files_still_records_that_it_ran() {
        let dir = temp_dir("none");
        let path = dir.join("lib.db");
        let conn = crate::db::try_open_db_at(&path).unwrap();
        assert_eq!(import_legacy_json(&conn, &path).unwrap(), Some(ImportReport::default()));
        assert_eq!(import_legacy_json(&conn, &path).unwrap(), None);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
