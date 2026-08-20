#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

main() {
  offer_data_disk /srv/sftpgo sftp-data
  local bind sftp_port web_port
  warn_docker_firewall; ensure_docker
  bind=$(ui_input 'SFTPGo' 'IP для публикации сервисов' '0.0.0.0')
  sftp_port=$(ui_input 'SFTPGo' 'SFTP порт' '2022')
  web_port=$(ui_input 'SFTPGo' 'WebAdmin/WebClient порт' '8081')
  valid_port "$sftp_port" && valid_port "$web_port" || exit 2
  mkdir -p /opt/sftpgo /srv/sftpgo/{data,config}
  cat > /opt/sftpgo/docker-compose.yml <<EOT
services:
  sftpgo:
    image: drakkan/sftpgo:v2.7.5
    restart: unless-stopped
    ports:
      - "$bind:$sftp_port:2022"
      - "$bind:$web_port:8080"
    volumes:
      - /srv/sftpgo/data:/srv/sftpgo
      - /srv/sftpgo/config:/var/lib/sftpgo
EOT
  run_step 'Проверка SFTPGo Compose' bash -lc 'cd /opt/sftpgo && docker compose config >/dev/null'
  run_step 'Запуск SFTPGo' bash -lc 'cd /opt/sftpgo && docker compose pull && docker compose up -d'
  run_step 'Проверка SFTPGo' bash -lc 'cd /opt/sftpgo && docker compose ps'
  ui_info 'Первичная настройка' "Откройте WebAdmin на http://HOST:$web_port и создайте первого администратора. Обновляйте image tag контролируемо."
  finish_role sftpgo "SFTPGo запущен: SFTP $sftp_port, Web $web_port. Данные: /srv/sftpgo."
}
main "$@"
