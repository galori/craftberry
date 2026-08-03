#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Craftberry.xcodeproj"
SCHEME="Craftberry"
OUTPUT_DIR="$ROOT_DIR/.build/minecraft-coordinate-touch"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"

physical_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and .connectionProperties.tunnelState == "connected")]'

usage() {
    cat <<USAGE
Usage: scripts/minecraft-coordinate-touch.sh

Runs the USB-only XCUITest proof that taps Minecraft's visible Creative
inventory search field via a genuine XCTest coordinate gesture. The test
records before/after device screenshots in a timestamped .xcresult.

Before running: quit iPhone Mirroring, unlock the iPhone, connect it by USB,
and leave Minecraft open to Creative inventory with the All Items search field
visible. The first calibration targets an iPhone 16e in landscape.

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
    xcrun devicectl list devices --timeout 10 --json-output "$json_path" > "$OUTPUT_DIR/devices.txt"

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

    local count
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
    require_tool xcodebuild
    require_tool xcrun

    local device_id timestamp result_path
    device_id="$(select_device)"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    result_path="$OUTPUT_DIR/MinecraftCoordinateTouch-$timestamp.xcresult"

    echo "Running Minecraft coordinate-touch proof on device $device_id"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_path" \
        -allowProvisioningUpdates \
        -only-testing:CraftberryUITests/MinecraftCoordinateTouchUITests/testMinecraftReceivesCoordinateTapInCreativeSearch \
        test

    echo "Coordinate-touch proof complete. Inspect the before/after screenshots in: $result_path"
}

main "$@"
