#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
while IFS= read -r -d '' f; do
  if ! bash -n "$f"; then
    echo "bash -n FAILED: $f" >&2
    fail=1
  fi
done < <(find vm-init migration -type f -name '*.sh' -print0; printf '%s\0' install.sh update.sh)

for f in install.sh update.sh vm-init/vm-setup.sh vm-init/setup.sh vm-init/healthcheck.sh; do
  [[ -f "$f" ]] || { echo "MISSING: $f" >&2; fail=1; }
done
python3 -m compileall -q migration/mail-migration/mailbox_sync.py

(cd archives && sha256sum -c SHA256SUMS)
archive="archives/infrastructure-migration-kit-v1.0.0.tar.gz"
if [[ -f "$archive" ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  tar -xzf "$archive" -C "$tmp"
  python3 -m compileall -q "$tmp/orchestrator.py" "$tmp/remote_agent.py" "$tmp/mail-migration/mailbox_sync.py"
  while IFS= read -r -d '' f; do bash -n "$f"; done < <(find "$tmp" -type f -name '*.sh' -print0)
  if python3 -c 'import pytest' >/dev/null 2>&1; then
    (cd "$tmp" && python3 -m pytest -q)
  else
    echo 'pytest не установлен — migration unit tests пропущены.' >&2
  fi
else
  echo "MISSING: $archive" >&2
  fail=1
fi

[[ -x install.sh && -x update.sh ]] || {
  echo 'Root bootstrap/update entrypoints must be executable.' >&2
  fail=1
}

exit "$fail"
