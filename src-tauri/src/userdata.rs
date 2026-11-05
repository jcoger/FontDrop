//! The designer's own data: brands, a shortlist per job, and the faces they
//! chose. Lives in the same SQLite DB as the font library so every copy of the
//! app (Tauri today, SwiftUI next) sees the same brands. Browser storage was
//! per-origin and lost data between app copies.
//!
//! "Like my picks" (docs/ideas/pairing-experience.md) reads patterns from the
//! chosen pairs. It only speaks after 3 picks and always says what it learned.

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;

/// Jobs a face can be chosen for (BRO ch.3 lists six; these are the four the
/// app surfaces today).
pub const JOBS: &[&str] = &["display", "reading", "ui", "mono"];

// Tables: brands, shortlist, choices. Created by db::MIGRATIONS (append-only).

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Brand {
    pub id: i64,
    pub name: String,
    pub logo_svg: Option<String>,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Choice {
    pub job: String,
    pub font_family: String,
}

fn check_job(job: &str) -> Result<(), String> {
    if JOBS.contains(&job) { Ok(()) } else { Err(format!("unknown job '{job}'")) }
}

// ── Brands ────────────────────────────────────────────────────────────────────

pub fn create_brand(conn: &Connection, name: &str) -> Result<Brand, String> {
    let name = name.trim();
    if name.is_empty() {
        return Err("brand name is empty".into());
    }
    conn.execute("INSERT INTO brands (name) VALUES (?1)", params![name]).map_err(|e| e.to_string())?;
    Ok(Brand { id: conn.last_insert_rowid(), name: name.into(), logo_svg: None })
}

pub fn list_brands(conn: &Connection) -> Result<Vec<Brand>, String> {
    let mut st = conn.prepare("SELECT id, name, logo_svg FROM brands ORDER BY id").map_err(|e| e.to_string())?;
    let rows = st
        .query_map([], |r| Ok(Brand { id: r.get(0)?, name: r.get(1)?, logo_svg: r.get(2)? }))
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

pub fn update_brand(conn: &Connection, id: i64, name: &str, logo_svg: Option<&str>) -> Result<(), String> {
    conn.execute("UPDATE brands SET name = ?1, logo_svg = ?2 WHERE id = ?3", params![name.trim(), logo_svg, id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_brand(conn: &Connection, id: i64) -> Result<(), String> {
    conn.execute("DELETE FROM shortlist WHERE brand_id = ?1", params![id]).map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM choices WHERE brand_id = ?1", params![id]).map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM brands WHERE id = ?1", params![id]).map_err(|e| e.to_string())?;
    Ok(())
}

// ── Shortlist (one per job, per brand) ────────────────────────────────────────

pub fn shortlist_add(conn: &Connection, brand: i64, job: &str, family: &str) -> Result<(), String> {
    check_job(job)?;
    conn.execute(
        "INSERT OR IGNORE INTO shortlist (brand_id, job, font_family) VALUES (?1, ?2, ?3)",
        params![brand, job, family],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn shortlist_remove(conn: &Connection, brand: i64, job: &str, family: &str) -> Result<(), String> {
    conn.execute(
        "DELETE FROM shortlist WHERE brand_id = ?1 AND job = ?2 AND font_family = ?3",
        params![brand, job, family],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn shortlist(conn: &Connection, brand: i64, job: &str) -> Result<Vec<String>, String> {
    let mut st = conn
        .prepare("SELECT font_family FROM shortlist WHERE brand_id = ?1 AND job = ?2 ORDER BY added_at, font_family")
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map(params![brand, job], |r| r.get(0))
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

// ── Choices (the designer pressed "Use for <job>") ───────────────────────────

pub fn choose(conn: &Connection, brand: i64, job: &str, family: &str) -> Result<(), String> {
    check_job(job)?;
    conn.execute(
        "INSERT INTO choices (brand_id, job, font_family) VALUES (?1, ?2, ?3)
         ON CONFLICT(brand_id, job) DO UPDATE SET font_family = excluded.font_family, chosen_at = datetime('now')",
        params![brand, job, family],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn choices(conn: &Connection, brand: i64) -> Result<Vec<Choice>, String> {
    let mut st = conn
        .prepare("SELECT job, font_family FROM choices WHERE brand_id = ?1 ORDER BY job")
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map(params![brand], |r| Ok(Choice { job: r.get(0)?, font_family: r.get(1)? }))
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

// ── "Like my picks" ───────────────────────────────────────────────────────────

/// What the designer's chosen Display + Reading pairs have in common.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct HouseStyle {
    /// Brands with both a Display and a Reading face chosen.
    pub picks: usize,
    pub same_foundry: usize,
    pub crossed_hands: usize,
    pub serif_with_sans: usize,
    /// Plain sentences, only when picks >= MIN_PICKS. Empty means "stay quiet".
    pub statements: Vec<String>,
}

pub const MIN_PICKS: usize = 3;

/// Traits of a family's upright face nearest weight 400.
fn traits(conn: &Connection, family: &str) -> Option<(Option<String>, String, i32)> {
    conn.query_row(
        "SELECT vendor_id, skeleton, flesh_serif FROM fonts
         WHERE font_family = ?1 AND lower(file_name) NOT LIKE '%italic%'
         ORDER BY abs(weight - 400) LIMIT 1",
        params![family],
        |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, String>(1)?, r.get::<_, i32>(2)?)),
    )
    .optional()
    .ok()
    .flatten()
}

pub fn house_style(conn: &Connection) -> Result<HouseStyle, String> {
    let mut st = conn
        .prepare(
            "SELECT d.font_family, r.font_family FROM choices d
             JOIN choices r ON r.brand_id = d.brand_id AND r.job = 'reading'
             WHERE d.job = 'display'",
        )
        .map_err(|e| e.to_string())?;
    let pairs: Vec<(String, String)> = st
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    let camp = |sk: &str| if sk == "dynamic" { "pen-made" } else { "constructed" };
    let (mut same_foundry, mut crossed, mut serif_sans) = (0, 0, 0);
    for (d, r) in &pairs {
        let (Some(a), Some(b)) = (traits(conn, d), traits(conn, r)) else { continue };
        if a.0.as_deref().is_some_and(|v| !v.is_empty()) && a.0 == b.0 {
            same_foundry += 1;
        }
        if a.1 != "unknown" && b.1 != "unknown" && camp(&a.1) != camp(&b.1) {
            crossed += 1;
        }
        if a.2 != b.2 {
            serif_sans += 1;
        }
    }

    let n = pairs.len();
    let mut statements = Vec::new();
    if n >= MIN_PICKS {
        let say = |count: usize, what: &str| format!("{what} in {count} of {n} picks");
        // Only patterns that hold for most picks are worth a sort.
        if same_foundry * 2 > n { statements.push(say(same_foundry, "Same foundry")); }
        if crossed * 2 > n { statements.push(say(crossed, "Crossed hands (pen-made with constructed)")); }
        if serif_sans * 2 > n { statements.push(say(serif_sans, "Serif with sans")); }
    }
    Ok(HouseStyle { picks: n, same_foundry, crossed_hands: crossed, serif_with_sans: serif_sans, statements })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(crate::db::CREATE_TABLE).unwrap();
        crate::db::run_migrations(&conn);
        conn
    }

    fn font(conn: &Connection, id: &str, family: &str, vendor: &str, skeleton: &str, serif: i32) {
        conn.execute(
            "INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, weight, category,
             style, width, skeleton, flesh_contrast, flesh_serif, classification_source, user_override,
             created_at, updated_at, vendor_id)
             VALUES (?1, ?2, ?1, ?1, 'user', ?2, 400, 'other', 'normal', 'normal', ?3, 'linear', ?4, 'file', 0, '', '', ?5)",
            params![id, family, skeleton, serif, vendor],
        )
        .unwrap();
    }

    #[test]
    fn brands_round_trip() {
        let c = db();
        let b = create_brand(&c, "  Acme ").unwrap();
        assert_eq!(b.name, "Acme");
        update_brand(&c, b.id, "Acme Co", Some("<svg/>")).unwrap();
        assert_eq!(list_brands(&c).unwrap()[0].logo_svg.as_deref(), Some("<svg/>"));
        assert!(create_brand(&c, " ").is_err());
    }

    #[test]
    fn shortlists_are_separate_per_job() {
        let c = db();
        let b = create_brand(&c, "A").unwrap().id;
        shortlist_add(&c, b, "reading", "PP Mori").unwrap();
        shortlist_add(&c, b, "reading", "PP Mori").unwrap(); // idempotent
        shortlist_add(&c, b, "mono", "PP Supply Mono").unwrap();
        assert_eq!(shortlist(&c, b, "reading").unwrap(), vec!["PP Mori"]);
        assert_eq!(shortlist(&c, b, "mono").unwrap(), vec!["PP Supply Mono"]);
        assert!(shortlist_add(&c, b, "headline", "X").is_err());
        shortlist_remove(&c, b, "reading", "PP Mori").unwrap();
        assert!(shortlist(&c, b, "reading").unwrap().is_empty());
    }

    #[test]
    fn choosing_again_replaces_the_job() {
        let c = db();
        let b = create_brand(&c, "A").unwrap().id;
        choose(&c, b, "reading", "Satoshi").unwrap();
        choose(&c, b, "reading", "Timeless Sans").unwrap();
        assert_eq!(choices(&c, b).unwrap(), vec![Choice { job: "reading".into(), font_family: "Timeless Sans".into() }]);
    }

    #[test]
    fn house_style_stays_quiet_until_three_picks_then_names_the_pattern() {
        let c = db();
        font(&c, "s1", "Serif One", "PP", "dynamic", 1);
        font(&c, "a1", "Sans One", "PP", "rational", 0);
        font(&c, "s2", "Serif Two", "AS", "dynamic", 1);
        font(&c, "a2", "Sans Two", "AS", "rational", 0);
        font(&c, "s3", "Serif Three", "TMLS", "dynamic", 1);
        font(&c, "a3", "Sans Three", "OT", "geometric", 0);
        for (i, (d, r)) in [("Serif One", "Sans One"), ("Serif Two", "Sans Two")].iter().enumerate() {
            let b = create_brand(&c, &format!("B{i}")).unwrap().id;
            choose(&c, b, "display", d).unwrap();
            choose(&c, b, "reading", r).unwrap();
        }
        let h = house_style(&c).unwrap();
        assert_eq!(h.picks, 2);
        assert!(h.statements.is_empty(), "quiet below 3 picks");

        let b = create_brand(&c, "B2").unwrap().id;
        choose(&c, b, "display", "Serif Three").unwrap();
        choose(&c, b, "reading", "Sans Three").unwrap();
        let h = house_style(&c).unwrap();
        assert_eq!((h.picks, h.same_foundry, h.crossed_hands, h.serif_with_sans), (3, 2, 3, 3));
        assert!(h.statements.contains(&"Same foundry in 2 of 3 picks".to_string()));
        assert!(h.statements.iter().any(|s| s.starts_with("Crossed hands")));
    }
}

// ── App commands (the same surface the SwiftUI app will call through the core) ─

mod commands {
    use super::*;
    use crate::db::DbState;

    fn with<T>(state: &tauri::State<'_, DbState>, f: impl FnOnce(&Connection) -> Result<T, String>) -> Result<T, String> {
        let conn = state.0.lock().map_err(|e| e.to_string())?;
        f(&conn)
    }

    #[tauri::command]
    pub fn brands_list(state: tauri::State<'_, DbState>) -> Result<Vec<Brand>, String> {
        with(&state, list_brands)
    }
    #[tauri::command]
    pub fn brand_create(state: tauri::State<'_, DbState>, name: String) -> Result<Brand, String> {
        with(&state, |c| create_brand(c, &name))
    }
    #[tauri::command]
    pub fn brand_update(state: tauri::State<'_, DbState>, id: i64, name: String, logo_svg: Option<String>) -> Result<(), String> {
        with(&state, |c| update_brand(c, id, &name, logo_svg.as_deref()))
    }
    #[tauri::command]
    pub fn brand_delete(state: tauri::State<'_, DbState>, id: i64) -> Result<(), String> {
        with(&state, |c| delete_brand(c, id))
    }
    #[tauri::command]
    pub fn shortlist_get(state: tauri::State<'_, DbState>, brand: i64, job: String) -> Result<Vec<String>, String> {
        with(&state, |c| shortlist(c, brand, &job))
    }
    #[tauri::command]
    pub fn shortlist_set(state: tauri::State<'_, DbState>, brand: i64, job: String, family: String, on: bool) -> Result<(), String> {
        with(&state, |c| if on { shortlist_add(c, brand, &job, &family) } else { shortlist_remove(c, brand, &job, &family) })
    }
    #[tauri::command]
    pub fn choice_set(state: tauri::State<'_, DbState>, brand: i64, job: String, family: String) -> Result<(), String> {
        with(&state, |c| choose(c, brand, &job, &family))
    }
    #[tauri::command]
    pub fn choices_get(state: tauri::State<'_, DbState>, brand: i64) -> Result<Vec<Choice>, String> {
        with(&state, |c| choices(c, brand))
    }
    #[tauri::command]
    pub fn house_style_get(state: tauri::State<'_, DbState>) -> Result<HouseStyle, String> {
        with(&state, house_style)
    }
}
pub use commands::*;
