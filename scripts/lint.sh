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
swiftlint lint --config .swiftlint.yml
echo "swiftlint passed."
