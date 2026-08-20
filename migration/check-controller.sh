#!/usr/bin/env bash
set -Eeuo pipefail
missing=0
for cmd in python3 ssh scp rsync tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "MISSING: $cmd" >&2
    missing=1
  else
    echo "OK: $cmd -> $(command -v "$cmd")"
  fi
done
python3 - <<'PY'
import sys
if sys.version_info < (3, 8):
    raise SystemExit("Python 3.8+ is required on the controller")
print("OK: Python", sys.version.split()[0])
PY
if [[ "$missing" -ne 0 ]]; then
  exit "$missing"
fi

probe_dir="$(mktemp -d)"
trap 'rm -rf "$probe_dir"' EXIT
PROBE_DIR="$probe_dir" python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["PROBE_DIR"]) / "xattr-probe"
p.write_bytes(b"probe")
try:
    os.setxattr(p, b"user.migkit.probe", b"ok")
    assert os.getxattr(p, b"user.migkit.probe") == b"ok"
except (AttributeError, OSError) as exc:
    raise SystemExit("MISSING: staging filesystem does not support user xattr: {}".format(exc))
print("OK: staging filesystem supports user xattr")
PY
if ! rsync --help 2>&1 | grep -q -- '--fake-super'; then
  echo "MISSING: rsync does not advertise --fake-super" >&2
  exit 1
fi
echo "OK: rsync supports --fake-super"
