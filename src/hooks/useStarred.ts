import { useState, useEffect, useCallback } from "react";

const STORAGE_KEY = "fontdrop:starred";
const LEGACY_KEYS = ["fontdrop:grid:starred", "fontdrop:explorer:starred"];

export interface StarredState {
  starred: Set<string>;
  toggle: (id: string) => void;
  showStarred: boolean;
  setShowStarred: (v: boolean) => void;
}

/** Merge legacy per-tab starred sets into the unified key (runs once). */
function migrateAndLoad(): Set<string> {
  try {
    const unified = localStorage.getItem(STORAGE_KEY);
    if (unified) return new Set<string>(JSON.parse(unified));

    // First load after migration — merge legacy keys
    const merged = new Set<string>();
    for (const key of LEGACY_KEYS) {
      const raw = localStorage.getItem(key);
      if (raw) {
        for (const id of JSON.parse(raw) as string[]) merged.add(id);
        localStorage.removeItem(key);
      }
    }
    if (merged.size > 0) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify([...merged]));
    }
    return merged;
  } catch {
    return new Set<string>();
  }
}

export function useStarred(): StarredState {
  const [starred, setStarred] = useState<Set<string>>(migrateAndLoad);
  const [showStarred, setShowStarred] = useState(false);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify([...starred]));
    } catch { /* quota */ }
  }, [starred]);

  const toggle = useCallback((id: string) => {
    setStarred((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  return { starred, toggle, showStarred, setShowStarred };
}
