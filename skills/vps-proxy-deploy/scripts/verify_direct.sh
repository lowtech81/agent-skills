#!/usr/bin/env bash
# Cross-Platform Direct-Line Proxy Verification Script (macOS & Linux)
# Bypasses local VPN / TUN virtual interfaces (utun*, tun*, wg*, Meta) to verify true direct connectivity.
set -uo pipefail

if [ "$#" -lt 8 ]; then
    echo "Usage: $0 <SERVER_IP> <PORT> <VLESS_UUID> <PUBLIC_KEY> <SHORT_ID> <REALITY_SNI> <HY2_PASSWORD> <HY2_PIN_SHA256>"
    exit 1
fi

SERVER_IP="$1"
PORT="$2"
VLESS_UUID="$3"
PUBLIC_KEY="$4"
SHORT_ID="$5"
REALITY_SNI="$6"
HY2_PASSWORD="$7"
HY2_PIN_SHA256="$8"

OS_TYPE="$(uname -s)"

# 1. Auto-detect primary physical network interface (excluding VPN/TUN virtual interfaces)
detect_physical_interface() {
    if [ -n "${PHYS_IF:-}" ]; then
        echo "${PHYS_IF}"
        return
    fi
    if [ "${OS_TYPE}" = "Darwin" ]; then
        local iface
        iface="$(scutil --nwi 2>/dev/null | awk '/Network interfaces:/{print $3}' | tr -d '[:space:]')"
        if [ -z "${iface}" ] || [[ "${iface}" == utun* ]]; then
            iface="en0"
        fi
        echo "${iface}"
    else
        ip route show table main 2>/dev/null \
            | awk '/^default/ && $5 !~ /^(tun|utun|wg|clash|Meta|tailscale|docker)/ {print $5; exit}'
    fi
}

PHYS_IF="$(detect_physical_interface)"
echo "=== 1. Detected Physical Outbound Interface: ${PHYS_IF:-default} ==="

# 2. Direct TCP & TLS 1.3 REALITY Handshake Check over Physical Interface
echo "=== 2. Direct TCP & REALITY Handshake Check (${SERVER_IP}:${PORT}) ==="
if [ "${OS_TYPE}" = "Darwin" ] && [ -n "${PHYS_IF}" ]; then
    if nc -b "${PHYS_IF}" -zv -G 4 "${SERVER_IP}" "${PORT}" 2>&1; then
        echo "[PASS] Direct TCP handshake via ${PHYS_IF} succeeded"
    else
        echo "[FAIL] Direct TCP handshake via ${PHYS_IF} timed out (Check Cloud VPC Firewall or ISP block)"
    fi
elif [ -n "${PHYS_IF}" ]; then
    if curl -sS -I -m 5 --interface "${PHYS_IF}" --noproxy '*' --resolve "${REALITY_SNI}:${PORT}:${SERVER_IP}" "https://${REALITY_SNI}:${PORT}" >/dev/null 2>&1; then
        echo "[PASS] Direct TCP/TLS connection via ${PHYS_IF} succeeded"
    else
        echo "[WARN] Direct TCP/TLS check via ${PHYS_IF} failed or timed out"
    fi
fi

# 3. Auto-detect local Mihomo / Clash Meta binary for full URLTest verification
find_mihomo_binary() {
    if [ -n "${MIHOMO_BIN:-}" ] && [ -x "${MIHOMO_BIN}" ]; then
        echo "${MIHOMO_BIN}"
        return
    fi
    for cmd in mihomo clash-meta verge-mihomo; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            command -v "${cmd}"
            return
        fi
    done
    for path in \
        "/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" \
        "/Applications/Clash Verge.app/Contents/MacOS/clash-meta" \
        "/Applications/FlClash.app/Contents/MacOS/FlClashCore" \
        "/usr/bin/verge-mihomo" \
        "/usr/local/bin/mihomo"; do
        if [ -x "${path}" ]; then
            echo "${path}"
            return
        fi
    done
}

MIHOMO_BIN="$(find_mihomo_binary)"
if [ -z "${MIHOMO_BIN}" ]; then
    echo "=== 3. No local Mihomo binary found; skipping local client URLTest ==="
    echo "Tip: Set MIHOMO_BIN=/path/to/mihomo to run full client-side tunnel verification."
    exit 0
fi

echo "=== 3. Running Isolated Mihomo End-to-End URLTest (using ${MIHOMO_BIN}) ==="
TMP_DIR="$(mktemp -d /tmp/mihomo_verify.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

IFACE_LINE=""
if [ -n "${PHYS_IF}" ]; then
    IFACE_LINE="interface-name: ${PHYS_IF}"
fi

cat <<EOF > "${TMP_DIR}/config.yaml"
mixed-port: 17899
allow-lan: false
mode: rule
log-level: debug
ipv6: false
unified-delay: true
tcp-concurrent: true
${IFACE_LINE}
external-controller: 127.0.0.1:19099

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]
  nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]
  proxy-server-nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]

proxies:
  - name: "Verify-VLESS-Reality"
    type: vless
    server: ${SERVER_IP}
    port: ${PORT}
    uuid: ${VLESS_UUID}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: ${REALITY_SNI}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}

  - name: "Verify-Hysteria2"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${PORT}
    password: ${HY2_PASSWORD}
    sni: www.bing.com
    skip-cert-verify: true
    fingerprint: ${HY2_PIN_SHA256}
EOF

"${MIHOMO_BIN}" -d "${TMP_DIR}" -f "${TMP_DIR}/config.yaml" >"${TMP_DIR}/mihomo.log" 2>&1 &
MPID=$!
sleep 2

for node in "Verify-VLESS-Reality" "Verify-Hysteria2"; do
    echo -n "URLTest [${node}]: "
    curl -sS -m 6 --noproxy '*' "http://127.0.0.1:19099/proxies/${node}/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000" || true
    echo ""
done

kill "${MPID}" 2>/dev/null || true
echo ""
echo "=== 4. Handshake Debug Summary ==="
grep -E "(REALITY|XTLS|error)" "${TMP_DIR}/mihomo.log" | tail -n 25 || true
