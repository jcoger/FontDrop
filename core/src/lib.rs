//! FontDrop core: the one engine behind every FontDrop app.
//!
//! - `db`: schema, migrations (run on every open), scan, classify, queries
//! - `names`: what a font file says about itself (family, vendor, trial flag, foundry URL)
//! - `classifier`, `metrics`: skeleton and proportion measurements
//! - `pairing`: scoring, buckets, evidence
//! - `same_family`: offering the Display family itself, with a body style
//! - `userdata`: brands, shortlist per job, choices, house style
//! - `google_fonts`: catalogue enrichment
//! - `ffi` (feature `uniffi`): the Swift surface
//!
//! Nothing here depends on Tauri. The Tauri shell calls these functions from
//! its command wrappers; the SwiftUI app calls `ffi::Library`.

pub mod classifier;
pub mod db;
pub mod finder;
pub mod google_fonts;
pub mod google_list;
pub mod metrics;
pub mod names;
pub mod pairing;
pub mod same_family;
pub mod userdata;

pub use names::{
    looks_trial, parse_family, parse_font_meta, read_family_name, read_name_meta,
    strip_instance_words, Classification, FontMeta, NameMeta,
};

#[cfg(feature = "uniffi")]
mod ffi;
#[cfg(feature = "uniffi")]
pub use ffi::*;

#[cfg(feature = "uniffi")]
uniffi::setup_scaffolding!();
