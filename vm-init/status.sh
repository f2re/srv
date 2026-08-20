#!/usr/bin/env bash
set -Eeuo pipefail
printf '=== Ubuntu VM Init Kit ===\n'
printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'OS:   '; . /etc/os-release; printf '%s\n' "$PRETTY_NAME"
printf 'Role: '
if [[ -f /etc/infra-provision/config.env ]]; then
  # shellcheck disable=SC1091
  source /etc/infra-provision/config.env
  printf '%s\n' "${ROLE:-not selected}"
else
  printf 'not selected\n'
fi
printf '\nCompleted steps:\n'
if [[ -d /var/lib/infra-provision/steps ]]; then
  for f in /var/lib/infra-provision/steps/*; do [[ -e "$f" ]] || continue; printf '  %-30s %s\n' "$(basename "$f")" "$(cat "$f")"; done
else
  echo '  none'
fi
printf '\nFailed systemd units:\n'
systemctl --failed --no-pager || true
printf '\nRecent provisioning log:\n'
tail -n 30 /var/log/infra-provision/provision.log 2>/dev/null || true
