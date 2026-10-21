import { useState, useCallback } from "react";

// The Brand: the name and logo being designed for. One saved value, shown in every mode.
// Keeps the old Brand Colors key so an existing brand name carries over.
const LS_NAME = "fontdrop-brand-name";
const LS_LOGO = "fontdrop:brand-logo";
const LS_SCALE = "fontdrop:brand-logo-scale";
const NAME_MAX = 30;

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string | null): void {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // quota (a very large SVG): the brand still works for this session
  }
}

export interface BrandState {
  name: string;
  /** Text for previews: the brand name, or "Fontdrop" when empty. */
  displayName: string;
  setName: (v: string) => void;
  logoSvg: string | null;
  setLogoSvg: (svg: string | null) => void;
  logoScale: number;
  setLogoScale: (v: number) => void;
}

export function useBrand(): BrandState {
  const [name, setNameState] = useState(() => read(LS_NAME) ?? "");
  const [logoSvg, setLogoState] = useState<string | null>(() => read(LS_LOGO));
  const [logoScale, setScaleState] = useState(() => {
    const n = Number(read(LS_SCALE));
    return Number.isFinite(n) && n > 0 ? n : 1.0;
  });

  const setName = useCallback((v: string) => {
    const clamped = v.slice(0, NAME_MAX);
    setNameState(clamped);
    write(LS_NAME, clamped);
  }, []);

  const setLogoSvg = useCallback((svg: string | null) => {
    setLogoState(svg);
    write(LS_LOGO, svg);
  }, []);

  const setLogoScale = useCallback((v: number) => {
    setScaleState(v);
    write(LS_SCALE, String(v));
  }, []);

  return {
    name,
    displayName: name || "Fontdrop",
    setName,
    logoSvg,
    setLogoSvg,
    logoScale,
    setLogoScale,
  };
}
