#!/usr/bin/env bash
# shellcheck shell=bash

install_node_lts() {
  local major="${1:-24}" arch node_arch base version tarball tmp
  case "$(dpkg --print-architecture)" in
    amd64) node_arch=x64 ;;
    arm64) node_arch=arm64 ;;
    *) echo 'Поддерживаются amd64/arm64' >&2; return 2 ;;
  esac
  base="https://nodejs.org/dist/latest-v${major}.x"
  tmp=$(mktemp -d)
  curl -fsSL "$base/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt"
  tarball=$(awk -v a="linux-${node_arch}.tar.xz" '$2 ~ a"$" {print $2; exit}' "$tmp/SHASUMS256.txt")
  [[ -n "$tarball" ]] || { echo "Не найден Node.js v${major} для $node_arch" >&2; return 3; }
  curl -fsSL "$base/$tarball" -o "$tmp/$tarball"
  (cd "$tmp" && grep "  $tarball$" SHASUMS256.txt | sha256sum -c -)
  version="${tarball%.tar.xz}"
  rm -rf "/opt/$version"
  tar -xJf "$tmp/$tarball" -C /opt
  ln -sfn "/opt/$version/bin/node" /usr/local/bin/node
  ln -sfn "/opt/$version/bin/npm" /usr/local/bin/npm
  ln -sfn "/opt/$version/bin/npx" /usr/local/bin/npx
  if [[ -x "/opt/$version/bin/corepack" ]]; then
    ln -sfn "/opt/$version/bin/corepack" /usr/local/bin/corepack
  fi
  node --version
  npm --version
  rm -rf "$tmp"
}
