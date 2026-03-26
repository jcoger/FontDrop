import { useState, useEffect, useCallback } from "react";

export interface StarredState {
  starred: Set<string>;
  toggle: (id: string) => void;
  showStarred: boolean;
  setShowStarred: (v: boolean) => void;
}

export function useStarred(storageKey: string): StarredState {
  const [starred, setStarred] = useState<Set<string>>(() => {
    try {
      const raw = localStorage.getItem(storageKey);
      return raw ? new Set<string>(JSON.parse(raw)) : new Set<string>();
    } catch {
      return new Set<string>();
    }
  });

  const [showStarred, setShowStarred] = useState(false);

  // Persist to localStorage whenever the set changes
  useEffect(() => {
    try {
      localStorage.setItem(storageKey, JSON.stringify([...starred]));
    } catch {
      // Ignore quota errors
    }
  }, [starred, storageKey]);

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
