import { useState, useEffect, useCallback, useMemo } from "react";
import type { FontInfo } from "./useFonts";
import {
  DEFAULT_EXCLUSION_FAMILIES,
  DEFAULT_EXCLUSION_PREFIXES,
} from "../data/defaultExclusions";

const LS_USER_EXCLUDED = "fontdrop:user-excluded";
const LS_BUILTIN_UNHIDDEN = "fontdrop:builtin-unhidden";
const LS_JUNK_INIT = "fontdrop:junk-init";

function readStringSet(key: string): Set<string> {
  try {
    const raw = localStorage.getItem(key);
    return raw ? new Set<string>(JSON.parse(raw)) : new Set<string>();
  } catch {
    return new Set<string>();
  }
}

function writeStringSet(key: string, set: Set<string>): void {
  try {
    localStorage.setItem(key, JSON.stringify([...set]));
  } catch {
    // ignore quota errors
  }
}

function isBuiltinExcluded(familyName: string): boolean {
  if (DEFAULT_EXCLUSION_FAMILIES.includes(familyName)) return true;
  return DEFAULT_EXCLUSION_PREFIXES.some((prefix) => familyName.startsWith(prefix));
}

export interface ExclusionsState {
  isExcluded: (font: FontInfo) => boolean;
  excludeFont: (filePath: string) => void;
  unhideUser: (filePath: string) => void;
  unhideBuiltin: (familyName: string) => void;
  resetAll: () => void;
  excludedCount: number;
  userExcludedFonts: FontInfo[];
  builtinExcludedFonts: FontInfo[];
  /** Non-null only on first render after junk-init was absent. Clear after showing toast. */
  firstLaunchCount: number | null;
  clearFirstLaunch: () => void;
}

export function useExclusions(allFonts: FontInfo[]): ExclusionsState {
  const [userExcluded, setUserExcluded] = useState<Set<string>>(
    () => readStringSet(LS_USER_EXCLUDED)
  );
  const [builtinUnhidden, setBuiltinUnhidden] = useState<Set<string>>(
    () => readStringSet(LS_BUILTIN_UNHIDDEN)
  );

  // First-launch: needsInit is true if the flag was absent on mount (set it right away
  // so subsequent remounts don't re-trigger). The actual count is computed in a
  // useEffect after fonts have loaded asynchronously.
  const [needsInit] = useState<boolean>(() => {
    try {
      if (localStorage.getItem(LS_JUNK_INIT)) return false;
      localStorage.setItem(LS_JUNK_INIT, "1");
      return true;
    } catch {
      return false;
    }
  });

  const [firstLaunchCount, setFirstLaunchCount] = useState<number | null>(null);

  // Once fonts are loaded (allFonts.length > 0) and this is a first launch,
  // count how many unique families are in the built-in exclusion list.
  useEffect(() => {
    if (!needsInit || allFonts.length === 0) return;
    const seen = new Set<string>();
    let count = 0;
    for (const f of allFonts) {
      if (!seen.has(f.font_family)) {
        seen.add(f.font_family);
        if (isBuiltinExcluded(f.font_family)) count++;
      }
    }
    setFirstLaunchCount(count);
  }, [needsInit, allFonts]);

  const clearFirstLaunch = useCallback(() => setFirstLaunchCount(null), []);

  const isExcluded = useCallback(
    (font: FontInfo): boolean => {
      if (userExcluded.has(font.file_path)) return true;
      if (isBuiltinExcluded(font.font_family) && !builtinUnhidden.has(font.font_family)) {
        return true;
      }
      return false;
    },
    [userExcluded, builtinUnhidden]
  );

  const excludeFont = useCallback((filePath: string) => {
    setUserExcluded((prev) => {
      const next = new Set(prev);
      next.add(filePath);
      writeStringSet(LS_USER_EXCLUDED, next);
      return next;
    });
  }, []);

  const unhideUser = useCallback((filePath: string) => {
    setUserExcluded((prev) => {
      const next = new Set(prev);
      next.delete(filePath);
      writeStringSet(LS_USER_EXCLUDED, next);
      return next;
    });
  }, []);

  const unhideBuiltin = useCallback((familyName: string) => {
    setBuiltinUnhidden((prev) => {
      const next = new Set(prev);
      next.add(familyName);
      writeStringSet(LS_BUILTIN_UNHIDDEN, next);
      return next;
    });
  }, []);

  const resetAll = useCallback(() => {
    setUserExcluded(new Set());
    setBuiltinUnhidden(new Set());
    writeStringSet(LS_USER_EXCLUDED, new Set());
    writeStringSet(LS_BUILTIN_UNHIDDEN, new Set());
  }, []);

  // Build lists for the manager UI
  const userExcludedFonts = useMemo(
    () => allFonts.filter((f) => userExcluded.has(f.file_path)),
    [allFonts, userExcluded]
  );

  // One representative font per built-in excluded family (not in user-unhidden)
  const builtinExcludedFonts = useMemo(() => {
    const seen = new Set<string>();
    return allFonts.filter((f) => {
      if (!isBuiltinExcluded(f.font_family)) return false;
      if (builtinUnhidden.has(f.font_family)) return false;
      if (seen.has(f.font_family)) return false;
      seen.add(f.font_family);
      return true;
    });
  }, [allFonts, builtinUnhidden]);

  const excludedCount = userExcluded.size + builtinExcludedFonts.length;

  return {
    isExcluded,
    excludeFont,
    unhideUser,
    unhideBuiltin,
    resetAll,
    excludedCount,
    userExcludedFonts,
    builtinExcludedFonts,
    firstLaunchCount,
    clearFirstLaunch,
  };
}
