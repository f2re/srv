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

python3 -m compileall -q migration/orchestrator.py migration/remote_agent.py migration/mail-migration/mailbox_sync.py

if python3 -c 'import pytest' >/dev/null 2>&1; then
  (cd migration && python3 -m pytest -q)
else
  echo 'pytest не установлен — Python unit tests пропущены.' >&2
fi

[[ -x install.sh && -x update.sh ]] || {
  echo 'Root bootstrap/update entrypoints must be executable.' >&2
  fail=1
}

exit "$fail"
