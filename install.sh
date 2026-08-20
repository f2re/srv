#!/usr/bin/env bash
# Bootstrap f2re/srv on a freshly installed Ubuntu VM.
set -Eeuo pipefail
IFS=$'\n\t'

REPO_URL="${SRV_REPO_URL:-https://github.com/f2re/srv.git}"
REF="${SRV_REF:-main}"
DEST="${SRV_INSTALL_DIR:-/opt/srv}"
LOG="/var/log/srv-bootstrap.log"

log(){ printf '%s %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)" "$*" | tee -a "$LOG" >&2; }
die(){ log "ERROR: $*"; exit 1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die 'Нужен root/sudo.'
  exec sudo -E bash "$0" "$@"
fi

touch "$LOG"; chmod 600 "$LOG"
[[ -r /etc/os-release ]] || die 'Не удалось определить ОС.'
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "Поддерживается Ubuntu; обнаружено ${PRETTY_NAME:-unknown}."
case "${VERSION_ID:-}" in 22.04|24.04) :;; *) log "WARN: целевые версии 22.04/24.04; обнаружено ${VERSION_ID:-unknown}. Основной мастер запросит подтверждение или остановится.";; esac

export DEBIAN_FRONTEND=noninteractive
for _ in {1..60}; do
  if ! fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then break; fi
  sleep 2
done
apt-get update
apt-get install -y --no-install-recommends ca-certificates git curl

if [[ -d "$DEST/.git" ]]; then
  log "Обновление $DEST до origin/$REF"
  git -C "$DEST" remote set-url origin "$REPO_URL"
  git -C "$DEST" fetch --depth 1 origin "$REF"
  git -C "$DEST" reset --hard FETCH_HEAD
elif [[ -e "$DEST" ]]; then
  backup="${DEST}.backup.$(date +%Y%m%d-%H%M%S)"
  log "Существующий $DEST не является git checkout; перемещаю в $backup"
  mv "$DEST" "$backup"
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$DEST"
else
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$DEST"
fi

chmod -R go-w "$DEST"
log "Репозиторий готов: $DEST"
exec bash "$DEST/vm-init/vm-setup.sh" "$@"
