#!/usr/bin/env python3
"""Regression tests for the pinned catalog generator and advisory schema guards."""
from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRATCH = ROOT / ".scratch"
SCRATCH.mkdir(exist_ok=True)


def load_script(filename: str, module_name: str):
    path = ROOT / "scripts" / filename
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def run_git(repo: pathlib.Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


class ScriptRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir=SCRATCH)
        self.root = pathlib.Path(self.temporary.name)
        self.generator = load_script("generate-vanilla-catalog.py", "catalog_generator_tested")
        self.samples = self.make_sample_repository()
        self.commit = run_git(self.samples, "rev-parse", "HEAD")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def make_sample_repository(self) -> pathlib.Path:
        samples = self.root / "bedrock-samples"
        samples.mkdir()
        fixture_files = (
            ("version.json", {"1.26.30": {"version": "1.26.30"}}),
            (
                "metadata/vanilladata_modules/mojang-items.json",
                {"data_items": [{"name": "minecraft:pinned_item"}]},
            ),
            (
                "behavior_pack/recipes/pinned.json",
                {
                    "minecraft:recipe_furnace": {"input": "minecraft:pinned_item"},
                    "evidence": {"tag": "minecraft:test_tag"},
                },
            ),
        )
        for relative_path, value in fixture_files:
            path = samples / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value))
        run_git(samples, "init", "-q")
        run_git(samples, "config", "user.name", "Catalog Test")
        run_git(samples, "config", "user.email", "catalog-test@example.invalid")
        run_git(samples, "add", "version.json", "metadata", "behavior_pack/recipes")
        run_git(samples, "commit", "-q", "-m", "Pinned sample fixture")
        return samples

    def allowlist(self) -> dict[str, object]:
        return {
            "sourceCommit": self.commit,
            "sampleVersion": "1.26.30",
            "materialSources": ["minecraft:pinned_item"],
            "additionalIdentifiers": [],
            "smithingTemplates": [],
            "smithingBases": [],
            "brewingReagents": [],
            "brewingInputs": [],
            "recipeForms": ["minecraft:recipe_furnace"],
            "recipeFormEvidence": [
                {"path": "behavior_pack/recipes/pinned.json", "form": "minecraft:recipe_furnace"}
            ],
            "itemTags": ["minecraft:test_tag"],
            "itemTagEvidence": [
                {"path": "behavior_pack/recipes/pinned.json", "tag": "minecraft:test_tag"}
            ],
        }

    def test_write_mode_creates_a_missing_catalog(self) -> None:
        allowlist_path = self.root / "vanilla-catalog-allowlist.json"
        allowlist_path.write_text(json.dumps(self.allowlist()))
        output = self.root / "Craftberry/Core/Domain/GeneratedVanillaItemCatalog.swift"
        output.parent.mkdir(parents=True)
        self.assertFalse(output.exists())

        with (
            patch.object(self.generator, "ROOT", self.root),
            patch.object(self.generator, "ALLOWLIST_PATH", allowlist_path),
            patch.object(self.generator, "OUTPUT_PATH", output),
            patch.object(
                sys,
                "argv",
                ["generate-vanilla-catalog.py", "--samples", str(self.samples), "--write"],
            ),
        ):
            self.assertEqual(self.generator.main(), 0)

        self.assertIn("minecraft:pinned_item", output.read_text())

    def test_validation_reads_pinned_item_bytes_not_modified_worktree(self) -> None:
        allowlist = self.allowlist()
        allowlist["materialSources"] = ["minecraft:pinned_item", "minecraft:local_only"]
        items = self.samples / "metadata/vanilladata_modules/mojang-items.json"
        items.write_text(json.dumps({"data_items": [
            {"name": "minecraft:pinned_item"},
            {"name": "minecraft:local_only"},
        ]}))

        with self.assertRaisesRegex(ValueError, "missing from pinned mojang-items.json"):
            self.generator.validate_sources(allowlist, self.samples)

    def test_validation_does_not_discover_uncommitted_recipe_forms(self) -> None:
        allowlist = self.allowlist()
        allowlist["recipeForms"] = ["minecraft:recipe_furnace", "minecraft:recipe_custom"]
        allowlist["recipeFormEvidence"] = [
            {"path": "behavior_pack/recipes/pinned.json", "form": "minecraft:recipe_furnace"},
            {"path": "behavior_pack/recipes/local.json", "form": "minecraft:recipe_custom"},
        ]
        local_recipe = self.samples / "behavior_pack/recipes/local.json"
        local_recipe.write_text(json.dumps({"minecraft:recipe_custom": {}}))

        with self.assertRaisesRegex(ValueError, "Recipe forms missing from pinned samples"):
            self.generator.validate_sources(allowlist, self.samples)

    def test_transform_string_exception_does_not_match_an_object(self) -> None:
        with patch.dict(sys.modules, {"jsonschema": SimpleNamespace(Draft7Validator=object)}):
            linter = load_script("lint-bedrock-schemas.py", "schema_linter_tested")
        exception = {
            "family": "recipes/",
            "pathPattern": r"recipes/.+_sword_smithing_recipe\.json",
            "jsonPathPattern": r"^\$\['minecraft:recipe_smithing_transform'\]\.(base|addition|result)$",
            "validator": "oneOf",
            "messageContains": "not valid under any",
            "instanceType": "string",
        }
        path = "recipes/test_sword_smithing_recipe.json"
        object_error = SimpleNamespace(
            json_path="$['minecraft:recipe_smithing_transform'].base",
            validator="oneOf",
            message="Value is not valid under any of the given schemas",
            instance={"item": 42},
        )
        string_error = SimpleNamespace(
            json_path="$['minecraft:recipe_smithing_transform'].base",
            validator="oneOf",
            message="Value is not valid under any of the given schemas",
            instance="minecraft:diamond_sword",
        )
        self.assertFalse(linter.matches_exception(exception, "recipes/", path, object_error))
        self.assertTrue(linter.matches_exception(exception, "recipes/", path, string_error))

    def test_entity_description_schema_requires_an_object(self) -> None:
        schema = json.loads((ROOT / "schemas/blockception/behavior/entities/entities.json").read_text())
        description = schema["definitions"]["B"]["properties"]["description"]
        self.assertEqual(description.get("type"), "object")
        try:
            from jsonschema import Draft7Validator
        except ImportError:
            self.skipTest("jsonschema is installed by the advisory-schema CI job")
        self.assertFalse(Draft7Validator(description).is_valid(None))

    def test_entity_schema_accepts_its_documented_timer_and_swoop_examples(self) -> None:
        schema = json.loads((ROOT / "schemas/blockception/behavior/entities/entities.json").read_text())
        try:
            from jsonschema import Draft7Validator
        except ImportError:
            self.skipTest("jsonschema is installed by the advisory-schema CI job")

        timer = schema["definitions"]["DBG"]
        timer_instance = {
            "format_version": "1.20.80",
            "minecraft:entity": {
                "description": {"identifier": "craftberry:timer_fixture"},
                "components": {"minecraft:timer": timer["examples"][0]},
            },
        }
        timer_errors = list(Draft7Validator(schema).iter_errors(timer_instance))
        with self.subTest(component="minecraft:timer"):
            self.assertEqual(timer_errors, [], "the timer schema must accept its own documented scalar time example")

        swoop = schema["definitions"]["EJI"]
        swoop_instance = {
            "format_version": "1.20.80",
            "minecraft:entity": {
                "description": {"identifier": "craftberry:swoop_fixture"},
                "components": {"minecraft:behavior.swoop_attack": swoop["examples"][0]},
            },
        }
        swoop_errors = list(Draft7Validator(schema).iter_errors(swoop_instance))
        with self.subTest(component="minecraft:behavior.swoop_attack"):
            self.assertEqual(swoop_errors, [], "the swoop schema must accept its own documented numeric pair example")

    def test_template_exception_matches_only_the_template_property_error(self) -> None:
        with patch.dict(sys.modules, {"jsonschema": SimpleNamespace(Draft7Validator=object)}):
            linter = load_script("lint-bedrock-schemas.py", "schema_linter_template_exception_tested")
        exceptions = json.loads((ROOT / "schemas/blockception/exceptions.json").read_text())
        exception = next(
            item for item in exceptions
            if item["id"] == "smithing-transform-template-omitted-from-pinned-blockception-schema"
        )
        path = "recipes/test_sword_smithing_recipe.json"
        template_only = SimpleNamespace(
            json_path="$['minecraft:recipe_smithing_transform']",
            validator="additionalProperties",
            message="Additional properties are not allowed ('template' was unexpected)",
            instance={"template": "minecraft:netherite_upgrade_smithing_template"},
        )
        template_and_typo = SimpleNamespace(
            json_path="$['minecraft:recipe_smithing_transform']",
            validator="additionalProperties",
            message="Additional properties are not allowed ('template', 'templat' were unexpected)",
            instance={
                "template": "minecraft:netherite_upgrade_smithing_template",
                "templat": "minecraft:netherite_upgrade_smithing_template",
            },
        )
        self.assertTrue(linter.matches_exception(exception, "recipes/", path, template_only))
        self.assertFalse(linter.matches_exception(exception, "recipes/", path, template_and_typo))


if __name__ == "__main__":
    unittest.main()
