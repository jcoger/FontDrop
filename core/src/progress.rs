//! How far the startup scan has got, for the first-run scan screen.
//!
//! The scan has four steps over the font files: find them, read their name tables, classify, measure.
//! Each of the last three reports how many files it has handled. `Snapshot::fraction` joins them into one 0 to 1 number.
//! Process-wide on purpose: one scan runs at a time, and the UI polls this from another thread.

use std::sync::atomic::{AtomicU32, Ordering};

static STAGE: AtomicU32 = AtomicU32::new(0);
static DONE: AtomicU32 = AtomicU32::new(0);
static TOTAL: AtomicU32 = AtomicU32::new(0);
static FILES: AtomicU32 = AtomicU32::new(0);
static FAMILIES: AtomicU32 = AtomicU32::new(0);

/// Steps that count toward the fraction: name tables, classify, measure. Finding the files is the lead-in.
pub const STAGES: u32 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Snapshot {
    /// 0 = not scanning or still finding files, 1..=3 = a step is running.
    pub stage: u32,
    pub done: u32,
    pub total: u32,
    /// Font files found on disk, and distinct family names among them.
    pub files: u32,
    pub families: u32,
}

impl Snapshot {
    /// 0 to 1 across all steps. A step with nothing to do (a warm library) counts as finished when passed.
    pub fn fraction(&self) -> f64 {
        if self.stage == 0 {
            return 0.0;
        }
        let within = if self.total == 0 { 1.0 } else { self.done as f64 / self.total as f64 };
        (((self.stage - 1) as f64 + within) / STAGES as f64).clamp(0.0, 1.0)
    }
}

pub fn snapshot() -> Snapshot {
    Snapshot {
        stage: STAGE.load(Ordering::Relaxed),
        done: DONE.load(Ordering::Relaxed),
        total: TOTAL.load(Ordering::Relaxed),
        files: FILES.load(Ordering::Relaxed),
        families: FAMILIES.load(Ordering::Relaxed),
    }
}

/// A scan begins: forget the last one.
pub fn start() {
    STAGE.store(0, Ordering::Relaxed);
    DONE.store(0, Ordering::Relaxed);
    TOTAL.store(0, Ordering::Relaxed);
    FILES.store(0, Ordering::Relaxed);
    FAMILIES.store(0, Ordering::Relaxed);
}

pub fn found(files: u32, families: u32) {
    FILES.store(files, Ordering::Relaxed);
    FAMILIES.store(families, Ordering::Relaxed);
}

/// A step begins over `total` files. `stage` is 1, 2 or 3.
pub fn begin(stage: u32, total: u32) {
    DONE.store(0, Ordering::Relaxed);
    TOTAL.store(total, Ordering::Relaxed);
    STAGE.store(stage, Ordering::Relaxed);
}

pub fn tick() {
    DONE.fetch_add(1, Ordering::Relaxed);
}

/// The scan is over.
pub fn finish() {
    STAGE.store(STAGES, Ordering::Relaxed);
    TOTAL.store(1, Ordering::Relaxed);
    DONE.store(1, Ordering::Relaxed);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fraction_runs_zero_to_one_across_steps() {
        let s = |stage, done, total| Snapshot { stage, done, total, files: 0, families: 0 }.fraction();
        assert_eq!(s(0, 0, 0), 0.0);
        assert!(s(1, 0, 100).abs() < 1e-9);
        assert!((s(1, 100, 100) - 1.0 / 3.0).abs() < 1e-9);
        assert!((s(2, 50, 100) - 0.5).abs() < 1e-9);
        assert!((s(3, 100, 100) - 1.0).abs() < 1e-9);
        assert!((s(2, 0, 0) - 2.0 / 3.0).abs() < 1e-9, "an empty step counts as done");
    }
}
