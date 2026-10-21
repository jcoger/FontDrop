//! FontDrop core, spike edition. Two calls cross the Swift boundary:
//! `list_families` and `font_pairs`. Both open the SQLite DB read-only.

mod pairing;

use rusqlite::{Connection, OpenFlags};
use std::collections::{HashMap, HashSet};

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("database error: {0}")]
    Db(String),
    #[error("font {0} not found")]
    NotFound(String),
}

impl From<rusqlite::Error> for CoreError {
    fn from(e: rusqlite::Error) -> Self {
        CoreError::Db(e.to_string())
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FamilySummary {
    pub name: String,
    /// File of the upright face nearest weight 400.
    pub file_path: String,
    pub font_id: String,
    pub style_count: u32,
    pub skeleton: String,
    pub serif: bool,
}

/// One font file row, for the flat "every font" list.
#[derive(Debug, Clone, uniffi::Record)]
pub struct FontFile {
    pub font_id: String,
    pub family: String,
    pub name: String,
    pub file_path: String,
    pub weight: u16,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Evidence {
    pub lens: String,
    pub detail: String,
    pub source: String,
    pub strength: String,
    pub effect: i8,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PairMatch {
    pub font_id: String,
    pub family: String,
    pub file_path: String,
    pub score: u8,
    pub pair_type: String,
    pub reason: String,
    pub evidence: Vec<Evidence>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PairBucket {
    pub label: String,
    pub description: String,
    pub pairs: Vec<PairMatch>,
}

fn open_ro(db_path: &str) -> Result<Connection, CoreError> {
    Ok(Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?)
}

fn is_slanted(file_name: &str, style: &str) -> bool {
    let l = file_name.to_lowercase();
    style == "italic" || l.contains("italic") || l.contains("oblique") || l.contains("kursiv")
}

struct Best {
    id: String,
    path: String,
    dist: i64,
    skeleton: String,
    serif: bool,
}

/// One row per family, sorted by name (case-insensitive).
#[uniffi::export]
pub fn list_families(db_path: String) -> Result<Vec<FamilySummary>, CoreError> {
    let conn = open_ro(&db_path)?;
    let mut stmt = conn.prepare(
        "SELECT font_id, font_family, file_path, file_name, style, weight, skeleton, flesh_serif FROM fonts",
    )?;
    let mut best: HashMap<String, Best> = HashMap::new();
    let mut counts: HashMap<String, u32> = HashMap::new();
    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, String>(4)?,
            r.get::<_, i64>(5)?,
            r.get::<_, String>(6)?,
            r.get::<_, i64>(7)?,
        ))
    })?;
    for row in rows {
        let (id, family, path, file_name, style, weight, skeleton, serif) = row?;
        *counts.entry(family.clone()).or_default() += 1;
        let dist = (weight - 400).abs() + if is_slanted(&file_name, &style) { 1000 } else { 0 };
        let better = best.get(&family).map_or(true, |b| dist < b.dist);
        if better {
            best.insert(family, Best { id, path, dist, skeleton, serif: serif != 0 });
        }
    }
    let mut out: Vec<FamilySummary> = best
        .into_iter()
        .map(|(name, b)| FamilySummary {
            style_count: counts[&name],
            name,
            file_path: b.path,
            font_id: b.id,
            skeleton: b.skeleton,
            serif: b.serif,
        })
        .collect();
    out.sort_by_key(|f| f.name.to_lowercase());
    Ok(out)
}

/// Every font file in the DB, sorted by family then weight. Spike helper for the flat-list test.
#[uniffi::export]
pub fn list_fonts(db_path: String) -> Result<Vec<FontFile>, CoreError> {
    let conn = open_ro(&db_path)?;
    let mut stmt =
        conn.prepare("SELECT font_id, font_family, name, file_path, weight FROM fonts")?;
    let mut out: Vec<FontFile> = stmt
        .query_map([], |r| {
            Ok(FontFile {
                font_id: r.get(0)?,
                family: r.get(1)?,
                name: r.get(2)?,
                file_path: r.get(3)?,
                weight: r.get(4)?,
            })
        })?
        .collect::<Result<_, _>>()?;
    out.sort_by(|a, b| {
        a.family.to_lowercase().cmp(&b.family.to_lowercase()).then(a.weight.cmp(&b.weight))
    });
    Ok(out)
}

/// Same behaviour as the Tauri command `get_font_pairs`.
#[uniffi::export]
pub fn font_pairs(
    db_path: String,
    font_id: String,
    excluded_ids: Vec<String>,
    job: Option<String>,
) -> Result<Vec<PairBucket>, CoreError> {
    let conn = open_ro(&db_path)?;
    let all = pairing::load_all_fonts(&conn).map_err(CoreError::Db)?;
    let primary = all
        .iter()
        .find(|f| f.font_id == font_id)
        .ok_or_else(|| CoreError::NotFound(font_id.clone()))?;
    let mut excluded: HashSet<String> = excluded_ids.into_iter().collect();
    if job.as_deref() == Some("reading") {
        excluded.extend(pairing::unfit_for_reading(&all));
    }
    let buckets = pairing::bucket_pairs(primary, &all, &excluded);

    let mut paths: HashMap<String, String> = HashMap::new();
    let mut stmt = conn.prepare("SELECT font_id, file_path FROM fonts")?;
    for r in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (id, p) = r?;
        paths.insert(id, p);
    }
    let family_of: HashMap<&str, &str> =
        all.iter().map(|f| (f.font_id.as_str(), f.font_family.as_str())).collect();

    Ok(buckets
        .into_iter()
        .map(|b| PairBucket {
            label: b.label,
            description: b.description,
            pairs: b
                .pairs
                .into_iter()
                .map(|p| PairMatch {
                    family: family_of.get(p.font_id.as_str()).copied().unwrap_or("").to_string(),
                    file_path: paths.get(&p.font_id).cloned().unwrap_or_default(),
                    font_id: p.font_id,
                    score: p.score,
                    pair_type: p.pair_type,
                    reason: p.reason,
                    evidence: p
                        .evidence
                        .into_iter()
                        .map(|e| Evidence {
                            lens: e.lens,
                            detail: e.detail,
                            source: e.source,
                            strength: e.strength,
                            effect: e.effect,
                        })
                        .collect(),
                })
                .collect(),
        })
        .collect())
}
