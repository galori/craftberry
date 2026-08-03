#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Craftberry.xcodeproj"
SCHEME="Craftberry"
OUTPUT_DIR="$ROOT_DIR/.build/minecraft-coordinate-touch"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
OCR_SCRIPT="$ROOT_DIR/scripts/ocr.swift"

physical_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and .connectionProperties.tunnelState == "connected")]'
paired_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and .connectionProperties.pairingState == "paired")]'

usage() {
    cat <<USAGE
Usage: scripts/minecraft-coordinate-touch.sh

Runs the USB-only XCUITest proof that taps Minecraft's main-menu Play button
via a genuine XCTest coordinate gesture. The test records before/after device
screenshots in a timestamped .xcresult.

Before running: quit iPhone Mirroring, unlock the iPhone, and connect it by
USB. The test cold-launches Minecraft and targets an iPhone 16e in landscape.

Set DEVICE_ID=<xcode-device-id> when more than one physical iPhone is connected.
USAGE
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool '$1' was not found on PATH" >&2
        exit 1
    fi
}

select_device() {
    mkdir -p "$OUTPUT_DIR"
    local json_path="$OUTPUT_DIR/devices.json"
    local attempt count candidate_id

    # CoreDevice can briefly list a just-unlocked wired phone as merely
    # "available (paired)" even though a detail query immediately establishes
    # its tunnel. Wake the single paired iPhone and retry before failing.
    for attempt in 1 2 3 4 5; do
        xcrun devicectl list devices --timeout 10 --json-output "$json_path" > "$OUTPUT_DIR/devices.txt"
        count="$(jq -r "$physical_iphone_filter | length" "$json_path")"
        if [[ "$count" != "0" ]]; then
            break
        fi

        if [[ "$(jq -r "$paired_iphone_filter | length" "$json_path")" == "1" ]]; then
            candidate_id="$(jq -r "$paired_iphone_filter | .[0].identifier" "$json_path")"
            xcrun devicectl device info details --device "$candidate_id" --timeout 10 >/dev/null 2>&1 || true
        fi
        sleep 1
    done

    if [[ -n "${DEVICE_ID:-}" ]]; then
        local matches
        matches="$(jq -r --arg id "$DEVICE_ID" "$physical_iphone_filter | map(select(.identifier == \$id)) | length" "$json_path")"
        if [[ "$matches" == "1" ]]; then
            printf '%s\n' "$DEVICE_ID"
            return
        fi
        echo "error: DEVICE_ID '$DEVICE_ID' is not a connected physical iPhone." >&2
        exit 1
    fi

    count="$(jq -r "$physical_iphone_filter | length" "$json_path")"
    case "$count" in
        1) jq -r "$physical_iphone_filter | .[0].identifier" "$json_path" ;;
        0) echo "error: no connected physical iPhones found. Quit iPhone Mirroring, unlock the phone, then connect USB." >&2; exit 1 ;;
        *) echo "error: multiple connected physical iPhones found; set DEVICE_ID." >&2; exit 1 ;;
    esac
}

main() {
    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
        "") ;;
        *) usage >&2; exit 1 ;;
    esac

    require_tool jq
    require_tool swift
    require_tool xcodebuild
    require_tool xcrun

    local device_id timestamp result_path attachments_dir after_file
    device_id="$(select_device)"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    result_path="$OUTPUT_DIR/MinecraftCoordinateTouch-$timestamp.xcresult"
    attachments_dir="$OUTPUT_DIR/attachments-$timestamp"

    echo "Running Minecraft coordinate-touch proof on device $device_id"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_path" \
        -allowProvisioningUpdates \
        -only-testing:CraftberryUITests/MinecraftCoordinateTouchUITests/testMinecraftReceivesCoordinateTapOnPlay \
        test

    mkdir -p "$attachments_dir"
    xcrun xcresulttool export attachments \
        --path "$result_path" \
        --output-path "$attachments_dir"

    after_file="$(jq -r '[.[] | .attachments[] | select(.suggestedHumanReadableName | startswith("After tapping Minecraft Play"))][0].exportedFileName // empty' "$attachments_dir/manifest.json")"
    if [[ -z "$after_file" || ! -f "$attachments_dir/$after_file" ]]; then
        echo "error: the post-tap screenshot was not exported from $result_path" >&2
        exit 1
    fi

    swift "$OCR_SCRIPT" "$attachments_dir/$after_file" "My World"
    echo "Coordinate-touch proof complete: Minecraft opened the world list and OCR found 'My World'."
    echo "Result bundle: $result_path"
    echo "Exported screenshots: $attachments_dir"
}

main "$@"
