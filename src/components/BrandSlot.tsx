import { LogoDrop } from "./LogoDrop";
import type { BrandState } from "../hooks/useBrand";

/** The Brand's one home: logo + name, same place in every mode. */
export function BrandSlot({ brand }: { brand: BrandState }) {
  return (
    <>
      <LogoDrop
        svg={brand.logoSvg}
        onLoad={brand.setLogoSvg}
        onClear={() => brand.setLogoSvg(null)}
        onScaleChange={brand.setLogoScale}
        logoScale={brand.logoScale}
      />
      <input
        className="flex-shrink-0 w-40 bg-surface-4 text-fg text-sm rounded-md px-3 h-9 outline-none
                   placeholder:text-fg-3 focus:ring-1 focus:ring-border-default select-text"
        value={brand.name}
        onChange={(e) => brand.setName(e.target.value)}
        placeholder="Brand name…"
        maxLength={30}
        spellCheck={false}
      />
    </>
  );
}
