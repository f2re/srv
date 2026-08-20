#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail

KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
source "$KIT_ROOT/lib/ui.sh"
source "$KIT_ROOT/lib/common.sh"

install_base_packages() {
  apt_install qemu-guest-agent openssh-server fail2ban unattended-upgrades needrestart \
    ca-certificates curl wget gnupg jq git rsync acl attr vim nano tmux htop btop fish sudo \
    unzip zip xz-utils whiptail lsof dnsutils netcat-openbsd socat python3 python3-venv python3-pip pipx \
    apparmor-utils auditd ufw etckeeper
}

configure_time() {
  local tz="$1"
  timedatectl set-timezone "$tz"
  timedatectl set-ntp true
}

install_authorized_key_interactive() {
  local user="$1" home key tmp ok_msg
  [[ "$user" != root ]] || return 0
  home=$(getent passwd "$user" | cut -d: -f6)
  mkdir -p "$home/.ssh"
  chmod 700 "$home/.ssh"
  if [[ -s "$home/.ssh/authorized_keys" ]]; then
    return 0
  fi
  if ! ui_yesno 'SSH-ключ' "У $user нет authorized_keys. Добавить публичный SSH-ключ сейчас?" yes; then
    return 0
  fi
  key=$(ui_input 'SSH public key' 'Вставьте одну строку public key (ssh-ed25519/ssh-rsa/ecdsa-...)' '')
  [[ -n "$key" ]] || return 0
  tmp=$(mktemp)
  printf '%s\n' "$key" > "$tmp"
  if ! ssh-keygen -l -f "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    ui_warn 'SSH-ключ' 'Строка не распознана как публичный SSH-ключ. Ничего не записано.'
    return 2
  fi
  cat "$tmp" >> "$home/.ssh/authorized_keys"
  rm -f "$tmp"
  sort -u "$home/.ssh/authorized_keys" -o "$home/.ssh/authorized_keys"
  chown -R "$user:$(id -gn "$user")" "$home/.ssh"
  chmod 600 "$home/.ssh/authorized_keys"
  ok_msg="$(ssh-keygen -lf "$home/.ssh/authorized_keys" | tail -n1 2>/dev/null || true)"
  log INFO "SSH key added for $user: $ok_msg"
}

configure_unattended() {
  cat > /etc/apt/apt.conf.d/52infra-unattended <<'EOT'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOT
  dpkg-reconfigure -f noninteractive unattended-upgrades
}

configure_sysctl() {
  cat > /etc/sysctl.d/99-infra-hardening.conf <<'EOT'
# Conservative hardening. Avoids Docker/mail routing-sensitive knobs.
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOT
  sysctl --system >/dev/null
}

configure_ssh() {
  local admin="$1" port="$2" password_auth="$3"
  valid_port "$port" || { echo "Некорректный SSH-порт: $port" >&2; return 2; }
  mkdir -p /etc/ssh/sshd_config.d
  backup_path /etc/ssh/sshd_config
  [[ -e /etc/ssh/sshd_config.d/99-infra-hardening.conf ]] && backup_path /etc/ssh/sshd_config.d/99-infra-hardening.conf
  cat > /etc/ssh/sshd_config.d/99-infra-hardening.conf <<EOT
Port $port
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication $password_auth
KbdInteractiveAuthentication no
X11Forwarding no
MaxAuthTries 4
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
EOT
  sshd -t
  systemctl daemon-reload
  if systemctl is-enabled ssh.socket >/dev/null 2>&1 || systemctl is-active ssh.socket >/dev/null 2>&1; then
    systemctl restart ssh.socket
  fi
  systemctl restart ssh.service || true
  sleep 1
  ss -lnt | grep -Eq "[:.]${port}[[:space:]]" || { echo "sshd не слушает порт $port" >&2; return 3; }
  write_config_kv SSH_PORT "$port"
  write_config_kv ADMIN_USER "$admin"
}

configure_fail2ban() {
  local port="$1"
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd-infra.local <<EOT
[sshd]
enabled = true
backend = systemd
port = $port
maxretry = 5
findtime = 10m
bantime = 1h
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 1d
EOT
  systemctl enable --now fail2ban
  fail2ban-client reload
  fail2ban-client status sshd
}

configure_ufw_host() {
  local ssh_port="$1"
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "$ssh_port/tcp" comment 'SSH administration'
  ufw --force enable
  ufw status verbose
}

install_omf_for_user() {
  local user="$1" home tmpdir group
  [[ "$user" != root ]] || return 0
  home=$(getent passwd "$user" | cut -d: -f6)
  group=$(id -gn "$user")
  if [[ -f "$home/.local/share/omf/init.fish" || -f "$home/.config/omf/init.fish" ]]; then
    log INFO "Oh My Fish already installed for $user"
  else
    tmpdir=$(mktemp -d)
    curl -fsSL https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install -o "$tmpdir/install"
    curl -fsSL https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install.sha256 -o "$tmpdir/install.sha256"
    (cd "$tmpdir" && sha256sum -c install.sha256)
    chown -R "$user:$group" "$tmpdir"
    sudo -H -u "$user" fish "$tmpdir/install" --noninteractive
    rm -rf "$tmpdir"
  fi
  if ui_yesno 'Fish' "Сделать fish оболочкой входа для $user? root останется на bash." yes; then
    chsh -s "$(command -v fish)" "$user"
  fi
}

