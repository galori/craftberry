#!/usr/bin/env python3
"""Advisory validation of generated feature documents against pinned schemas."""
import io
import json
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = {
    "features/": pathlib.Path("features.json"),
    "feature_rules/": pathlib.Path("feature_rules.json"),
    "items/": pathlib.Path("items/items.json"),
    "recipes/": pathlib.Path("recipes/recipes.json"),
    "blocks/": pathlib.Path("blocks/blocks.json"),
    "entities/": pathlib.Path("entities/entities.json"),
    "loot_tables/": pathlib.Path("loot_tables/loot_tables.json"),
    "spawn_rules/": pathlib.Path("spawn_rules/spawn_rules.json"),
}
EXCEPTIONS_PATH = ROOT / "schemas/blockception/exceptions.json"


def matches_exception(exception, family, name, error):
    instance_type = exception.get("instanceType")
    if instance_type == "string" and not isinstance(error.instance, str):
        return False
    if instance_type not in (None, "string"):
        raise ValueError(f"Unsupported exception instance type: {instance_type}")
    return (
        exception["family"] == family
        and re.fullmatch(exception["pathPattern"], name)
        and re.fullmatch(exception["jsonPathPattern"], str(error.json_path))
        and exception["validator"] == error.validator
        and exception["messageContains"] in error.message
    )


def main(archive):
    from jsonschema import Draft7Validator

    validators = {}
    for prefix, relative_schema_path in SCHEMAS.items():
        schema_path = ROOT / "schemas/blockception/behavior" / relative_schema_path
        schema = json.loads(schema_path.read_text())
        Draft7Validator.check_schema(schema)
        validator = Draft7Validator(schema)
        validators[prefix] = validator
    seen = set()
    failed = False
    exceptions = json.loads(EXCEPTIONS_PATH.read_text())
    exception_counts = {item["id"]: 0 for item in exceptions}
    allowlist = json.loads((ROOT / "Config/vanilla-catalog-allowlist.json").read_text())
    pinned_sample_paths = {item["path"] for item in allowlist["recipeFormEvidence"]}
    if any(item["samplePath"] not in pinned_sample_paths for item in exceptions):
        raise RuntimeError("Every schema exception must point to a recipe form verified by the pinned sample catalog")
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
                                exception = next((
                                    item for item in exceptions
                                    if matches_exception(item, prefix, name, error)
                                ), None)
                                if exception:
                                    exception_counts[exception["id"]] += 1
                                else:
                                    print(f"{name}: {error.json_path}: {error.message}", file=sys.stderr)
                                    failed = True
    if seen != set(SCHEMAS):
        raise RuntimeError(f"Missing generated document families: {set(SCHEMAS) - seen}")
    for exception in exceptions:
        observed = exception_counts[exception["id"]]
        expected = exception["expectedOccurrences"]
        if observed != expected:
            print(
                f"Schema exception {exception['id']} matched {observed} validation errors; expected {expected}.",
                file=sys.stderr,
            )
            failed = True
    if failed:
        return 1
    print(f"All {len(SCHEMAS)} generated document families match the pinned advisory schemas.")
    for exception in exceptions:
        print(f"Documented schema exception: {exception['id']} ({exception['samplePath']})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: lint-bedrock-schemas.py <fixture.mcaddon>")
    sys.exit(main(sys.argv[1]))
