import { useState, useCallback } from "react";
import type { OklchColor } from "../../utils/oklch";
import type { MethodName } from "./types";

// ── Types ────────────────────────────────────────────────────────────

export interface CollectionItem {
  id: string;
  bg: OklchColor;
  fg: OklchColor;
  fontName: string;
  fontWeight: string;
  fontCategory: string;
  sourceMode: MethodName;
  savedAt: string; // ISO string
}

// ── Color key (same rounding as spotlight) ───────────────────────────

export function collectionColorKey(bg: OklchColor, fg: OklchColor): string {
  return `${bg.l.toFixed(2)}.${bg.c.toFixed(2)}.${Math.round(bg.h)}|${fg.l.toFixed(2)}.${fg.c.toFixed(2)}.${Math.round(fg.h)}`;
}

// ── Storage ──────────────────────────────────────────────────────────

const LS_KEY = "fontdrop-collection";

function loadCollection(): CollectionItem[] {
  try {
    const raw = localStorage.getItem(LS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveCollection(items: CollectionItem[]): void {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(items));
  } catch { /* quota exceeded — silently ignore */ }
}

// ── Hook ─────────────────────────────────────────────────────────────

export function useCollection() {
  const [items, setItems] = useState<CollectionItem[]>(loadCollection);

  /** Set of color keys for fast dedup lookup */
  const savedKeys = new Set(items.map((item) => collectionColorKey(item.bg, item.fg)));

  const addItem = useCallback((item: Omit<CollectionItem, "id" | "savedAt">): { status: "added" | "duplicate"; id: string } => {
    const key = collectionColorKey(item.bg, item.fg);
    // If duplicate, find and return existing ID
    if (savedKeys.has(key)) {
      const existing = items.find((i) => collectionColorKey(i.bg, i.fg) === key);
      return { status: "duplicate", id: existing?.id || "" };
    }

    const newItem: CollectionItem = {
      ...item,
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      savedAt: new Date().toISOString(),
    };

    setItems((prev) => {
      const next = [...prev, newItem];
      saveCollection(next);
      return next;
    });
    return { status: "added", id: newItem.id };
  }, [savedKeys, items]);

  const removeByColorKey = useCallback((bg: OklchColor, fg: OklchColor) => {
    const key = collectionColorKey(bg, fg);
    setItems((prev) => {
      const next = prev.filter((item) => collectionColorKey(item.bg, item.fg) !== key);
      saveCollection(next);
      return next;
    });
  }, []);

  const isSaved = useCallback((bg: OklchColor, fg: OklchColor): boolean => {
    return savedKeys.has(collectionColorKey(bg, fg));
  }, [savedKeys]);

  const removeById = useCallback((id: string) => {
    setItems((prev) => {
      const next = prev.filter((item) => item.id !== id);
      saveCollection(next);
      return next;
    });
  }, []);

  const restoreItem = useCallback((item: CollectionItem) => {
    setItems((prev) => {
      const next = [...prev, item];
      saveCollection(next);
      return next;
    });
  }, []);

  const clear = useCallback(() => {
    setItems([]);
    saveCollection([]);
  }, []);

  return { items, count: items.length, addItem, removeByColorKey, removeById, restoreItem, isSaved, clear };
}
