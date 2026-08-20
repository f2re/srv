#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

check_mail_ports() {
  local p bad=0
  for p in 25 80 110 143 443 465 587 993 995 4190; do
    if port_in_use "$p"; then
      echo "Port already in use: $p" >&2; bad=1
    fi
  done
  return "$bad"
}

prepare_mailcow_repo() {
  local ref="$1"
  if [[ ! -d /opt/mailcow-dockerized/.git ]]; then
    git clone https://github.com/mailcow/mailcow-dockerized /opt/mailcow-dockerized
  fi
  cd /opt/mailcow-dockerized
  git fetch --tags --prune
  if [[ -n "$ref" && "$ref" != latest ]]; then git checkout "$ref"; fi
}

main() {
  offer_data_disk /var/lib/docker mailcow-docker-data
  local fqdn mode ref
  check_ram_gib 6 || { ui_warn 'Mailcow RAM' 'Mailcow требует минимум 6 GiB RAM + swap в стандартной конфигурации. Для небольшого хоста лучше выбрать mail-lite.'; ui_yesno 'Продолжить?' 'Продолжить при памяти меньше рекомендуемого минимума?' no || exit 3; }
  check_free_gib / 25 || ui_warn 'Mailcow disk' 'Свободно менее 25 GiB; этого мало даже до накопления почты.'
  run_step 'Создание swap при отсутствии' ensure_swap 2

  fqdn=$(ui_input 'Mailcow' 'Полный hostname почтового сервера, например mail.example.org' 'mail.example.org')
  valid_fqdn "$fqdn" || { ui_warn 'FQDN' 'Нужен корректный FQDN.'; exit 2; }
  ui_yesno 'DNS/PTR' "Подтверждаете, что для $fqdn подготовлены A/AAAA (если используется IPv6), MX, PTR/reverse DNS и разрешён исходящий TCP/25?" no || exit 3

  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    ui_warn 'Mailcow и UFW' 'Mailcow/Docker управляет собственными netfilter-правилами. Для этой VM рекомендуется фильтрация на Proxmox/маршрутизаторе.'
    if ui_yesno 'Отключить UFW?' 'Отключить UFW на Mailcow VM? SSH продолжит защищаться Fail2Ban, а сетевые ACL должны быть настроены снаружи.' yes; then
      ufw --force disable
      write_config_kv FIREWALL_MODE external
    else
      ui_warn 'Риск' 'Продолжение с UFW может нарушить доступ к контейнерам. Скрипт не будет автоматически исправлять конфликтующие правила.'
    fi
  fi

  run_step 'Проверка, что почтовые порты свободны' check_mail_ports
  warn_docker_firewall
  ensure_docker
  run_step 'Установка зависимостей Mailcow' apt_install git openssl curl gawk coreutils grep jq

  mode=$(ui_menu 'Mailcow' 'Назначение VM:' fresh 'Новая установка' migration 'Цель миграции существующего Mailcow')
  ref=latest
  if [[ "$mode" == migration ]]; then
    ref=$(ui_input 'Mailcow Git ref' 'Если нужно сохранить точный релиз/commit исходной системы, укажите tag/commit. Иначе latest.' 'latest')
  fi
  run_step 'Подготовка репозитория Mailcow' prepare_mailcow_repo "$ref"

  if [[ ! -f /opt/mailcow-dockerized/mailcow.conf ]]; then
    ui_info 'Конфигуратор Mailcow' "Сейчас запустится официальный generate_config.sh. Укажите hostname: $fqdn. После завершения вернётесь в мастер."
    run_interactive_step 'Mailcow generate_config.sh' bash -lc 'cd /opt/mailcow-dockerized && ./generate_config.sh'
  else
    ui_info 'Mailcow' 'mailcow.conf уже существует — повторная генерация пропущена.'
  fi

  run_step 'Проверка Docker Compose Mailcow' bash -lc 'cd /opt/mailcow-dockerized && docker compose config >/dev/null'
  run_step 'Загрузка Mailcow images' bash -lc 'cd /opt/mailcow-dockerized && docker compose pull'
  run_step 'Запуск Mailcow' bash -lc 'cd /opt/mailcow-dockerized && docker compose up -d'
  run_step 'Проверка контейнеров Mailcow' bash -lc 'cd /opt/mailcow-dockerized && docker compose ps'

  ui_warn 'Обязательное действие' 'После новой установки немедленно войдите в /admin и смените первоначальный пароль администратора. Затем настройте домены, DKIM, SPF/DMARC и резервное копирование.'
  ui_info 'Антибрутфорс' 'Общий Fail2Ban из base.sh защищает только SSH. Почтовые протоколы защищает штатный netfilter-mailcow; его параметры меняются в Mailcow UI.'
  finish_role mailcow "Mailcow запущен. Каталог: /opt/mailcow-dockerized. Hostname должен быть $fqdn."
}
main "$@"
