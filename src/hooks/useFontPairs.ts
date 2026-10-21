import { useState, useEffect, useCallback, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";

/** One piece of reasoning behind a score (lens, what was measured, source, strength). */
export interface Evidence {
  lens: string;
  detail: string;
  source: string;
  strength: "rule" | "guideline" | "shortcut" | "caveat";
  effect: number;
}

export interface PairScore {
  font_id: string;
  score: number;
  pair_type: "contrast" | "uniform" | "superfamily" | "middle" | "uncertain";
  reason: string;
  evidence: Evidence[];
}

export interface PairBucket {
  label: string;
  description: string;
  pairs: PairScore[];
}

/** `excludedIds`: hidden fonts. The engine skips them so they never take a match slot. */
export function useFontPairs(fontId: string | null, excludedIds: string[]) {
  const [buckets, setBuckets] = useState<PairBucket[]>([]);
  const [loading, setLoading] = useState(false);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (!fontId) {
      setBuckets([]);
      return;
    }

    setLoading(true);
    invoke<PairBucket[]>("get_font_pairs", { fontId, excludedIds })
      .then(setBuckets)
      .catch(() => setBuckets([]))
      .finally(() => setLoading(false));
  }, [fontId, excludedIds, version]);

  const refresh = useCallback(() => setVersion((v) => v + 1), []);

  const allPairs = useMemo(
    () => buckets.flatMap((b) => b.pairs),
    [buckets],
  );

  return { buckets, allPairs, loading, refresh };
}
