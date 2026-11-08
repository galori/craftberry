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

# A paired phone can report a disconnected CoreDevice tunnel and a
# localNetwork transport while still being available to Xcode. CoreDevice
# exposes the connectdevice capability only while that phone is available.
physical_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and (.connectionProperties.tunnelState == "connected" or (.connectionProperties.pairingState == "paired" and any(.capabilities[]?; .featureIdentifier == "com.apple.coredevice.feature.connectdevice"))))]'

usage() {
    cat <<USAGE
Usage: scripts/ios-device.sh <command> [options]

Commands:
  list    Show connected physical iPhones.
  run     Build, install, and launch Craftberry on the selected iPhone.
  test    Run the deterministic UI smoke test on the selected iPhone.
  minecraft-e2e [redstone|emerald|weapon|armor|consumable|block|smithing|furnace|brewing|ore|crop|entity|structure] [--fresh-world|--delete-world]
          Run a full Craftberry-to-Minecraft acceptance test, defaulting to
          redstone. Redstone checks the .mcaddon import and activation path.
          Other scenarios import a prepared .mcworld with packs active and
          remove that exact test world before and after the run.
  minecraft-e2e-all [--fresh-world]
          Run all thirteen scenarios sequentially. The regular .mcaddon
          import check runs once; the other checks use prepared .mcworlds.
          Each prepared-world check removes only its exact named test world.
          --fresh-world clears the reusable "craftberry test" world before
          the regular .mcaddon scenario.

Set DEVICE_ID=<xcode-udid-or-coredevice-id> when more than one physical iPhone is connected.
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
            ([\"CoreDevice ID\", \"Xcode UDID\", \"Name\", \"Model\", \"OS\"] | @tsv),
            (.[] | [.identifier, .hardwareProperties.udid, .deviceProperties.name, .hardwareProperties.marketingName, .deviceProperties.osVersionNumber] | @tsv)
          end" "$json_path"
}

select_device() {
    local json_path
    json_path="$(discover_devices)"
    local selected_json

    if [[ -n "${DEVICE_ID:-}" ]]; then
        local matches
        matches="$(jq -r --arg id "$DEVICE_ID" "$physical_iphone_filter | map(select(.identifier == \$id or .hardwareProperties.udid == \$id)) | length" "$json_path")"
        if [[ "$matches" == "1" ]]; then
            selected_json="$(jq -c --arg id "$DEVICE_ID" "$physical_iphone_filter | map(select(.identifier == \$id or .hardwareProperties.udid == \$id)) | .[0]" "$json_path")"
        else
            echo "error: DEVICE_ID '$DEVICE_ID' is not a connected physical iPhone (accepted: CoreDevice ID or Xcode UDID)." >&2
            print_devices "$json_path" >&2
            exit 1
        fi
    else
        local count
        count="$(jq -r "$physical_iphone_filter | length" "$json_path")"
        case "$count" in
            0)
                echo "error: no connected physical iPhones found." >&2
                print_devices "$json_path" >&2
                exit 1
                ;;
            1)
                selected_json="$(jq -c "$physical_iphone_filter | .[0]" "$json_path")"
                ;;
            *)
                echo "error: multiple connected physical iPhones found; set DEVICE_ID." >&2
                print_devices "$json_path" >&2
                exit 1
                ;;
        esac
    fi

    CORE_DEVICE_ID="$(printf '%s\n' "$selected_json" | jq -r '.identifier')"
    XCODE_DEVICE_ID="$(printf '%s\n' "$selected_json" | jq -r '.hardwareProperties.udid // empty')"
    if [[ -z "$CORE_DEVICE_ID" || -z "$XCODE_DEVICE_ID" ]]; then
        echo "error: selected physical iPhone did not provide both CoreDevice ID and Xcode UDID." >&2
        exit 1
    fi
}

build_for_device() {
    local xcode_device_id="$1"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$xcode_device_id" \
        -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates \
        build
}

