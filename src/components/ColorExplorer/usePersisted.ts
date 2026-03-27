import { useState, useEffect } from "react";
import { lsGet, lsSet } from "./storage";

/**
 * A thin wrapper around useState that automatically persists to and
 * restores from localStorage. Replaces the `useState(lsGet(...))` +
 * `useEffect(() => lsSet(...), [value])` pattern used throughout the
 * ColorExplorer.
 *
 * @param key      - The localStorage key (use LS_KEYS from storage.ts)
 * @param fallback - Default value when no persisted value exists
 * @returns        - [value, setter] identical to useState's API
 */
export function usePersisted<T>(
  key: string,
  fallback: T,
): [T, React.Dispatch<React.SetStateAction<T>>] {
  const [value, setValue] = useState<T>(() => lsGet(key, fallback));

  useEffect(() => {
    lsSet(key, value);
  }, [key, value]);

  return [value, setValue];
}
