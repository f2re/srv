#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
require_root; require_base

main() {
  run_step 'Установка Nginx и Certbot' apt_install nginx certbot python3-certbot-nginx
  backup_path /etc/nginx/nginx.conf
  cat > /etc/nginx/conf.d/99-infra-security.conf <<'EOT'
server_tokens off;
client_body_timeout 30s;
client_header_timeout 30s;
keepalive_timeout 65s;
send_timeout 30s;
EOT
  run_step 'Проверка Nginx' nginx -t
  run_step 'Запуск Nginx' service_enable_now nginx
  ufw_allow_if_host 80/tcp 'HTTP reverse proxy'
  ufw_allow_if_host 443/tcp 'HTTPS reverse proxy'
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  cat > /etc/nginx/sites-available/EXAMPLE-UPSTREAM.conf.disabled <<'EOT'
# Скопируйте файл и замените имена/адрес backend.
server {
    listen 80;
    server_name service.example.org;
    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_pass http://10.0.30.10:8080;
    }
}
EOT
  finish_role edge 'Edge VM готова: Nginx запущен, 80/443 разрешены при host-firewall. Конкретные upstream-конфиги намеренно не создаются без адресов сервисов.'
}
main "$@"
