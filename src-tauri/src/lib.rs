//! Tauri shell. The engine lives in the `fontdrop_core` crate (../core); this
//! file only holds app state, the `#[tauri::command]` wrappers the React UI
//! calls, and the background startup thread.

use fontdrop_core::{db, google_fonts, pairing, userdata};
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{Manager, State};

pub struct DbState(pub Mutex<rusqlite::Connection>);
pub struct AppDataDir(pub PathBuf);

fn with_conn<T>(
    state: &State<'_, DbState>,
    f: impl FnOnce(&rusqlite::Connection) -> Result<T, String>,
) -> Result<T, String> {
    let conn = state.0.lock().map_err(|e| e.to_string())?;
    f(&conn)
}

// ── Font library ──────────────────────────────────────────────────────────────

#[tauri::command]
fn get_font_db(state: State<'_, DbState>) -> Result<Vec<db::FontRow>, String> {
    with_conn(&state, db::get_font_rows)
}

#[tauri::command]
fn update_font_classification(
    state: State<'_, DbState>,
    font_id: String,
    updates: db::FontUpdate,
) -> Result<(), String> {
    with_conn(&state, |c| db::update_font_classification(c, font_id, updates))
}

#[tauri::command]
fn classify_single_font(
    state: State<'_, DbState>,
    font_id: String,
) -> Result<fontdrop_core::classifier::ClassificationResult, String> {
    with_conn(&state, |c| db::classify_single_font(c, font_id))
}

#[tauri::command]
fn refresh_google_fonts(state: State<'_, DbState>, data_dir: State<'_, AppDataDir>) -> Result<u32, String> {
    with_conn(&state, |c| db::refresh_google_fonts(c, &data_dir.0))
}

#[tauri::command]
fn set_google_api_key(data_dir: State<'_, AppDataDir>, key: String) -> Result<(), String> {
    google_fonts::save_api_key(&data_dir.0, &key);
    Ok(())
}

#[tauri::command]
fn get_google_api_key(data_dir: State<'_, AppDataDir>) -> Result<Option<String>, String> {
    Ok(google_fonts::get_api_key(&data_dir.0))
}

// ── Pairing ───────────────────────────────────────────────────────────────────

/// `excluded_ids`: fonts the user has hidden. They never take a match slot.
#[tauri::command]
fn get_font_pairs(
    state: State<'_, DbState>,
    font_id: String,
    excluded_ids: Option<Vec<String>>,
    job: Option<String>,
) -> Result<Vec<pairing::PairBucket>, String> {
    with_conn(&state, |c| {
        pairing::font_pairs(c, &font_id, excluded_ids.unwrap_or_default(), job.as_deref())
    })
}

// ── User data ─────────────────────────────────────────────────────────────────

#[tauri::command]
fn brands_list(state: State<'_, DbState>) -> Result<Vec<userdata::Brand>, String> {
    with_conn(&state, userdata::list_brands)
}
#[tauri::command]
fn brand_create(state: State<'_, DbState>, name: String) -> Result<userdata::Brand, String> {
    with_conn(&state, |c| userdata::create_brand(c, &name))
}
#[tauri::command]
fn brand_update(state: State<'_, DbState>, id: i64, name: String, logo_svg: Option<String>) -> Result<(), String> {
    with_conn(&state, |c| userdata::update_brand(c, id, &name, logo_svg.as_deref()))
}
#[tauri::command]
fn brand_delete(state: State<'_, DbState>, id: i64) -> Result<(), String> {
    with_conn(&state, |c| userdata::delete_brand(c, id))
}
#[tauri::command]
fn shortlist_get(state: State<'_, DbState>, brand: i64, job: String) -> Result<Vec<String>, String> {
    with_conn(&state, |c| userdata::shortlist(c, brand, &job))
}
#[tauri::command]
fn shortlist_set(state: State<'_, DbState>, brand: i64, job: String, family: String, on: bool) -> Result<(), String> {
    with_conn(&state, |c| {
        if on {
            userdata::shortlist_add(c, brand, &job, &family)
        } else {
            userdata::shortlist_remove(c, brand, &job, &family)
        }
    })
}
#[tauri::command]
fn choice_set(state: State<'_, DbState>, brand: i64, job: String, family: String) -> Result<(), String> {
    with_conn(&state, |c| userdata::choose(c, brand, &job, &family))
}
#[tauri::command]
fn choices_get(state: State<'_, DbState>, brand: i64) -> Result<Vec<userdata::Choice>, String> {
    with_conn(&state, |c| userdata::choices(c, brand))
}
#[tauri::command]
fn house_style_get(state: State<'_, DbState>) -> Result<userdata::HouseStyle, String> {
    with_conn(&state, userdata::house_style)
}

// ── App ───────────────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let data_dir = app
                .path()
                .app_data_dir()
                .expect("failed to resolve app data dir");
            // Open the window on what the DB already knows; scan, classify and
            // enrich on a second connection in the background, then tell the
            // UI to reload. A classifier version bump used to freeze launch
            // for ~25 s before the window appeared.
            let conn = db::open_db(&data_dir);
            app.manage(AppDataDir(data_dir.clone()));
            app.manage(DbState(Mutex::new(conn)));
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                use tauri::Emitter;
                let _ = db::refresh_library(&data_dir.join(db::DB_FILE));
                let _ = handle.emit("library-updated", ());
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_font_db,
            update_font_classification,
            classify_single_font,
            refresh_google_fonts,
            set_google_api_key,
            get_google_api_key,
            get_font_pairs,
            brands_list,
            brand_create,
            brand_update,
            brand_delete,
            shortlist_get,
            shortlist_set,
            choice_set,
            choices_get,
            house_style_get
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
