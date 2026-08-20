#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
source "$KIT_ROOT/lib/docker.sh"
require_root; require_base

install_runner_repo() {
  local tmp
  tmp=$(mktemp)
  curl -L --fail https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh -o "$tmp"
  bash "$tmp"
  rm -f "$tmp"
}

register_runner_secure() {
  local url="$1" token="$2" name="$3" executor="$4" image="$5"
  local -a args=(register --non-interactive --url "$url" --token "$token" --name "$name" --executor "$executor")
  if [[ "$executor" == docker ]]; then
    args+=(--docker-image "$image" --docker-pull-policy if-not-present)
  fi
  gitlab-runner "${args[@]}"
}

main() {
  local executor url name token image
  executor=$(ui_menu 'GitLab Runner' 'Executor:' docker 'Docker executor (рекомендуется для изоляции jobs)' shell 'Shell executor (jobs выполняются непосредственно на VM)')
  url=$(ui_input 'GitLab Runner' 'URL GitLab instance' 'https://gitlab.example.org')
  name=$(ui_input 'GitLab Runner' 'Имя runner' "$(hostname -s)")

  run_step 'Подключение GitLab Runner apt-репозитория' install_runner_repo
  run_step 'Установка GitLab Runner' apt_install gitlab-runner

  if [[ "$executor" == docker ]]; then
    warn_docker_firewall
    ensure_docker
    usermod -aG docker gitlab-runner
    image=$(ui_input 'Docker executor' 'Базовый image по умолчанию' 'ubuntu:24.04')
  else
    image=''
  fi

  if ui_yesno 'Регистрация' 'Зарегистрировать runner сейчас? Нужен runner authentication token glrt-...' yes; then
    token=$(ui_password 'Runner token' 'Введите runner authentication token')
    [[ "$token" == glrt-* ]] || ui_warn 'Token' 'Токен не начинается с glrt-. Проверьте тип токена.'
    run_step 'Регистрация GitLab Runner' register_runner_secure "$url" "$token" "$name" "$executor" "$image"
    unset token
  fi

  run_step 'Включение службы GitLab Runner' service_enable_now gitlab-runner
  ALLOW_SKIP=1 run_step 'Проверка зарегистрированных runners' gitlab-runner verify

  if [[ "$executor" == docker ]]; then
    ui_info 'Безопасность Runner' 'privileged=true автоматически НЕ включён. Включайте его только для доверенных jobs, если без этого действительно нельзя.'
  fi
  finish_role gitlab-runner "GitLab Runner установлен. Конфигурация: /etc/gitlab-runner/config.toml. Executor: $executor."
}
main "$@"
