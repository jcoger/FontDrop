//! The backup written before an upgrade. Every test works in its own temp directory, never the real library.

use super::*;

fn temp_dir(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("fontdrop-core-backup-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn backups(dir: &Path) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.contains(".backup-v"))
        .collect();
    v.sort();
    v
}

const FONT: &str =
    "INSERT INTO fonts (font_id, name, file_name, file_path, font_family, source, created_at, updated_at) VALUES ('a','A','a.otf','/a.otf','A','user','t','t')";

#[test]
fn a_new_library_writes_no_backup() {
    let dir = temp_dir("fresh");
    drop(try_open_db_at(&dir.join("lib.db")).unwrap());
    assert!(backups(&dir).is_empty());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_migration_backs_up_the_old_library_first() {
    let dir = temp_dir("migrate");
    let path = dir.join("lib.db");
    let old = MIGRATIONS.len() - 1;
    {
        let c = Connection::open(&path).unwrap();
        c.execute_batch(CREATE_TABLE).unwrap();
        for stmt in MIGRATIONS.iter().take(old) {
            c.execute_batch(stmt).ok();
        }
        c.execute_batch(&format!("PRAGMA user_version = {old};")).unwrap();
        c.execute(FONT, []).unwrap();
    }
    let conn = try_open_db_at(&path).unwrap();
    let name = format!("lib.db.backup-v{old}.db");
    assert_eq!(backups(&dir), vec![name.clone()]);
    // The copy is the library as it was: the old version, the same rows.
    let copy = Connection::open(dir.join(name)).unwrap();
    let v: i64 = copy.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
    let fonts: i64 = copy.query_row("SELECT COUNT(*) FROM fonts", [], |r| r.get(0)).unwrap();
    assert_eq!((v as usize, fonts), (old, 1));
    let live: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
    assert_eq!(live as usize, MIGRATIONS.len());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_classifier_bump_backs_up_and_an_up_to_date_library_does_not() {
    let dir = temp_dir("classifier");
    let path = dir.join("lib.db");
    {
        let conn = try_open_db_at(&path).unwrap();
        conn.execute(FONT, []).unwrap();
        meta_set(&conn, "classifier_version", &CLASSIFIER_VERSION.to_string());
    }
    drop(try_open_db_at(&path).unwrap());
    assert!(backups(&dir).is_empty(), "nothing pending, nothing written");

    {
        let conn = Connection::open(&path).unwrap();
        meta_set(&conn, "classifier_version", &(CLASSIFIER_VERSION - 1).to_string());
    }
    drop(try_open_db_at(&path).unwrap());
    assert_eq!(backups(&dir), vec![format!("lib.db.backup-v{}.db", MIGRATIONS.len())]);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn only_the_two_newest_backups_stay() {
    let dir = temp_dir("prune");
    let path = dir.join("lib.db");
    for v in [3, 4, 5] {
        std::fs::write(dir.join(format!("lib.db.backup-v{v}.db")), b"x").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(30));
    }
    std::fs::write(dir.join("other.db.backup-v1.db"), b"x").unwrap();
    prune_backups(&path, BACKUPS_KEPT);
    assert_eq!(backups(&dir), vec!["lib.db.backup-v4.db", "lib.db.backup-v5.db", "other.db.backup-v1.db"]);
    let _ = std::fs::remove_dir_all(&dir);
}
