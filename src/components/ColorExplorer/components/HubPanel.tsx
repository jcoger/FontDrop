import { useState, useEffect } from "react";
import { oklchToCss, oklchToHex, contrastRatio } from "../../../utils/oklch";
import type { CollectionItem } from "../useCollection";
import { exportCollectionJSON, downloadFile, todayStr } from "../exportUtils";

interface HubPanelProps {
  items: CollectionItem[];
  brandName: string;
  onRemove: (id: string) => void;
  onRestore: (item: CollectionItem) => void;
  onClearAll: () => void;
  onSendToBrandKit: (item: CollectionItem) => void;
  onClose: () => void;
}

export function HubPanel({
  items,
  brandName,
  onRemove,
  onRestore,
  onClearAll,
  onSendToBrandKit,
  onClose,
}: HubPanelProps) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [undoItem, setUndoItem] = useState<CollectionItem | null>(null);
  const [undoTimer, setUndoTimer] = useState<ReturnType<typeof setTimeout> | null>(null);

  const selected = selectedId ? items.find((i) => i.id === selectedId) : null;

  // Clear undo on unmount
  useEffect(() => () => { if (undoTimer) clearTimeout(undoTimer); }, [undoTimer]);

  function handleDelete(item: CollectionItem) {
    onRemove(item.id);
    setUndoItem(item);
    if (undoTimer) clearTimeout(undoTimer);
    const t = setTimeout(() => setUndoItem(null), 3000);
    setUndoTimer(t);
    if (selectedId === item.id) setSelectedId(null);
  }

  function handleUndo() {
    if (!undoItem) return;
    onRestore(undoItem);
    setUndoItem(null);
    if (undoTimer) clearTimeout(undoTimer);
  }

  function handleClearAll() {
    if (!confirm("Remove all saved cards?")) return;
    onClearAll();
    setSelectedId(null);
  }

  // Sort most recent first
  const sorted = [...items].sort((a, b) => new Date(b.savedAt).getTime() - new Date(a.savedAt).getTime());

  // ── Empty state ────────────────────────────────────────────────
  if (items.length === 0) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-3 text-center p-8">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-fg-3">
          <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
        </svg>
        <span style={{ fontSize: "var(--text-ui)", color: "var(--c-text-3)" }}>
          No saved cards yet
        </span>
        <span style={{ fontSize: "var(--text-body)", color: "var(--c-text-4)" }}>
          Hover any card in the explorer and click the bookmark icon to save
        </span>
        <button
          className="font-mono cursor-pointer mt-2"
          style={{ fontSize: "var(--text-body)", color: "var(--c-accent)" }}
          onClick={onClose}
        >
          ← Back to Explorer
        </button>
      </div>
    );
  }

  // ── Hub layout ─────────────────────────────────────────────────
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* Top bar */}
      <div className="flex items-center justify-between px-6 py-3 border-b border-border-default bg-surface-2 shrink-0">
        <div className="flex items-center gap-3">
          <button
            className="font-mono cursor-pointer"
            style={{ fontSize: "var(--text-body)", color: "var(--c-text-3)" }}
            onClick={onClose}
          >
            ← Back
          </button>
          <span className="font-mono" style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>
            {items.length} saved card{items.length !== 1 ? "s" : ""}
          </span>
        </div>
        <div className="flex items-center gap-3">
          <button
            className="font-mono uppercase cursor-pointer"
            style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}
            onClick={() => {
              const json = exportCollectionJSON(items);
              downloadFile(`fontdrop-collection-${todayStr()}.json`, json);
            }}
          >
            Export All
          </button>
          <button
            className="font-mono uppercase cursor-pointer"
            style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}
            onClick={handleClearAll}
          >
            Clear All
          </button>
        </div>
      </div>

      {/* Main content */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left: swatch grid */}
        <div className="flex-1 overflow-y-auto p-6">
          <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(160px, 1fr))" }}>
            {sorted.map((item) => {
              const bgCss = oklchToCss(item.bg);
              const fgCss = oklchToCss(item.fg);
              const metaCss = item.bg.l > 0.55 ? "rgba(0,0,0,0.55)" : "rgba(255,255,255,0.55)";
              const isSelected = selectedId === item.id;
              return (
                <div
                  key={item.id}
                  className="group relative rounded-lg cursor-pointer overflow-hidden"
                  style={{
                    backgroundColor: bgCss,
                    height: 120,
                    boxShadow: isSelected ? `0 0 0 2px ${bgCss}, 0 0 12px ${bgCss}60` : undefined,
                    transition: "box-shadow var(--dur-fast) var(--ease-hover)",
                  }}
                  onClick={() => setSelectedId(isSelected ? null : item.id)}
                >
                  {/* Source mode label */}
                  <div className="absolute top-2 left-2">
                    <span
                      className="font-mono uppercase px-1.5 py-0.5 rounded backdrop-blur-sm"
                      style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: metaCss, background: "rgba(0,0,0,0.1)" }}
                    >
                      {item.sourceMode}
                    </span>
                  </div>

                  {/* Delete button */}
                  <button
                    className="absolute top-2 right-2 w-5 h-5 rounded flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer"
                    style={{ background: "rgba(0,0,0,0.25)", color: metaCss }}
                    onClick={(e) => { e.stopPropagation(); handleDelete(item); }}
                    aria-label="Remove from collection"
                  >
                    <svg width="8" height="8" viewBox="0 0 10 10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
                      <path d="M2 2l6 6M8 2l-6 6" />
                    </svg>
                  </button>

                  {/* Brand name */}
                  <div className="absolute inset-0 flex items-center justify-center px-3">
                    <span
                      className="text-[24px] tracking-tight leading-none text-center truncate max-w-full font-semibold"
                      style={{ color: fgCss }}
                    >
                      {brandName || item.fontName}
                    </span>
                  </div>

                  {/* Font name */}
                  <div className="absolute bottom-2 left-2 right-2">
                    <span className="font-mono truncate block" style={{ fontSize: "var(--text-badge)", color: metaCss }}>
                      {item.fontName}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right: detail panel */}
        <div className="w-[320px] border-l border-border-default bg-surface-1 shrink-0 overflow-y-auto">
          {selected ? (
            <div className="flex flex-col h-full">
              {/* Large preview */}
              <div
                className="h-48 flex items-center justify-center px-6 shrink-0"
                style={{ backgroundColor: oklchToCss(selected.bg) }}
              >
                <span
                  className="text-[42px] tracking-tight leading-none text-center truncate max-w-full"
                  style={{ color: oklchToCss(selected.fg) }}
                >
                  {brandName || selected.fontName}
                </span>
              </div>

              {/* Details */}
              <div className="p-5 flex flex-col gap-4 flex-1">
                {/* Font info */}
                <div>
                  <span className="font-medium" style={{ fontSize: "var(--text-ui)", color: "var(--c-text)" }}>
                    {selected.fontName}
                  </span>
                  <div className="font-mono mt-0.5" style={{ fontSize: "var(--text-label)", color: "var(--c-text-3)" }}>
                    {selected.fontWeight} · {selected.fontCategory}
                  </div>
                </div>

                {/* BG color */}
                <div>
                  <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Background</div>
                  <div className="flex items-center gap-2">
                    <div className="w-5 h-5 rounded border border-border-strong" style={{ backgroundColor: oklchToCss(selected.bg) }} />
                    <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>
                      {oklchToHex(selected.bg)}
                    </span>
                  </div>
                  <div className="font-mono mt-0.5" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
                    oklch({selected.bg.l.toFixed(2)}, {selected.bg.c.toFixed(3)}, {Math.round(selected.bg.h)})
                  </div>
                </div>

                {/* FG color */}
                <div>
                  <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Foreground</div>
                  <div className="flex items-center gap-2">
                    <div className="w-5 h-5 rounded border border-border-strong" style={{ backgroundColor: oklchToCss(selected.fg) }} />
                    <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>
                      {oklchToHex(selected.fg)}
                    </span>
                  </div>
                  <div className="font-mono mt-0.5" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
                    oklch({selected.fg.l.toFixed(2)}, {selected.fg.c.toFixed(3)}, {Math.round(selected.fg.h)})
                  </div>
                </div>

                {/* Contrast */}
                <div>
                  <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Contrast</div>
                  <span className="font-mono" style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>
                    {contrastRatio(selected.bg, selected.fg).toFixed(1)}:1
                  </span>
                </div>

                {/* Source */}
                <div>
                  <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Source</div>
                  <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
                    {selected.sourceMode} · {new Date(selected.savedAt).toLocaleDateString()}
                  </span>
                </div>

                {/* Send to Build System */}
                <button
                  className="mt-auto px-4 py-2 rounded font-semibold cursor-pointer transition-colors"
                  style={{ fontSize: "var(--text-body)", backgroundColor: "var(--c-text)", color: "var(--surface-0)" }}
                  onClick={() => onSendToBrandKit(selected)}
                >
                  Send to Brand Kit →
                </button>
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-center h-full">
              <span className="font-mono italic" style={{ fontSize: "var(--text-body)", color: "var(--c-text-4)" }}>
                Select a saved card to see details
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Undo toast */}
      {undoItem && (
        <div className="fixed bottom-20 left-1/2 -translate-x-1/2 z-50 bg-surface-4 text-fg text-xs font-medium px-4 py-2 rounded-md shadow-lg flex items-center gap-3">
          Card removed
          <button
            className="font-mono uppercase cursor-pointer"
            style={{ fontSize: "var(--text-badge)", color: "var(--c-accent)" }}
            onClick={handleUndo}
          >
            Undo
          </button>
        </div>
      )}
    </div>
  );
}
