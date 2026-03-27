// ── ColorExplorer localStorage key registry ───────────────────────────
//
// All keys live here so name collisions are caught at a glance and
// refactoring a key never requires hunting through multiple files.

export const LS_KEYS = {
  method: "fontdrop-ce-method",

  hueLock: {
    hue:          "fontdrop-ce-huelock-hue",
    steps:        "fontdrop-ce-huelock-steps",
    curveMidY:    "fontdrop-ce-huelock-curveMidY",
    chromaMode:   "fontdrop-ce-huelock-chromaMode",
    fixedChroma:  "fontdrop-ce-huelock-fixedChroma",
    accentEnabled:"fontdrop-ce-huelock-accentEnabled",
    accentHue:    "fontdrop-ce-huelock-accentHue",
    accentL:      "fontdrop-ce-huelock-accentL",
  },

  corridor: {
    hCenter:      "fontdrop-ce-corridor-hCenter",
    width:        "fontdrop-ce-corridor-width",
    chromaMin:    "fontdrop-ce-corridor-chromaMin",
    chromaMax:    "fontdrop-ce-corridor-chromaMax",
    lRange:       "fontdrop-ce-corridor-lRange",
    count:        "fontdrop-ce-corridor-count",
  },

  contrastSafe: {
    primary:      "fontdrop-ce-cs-primary",
    primaryHex:   "fontdrop-ce-cs-primaryHex",
    lRange:       "fontdrop-ce-cs-lRange",
    cRange:       "fontdrop-ce-cs-cRange",
    hueMode:      "fontdrop-ce-cs-hueMode",
    threshold:    "fontdrop-ce-cs-threshold",
    density:      "fontdrop-ce-cs-density",
    fgLock:       "fontdrop-ce-cs-fgLock",
  },

  roleBuilder: {
    primary:         "fontdrop-ce-rb-primary",
    primaryHex:      "fontdrop-ce-rb-primaryHex",
    theme:           "fontdrop-ce-rb-theme",
    accentOffset:    "fontdrop-ce-rb-accentOffset",
    accentChromaMult:"fontdrop-ce-rb-accentChromaMult",
  },

  extract: {
    clusterCount:    "fontdrop-ce-ex-clusterCount",
    remap:           "fontdrop-ce-ex-remap",
    lightnessLock:   "fontdrop-ce-ex-lightnessLock",
    lockedL:         "fontdrop-ce-ex-lockedL",
  },

  ui: {
    albersExpanded: "fontdrop-albers-expanded",
  },
} as const;

// ── Helpers ───────────────────────────────────────────────────────────

export function lsGet<T>(key: string, fallback: T): T {
  try {
    const v = localStorage.getItem(key);
    return v !== null ? (JSON.parse(v) as T) : fallback;
  } catch {
    return fallback;
  }
}

export function lsSet(key: string, value: unknown): void {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Quota exceeded or private-browsing restriction — silently ignore
  }
}
