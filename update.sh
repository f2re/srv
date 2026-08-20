#!/usr/bin/env bash
set -Eeuo pipefail
DEST="${SRV_INSTALL_DIR:-/opt/srv}"
REF="${SRV_REF:-main}"
[[ ${EUID:-$(id -u)} -eq 0 ]] || exec sudo -E "$0" "$@"
[[ -d "$DEST/.git" ]] || { echo "Нет $DEST/.git. Сначала запустите install.sh." >&2; exit 2; }
git -C "$DEST" fetch --depth 1 origin "$REF"
git -C "$DEST" reset --hard FETCH_HEAD
printf 'Обновлено: %s\n' "$(git -C "$DEST" rev-parse --short HEAD)"
