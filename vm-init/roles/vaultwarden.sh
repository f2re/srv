#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

main() {
  local domain bind port admin_token
  warn_docker_firewall; ensure_docker
  if [[ -s /opt/vaultwarden/.env && -s /opt/vaultwarden/docker-compose.yml ]]; then
    ui_warn 'Vaultwarden уже инициализирован' 'Существующая .env будет переиспользована; ADMIN_TOKEN не регенерируется.'
    # shellcheck disable=SC1091
    source /opt/vaultwarden/.env
    domain="${DOMAIN:-unknown}"; bind="${VW_BIND:-0.0.0.0}"; port="${VW_PORT:-8000}"
  else
    domain=$(ui_input 'Vaultwarden' 'Публичный HTTPS URL' 'https://vault.example.org')
    bind=$(ui_input 'Vaultwarden' 'Backend bind address (127.0.0.1 только если reverse proxy на этой же VM)' '0.0.0.0')
    port=$(ui_input 'Vaultwarden' 'Backend port' '8000')
    admin_token=$(openssl rand -hex 48 | tr -d '\n')
    mkdir -p /opt/vaultwarden /srv/vaultwarden/data
    cat > /opt/vaultwarden/.env <<EOT
DOMAIN=$domain
VW_BIND=$bind
VW_PORT=$port
ADMIN_TOKEN=$admin_token
EOT
    chmod 600 /opt/vaultwarden/.env
    cat > /opt/vaultwarden/docker-compose.yml <<'EOT'
services:
  vaultwarden:
    image: vaultwarden/server:1.37.1
    restart: unless-stopped
    environment:
      DOMAIN: ${DOMAIN}
      ADMIN_TOKEN: ${ADMIN_TOKEN}
      SIGNUPS_ALLOWED: "false"
      INVITATIONS_ALLOWED: "true"
    volumes:
      - /srv/vaultwarden/data:/data
    ports:
      - "${VW_BIND}:${VW_PORT}:80"
EOT
    unset admin_token
  fi
  run_step 'Запуск Vaultwarden' bash -lc 'cd /opt/vaultwarden && docker compose pull && docker compose up -d'
  run_step 'Проверка Vaultwarden' bash -lc 'cd /opt/vaultwarden && docker compose ps'
  ui_warn 'Vaultwarden' 'Web Vault требует HTTPS. Не публикуйте backend напрямую в Интернет; используйте edge reverse proxy. ADMIN_TOKEN хранится только в /opt/vaultwarden/.env (0600). Включите MFA.'
  finish_role vaultwarden "Vaultwarden запущен на $bind:$port, domain=$domain."
}

main "$@"
