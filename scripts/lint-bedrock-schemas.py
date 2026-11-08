#!/usr/bin/env python3
"""Advisory validation of generated feature documents against pinned schemas."""
import io
import json
import pathlib
import sys
import zipfile

from jsonschema import Draft7Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = {
    "features/": "features.json",
    "feature_rules/": "feature_rules.json",
}


def main(archive):
    validators = {}
    for prefix, filename in SCHEMAS.items():
        schema = json.loads((ROOT / "schemas/blockception/behavior" / filename).read_text())
        Draft7Validator.check_schema(schema)
        validator = Draft7Validator(schema)
        if validator.is_valid({}):
            raise RuntimeError(f"Schema {filename} accepts an empty document")
        validators[prefix] = validator
    seen = set()
    failed = False
    with zipfile.ZipFile(archive) as addon:
        for pack_name in addon.namelist():
            if not pack_name.endswith(".mcpack"):
                continue
            with zipfile.ZipFile(io.BytesIO(addon.read(pack_name))) as pack:
                for name in pack.namelist():
                    for prefix, validator in validators.items():
                        if name.startswith(prefix) and name.endswith(".json"):
                            seen.add(prefix)
                            errors = list(validator.iter_errors(json.loads(pack.read(name))))
                            for error in errors:
                                print(f"{name}: {error.json_path}: {error.message}", file=sys.stderr)
                                failed = True
    if seen != set(SCHEMAS):
        raise RuntimeError(f"Missing generated document families: {set(SCHEMAS) - seen}")
    if failed:
        return 1
    print("Generated feature and feature-rule documents match the pinned advisory schemas.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: lint-bedrock-schemas.py <fixture.mcaddon>")
    sys.exit(main(sys.argv[1]))
