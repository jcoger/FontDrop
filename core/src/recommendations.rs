//! Typefaces that published type guides recommend for body text, with their sources.
//!
//! The data is `core/data/text-recommendations.csv`: family, source (publisher), page URL, a short quote or section
//! title, and the role. Every row was checked against its live page. Reading uses it two ways: a recommended face counts
//! as a dependable text face even when one measured signal could not be read (never when one fails), and it gets the
//! same small boost the other shortcuts get, with the sources shown on the card.

use std::collections::HashMap;
use std::sync::OnceLock;

const CSV: &str = include_str!("../data/text-recommendations.csv");

/// One row of the data file.
#[derive(Debug, Clone, PartialEq)]
pub struct Rec {
    pub family: String,
    pub source: String,
    pub url: String,
    pub quote: String,
    pub role: String,
}

/// What the guides say about one family.
#[derive(Debug, Clone, PartialEq)]
pub struct Recommendation {
    /// The publishers, each once, in the order the data file lists them.
    pub sources: Vec<String>,
    pub rows: Vec<Rec>,
}

/// The score a recommendation adds in Reading: the same size as the other shortcuts (shared foundry, stroke texture).
pub const BOOST: f32 = 4.0;

/// The short code the app turns into the source's name (Lexicon.sources), as the other evidence does.
pub fn source_code(source: &str) -> &'static str {
    if source.starts_with("Typewolf") { "TYW" } else if source.starts_with("Butterick") { "BPT" } else { "REC" }
}

/// Splits one CSV line into fields. Handles double-quoted fields with commas; no multi-line fields.
fn fields(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut quoted = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match (c, quoted) {
            ('"', true) if chars.peek() == Some(&'"') => { cur.push('"'); chars.next(); }
            ('"', _) => quoted = !quoted,
            (',', false) => out.push(std::mem::take(&mut cur)),
            _ => cur.push(c),
        }
    }
    out.push(cur);
    out
}

/// The rows of a data file's text. Comment lines (#) and the header are skipped; short or empty rows too.
pub fn parse(text: &str) -> Vec<Rec> {
    text.lines()
        .filter(|l| !l.trim().is_empty() && !l.starts_with('#'))
        .map(fields)
        .filter(|f| f.len() >= 5 && f[0] != "family")
        .map(|f| Rec { family: f[0].clone(), source: f[1].clone(), url: f[2].clone(), quote: f[3].clone(), role: f[4].clone() })
        .collect()
}

/// A family name as the match sees it: lowercase letters and digits only, with a leading "Test" and a trailing "Trial"
/// or "Test" removed (the foundries' trial builds), and then a trailing "Text" or "Txt" removed. "GT Super Txt Trial",
/// "Test Domaine Text" and "Dashiell Text TEST" read as "gtsuper", "domaine" and "dashiell".
pub fn key(name: &str) -> String {
    let mut k: String = name.chars().filter(|c| c.is_alphanumeric()).flat_map(|c| c.to_lowercase()).collect();
    if let Some(rest) = k.strip_prefix("test") { if rest.len() > 2 { k = rest.to_string(); } }
    // "Inter Variable", "Fraunces VF": the same family, named for the kind of file.
    for suffix in ["trial", "test", "variable", "vf"] {
        if let Some(rest) = k.strip_suffix(suffix) { if rest.len() > 2 { k = rest.to_string(); } }
    }
    for suffix in ["text", "txt"] {
        if let Some(rest) = k.strip_suffix(suffix) { if rest.len() > 2 { k = rest.to_string(); } }
    }
    k
}

fn table() -> &'static HashMap<String, Recommendation> {
    static TABLE: OnceLock<HashMap<String, Recommendation>> = OnceLock::new();
    TABLE.get_or_init(|| build(&parse(CSV)))
}

/// The rows grouped by matching key, only the body (text) role.
pub fn build(rows: &[Rec]) -> HashMap<String, Recommendation> {
    let mut map: HashMap<String, Recommendation> = HashMap::new();
    for r in rows.iter().filter(|r| r.role == "body") {
        let e = map.entry(key(&r.family)).or_insert_with(|| Recommendation { sources: Vec::new(), rows: Vec::new() });
        if !e.sources.contains(&r.source) { e.sources.push(r.source.clone()); }
        e.rows.push(r.clone());
    }
    map
}

/// What the guides say about a library family, if anything.
pub fn for_family(family: &str) -> Option<&'static Recommendation> {
    table().get(&key(family))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_data_file_parses_and_every_row_is_complete() {
        let rows = parse(CSV);
        assert!(rows.len() >= 40, "{} rows", rows.len());
        for r in &rows {
            assert!(!r.family.is_empty() && r.url.starts_with("https://") && !r.source.is_empty(), "{r:?}");
            assert!(!r.quote.is_empty() && r.quote.split_whitespace().count() < 15, "quote of {}: {}", r.family, r.quote);
            assert_eq!(r.role, "body", "{}", r.family);
        }
        let families: std::collections::HashSet<_> = rows.iter().map(|r| key(&r.family)).collect();
        assert!(families.len() >= 40, "{} families", families.len());
    }

    #[test]
    fn names_match_through_trial_test_and_text_variants() {
        assert_eq!(key("GT Super Txt Trial"), "gtsuper");
        assert_eq!(key("Test Domaine Text"), "domaine");
        assert_eq!(key("Dashiell Text TEST"), "dashiell");
        assert_eq!(key("Tiempos Text"), "tiempos");
        assert_eq!(key("Freight Text"), "freight");
        assert_eq!(key("Test Martina Plantijn"), "martinaplantijn");
        assert_eq!(key("Inter"), "inter");
        assert_eq!(key("Inter Variable"), "inter");
        assert_eq!(key("Fraunces VF"), "fraunces");
        assert!(for_family("Inter Variable").is_some());
        assert_eq!(key("Test"), "test", "a bare Test stays");
        // A recommended "Tiempos Text" is found for a library "Tiempos" and the reverse.
        assert!(for_family("Tiempos Text Trial").is_some());
        assert!(for_family("Tiempos").is_some());
        assert!(for_family("Inter").is_some() && for_family("Zzz Not A Font").is_none());
    }

    #[test]
    fn sources_are_listed_once_each() {
        let rec = for_family("Charter").unwrap();
        assert_eq!(rec.sources, vec!["Butterick's Practical Typography".to_string()], "two Butterick pages, one source");
        assert_eq!(rec.rows.len(), 2);
        assert_eq!(source_code("Typewolf"), "TYW");
        assert_eq!(source_code("Butterick's Practical Typography"), "BPT");
    }

    #[test]
    fn a_quoted_field_keeps_its_comma() {
        let rows = parse("family,source,url,quote,role\nAcme,Guide,https://x.test,\"One, two\",body\n# comment\n");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].quote, "One, two");
    }
}
