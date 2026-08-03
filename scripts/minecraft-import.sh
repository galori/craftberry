#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Craftberry.xcodeproj"
SCHEME="Craftberry"
OUTPUT_DIR="$ROOT_DIR/.build/minecraft-import"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
FIXTURE_DIR="$OUTPUT_DIR/fixture"
IMPORT_CONFIG_PATH="$ROOT_DIR/CraftberryUITests/MinecraftImportConfig.json"

physical_iphone_filter='[.result.devices[]? | select(.hardwareProperties.platform == "iOS" and .hardwareProperties.deviceType == "iPhone" and .hardwareProperties.reality == "physical" and .connectionProperties.tunnelState == "connected")]'

usage() {
    cat <<USAGE
Usage: scripts/minecraft-import.sh [mcaddon-path]

Leg 1 of physical-device Minecraft validation: serves an .mcaddon over local
HTTP and drives Safari (not Craftberry) via XCUITest on a connected physical
iPhone to download it and hand it off to Minecraft's "Open in Minecraft"
import. Stops once Minecraft has imported the pack into its library.

If mcaddon-path is omitted, a fresh fixture sword add-on is generated on the
Mac via the MinecraftFixture Swift package executable (no iPhone needed for
generation) with a brand-new display name and identifiers.

Activating the imported pack in a test world and verifying it in-game is a
separate step: scripts/minecraft-mirror-drive.sh.

Set DEVICE_ID=<xcode-device-id> when more than one physical iPhone is connected.
Set MCADDON_SERVER_PORT to pin the local HTTP server port; otherwise a free
ephemeral port is picked automatically each run (avoids "Address already in
use" if a previous run's server was orphaned rather than cleanly killed).
All output is kept under .build/minecraft-import.
USAGE
}

free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'
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

select_device() {
    if [[ -n "${DEVICE_ID:-}" ]]; then
        printf '%s\n' "$DEVICE_ID"
        return
    fi

    local json_path
    json_path="$(discover_devices)"
    local count
    count="$(jq -r "$physical_iphone_filter | length" "$json_path")"
    case "$count" in
        0)
            echo "error: no connected physical iPhones found." >&2
            exit 1
            ;;
        1)
            jq -r "$physical_iphone_filter | .[0].identifier" "$json_path"
            ;;
        *)
            echo "error: multiple connected physical iPhones found; set DEVICE_ID." >&2
            jq -r "$physical_iphone_filter | .[] | [.identifier, .deviceProperties.name] | @tsv" "$json_path" >&2
            exit 1
            ;;
    esac
}

lan_ip() {
    local iface
    iface="$(route get 1.1.1.1 2>/dev/null | awk '/interface:/{print $2}')"
    if [[ -z "$iface" ]]; then
        echo "error: could not determine the active network interface." >&2
        exit 1
    fi

    local ip
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [[ -z "$ip" ]]; then
        echo "error: could not determine a LAN IP for interface $iface. Ensure the Mac and iPhone are on the same Wi-Fi network." >&2
        exit 1
    fi
    printf '%s\n' "$ip"
}

build_fixture() {
    mkdir -p "$FIXTURE_DIR"
    swift build --package-path "$ROOT_DIR" --product MinecraftFixture >&2
    local bin_dir
    bin_dir="$(swift build --package-path "$ROOT_DIR" --show-bin-path)"
    "$bin_dir/MinecraftFixture" "$FIXTURE_DIR"
}

