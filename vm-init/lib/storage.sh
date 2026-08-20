#!/usr/bin/env bash
# shellcheck shell=bash

show_block_devices() {
  lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
}

prepare_data_disk() {
  local mountpoint="$1" label="${2:-service-data}" dev fs uuid confirm children
  ui_info 'Отдельный диск данных' "Рекомендуемый mountpoint: $mountpoint. В следующем окне будет показан lsblk. Скрипт НИКОГДА не форматирует диск без ввода точного имени устройства."
  show_block_devices >&2
  dev=$(ui_input 'Data disk' 'Устройство, например /dev/sdb или /dev/vdb; пусто = пропустить' '')
  [[ -n "$dev" ]] || return 0
  [[ -b "$dev" ]] || { ui_warn 'Data disk' "$dev не является блочным устройством."; return 2; }
  if findmnt -rn -S "$dev" >/dev/null 2>&1; then
    ui_warn 'Data disk' "$dev уже смонтирован. Автоматические изменения отменены."
    return 2
  fi
  children=$(lsblk -nrpo NAME "$dev" | tail -n +2 | wc -l)
  fs=$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)
  if (( children > 0 )) && [[ -z "$fs" ]]; then
    ui_warn 'Data disk' "$dev содержит разделы. Укажите конкретный раздел (например /dev/sdb1), а не весь диск."
    return 2
  fi

  mkdir -p "$mountpoint"
  if find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    ui_warn 'Data disk' "$mountpoint уже содержит файлы. Монтировать поверх них автоматически запрещено."
    return 2
  fi

  if [[ -z "$fs" ]]; then
    ui_warn 'ФОРМАТИРОВАНИЕ' "$dev не содержит распознанной файловой системы. Для продолжения он будет отформатирован в ext4, и ВСЕ данные на устройстве будут уничтожены."
    confirm=$(ui_input 'Подтверждение' "Введите ТОЧНО $dev для форматирования" '')
    [[ "$confirm" == "$dev" ]] || { ui_warn 'Отменено' 'Имя устройства не совпало; форматирование отменено.'; return 2; }
    run_step "Создание ext4 на $dev" mkfs.ext4 -F -L "$label" "$dev"
    fs=ext4
  fi

  uuid=$(blkid -o value -s UUID "$dev")
  [[ -n "$uuid" ]] || { ui_warn 'Data disk' 'Не удалось получить UUID.'; return 2; }
  backup_path /etc/fstab
  grep -Fq "UUID=$uuid " /etc/fstab || printf 'UUID=%s %s %s defaults,noatime 0 2\n' "$uuid" "$mountpoint" "$fs" >> /etc/fstab
  run_step "Монтирование $mountpoint" mount "$mountpoint"
  findmnt "$mountpoint"
}

offer_data_disk() {
  local mountpoint="$1" label="${2:-service-data}"
  if ui_yesno 'Диск данных' "Подключить/подготовить отдельный виртуальный диск для $mountpoint? Рекомендуется для stateful-сервиса." no; then
    prepare_data_disk "$mountpoint" "$label"
  fi
}
