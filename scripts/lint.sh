#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not found. Install with: brew install swiftlint"
  echo "Skipping lint (treat as pass for environments without swiftlint)."
  exit 0
fi

echo "Running swiftlint..."
# Lint staged? No — lint whole project. Pre-commit hook filters to staged files.
swiftlint lint --strict --config .swiftlint.yml
echo "swiftlint passed."
