#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/.build/minecraft-mirror"
DEFAULT_STEPS_FILE="$SCRIPT_DIR/minecraft-activation-steps.json"

usage() {
    cat <<'USAGE'
Usage: scripts/minecraft-mirror-drive.sh <command> [args]

Leg 2 of physical-device Minecraft validation: drives Minecraft's own UI
(not accessibility-navigable, so XCUITest can't reach it) through keyboard
focus navigation in the Mac-side "iPhone Mirroring" window, and verifies
outcomes with screenshots + Vision-framework OCR (scripts/ocr.swift).

Requires you to have already started an iPhone Mirroring session by hand
(Spotlight -> "iPhone Mirroring" -> select the device -> authenticate on the
phone). There is no CLI/AppleScript API to start this non-interactively.

Commands:
  window                    Print the mirrored window's screen frame.
  screenshot [name]         Screenshot just the mirrored window, for calibration.
  tap <relX> <relY> [name]  Click inside the mirrored window at a fraction of
                             its width/height (0.0-1.0 each), then screenshot.
  home                      Go to the Home Screen (View menu command; no
                             swipe gesture needed/available for Face ID
                             phones).
  spotlight                 Open Spotlight search (View menu command).
  type <text>               Type text via the keyboard into the current
                             focused field (routes to the mirrored phone).
  key <name> [count]        Send a key to the mirrored phone. Names: tab,
                             left, right, up, down, escape.
  confirm [count]           Send Return to confirm the focused control.
  run [steps.json]          Run a declarative step sequence (default:
                             scripts/minecraft-activation-steps.json). Each
                             step is one of:
                               {"type": "key", "key": "tab|left|right|up|down|escape", "count": N, "label": "..."}
                               {"type": "confirm", "count": N, "label": "..."}
                               {"type": "type", "text": "...", "label": "..."}
                               {"type": "wait", "seconds": N, "label": "..."}
                               {"type": "ocr", "expect": "text", "label": "..."}
                             Minecraft's Ore UI ignores mirrored pointer
                             clicks, so use key/confirm steps for its UI.
                             `tap` remains available only for ordinary iOS
                             views outside Minecraft.

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
    ensure_window_is_capturable
}

# `screencapture -R` silently crops a rectangle with a negative origin. Keep
# the mirror window on the primary display before computing any relative
# coordinates or taking evidence screenshots.
ensure_window_is_capturable() {
    if (( WIN_X < 0 || WIN_Y < 0 )); then
        echo "Repositioning iPhone Mirroring window onto the primary display." >&2
        osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
    tell process "iPhone Mirroring"
        set position of window 1 to {40, 40}
    end tell
end tell
APPLESCRIPT
        window_frame || {
            echo "error: could not re-read the repositioned iPhone Mirroring window frame." >&2
            exit 1
        }
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
    # AppleScript's `System Events click at` does not reliably register as a
    # touch on the mirrored surface (confirmed live: repeated taps on
    # unambiguous targets like Home Screen icons produced no reaction). A
    # raw Quartz mouseDown+mouseUp with a brief hold does.
    python3 "$SCRIPT_DIR/lib/mirror_click.py" "$abs_x" "$abs_y"
}

mirroring_menu_click() {
    local menu_item="$1"
    require_window
    osascript -e "tell application \"System Events\" to tell process \"iPhone Mirroring\" to click menu item \"$menu_item\" of menu 1 of menu bar item \"View\" of menu bar 1" >/dev/null
}

cmd_window() {
    require_window
    echo "x,y,width,height = $WIN_X,$WIN_Y,$WIN_W,$WIN_H"
}

cmd_home() {
    mirroring_menu_click "Home Screen"
}

cmd_spotlight() {
    mirroring_menu_click "Spotlight"
}

cmd_type() {
    local text="${1:?text required}"
    require_window
    osascript - "$text" <<'APPLESCRIPT' >/dev/null
on run argv
    tell application "System Events" to keystroke (item 1 of argv)
end run
APPLESCRIPT
}

key_code() {
    case "$1" in
        tab) echo 48 ;;
        left) echo 123 ;;
        right) echo 124 ;;
        down) echo 125 ;;
        up) echo 126 ;;
        escape) echo 53 ;;
        *)
            echo "error: unsupported key '$1'; use tab, left, right, up, down, or escape." >&2
            exit 1
            ;;
    esac
}

send_key() {
    local name="$1" count="${2:-1}" code
    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        echo "error: key count must be a positive integer, got '$count'." >&2
        exit 1
    }
    code="$(key_code "$name")"
    require_window
    for ((press = 0; press < count; press++)); do
        osascript -e "tell application \"System Events\" to key code $code" >/dev/null
        sleep 0.15
    done
}

cmd_key() {
    send_key "${1:?key name required}" "${2:-1}"
}

cmd_confirm() {
    local count="${1:-1}"
    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        echo "error: confirm count must be a positive integer, got '$count'." >&2
        exit 1
    }
    require_window
    for ((press = 0; press < count; press++)); do
        osascript -e 'tell application "System Events" to key code 36' >/dev/null
        sleep 0.15
    done
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
            key)
                local key count
                key="$(jq -r '.key' <<<"$step")"
                count="$(jq -r '.count // 1' <<<"$step")"
                send_key "$key" "$count"
                sleep 0.5
                screenshot_window "$shot_path"
                ;;
            confirm)
                local count
                count="$(jq -r '.count // 1' <<<"$step")"
                cmd_confirm "$count"
                sleep 0.5
                screenshot_window "$shot_path"
                ;;
            type)
                local text
                text="$(jq -r '.text' <<<"$step")"
                cmd_type "$text"
                sleep 0.5
                screenshot_window "$shot_path"
                ;;
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
        home) cmd_home ;;
        spotlight) cmd_spotlight ;;
        type) cmd_type "$@" ;;
        key) cmd_key "$@" ;;
        confirm) cmd_confirm "$@" ;;
        run) cmd_run "$@" ;;
        -h|--help|help|"") usage ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
