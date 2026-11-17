#!/usr/bin/env bash
# Universal Dual-Stack Proxy Deployment Script (Debian/Ubuntu/Rocky/CentOS)
# Deploys:
#   1) Xray-core v1.8.24: VLESS + TCP + XTLS-Vision + REALITY
#   2) Hysteria 2: QUIC / UDP with SHA256 Certificate Pinning & Masquerade
# Usage:
#   ssh root@<SERVER_IP> "PORT=443 bash -s" < deploy_dual_proxy.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
PORT="${PORT:-443}"
XRAY_VERSION="${XRAY_VERSION:-v1.8.24}"
MASQ_DOMAIN="${MASQ_DOMAIN:-www.bing.com}"

echo "=========================================="
echo "1. Detecting Environment & Cloud Metadata"
echo "=========================================="
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq curl openssl jq ca-certificates unzip iproute2
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q curl openssl jq ca-certificates unzip iproute
elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl openssl jq ca-certificates unzip iproute
fi

SERVER_IP="${SERVER_IP:-}"
if [ -z "${SERVER_IP}" ]; then
    SERVER_IP="$(curl -fsSL -4 --max-time 5 https://icanhazip.com 2>/dev/null \
        || curl -fsSL -4 --max-time 5 https://api.ipify.org 2>/dev/null \
        || true)"
    SERVER_IP="$(printf '%s' "${SERVER_IP}" | tr -d '[:space:]')"
fi
if [ -z "${SERVER_IP}" ]; then
    echo "Error: failed to auto-detect the server's public IPv4 address."
    echo "Re-run with an explicit value: SERVER_IP=<your.ip> PORT=${PORT} bash -s < deploy_dual_proxy.sh"
    exit 1
fi
echo "Detected Server IP: ${SERVER_IP} (${ARCH})"

# Check Cloud Provider Metadata for Firewall Hints
if curl -fsS -m 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/name >/dev/null 2>&1; then
    GCP_PROJECT="$(curl -fsS -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/project/project-id || true)"
    GCP_TAGS="$(curl -fsS -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/tags || true)"
    echo "[Cloud: GCP] Project: ${GCP_PROJECT} | Network Tags: ${GCP_TAGS}"
    echo "[Action Required if Blocked] Allow TCP & UDP ${PORT} in GCP VPC Firewall:"
    echo "  gcloud compute firewall-rules create allow-proxy-${PORT} --project=${GCP_PROJECT} --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:${PORT},udp:${PORT} --source-ranges=0.0.0.0/0"
elif curl -fsS -m 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
    echo "[Cloud: AWS/Cloud-Init] Ensure Security Group allows Inbound TCP ${PORT} and UDP ${PORT} from 0.0.0.0/0."
fi

echo "=========================================="
echo "2. Enabling TCP BBR & UDP Buffer Tuning"
echo "=========================================="
modprobe tcp_bbr 2>/dev/null || true
cat <<'EOF' > /etc/sysctl.d/99-proxy-tuning.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
sysctl --system >/dev/null 2>&1 || true

echo "=========================================="
echo "3. Configuring OS Firewall (UFW / firewalld)"
echo "=========================================="
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow "${PORT}/tcp" >/dev/null
    ufw allow "${PORT}/udp" >/dev/null
    echo "Opened ${PORT}/tcp and ${PORT}/udp in UFW"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null
    firewall-cmd --permanent --add-port="${PORT}/udp" >/dev/null
    firewall-cmd --reload >/dev/null
    echo "Opened ${PORT}/tcp and ${PORT}/udp in firewalld"
else
    echo "No active OS firewall detected"
fi

echo "=========================================="
echo "4. Installing Xray ${XRAY_VERSION} (VLESS + REALITY)"
echo "=========================================="
bash -c "$(curl -fsSL --connect-timeout 15 https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Pin Xray binary to v1.8.24 for universal Mihomo / Shadowrocket REALITY compatibility
curl -fsSL --connect-timeout 15 --retry 2 "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray_pinned.zip
mkdir -p /tmp/xray_pinned
unzip -o /tmp/xray_pinned.zip xray -d /tmp/xray_pinned/
install -m 755 /tmp/xray_pinned/xray /usr/local/bin/xray
rm -rf /tmp/xray_pinned /tmp/xray_pinned.zip
xray version
if ! xray version | grep -q "${XRAY_VERSION#v}"; then
    echo "Error: pinned Xray ${XRAY_VERSION} is not active after installation."
    exit 1
fi

# Select a low-profile TLS 1.3 + H2 target domain (avoiding overused www.apple.com / www.microsoft.com)
REALITY_TARGET="${REALITY_TARGET:-}"
if [ -z "${REALITY_TARGET}" ]; then
    for candidate in "addons.mozilla.org" "www.lovelive-anime.jp" "swdist.apple.com" "dl.google.com"; do
        if curl -fsS -I --tlsv1.3 --http2 --max-time 4 "https://${candidate}" >/dev/null 2>&1; then
            REALITY_TARGET="${candidate}"
            break
        fi
    done
    REALITY_TARGET="${REALITY_TARGET:-addons.mozilla.org}"
