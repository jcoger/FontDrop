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

use crate::finder::{self, FamilyQuery, FamilyResults};
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
    /// The font's own style name from its name table ("Grand Heavy", "Text Book"). Empty when not read yet.
    pub style_name: String,
}

/// How far the startup scan has got. `fraction` runs 0 to 1. `files` and `families` are what the scan found on disk.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ScanProgress {
    pub fraction: f64,
    pub files: u32,
    pub families: u32,
}

/// Read while `Library::refresh_library` runs on another thread. Safe at any time; zeros when no scan has run.
#[uniffi::export]
pub fn scan_progress() -> ScanProgress {
    let s = crate::progress::snapshot();
    ScanProgress { fraction: s.fraction(), files: s.files, families: s.families }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ReadingFamily {
    pub font_id: String,
    pub family: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ReadingFamilies {
    pub families: Vec<ReadingFamily>,
    pub not_for_long_text: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Evidence {
    pub lens: String,
    pub detail: String,
    pub source: String,
    pub strength: String,
    pub effect: i8,
}

/// A style of a family to set body text in ("Regular", "Text"). Only set for a `same_family` pair.
#[derive(Debug, Clone, uniffi::Record)]
pub struct BodyStyle {
    pub font_id: String,
    pub file_path: String,
    pub label: String,
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
    /// A dependable text face (workhorse.rs). Only set for the Reading job.
    pub workhorse: bool,
    /// For `same_family`: the style of the Display family to use for body text.
    pub suggested_body_style: Option<BodyStyle>,
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

/// One axis value of a named instance.
#[derive(Debug, Clone, uniffi::Record)]
pub struct AxisSetting {
    pub tag: String,
    pub value: f64,
}

/// A named instance of a variable font ("Light", "Black") and the axis values it sets.
#[derive(Debug, Clone, uniffi::Record)]
pub struct FontInstance {
    pub name: String,
    pub axes: Vec<AxisSetting>,
}

/// The named instances in a variable font file's `fvar` table, in the font's own order. Empty for a static font.
#[uniffi::export]
pub fn font_instances(path: String) -> Vec<FontInstance> {
    crate::names::named_instances(std::path::Path::new(&path))
        .into_iter()
        .map(|i| FontInstance { name: i.name, axes: i.axes.into_iter().map(|(tag, value)| AxisSetting { tag, value }).collect() })
        .collect()
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

    /// `refresh_library` over the given folders only (source "user"), with no network step.
    /// A test seam: a test scans a fixture folder instead of the real font folders.
    pub fn refresh_library_folders(&self, folders: Vec<String>) -> Result<u32, CoreError> {
        let dirs: Vec<PathBuf> = folders.into_iter().map(PathBuf::from).collect();
        db::refresh_library_in(&self.db_path, Some(&dirs)).map_err(CoreError::Db)
    }
    /// One row per family, sorted by name (case-insensitive). The family is
    /// the name the font file declares about itself (see `names::read_family_name`).
    pub fn list_families(&self) -> Result<Vec<FamilySummary>, CoreError> {
        let conn = self.lock()?;
        Ok(finder::load_families(&conn)?
            .into_iter()
            .map(|f| FamilySummary {
                name: f.name,
                file_path: f.file_path,
                font_id: f.font_id,
                style_count: f.style_count,
                skeleton: f.skeleton,
                serif: f.serif,
                is_trial: f.is_trial,
                foundry_url: f.foundry_url,
                vendor: f.vendor,
            })
            .collect())
    }

    /// Find families: text, sources, kinds, traits, Saved, Hidden. One answer with the
    /// families (Yours first, then by name) and the count for every chip, each computed
    /// with the other filters applied. Hidden families (junk list plus the user's hides)
    /// stay out unless `include_hidden` is set. See `finder.rs`.
    pub fn find_families(&self, query: FamilyQuery) -> Result<FamilyResults, CoreError> {
        finder::find_families(&*self.lock()?, &query).map_err(from_msg)
    }

    /// Hide a family from every list and from pairing candidates.
    pub fn hide_family(&self, family: String) -> Result<(), CoreError> {
        finder::hide_family(&*self.lock()?, &family).map_err(from_msg)
    }

    /// Show a hidden family again (also for families on the built-in junk list).
    pub fn unhide_family(&self, family: String) -> Result<(), CoreError> {
        finder::unhide_family(&*self.lock()?, &family).map_err(from_msg)
    }

    /// Star (`on`) or unstar a family. Global, not per brand.
    pub fn set_favorite(&self, family: String, on: bool) -> Result<(), CoreError> {
        finder::set_favorite(&*self.lock()?, &family, on).map_err(from_msg)
    }

    /// How many families the Reading rule removes from the candidates for `font_id`
    /// ("42 not made for long text"). Counts families, not capped by the page size.
    pub fn reading_hidden_count(&self, font_id: String, excluded_ids: Vec<String>, excluded_families: Vec<String>) -> Result<u32, CoreError> {
        let conn = self.lock()?;
        pairing::unfit_family_count(&conn, &font_id, excluded_ids, excluded_families).map_err(|m| {
            if m.ends_with("not found") { CoreError::NotFound(font_id.clone()) } else { CoreError::Db(m) }
        })
    }

    /// Families for Reading when no Display face is chosen yet: one per family, with the same long-text
    /// rule as pairs (`only_fit`) and the count of families that rule removes. Hidden families stay out.
    pub fn reading_families(&self, excluded_ids: Vec<String>, excluded_families: Vec<String>, only_fit: bool) -> Result<ReadingFamilies, CoreError> {
        let conn = self.lock()?;
        let (list, unfit) = pairing::reading_families(&conn, excluded_ids, excluded_families, only_fit).map_err(CoreError::Db)?;
        Ok(ReadingFamilies {
            families: list.into_iter().map(|(font_id, family)| ReadingFamily { font_id, family }).collect(),
            not_for_long_text: unfit,
        })
    }

    /// Every font file, sorted by family then weight (flat list).
    pub fn list_fonts(&self) -> Result<Vec<FontFile>, CoreError> {
        let conn = self.lock()?;
        // .otf first so it wins the de-duplication below
        let mut stmt = conn.prepare(
            "SELECT font_id, font_family, name, file_path, weight, COALESCE(style_name, '') FROM fonts
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
                    style_name: r.get(5)?,
                })
            })?
            .collect::<Result<_, _>>()?;
        // One entry per style: drop a .ttf when the same style exists as .otf.
        let mut seen: HashSet<(String, String)> = HashSet::new();
        let mut out: Vec<FontFile> = all
            .into_iter()
            .filter(|f| {
                let file = f.file_path.rsplit('/').next().unwrap_or(&f.file_path);
                seen.insert((f.family.clone(), finder::file_stem(file)))
            })
            .collect();
        out.sort_by(|a, b| {
            a.family.to_lowercase().cmp(&b.family.to_lowercase()).then(a.weight.cmp(&b.weight))
        });
        Ok(out)
    }

    /// `excluded_ids` and `excluded_families` stay out; a family name removes every file of that family.
    /// A flat ranked list of partners for `font_id`, one per family, best first,
    /// at most `limit`. Hidden fonts are always out (`job` "reading" drops
    /// families unfit for body text). There is no cap of 11 as in the Tauri buckets,
    /// so the app can page through more ("Show more") and filter client-side.
    pub fn font_candidates(
        &self,
        font_id: String,
        excluded_ids: Vec<String>,
        excluded_families: Vec<String>,
        job: Option<String>,
        character_first: bool,
        limit: u32,
    ) -> Result<Vec<PairCandidate>, CoreError> {
        let conn = self.lock()?;
        let (scored, horses) = if job.as_deref() == Some("reading") {
            // Reading: dependable text faces first (or last, with `character_first`), the engine's order within each group.
            pairing::reading_candidates(&conn, &font_id, excluded_ids, excluded_families, character_first, limit as usize)
        } else {
            pairing::font_candidates(&conn, &font_id, excluded_ids, excluded_families, job.as_deref(), limit as usize)
                .map(|s| (s, std::collections::HashSet::new()))
        }
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
                    workhorse: horses.contains(&p.font_id),
                    suggested_body_style: body_style(p.suggested_body_style, &paths),
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

/// The engine's body style with its file path filled in from the id.
fn body_style(b: Option<pairing::BodyStyle>, paths: &HashMap<String, (String, String)>) -> Option<BodyStyle> {
    b.map(|b| BodyStyle { file_path: paths.get(&b.font_id).map(|p| p.0.clone()).unwrap_or_default(), font_id: b.font_id, label: b.label })
}

impl Library {
    fn lock(&self) -> Result<std::sync::MutexGuard<'_, Connection>, CoreError> {
        self.conn.lock().map_err(|_| CoreError::Db("library lock poisoned".into()))
    }
}

