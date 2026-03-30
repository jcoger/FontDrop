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
    fgPreset:     "fontdrop-ce-hue-fgpreset",
    fgLOverride:  "fontdrop-ce-hue-fgloverride",
    fgCOverride:  "fontdrop-ce-hue-fgcoverride",
    variety:      "fontdrop-ce-hue-variety",
  },

  corridor: {
    hCenter:        "fontdrop-ce-corridor-hCenter",
    width:          "fontdrop-ce-corridor-width",
    chromaMin:      "fontdrop-ce-corridor-chromaMin",
    chromaMax:      "fontdrop-ce-corridor-chromaMax",
    chromaFloor:    "fontdrop-ce-corridor-chromaFloor",
    chromaCeiling:  "fontdrop-ce-corridor-chromaCeiling",
    lRange:         "fontdrop-ce-corridor-lRange",
    count:          "fontdrop-ce-corridor-count",
    variety:        "fontdrop-ce-corridor-variety",
    hCenter2:       "fontdrop-ce-corridor-hcenter2",
    chromaMin2:     "fontdrop-ce-corridor-chromamin2",
    chromaMax2:     "fontdrop-ce-corridor-chromamax2",
    chromaFloor2:   "fontdrop-ce-corridor-chromaFloor2",
    chromaCeiling2: "fontdrop-ce-corridor-chromaCeiling2",
    width2:         "fontdrop-ce-corridor-width2",
    accentWeight:   "fontdrop-ce-corridor-accentweight",
    hueOffset:          "fontdrop-ce-corridor-hueoffset",
    hueWidth:           "fontdrop-ce-corridor-huewidth",
    accentChromaOffset: "fontdrop-ce-corridor-accentchromaoffset",
    lMidBias:           "fontdrop-ce-corridor-lmidbias",
    lockComplement:     "fontdrop-ce-corridor-lockcomplement",
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

  macroKnob: {
    knob:          "fontdrop-ce-macroknob-knob",
    hue:           "fontdrop-ce-macroknob-hue",
    count:         "fontdrop-ce-macroknob-count",
    chaos:         "fontdrop-ce-macroknob-chaos",
    spread:        "fontdrop-ce-macroknob-spread",
    variMode:      "fontdrop-ce-macroknob-varimode",
    relMode:       "fontdrop-ce-macroknob-relmode",
    contrastlock:  "fontdrop-ce-macroknob-contrastlock",
  },

  wordPicker: {
    tags:    "fontdrop-ce-wordpicker-tags",
    drift:   "fontdrop-ce-wordpicker-drift",
    count:   "fontdrop-ce-wordpicker-count",
    variety: "fontdrop-ce-wordpicker-variety",
    accent:  "fontdrop-ce-wordpicker-accent",
  },

  extract: {
    clusterCount:    "fontdrop-ce-ex-clusterCount",
    remap:           "fontdrop-ce-ex-remap",
    lightnessLock:   "fontdrop-ce-ex-lightnessLock",
    lockedL:         "fontdrop-ce-ex-lockedL",
    cachedClusters:  "fontdrop-ce-ex-cachedClusters",
    cachedThumb:     "fontdrop-ce-ex-cachedThumb",
  },

  ui: {
    albersOpen:     "fontdrop-albers-open",
    contrastLevel:  "fontdrop-contrast-level",
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
