#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

prepare_nextcloud() {
  local domain="$1" bind_addr="$2" port="$3" admin="$4" admin_pass="$5" dir=/opt/nextcloud
  local pgpass
  pgpass=$(openssl rand -hex 32)
  mkdir -p "$dir" /srv/nextcloud/{data,postgres}
  chmod 750 /srv/nextcloud
  cat > "$dir/.env" <<EOT
NEXTCLOUD_DOMAIN=$domain
NEXTCLOUD_BIND_ADDR=$bind_addr
NEXTCLOUD_PORT=$port
NEXTCLOUD_ADMIN_USER=$admin
NEXTCLOUD_ADMIN_PASSWORD=$admin_pass
POSTGRES_PASSWORD=$pgpass
EOT
  chmod 600 "$dir/.env"
  cat > "$dir/docker-compose.yml" <<'EOT'
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: nextcloud
      POSTGRES_USER: nextcloud
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - /srv/nextcloud/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nextcloud -d nextcloud"]
      interval: 10s
      timeout: 5s
      retries: 10
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis:/data
  app:
    image: nextcloud:34-apache
    restart: unless-stopped
    ports:
      - "${NEXTCLOUD_BIND_ADDR:-0.0.0.0}:${NEXTCLOUD_PORT:-8080}:80"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    environment:
      POSTGRES_HOST: db
      POSTGRES_DB: nextcloud
      POSTGRES_USER: nextcloud
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_HOST: redis
      NEXTCLOUD_ADMIN_USER: ${NEXTCLOUD_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_DOMAIN}
    volumes:
      - nextcloud:/var/www/html
      - /srv/nextcloud/data:/var/www/html/data
  cron:
    image: nextcloud:34-apache
    restart: unless-stopped
    entrypoint: /cron.sh
    depends_on:
      - app
    volumes:
      - nextcloud:/var/www/html
      - /srv/nextcloud/data:/var/www/html/data
volumes:
  nextcloud:
  redis:
EOT
  (cd "$dir" && docker compose config >/dev/null)
}

main() {
  offer_data_disk /srv/nextcloud nextcloud-data
  local domain bind_addr port admin admin_pass pass_mode secret_file
  warn_docker_firewall; ensure_docker

  if [[ -s /opt/nextcloud/.env && -s /opt/nextcloud/docker-compose.yml ]]; then
    ui_warn 'Nextcloud уже инициализирован' 'Найдены /opt/nextcloud/.env и docker-compose.yml. Секреты БД НЕ будут генерироваться заново.'
    # shellcheck disable=SC1091
    source /opt/nextcloud/.env
    domain="${NEXTCLOUD_DOMAIN:-unknown}"
    bind_addr="${NEXTCLOUD_BIND_ADDR:-0.0.0.0}"
    port="${NEXTCLOUD_PORT:-8080}"
  else
    domain=$(ui_input 'Nextcloud' 'Trusted domain/FQDN' 'cloud.example.org')
    bind_addr=$(ui_input 'Nextcloud' 'IP для публикации HTTP backend' '0.0.0.0')
    port=$(ui_input 'Nextcloud' 'Backend TCP-порт' '8080')
    admin=$(ui_input 'Nextcloud' 'Имя первоначального администратора' 'ncadmin')
    pass_mode=$(ui_menu 'Nextcloud' 'Пароль первоначального администратора:' generated 'Сгенерировать безопасный пароль и сохранить root-only файлом' custom 'Ввести пароль вручную')
    if [[ "$pass_mode" == generated ]]; then
      admin_pass=$(openssl rand -hex 20)
    else
      while true; do
        admin_pass=$(ui_password 'Nextcloud' 'Пароль: минимум 12 символов; разрешены A-Z a-z 0-9 . _ ~ ! @ % + = : , ^ -')
        [[ ${#admin_pass} -ge 12 ]] || { ui_warn 'Пароль' 'Минимальная длина — 12 символов.'; continue; }
        [[ "$admin_pass" =~ ^[A-Za-z0-9._~!@%+=:,^-]+$ ]] || { ui_warn 'Пароль' 'Есть символы, небезопасные для Compose .env.'; continue; }
        break
      done
    fi
    run_step 'Подготовка Nextcloud Compose' prepare_nextcloud "$domain" "$bind_addr" "$port" "$admin" "$admin_pass"
    secret_file=/root/nextcloud-initial-admin.txt
    { printf 'user=%s\n' "$admin"; printf 'password='; grep '^NEXTCLOUD_ADMIN_PASSWORD=' /opt/nextcloud/.env | cut -d= -f2-; printf '\n'; } > "$secret_file"
    chmod 600 "$secret_file"
    unset admin_pass
  fi

  run_step 'Загрузка Nextcloud images' bash -lc 'cd /opt/nextcloud && docker compose pull'
  run_step 'Запуск Nextcloud' bash -lc 'cd /opt/nextcloud && docker compose up -d'
  run_step 'Проверка Nextcloud containers' bash -lc 'cd /opt/nextcloud && docker compose ps'
  ui_warn 'Данные Nextcloud' 'Каталог /srv/nextcloud/data предназначен только Nextcloud. Не публикуйте его одновременно по Samba. Для общих SMB-каталогов используйте External Storage внутри Nextcloud.'
  [[ -f /root/nextcloud-initial-admin.txt ]] && ui_info 'Учётная запись' 'Первоначальные реквизиты сохранены только для root в /root/nextcloud-initial-admin.txt. После входа смените пароль и удалите файл.'
  finish_role nextcloud "Nextcloud запущен на $bind_addr:$port для домена $domain. Reverse proxy должен передавать HTTPS/Host/X-Forwarded-Proto."
}

main "$@"
