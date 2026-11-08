# Advisory Bedrock schemas

These unmodified JSON Schema draft-07 files come from [Blockception/Minecraft-bedrock-json-schemas](https://github.com/Blockception/Minecraft-bedrock-json-schemas) at commit `e04436c149ab2f9592e2b623aac9e19f0c6b2849`. They cover generated feature and feature-rule documents only. The upstream BSD license is included here.

Run `python3 -m pip install jsonschema==4.25.1` and `scripts/lint-bedrock-schemas.sh` to validate a freshly generated structure fixture. CI runs this as an advisory job; it does not replace pinned Mojang sample assertions or physical-device acceptance. There are currently no schema exceptions.
