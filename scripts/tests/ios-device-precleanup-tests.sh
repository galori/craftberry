#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRATCH_DIR="$ROOT_DIR/.scratch"
mkdir -p "$SCRATCH_DIR"
TEST_ROOT="$(mktemp -d "$SCRATCH_DIR/ios-device-precleanup-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

cat > "$TEST_ROOT/failing-cleanup" <<'EOF'
#!/usr/bin/env bash
exit 37
EOF
chmod +x "$TEST_ROOT/failing-cleanup"

source "$ROOT_DIR/scripts/ios-device.sh"
CLEANUP_SCRIPT="$TEST_ROOT/failing-cleanup"
select_device() {
    CORE_DEVICE_ID="mock-core-device"
    XCODE_DEVICE_ID="mock-xcode-device"
}
terminate_minecraft_on_device() {
    :
}
xcodebuild() {
    touch "$TEST_ROOT/xcodebuild-ran"
    return 0
}

if minecraft_e2e_on_device furnace >"$TEST_ROOT/output.txt" 2>&1; then
    echo "FAIL: pre-test cleanup failure was ignored." >&2
    cat "$TEST_ROOT/output.txt" >&2
    exit 1
else
    cleanup_status=$?
fi

if [[ "$cleanup_status" -ne 37 ]]; then
    echo "FAIL: expected cleanup status 37, got $cleanup_status." >&2
    cat "$TEST_ROOT/output.txt" >&2
    exit 1
fi
if [[ -e "$TEST_ROOT/xcodebuild-ran" ]]; then
    echo "FAIL: xcodebuild ran after pre-test cleanup failed." >&2
    cat "$TEST_ROOT/output.txt" >&2
    exit 1
fi

echo "PASS: pre-test cleanup failure prevents xcodebuild"
