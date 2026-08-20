#!/usr/bin/env bash
set -Eeuo pipefail
KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; export KIT_ROOT
source "$KIT_ROOT/lib/role.sh"
require_root; require_base

main() {
  local path share share_section cidr
  path=$(ui_input 'Файловый сервер' 'Путь к данным (желательно отдельный диск/dataset)' '/srv/files')
  offer_data_disk "$path" files-data
  share=$(ui_input 'Samba' 'Имя общей папки' 'projects')
  share_section=$(printf '%s' "$share" | tr -cd 'A-Za-z0-9._-')
  [[ -n "$share_section" ]] || { ui_warn 'Samba' 'Имя общей папки после очистки пустое.'; exit 2; }
  run_step 'Установка Samba/NFS/ACL' apt_install samba samba-vfs-modules nfs-kernel-server acl attr
  mkdir -p "$path"; chmod 2770 "$path"
  getent group fileshare >/dev/null || groupadd fileshare
  backup_path /etc/samba/smb.conf
  if ! grep -Fq "[$share_section]" /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf <<EOT

[$share_section]
    path = $path
    browseable = yes
    read only = no
    valid users = @fileshare
    force group = fileshare
    create mask = 0660
    directory mask = 2770
    inherit permissions = yes
    vfs objects = acl_xattr
    map acl inherit = yes
    store dos attributes = yes
EOT
  fi
  run_step 'Проверка smb.conf' testparm -s
  run_step 'Запуск Samba' service_enable_now smbd
  ufw_allow_if_host 'Samba' 'Samba'
  if ui_yesno 'NFS' 'Настроить NFS export для серверной сети?' no; then
    cidr=$(ui_input 'NFS' 'Разрешённая сеть/CIDR' '10.0.30.0/24')
    backup_path /etc/exports
    grep -Fq "$path $cidr" /etc/exports || echo "$path $cidr(rw,sync,no_subtree_check,root_squash)" >> /etc/exports
    exportfs -ra
    run_step 'Запуск NFS' service_enable_now nfs-server
    [[ "${FIREWALL_MODE:-}" == host ]] && ui_warn 'NFS+UFW' 'NFS использует несколько RPC-портов; ограничивайте его серверной VLAN/Proxmox firewall. Скрипт не открывает NFS в UFW автоматически.'
  fi
  ui_info 'Пользователи Samba' 'Добавьте пользователя в группу fileshare: usermod -aG fileshare USER; затем задайте SMB-пароль: smbpasswd -a USER. При миграции UID/GID/ACL восстанавливайте migration-kit до включения записи.'
  finish_role fileserver "Samba запущена. Данные: $path. Группа доступа: fileshare."
}
main "$@"
