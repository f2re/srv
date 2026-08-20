#!/usr/bin/env bash
set -Eeuo pipefail

KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
export KIT_ROOT
source "$KIT_ROOT/lib/ui.sh"
source "$KIT_ROOT/lib/common.sh"

usage() {
  cat <<'EOT'
Использование внутри Ubuntu VM:
  sudo ./vm-setup.sh                     # интерактивный выбор роли
  sudo ./vm-setup.sh --role gitlab
  sudo ./vm-setup.sh --role gitlab-runner
  sudo ./vm-setup.sh --base-only

Роли:
  edge, web, gitlab, gitlab-runner, planka, telemetry,
  fileserver, nextcloud, sftpgo, mailcow, mail-lite, monitoring, vaultwarden
EOT
}

role=''
base_only=0
while (($#)); do
  case "$1" in
    --role) role="${2:-}"; shift 2 ;;
    --base-only) base_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Неизвестный аргумент: $1" >&2; usage; exit 2 ;;
  esac
done

require_root
mkdir -p /var/log/infra-provision
load_config

if (( base_only == 0 )) && [[ -z "$role" ]]; then
  role=$(ui_menu 'Роль этой виртуальной машины' 'Выберите ОДНУ основную роль. Базовая защита Ubuntu будет установлена автоматически перед сервисом:' \
    gitlab 'GitLab CE/EE — репозитории, issues, CI coordinator' \
    gitlab-runner 'GitLab Runner/worker — Docker или Shell executor' \
    web 'Сайт/API — Python, Node.js, PHP, Docker или Nginx' \
    mailcow 'Почтовый сервер Mailcow (тяжёлый, 6+ GiB RAM)' \
    mail-lite 'Лёгкая почта — Postfix/Dovecot/Rspamd (для слабого хоста)' \
    planka 'PLANKA — управление задачами' \
    telemetry 'Телеметрия — PostgreSQL/Python/Node/Docker' \
    fileserver 'Файловый сервер — Samba/NFS' \
    nextcloud 'Nextcloud — web/mobile файлы, PostgreSQL, Redis' \
    sftpgo 'SFTPGo — защищённый файловый обмен' \
    monitoring 'Prometheus + Grafana + Alertmanager + node-exporter' \
    edge 'Nginx reverse proxy / TLS edge' \
    vaultwarden 'Vaultwarden — пароли и секреты пользователей')
fi

if (( base_only == 0 )); then
  script="$KIT_ROOT/roles/$role.sh"
  [[ -f "$script" ]] || { ui_warn 'Неизвестная роль' "$role"; usage; exit 2; }
  export ROLE="$role"
  write_config_kv ROLE "$role"
fi

if ! is_done base; then
  bash "$KIT_ROOT/base.sh"
fi

(( base_only == 1 )) && {
  ui_info 'Готово' 'Базовая подготовка Ubuntu завершена. Для установки сервиса снова запустите sudo /opt/infra-vm-init-kit/vm-setup.sh.'
  exit 0
}

if is_done "role-$role"; then
  ui_warn 'Роль уже настроена' "Роль $role ранее завершилась успешно. Повторный запуск может изменить конфигурацию."
  ui_yesno 'Повторный запуск' 'Продолжить повторную настройку роли?' no || exit 0
fi

exec bash "$script"
