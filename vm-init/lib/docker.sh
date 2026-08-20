#!/usr/bin/env bash
# shellcheck shell=bash

install_docker_official() {
  . /etc/os-release
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.sources <<EOF2
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF2
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker version
  docker compose version
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi
  run_step 'Установка Docker Engine из официального репозитория' install_docker_official
}

warn_docker_firewall() {
  ui_warn 'Docker и firewall' 'Опубликованные Docker-порты могут обходить UFW. На Docker-VM внешний доступ необходимо ограничивать firewall Proxmox/маршрутизатора и публиковать только требуемые порты. Не включайте UFW как единственную защиту контейнеров.'
}
