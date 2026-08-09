#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$ROOT/.githooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "No .githooks directory found at $HOOKS_DIR"
  exit 1
fi

git -C "$ROOT" config core.hooksPath .githooks
echo "Configured core.hooksPath to .githooks"
echo "Pre-commit hook will run swiftlint on staged Swift files."
# Ensure hooks are executable
chmod +x "$HOOKS_DIR"/*
echo "Done."
