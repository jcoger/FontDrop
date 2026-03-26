/**
 * Built-in junk exclusion list.
 * Fonts matching these names/prefixes are hidden by default on first launch.
 * Users can unhide them individually via the Excluded manager.
 */

/** Exact family name matches (case-sensitive, matches font_family field) */
export const DEFAULT_EXCLUSION_FAMILIES: string[] = [
  // Apple symbol / dingbat fonts
  "Apple Symbols",
  "Apple Color Emoji",
  "Apple Braille",
  "Apple Chancery",
  "Zapf Dingbats",
  "Wingdings",
  "Wingdings 2",
  "Wingdings 3",
  "Webdings",
  "Bodoni Ornaments",

  // System utility fonts
  "LastResort",
  "Keyboard",

  // CJK — Hiragino
  "Hiragino Kaku Gothic Pro",
  "Hiragino Kaku Gothic ProN",
  "Hiragino Kaku Gothic Std",
  "Hiragino Kaku Gothic StdN",
  "Hiragino Maru Gothic Pro",
  "Hiragino Maru Gothic ProN",
  "Hiragino Mincho Pro",
  "Hiragino Mincho ProN",
  "Hiragino Sans",
  "Hiragino Sans GB",

  // CJK — PingFang
  "PingFang HK",
  "PingFang SC",
  "PingFang TC",

  // CJK — Songti / STFonts
  "Songti SC",
  "Songti TC",
  "STSong",
  "STHeiti",
  "STFangsong",
  "STKaiti",
  "STXihei",
  "STXingkai",
  "STXinwei",
  "STZhongsong",
  "STCaiyun",
  "STHupo",
  "STLiti",

  // CJK — Noto
  "Noto Sans CJK JP",
  "Noto Sans CJK KR",
  "Noto Sans CJK SC",
  "Noto Sans CJK TC",
  "Noto Serif CJK JP",
  "Noto Serif CJK KR",
  "Noto Serif CJK SC",
  "Noto Serif CJK TC",

  // CJK — Apple Li / Biau
  "Apple LiGothic",
  "Apple LiSung",
  "LiHei Pro",
  "LiSong Pro",
  "BiauKai",

  // CJK — other
  "GB18030 Bitmap",

  // Redundant system fonts (prefer "Neue" / "New" variants)
  "Courier",
  "Times",
  "Helvetica",
];

/** Prefix matches — any font_family starting with these strings is excluded */
export const DEFAULT_EXCLUSION_PREFIXES: string[] = [
  ".",           // All dot-prefixed Apple private fonts (.SF Pro, .New York, etc.)
  "Apple SD",    // Apple SD Gothic Neo etc.
  "Aqua Kana",
  "GB18030",
];