run_on_device() {
    select_device
    mkdir -p "$OUTPUT_DIR"

    echo "Building Craftberry for Xcode device $XCODE_DEVICE_ID (CoreDevice $CORE_DEVICE_ID)"
    build_for_device "$XCODE_DEVICE_ID"

    if [[ ! -d "$APP_PATH" ]]; then
        echo "error: expected app bundle was not produced at $APP_PATH" >&2
        exit 1
    fi

    echo "Installing $APP_PATH"
    xcrun devicectl device install app \
        --device "$CORE_DEVICE_ID" \
        "$APP_PATH" \
        --timeout 120 \
        --json-output "$OUTPUT_DIR/install.json"

    echo "Launching $BUNDLE_ID"
    xcrun devicectl device process launch \
        --device "$CORE_DEVICE_ID" \
        --terminate-existing \
        --activate \
        "$BUNDLE_ID" \
        --timeout 60 \
        --json-output "$OUTPUT_DIR/launch.json"
}

test_on_device() {
    select_device
    mkdir -p "$OUTPUT_DIR"

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local result_path="$OUTPUT_DIR/CraftberryUITests-$timestamp.xcresult"

    echo "Running deterministic UI smoke test on Xcode device $XCODE_DEVICE_ID (CoreDevice $CORE_DEVICE_ID)"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$XCODE_DEVICE_ID" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_path" \
        -allowProvisioningUpdates \
        -collect-test-diagnostics never \
        -only-testing:CraftberryUITests/CraftberryUITests/testDeterministicSwordExportBuildsAndOpensShareSheetInOneStep \
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

afc_world_exists() {
    # Returns 0 if a "craftberry test" world directory exists via AFC.
    # Must be called when Minecraft is *not* running (AFC house-arrest is
    # incoherent while running). Fail-open: if AFC is unavailable, report
    # "does not exist" so a fresh creation is attempted rather than risking
    # a false reuse.
    if ! command -v afcclient >/dev/null 2>&1; then return 1; fi
    local tmp
    mkdir -p "$ROOT_DIR/.scratch"
    tmp="$(mktemp "$ROOT_DIR/.scratch/afc-world-status.XXXXXX")"
    if "$CLEANUP_SCRIPT" status >"$tmp" 2>&1; then
        # status prints "Worlds: craftberry test" followed by world dirs when found.
        # When no world exists it prints "Worlds: craftberry test not found".
        if grep -q "not found" "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
        if grep -q "minecraftWorlds/" "$tmp"; then
            rm -f "$tmp"
            return 0
        fi
    fi
    rm -f "$tmp"
    return 1
}

minecraft_e2e_on_device() {
    local scenario="${1:-redstone}"
    local fresh_world="no"
    # Permit trailing flags after scenario: minecraft-e2e [scenario] [--fresh-world|--delete-world]
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fresh-world|--delete-world) fresh_world="yes"; shift ;;
            --keep-world) fresh_world="no"; shift ;;
            *) echo "error: unknown flag '$1' for minecraft-e2e (expected --fresh-world)" >&2; exit 1 ;;
        esac
    done
    local test_selector
    local result_name
    local prepared_world_name=""
    case "$scenario" in
        redstone)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneToolSetCanBeImportedActivatedAndCraftedIntoPickaxe"
            result_name="MinecraftRedstoneToolSetE2EUITests"
            ;;
        emerald)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryEmeraldSwordCanBeCraftedInImportedCreativeWorld"
            result_name="MinecraftDeviceEmeraldSwordE2EUITests"
            prepared_world_name="Emerald Test Sword (Creative)"
            ;;
        weapon)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneWeaponSetCanCraftSpearInImportedCreativeWorld"
            result_name="MinecraftRedstoneWeaponSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        armor)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneArmorSetCanCraftBootsInImportedCreativeWorld"
            result_name="MinecraftRedstoneArmorSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        consumable)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneConsumableSetCanCraftFoodInImportedCreativeWorld"
            result_name="MinecraftRedstoneConsumableSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        block)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneBlockSetCanCraftBlockInImportedCreativeWorld"
            result_name="MinecraftRedstoneBlockSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        smithing)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneSmithingSetCanCraftIngotInImportedCreativeWorld"
            result_name="MinecraftRedstoneSmithingSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        furnace)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneFurnaceSetCanCraftSwordInImportedCreativeWorld"
            result_name="MinecraftRedstoneFurnaceSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        brewing)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneBrewingSetCanCraftIngotInImportedCreativeWorld"
            result_name="MinecraftRedstoneBrewingSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        ore)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneOreSetCanCraftOreInImportedCreativeWorld"
            result_name="MinecraftRedstoneOreSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        crop)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneCropSetCanCraftSeedsInImportedCreativeWorld"
            result_name="MinecraftRedstoneCropSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        entity)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneEntitySetCanCraftSpawnEggInImportedCreativeWorld"
            result_name="MinecraftRedstoneEntitySetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        structure)
            test_selector="CraftberryUITests/MinecraftDeviceE2EUITests/testCraftberryRedstoneStructureSetCanCraftBlockInImportedCreativeWorld"
            result_name="MinecraftRedstoneStructureSetE2EUITests"
            prepared_world_name="Redstone (Creative)"
            ;;
        *)
            echo "error: unknown minecraft-e2e scenario '$scenario' (expected redstone, emerald, weapon, armor, consumable, block, smithing, furnace, brewing, ore, crop, entity, or structure)." >&2
            exit 1
            ;;
    esac

    select_device
    mkdir -p "$OUTPUT_DIR"

    if [[ -n "$prepared_world_name" ]]; then
        echo "Removing only the prior '$prepared_world_name' test world and generated packs..."
        terminate_minecraft_on_device "$CORE_DEVICE_ID"
        CRAFTBERRY_CLEANUP_WORLD_NAME="$prepared_world_name" \
            CRAFTBERRY_CLEANUP_WORLD_MATCH_MODE=exact \
            "$CLEANUP_SCRIPT" clean --delete-world --yes
    elif [[ "$fresh_world" == "yes" ]]; then
        echo "Fresh-world requested — deleting existing craftberry test world and packs via AFC..."
        terminate_minecraft_on_device "$CORE_DEVICE_ID"
        set +e
        "$CLEANUP_SCRIPT" clean --delete-world --yes
        set -e
        echo "Fresh-world cleanup done."
    fi

    local world_exists_flag="0"
    if [[ -z "$prepared_world_name" ]] && afc_world_exists; then
        world_exists_flag="1"
        echo "Existing craftberry test world found via AFC — harness will reuse it (skip creation)."
    else
        echo "No existing craftberry test world found via AFC — harness will create one."
    fi

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local result_path="$OUTPUT_DIR/$result_name-$timestamp.xcresult"

    echo "Running full Minecraft $scenario E2E on Xcode device $XCODE_DEVICE_ID (CoreDevice $CORE_DEVICE_ID)"
    echo "The XCTest teardown terminates $MINECRAFT_BUNDLE_ID before Mac-side AFC cleanup runs."

    set +e
    CRAFTBERRY_E2E_REUSE_WORLD="$world_exists_flag" xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$XCODE_DEVICE_ID" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_path" \
        -allowProvisioningUpdates \
        -collect-test-diagnostics never \
        -only-testing:"$test_selector" \
        test
    local test_status=$?
    set -e

    echo "Result bundle: $result_path"
    terminate_minecraft_on_device "$CORE_DEVICE_ID"
    echo "Cleaning Minecraft test data via AFC..."

    set +e
    if [[ -n "$prepared_world_name" ]]; then
        CRAFTBERRY_CLEANUP_WORLD_NAME="$prepared_world_name" \
            CRAFTBERRY_CLEANUP_WORLD_MATCH_MODE=exact \
            "$CLEANUP_SCRIPT" clean --delete-world --yes
    else
        "$CLEANUP_SCRIPT" clean --yes
    fi
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

minecraft_e2e_all_on_device() {
    local fresh_world="no"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fresh-world|--delete-world) fresh_world="yes"; shift ;;
            --keep-world) fresh_world="no"; shift ;;
            *) echo "error: unknown flag '$1' for minecraft-e2e-all (expected --fresh-world)" >&2; exit 1 ;;
        esac
    done
    local scenarios=(redstone emerald weapon armor consumable block smithing furnace brewing ore crop entity structure)
    local overall_status=0
    local first="yes"
    for scenario in "${scenarios[@]}"; do
        local -a args=("$scenario")
        if [[ "$first" == "yes" && "$fresh_world" == "yes" ]]; then
            args+=(--fresh-world)
        fi
        if minecraft_e2e_on_device "${args[@]}"; then
            overall_status=0
        else
            overall_status=$?
            echo "minecraft-e2e-all: $scenario failed with status $overall_status — stopping." >&2
            return "$overall_status"
        fi
        first="no"
    done
    return "$overall_status"
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
            shift
            minecraft_e2e_on_device "$@"
            ;;
        minecraft-e2e-all)
            shift
            minecraft_e2e_all_on_device "$@"
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
