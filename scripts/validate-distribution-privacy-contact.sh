#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi

info_plist="${BUILT_PRODUCTS_DIR:?}/${INFOPLIST_PATH:?}"
if [ ! -f "$info_plist" ]; then
    echo "error: Release privacy-contact validation could not find $info_plist" >&2
    exit 1
fi

python3 - "$info_plist" <<'PY'
import plistlib
import sys
from urllib.parse import urlsplit

with open(sys.argv[1], "rb") as plist_file:
    contact = plistlib.load(plist_file).get("PrivacyContactURL")

if not isinstance(contact, str):
    contact = ""
lowered = contact.strip().lower()
try:
    parsed = urlsplit(contact.strip())
    host = (parsed.hostname or "").lower()
except ValueError:
    parsed = None
    host = ""

placeholder_hosts = {"example.com", "example.org", "example.net", "example.invalid"}
placeholder_suffixes = (
    ".example", ".example.com", ".example.org", ".example.net", ".invalid", ".test"
)
placeholder_terms = ("placeholder", "your-domain", "yourdomain", "replace-me", "change-me", "$", "<", ">")
valid = (
    parsed is not None
    and parsed.scheme.lower() == "https"
    and host
    and host not in placeholder_hosts
    and host not in {"localhost", "127.0.0.1", "::1"}
    and not host.endswith(placeholder_suffixes)
    and not any(term in lowered for term in placeholder_terms)
)

if not valid:
    print("error: Release builds require a real HTTPS privacy contact URL in CRAFTBERRY_PRIVACY_CONTACT_URL.", file=sys.stderr)
    raise SystemExit(1)

print("Release privacy contact URL is configured.")
PY
