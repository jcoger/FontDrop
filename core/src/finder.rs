//! Finding fonts: one query over the families in the library, with counts for the filter chips.
//!
//! Source, kind and trait filters, text search, Saved and Hidden all live here so the
//! Mac app, the Tauri app and a future Claude connector filter the same way.
//! Design: docs/ideas/finding-fonts.md.
//!
//! Source mapping (`fonts.source` is set by the scan):
//! - `user` (~/Library/Fonts) and `library` (/Library/Fonts) are **Yours**.
//! - `system` (/System/Library/Fonts) is **System**.
//! - **Google** is not a folder: the installed family's name is in Google's public list
//!   (`google_list.rs`). A family can be Yours and Google at once.
//!   A family's sources are the union over its files.

use std::collections::{HashMap, HashSet};

use rusqlite::{params, Connection};

use crate::google_list::match_key;

// ── Types ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum Source {
    Yours,
    Google,
    System,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum Kind {
    Serif,
    Sans,
    Script,
    Display,
    Mono,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum Trait {
    Italic,
    Variable,
    Condensed,
    Wide,
    Trial,
}

pub const ALL_SOURCES: [Source; 3] = [Source::Yours, Source::Google, Source::System];
pub const ALL_KINDS: [Kind; 5] = [Kind::Serif, Kind::Sans, Kind::Script, Kind::Display, Kind::Mono];
pub const ALL_TRAITS: [Trait; 5] = [Trait::Italic, Trait::Variable, Trait::Condensed, Trait::Wide, Trait::Trial];

/// What to find. Empty lists mean "no filter". Sources OR together, kinds OR together,
/// traits AND together, and the groups AND with each other.
#[derive(Debug, Clone, Default)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct FamilyQuery {
    /// Every word must appear in the family name, foundry, vendor or designer.
    pub text: String,
    pub sources: Vec<Source>,
    pub kinds: Vec<Kind>,
    pub traits: Vec<Trait>,
    pub saved_only: bool,
    /// Hidden families (the junk list and the user's hides) stay out unless this is set.
    pub include_hidden: bool,
}

/// One family in a result.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct FamilyEntry {
    pub name: String,
    /// The representative file (upright, nearest weight 400).
    pub font_id: String,
    pub sources: Vec<Source>,
    pub kind: Kind,
    pub traits: Vec<Trait>,
    pub saved: bool,
    pub hidden: bool,
    /// Google popularity rank, 1 = most used. None when Google does not list the family.
    pub google_rank: Option<u32>,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct SourceCount {
    pub source: Source,
    pub count: u32,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct KindCount {
    pub kind: Kind,
    pub count: u32,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct TraitCount {
    pub tr: Trait,
    pub count: u32,
}

/// Chip counts. Each chip's count is computed with every *other* active filter applied.
///
/// - A source chip counts families with that source, ignoring which sources are selected
///   (sources OR together, so selecting Yours must not zero out the Google chip).
/// - A kind chip works the same way.
/// - A trait chip counts families that would remain if that trait were also required
///   (traits AND together), so an active trait shows the current total.
/// - `saved` counts Saved families that match everything except the Saved filter.
/// - `hidden` counts hidden families that match everything except the Hidden rule: what
///   "Show hidden" would add.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct FacetCounts {
    pub sources: Vec<SourceCount>,
    pub kinds: Vec<KindCount>,
    pub traits: Vec<TraitCount>,
    pub saved: u32,
    pub hidden: u32,
}

/// Families sorted with Yours first, then by name (case-insensitive).
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct FamilyResults {
    pub families: Vec<FamilyEntry>,
    pub counts: FacetCounts,
}

// ── Junk list ────────────────────────────────────────────────────────────────

// Ported from the Tauri app's `src/data/defaultExclusions.ts`: dingbats, symbol and
// emoji faces, system UI faces, and CJK families a brand designer never picks from.

pub const JUNK_FAMILIES: &[&str] = &[
    "Apple Symbols",
    "Apple Color Emoji",
    "Apple Braille",
    "Apple Chancery",
    "Zapf Dingbats",
    "Wingdings",
    "Wingdings 2",
    "Wingdings 3",
    "Webdings",
    "Bodoni Ornaments",
    "LastResort",
    "Keyboard",
    "Hiragino Kaku Gothic Pro",
    "Hiragino Kaku Gothic ProN",
    "Hiragino Kaku Gothic Std",
    "Hiragino Kaku Gothic StdN",
    "Hiragino Maru Gothic Pro",
    "Hiragino Maru Gothic ProN",
    "Hiragino Mincho Pro",
    "Hiragino Mincho ProN",
    "Hiragino Sans",
    "Hiragino Sans GB",
    "PingFang HK",
    "PingFang SC",
    "PingFang TC",
    "Songti SC",
    "Songti TC",
    "STSong",
    "STHeiti",
    "STFangsong",
    "STKaiti",
    "STXihei",
    "STXingkai",
    "STXinwei",
    "STZhongsong",
    "STCaiyun",
    "STHupo",
    "STLiti",
    "Noto Sans CJK JP",
    "Noto Sans CJK KR",
    "Noto Sans CJK SC",
    "Noto Sans CJK TC",
    "Noto Serif CJK JP",
    "Noto Serif CJK KR",
    "Noto Serif CJK SC",
    "Noto Serif CJK TC",
    "Apple LiGothic",
    "Apple LiSung",
    "LiHei Pro",
    "LiSong Pro",
    "BiauKai",
    "GB18030 Bitmap",
    "Courier",
    "Times",
    "Helvetica",
];

pub const JUNK_PREFIXES: &[&str] = &[
    ".",
    "Apple SD",
    "Aqua Kana",
    "GB18030",
];

/// Is this family on the built-in junk list (exact name, or a junk prefix)? Case-insensitive.
pub fn is_junk_family(name: &str) -> bool {
    let lower = name.to_lowercase();
    JUNK_FAMILIES.iter().any(|f| f.to_lowercase() == lower)
        || JUNK_PREFIXES.iter().any(|p| lower.starts_with(&p.to_lowercase()))
}

// ── Hide, unhide, save ───────────────────────────────────────────────────────

/// Hide a family. Overrides nothing else: the junk list stays as it is.
pub fn hide_family(conn: &Connection, family: &str) -> Result<(), String> {
    conn.execute(
        "INSERT INTO hidden (family, hidden) VALUES (?1, 1) ON CONFLICT(family) DO UPDATE SET hidden = 1",
        params![family],
    )
    .map(|_| ())
    .map_err(|e| e.to_string())
}

/// Show a family again. For a junk-list family this records "shown on purpose"; for any
/// other it removes the user's hide.
pub fn unhide_family(conn: &Connection, family: &str) -> Result<(), String> {
    let result = if is_junk_family(family) {
        conn.execute(
            "INSERT INTO hidden (family, hidden) VALUES (?1, 0) ON CONFLICT(family) DO UPDATE SET hidden = 0",
            params![family],
        )
    } else {
        conn.execute("DELETE FROM hidden WHERE family = ?1", params![family])
    };
    result.map(|_| ()).map_err(|e| e.to_string())
}

/// Star (`on`) or unstar a family. Global, separate from the per-brand shortlists.
pub fn set_favorite(conn: &Connection, family: &str, on: bool) -> Result<(), String> {
    let result = if on {
        conn.execute("INSERT OR IGNORE INTO favorites (family) VALUES (?1)", params![family])
    } else {
        conn.execute("DELETE FROM favorites WHERE family = ?1", params![family])
    };
    result.map(|_| ()).map_err(|e| e.to_string())
}

/// family (lowercased) -> 1 hidden by the user, 0 shown on purpose.
fn hidden_overrides(conn: &Connection) -> HashMap<String, bool> {
    let mut out = HashMap::new();
    if let Ok(mut st) = conn.prepare("SELECT family, hidden FROM hidden") {
        if let Ok(rows) = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))) {
            for (f, h) in rows.flatten() {
                out.insert(f.to_lowercase(), h != 0);
            }
        }
    }
    out
}

