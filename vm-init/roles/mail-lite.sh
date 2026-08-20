#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
require_root; require_base

check_mail_ports_lite() {
  local p bad=0
  for p in 25 465 587 993; do
    if port_in_use "$p"; then
      echo "Порт уже занят: $p" >&2
      bad=1
    fi
  done
  return "$bad"
}

main() {
  local fqdn domain
  check_ram_gib 2 || ui_warn 'Mail Lite' 'Выделено меньше 2 GiB RAM. Для Rspamd/Dovecot/Postfix это нежелательно.'
  run_step 'Проверка SMTP/Submission/IMAPS портов' check_mail_ports_lite
  fqdn=$(ui_input 'Mail Lite' 'FQDN почтового сервера' 'mail.example.org')
  valid_fqdn "$fqdn" || { ui_warn 'FQDN' 'Введите полноценное имя, например mail.example.org.'; exit 2; }
  domain=$(ui_input 'Mail Lite' 'Основной почтовый домен' "${fqdn#*.}")
  ui_warn 'Публичная почта' 'До переключения MX проверьте PTR/reverse DNS, TCP/25 inbound/outbound, SPF, DKIM и DMARC. Скрипт не меняет DNS автоматически.'

  export DEBIAN_FRONTEND=noninteractive
  printf 'postfix postfix/mailname string %s\n' "$domain" | debconf-set-selections
  printf 'postfix postfix/main_mailer_type select Internet Site\n' | debconf-set-selections
  run_step 'Установка Postfix/Dovecot/Rspamd/Redis' apt_install postfix dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved rspamd redis-server opendkim opendkim-tools

  backup_path /etc/postfix/main.cf
  postconf -e "myhostname = $fqdn"
  postconf -e "mydomain = $domain"
  postconf -e 'home_mailbox = Maildir/'
  postconf -e 'smtpd_milters = inet:127.0.0.1:11332'
  postconf -e 'non_smtpd_milters = inet:127.0.0.1:11332'
  postconf -e 'milter_default_action = accept'
  postconf -e 'smtpd_helo_required = yes'
  postconf -e 'disable_vrfy_command = yes'
  sed -ri 's|^#?mail_location\s*=.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf

  run_step 'Запуск Redis' service_enable_now redis-server
  run_step 'Запуск Rspamd' service_enable_now rspamd
  run_step 'Запуск Dovecot' service_enable_now dovecot
  run_step 'Проверка Postfix' postfix check
  run_step 'Запуск Postfix' service_enable_now postfix

  ufw_allow_if_host 25/tcp 'SMTP'
  ufw_allow_if_host 465/tcp 'SMTPS'
  ufw_allow_if_host 587/tcp 'Submission'
  ufw_allow_if_host 993/tcp 'IMAPS'

  finish_role mail-lite "Лёгкий почтовый стек установлен: Postfix + Dovecot + Rspamd + Redis. Перед production требуется настроить TLS, DKIM selector, виртуальные домены/ящики или восстановить существующую конфигурацию migration-kit."
}
main "$@"
