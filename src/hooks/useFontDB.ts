import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { FontInfo, Classification } from "../types/font";

/** Extended row shape from the SQLite database. */
export interface FontDBRow extends FontInfo {
  font_id: string;
  /** 1 = trial / test / demo build */
  is_trial?: number | null;
  /** Foundry or licence page from the file */
  foundry_url?: string | null;
  name: string;
  foundry: string | null;
  designer: string | null;
  skeleton: string;
  flesh_contrast: string;
  flesh_serif: number;
  x_height_ratio: number | null;
  cap_height_ratio: number | null;
  stroke_contrast_ratio: number | null;
  classification_source: string;
  user_override: number;
  google_category: string | null;
  classification_reason: string | null;
  optical_role: string | null;
  superfamily_group: string | null;
  superfamily_role: string | null;
  ascender_descender_ratio: number | null;
  weight_range_min: number | null;
  weight_range_max: number | null;
  spacing_personality: string | null;
  width_class: string | null;
  created_at: string;
  updated_at: string;
}

export interface FontUpdate {
  foundry?: string;
  designer?: string;
  skeleton?: string;
  flesh_contrast?: string;
  flesh_serif?: number;
  x_height_ratio?: number;
  cap_height_ratio?: number;
  stroke_contrast_ratio?: number;
  classification_source?: string;
  user_override?: number;
  google_category?: string;
  category?: string;
  classification_reason?: string;
}

/** Map from file_path → font_id for migrating localStorage references. */
export type PathToIdMap = Map<string, string>;

export function useFontDB() {
  const [fonts, setFonts] = useState<FontDBRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pathToId, setPathToId] = useState<PathToIdMap>(new Map());

  // Show what the DB already has right away. The library scan runs in the
  // background and emits "library-updated" when done; a first-ever launch
  // (empty DB) stays in the loading state until then.
  useEffect(() => {
    const apply = (rows: FontDBRow[]) => {
      setFonts(rows);
      const map = new Map<string, string>();
      for (const r of rows) map.set(r.file_path, r.font_id);
      setPathToId(map);
    };
    invoke<FontDBRow[]>("get_font_db")
      .then((rows) => {
        apply(rows);
        if (rows.length > 0) setLoading(false);
      })
      .catch((e) => {
        setError(String(e));
        setLoading(false);
      });
    const unlisten = listen("library-updated", () => {
      invoke<FontDBRow[]>("get_font_db")
        .then(apply)
        .catch((e) => setError(String(e)))
        .finally(() => setLoading(false));
    });
    return () => {
      unlisten.then((off) => off());
    };
  }, []);

  const updateClassification = useCallback(
    async (fontId: string, updates: FontUpdate) => {
      await invoke("update_font_classification", {
        fontId,
        updates,
      });
      // Refresh the local state for the updated row
      setFonts((prev) =>
        prev.map((f) =>
          f.font_id === fontId
            ? {
                ...f,
                ...updates,
                classification: updates.category
                  ? { ...f.classification, category: updates.category as Classification["category"] }
                  : f.classification,
                updated_at: new Date().toISOString(),
              }
            : f,
        ),
      );
    },
    [],
  );

  const refreshGoogleFonts = useCallback(async () => {
    const enriched = await invoke<number>("refresh_google_fonts");
    // Reload all fonts to pick up enrichment changes
    const rows = await invoke<FontDBRow[]>("get_font_db");
    setFonts(rows);
    return enriched;
  }, []);

  const reload = useCallback(async () => {
    const rows = await invoke<FontDBRow[]>("get_font_db");
    setFonts(rows);
    const map = new Map<string, string>();
    for (const r of rows) map.set(r.file_path, r.font_id);
    setPathToId(map);
  }, []);

  return { fonts, loading, error, pathToId, updateClassification, refreshGoogleFonts, reload };
}