fi
echo "Selected REALITY target (SNI): ${REALITY_TARGET}"

VLESS_UUID="${VLESS_UUID:-$(xray uuid)}"
KEYPAIR_OUT="$(xray x25519)"
PRIVATE_KEY="$(echo "${KEYPAIR_OUT}" | awk -F':' '/Private/{print $2}' | tr -d '[:space:]')"
PUBLIC_KEY="$(echo "${KEYPAIR_OUT}" | awk -F':' '/(Public|Password)/{print $2}' | tr -d '[:space:]')"
if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ]; then
    echo "Error: failed to parse xray x25519 output:"
    echo "${KEYPAIR_OUT}"
    exit 1
fi
SHORT_ID="${SHORT_ID:-$(openssl rand -hex 8)}"

mkdir -p /usr/local/etc/xray
cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${VLESS_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_TARGET}:443",
          "xver": 0,
          "serverNames": [
            "${REALITY_TARGET}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

xray run -test -config /usr/local/etc/xray/config.json

DEPLOY_FAILED=0
start_service() {
    local svc="$1"
    if systemctl enable "${svc}" >/dev/null 2>&1 && systemctl restart "${svc}"; then
        echo "[OK] ${svc} started"
    else
        echo "[ERROR] Failed to start ${svc}; inspect: journalctl -u ${svc} -n 100 --no-pager"
        DEPLOY_FAILED=1
    fi
}
start_service xray

echo "=========================================="
echo "5. Installing Hysteria 2 (UDP ${PORT})"
echo "=========================================="
bash <(curl -fsSL --connect-timeout 15 https://get.hy2.sh/)
if ! command -v hysteria >/dev/null 2>&1; then
    echo "Error: Hysteria 2 installation failed (hysteria binary not found)."
    exit 1
fi
if ! id hysteria >/dev/null 2>&1; then
    echo "[WARN] 'hysteria' system user not found; the hysteria-server service may fail to start."
fi

HY2_PASSWORD="${HY2_PASSWORD:-$(openssl rand -hex 12)}"
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=${MASQ_DOMAIN}" \
    -days 3650 2>/dev/null

if id hysteria >/dev/null 2>&1; then
    chown -R hysteria:hysteria /etc/hysteria
fi
chmod 600 /etc/hysteria/server.key
chmod 644 /etc/hysteria/server.crt

HY2_PIN_SHA256="$(openssl x509 -noout -fingerprint -sha256 -in /etc/hysteria/server.crt | cut -d= -f2)"

cat <<EOF > /etc/hysteria/config.yaml
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: ${HY2_PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: https://${MASQ_DOMAIN}
    rewriteHost: true
EOF

# config.yaml contains the auth password; keep it private to the service user.
if id hysteria >/dev/null 2>&1; then
    chown hysteria:hysteria /etc/hysteria/config.yaml
fi
chmod 600 /etc/hysteria/config.yaml

start_service hysteria-server
sleep 2

echo "=========================================="
echo "6. Service Status & Listener Check"
echo "=========================================="
for svc in xray hysteria-server; do
    if systemctl is-active --quiet "${svc}"; then
        echo "[OK] ${svc} is active"
    else
        echo "[ERROR] ${svc} is not active"
        DEPLOY_FAILED=1
    fi
done
if ss -tulpn 2>/dev/null | grep -Eq "[:.]${PORT}([^0-9]|$)"; then
    ss -tulpn 2>/dev/null | grep -E "[:.]${PORT}([^0-9]|$)"
else
    echo "[WARN] No listener detected on port ${PORT}"
fi

VLESS_URI="vless://${VLESS_UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&udp=1#VPS-VLESS-Reality"
HY2_URI="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${PORT}/?sni=${MASQ_DOMAIN}&insecure=1&pinSHA256=${HY2_PIN_SHA256}#VPS-Hysteria2"

echo "SERVER_IP=${SERVER_IP}"
echo "PORT=${PORT}"
echo "REALITY_TARGET=${REALITY_TARGET}"
echo "VLESS_UUID=${VLESS_UUID}"
echo "PUBLIC_KEY=${PUBLIC_KEY}"
echo "SHORT_ID=${SHORT_ID}"
echo "HY2_PASSWORD=${HY2_PASSWORD}"
echo "HY2_PIN_SHA256=${HY2_PIN_SHA256}"
echo "VLESS_URI=${VLESS_URI}"
echo "HY2_URI=${HY2_URI}"
if [ "${DEPLOY_FAILED}" -ne 0 ]; then
    echo "DEPLOY_FAILED"
    exit 1
fi
echo "DEPLOY_DONE"
