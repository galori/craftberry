#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Craftberry.xcodeproj"
SCHEME="Craftberry"
BUNDLE_ID="com.craftberry.app"
OUTPUT_DIR="$ROOT_DIR/.build/ios-device"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Debug-iphoneos"
APP_PATH="$PRODUCTS_DIR/Craftberry.app"

physical_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and .connectionProperties.tunnelState == "connected")]'

usage() {
    cat <<USAGE
Usage: scripts/ios-device.sh <command>

Commands:
  list    Show connected physical iPhones.
  run     Build, install, and launch Craftberry on the selected iPhone.
  test    Run the deterministic UI smoke test on the selected iPhone.

Set DEVICE_ID=<xcode-device-id> when more than one physical iPhone is connected.
All build and test output is kept under .build/ios-device.
USAGE
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool '$1' was not found on PATH" >&2
        exit 1
    fi
}

discover_devices() {
    mkdir -p "$OUTPUT_DIR"
    local json_path="$OUTPUT_DIR/devices.json"
    xcrun devicectl list devices \
        --timeout 10 \
        --json-output "$json_path" \
        > "$OUTPUT_DIR/devices.txt"
    printf '%s\n' "$json_path"
}

print_devices() {
    local json_path="$1"
    jq -r "$physical_iphone_filter
        | if length == 0 then
            \"No connected physical iPhones found.\"
          else
            ([\"Identifier\", \"Name\", \"Model\", \"OS\"] | @tsv),
            (.[] | [.identifier, .deviceProperties.name, .hardwareProperties.marketingName, .deviceProperties.osVersionNumber] | @tsv)
          end" "$json_path"
}

select_device() {
    local json_path
    json_path="$(discover_devices)"

    if [[ -n "${DEVICE_ID:-}" ]]; then
        local matches
        matches="$(jq -r --arg id "$DEVICE_ID" "$physical_iphone_filter | map(select(.identifier == \$id)) | length" "$json_path")"
        if [[ "$matches" == "1" ]]; then
            printf '%s\n' "$DEVICE_ID"
            return
        fi
        echo "error: DEVICE_ID '$DEVICE_ID' is not a connected physical iPhone." >&2
        print_devices "$json_path" >&2
        exit 1
    fi

    local count
    count="$(jq -r "$physical_iphone_filter | length" "$json_path")"
    case "$count" in
        0)
            echo "error: no connected physical iPhones found." >&2
            print_devices "$json_path" >&2
            exit 1
            ;;
        1)
            jq -r "$physical_iphone_filter | .[0].identifier" "$json_path"
            ;;
        *)
            echo "error: multiple connected physical iPhones found; set DEVICE_ID." >&2
            print_devices "$json_path" >&2
            exit 1
            ;;
    esac
}

build_for_device() {
    local device_id="$1"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates \
        build
}

run_on_device() {
    local device_id
    device_id="$(select_device)"
    mkdir -p "$OUTPUT_DIR"

    echo "Building Craftberry for device $device_id"
    build_for_device "$device_id"

    if [[ ! -d "$APP_PATH" ]]; then
        echo "error: expected app bundle was not produced at $APP_PATH" >&2
        exit 1
    fi

    echo "Installing $APP_PATH"
    xcrun devicectl device install app \
        --device "$device_id" \
        "$APP_PATH" \
        --timeout 120 \
        --json-output "$OUTPUT_DIR/install.json"

    echo "Launching $BUNDLE_ID"
    xcrun devicectl device process launch \
        --device "$device_id" \
        --terminate-existing \
        --activate \
        "$BUNDLE_ID" \
        --timeout 60 \
        --json-output "$OUTPUT_DIR/launch.json"
}

test_on_device() {
    local device_id
    device_id="$(select_device)"
    mkdir -p "$OUTPUT_DIR"

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local result_path="$OUTPUT_DIR/CraftberryUITests-$timestamp.xcresult"

    echo "Running deterministic UI smoke test on device $device_id"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_path" \
        -allowProvisioningUpdates \
        -only-testing:CraftberryUITests/CraftberryUITests/testDeterministicSwordBuildCanOpenShareSheet \
        test

    echo "Result bundle: $result_path"
}

main() {
    require_tool jq
    require_tool xcodebuild
    require_tool xcrun

    case "${1:-}" in
        list)
            print_devices "$(discover_devices)"
            ;;
        run)
            run_on_device
            ;;
        test)
            test_on_device
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