fn favorite_set(conn: &Connection) -> HashSet<String> {
    let mut out = HashSet::new();
    if let Ok(mut st) = conn.prepare("SELECT family FROM favorites") {
        if let Ok(rows) = st.query_map([], |r| r.get::<_, String>(0)) {
            out.extend(rows.flatten().map(|f| f.to_lowercase()));
        }
    }
    out
}

fn effective_hidden(name: &str, overrides: &HashMap<String, bool>) -> bool {
    match overrides.get(&name.to_lowercase()) {
        Some(&h) => h,
        None => is_junk_family(name),
    }
}

/// Font ids of every file in a hidden family (junk list or user hide). Pairing takes these
/// as exclusions so a hidden family never shows up as a match. Empty if the tables are missing.
pub fn hidden_font_ids(conn: &Connection) -> HashSet<String> {
    let overrides = hidden_overrides(conn);
    let mut out = HashSet::new();
    if let Ok(mut st) = conn.prepare("SELECT font_id, font_family FROM fonts") {
        if let Ok(rows) = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))) {
            for (id, fam) in rows.flatten() {
                if effective_hidden(&fam, &overrides) {
                    out.insert(id);
                }
            }
        }
    }
    out
}

// ── Loading families ─────────────────────────────────────────────────────────

/// Everything known about one family. `list_families` and `find_families` both build from this.
#[derive(Debug, Clone)]
pub struct FamilyAgg {
    pub name: String,
    pub file_path: String,
    pub font_id: String,
    pub style_count: u32,
    pub skeleton: String,
    pub serif: bool,
    pub is_trial: bool,
    pub foundry_url: Option<String>,
    pub vendor: Option<String>,
    pub entry: FamilyEntry,
    /// Lowercased family, foundry, vendor and designer text for search.
    haystack: String,
}

struct Best {
    id: String,
    path: String,
    dist: i64,
    skeleton: String,
    serif: bool,
    url: Option<String>,
    vendor: Option<String>,
    category: String,
}

#[derive(Default)]
struct Acc {
    best: Option<Best>,
    styles: HashSet<String>,
    sources: HashSet<Source>,
    traits: HashSet<Trait>,
    any_url: Option<String>,
    any_vendor: Option<String>,
    hay: HashSet<String>,
}

/// File name without extension, lowercased: ".otf" and ".ttf" copies are the same style.
fn file_stem(file_name: &str) -> String {
    let lower = file_name.to_lowercase();
    match lower.rfind('.') {
        Some(i) => lower[..i].to_string(),
        None => lower,
    }
}

fn is_slanted(file_name: &str, style: &str) -> bool {
    let l = file_name.to_lowercase();
    style == "italic" || l.contains("italic") || l.contains("oblique") || l.contains("kursiv")
}

