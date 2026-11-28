#!/usr/bin/env bash
# Smoke test for a deployed generation Worker. Usage: scripts/smoke.sh https://<worker-url>
# Checks: health, challenge issue, and that /v1/generate is rejected without attestation.
set -euo pipefail

BASE="${1:-${SMOKE_BASE_URL:-}}"
if [[ -z "$BASE" ]]; then
  echo "usage: $0 <base-url>" >&2
  exit 2
fi
BASE="${BASE%/}"
fail() { echo "FAIL: $*" >&2; exit 1; }

health=$(curl -fsS "$BASE/health") || fail "health request failed"
echo "$health" | grep -q '"ok":true' || fail "health not ok: $health"
echo "ok   health: $health"

challenge=$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/v1/session/challenge") \
  || fail "challenge request failed"
echo "$challenge" | grep -q '"challengeID"' || fail "no challengeID: $challenge"
echo "$challenge" | grep -Eq '"expiresAt":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z"' || fail "bad expiresAt: $challenge"
echo "ok   challenge issued"

body='{"intentVersion":1,"profileID":"bedrock-stable-1.26.30","prompt":"smoke test"}'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$body" "$BASE/v1/generate")
[[ "$status" == "401" ]] || fail "unattested generate expected 401, got $status"
echo "ok   generate without attestation rejected (401)"

status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $(printf 'A%.0s' {1..43})" -d "$body" "$BASE/v1/generate")
[[ "$status" == "401" ]] || fail "unknown session expected 401, got $status"
echo "ok   unknown session rejected (401)"
echo "smoke passed: $BASE"
