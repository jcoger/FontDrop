# FontDrop

A native Mac app for choosing the type for a brand.

You pick a Display face for headlines and a Text face for reading. FontDrop shows the pair in real layouts, sets the sizes and spacing from the fonts' own measurements, and exports the result as CSS, Tailwind or Paper tokens. It reads every font already on your Mac.

## Install

1. Download `FontDrop-<version>.dmg` from [Releases](../../releases).
2. Open the DMG and drag FontDrop to Applications.
3. Open FontDrop. Releases are signed and notarized by Apple, so macOS opens them without a warning. (An ad-hoc test build asks you to right-click and choose Open.)

Needs macOS 14 or later on an Apple Silicon Mac.

## First run

FontDrop scans the font folders on your Mac (`/System/Library/Fonts`, `/Library/Fonts` and `~/Library/Fonts`). It shows fonts as it reads them, so you can start at once. The first scan takes about a minute for a large library. Later launches update quietly in the background.

When you pick your first face, FontDrop asks which brand it is for. Everything you choose is saved per brand.

## The loop

1. **Display.** Browse the grid in your brand name, narrow it with the filter bar, and press Return (or Use for Display) on a face.
2. **Text.** FontDrop ranks faces that pair with your Display face and says why. Preview any face with Space. Press Return to use one.
3. **Set.** See the pair on a poster, an article or an app screen. Turn the ratio dial or type exact numbers for Body, Measure and Line height.
4. **Export.** File > Export copies CSS, Tailwind or Paper tokens, writes a one-page spec as PDF and PNG, or copies a license list.

Everything works from the keyboard. Every command is in a menu with its shortcut: Command-1, 2, 3 switch screens, Command-F finds a font, Command-Z undoes a face choice, Command-Plus and Command-Minus zoom the stage, Shift-Command-C copies the CSS.

## Build from source

Needs Xcode, Rust (`rustup`) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
core/build-swift.sh        # the Rust engine as an XCFramework plus Swift bindings (about 3 minutes the first time)
macos/build.sh --run       # builds macos/build/FontDrop.app and opens it
macos/build.sh --test      # the Mac app's tests
(cd core && cargo test)    # the engine's tests
make release-adhoc         # a DMG for testing; see docs/release.md for the signed one
```

Layout: `core/` is the engine (Rust: library database, scan, classifier, pairing). `macos/` is the SwiftUI app. `docs/` holds the research, plans and copy rules. Developer flags for screenshots and benchmarks are listed at the top of `macos/Sources/FontDrop/Bench.swift`.

## How pairing works

FontDrop reads each font's own data: family name, x-height, cap height, stroke contrast, serifs, letter construction, vendor and designer. It scores candidates with lenses drawn from the typography literature, and every suggestion carries its evidence: what was measured, which source backs it, and how strongly that source states it. It shares reasoning. The designer decides.

- Rules and sources: [`docs/research/pairing-rulebook.md`](docs/research/pairing-rulebook.md)
- Benchmark of real-world pairs: [`docs/research/benchmarks/`](docs/research/benchmarks/)

## Standing on the shoulders of

The pairing lenses come from close reading of these works. Any mistakes in turning them into code are ours.

- Tim Brown, *Flexible Typesetting* (and *Combining Typefaces*, through Matej Latin's method)
- Matej Latin, *Better Web Typography for a Better Web* and its cheat sheets
- Elliot Jay Stocks, *Universal Principles of Typography*, including Indra Kupferschmid's skeleton / flesh / skin font matrix
- Jeremiah Shoaf (Typewolf), *Flawless Typography Checklist* and his font-combination guides
- Smashing Magazine authors: Dan Mayer, Douglas Bonneville, Marko Dugonjić, Dan Reynolds
- Adam Wathan and Steve Schoger, *Refactoring UI*
- Beth Tondreau, *Layout Essentials*; Timothy Samara, *Making and Breaking the Grid*
- Nguyen Le, *Typography Playbook*; Yesenia Perez-Cruz, *Expressive Design Systems*
- Research: Jiang et al., "Visual Font Pairing" (2019); Jack Qiao's Fontjoy; Google Fonts' public metadata
- Butterick's *Practical Typography* and Typewolf's body-text picks feed the Recommended for text list.

## Licences

- FontDrop's code: MIT, see [LICENSE](LICENSE).
- Doto and Geist Mono, bundled for the interface, are under the SIL Open Font License 1.1. The licence texts are in `macos/Sources/FontDrop/Resources/Fonts/`.
- Fonts on your Mac stay yours. FontDrop reads them and never copies or uploads them. The license list export tells you which of your picks need a license before you ship.

## History

FontDrop began as a Tauri and React app. That app was removed in round R7 of the SwiftUI rewrite. Its history is in git, before the commit "R7".

© 2026 Dyno Labs
