import { fontFamily } from "../../../lib/fontFace";
import type { FontInfo } from "../../../hooks/useFonts";
import type { OklchColor } from "../../../utils/oklch";
import { oklchToCss } from "../../../utils/oklch";

interface ColorCardProps {
  font: FontInfo | null;
  bgColor: OklchColor;
  fgColor: string;
  badge: string;
  badgeColor?: string;
  isWorking: boolean;
  isPulsing?: boolean;
  dimmed?: boolean;
  brandName?: string;
  logoSvg?: string | null;
  isLogoCard?: boolean;
  onClick: () => void;
}

export function ColorCard({
  font,
  bgColor,
  fgColor,
  badge,
  badgeColor,
  isWorking,
  isPulsing,
  dimmed,
  brandName,
  logoSvg,
  isLogoCard,
  onClick,
}: ColorCardProps) {
  const displayText = brandName || (font ? font.font_family : "");

  return (
    <div
      className="aspect-[4/3] rounded-xl p-5 flex flex-col justify-between relative group cursor-pointer shadow-lg"
      style={{
        backgroundColor: oklchToCss(bgColor),
        color: fgColor,
        boxShadow: isWorking
          ? "0 0 0 2px rgba(217,119,54,0.6), 0 0 12px rgba(217,119,54,0.2), 0 10px 15px -3px rgba(0,0,0,0.3)"
          : undefined,
        opacity: dimmed ? 0.3 : 1,
        filter: dimmed ? "saturate(0.3)" : undefined,
        transform: isPulsing ? "scale(1.02)" : "scale(1)",
        transition: "transform var(--dur-micro) var(--ease-hover), box-shadow var(--dur-normal) var(--ease-hover), opacity var(--dur-normal) var(--ease-hover), filter var(--dur-normal) var(--ease-hover)",
      }}
      onClick={onClick}
    >
      {/* Badge */}
      <div className="absolute top-4 right-4">
        <div
          className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border uppercase"
          style={{
            fontSize: "var(--text-badge)",
            letterSpacing: "var(--track-caps)",
            background: "rgba(0,0,0,0.15)",
            borderColor: "rgba(0,0,0,0.05)",
            color: badgeColor || fgColor,
          }}
        >
          {badge}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 flex items-center justify-center overflow-hidden">
        {isLogoCard && logoSvg ? (
          <div className="flex flex-col items-center gap-2">
            <div
              className="h-12 flex items-center justify-center"
              style={{ color: fgColor }}
              dangerouslySetInnerHTML={{ __html: logoSvg }}
            />
            {displayText && (
              <span className="text-[18px] font-semibold tracking-tight leading-none text-center truncate max-w-full px-2">
                {displayText}
              </span>
            )}
          </div>
        ) : (
          <span
            className="text-[42px] tracking-tight leading-none text-center truncate max-w-full px-2"
            style={font ? { fontFamily: fontFamily(font.file_path) } : undefined}
          >
            {displayText}
          </span>
        )}
      </div>

      {/* Font info */}
      <div>
        <div className="font-medium truncate" style={{ fontSize: "var(--text-ui)", opacity: 0.9 }}>
          {isLogoCard ? "Logo" : font ? font.font_family : ""}
        </div>
        <div className="font-mono mt-0.5" style={{ fontSize: "var(--text-label)", opacity: 0.6 }}>
          {isLogoCard ? "Brand Mark" : font ? `${font.weight} · ${font.classification.category}` : ""}
        </div>
      </div>
    </div>
  );
}
