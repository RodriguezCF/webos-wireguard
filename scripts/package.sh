#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_ID="com.github.cfernande1470.wireguard"
VERSION="1.0.8"
APP="$ROOT/app/$APP_ID"
DIST="$ROOT/dist"
PACKAGER="${ARES_PACKAGE:-ares-package}"
IPK="$DIST/${APP_ID}_${VERSION}_all.ipk"

command -v "$PACKAGER" >/dev/null 2>&1 || {
  echo "ERROR: ares-package is required." >&2
  echo "Install @webos-tools/cli or webosbrew/ares-cli-rs, or set ARES_PACKAGE to its path." >&2
  exit 1
}

mkdir -p "$DIST"
rm -f "$IPK"

"$PACKAGER" --force-arch all --outdir "$DIST" "$APP"

test -f "$IPK" || {
  echo "ERROR: ares-package did not create $IPK" >&2
  exit 1
}

python3 - "$ROOT/$APP_ID.manifest.json" "$IPK" "$DIST/$APP_ID.manifest.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
manifest["ipkHash"] = {"sha256": hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()}
Path(sys.argv[3]).write_text(json.dumps(manifest, indent=2) + "\n")
PY

echo "Created $IPK"
echo "Created $DIST/$APP_ID.manifest.json"
