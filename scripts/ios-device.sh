#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Craftberry.xcodeproj"
SCHEME="Craftberry"
BUNDLE_ID="com.craftberry.app"
MINECRAFT_BUNDLE_ID="com.mojang.minecraftpe"
OUTPUT_DIR="$ROOT_DIR/.build/ios-device"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Debug-iphoneos"
APP_PATH="$PRODUCTS_DIR/Craftberry.app"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/minecraft-cleanup.sh"

physical_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and .connectionProperties.tunnelState == "connected")]'

usage() {
    cat <<USAGE
Usage: scripts/ios-device.sh <command>

Commands:
  list    Show connected physical iPhones.
  run     Build, install, and launch Craftberry on the selected iPhone.
  test    Run the deterministic UI smoke test on the selected iPhone.
  minecraft-e2e [redstone|emerald|weapon]
          Run a full Craftberry-to-Minecraft acceptance test, defaulting to
          redstone, then clean Minecraft's generated packs and test world via AFC.

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

terminate_minecraft_on_device() {
    local device_id="$1"
    local processes_json="$OUTPUT_DIR/minecraft-processes.json"
    local processes_log="$OUTPUT_DIR/minecraft-processes.log"

    if ! xcrun devicectl device info processes \
        --device "$device_id" \
        --timeout 15 \
        --json-output "$processes_json" \
        --log-output "$processes_log" \
        >/dev/null 2>&1; then
        echo "warning: could not list device processes before cleanup; continuing to AFC cleanup" >&2
        return 0
    fi

    local pids
    pids="$(jq -r --arg bundle "$MINECRAFT_BUNDLE_ID" '
        .. | objects
        | select(
            ((.bundleIdentifier? // .bundleID? // .applicationIdentifier? // "") == $bundle)
            or ((.executable? // "") | test("/Minecraft[.]app/Minecraft$|minecraftpe"; "i"))
        )
        | (.pid? // .processIdentifier? // empty)
    ' "$processes_json" | sort -u)"

    if [[ -z "$pids" ]]; then
        echo "Minecraft is not running."
        return 0
    fi

    local pid
    for pid in $pids; do
        echo "Terminating Minecraft process $pid before AFC cleanup..."
        xcrun devicectl device process terminate \
            --device "$device_id" \
            --pid "$pid" \
            --kill \
            --timeout 15 \
            >/dev/null
    done
}

minecraft_e2e_on_device() {
    local scenario="${1:-redstone}"
    local test_selector
    local result_name
    case "$scenario" in
        redstone)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneToolSetCanBeImportedActivatedAndCraftedIntoPickaxe"
            result_name="MinecraftRedstoneToolSetE2EUITests"
            ;;
        emerald)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryEmeraldSwordCanBeImportedActivatedAndCrafted"
            result_name="MinecraftDeviceEmeraldSwordE2EUITests"
            ;;
        weapon)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneWeaponSetCanBeImportedActivatedAndCraftedIntoSpear"
            result_name="MinecraftRedstoneWeaponSetE2EUITests"
            ;;
        *)
            echo "error: unknown minecraft-e2e scenario '$scenario' (expected redstone, emerald, or weapon)." >&2
            exit 1
            ;;
    esac

    local device_id
    device_id="$(select_device)"
    mkdir -p "$OUTPUT_DIR"

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local result_path="$OUTPUT_DIR/$result_name-$timestamp.xcresult"

    echo "Running full Minecraft $scenario E2E on device $device_id"
    echo "The XCTest teardown terminates $MINECRAFT_BUNDLE_ID before Mac-side AFC cleanup runs."

    set +e
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_path" \
        -allowProvisioningUpdates \
        -only-testing:"$test_selector" \
        test
    local test_status=$?
    set -e

    echo "Result bundle: $result_path"
    terminate_minecraft_on_device "$device_id"
    echo "Cleaning Minecraft test packs and world via AFC..."

    set +e
    "$CLEANUP_SCRIPT" clean --delete-world --yes
    local cleanup_status=$?
    set -e

    if [[ "$cleanup_status" -ne 0 ]]; then
        echo "error: Minecraft AFC cleanup failed with status $cleanup_status" >&2
    fi

    if [[ "$test_status" -ne 0 ]]; then
        return "$test_status"
    fi
    return "$cleanup_status"
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
        minecraft-e2e)
            minecraft_e2e_on_device "${2:-redstone}"
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
