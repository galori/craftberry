#!/usr/bin/env bash
# Renders every icon PixelArtTextureRenderer supports (vanilla materials, plus every
# generated item kind in every palette color) into a single self-contained HTML page
# and opens it. Useful for eyeballing icon-rendering changes without launching the app.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

output="${1:-$repo_root/.build/icon-preview.html}"
mkdir -p "$(dirname "$output")"

swift build --product IconPreview
swift run --skip-build IconPreview "$output"

if [[ "${CI:-}" != "true" ]] && command -v open >/dev/null 2>&1; then
  open "$output"
fi