fn name_tokens(name: &str) -> Vec<String> {
    name.to_lowercase().split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).map(String::from).collect()
}

/// One kind per family. When Google lists the family its category decides script, display
/// and mono (a designer-curated answer). Otherwise the file's category and name words do.
/// Serif against sans always comes from the outline detector (`serif`).
pub fn kind_of(name: &str, file_category: &str, google_category: Option<&str>, serif: bool) -> Kind {
    let by_outline = if serif { Kind::Serif } else { Kind::Sans };
    if let Some(g) = google_category {
        return match g {
            "Monospace" => Kind::Mono,
            "Handwriting" => Kind::Script,
            "Display" => Kind::Display,
            _ => by_outline,
        };
    }
    let words = name_tokens(name);
    let has = |keys: &[&str]| words.iter().any(|w| keys.contains(&w.as_str()));
    if file_category == "monospace" || has(&["mono", "monospace", "code", "console", "terminal"]) {
        Kind::Mono
    } else if file_category == "script"
        || has(&["script", "brush", "handwriting", "handwritten", "hand", "cursive", "calligraphy"])
    {
        Kind::Script
    } else if file_category == "decorative"
        || has(&["display", "ornaments", "ornament", "dingbats", "symbols", "symbol", "emoji", "stencil", "titling"])
    {
        Kind::Display
    } else {
        by_outline
    }
}

/// Every family in the library, one aggregate each, sorted by name (case-insensitive).
pub fn load_families(conn: &Connection) -> Result<Vec<FamilyAgg>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "SELECT font_id, font_family, file_path, file_name, style, weight, skeleton, flesh_serif,
                COALESCE(is_trial, 0), foundry_url, vendor_id, source, category,
                width, width_class, COALESCE(is_variable, 0), foundry, designer
         FROM fonts",
    )?;

    let mut accs: HashMap<String, Acc> = HashMap::new();
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
            r.get::<_, String>(11)?,
            r.get::<_, String>(12)?,
            r.get::<_, String>(13)?,
            r.get::<_, Option<String>>(14)?,
            r.get::<_, i64>(15)?,
            r.get::<_, Option<String>>(16)?,
            r.get::<_, Option<String>>(17)?,
        ))
    })?;
    for row in rows {
        let (id, family, path, file_name, style, weight, skeleton, serif, trial, url, vendor, source, category, width, width_class, variable, foundry, designer) = row?;
        let acc = accs.entry(family.clone()).or_default();
        acc.styles.insert(file_stem(&file_name));
        acc.sources.insert(match source.as_str() {
            "system" => Source::System,
            _ => Source::Yours, // user and library
        });
        if trial != 0 { acc.traits.insert(Trait::Trial); }
        if variable != 0 { acc.traits.insert(Trait::Variable); }
        let slanted = is_slanted(&file_name, &style);
        if slanted { acc.traits.insert(Trait::Italic); }
        if width == "condensed" || width_class.as_deref() == Some("condensed") { acc.traits.insert(Trait::Condensed); }
        if width == "extended" || width_class.as_deref() == Some("expanded") { acc.traits.insert(Trait::Wide); }
        if let Some(u) = url.as_ref().filter(|u| !u.is_empty()) {
            acc.any_url.get_or_insert_with(|| u.clone());
        }
        if let Some(v) = vendor.as_ref().filter(|v| !v.is_empty()) {
            acc.any_vendor.get_or_insert_with(|| v.clone());
        }
        for text in [foundry.as_deref(), designer.as_deref(), vendor.as_deref()].into_iter().flatten() {
            if !text.is_empty() { acc.hay.insert(text.to_lowercase()); }
        }
        let dist = (weight - 400).abs() + if slanted { 1000 } else { 0 };
        if acc.best.as_ref().map_or(true, |b| dist < b.dist) {
            acc.best = Some(Best { id, path, dist, skeleton, serif: serif != 0, url, vendor, category });
        }
    }

    // Google's list, if it was ever fetched.
    let mut google: HashMap<String, (Option<String>, Option<u32>)> = HashMap::new();
    if let Ok(mut st) = conn.prepare("SELECT norm, category, popularity FROM google_families") {
        if let Ok(it) = st.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, Option<u32>>(2)?))
        }) {
            for (n, c, p) in it.flatten() {
                google.insert(n, (c, p));
            }
        }
    }
    let google_keys: HashSet<String> = google.keys().cloned().collect();
    let overrides = hidden_overrides(conn);
    let favorites = favorite_set(conn);

    let mut out: Vec<FamilyAgg> = accs
        .into_iter()
        .filter_map(|(name, mut acc)| {
            let b = acc.best.take()?;
            let g = match_key(&name, &google_keys).and_then(|k| google.get(&k).cloned());
            let mut sources: Vec<Source> = ALL_SOURCES.iter().copied().filter(|s| acc.sources.contains(s)).collect();
            if g.is_some() {
                sources.push(Source::Google);
                sources.sort_by_key(|s| ALL_SOURCES.iter().position(|x| x == s));
            }
            let traits: Vec<Trait> = ALL_TRAITS.iter().copied().filter(|t| acc.traits.contains(t)).collect();
            let google_category = g.as_ref().and_then(|(c, _)| c.clone());
            let kind = kind_of(&name, &b.category, google_category.as_deref().or(g.as_ref().map(|_| "")), b.serif);
            let mut haystack = name.to_lowercase();
            for h in &acc.hay {
                haystack.push('\n');
                haystack.push_str(h);
            }
            let entry = FamilyEntry {
                name: name.clone(),
                font_id: b.id.clone(),
                sources,
                kind,
                traits,
                saved: favorites.contains(&name.to_lowercase()),
                hidden: effective_hidden(&name, &overrides),
                google_rank: g.as_ref().and_then(|(_, p)| *p),
            };
            Some(FamilyAgg {
                style_count: acc.styles.len().max(1) as u32,
                is_trial: acc.traits.contains(&Trait::Trial),
                foundry_url: b.url.filter(|u| !u.is_empty()).or(acc.any_url),
                vendor: b.vendor.filter(|v| !v.is_empty()).or(acc.any_vendor),
                name,
                file_path: b.path,
                font_id: b.id,
                skeleton: b.skeleton,
                serif: b.serif,
                entry,
                haystack,
            })
        })
        .collect();
    out.sort_by_key(|f| f.name.to_lowercase());
    Ok(out)
}

