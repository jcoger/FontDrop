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
fn user_version_never_goes_down() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch(CREATE_TABLE).unwrap();
    let above = MIGRATIONS.len() + 5;
    conn.execute_batch(&format!("PRAGMA user_version = {above};")).unwrap();
    try_run_migrations(&conn).unwrap();
    let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
    assert_eq!(v as usize, above, "an older build must not lower the stamp");
}
