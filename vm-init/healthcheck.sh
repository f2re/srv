#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT_ROOT/lib/ui.sh"
source "$KIT_ROOT/lib/common.sh"
require_root
load_config

ok=0; warn=0; bad=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '[ OK ] %s\n' "$label"; ((ok+=1));
  else printf '[FAIL] %s\n' "$label"; ((bad+=1)); fi
}
check_opt() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '[ OK ] %s\n' "$label"; ((ok+=1));
  else printf '[WARN] %s\n' "$label"; ((warn+=1)); fi
}
root_space_ok() {
  local used
  used=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  [[ "$used" =~ ^[0-9]+$ ]] && (( used < 90 ))
}
compose_healthy() {
  local dir="$1"
  cd "$dir"
  docker compose ps -q | grep -q . || return 1
  ! docker compose ps --status exited -q | grep -q .
}

printf 'Infrastructure VM healthcheck — %s\n\n' "$(date --iso-8601=seconds)"
check 'systemd: no failed units' bash -lc '! systemctl --failed --no-legend | grep -q .'
check_opt 'QEMU Guest Agent active' systemctl is-active qemu-guest-agent
check 'SSH config valid' sshd -t
check 'Fail2Ban active' systemctl is-active fail2ban
check 'Fail2Ban sshd jail' fail2ban-client status sshd
check_opt 'NTP synchronized' bash -lc 'timedatectl show -p NTPSynchronized --value | grep -qx yes'
check_opt 'Root FS below 90%' root_space_ok

role="${ROLE:-}"
case "$role" in
  gitlab)
    check 'GitLab status' gitlab-ctl status
    check 'GitLab application check' gitlab-rake gitlab:check SANITIZE=true
    ;;
  gitlab-runner) check 'GitLab Runner service' systemctl is-active gitlab-runner ;;
  edge) check 'nginx config' nginx -t; check 'nginx service' systemctl is-active nginx ;;
  fileserver) check 'Samba config' testparm -s; check 'Samba service' systemctl is-active smbd ;;
  monitoring)
    check 'Prometheus' systemctl is-active prometheus
    check 'Alertmanager' systemctl is-active prometheus-alertmanager
    check 'Node exporter' systemctl is-active prometheus-node-exporter
    check 'Grafana' systemctl is-active grafana-server
    ;;
  planka) check 'PLANKA compose' compose_healthy /opt/planka ;;
  nextcloud) check 'Nextcloud compose' compose_healthy /opt/nextcloud ;;
  mailcow) check 'Mailcow compose' compose_healthy /opt/mailcow-dockerized ;;
  mail-lite)
    check 'Postfix config' postfix check
    check 'Postfix service' systemctl is-active postfix
    check 'Dovecot service' systemctl is-active dovecot
    check 'Rspamd service' systemctl is-active rspamd
    ;;
  sftpgo) check 'SFTPGo compose' compose_healthy /opt/sftpgo ;;
  vaultwarden) check 'Vaultwarden compose' compose_healthy /opt/vaultwarden ;;
  telemetry|web) : ;;
esac

printf '\nResult: OK=%d WARN=%d FAIL=%d\n' "$ok" "$warn" "$bad"
((bad == 0))
