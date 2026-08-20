#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
require_root; require_base

install_grafana_repo() {
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg.tmp
  mv /etc/apt/keyrings/grafana.gpg.tmp /etc/apt/keyrings/grafana.gpg
  chmod 0644 /etc/apt/keyrings/grafana.gpg
  cat > /etc/apt/sources.list.d/grafana.sources <<'EOT'
Types: deb
URIs: https://apt.grafana.com
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/grafana.gpg
EOT
  apt-get update
  apt-get install -y grafana
}

main() {
  offer_data_disk /var/lib/prometheus monitoring-data
  local cidr
  cidr=$(ui_input 'Monitoring' 'Административная сеть/CIDR для Grafana и Prometheus' '10.0.10.0/24')
  run_step 'Установка Prometheus/Alertmanager/node-exporter' apt_install prometheus prometheus-alertmanager prometheus-node-exporter
  run_step 'Подключение репозитория и установка Grafana' install_grafana_repo
  run_step 'Запуск Prometheus' service_enable_now prometheus
  run_step 'Запуск Alertmanager' service_enable_now prometheus-alertmanager
  run_step 'Запуск node-exporter' service_enable_now prometheus-node-exporter
  run_step 'Запуск Grafana' service_enable_now grafana-server
  if [[ "${FIREWALL_MODE:-}" == host ]]; then
    ufw_allow_from_if_host "$cidr" 3000 tcp 'Grafana'
    ufw_allow_from_if_host "$cidr" 9090 tcp 'Prometheus'
    ufw_allow_from_if_host "$cidr" 9093 tcp 'Alertmanager'
    ufw_allow_from_if_host "$cidr" 9100 tcp 'node-exporter'
  fi
  ui_warn 'Grafana' 'После первого входа смените пароль admin, создайте отдельную учётную запись администратора и отключите анонимный доступ. Доступ к 3000/9090 должен быть только из management VLAN/VPN.'
  finish_role monitoring "Prometheus :9090, Alertmanager :9093, Grafana :3000, node-exporter :9100. Ограничьте доступ сетью $cidr."
}
main "$@"
