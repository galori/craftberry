#!/usr/bin/env bash
# Regenerate the small, reviewed vanilla allowlist from the profile's exact sample commit.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
samples_dir="$repo_root/.scratch/bedrock-samples"
source_commit=$(python3 -c 'import json, pathlib, sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["sourceCommit"])' "$repo_root/Config/vanilla-catalog-allowlist.json")

mkdir -p "$repo_root/.scratch"
if [[ ! -d "$samples_dir/.git" ]]; then
  git init "$samples_dir"
  git -C "$samples_dir" remote add origin https://github.com/Mojang/bedrock-samples.git
fi

current_commit=$(git -C "$samples_dir" rev-parse HEAD 2>/dev/null || true)
if [[ "$current_commit" != "$source_commit" ]]; then
  git -C "$samples_dir" fetch --filter=blob:none --depth=1 origin "$source_commit"
  git -C "$samples_dir" sparse-checkout init --cone
  git -C "$samples_dir" sparse-checkout set behavior_pack/recipes metadata/vanilladata_modules
  git -C "$samples_dir" checkout --detach FETCH_HEAD
fi

mode=--write
if [[ ${1:-} == "--check" ]]; then
  mode=--check
elif [[ $# -gt 0 ]]; then
  echo "usage: scripts/refresh-vanilla-catalog.sh [--check]" >&2
  exit 2
fi

python3 "$repo_root/scripts/generate-vanilla-catalog.py" --samples "$samples_dir" "$mode"
