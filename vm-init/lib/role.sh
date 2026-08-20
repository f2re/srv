#!/usr/bin/env bash
# shellcheck shell=bash

source "$KIT_ROOT/lib/ui.sh"
source "$KIT_ROOT/lib/common.sh"
load_config

require_base() {
  is_done base || { ui_warn 'Базовая настройка' 'Сначала запустите sudo ./setup.sh --base-only'; exit 2; }
}

ufw_allow_if_host() {
  local rule="$1" comment="${2:-service}"
  [[ "${FIREWALL_MODE:-keep}" == host ]] || return 0
  ufw allow "$rule" comment "$comment"
}

ufw_allow_from_if_host() {
  local src="$1" port="$2" proto="${3:-tcp}" comment="${4:-service}"
  [[ "${FIREWALL_MODE:-keep}" == host ]] || return 0
  ufw allow from "$src" to any port "$port" proto "$proto" comment "$comment"
}

ensure_service_user() {
  local u="$1" home="${2:-/srv/$1}"
  if ! id "$u" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$home" --shell /usr/sbin/nologin "$u"
  fi
}

finish_role() {
  local role="$1" msg="$2"
  write_config_kv ROLE "$role"
  run_step "Финальная проверка роли $role" bash "$KIT_ROOT/healthcheck.sh"
  mark_done "role-$role"
  system_report || true
  ui_info 'Готово' "$msg\n\nПовторная проверка: sudo /opt/infra-vm-init-kit/healthcheck.sh\nПовторный мастер: sudo /opt/infra-vm-init-kit/vm-setup.sh\nЖурнал: $PROVISION_LOG"
}

source "$KIT_ROOT/lib/storage.sh"
