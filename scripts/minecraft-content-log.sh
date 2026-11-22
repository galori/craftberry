#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.build/minecraft-content-log"
BUNDLE_ID="com.mojang.minecraftpe"
LOG_DIR="Documents/games/com.mojang/logs"
OPTIONS="Documents/games/com.mojang/minecraftpe/options.txt"

usage() {
    cat <<USAGE
Usage: scripts/minecraft-content-log.sh <command> [file]

Reads Minecraft Bedrock's Content Log from the connected iPhone over USB
(afcclient / House Arrest). Requires Settings > Creator > "Enable Content
Log File" to be on in Minecraft; the game only flushes that setting to disk
when it is backgrounded or restarted.

Commands:
  status        Is file logging enabled, which log files exist, how big
  list          List log file names (oldest to newest)
  show [file]   Print a log file (default: newest)
  errors [file] Print only [warn]/[error] lines (format: HH:MM:SS[Category][level]-text)
  mark          Remember the newest file's current size as a baseline
  since         Print what was appended after the last 'mark' (new file => all)

Set CONTENT_LOG_QUIET=1 to drop [verbose] and blank lines from show/since.
Minecraft writes the file in chunks (32 KB seen), so very recent lines may lag.
USAGE
}

afc() { afcclient --documents "$BUNDLE_ID" -- "$@"; }

# Log names sort chronologically because they embed a timestamp.
log_names() { afc ls "$LOG_DIR" 2>/dev/null | grep '^ContentLog.*\.txt$' | sort || true; }

newest() {
    local n
    n="$(log_names | tail -1)"
    [[ -n "$n" ]] || { echo "error: no ContentLog files on device (see 'status')" >&2; exit 1; }
    echo "$n"
}

# Downloads a log to a temp file and prints the local path.
fetch() {
    local tmp
    tmp="$(mktemp -d)/log.txt"
    afc get "$LOG_DIR/$1" "$tmp" >/dev/null
    echo "$tmp"
}

# Optionally strips the high-volume [verbose] lines (mostly [Sound]) and blanks.
filter() { if [[ "${CONTENT_LOG_QUIET:-0}" == 1 ]]; then grep -v -e '\]\[verbose\]' -e '^$' || true; else cat; fi; }

size_of() { wc -c <"$1" | tr -d ' '; }

cmd="${1:-}"; shift || true
command -v afcclient >/dev/null || { echo "error: afcclient not on PATH (brew install libimobiledevice)" >&2; exit 1; }

case "$cmd" in
    status)
        tmp="$(mktemp -d)/options.txt"
        if afc get "$OPTIONS" "$tmp" >/dev/null 2>&1; then
            grep -E '^content_log' "$tmp" || true
            grep -q '^content_log_file:1' "$tmp" || echo "WARNING: content_log_file is not 1. Enable it in Minecraft, then background/restart the app."
        else
            echo "error: cannot read options.txt (device locked/disconnected, or Minecraft not installed?)" >&2
        fi
        rm -f "$tmp"
        echo "log files:"; log_names | sed 's/^/  /'
        ;;
    list) log_names ;;
    show)
        f="${1:-$(newest)}"; tmp="$(fetch "$f")"; filter <"$tmp"; rm -f "$tmp" ;;
    errors)
        f="${1:-$(newest)}"; tmp="$(fetch "$f")"; grep -iE '\]\[(warn|warning|error)\]' "$tmp" || true; rm -f "$tmp" ;;
    mark)
        f="$(newest)"; tmp="$(fetch "$f")"; mkdir -p "$STATE_DIR"
        printf '%s %s\n' "$f" "$(size_of "$tmp")" >"$STATE_DIR/mark"
        echo "marked $f at $(size_of "$tmp") bytes"; rm -f "$tmp" ;;
    since)
        f="$(newest)"; tmp="$(fetch "$f")"; off=0
        if [[ -f "$STATE_DIR/mark" ]]; then
            read -r mf moff <"$STATE_DIR/mark"
            [[ "$mf" == "$f" ]] && off="$moff"
        fi
        tail -c +"$((off + 1))" "$tmp" | filter; rm -f "$tmp" ;;
    -h|--help|help|"") usage ;;
    *) usage >&2; exit 2 ;;
esac
