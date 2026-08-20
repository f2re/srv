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
done < <(find vm-init -type f -name '*.sh' -print0; printf '%s\0' install.sh update.sh)

python3 -m compileall -q migration/orchestrator.py migration/remote_agent.py migration/mail-migration/mailbox_sync.py

if python3 -c 'import pytest' >/dev/null 2>&1; then
  (cd migration && python3 -m pytest -q)
else
  echo 'pytest не установлен — Python unit tests пропущены.' >&2
fi

[[ -x install.sh && -x update.sh && -x vm-init/vm-setup.sh ]] || {
  echo 'Критические entrypoint-скрипты должны быть executable.' >&2
  fail=1
}

exit "$fail"
