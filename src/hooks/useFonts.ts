import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface Classification {
  category: "sans-serif" | "serif" | "script" | "decorative" | "monospace";
  style: "normal" | "italic";
  width: "condensed" | "normal" | "extended";
}

export interface FontInfo {
  file_name: string;
  file_path: string;
  font_family: string;
  weight: number;
  source: "system" | "library" | "user";
  classification: Classification;
}

export function useFonts() {
  const [fonts, setFonts] = useState<FontInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    invoke<FontInfo[]>("get_system_fonts")
      .then(setFonts)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }, []);

  return { fonts, loading, error };
}
