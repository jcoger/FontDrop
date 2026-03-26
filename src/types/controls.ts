export interface Controls {
  fontSize: number;       // px, range 12–120, default 32
  letterSpacing: number;  // em, range -0.05–0.3, default 0
  fontWeight: number;     // range 100–900 step 100, default 400
  bgColor: string;        // hex
  fgColor: string;        // hex
}

export const DEFAULT_CONTROLS: Controls = {
  fontSize: 32,
  letterSpacing: 0,
  fontWeight: 400,
  bgColor: "#000000",
  fgColor: "#ffffff",
};
