#!/usr/bin/env bash
# Builds the AppIcon asset from the 1024 px source (macos/Resources/AppIcon-source.png) with sips.
# To change the icon: replace the source PNG (1024 x 1024, with its own rounded square and transparent corners),
# then run  macos/scripts/make-app-icon.sh. Nothing else in the project refers to the icon.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/Resources/AppIcon-source.png"
SET="$HERE/Sources/FontDrop/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
# point size, scale
for spec in "16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2"; do
  set -- $spec
  pt=$1; scale=$2; px=$((pt * scale))
  suffix=""; if [[ $scale == 2 ]]; then suffix="@2x"; fi
  name="icon_${pt}x${pt}${suffix}.png"
  sips -z "$px" "$px" "$SRC" --out "$SET/$name" >/dev/null
done
echo "wrote the AppIcon set to $SET"
