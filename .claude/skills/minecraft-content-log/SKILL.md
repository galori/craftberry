---
name: minecraft-content-log
description: Read Minecraft Bedrock's Content Log (pack load errors, script/JSON/manifest warnings) from the physical iPhone over USB. Use when verifying a generated Craftberry pack loaded cleanly, diagnosing why content is missing in-game, or checking an E2E run for pack errors without OCR.
---

# Minecraft Content Log (physical device)

Use `scripts/minecraft-content-log.sh` — it reads the log files Minecraft writes to its shared Documents folder via `afcclient` (no Xcode, jailbreak, or macFUSE needed). The iPhone must be connected, unlocked, and trusted.

## Workflow

1. `scripts/minecraft-content-log.sh status` — confirms `content_log_file:1` and lists log files. If it warns the setting is off, ask the user to enable Settings > Creator > "Enable Content Log File", then fully quit and relaunch Minecraft (the setting is only flushed to disk then).
2. `scripts/minecraft-content-log.sh mark` — baseline before the action under test (import a pack, open a world, run a scenario).
3. Perform the action.
4. `scripts/minecraft-content-log.sh since` — only what was logged after the mark. Or `errors` for ERROR/WARN lines in the newest log, `show [file]` for the whole file, `list` for file names.

## Notes

- Minecraft creates a new `ContentLog<timestamp>_N.txt` per game launch; the script defaults to the newest. `since` treats a newer file than the mark as all-new.
- An empty or short file is inconclusive, not proof of a clean load: Minecraft writes the log in chunks, so recent diagnostics may not be on disk yet. Wait and re-read after Minecraft has had time to flush, and only then declare the load clean. Prefer backgrounding the app over relaunching it: a relaunch starts a NEW log file, so note the tested session's filename (`list`/`mark` print it) and read that exact file with `show <file>` / `errors <file>` afterwards. `since` and the default `show` follow the newest file, and a clean new file says nothing about the earlier session. `status` shows the setting is on, not that pending lines reached disk.
- Pack errors are logged when a world loads with the pack active, so open the world before reading.
- Logs can contain world/pack names; don't commit them.
- Don't confuse this with the on-screen Content Log OCR the E2E harness uses; this is the file on disk.
