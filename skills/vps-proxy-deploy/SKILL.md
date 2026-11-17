---
name: vps-proxy-deploy
description: >-
  Deploy, verify, and troubleshoot dual-stack proxy services (VLESS + XTLS-Vision + REALITY
  and Hysteria 2) on remote Linux VPS servers, perform true direct-line verification
  bypassing local VPN/TUN interfaces, and export configurations for Clash, Shadowrocket,
  v2rayN, and Sing-box. Use this skill whenever a user wants to set up a proxy/VPN on a
  VPS, diagnose node timeouts, or export client configurations.
---

# VPS Dual-Stack Proxy Deployment & Verification Skill

This skill provides a general-purpose, cross-platform workflow for deploying dual-protocol proxy services (**VLESS + XTLS-Vision + REALITY** over TCP and **Hysteria 2** over UDP) on any Linux VPS (`x86_64` or `arm64`), verifying real direct-line connectivity without false positives from local VPNs, and exporting universal client configurations.

---

## 1. Core Technical Rules

Follow these rules in every deployment to avoid common network and client-compatibility pitfalls:

1. **Pin Xray-core Version for Client Compatibility (`v1.8.24`)**:
   - Bleeding-edge `Xray 26.x` (built with `go1.27` and post-quantum `X25519MLKEM768` REALITY changes) causes handshake validation failures (`REALITY Authentication: false` / `hs.c.isHandshakeComplete.Load(): false`) when accessed by **Mihomo (`v1.19.x`)** used in Clash clients.
   - Always pin the server's Xray binary to **`v1.8.24`** (supporting both `x86_64` and `arm64`) for universal compatibility across Mihomo, Shadowrocket, Xray, and Sing-box clients.
2. **Avoid Overused Big-Tech REALITY SNIs**:
   - Never use `www.apple.com`, `www.microsoft.com`, `www.bing.com`, or `www.yahoo.com` as REALITY `dest` / `serverNames`. Domestic ISP DPI actively blocks TLS handshakes carrying these SNIs when the destination IP does not belong to those companies' ASNs, and newer Xray versions explicitly flag them as high-risk.
   - Probe candidate domains from the VPS (`curl -I --tlsv1.3 --http2`) and pick a low-profile foreign site supporting TLS 1.3 + HTTP/2 (e.g., `addons.mozilla.org`, `www.lovelive-anime.jp`, or a user-specified niche domain).
3. **Check Both OS Firewall and Cloud VPC Security Groups**:
   - Dual-protocol deployment on a single port (default `443`) requires **both `TCP` (VLESS-REALITY) and `UDP` (Hysteria 2)** to be open.
   - Cloud providers (GCP, AWS, Alicloud, Tencent, Oracle, Azure) often block `UDP 443` even when "Allow HTTPS" is checked (which only opens `TCP 443`), or block both when instance tags/security groups are default. Always detect the cloud provider and remind the user to allow both `TCP` and `UDP` on the chosen port.
4. **Bypass Local VPN / TUN During Client-Side Verification**:
   - If the client machine already has a VPN or TUN proxy running (such as `utun*` / `Meta` / `tun0`), standard tools like `nc -zv <VPS_IP> <PORT>` or `curl` will be intercepted by the local user-space TCP stack (which completes the 3-way TCP handshake locally) or routed through the existing VPN, producing **false positives**.
   - Always detect and bind to the physical network interface (e.g., `en0` on macOS, `eth0`/`wlan0` on Linux) and bypass Fake-IP DNS (`198.18.0.0/16`) when testing connectivity.

---

## 2. Standard Deployment Workflow

### Step 1: Gather or Confirm Parameters
Check if the user has provided:
- **Server IP / Host** and **SSH User / Port** (default: `root`, port `22`)
- **Listen Port** (default: `443` for both TCP VLESS-REALITY and UDP Hysteria 2; or custom ports if `443` is occupied by a web server)

### Step 2: Execute Server Deployment
Run [scripts/deploy_dual_proxy.sh](./scripts/deploy_dual_proxy.sh) on the remote server:
```bash
ssh root@<SERVER_IP> "PORT=443 bash -s" < scripts/deploy_dual_proxy.sh | tee deploy.log
```
What the script does automatically:
- Detects CPU architecture (`x86_64` / `aarch64`) and cloud provider metadata (GCP / AWS / generic).
- Enables kernel TCP BBR (`net.ipv4.tcp_congestion_control = bbr`) and tunes UDP buffers for QUIC.
- Opens the target TCP/UDP port in `ufw` / `firewalld` if active.
- Installs Xray pinned to `v1.8.24`, generates UUID / x25519 keys / shortId, verifies a working TLS 1.3 + H2 target domain, and blocks private/metadata IP ranges (`169.254.0.0/16`, RFC1918) to prevent SSRF.
- Installs Hysteria 2, generates a 10-year ECDSA self-signed certificate with SHA256 fingerprint pinning (`pinSHA256`), and configures reverse-proxy masquerade.
- Prints ready-to-use `vless://` and `hysteria2://` URIs and raw parameters.

### Step 3: Verify Direct-Line Connectivity from Client
Run [scripts/verify_direct.sh](./scripts/verify_direct.sh) on the client machine:
```bash
bash scripts/verify_direct.sh <SERVER_IP> <PORT> <VLESS_UUID> <PUBLIC_KEY> <SHORT_ID> <REALITY_SNI> <HY2_PASSWORD> <HY2_PIN_SHA256>
```
What the verification script does:
- Auto-detects the physical outbound network interface on macOS or Linux (ignoring `utun*`, `tun*`, `wg*`, `clash*` virtual interfaces).
- Tests direct physical TCP reachability and TLS 1.3 REALITY handshake.
- If a local Mihomo / Clash Meta binary is available, runs an isolated temporary instance bound to the physical interface with `log-level: debug` to verify `REALITY Authentication: true` and real `URLTest` latency against `https://www.gstatic.com/generate_204`.

### Step 4: Export Standard Client Configurations
By default, generate universal client configuration files in the workspace:
1. **`nodes.txt` & `sub-base64.txt`**: Standard `vless://` and `hysteria2://` share URIs and Base64-encoded subscription file for **Shadowrocket**, **v2rayN**, **v2rayNG**, **NekoBox**, and **V2Box**.
2. **`clash-meta.yaml`**: Standalone **Clash Meta / Mihomo / Stash** configuration with `url-test` / `fallback` groups, domestic DNS (`223.5.5.5`), and `ipv6: false`.

---

## 3. Optional: Injecting Nodes into an Existing Clash Verge Subscription

> **Note**: This step is **optional** and should **only** be performed when the user explicitly asks to merge the new nodes into an existing third-party Clash Verge subscription.

When injecting custom nodes into an existing Clash Verge profile via a Profile Extension Script, use the template in [scripts/clash_verge_inject.js](./scripts/clash_verge_inject.js), which avoids two common pitfalls:
- **Node Duplication**: When a profile's Merge template uses `include-all-proxies: true`, manually pushing custom nodes into `g.proxies` causes custom nodes to appear **twice**. The template expands deduplicated proxies into `g.proxies` and deletes `include-all-proxies`, while skipping ad-block groups (`🛑 广告拦截`).
- **Domain Node Timeouts**: Sets `config.ipv6 = false` and injects domestic `default-nameserver`, `nameserver`, and `proxy-server-nameserver` entries so domain-based nodes do not fail DNS resolution.

---

## 4. Troubleshooting Reference
When diagnosing node timeouts, `REALITY Authentication: false`, or firewall drops, consult:
- [Troubleshooting & Lessons Learned](./references/troubleshooting-and-lessons.md)
