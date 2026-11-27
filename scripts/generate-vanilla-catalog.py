#!/usr/bin/env python3
"""Render the app's intentionally small vanilla allowlist from a pinned sample commit."""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWLIST_PATH = ROOT / "Config" / "vanilla-catalog-allowlist.json"
OUTPUT_PATH = ROOT / "Craftberry" / "Core" / "Domain" / "GeneratedVanillaItemCatalog.swift"
DIRECT_ITEM_GROUPS = (
    "materialSources",
    "additionalIdentifiers",
    "smithingTemplates",
    "smithingBases",
    "brewingReagents",
)


def read_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read JSON source {path}: {error}") from error


def strings_in(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings_in(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings_in(child)


def repository_commit(samples: pathlib.Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(samples), "rev-parse", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError(f"{samples} is not a checked-out Bedrock samples repository")
    return result.stdout.strip()


def read_pinned_json(samples: pathlib.Path, commit: str, relative_path: str) -> Any:
    result = subprocess.run(
        ["git", "-C", str(samples), "show", f"{commit}:{relative_path}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError(f"Cannot read {relative_path} from pinned sample commit {commit}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid JSON in pinned sample {relative_path}: {error}") from error


def pinned_recipe_paths(samples: pathlib.Path, commit: str) -> list[str]:
    result = subprocess.run(
        [
            "git", "-C", str(samples), "ls-tree", "-r", "-z", "--name-only", commit,
            "--", "behavior_pack/recipes",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError(f"Cannot list recipes at pinned sample commit {commit}")
    return [path for path in result.stdout.split("\0") if path.endswith(".json")]


def validate_sources(allowlist: dict[str, Any], samples: pathlib.Path) -> None:
    expected_commit = allowlist["sourceCommit"]
    actual_commit = repository_commit(samples)
    if actual_commit != expected_commit:
        raise ValueError(f"Sample checkout is {actual_commit}; expected pinned commit {expected_commit}")

    version = read_pinned_json(samples, expected_commit, "version.json")
    if version.get(allowlist["sampleVersion"], {}).get("version") != allowlist["sampleVersion"]:
        raise ValueError(f"Pinned samples do not declare version {allowlist['sampleVersion']}")

    item_data = read_pinned_json(
        samples,
        expected_commit,
        "metadata/vanilladata_modules/mojang-items.json",
    )
    item_identifiers = {item.get("name") for item in item_data.get("data_items", [])}
    direct_identifiers = {
        identifier
        for key in DIRECT_ITEM_GROUPS
        for identifier in allowlist[key]
    }
    direct_identifiers.update(
        identifier
        for identifier in allowlist["brewingInputs"]
        if not identifier.startswith("minecraft:potion_type:")
    )
    missing = sorted(direct_identifiers - item_identifiers)
    if missing:
        raise ValueError(f"Identifiers missing from pinned mojang-items.json: {', '.join(missing)}")

    recipe_documents: dict[str, dict[str, Any]] = {}
    recipe_forms: set[str] = set()
    recipe_strings: set[str] = set()
    for relative_path in pinned_recipe_paths(samples, expected_commit):
        document = read_pinned_json(samples, expected_commit, relative_path)
        recipe_documents[relative_path] = document
        recipe_forms.update(key for key in document if key.startswith("minecraft:recipe_"))
        recipe_strings.update(strings_in(document))

    missing_forms = sorted(set(allowlist["recipeForms"]) - recipe_forms)
    if missing_forms:
        raise ValueError(f"Recipe forms missing from pinned samples: {', '.join(missing_forms)}")

    for evidence in allowlist["recipeFormEvidence"]:
        document = recipe_documents.get(evidence["path"])
        if document is None or evidence["form"] not in document:
            raise ValueError(f"Invalid recipe-form evidence: {evidence['path']} does not contain {evidence['form']}")

    pseudo_items = {
        identifier
        for identifier in allowlist["brewingInputs"]
        if identifier.startswith("minecraft:potion_type:")
    }
    missing_pseudo_items = sorted(pseudo_items - recipe_strings)
    if missing_pseudo_items:
        raise ValueError(f"Potion inputs missing from pinned recipe samples: {', '.join(missing_pseudo_items)}")

    for evidence in allowlist["itemTagEvidence"]:
        document = recipe_documents.get(evidence["path"])
        if document is None or not any(
            isinstance(value, dict) and value.get("tag") == evidence["tag"]
            for value in walk_objects(document)
        ):
            raise ValueError(f"Invalid item-tag evidence: {evidence['path']} does not reference {evidence['tag']}")

    supported_tags = set(allowlist["itemTags"])
    evidenced_tags = {evidence["tag"] for evidence in allowlist["itemTagEvidence"]}
    if supported_tags != evidenced_tags:
        raise ValueError("Every supported item tag must have one explicit pinned sample evidence entry")


def walk_objects(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_objects(child)


def swift_set(name: str, values: list[str]) -> str:
    ordered = sorted(values)
    if not ordered:
        return f"    static let {name}: Set<String> = []"
    lines = [f"    static let {name}: Set<String> = ["]
    for index in range(0, len(ordered), 3):
        chunk = ordered[index : index + 3]
        comma = "," if index + 3 < len(ordered) else ""
        lines.append("        " + ", ".join(f'"{value}"' for value in chunk) + comma)
    lines.append("    ]")
    return "\n".join(lines)


def render(allowlist: dict[str, Any]) -> str:
    fields = (
        ("materialSources", "materialSources"),
        ("additionalIdentifiers", "additionalIdentifiers"),
        ("smithingTemplates", "smithingTemplates"),
        ("smithingBases", "smithingBases"),
        ("brewingInputs", "brewingInputs"),
        ("brewingReagents", "brewingReagents"),
        ("itemTags", "itemTags"),
        ("recipeForms", "recipeForms"),
    )
    chunks = [
        "import Foundation",
        "",
        f"/// Generated from Mojang/bedrock-samples v{allowlist['sampleVersion']} at {allowlist['sourceCommit']}.",
        "/// Refresh with `scripts/refresh-vanilla-catalog.sh`; the allowlist is deliberately narrower than vanilla.",
        "enum GeneratedVanillaItemCatalog {",
        f'    static let sourceVersion = "{allowlist["sampleVersion"]}"',
        f'    static let sourceCommit = "{allowlist["sourceCommit"]}"',
    ]
    chunks.extend(swift_set(property_name, allowlist[input_name]) for input_name, property_name in fields)
    if len(allowlist["itemTags"]) != 1:
        raise ValueError("The profile currently requires exactly one trimmable-armor item tag")
    chunks.extend(
        [
            f'    static let trimmableArmorTag = "{allowlist["itemTags"][0]}"',
            "    static let identifiers = materialSources.union(additionalIdentifiers).union(smithingTemplates).union(smithingBases).union(brewingInputs).union(brewingReagents)",
            "}",
            "",
        ]
    )
    return "\n".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=pathlib.Path, required=True, help="Checkout of the pinned Mojang bedrock-samples commit")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Fail if the checked-in Swift catalog differs from the generated output")
    mode.add_argument("--write", action="store_true", help="Write the generated Swift catalog")
    args = parser.parse_args()

    try:
        allowlist = read_json(ALLOWLIST_PATH)
        validate_sources(allowlist, args.samples)
        generated = render(allowlist)
    except (KeyError, TypeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    if args.check:
        try:
            existing = OUTPUT_PATH.read_text()
        except OSError as error:
            print(f"Cannot read {OUTPUT_PATH.relative_to(ROOT)}: {error}", file=sys.stderr)
            return 1
        if existing != generated:
            print(f"{OUTPUT_PATH.relative_to(ROOT)} is stale; run scripts/refresh-vanilla-catalog.sh", file=sys.stderr)
            return 1
        print(f"Vanilla catalog matches the explicit allowlist and Mojang sample commit {allowlist['sourceCommit']}.")
        return 0

    OUTPUT_PATH.write_text(generated)
    print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)} from {allowlist['sampleVersion']} ({allowlist['sourceCommit']}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
