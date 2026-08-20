#!/usr/bin/env bash
# shellcheck shell=bash

KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR=/var/lib/infra-provision
BACKUP_ROOT=/var/backups/infra-provision
CONFIG_FILE=/etc/infra-provision/config.env
mkdir -p "$STATE_DIR" "$BACKUP_ROOT" /etc/infra-provision /var/log/infra-provision
chmod 700 /etc/infra-provision

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo 'Запустите через sudo/root.' >&2
    exit 1
  fi
}

check_ubuntu() {
  . /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || { ui_warn 'Неподдерживаемая ОС' "Ожидалась Ubuntu, обнаружено ${PRETTY_NAME:-unknown}."; return 1; }
  case "${VERSION_ID:-}" in
    22.04|24.04) return 0 ;;
    26.04)
      ui_warn 'Ubuntu 26.04' 'Эта версия новее целевой матрицы комплекта. Базовая подготовка обычно работает, но отдельные продукты могут ещё не публиковать пакеты. Для production используйте Ubuntu 24.04 LTS.'
      ui_yesno 'Непроверенная версия' 'Продолжить на Ubuntu 26.04?' no
      return $?
      ;;
    *) ui_warn 'Версия Ubuntu' "Поддерживаются Ubuntu 22.04/24.04. Обнаружено: ${VERSION_ID:-unknown}."; return 2 ;;
  esac
}

backup_path() {
  local p="$1" stamp dest
  [[ -e "$p" || -L "$p" ]] || return 0
  stamp=$(date +%Y%m%d-%H%M%S)
  dest="$BACKUP_ROOT/$stamp${p}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$p" "$dest"
  log INFO "Backup: $p -> $dest"
}

mark_done() { mkdir -p "$STATE_DIR/steps"; date --iso-8601=seconds > "$STATE_DIR/steps/$1"; }
is_done() { [[ -f "$STATE_DIR/steps/$1" ]]; }

step_once() {
  local key="$1" label="$2"; shift 2
  if is_done "$key"; then
    log INFO "SKIP already done: $label"
    return 0
  fi
  run_step "$label" "$@"
  mark_done "$key"
}

wait_for_apt_locks() {
  local i
  for i in {1..60}; do
    if ! fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo 'APT/DPKG lock не освободился за 120 секунд.' >&2
  return 75
}

apt_update() {
  export DEBIAN_FRONTEND=noninteractive
  wait_for_apt_locks
  apt-get update
}

apt_upgrade() {
  export DEBIAN_FRONTEND=noninteractive
  wait_for_apt_locks
  apt-get -y -o Dpkg::Options::='--force-confold' upgrade
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  wait_for_apt_locks
  apt-get install -y --no-install-recommends "$@"
}

service_enable_now() { systemctl enable --now "$1"; }

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 )); }
valid_hostname() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; }
valid_fqdn() { [[ "$1" == *.* ]] && valid_hostname "$1"; }

get_admin_user() {
  local u="${ADMIN_USER:-${SUDO_USER:-}}"
  if [[ -z "$u" || "$u" == root ]]; then
    u=$(awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
  fi
  [[ -n "$u" ]] || u=root
  printf '%s' "$u"
}

has_authorized_key() {
  local u="$1" home
  home=$(getent passwd "$u" | cut -d: -f6)
  [[ -s "$home/.ssh/authorized_keys" ]]
}

write_config_kv() {
  local key="$1" value="$2"
  touch "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
  grep -v -E "^${key}=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || true
  printf '%s=%q\n' "$key" "$value" >> "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

load_config() { [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"; }

ensure_swap() {
  local gib="${1:-2}"
  swapon --show --noheadings | grep -q . && return 0
  [[ -f /swapfile ]] || fallocate -l "${gib}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
}

check_ram_gib() {
  local min="$1" mem_kib
  mem_kib=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
  (( mem_kib >= min * 1024 * 1024 ))
}

check_free_gib() {
  local path="$1" min="$2" avail
  avail=$(df -Pk "$path" | awk 'NR==2 {print $4}')
  (( avail >= min * 1024 * 1024 ))
}

port_in_use() { ss -lntup 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]$1$"; }

system_report() {
  local out=/var/log/infra-provision/system-report.txt
  {
    echo "Generated: $(date --iso-8601=seconds)"
    echo '== OS =='; cat /etc/os-release
    echo '== Kernel =='; uname -a
    echo '== CPU =='; nproc; lscpu | grep -E 'Model name|Virtualization|Architecture' || true
    echo '== RAM =='; free -h
    echo '== Disk =='; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS; df -hT
    echo '== Network =='; ip -br addr; ip route
    echo '== Listening =='; ss -lntup
    echo '== Services failed =='; systemctl --failed --no-pager || true
  } > "$out"
}

set_hostname_safe() {
  local new="$1"
  valid_hostname "$new" || return 2
  hostnamectl set-hostname "$new"
  if ! grep -qE "^127\.0\.1\.1\s+${new//./\\.}([[:space:]]|$)" /etc/hosts; then
    sed -i '/^127\.0\.1\.1[[:space:]]/d' /etc/hosts
    echo "127.0.1.1 $new ${new%%.*}" >> /etc/hosts
  fi
}

wait_for_dns() {
  getent ahosts archive.ubuntu.com >/dev/null 2>&1 || getent ahosts security.ubuntu.com >/dev/null 2>&1
}
