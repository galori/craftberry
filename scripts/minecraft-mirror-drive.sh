#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/.build/minecraft-mirror"
DEFAULT_STEPS_FILE="$SCRIPT_DIR/minecraft-activation-steps.json"

usage() {
    cat <<USAGE
Usage: scripts/minecraft-mirror-drive.sh <command> [args]

Leg 2 of physical-device Minecraft validation: drives Minecraft's own UI
(not accessibility-navigable, so XCUITest can't reach it) by sending
synthetic clicks into the Mac-side "iPhone Mirroring" window, and verifies
outcomes with screenshots + Vision-framework OCR (scripts/ocr.swift).

Requires you to have already started an iPhone Mirroring session by hand
(Spotlight -> "iPhone Mirroring" -> select the device -> authenticate on the
phone). There is no CLI/AppleScript API to start this non-interactively.

Commands:
  window                    Print the mirrored window's screen frame.
  screenshot [name]         Screenshot just the mirrored window, for calibration.
  tap <relX> <relY> [name]  Click inside the mirrored window at a fraction of
                             its width/height (0.0-1.0 each), then screenshot.
  run [steps.json]          Run a declarative step sequence (default:
                             scripts/minecraft-activation-steps.json). Each
                             step is one of:
                               {"type": "tap", "x": 0-1, "y": 0-1, "label": "..."}
                               {"type": "wait", "seconds": N, "label": "..."}
                               {"type": "ocr", "expect": "text", "label": "..."}
                             tap coordinates are fractions of the mirrored
                             window, not absolute pixels, so they survive
                             window resizes. A step with x/y still set to
                             null has not been calibrated against the live
                             device yet.

All screenshots and logs are kept under .build/minecraft-mirror.
USAGE
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool '$1' was not found on PATH" >&2
        exit 1
    fi
}

# Sets globals WIN_X/WIN_Y/WIN_W/WIN_H on success; returns non-zero on
# failure without exiting, so callers control how the failure surfaces
# (a plain `exit` inside a function only kills the $(...) subshell it runs
# in when invoked via command substitution, not the whole script).
window_frame() {
    local result
    result="$(osascript <<'APPLESCRIPT'
tell application "System Events"
    if not (exists process "iPhone Mirroring") then
        error "iPhone Mirroring is not running."
    end if
    tell process "iPhone Mirroring"
        set frontmost to true
        set winPos to position of window 1
        set winSize to size of window 1
    end tell
end tell
set px to item 1 of winPos
set py to item 2 of winPos
set sw to item 1 of winSize
set sh to item 2 of winSize
return (px as string) & "," & (py as string) & "," & (sw as string) & "," & (sh as string)
APPLESCRIPT
    )" || return 1
    IFS=',' read -r WIN_X WIN_Y WIN_W WIN_H <<<"$result"
}

require_window() {
    if ! window_frame; then
        echo "error: could not read the iPhone Mirroring window frame." >&2
        echo "Start a session by hand (Spotlight -> iPhone Mirroring -> select the device -> authenticate), then re-run this script." >&2
        exit 1
    fi
}

screenshot_window() {
    local out_path="$1"
    require_window
    mkdir -p "$(dirname "$out_path")"
    screencapture -x -R"${WIN_X},${WIN_Y},${WIN_W},${WIN_H}" "$out_path"
}

tap_relative() {
    local rel_x="$1" rel_y="$2"
    local abs_x abs_y
    require_window
    abs_x="$(python3 -c "print(round($WIN_X + $WIN_W * $rel_x))")"
    abs_y="$(python3 -c "print(round($WIN_Y + $WIN_H * $rel_y))")"
    osascript -e "tell application \"System Events\" to click at {$abs_x, $abs_y}"
}

cmd_window() {
    require_window
    echo "x,y,width,height = $WIN_X,$WIN_Y,$WIN_W,$WIN_H"
}

cmd_screenshot() {
    local name="${1:-screenshot}"
    mkdir -p "$OUTPUT_DIR"
    local out_path="$OUTPUT_DIR/${name}-$(date +%Y%m%d-%H%M%S).png"
    screenshot_window "$out_path"
    echo "Saved $out_path"
}

cmd_tap() {
    local rel_x="${1:?relX required}" rel_y="${2:?relY required}"
    local name="${3:-tap}"
    tap_relative "$rel_x" "$rel_y"
    sleep 1
    mkdir -p "$OUTPUT_DIR"
    local out_path="$OUTPUT_DIR/${name}-$(date +%Y%m%d-%H%M%S).png"
    screenshot_window "$out_path"
    echo "Tapped ($rel_x, $rel_y); saved $out_path"
}

cmd_run() {
    local steps_file="${1:-$DEFAULT_STEPS_FILE}"
    if [[ ! -f "$steps_file" ]]; then
        echo "error: steps file not found at $steps_file" >&2
        exit 1
    fi

    local run_dir="$OUTPUT_DIR/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$run_dir"

    local count
    count="$(jq 'length' "$steps_file")"
    for ((i = 0; i < count; i++)); do
        local step type label safe_label shot_path
        step="$(jq -c ".[$i]" "$steps_file")"
        type="$(jq -r '.type' <<<"$step")"
        label="$(jq -r '.label // .type' <<<"$step")"
        safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
        shot_path="$run_dir/$(printf '%02d' "$i")-${safe_label}.png"

        printf 'Step %02d (%s): %s\n' "$i" "$type" "$label"

        case "$type" in
            tap)
                local x y
                x="$(jq -r '.x' <<<"$step")"
                y="$(jq -r '.y' <<<"$step")"
                if [[ "$x" == "null" || "$y" == "null" ]]; then
                    echo "error: step $i (\"$label\") has no calibrated coordinates yet." >&2
                    echo "Run 'scripts/minecraft-mirror-drive.sh screenshot' to see the current view," >&2
                    echo "determine the tap location, and set x/y as fractions of window width/height in $steps_file." >&2
                    exit 1
                fi
                tap_relative "$x" "$y"
                sleep 1
                screenshot_window "$shot_path"
                ;;
            wait)
                local seconds
                seconds="$(jq -r '.seconds' <<<"$step")"
                sleep "$seconds"
                screenshot_window "$shot_path"
                ;;
            ocr)
                local expect
                expect="$(jq -r '.expect' <<<"$step")"
                screenshot_window "$shot_path"
                if ! swift "$SCRIPT_DIR/ocr.swift" "$shot_path" "$expect" >"$run_dir/$(printf '%02d' "$i")-${safe_label}.ocr.log" 2>&1; then
                    echo "error: OCR check failed for step $i (\"$label\"); expected text \"$expect\" not found." >&2
                    echo "See $shot_path and $run_dir/$(printf '%02d' "$i")-${safe_label}.ocr.log" >&2
                    exit 1
                fi
                echo "OCR match confirmed: \"$expect\""
                ;;
            *)
                echo "error: unknown step type '$type' at index $i" >&2
                exit 1
                ;;
        esac
    done

    echo "Run complete. Screenshots and logs in $run_dir"
}

main() {
    require_tool osascript
    require_tool screencapture
    require_tool jq
    require_tool python3
    require_tool swift

    local command="${1:-}"
    [[ $# -gt 0 ]] && shift || true

    case "$command" in
        window) cmd_window ;;
        screenshot) cmd_screenshot "$@" ;;
        tap) cmd_tap "$@" ;;
        run) cmd_run "$@" ;;
        -h|--help|help|"") usage ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
