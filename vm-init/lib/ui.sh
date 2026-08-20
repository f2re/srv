#!/usr/bin/env bash
# shellcheck shell=bash

: "${PROVISION_LOG:=/var/log/infra-provision/provision.log}"

_ui_has_whiptail() { command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; }

log() {
  local level="$1"; shift
  local line
  line="$(date --iso-8601=seconds) [$level] $*"
  printf '%s\n' "$line" | tee -a "$PROVISION_LOG" >&2
}

ui_info() {
  local title="$1" text="$2"
  log INFO "$title: $text"
  if _ui_has_whiptail; then
    whiptail --title "$title" --msgbox "$text" 14 78
  else
    printf '\n== %s ==\n%s\n\n' "$title" "$text" >&2
  fi
}

ui_warn() {
  local title="$1" text="$2"
  log WARN "$title: $text"
  if _ui_has_whiptail; then
    whiptail --title "$title" --msgbox "$text" 16 78
  else
    printf '\n!! %s !!\n%s\n\n' "$title" "$text" >&2
  fi
}

ui_yesno() {
  local title="$1" text="$2" default="${3:-yes}"
  if _ui_has_whiptail; then
    local args=(--title "$title" --yesno "$text" 14 78)
    [[ "$default" == no ]] && args=(--defaultno "${args[@]}")
    whiptail "${args[@]}"
    return $?
  fi
  local answer suffix='[Y/n]'
  [[ "$default" == no ]] && suffix='[y/N]'
  while true; do
    read -r -p "$text $suffix " answer || return 1
    answer="${answer:-$([[ "$default" == yes ]] && echo y || echo n)}"
    case "$answer" in y|Y|yes|YES|д|Д) return 0;; n|N|no|NO|н|Н) return 1;; esac
  done
}

ui_input() {
  local title="$1" text="$2" default="${3:-}" out
  if _ui_has_whiptail; then
    out=$(whiptail --title "$title" --inputbox "$text" 12 78 "$default" 3>&1 1>&2 2>&3) || return 1
  else
    read -r -p "$text [$default]: " out || return 1
    out="${out:-$default}"
  fi
  printf '%s' "$out"
}

ui_password() {
  local title="$1" text="$2" out
  if _ui_has_whiptail; then
    out=$(whiptail --title "$title" --passwordbox "$text" 12 78 3>&1 1>&2 2>&3) || return 1
  else
    read -r -s -p "$text: " out || return 1
    printf '\n' >&2
  fi
  printf '%s' "$out"
}

ui_menu() {
  local title="$1" text="$2"; shift 2
  if _ui_has_whiptail; then
    whiptail --title "$title" --menu "$text" 22 88 12 "$@" 3>&1 1>&2 2>&3
  else
    local -a args=("$@")
    local i choice
    printf '\n== %s ==\n%s\n' "$title" "$text" >&2
    for ((i=0; i<${#args[@]}; i+=2)); do
      printf '  %s) %s\n' "${args[i]}" "${args[i+1]}" >&2
    done
    while true; do
      read -r -p 'Выбор: ' choice || return 1
      for ((i=0; i<${#args[@]}; i+=2)); do
        [[ "$choice" == "${args[i]}" ]] && { printf '%s' "$choice"; return 0; }
      done
    done
  fi
}

show_log_tail() {
  local n="${1:-40}"
  local text
  text=$(tail -n "$n" "$PROVISION_LOG" 2>/dev/null || true)
  if _ui_has_whiptail; then
    printf '%s\n' "$text" | whiptail --title 'Последние строки журнала' --textbox /dev/stdin 24 100
  else
    printf '\n--- log tail ---\n%s\n---------------\n' "$text" >&2
  fi
}

run_step() {
  local label="$1"; shift
  local allow_skip="${ALLOW_SKIP:-0}" rc action
  while true; do
    log INFO "START: $label"
    if "$@" >>"$PROVISION_LOG" 2>&1; then
      log INFO "OK: $label"
      return 0
    else
      rc=$?
    fi
    log ERROR "FAILED($rc): $label"
    if [[ "${NONINTERACTIVE:-0}" == 1 ]]; then
      return "$rc"
    fi
    local menu=(retry 'Повторить шаг' log 'Показать журнал' shell 'Открыть аварийную оболочку')
    [[ "$allow_skip" == 1 ]] && menu+=(skip 'Пропустить этот необязательный шаг')
    menu+=(abort 'Прервать установку')
    action=$(ui_menu 'Ошибка шага' "$label завершился с кодом $rc. Что сделать?" "${menu[@]}") || return "$rc"
    case "$action" in
      retry) continue ;;
      log) show_log_tail 80 ;;
      shell) ui_warn 'Аварийная оболочка' 'После диагностики выполните exit, чтобы вернуться в установщик.'; bash -l ;;
      skip) log WARN "SKIPPED: $label"; return 0 ;;
      abort|*) return "$rc" ;;
    esac
  done
}

run_interactive_step() {
  local label="$1"; shift
  local rc action
  while true; do
    log INFO "START interactive: $label"
    if "$@" > >(tee -a "$PROVISION_LOG") 2> >(tee -a "$PROVISION_LOG" >&2); then
      log INFO "OK interactive: $label"
      return 0
    else
      rc=$?
    fi
    log ERROR "FAILED($rc) interactive: $label"
    [[ "${NONINTERACTIVE:-0}" == 1 ]] && return "$rc"
    action=$(ui_menu 'Ошибка интерактивного шага' "$label завершился с кодом $rc." retry 'Повторить' log 'Показать журнал' shell 'Открыть shell' abort 'Прервать') || return "$rc"
    case "$action" in retry) continue;; log) show_log_tail 80;; shell) bash -l;; abort|*) return "$rc";; esac
  done
}