// ── The query ────────────────────────────────────────────────────────────────

#[derive(PartialEq, Clone, Copy)]
enum Group {
    Text,
    Sources,
    Kinds,
    Traits,
    Saved,
    Hidden,
}

/// Does `f` pass every filter group except `skip`?
fn passes(f: &FamilyAgg, q: &FamilyQuery, words: &[String], skip: Option<Group>) -> bool {
    let on = |g: Group| skip != Some(g);
    let e = &f.entry;
    (!on(Group::Text) || words.iter().all(|w| f.haystack.contains(w.as_str())))
        && (!on(Group::Sources) || q.sources.is_empty() || q.sources.iter().any(|s| e.sources.contains(s)))
        && (!on(Group::Kinds) || q.kinds.is_empty() || q.kinds.contains(&e.kind))
        && (!on(Group::Traits) || q.traits.iter().all(|t| e.traits.contains(t)))
        && (!on(Group::Saved) || !q.saved_only || e.saved)
        && (!on(Group::Hidden) || q.include_hidden || !e.hidden)
}

/// Run a query over already-loaded families. Pure: no database.
pub fn run_query(all: &[FamilyAgg], q: &FamilyQuery) -> FamilyResults {
    let words: Vec<String> = q.text.to_lowercase().split_whitespace().map(String::from).collect();
    let count = |skip: Option<Group>, extra: &dyn Fn(&FamilyEntry) -> bool| -> u32 {
        all.iter().filter(|f| passes(f, q, &words, skip) && extra(&f.entry)).count() as u32
    };

    let counts = FacetCounts {
        sources: ALL_SOURCES
            .iter()
            .map(|&s| SourceCount { source: s, count: count(Some(Group::Sources), &|e| e.sources.contains(&s)) })
            .collect(),
        kinds: ALL_KINDS
            .iter()
            .map(|&k| KindCount { kind: k, count: count(Some(Group::Kinds), &|e| e.kind == k) })
            .collect(),
        traits: ALL_TRAITS
            .iter()
            .map(|&t| TraitCount { tr: t, count: count(None, &|e| e.traits.contains(&t)) })
            .collect(),
        saved: count(Some(Group::Saved), &|e| e.saved),
        hidden: count(Some(Group::Hidden), &|e| e.hidden),
    };

    let mut families: Vec<FamilyEntry> =
        all.iter().filter(|f| passes(f, q, &words, None)).map(|f| f.entry.clone()).collect();
    // Yours first (the fonts you chose to install), then by name. Stable on the name-sorted input.
    families.sort_by_key(|e| !e.sources.contains(&Source::Yours));
    FamilyResults { families, counts }
}

