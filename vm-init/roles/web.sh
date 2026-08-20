#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
source "$KIT_ROOT/lib/node.sh"
require_root; require_base

install_python_stack() { apt_install python3 python3-venv python3-pip pipx build-essential libpq-dev; }
install_php_stack() { apt_install nginx php-fpm php-cli php-curl php-gd php-intl php-mbstring php-xml php-zip php-pgsql php-mysql; }

main() {
  local stack
  stack=$(ui_menu 'Web host' 'Выберите runtime. Можно повторно запустить роль и добавить другой:' \
    python 'Python/FastAPI/Flask/Django' node 'Node.js 24 LTS' php 'PHP-FPM + Nginx' docker 'Docker/Compose host' nginx 'Только Nginx/static')
  ensure_service_user webapp /srv/webapp
  mkdir -p /srv/webapp/app /srv/webapp/data /srv/webapp/releases
  chown -R webapp:webapp /srv/webapp
  case "$stack" in
    python) run_step 'Установка Python runtime' install_python_stack ;;
    node) run_step 'Установка Node.js 24 LTS из официальных binaries с SHA256' install_node_lts 24 ;;
    php) run_step 'Установка PHP-FPM/Nginx' install_php_stack; run_step 'Запуск Nginx' service_enable_now nginx ;;
    docker) warn_docker_firewall; ensure_docker ;;
    nginx) run_step 'Установка Nginx' apt_install nginx; run_step 'Запуск Nginx' service_enable_now nginx ;;
  esac
  cat > /etc/systemd/system/webapp.service.example <<'EOT'
[Unit]
Description=Example web application service
After=network-online.target
Wants=network-online.target

[Service]
User=webapp
Group=webapp
WorkingDirectory=/srv/webapp/app
# Replace ExecStart with actual application command.
ExecStart=/usr/bin/false
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/srv/webapp

[Install]
WantedBy=multi-user.target
EOT
  finish_role web "Web VM подготовлена. Runtime: $stack. Каталог приложения: /srv/webapp/app. Пример unit: /etc/systemd/system/webapp.service.example."
}
main "$@"
