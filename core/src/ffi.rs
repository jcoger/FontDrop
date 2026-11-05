//! The Swift surface (feature `uniffi`). One object, `Library`, wraps an open
//! library DB. Everything crossing the boundary is a plain record, and every
//! failure is a `CoreError`, never a panic.
//!
//! Threading: `Library` holds one connection behind a mutex for reads and
//! edits. `refresh_library` opens its own connection (WAL mode), so Swift can
//! call it from a background task while the UI keeps reading.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use rusqlite::Connection;

use crate::{db, pairing, userdata};

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    /// SQLite or schema failure (message from the database).
    #[error("database error: {0}")]
    Db(String),
    /// No font with this id.
    #[error("font {0} not found")]
    NotFound(String),
    /// A caller mistake, e.g. an unknown job name.
    #[error("invalid input: {0}")]
    Invalid(String),
}

impl From<rusqlite::Error> for CoreError {
    fn from(e: rusqlite::Error) -> Self {
        CoreError::Db(e.to_string())
    }
}

/// Engine functions report `String` errors; map a "not found" to its own case.
fn from_msg(msg: String) -> CoreError {
    if msg.starts_with("unknown job") {
        CoreError::Invalid(msg)
    } else {
        CoreError::Db(msg)
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
    /// Any file in the family is a trial / test / demo build.
    pub is_trial: bool,
    /// Foundry or licence page read from the font file (for "get the licence").
    pub foundry_url: Option<String>,
    /// OS/2 vendor code, e.g. a foundry's four-letter tag.
    pub vendor: Option<String>,
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

/// One entry of the flat ranked list (`Library::font_candidates`). Best first;
/// `rank` is the 0-based position. One per family.
#[derive(Debug, Clone, uniffi::Record)]
pub struct PairCandidate {
    pub font_id: String,
    pub family: String,
    pub file_path: String,
    pub pair_type: String,
    pub evidence: Vec<Evidence>,
    pub rank: u32,
}

/// What the designer's chosen Display + Reading pairs have in common.
#[derive(Debug, Clone, uniffi::Record)]
pub struct HouseStyle {
    pub picks: u32,
    pub same_foundry: u32,
    pub crossed_hands: u32,
    pub serif_with_sans: u32,
    /// Plain sentences; empty means "stay quiet" (fewer than 3 picks).
    pub statements: Vec<String>,
}

/// The four jobs a face can be chosen for: display, reading, ui, mono.
#[uniffi::export]
pub fn jobs() -> Vec<String> {
    userdata::JOBS.iter().map(|j| j.to_string()).collect()
}

/// An open FontDrop library. Opening runs schema migrations, so any DB file
/// (including one written by an older build) is brought up to date first.
#[derive(uniffi::Object)]
pub struct Library {
    db_path: PathBuf,
    conn: Mutex<Connection>,
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
    url: Option<String>,
    vendor: Option<String>,
}

#[uniffi::export]
impl Library {
    /// Open (creating if missing) the library DB file at `path`.
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Arc<Self>, CoreError> {
        let db_path = PathBuf::from(path);
        let conn = db::try_open_db_at(&db_path)?;
        Ok(Arc::new(Library { db_path, conn: Mutex::new(conn) }))
    }

    /// Scan the disk, read name tables, classify, measure, enrich. Opens its
    /// own connection; safe to call from a background task while the UI reads.
    /// Returns the number of font files in the library afterwards. Re-read
    /// `list_families` when it returns.
    pub fn refresh_library(&self) -> Result<u32, CoreError> {
        db::refresh_library(&self.db_path).map_err(CoreError::Db)
    }

    /// One row per family, sorted by name (case-insensitive). The family is
    /// the name the font file declares about itself (see `names::read_family_name`).
    pub fn list_families(&self) -> Result<Vec<FamilySummary>, CoreError> {
        let conn = self.lock()?;
        let mut stmt = conn.prepare(
            "SELECT font_id, font_family, file_path, file_name, style, weight, skeleton,
                    flesh_serif, COALESCE(is_trial, 0), foundry_url, vendor_id
             FROM fonts",
        )?;
        let mut best: HashMap<String, Best> = HashMap::new();
        // Styles counted once even when a library holds both .otf and .ttf
        // copies of the same style (common): keyed by file stem.
        let mut styles: HashMap<String, HashSet<String>> = HashMap::new();
        let mut trial: HashSet<String> = HashSet::new();
        // First non-empty value seen in any file, as a fallback for the family.
        let mut any_url: HashMap<String, String> = HashMap::new();
        let mut any_vendor: HashMap<String, String> = HashMap::new();
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
                r.get::<_, i64>(8)?,
                r.get::<_, Option<String>>(9)?,
                r.get::<_, Option<String>>(10)?,
            ))
        })?;
        for row in rows {
            let (id, family, path, file_name, style, weight, skeleton, serif, is_trial, url, vendor) = row?;
            styles.entry(family.clone()).or_default().insert(file_stem(&file_name));
            if is_trial != 0 {
                trial.insert(family.clone());
            }
            if let Some(u) = url.as_ref().filter(|u| !u.is_empty()) {
                any_url.entry(family.clone()).or_insert_with(|| u.clone());
            }
            if let Some(v) = vendor.as_ref().filter(|v| !v.is_empty()) {
                any_vendor.entry(family.clone()).or_insert_with(|| v.clone());
            }
            let dist = (weight - 400).abs() + if is_slanted(&file_name, &style) { 1000 } else { 0 };
            if best.get(&family).map_or(true, |b| dist < b.dist) {
                best.insert(family, Best { id, path, dist, skeleton, serif: serif != 0, url, vendor });
            }
        }
        let mut out: Vec<FamilySummary> = best
            .into_iter()
            .map(|(name, b)| FamilySummary {
                style_count: styles.get(&name).map_or(1, |s| s.len() as u32),
                is_trial: trial.contains(&name),
                foundry_url: b.url.filter(|u| !u.is_empty()).or_else(|| any_url.remove(&name)),
                vendor: b.vendor.filter(|v| !v.is_empty()).or_else(|| any_vendor.remove(&name)),
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

    /// Every font file, sorted by family then weight (flat list).
    pub fn list_fonts(&self) -> Result<Vec<FontFile>, CoreError> {
        let conn = self.lock()?;
        // .otf first so it wins the de-duplication below
        let mut stmt = conn.prepare(
            "SELECT font_id, font_family, name, file_path, weight FROM fonts
             ORDER BY CASE WHEN lower(file_name) LIKE '%.otf' THEN 0 ELSE 1 END",
        )?;
        let all: Vec<FontFile> = stmt
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
        // One entry per style: drop a .ttf when the same style exists as .otf.
        let mut seen: HashSet<(String, String)> = HashSet::new();
        let mut out: Vec<FontFile> = all
            .into_iter()
            .filter(|f| {
                let file = f.file_path.rsplit('/').next().unwrap_or(&f.file_path);
                seen.insert((f.family.clone(), file_stem(file)))
            })
            .collect();
        out.sort_by(|a, b| {
            a.family.to_lowercase().cmp(&b.family.to_lowercase()).then(a.weight.cmp(&b.weight))
        });
        Ok(out)
    }

    /// Matches for `font_id`, in buckets, each with its evidence. `job` is
    /// "reading" to drop families unfit for body text. Same result as the
    /// Tauri command `get_font_pairs`.
    pub fn font_pairs(
        &self,
        font_id: String,
        excluded_ids: Vec<String>,
        job: Option<String>,
    ) -> Result<Vec<PairBucket>, CoreError> {
        let conn = self.lock()?;
        let buckets = pairing::font_pairs(&conn, &font_id, excluded_ids, job.as_deref()).map_err(|m| {
            if m.ends_with("not found") { CoreError::NotFound(font_id.clone()) } else { CoreError::Db(m) }
        })?;

        let mut paths: HashMap<String, (String, String)> = HashMap::new();
        let mut stmt = conn.prepare("SELECT font_id, file_path, font_family FROM fonts")?;
        for r in stmt.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?))
        })? {
            let (id, p, fam) = r?;
            paths.insert(id, (p, fam));
        }

        Ok(buckets
            .into_iter()
            .map(|b| PairBucket {
                label: b.label,
                description: b.description,
                pairs: b
                    .pairs
                    .into_iter()
                    .map(|p| {
                        let (file_path, family) = paths.get(&p.font_id).cloned().unwrap_or_default();
                        PairMatch {
                            family,
                            file_path,
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
                        }
                    })
                    .collect(),
            })
            .collect())
    }

    /// A flat ranked list of partners for `font_id`, one per family, best first,
    /// at most `limit`. Same exclusions as `font_pairs` (`job` "reading" drops
    /// families unfit for body text). Unlike the buckets there is no cap of 11,
    /// so the app can page through more ("Show more") and filter client-side.
    pub fn font_candidates(
        &self,
        font_id: String,
        excluded_ids: Vec<String>,
        job: Option<String>,
        limit: u32,
    ) -> Result<Vec<PairCandidate>, CoreError> {
        let conn = self.lock()?;
        let scored = pairing::font_candidates(&conn, &font_id, excluded_ids, job.as_deref(), limit as usize)
            .map_err(|m| {
                if m.ends_with("not found") { CoreError::NotFound(font_id.clone()) } else { CoreError::Db(m) }
            })?;
        let mut paths: HashMap<String, (String, String)> = HashMap::new();
        let mut stmt = conn.prepare("SELECT font_id, file_path, font_family FROM fonts")?;
        for r in stmt.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?))
        })? {
            let (id, p, fam) = r?;
            paths.insert(id, (p, fam));
        }
        Ok(scored
            .into_iter()
            .enumerate()
            .map(|(i, p)| {
                let (file_path, family) = paths.get(&p.font_id).cloned().unwrap_or_default();
                PairCandidate {
                    family,
                    file_path,
                    font_id: p.font_id,
                    pair_type: p.pair_type,
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
                    rank: i as u32,
                }
            })
            .collect())
    }

    // ── Brands ────────────────────────────────────────────────────────────────

    pub fn brands_list(&self) -> Result<Vec<userdata::Brand>, CoreError> {
        userdata::list_brands(&*self.lock()?).map_err(from_msg)
    }

    pub fn brand_create(&self, name: String) -> Result<userdata::Brand, CoreError> {
        userdata::create_brand(&*self.lock()?, &name).map_err(from_msg)
    }

    pub fn brand_update(&self, id: i64, name: String, logo_svg: Option<String>) -> Result<(), CoreError> {
        userdata::update_brand(&*self.lock()?, id, &name, logo_svg.as_deref()).map_err(from_msg)
    }

    pub fn brand_delete(&self, id: i64) -> Result<(), CoreError> {
        userdata::delete_brand(&*self.lock()?, id).map_err(from_msg)
    }

    // ── Shortlist, choices, house style ──────────────────────────────────────

    /// Family names on this brand's shortlist for `job`.
    pub fn shortlist_get(&self, brand: i64, job: String) -> Result<Vec<String>, CoreError> {
        userdata::shortlist(&*self.lock()?, brand, &job).map_err(from_msg)
    }

    /// Add (`on`) or remove a family from the shortlist for `job`.
    pub fn shortlist_set(&self, brand: i64, job: String, family: String, on: bool) -> Result<(), CoreError> {
        let conn = self.lock()?;
        if on {
            userdata::shortlist_add(&conn, brand, &job, &family)
        } else {
            userdata::shortlist_remove(&conn, brand, &job, &family)
        }
        .map_err(from_msg)
    }

    /// The one family chosen for this brand and job (replaces any earlier choice).
    pub fn choose(&self, brand: i64, job: String, family: String) -> Result<(), CoreError> {
        userdata::choose(&*self.lock()?, brand, &job, &family).map_err(from_msg)
    }

    /// Remove the choice for this brand and job (used by "Undo" after a first choice).
    pub fn choice_clear(&self, brand: i64, job: String) -> Result<(), CoreError> {
        userdata::clear_choice(&*self.lock()?, brand, &job).map_err(from_msg)
    }

    pub fn choices(&self, brand: i64) -> Result<Vec<userdata::Choice>, CoreError> {
        userdata::choices(&*self.lock()?, brand).map_err(from_msg)
    }

    pub fn house_style(&self) -> Result<HouseStyle, CoreError> {
        let h = userdata::house_style(&*self.lock()?).map_err(from_msg)?;
        Ok(HouseStyle {
            picks: h.picks as u32,
            same_foundry: h.same_foundry as u32,
            crossed_hands: h.crossed_hands as u32,
            serif_with_sans: h.serif_with_sans as u32,
            statements: h.statements,
        })
    }
}

impl Library {
    fn lock(&self) -> Result<std::sync::MutexGuard<'_, Connection>, CoreError> {
        self.conn.lock().map_err(|_| CoreError::Db("library lock poisoned".into()))
    }
}

/// File name without extension, lowercased: "PPRightSerif-SpatialFine.otf"
/// and ".ttf" are the same style.
fn file_stem(file_name: &str) -> String {
    let lower = file_name.to_lowercase();
    match lower.rfind('.') {
        Some(i) => lower[..i].to_string(),
        None => lower,
    }
}
