#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./bootstrap-node.sh --authorized-key-file /path/to/key.pub [--user migration]

Creates a temporary SSH user for the migration controller and grants only the
sudo commands needed to install and run the migration agent. Run this on every
source and target server. Remove the account with cleanup-node.sh after the
migration is accepted.
EOF
}

MIG_USER="migration"
KEY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) MIG_USER="$2"; shift 2 ;;
    --authorized-key-file) KEY_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -n "$KEY_FILE" && -f "$KEY_FILE" ]] || { echo "--authorized-key-file is required" >&2; exit 2; }
[[ "$MIG_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "Invalid user name" >&2; exit 2; }

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y python3 rsync tar acl attr sudo ca-certificates curl jq openssh-server
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y python3 rsync tar acl attr sudo ca-certificates curl jq openssh-server
elif command -v yum >/dev/null 2>&1; then
  yum install -y python3 rsync tar acl attr sudo ca-certificates curl jq openssh-server
else
  echo "Unsupported package manager; install python3 rsync tar acl attr sudo curl jq manually" >&2
  exit 1
fi

if ! id "$MIG_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$MIG_USER"
fi
passwd -l "$MIG_USER" >/dev/null 2>&1 || true

HOME_DIR="$(getent passwd "$MIG_USER" | cut -d: -f6)"
install -d -m 0700 -o "$MIG_USER" -g "$MIG_USER" "$HOME_DIR/.ssh"
install -m 0600 -o "$MIG_USER" -g "$MIG_USER" "$KEY_FILE" "$HOME_DIR/.ssh/authorized_keys"

INSTALL_BIN="$(command -v install)"
RM_BIN="$(command -v rm)"
PYTHON_BIN="$(command -v python3)"
RSYNC_BIN="$(command -v rsync)"
SUDOERS="/etc/sudoers.d/90-migkit-${MIG_USER}"
cat >"$SUDOERS" <<EOF
Defaults:${MIG_USER} !requiretty
${MIG_USER} ALL=(root) NOPASSWD: ${INSTALL_BIN}
${MIG_USER} ALL=(root) NOPASSWD: ${RM_BIN}
${MIG_USER} ALL=(root) NOPASSWD: ${PYTHON_BIN} /opt/migkit/remote_agent.py *
${MIG_USER} ALL=(root) NOPASSWD: ${RSYNC_BIN} *
EOF
chmod 0440 "$SUDOERS"
visudo -cf "$SUDOERS"

install -d -m 0700 /opt/migkit /var/lib/migkit/runs

echo "Migration access prepared for user: $MIG_USER"
echo "Verify from controller: ssh ${MIG_USER}@$(hostname -f) 'sudo -n ${INSTALL_BIN} --version | head -1'"
