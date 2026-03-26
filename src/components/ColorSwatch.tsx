import { useState, useCallback, useEffect } from "react";
import { HexColorPicker } from "react-colorful";
import { Menu } from "bloom-menu";

const DARK_BG = "#000000";
const DARK_FG = "#ffffff";
const LIGHT_BG = "#ffffff";
const LIGHT_FG = "#000000";

function isValidHex(hex: string) {
  return /^#[0-9a-fA-F]{6}$/.test(hex);
}

interface Props {
  bgColor: string;
  fgColor: string;
  onChangeBg: (hex: string) => void;
  onChangeFg: (hex: string) => void;
}

function ColorPickerPanel({
  label,
  color,
  onChange,
}: {
  label: string;
  color: string;
  onChange: (hex: string) => void;
}) {
  const [inputVal, setInputVal] = useState(color);

  // Sync input when color changes externally (e.g. clicking Dark/Light)
  useEffect(() => {
    setInputVal(color);
  }, [color]);

  const handlePickerChange = useCallback(
    (hex: string) => {
      setInputVal(hex);
      onChange(hex);
    },
    [onChange]
  );

  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const val = e.target.value;
      setInputVal(val);
      const normalized = val.startsWith("#") ? val : `#${val}`;
      if (isValidHex(normalized)) onChange(normalized);
    },
    [onChange]
  );

  const handleInputBlur = useCallback(() => {
    const normalized = inputVal.startsWith("#") ? inputVal : `#${inputVal}`;
    if (!isValidHex(normalized)) setInputVal(color);
    else setInputVal(normalized);
  }, [inputVal, color]);

  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-[10px] text-neutral-500 font-mono uppercase tracking-widest">
        {label}
      </span>
      <div className="compact-picker">
        <HexColorPicker color={color} onChange={handlePickerChange} style={{ width: "100%" }} />
      </div>
      <div className="flex items-center gap-2">
        <div
          className="w-5 h-5 rounded flex-shrink-0"
          style={{
            backgroundColor: color,
            boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.15)",
          }}
        />
        <input
          className="flex-1 bg-neutral-800 text-white text-xs font-mono rounded px-2 h-7
                     outline-none focus:ring-1 focus:ring-neutral-600 uppercase"
          value={inputVal.toUpperCase()}
          onChange={handleInputChange}
          onBlur={handleInputBlur}
          maxLength={7}
          spellCheck={false}
        />
      </div>
    </div>
  );
}

export function ColorControls({ bgColor, fgColor, onChangeBg, onChangeFg }: Props) {
  const isDark = bgColor === DARK_BG && fgColor === DARK_FG;
  const isLight = bgColor === LIGHT_BG && fgColor === LIGHT_FG;
  const isCustom = !isDark && !isLight;

  const btnBase =
    "flex items-center gap-1 h-7 px-2.5 rounded text-[11px] font-mono transition-all cursor-pointer flex-shrink-0";
  const btnActive = "bg-neutral-700 text-white";
  const btnInactive = "text-neutral-500 hover:text-neutral-300";

  return (
    <div className="flex items-center gap-1 flex-shrink-0">
      {/* Dark */}
      <button
        onClick={() => { onChangeBg(DARK_BG); onChangeFg(DARK_FG); }}
        className={[btnBase, isDark ? btnActive : btnInactive].join(" ")}
        title="Dark mode"
      >
        <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" stroke="none">
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
        </svg>
        Dark
      </button>

      {/* Light */}
      <button
        onClick={() => { onChangeBg(LIGHT_BG); onChangeFg(LIGHT_FG); }}
        className={[btnBase, isLight ? btnActive : btnInactive].join(" ")}
        title="Light mode"
      >
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
          <circle cx="12" cy="12" r="4" />
          <line x1="12" y1="2" x2="12" y2="4" />
          <line x1="12" y1="20" x2="12" y2="22" />
          <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
          <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
          <line x1="2" y1="12" x2="4" y2="12" />
          <line x1="20" y1="12" x2="22" y2="12" />
          <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
          <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
        </svg>
        Light
      </button>

      {/* Custom — opens color picker */}
      <Menu.Root direction="top" anchor="end">
        <Menu.Container
          buttonSize={{ width: 74, height: 28 }}
          menuWidth={196}
          menuRadius={10}
          buttonRadius={6}
          className="bg-neutral-900 ring-1 ring-neutral-700 shadow-2xl"
        >
          <Menu.Trigger>
            <div
              className={[
                "flex items-center justify-center gap-1.5 w-full h-full px-2 rounded text-[11px] font-mono cursor-pointer transition-all",
                isCustom ? "bg-neutral-700 text-white" : "text-neutral-500 hover:text-neutral-300",
              ].join(" ")}
            >
              <div className="flex flex-shrink-0">
                <div
                  className="w-2.5 h-2.5 rounded-l-sm"
                  style={{ backgroundColor: bgColor, boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.15)" }}
                />
                <div
                  className="w-2.5 h-2.5 rounded-r-sm"
                  style={{ backgroundColor: fgColor, boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.15)" }}
                />
              </div>
              Custom
            </div>
          </Menu.Trigger>

          <Menu.Content>
            <div className="p-3 flex flex-col gap-3">
              {/* Preview strip */}
              <div
                className="rounded px-2.5 py-1.5 text-xs font-mono flex items-center justify-between"
                style={{ backgroundColor: bgColor, color: fgColor }}
              >
                <span>Aa Bb</span>
                <span className="opacity-40 text-[10px]">Preview</span>
              </div>

              <ColorPickerPanel label="Background" color={bgColor} onChange={onChangeBg} />
              <ColorPickerPanel label="Foreground" color={fgColor} onChange={onChangeFg} />
            </div>
          </Menu.Content>
        </Menu.Container>
      </Menu.Root>
    </div>
  );
}
