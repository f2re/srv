#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

prepare_planka() {
  local base_url="$1" bind_addr="$2" port="$3" image="$4" dir=/opt/planka secret dbpass
  mkdir -p "$dir"
  secret=$(openssl rand -hex 64)
  dbpass=$(openssl rand -hex 32)
  cat > "$dir/.env" <<EOT
BASE_URL=$base_url
PLANKA_BIND_ADDR=$bind_addr
PLANKA_PORT=$port
PLANKA_IMAGE=$image
SECRET_KEY=$secret
POSTGRES_PASSWORD=$dbpass
EOT
  chmod 600 "$dir/.env"
  cat > "$dir/docker-compose.yml" <<'EOT'
services:
  planka:
    image: ${PLANKA_IMAGE:-ghcr.io/plankanban/planka:latest}
    restart: unless-stopped
    volumes:
      - data:/app/data
    ports:
      - "${PLANKA_BIND_ADDR:-0.0.0.0}:${PLANKA_PORT:-3000}:1337"
    environment:
      BASE_URL: ${BASE_URL}
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres/planka
      SECRET_KEY: ${SECRET_KEY}
      TRUST_PROXY: "true"
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: planka
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d planka"]
      interval: 10s
      timeout: 5s
      retries: 10

volumes:
  data:
  db-data:
EOT
  (cd "$dir" && docker compose config >/dev/null)
}

main() {
  local base_url bind_addr port image mode
  warn_docker_firewall
  ensure_docker

  if [[ -s /opt/planka/.env && -s /opt/planka/docker-compose.yml ]]; then
    ui_warn 'PLANKA уже инициализирована' 'Найдена существующая конфигурация. SECRET_KEY и пароль PostgreSQL будут сохранены; повторная генерация запрещена.'
    # shellcheck disable=SC1091
    source /opt/planka/.env
    base_url="${BASE_URL:-unknown}"
    bind_addr="${PLANKA_BIND_ADDR:-0.0.0.0}"
    port="${PLANKA_PORT:-3000}"
    image="${PLANKA_IMAGE:-ghcr.io/plankanban/planka:latest}"
  else
    base_url=$(ui_input 'PLANKA' 'BASE_URL' 'https://planka.example.org')
    bind_addr=$(ui_input 'PLANKA' 'IP интерфейса для публикации контейнера' '0.0.0.0')
    port=$(ui_input 'PLANKA' 'Локальный TCP-порт' '3000')
    valid_port "$port" || exit 2
    mode=$(ui_menu 'PLANKA image' 'Для новой установки можно использовать latest. Для миграции лучше указать тот же image/tag, что на исходном сервере:' \
      latest 'Новая установка: ghcr.io/plankanban/planka:latest' \
      exact 'Миграция/фиксированная версия: указать image:tag вручную')
    if [[ "$mode" == latest ]]; then
      image='ghcr.io/plankanban/planka:latest'
    else
      image=$(ui_input 'PLANKA image' 'Полное имя image:tag' 'ghcr.io/plankanban/planka:latest')
      [[ "$image" == *:* ]] || { ui_warn 'PLANKA image' 'Для фиксированной версии укажите tag, например ghcr.io/plankanban/planka:2.x.y'; exit 2; }
    fi
    run_step 'Подготовка PLANKA production compose' prepare_planka "$base_url" "$bind_addr" "$port" "$image"
  fi

  run_step 'Проверка PLANKA Compose' bash -lc 'cd /opt/planka && docker compose config >/dev/null'
  run_step 'Загрузка PLANKA images' bash -lc 'cd /opt/planka && docker compose pull'
  run_step 'Запуск PLANKA' bash -lc 'cd /opt/planka && docker compose up -d'
  run_step 'Проверка PLANKA containers' bash -lc 'cd /opt/planka && docker compose ps'

  if [[ ! -f /var/lib/infra-provision/planka-admin-created ]] && ui_yesno 'Администратор PLANKA' 'Создать администратора сейчас через штатный интерактивный мастер?' yes; then
    run_interactive_step 'Создание администратора PLANKA' bash -lc 'cd /opt/planka && docker compose run --rm planka npm run db:create-admin-user'
    touch /var/lib/infra-provision/planka-admin-created
  fi

  ui_warn 'Обновления PLANKA' "Используемый image: $image. Если это :latest, docker compose pull при повторном запуске может обновить приложение. Для стабильной production-миграции закрепите конкретный tag после проверки."
  finish_role planka "PLANKA запущена на $bind_addr:$port, BASE_URL=$base_url. Секреты: /opt/planka/.env (0600)."
}

main "$@"
