#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .scratch
fixture_dir=$(mktemp -d "$PWD/.scratch/schema-lint.XXXXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
artifact=$(swift run SchemaFixture "$fixture_dir")
python3 scripts/lint-bedrock-schemas.py "$artifact"
