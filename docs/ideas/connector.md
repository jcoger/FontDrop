# Idea: FontDrop as a connector for Claude and ChatGPT

Status: idea, not planned. Captured 2026-10-21 from Jarrett.

## The outcome

A designer working with Claude (in Paper, in a chat, in code) can ask "what reads well under this headline face?" and get answers from **their own installed fonts**, with the reasons, without leaving the tool. Claude can then set the type, or just suggest it. The designer stays in charge of the choice.

## Why FontDrop is the right place for it

- It already knows what's installed, classified, measured (x-height, skeleton, serif, contrast, vendor, designer).
- The pairing engine returns structured results: score, group, reasons. That's the shape a tool call needs.
- The type-set skill holds the reasoning. FontDrop holds the data. A connector joins them.

## Shape (MCP server, local)

The Mac app runs a local MCP server (stdio or localhost). Tools, all read-only except where noted:

| Tool | Does | Returns |
|---|---|---|
| `search_fonts` | Find installed families by name, kind, skeleton, trait | Families with measured traits |
| `suggest_partners` | For a font and a job (display, reading, ui, mono) | Ranked partners in groups (contrast, uniform, designed together), each with its reasons and evidence strength |
| `explain_pair` | Why two faces work or don't | The lenses that pass and fail, with sources |
| `set_type` | Build a scale for a pair: base size, ratio, measure, line height, x-height correction, opsz values | Tokens (CSS variables, Tailwind theme) + the reasoning per value |
| `brand_type_system` (write) | Save the chosen system to a brand in FontDrop | Confirmation |

Claude in Paper then applies `set_type` output through Paper's own MCP (family, px sizes, em tracking, `font-variation-settings` for opsz/wdth). Two modes, picked by the designer: **advise** (show options and reasons) or **apply** (set the values and list every one so they can be overridden).

## Guardrails

- Local only. Font files never leave the machine; only names and measurements are shared.
- Licences: trial fonts are welcome while exploring (that is how designers and clients end up buying fonts). Answers mark them as trial with the foundry link, and hand-off lists them under "license before shipping".
- No silent changes: apply mode always reports what it set.

## What has to be true first

1. The engine beats the broad benchmark (docs/research/benchmarks), not just Jarrett's 9 pairs.
2. Every result carries evidence (property, value, source, strength), not just a sentence.
3. User data lives in the app's database, not WebKit storage, so the server and the app see the same brands.
