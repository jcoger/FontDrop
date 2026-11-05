#!/usr/bin/env bash
# Builds the AppIcon asset from two 1024 px sources with sips:
#   macos/Resources/AppIcon-source.png        the full art, for 32x32@2x (64 px) and every larger size
#   macos/Resources/AppIcon-small-source.png  a simpler drawing, for the three smallest files (16, 16@2x, 32)
# To change the icon: replace a source PNG (1024 x 1024, with its own rounded square and transparent corners),
# then run  macos/scripts/make-app-icon.sh. Nothing else in the project refers to the icon.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_FULL="$HERE/Resources/AppIcon-source.png"
SRC_SMALL="$HERE/Resources/AppIcon-small-source.png"
SET="$HERE/Sources/FontDrop/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
# point size, scale
for spec in "16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2"; do
  set -- $spec
  pt=$1; scale=$2; px=$((pt * scale))
  suffix=""; if [[ $scale == 2 ]]; then suffix="@2x"; fi
  name="icon_${pt}x${pt}${suffix}.png"
  SRC="$SRC_FULL"; if (( px <= 32 )); then SRC="$SRC_SMALL"; fi
  sips -z "$px" "$px" "$SRC" --out "$SET/$name" >/dev/null
done
echo "wrote the AppIcon set to $SET"
