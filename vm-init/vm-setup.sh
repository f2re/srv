#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_ROOT="/opt/infra-vm-init-kit"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -E bash "$SOURCE_ROOT/vm-setup.sh" "$@"
fi

# Keep the installer on the VM so health checks and controlled re-runs remain available
# after the unpacked upload directory is removed.
if [[ "$SOURCE_ROOT" != "$INSTALL_ROOT" ]]; then
  mkdir -p "$INSTALL_ROOT"
  cp -a "$SOURCE_ROOT/." "$INSTALL_ROOT/"
  chmod -R go-w "$INSTALL_ROOT"
  exec bash "$INSTALL_ROOT/vm-setup.sh" "$@"
fi

exec bash "$INSTALL_ROOT/setup.sh" "$@"
