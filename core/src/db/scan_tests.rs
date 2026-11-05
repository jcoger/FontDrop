//! Scan safety: prune keeps hand classifications, a file replaced in place
//! leaves one row, and the schema stamp never goes down.

use super::*;

/// A scratch folder with fake font files. The scan hashes the bytes and reads
/// names from them; .woff skips the outline reading, so junk bytes work.
struct Fixture {
    dir: PathBuf,
}

impl Fixture {
    fn new(tag: &str) -> Fixture {
        let dir = std::env::temp_dir().join(format!("fontdrop-scan-{}-{}", tag, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Fixture { dir }
    }
    fn write(&self, name: &str, bytes: &[u8]) -> PathBuf {
        let p = self.dir.join(name);
        std::fs::write(&p, bytes).unwrap();
        p
    }
    fn scan(&self, conn: &Connection) {
        populate_from(conn, &[(self.dir.clone(), "user")]);
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn mem() -> Connection {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch(CREATE_TABLE).unwrap();
    run_migrations(&conn);
    conn
}

fn count(conn: &Connection, sql: &str) -> i64 {
    conn.query_row(sql, [], |r| r.get(0)).unwrap()
}

#[test]
fn prune_removes_a_missing_row_without_an_override() {
    let conn = mem();
    let fx = Fixture::new("prune-plain");
    let p = fx.write("Alpha-Regular.woff", b"alpha one");
    fx.scan(&conn);
    assert_eq!(count(&conn, "SELECT COUNT(*) FROM fonts"), 1);
    std::fs::remove_file(&p).unwrap();
    fx.scan(&conn);
    assert_eq!(count(&conn, "SELECT COUNT(*) FROM fonts"), 0);
}

#[test]
fn prune_keeps_a_missing_row_with_a_hand_classification() {
    let conn = mem();
    let fx = Fixture::new("prune-override");
    let p = fx.write("Beta-Regular.woff", b"beta one");
    fx.scan(&conn);
    let id = hash_font_file(&p).unwrap();
    conn.execute("UPDATE fonts SET user_override = 1, skeleton = 'humanist' WHERE font_id = ?1", params![id]).unwrap();
    std::fs::remove_file(&p).unwrap();
    fx.scan(&conn);
    assert_eq!(count(&conn, "SELECT COUNT(*) FROM fonts WHERE user_override = 1"), 1);
    let skeleton: String = conn.query_row("SELECT skeleton FROM fonts WHERE font_id = ?1", params![id], |r| r.get(0)).unwrap();
    assert_eq!(skeleton, "humanist");
}

#[test]
fn a_file_changed_in_place_leaves_one_row_for_its_path() {
    let conn = mem();
    let fx = Fixture::new("twin");
    let p = fx.write("Gamma-Regular.woff", b"gamma version one");
    fx.scan(&conn);
    let old_id = hash_font_file(&p).unwrap();
    std::fs::write(&p, b"gamma version two, updated in place").unwrap();
    let new_id = hash_font_file(&p).unwrap();
    assert_ne!(old_id, new_id);
    fx.scan(&conn);
    let path = p.to_string_lossy().to_string();
    let n: i64 = conn.query_row("SELECT COUNT(*) FROM fonts WHERE file_path = ?1", params![path], |r| r.get(0)).unwrap();
    assert_eq!(n, 1, "the old row must go");
    let kept: String = conn.query_row("SELECT font_id FROM fonts WHERE file_path = ?1", params![path], |r| r.get(0)).unwrap();
    assert_eq!(kept, new_id);
}

#[test]
fn two_rows_on_one_path_collapse_and_the_override_moves_to_the_new_row() {
    let conn = mem();
    let fx = Fixture::new("twin-override");
    let p = fx.write("Delta-Regular.woff", b"delta version one");
    fx.scan(&conn);
    let old_id = hash_font_file(&p).unwrap();
    conn.execute(
        "UPDATE fonts SET user_override = 1, skeleton = 'geometric', category = 'serif', flesh_serif = 1, classification_source = 'user' WHERE font_id = ?1",
        params![old_id],
    )
    .unwrap();
    std::fs::write(&p, b"delta version two, updated in place").unwrap();
    fx.scan(&conn);
    let path = p.to_string_lossy().to_string();
    assert_eq!(count(&conn, "SELECT COUNT(*) FROM fonts"), 1);
    let (skeleton, category, serif, over, source): (String, String, i32, i32, String) = conn
        .query_row(
            "SELECT skeleton, category, flesh_serif, user_override, classification_source FROM fonts WHERE file_path = ?1",
            params![path],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .unwrap();
    assert_eq!((skeleton.as_str(), category.as_str(), serif, over, source.as_str()), ("geometric", "serif", 1, 1, "user"));
}

#[test]
fn twin_cleanup_leaves_other_paths_alone() {
    let conn = mem();
    let fx = Fixture::new("twin-others");
    fx.write("Eps-Regular.woff", b"eps");
    let q = fx.write("Zeta-Regular.woff", b"zeta v1");
    fx.write("Zeta-Bold.woff", b"zeta bold");
    fx.scan(&conn);
    std::fs::write(&q, b"zeta v2 longer").unwrap();
    fx.scan(&conn);
    assert_eq!(count(&conn, "SELECT COUNT(*) FROM fonts"), 3);
}

#[test]
fn font_id_is_the_hash_of_the_first_64_kb() {
    let fx = Fixture::new("hash");
    let big: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
    let small = b"short file".to_vec();
    for bytes in [&big, &small] {
        let p = fx.write("x.woff", bytes);
        let chunk = &bytes[..bytes.len().min(65_536)];
        let want = format!("{:x}", Sha256::digest(chunk));
        assert_eq!(hash_font_file(&p).unwrap(), want);
    }
    // bytes past 64 KB do not change the id
    let mut other = big.clone();
    other[150_000] ^= 0xff;
    let p = fx.write("y.woff", &other);
    assert_eq!(hash_font_file(&p).unwrap(), format!("{:x}", Sha256::digest(&big[..65_536])));
}

/// On a COPY of a real database: every row whose file exists must still have
/// the id the new 64 KB read produces. Run on demand:
///   FONTDROP_DB=<copy> cargo test --lib ids_match_on_copy -- --ignored --nocapture
#[test]
#[ignore]
fn ids_match_on_copy() {
    let path = std::env::var("FONTDROP_DB").expect("set FONTDROP_DB to a copy");
    assert!(!path.contains("Application Support"), "point FONTDROP_DB at a copy, not the live DB");
    let conn = Connection::open(&path).unwrap();
    let mut st = conn.prepare("SELECT font_id, file_path FROM fonts").unwrap();
    let rows: Vec<(String, String)> = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().flatten().collect();
    let (mut same, mut differ, mut gone) = (0, 0, 0);
    for (id, p) in &rows {
        match hash_font_file(Path::new(p)) {
            Some(h) if &h == id => same += 1,
            Some(_) => differ += 1, // an in-place update or a twin row
            None => gone += 1,
        }
    }
    println!("rows {}: id matches {same}, differs {differ}, file missing {gone}", rows.len());
}

#[test]
fn user_version_never_goes_down() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch(CREATE_TABLE).unwrap();
    let above = MIGRATIONS.len() + 5;
    conn.execute_batch(&format!("PRAGMA user_version = {above};")).unwrap();
    // R7: a newer library is refused outright (the app shows a plain message), and the stamp stays where it was.
    let err = try_run_migrations(&conn).expect_err("a library from a newer build is refused");
    assert!(err.to_string().contains(NEWER_LIBRARY), "{err}");
    let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
    assert_eq!(v as usize, above, "an older build must not lower the stamp");
}
