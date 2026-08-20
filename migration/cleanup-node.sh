#!/usr/bin/env bash
set -Eeuo pipefail
MIG_USER="${1:-migration}"
[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
rm -f "/etc/sudoers.d/90-migkit-${MIG_USER}"
rm -rf /opt/migkit
if id "$MIG_USER" >/dev/null 2>&1; then
  userdel --remove "$MIG_USER" 2>/dev/null || userdel "$MIG_USER"
fi
echo "Migration account and agent removed. Bundles under /var/lib/migkit/runs were intentionally retained."