/// Find families. See `FamilyQuery` for the filter rules and `FacetCounts` for the counts.
pub fn find_families(conn: &Connection, q: &FamilyQuery) -> Result<FamilyResults, String> {
    let all = load_families(conn).map_err(|e| e.to_string())?;
    Ok(run_query(&all, q))
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{run_migrations, CREATE_TABLE};
    use crate::google_list::{parse_metadata, store_catalog};

    fn mem() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        conn
    }

    /// One font file row. Most columns keep their defaults.
    struct Row<'a> {
        id: &'a str,
        family: &'a str,
        source: &'a str,
        file: &'a str,
        serif: i32,
        category: &'a str,
        width: &'a str,
        variable: i32,
        trial: i32,
        foundry: &'a str,
    }

    fn row<'a>(id: &'a str, family: &'a str, source: &'a str) -> Row<'a> {
        Row { id, family, source, file: "Regular.otf", serif: 0, category: "sans-serif", width: "normal", variable: 0, trial: 0, foundry: "" }
    }

    fn add(conn: &Connection, r: Row) {
        conn.execute(
            "INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, category, width,
                                flesh_serif, is_variable, is_trial, foundry, created_at, updated_at)
             VALUES (?1, ?2, '/x/' || ?1 || '/' || ?4, ?4, ?3, ?2, ?5, ?6, ?7, ?8, ?9, NULLIF(?10, ''), 'x', 'x')",
            params![r.id, r.family, r.source, r.file, r.category, r.width, r.serif, r.variable, r.trial, r.foundry],
        )
        .unwrap();
    }

    fn names(res: &FamilyResults) -> Vec<&str> {
        res.families.iter().map(|f| f.name.as_str()).collect()
    }

    fn count_of(res: &FamilyResults, s: Source) -> u32 {
        res.counts.sources.iter().find(|c| c.source == s).unwrap().count
    }
    fn kind_count(res: &FamilyResults, k: Kind) -> u32 {
        res.counts.kinds.iter().find(|c| c.kind == k).unwrap().count
    }
    fn trait_count(res: &FamilyResults, t: Trait) -> u32 {
        res.counts.traits.iter().find(|c| c.tr == t).unwrap().count
    }

    /// A small library: yours, system, Google-listed, junk, one of every kind and trait.
    fn library() -> Connection {
        let conn = mem();
        store_catalog(&conn, &parse_metadata(include_str!("fixtures/google_metadata.json")).unwrap()).unwrap();
        // Yours
        add(&conn, Row { serif: 1, foundry: "Undercase Type", ..row("f1", "Fraunces", "user") });
        add(&conn, Row { file: "Italic.otf", serif: 1, ..row("f2", "Fraunces", "user") });
        add(&conn, Row { variable: 1, foundry: "Rasmus", ..row("i1", "Inter", "library") });
        add(&conn, Row { trial: 1, foundry: "Grilli Type", ..row("g1", "GT Flexa", "user") });
        add(&conn, Row { width: "condensed", ..row("c1", "Narrow Grot", "user") });
        add(&conn, Row { width: "extended", ..row("w1", "Wide Grot", "user") });
        add(&conn, Row { category: "monospace", ..row("m1", "Plex Mono", "user") });
        add(&conn, Row { category: "script", ..row("s1", "Signature", "user") });
        add(&conn, Row { category: "decorative", ..row("d1", "Posterface", "user") });
        // System: a normal one, a family that is both yours and system, and junk
        add(&conn, row("h1", "Helvetica Neue", "system"));
        add(&conn, Row { serif: 1, ..row("t1", "Times New Roman", "system") });
        add(&conn, row("i2", "Inter", "system")); // Inter is yours and system
        add(&conn, row("z1", "Zapf Dingbats", "system"));
        add(&conn, row("pf", "PingFang SC", "system"));
        conn
    }

    #[test]
    fn source_mapping_and_union() {
        let conn = library();
        let all = load_families(&conn).unwrap();
        let by = |n: &str| all.iter().find(|f| f.name == n).unwrap().entry.clone();
        assert_eq!(by("Fraunces").sources, vec![Source::Yours, Source::Google]);
        assert_eq!(by("Helvetica Neue").sources, vec![Source::System]);
        assert_eq!(by("Inter").sources, vec![Source::Yours, Source::Google, Source::System], "union of its files, plus Google");
        assert_eq!(by("GT Flexa").sources, vec![Source::Yours]);
        // "library" (/Library/Fonts) counts as yours
        assert!(by("Inter").sources.contains(&Source::Yours));
    }

    #[test]
    fn google_membership_and_rank() {
        let conn = library();
        let all = load_families(&conn).unwrap();
        let rank = |n: &str| all.iter().find(|f| f.name == n).unwrap().entry.google_rank;
        assert_eq!(rank("Inter"), Some(2));
        assert_eq!(rank("Fraunces"), Some(120));
        assert_eq!(rank("GT Flexa"), None);
        let res = find_families(&conn, &FamilyQuery { sources: vec![Source::Google], ..Default::default() }).unwrap();
        assert_eq!(names(&res), vec!["Fraunces", "Inter"]);
    }

    #[test]
    fn google_filter_is_empty_offline() {
        let conn = mem();
        add(&conn, row("a", "Inter", "user"));
        let res = find_families(&conn, &FamilyQuery { sources: vec![Source::Google], ..Default::default() }).unwrap();
        assert!(res.families.is_empty());
        assert_eq!(count_of(&res, Source::Google), 0);
        assert_eq!(count_of(&res, Source::Yours), 1);
    }

    #[test]
    fn junk_list_hides_by_name_and_prefix() {
        assert!(is_junk_family("Zapf Dingbats"));
        assert!(is_junk_family("zapf dingbats"));
        assert!(is_junk_family("PingFang SC"));
        assert!(is_junk_family("Apple SD Gothic Neo"), "prefix");
        assert!(is_junk_family(".SF NS"), "dot prefix");
        assert!(!is_junk_family("Inter"));
        assert!(!is_junk_family("Helvetica Neue"), "only plain Helvetica is on the list");
        assert!(is_junk_family("Helvetica"));
        let conn = library();
        let res = find_families(&conn, &FamilyQuery::default()).unwrap();
        assert!(!names(&res).contains(&"Zapf Dingbats"));
        assert!(!names(&res).contains(&"PingFang SC"));
        assert_eq!(res.counts.hidden, 2);
        let all = find_families(&conn, &FamilyQuery { include_hidden: true, ..Default::default() }).unwrap();
        assert!(names(&all).contains(&"Zapf Dingbats"));
        assert_eq!(all.families.len(), res.families.len() + 2);
    }

    #[test]
    fn hide_and_unhide_a_family() {
        let conn = library();
        hide_family(&conn, "Inter").unwrap();
        let q = FamilyQuery::default();
        assert!(!names(&find_families(&conn, &q).unwrap()).contains(&"Inter"));
        let hidden = find_families(&conn, &FamilyQuery { include_hidden: true, ..Default::default() }).unwrap();
        assert!(hidden.families.iter().find(|f| f.name == "Inter").unwrap().hidden);
        unhide_family(&conn, "Inter").unwrap();
        assert!(names(&find_families(&conn, &q).unwrap()).contains(&"Inter"));
        let rows: i64 = conn.query_row("SELECT COUNT(*) FROM hidden", [], |r| r.get(0)).unwrap();
        assert_eq!(rows, 0, "unhiding a normal family leaves no row");
    }

    #[test]
    fn unhiding_a_junk_family_sticks() {
        let conn = library();
        unhide_family(&conn, "Zapf Dingbats").unwrap();
        assert!(names(&find_families(&conn, &FamilyQuery::default()).unwrap()).contains(&"Zapf Dingbats"));
        // and the user can hide it again
        hide_family(&conn, "zapf dingbats").unwrap();
        assert!(!names(&find_families(&conn, &FamilyQuery::default()).unwrap()).contains(&"Zapf Dingbats"));
    }

    #[test]
    fn hidden_ids_cover_every_file_of_the_family() {
        let conn = library();
        hide_family(&conn, "Fraunces").unwrap();
        let ids = hidden_font_ids(&conn);
        assert!(ids.contains("f1") && ids.contains("f2"));
        assert!(ids.contains("z1"), "junk too");
        assert!(!ids.contains("i1"));
    }

    #[test]
    fn favorites_toggle_and_filter() {
        let conn = library();
        set_favorite(&conn, "Fraunces", true).unwrap();
        set_favorite(&conn, "Fraunces", true).unwrap(); // twice is fine
        set_favorite(&conn, "inter", true).unwrap();
        let res = find_families(&conn, &FamilyQuery { saved_only: true, ..Default::default() }).unwrap();
        assert_eq!(names(&res), vec!["Fraunces", "Inter"]);
        assert!(res.families.iter().all(|f| f.saved));
        assert_eq!(res.counts.saved, 2);
        set_favorite(&conn, "Fraunces", false).unwrap();
        let res = find_families(&conn, &FamilyQuery { saved_only: true, ..Default::default() }).unwrap();
        assert_eq!(names(&res), vec!["Inter"]);
    }

    #[test]
    fn kinds_come_from_outline_fixed_pitch_category_and_name() {
        let conn = library();
        let all = load_families(&conn).unwrap();
        let kind = |n: &str| all.iter().find(|f| f.name == n).unwrap().entry.kind;
        assert_eq!(kind("Times New Roman"), Kind::Serif);
        assert_eq!(kind("Helvetica Neue"), Kind::Sans);
        assert_eq!(kind("Plex Mono"), Kind::Mono);
        assert_eq!(kind("Signature"), Kind::Script);
        assert_eq!(kind("Posterface"), Kind::Display);
        // Google's category wins for mono, script and display; the outline decides serif or sans
        assert_eq!(kind_of("Pacifico", "sans-serif", Some("Handwriting"), false), Kind::Script);
        assert_eq!(kind_of("Space Mono", "other", Some("Monospace"), false), Kind::Mono);
        assert_eq!(kind_of("Playfair Display", "serif", Some("Serif"), true), Kind::Serif, "Display in the name does not matter when Google says Serif");
        assert_eq!(kind_of("Playfair Display", "serif", None, true), Kind::Display, "unlisted: the name word counts");
        assert_eq!(kind_of("Hand Lettering Pro", "other", None, false), Kind::Script);
        assert_eq!(kind_of("Chandler", "other", None, false), Kind::Sans, "'hand' inside a word is not a keyword");
    }

    #[test]
    fn traits_are_read_from_the_files() {
        let conn = library();
        let all = load_families(&conn).unwrap();
        let tr = |n: &str| all.iter().find(|f| f.name == n).unwrap().entry.traits.clone();
        assert_eq!(tr("Fraunces"), vec![Trait::Italic], "an italic file");
        assert_eq!(tr("Inter"), vec![Trait::Variable]);
        assert_eq!(tr("GT Flexa"), vec![Trait::Trial]);
        assert_eq!(tr("Narrow Grot"), vec![Trait::Condensed]);
        assert_eq!(tr("Wide Grot"), vec![Trait::Wide]);
    }

    #[test]
    fn filter_logic_or_within_groups_and_across() {
        let conn = library();
        let q = |f: &dyn Fn(&mut FamilyQuery)| {
            let mut q = FamilyQuery::default();
            f(&mut q);
            names(&find_families(&conn, &q).unwrap()).into_iter().map(String::from).collect::<Vec<_>>()
        };
        // sources OR
        assert_eq!(q(&|q| q.sources = vec![Source::System]), vec!["Inter", "Helvetica Neue", "Times New Roman"]);
        let both = q(&|q| q.sources = vec![Source::Yours, Source::System]);
        assert!(both.contains(&"Helvetica Neue".to_string()) && both.contains(&"Fraunces".to_string()));
        // kinds OR
        assert_eq!(q(&|q| q.kinds = vec![Kind::Mono, Kind::Script]), vec!["Plex Mono", "Signature"]);
        // traits AND: Inter is variable, nobody is variable and italic
        assert_eq!(q(&|q| q.traits = vec![Trait::Variable]), vec!["Inter"]);
        assert!(q(&|q| q.traits = vec![Trait::Variable, Trait::Italic]).is_empty());
        // groups AND: serif AND yours
        assert_eq!(q(&|q| { q.kinds = vec![Kind::Serif]; q.sources = vec![Source::Yours]; }), vec!["Fraunces"]);
        // text: family, foundry, vendor, designer; every word must match
        assert_eq!(q(&|q| q.text = "grilli".into()), vec!["GT Flexa"]);
        assert_eq!(q(&|q| q.text = "undercase fraun".into()), vec!["Fraunces"]);
        assert!(q(&|q| q.text = "undercase inter".into()).is_empty());
        assert_eq!(q(&|q| q.text = "NARROW".into()), vec!["Narrow Grot"]);
    }

    #[test]
    fn text_matches_designer_and_vendor() {
        let conn = library();
        conn.execute("UPDATE fonts SET designer = 'Sol Matas', vendor_id = 'PYRS' WHERE font_id = 's1'", []).unwrap();
        let find = |t: &str| names(&find_families(&conn, &FamilyQuery { text: t.into(), ..Default::default() }).unwrap()).iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(find("matas"), vec!["Signature"]);
        assert_eq!(find("pyrs"), vec!["Signature"]);
    }

    #[test]
    fn counts_apply_every_other_filter() {
        let conn = library();
        // No filters: visible families are 12 minus 2 hidden = 10... count them.
        let none = find_families(&conn, &FamilyQuery::default()).unwrap();
        let total = none.families.len() as u32;
        assert_eq!(total, 10);
        assert_eq!(count_of(&none, Source::Yours), 8, "Fraunces, Inter, GT Flexa, Narrow, Wide, Plex Mono, Signature, Posterface");
        assert_eq!(count_of(&none, Source::System), 3, "Helvetica Neue, Times, Inter");
        assert_eq!(count_of(&none, Source::Google), 2);

        // Selecting Yours does not zero the other source chips: they still show what they would add.
        let yours = find_families(&conn, &FamilyQuery { sources: vec![Source::Yours], ..Default::default() }).unwrap();
        assert_eq!(yours.families.len(), 8);
        assert_eq!(count_of(&yours, Source::System), 3);
        assert_eq!(count_of(&yours, Source::Yours), 8);

        // Another group does narrow a chip: serif kind only
        let serif = find_families(&conn, &FamilyQuery { kinds: vec![Kind::Serif], ..Default::default() }).unwrap();
        assert_eq!(names(&serif), vec!["Fraunces", "Times New Roman"]);
        assert_eq!(count_of(&serif, Source::Yours), 1);
        assert_eq!(count_of(&serif, Source::System), 1);
        assert_eq!(count_of(&serif, Source::Google), 1);
        // kind chips ignore the kind selection but obey sources
        assert_eq!(kind_count(&serif, Kind::Sans), kind_count(&none, Kind::Sans));
        let sys = find_families(&conn, &FamilyQuery { sources: vec![Source::System], ..Default::default() }).unwrap();
        assert_eq!(kind_count(&sys, Kind::Serif), 1);
        assert_eq!(kind_count(&sys, Kind::Mono), 0);

        // Traits AND: with Variable on, Italic would leave nothing
        let var = find_families(&conn, &FamilyQuery { traits: vec![Trait::Variable], ..Default::default() }).unwrap();
        assert_eq!(var.families.len() as u32, trait_count(&var, Trait::Variable));
        assert_eq!(trait_count(&var, Trait::Italic), 0);
        assert_eq!(trait_count(&none, Trait::Italic), 1);
        assert_eq!(trait_count(&none, Trait::Trial), 1);

        // Text narrows every chip
        let text = find_families(&conn, &FamilyQuery { text: "grot".into(), ..Default::default() }).unwrap();
        assert_eq!(count_of(&text, Source::Yours), 2);
        assert_eq!(count_of(&text, Source::System), 0);

        // Hidden: what Show hidden would add
        assert_eq!(none.counts.hidden, 2);
        let sys_only = FamilyQuery { sources: vec![Source::System], ..Default::default() };
        assert_eq!(find_families(&conn, &sys_only).unwrap().counts.hidden, 2);
        assert_eq!(find_families(&conn, &FamilyQuery { sources: vec![Source::Google], ..Default::default() }).unwrap().counts.hidden, 0);
    }

    #[test]
    fn yours_come_first_then_by_name() {
        let conn = library();
        let res = find_families(&conn, &FamilyQuery::default()).unwrap();
        let first_system_only = res.families.iter().position(|f| !f.sources.contains(&Source::Yours)).unwrap();
        assert!(res.families[..first_system_only].iter().all(|f| f.sources.contains(&Source::Yours)));
        let yours: Vec<&str> = names(&res)[..first_system_only].to_vec();
        let mut sorted = yours.clone();
        sorted.sort_by_key(|n| n.to_lowercase());
        assert_eq!(yours, sorted);
    }

    #[test]
    fn hidden_families_are_not_pairing_candidates() {
        use crate::pairing::{font_candidates, font_pairs};
        let conn = mem();
        // A serif display face and a few sans faces with measured proportions.
        let add_measured = |id: &str, family: &str, serif: i32, skeleton: &str| {
            add(&conn, Row { serif, ..row(id, family, "user") });
            conn.execute(
                "UPDATE fonts SET skeleton = ?2, x_height_ratio = 0.5, cap_height_ratio = 0.7, weight = 400 WHERE font_id = ?1",
                params![id, skeleton],
            )
            .unwrap();
        };
        add_measured("p", "Primary Serif", 1, "dynamic");
        for (i, fam) in ["Alpha Sans", "Beta Sans", "Gamma Sans"].iter().enumerate() {
            add_measured(&format!("c{i}"), fam, 0, "rational");
        }
        let family_of = |id: &str| -> String {
            conn.query_row("SELECT font_family FROM fonts WHERE font_id = ?1", [id], |r| r.get(0)).unwrap()
        };
        let before: Vec<String> = font_candidates(&conn, "p", vec![], None, 20).unwrap().iter().map(|s| family_of(&s.font_id)).collect();
        assert!(before.contains(&"Beta Sans".to_string()), "setup: Beta Sans should be a candidate, got {before:?}");
        hide_family(&conn, "Beta Sans").unwrap();
        let after: Vec<String> = font_candidates(&conn, "p", vec![], None, 20).unwrap().iter().map(|s| family_of(&s.font_id)).collect();
        assert!(!after.contains(&"Beta Sans".to_string()));
        assert_eq!(after.len(), before.len() - 1);
        let pairs = font_pairs(&conn, "p", vec![], None).unwrap();
        assert!(pairs.iter().flat_map(|b| &b.pairs).all(|p| family_of(&p.font_id) != "Beta Sans"));
    }

    /// Real-data numbers on a COPY of the library (never the live DB):
    ///   FONTDROP_DB=<copy> GOOGLE_METADATA=<saved response> cargo test --lib report_copy -- --ignored --nocapture
    /// Migrates the copy, re-reads name tables (trial and variable flags), stores Google's list
    /// from the saved file (no network), and prints families per source, hidden and matches.
    #[test]
    #[ignore]
    fn report_copy() {
        let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
        assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy, not the live DB");
        let conn = crate::db::try_open_db_at(std::path::Path::new(&path)).unwrap();
        crate::db::enrich_from_name_tables(&conn);
        let meta = std::env::var("GOOGLE_METADATA").expect("set GOOGLE_METADATA to a saved response");
        let list = parse_metadata(&std::fs::read_to_string(meta).unwrap()).unwrap();
        store_catalog(&conn, &list).unwrap();
        println!("google list: {} families", list.len());
        println!("matched installed families: {}", crate::google_list::match_installed(&conn));
        let res = find_families(&conn, &FamilyQuery { include_hidden: true, ..Default::default() }).unwrap();
        println!("all families: {}", res.families.len());
        for c in &res.counts.sources {
            println!("  source {:?}: {}", c.source, c.count);
        }
        for c in &res.counts.kinds {
            println!("  kind {:?}: {}", c.kind, c.count);
        }
        for c in &res.counts.traits {
            println!("  trait {:?}: {}", c.tr, c.count);
        }
        println!("junk list hides: {} families", res.families.iter().filter(|f| f.hidden).count());
        let default = find_families(&conn, &FamilyQuery { sources: vec![Source::Yours, Source::Google], ..Default::default() }).unwrap();
        println!("default view (Yours + Google, junk hidden): {} families", default.families.len());
        for f in res.families.iter().filter(|f| f.name.starts_with("GT Flexa Var")) {
            println!("  {} traits {:?}", f.name, f.traits);
        }
    }

    #[test]
    fn long_text_count_is_families_the_reading_rule_removes() {
        use crate::pairing::{font_candidates, unfit_family_count};
        let conn = mem();
        let measured = |id: &str, family: &str, file: &str, weight: i32, serif: i32, width: &str| {
            add(&conn, Row { file, serif, width, ..row(id, family, "user") });
            conn.execute(
                "UPDATE fonts SET skeleton = ?2, x_height_ratio = 0.5, cap_height_ratio = 0.7, weight = ?3 WHERE font_id = ?1",
                params![id, if serif == 1 { "dynamic" } else { "rational" }, weight],
            )
            .unwrap();
        };
        measured("p", "Primary Serif", "P.otf", 400, 1, "normal");
        // Fits long text: regular, italic, bold, bold italic.
        for (i, (file, w)) in [("Regular.otf", 400), ("Italic.otf", 400), ("Bold.otf", 700), ("BoldItalic.otf", 700)].iter().enumerate() {
            measured(&format!("ok{i}"), "Text Sans", file, *w, 0, "normal");
        }
        // Does not: one weight only. Another: condensed. A third: hidden, so never counted.
        measured("one", "Single Sans", "Regular.otf", 400, 0, "normal");
        measured("nar", "Narrow Sans", "Regular.otf", 400, 0, "condensed");
        measured("hid", "Hidden Sans", "Regular.otf", 400, 0, "normal");
        hide_family(&conn, "Hidden Sans").unwrap();

        let reading: Vec<String> = font_candidates(&conn, "p", vec![], Some("reading"), 50).unwrap().iter().map(|s| s.font_id.clone()).collect();
        let all: Vec<String> = font_candidates(&conn, "p", vec![], None, 50).unwrap().iter().map(|s| s.font_id.clone()).collect();
        assert_eq!(reading.len(), 1, "only Text Sans is made for long text: {reading:?}");
        assert_eq!(all.len(), 3, "Text Sans, Single Sans, Narrow Sans: {all:?}");
        assert_eq!(unfit_family_count(&conn, "p", vec![]).unwrap(), 2);
        assert_eq!(unfit_family_count(&conn, "p", vec!["one".into()]).unwrap(), 1, "an excluded file is not counted");
        assert!(unfit_family_count(&conn, "nope", vec![]).is_err());
    }
}