main() {
  require_root
  mkdir -p /var/log/infra-provision
  touch "$PROVISION_LOG"; chmod 600 "$PROVISION_LOG"
  check_ubuntu
  load_config

  ui_info 'Базовая подготовка VM' 'Скрипт обновит Ubuntu, установит QEMU Guest Agent, SSH, Fail2Ban, автоматические security-updates и инструменты администратора. Все изменения конфигурации предварительно резервируются.'

  local admin host tz ssh_port pass_auth firewall_mode admin_new
  admin="${ADMIN_USER:-$(get_admin_user)}"
  if [[ "$admin" == root ]]; then
    admin_new=$(ui_input 'Администратор' 'На свежей VM не найден обычный административный пользователь. Введите имя нового пользователя' 'admin')
    [[ "$admin_new" =~ ^[a-z_][a-z0-9_-]*$ ]] || { ui_warn 'Пользователь' 'Недопустимое имя пользователя.'; return 2; }
    if ! id "$admin_new" >/dev/null 2>&1; then
      run_step "Создание администратора $admin_new" useradd -m -s /bin/bash -G sudo "$admin_new"
      ui_warn 'Пароль администратора' "Сейчас задайте временный пароль для $admin_new. После добавления SSH-ключа парольный SSH-вход можно отключить повторным запуском базовой настройки."
      run_interactive_step "Пароль пользователя $admin_new" passwd "$admin_new"
    fi
    admin="$admin_new"
  fi
  host=$(ui_input 'Имя VM' 'Hostname/FQDN этой виртуальной машины' "$(hostname -f 2>/dev/null || hostname)")
  tz=$(ui_input 'Часовой пояс' 'IANA timezone' "${TIMEZONE:-Europe/Stockholm}")
  ssh_port=$(ui_input 'SSH' 'Новый SSH-порт' "${SSH_PORT:-2222}")
  valid_port "$ssh_port" || { ui_warn 'Ошибка' 'Порт должен быть 1..65535.'; return 2; }

  ALLOW_SKIP=1 run_step 'Проверка/добавление SSH public key' install_authorized_key_interactive "$admin"

  if has_authorized_key "$admin"; then
    if ui_yesno 'SSH' 'Отключить вход по паролю и оставить только ключи?' yes; then pass_auth=no; else pass_auth=yes; fi
  else
    pass_auth=yes
    ui_warn 'SSH-ключ не найден' "У пользователя $admin нет authorized_keys. PasswordAuthentication останется включён, иначе можно потерять доступ. Добавьте ключ и повторно запустите базовую настройку для отключения пароля."
  fi

  case "${ROLE:-}" in
    mailcow|planka|nextcloud|sftpgo|vaultwarden)
      firewall_mode=$(ui_menu 'Firewall' 'Эта роль использует Docker. Docker-публикация портов может обходить UFW. Рекомендуется внешний firewall Proxmox/маршрутизатора:' \
        external 'РЕКОМЕНДУЕТСЯ: не включать UFW; фильтровать на Proxmox/маршрутизаторе' \
        host 'Включить UFW для host-портов; Docker всё равно требует внешних ACL' \
        keep 'Не менять существующий firewall')
      ;;
    *)
      firewall_mode=$(ui_menu 'Firewall' 'Выберите режим firewall этой VM:' \
        host 'РЕКОМЕНДУЕТСЯ для обычной VM: UFW deny incoming + SSH; роль добавит свои host-порты' \
        external 'Не включать UFW; фильтрация только на Proxmox/маршрутизаторе' \
        keep 'Не менять существующий firewall')
      ;;
  esac

  run_step 'Проверка DNS/Интернета' wait_for_dns
  step_once apt-update 'apt update' apt_update
  step_once apt-upgrade 'Обновление установленных пакетов' apt_upgrade
  step_once base-packages 'Установка базовых пакетов' install_base_packages
  if ! is_done qemu-agent; then
    if [[ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]]; then
      run_step 'Включение QEMU Guest Agent' service_enable_now qemu-guest-agent
      mark_done qemu-agent
    else
      ui_warn 'QEMU Guest Agent' 'В Ubuntu пакет установлен, но канал guest-agent не обнаружен. В Proxmox включите VM → Options → QEMU Guest Agent, затем внутри VM выполните: sudo systemctl enable --now qemu-guest-agent. Это не блокирует установку сервиса.'
    fi
  fi
  run_step 'Настройка hostname' set_hostname_safe "$host"
  run_step 'Настройка времени/NTP' configure_time "$tz"
  run_step 'Настройка автоматических security-updates' configure_unattended
  run_step 'Консервативный sysctl hardening' configure_sysctl
  run_step 'Проверка и переключение SSH' configure_ssh "$admin" "$ssh_port" "$pass_auth"
  run_step 'Настройка Fail2Ban только для SSH' configure_fail2ban "$ssh_port"

  case "$firewall_mode" in
    host) run_step 'Настройка UFW для host-сервисов' configure_ufw_host "$ssh_port"; write_config_kv FIREWALL_MODE host ;;
    external) systemctl disable --now ufw.service >/dev/null 2>&1 || true; ufw --force disable >/dev/null 2>&1 || true; write_config_kv FIREWALL_MODE external ;;
    keep) write_config_kv FIREWALL_MODE keep ;;
  esac

  if ui_yesno 'Oh My Fish' "Установить Oh My Fish для пользователя $admin?" yes; then
    ALLOW_SKIP=1 run_step 'Установка Oh My Fish' install_omf_for_user "$admin"
  fi

  run_step 'Формирование отчёта о VM' system_report
  mark_done base

  ui_info 'Базовая настройка завершена' "SSH: порт $ssh_port. НЕ закрывайте текущую консоль/SSH-сессию, пока не проверите новый вход во второй сессии. Если SSH не поднимется, используйте Console этой VM в Proxmox. Журнал: $PROVISION_LOG"
}

main "$@"
