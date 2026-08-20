#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
source "$KIT_ROOT/lib/node.sh"
require_root; require_base

main() {
  offer_data_disk /srv/telemetry telemetry-data
  local stack
  stack=$(ui_menu 'Телеметрия' 'Базовый стек VM:' \
    pg-python 'PostgreSQL + Python venv (безопасный универсальный вариант)' \
    pg-node 'PostgreSQL + Node.js 24 LTS' \
    docker 'Docker/Compose для InfluxDB/VictoriaMetrics/ClickHouse/собственного стека' \
    base 'Только подготовленная Ubuntu; движок будет восстановлен migration-kit')
  mkdir -p /srv/telemetry/{app,data,archive}
  case "$stack" in
    pg-python)
      run_step 'Установка PostgreSQL/Python' apt_install postgresql postgresql-client python3-venv python3-pip build-essential libpq-dev
      run_step 'Запуск PostgreSQL' service_enable_now postgresql
      ;;
    pg-node)
      run_step 'Установка PostgreSQL' apt_install postgresql postgresql-client
      run_step 'Запуск PostgreSQL' service_enable_now postgresql
      run_step 'Установка Node.js 24 LTS' install_node_lts 24
      ;;
    docker) warn_docker_firewall; ensure_docker ;;
    base) : ;;
  esac
  ui_warn 'Данные телеметрии' 'Не размещайте большой ряд телеметрии на системном диске VM. Подключите отдельный disk/dataset до восстановления большого ряда.'
  finish_role telemetry "Telemetry VM подготовлена. Stack: $stack. Каталоги: /srv/telemetry/{app,data,archive}."
}
main "$@"
