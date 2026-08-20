#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
require_root; require_base

install_gitlab_repo() {
  local edition="$1" tmp
  tmp=$(mktemp)
  curl -fsSL "https://packages.gitlab.com/install/repositories/gitlab/gitlab-${edition}/script.deb.sh" -o "$tmp"
  bash "$tmp"
  rm -f "$tmp"
}

install_gitlab_pkg() {
  local pkg="$1" exturl="$2" version="$3"
  export DEBIAN_FRONTEND=noninteractive
  if [[ -n "$version" ]]; then
    apt-cache madison "$pkg" | tee -a "$PROVISION_LOG"
    EXTERNAL_URL="$exturl" apt-get install -y "$pkg=$version"
    apt-mark hold "$pkg"
  else
    EXTERNAL_URL="$exturl" apt-get install -y "$pkg"
  fi
}

configure_gitlab_ssh_port() {
  local port="$1"
  backup_path /etc/gitlab/gitlab.rb
  if grep -q "^[[:space:]]*gitlab_rails\['gitlab_shell_ssh_port'\]" /etc/gitlab/gitlab.rb; then
    sed -i "s|^[[:space:]]*gitlab_rails\['gitlab_shell_ssh_port'\].*|gitlab_rails['gitlab_shell_ssh_port'] = $port|" /etc/gitlab/gitlab.rb
  else
    printf "\n# Managed by infra-provision\ngitlab_rails['gitlab_shell_ssh_port'] = %s\n" "$port" >> /etc/gitlab/gitlab.rb
  fi
  gitlab-ctl reconfigure
}

main() {
  offer_data_disk /var/opt/gitlab gitlab-data
  . /etc/os-release
  if [[ "$VERSION_ID" != 24.04 ]]; then
    ui_warn 'GitLab и Ubuntu' "Для production GitLab рекомендуется Ubuntu 24.04. Обнаружена Ubuntu $VERSION_ID."
    ui_yesno 'Продолжить?' 'Пакет GitLab может отсутствовать для этой версии Ubuntu. Продолжить?' no || exit 3
  fi

  check_ram_gib 4 || ui_warn 'Ресурсы' 'GitLab получил меньше 4 GiB RAM. Для даже небольшой production-инсталляции это слишком мало.'
  check_free_gib / 20 || ui_warn 'Диск' 'Свободно менее 20 GiB. Проверьте размер системного/data-диска.'

  local edition pkg exturl mode version extssh
  edition=$(ui_menu 'GitLab' 'Редакция:' ce 'Community Edition (CE)' ee 'Enterprise Edition (EE)')
  pkg="gitlab-$edition"
  exturl=$(ui_input 'GitLab' 'External URL, например https://gitlab.example.org' 'https://gitlab.example.org')
  mode=$(ui_menu 'Версия' 'Режим установки:' latest 'Новая установка: последняя поддерживаемая версия' migration 'Миграция: установить ТОЧНО версию исходного GitLab')
  version=''
  if [[ "$mode" == migration ]]; then
    version=$(ui_input 'Версия GitLab' 'Точное имя версии apt (пример: 18.4.0-ce.0). Пусто = сначала показать доступные версии.' '')
  fi
  extssh=$(ui_input 'GitLab SSH' 'Порт, который пользователи видят в clone SSH URL' "${SSH_PORT:-2222}")
  valid_port "$extssh" || exit 2

  run_step 'Установка зависимостей GitLab' apt_install curl ca-certificates tzdata perl
  run_step 'Подключение официального GitLab apt-репозитория' install_gitlab_repo "$edition"
  if [[ "$mode" == migration && -z "$version" ]]; then
    apt-cache madison "$pkg" | tee -a "$PROVISION_LOG"
    version=$(ui_input 'Версия GitLab' 'Введите точную версию из списка' '')
    [[ -n "$version" ]] || { ui_warn 'Миграция' 'Для restore GitLab требуется точное совпадение версии и edition.'; exit 3; }
  fi
  run_step 'Установка GitLab' install_gitlab_pkg "$pkg" "$exturl" "$version"
  run_step 'Настройка внешнего SSH-порта GitLab' configure_gitlab_ssh_port "$extssh"
  run_step 'Проверка GitLab' gitlab-rake gitlab:check SANITIZE=true
  run_step 'Проверка служб GitLab' gitlab-ctl status

  ufw_allow_if_host 80/tcp 'GitLab HTTP'
  ufw_allow_if_host 443/tcp 'GitLab HTTPS'
  finish_role gitlab "GitLab установлен и запущен. Для миграции переносите /etc/gitlab, secrets и штатный backup только на совпадающую версию. External URL: $exturl"
}
main "$@"