main() {
    require_tool jq
    require_tool xcodebuild
    require_tool xcrun
    require_tool swift
    require_tool python3

    case "${1:-}" in
        -h|--help|help)
            usage
            exit 0
            ;;
    esac

    # A physical orientation change mid-run re-lays out Safari and can drop
    # keyboard focus right when the test is about to type into the address
    # bar — a strong live suspect for the address-bar flake this script
    # retries around (see MinecraftHandoffUITests.swift). No CLI/XCUITest API
    # exposes whether rotation lock is on, so just ask rather than guessing.
    echo "Reminder: keep the iPhone's rotation lock ON for this run — physical rotation mid-test can interrupt Safari and is a likely cause of the address-bar retry below."

    mkdir -p "$OUTPUT_DIR"

    local mcaddon_path display_name
    if [[ -n "${1:-}" ]]; then
        mcaddon_path="$1"
        display_name="${MCADDON_DISPLAY_NAME:-Craftberry add-on}"
    else
        echo "Generating a fresh fixture .mcaddon (no device involved)..."
        local fixture_json
        fixture_json="$(build_fixture)"
        echo "$fixture_json" > "$OUTPUT_DIR/fixture.json"
        mcaddon_path="$(jq -r '.artifactPath' <<<"$fixture_json")"
        display_name="$(jq -r '.displayName' <<<"$fixture_json")"
    fi

    if [[ ! -f "$mcaddon_path" ]]; then
        echo "error: .mcaddon not found at $mcaddon_path" >&2
        exit 1
    fi

    local serve_dir file_name
    serve_dir="$(mktemp -d "$OUTPUT_DIR/serve.XXXXXX")"
    file_name="$(basename "$mcaddon_path")"
    cp "$mcaddon_path" "$serve_dir/$file_name"

    local server_port
    server_port="${MCADDON_SERVER_PORT:-$(free_port)}"

    local ip url
    ip="$(lan_ip)"
    url="http://$ip:$server_port/$file_name"

    echo "Serving $file_name at $url"
    (cd "$serve_dir" && exec python3 -m http.server "$server_port") >"$OUTPUT_DIR/http-server.log" 2>&1 &
    # Deliberately not `local`: the EXIT trap fires after main() returns, at
    # which point a local would already be out of scope, and `set -u` would
    # turn every cleanup into "unbound variable" — silently leaking this
    # server process. Confirmed live: every run this session orphaned its
    # server until this fix (14 leaked python3 processes cleaned up by hand).
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM

    sleep 1
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "error: local HTTP server failed to start; see $OUTPUT_DIR/http-server.log" >&2
        exit 1
    fi

    local device_id
    device_id="$(select_device)"

    # xcodebuild's TEST_RUNNER_ environment-variable forwarding only reaches
    # the simulator's local test process, not the on-device test runner app,
    # so pass values via a bundled resource file written before the build
    # instead (see MinecraftHandoffUITests.swift).
    jq -n --arg url "$url" --arg name "$display_name" '{mcaddonURL: $url, displayName: $name}' > "$IMPORT_CONFIG_PATH"

    # Safari's address bar has a known live flake (intermittently loses
    # keyboard focus right after tapping — confirmed this session across
    # several different in-test mitigations that didn't fully eliminate it).
    # Retry the whole test invocation rather than chasing that race further.
    local max_attempts=3
    local attempt succeeded=0
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        local result_path="$OUTPUT_DIR/MinecraftHandoffUITests-$(date +%Y%m%d-%H%M%S)-attempt${attempt}.xcresult"
        echo "Driving Safari on device $device_id to import $url (display name: $display_name) [attempt $attempt/$max_attempts]"
        if xcodebuild \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -destination "platform=iOS,id=$device_id" \
            -derivedDataPath "$DERIVED_DATA" \
            -resultBundlePath "$result_path" \
            -allowProvisioningUpdates \
            -only-testing:CraftberryUITests/MinecraftHandoffUITests/testDownloadsAndHandsOffToMinecraft \
            test; then
            succeeded=1
            echo "Result bundle: $result_path"
            break
        fi
        echo "Attempt $attempt failed; result bundle: $result_path" >&2
    done

    if [[ "$succeeded" != "1" ]]; then
        echo "error: import handoff failed after $max_attempts attempts." >&2
        exit 1
    fi

    echo "Import handoff complete. Next: scripts/minecraft-mirror-drive.sh to activate and verify \"$display_name\" in-game."
}

main "$@"
