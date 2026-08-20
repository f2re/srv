#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

prepare_planka() {
  local base_url="$1" bind_addr="$2" port="$3" dir=/opt/planka secret dbpass
  mkdir -p "$dir"
  curl -fsSL https://raw.githubusercontent.com/plankanban/planka/master/docker-compose.yml -o "$dir/docker-compose.yml.upstream"
  cp "$dir/docker-compose.yml.upstream" "$dir/docker-compose.yml"
  secret=$(openssl rand -hex 64)
  dbpass=$(openssl rand -hex 32)
  cat > "$dir/.env" <<EOT
BASE_URL=$base_url
PLANKA_BIND_ADDR=$bind_addr
PLANKA_PORT=$port
SECRET_KEY=$secret
POSTGRES_PASSWORD=$dbpass
EOT
  chmod 600 "$dir/.env"
  python3 - "$dir/docker-compose.yml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
s=s.replace('      - 3000:1337','      - ${PLANKA_BIND_ADDR:-0.0.0.0}:${PLANKA_PORT:-3000}:1337')
s=s.replace('      - BASE_URL=http://localhost:3000','      - BASE_URL=${BASE_URL}')
s=s.replace('      - DATABASE_URL=postgresql://postgres@postgres/planka','      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres/planka')
s=s.replace('      - SECRET_KEY=notsecretkey','      - SECRET_KEY=${SECRET_KEY}')
s=s.replace('      - POSTGRES_HOST_AUTH_METHOD=trust','      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}')
p.write_text(s)
PY
  (cd "$dir" && docker compose config >/dev/null)
}

main() {
  local base_url bind_addr port
  warn_docker_firewall; ensure_docker
  if [[ -s /opt/planka/.env && -s /opt/planka/docker-compose.yml ]]; then
    ui_warn 'PLANKA уже инициализирована' 'Найдена существующая конфигурация. SECRET_KEY и пароль PostgreSQL будут сохранены; повторная генерация запрещена.'
    # shellcheck disable=SC1091
    source /opt/planka/.env
    base_url="${BASE_URL:-unknown}"
    bind_addr="${PLANKA_BIND_ADDR:-0.0.0.0}"
    port="${PLANKA_PORT:-3000}"
  else
    base_url=$(ui_input 'PLANKA' 'BASE_URL' 'https://planka.example.org')
    bind_addr=$(ui_input 'PLANKA' 'IP интерфейса для публикации контейнера' '0.0.0.0')
    port=$(ui_input 'PLANKA' 'Локальный TCP-порт' '3000')
    valid_port "$port" || exit 2
    run_step 'Подготовка PLANKA production compose' prepare_planka "$base_url" "$bind_addr" "$port"
  fi
  run_step 'Загрузка PLANKA images' bash -lc 'cd /opt/planka && docker compose pull'
  run_step 'Запуск PLANKA' bash -lc 'cd /opt/planka && docker compose up -d'
  run_step 'Проверка PLANKA containers' bash -lc 'cd /opt/planka && docker compose ps'
  if [[ ! -f /var/lib/infra-provision/planka-admin-created ]] && ui_yesno 'Администратор PLANKA' 'Создать администратора сейчас через штатный интерактивный мастер?' yes; then
    run_interactive_step 'Создание администратора PLANKA' bash -lc 'cd /opt/planka && docker compose run --rm planka npm run db:create-admin-user'
    touch /var/lib/infra-provision/planka-admin-created
  fi
  finish_role planka "PLANKA запущена на $bind_addr:$port, BASE_URL=$base_url. Секреты: /opt/planka/.env (0600)."
}

main "$@"
