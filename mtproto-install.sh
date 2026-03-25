#!/bin/bash

set -euo pipefail

# Quick setup for Telemt via systemd (Debian/Ubuntu)
# Source guide:
# https://github.com/telemt/telemt/blob/main/docs/QUICK_START_GUIDE.ru.md

TELEMT_USER="${TELEMT_USER:-telemt}"
TELEMT_GROUP="${TELEMT_GROUP:-telemt}"
TELEMT_HOME="${TELEMT_HOME:-/opt/telemt}"
TELEMT_BIN="${TELEMT_BIN:-/bin/telemt}"
TELEMT_CONF_DIR="${TELEMT_CONF_DIR:-/etc/telemt}"
TELEMT_CONF_FILE="${TELEMT_CONF_FILE:-/etc/telemt/telemt.toml}"
TELEMT_SERVICE_FILE="${TELEMT_SERVICE_FILE:-/etc/systemd/system/telemt.service}"
TELEMT_PORT="${TELEMT_PORT:-443}"
TELEMT_TLS_DOMAIN="${TELEMT_TLS_DOMAIN:-music.yandex.ru}"
TELEMT_USERNAME="${TELEMT_USERNAME:-hello}"
TELEMT_SECRET="${TELEMT_SECRET:-$(openssl rand -hex 16)}"

echo "[1/6] Installing dependencies..."
apt-get install -y curl wget tar jq

echo "[2/6] Downloading and installing telemt binary..."
wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-$(uname -m)-linux-$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu).tar.gz" | tar -xz
install -m 0755 telemt "${TELEMT_BIN}"
rm -f telemt

echo "[3/6] Creating config ${TELEMT_CONF_FILE}..."
mkdir -p "${TELEMT_CONF_DIR}"

if [[ -f "${TELEMT_CONF_FILE}" ]]; then
  cp "${TELEMT_CONF_FILE}" "${TELEMT_CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  echo "Existing config backed up."
fi

cat > "${TELEMT_CONF_FILE}" <<EOF
# === General Settings ===
[general]
# ad_tag = "00000000000000000000000000000000"
use_middle_proxy = false

[general.modes]
classic = false
secure = false
tls = true

[server]
port = ${TELEMT_PORT}

[server.api]
enabled = true
# listen = "127.0.0.1:9091"
# whitelist = ["127.0.0.1/32"]
# read_only = true

# === Anti-Censorship & Masking ===
[censorship]
tls_domain = "${TELEMT_TLS_DOMAIN}"

[access.users]
# format: "username" = "32_hex_chars_secret"
${TELEMT_USERNAME} = "${TELEMT_SECRET}"
EOF

echo "[4/6] Creating service user and ownership..."
if ! id "${TELEMT_USER}" >/dev/null 2>&1; then
  useradd -d "${TELEMT_HOME}" -m -r -U "${TELEMT_USER}"
fi

chown -R "${TELEMT_USER}:${TELEMT_GROUP}" "${TELEMT_CONF_DIR}"

echo "[5/6] Writing systemd unit ${TELEMT_SERVICE_FILE}..."
cat > "${TELEMT_SERVICE_FILE}" <<EOF
[Unit]
Description=Telemt
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${TELEMT_USER}
Group=${TELEMT_GROUP}
WorkingDirectory=${TELEMT_HOME}
ExecStart=${TELEMT_BIN} ${TELEMT_CONF_FILE}
Restart=on-failure
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo "[6/6] Enabling and starting service..."
systemctl daemon-reload
systemctl enable telemt
systemctl restart telemt

echo
echo "Telemt setup completed."
echo "Generated user secret:"
echo "  ${TELEMT_USERNAME} = ${TELEMT_SECRET}"
echo
systemctl --no-pager --full status telemt || true
echo
echo "User links:"
echo "  curl -s http://127.0.0.1:9091/v1/users | jq"
