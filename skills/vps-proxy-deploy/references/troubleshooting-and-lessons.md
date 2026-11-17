# VPS Proxy Deployment: Troubleshooting & Lessons Learned

This reference summarizes common failure modes, packet-level diagnostics, and permanent fixes when deploying `VLESS + XTLS-Vision + REALITY` and `Hysteria 2` on cloud VPS instances.

---

## 1. `Xray 26.x` vs `Mihomo v1.19.x` REALITY Handshake Incompatibility

### Symptom
- **Shadowrocket (iOS) / v2rayN (Xray core)**: `VLESS + XTLS-Vision + REALITY` connects normally.
- **Server-side Loopback (`xray` client -> `xray` server)**: `curl --socks5` returns `HTTP 204`.
- **Clash Verge / Mihomo (`v1.19.x`)**: Fails latency test with `{"message":"An error occurred in the delay test"}`.
- **Mihomo Debug Log (`log-level: debug`)**:
  ```text
  level=debug msg="REALITY localAddr: <SERVER_IP>:443 is using X25519MLKEM768 for TLS' communication: false"
  level=debug msg="REALITY Authentication: false, AEAD: *aes.gcmAsm"
  ```
- **Xray Server Debug Log (`realitySettings.show: true`)**:
  ```text
  REALITY remoteAddr: <CLIENT_IP>:<PORT>        forwarded SNI: <SNI>
  REALITY remoteAddr: <CLIENT_IP>:<PORT>        hs.c.isHandshakeComplete.Load(): false
  [Info] transport/internet/tcp: REALITY: processed invalid connection: authentication failed or validation criteria not met
  ```

### Root Cause
`Xray 26.x` (built with `go1.27` and post-quantum `X25519MLKEM768` REALITY changes) modifies the target handshake state check (`hs.c.isHandshakeComplete`). When `Mihomo v1.19.x` (built with `go1.22`) initiates a REALITY handshake, `Xray 26.x` evaluates `hs.c.isHandshakeComplete.Load()` as `false` and rejects authentication, falling back to the masquerade website.

### Fix
1. Pin the server's Xray binary to **`Xray v1.8.24`** (`go1.23.0`), which is 100% compatible with both Mihomo and Xray/Shadowrocket clients.
2. When parsing `xray x25519` output in deployment scripts, match both `Public` and `Password` labels (`awk -F':' '/(Public|Password)/{print $2}' | tr -d '[:space:]'`), because newer Xray CLI versions renamed `Public key:` to `Password (PublicKey):`.

---

## 2. ISP DPI Blocking of Overused REALITY SNIs (`www.apple.com`, `www.microsoft.com`)

### Symptom
- Even with `Xray v1.8.24`, REALITY connections using `www.apple.com` or `www.microsoft.com` as `servername` time out on domestic broadband lines, while UDP Hysteria 2 on the same server works.
- Newer Xray versions emit an explicit startup warning against choosing `www.apple.com` as the REALITY target.

### Root Cause
Domestic ISP DPI systems actively flag TLS `ClientHello` packets carrying high-profile SNIs (`www.apple.com`, `www.microsoft.com`) when the destination IP does not belong to Apple or Microsoft ASNs.

### Fix
Select a low-profile foreign website that supports TLS 1.3 and HTTP/2 (verify from the VPS with `curl -I --tlsv1.3 --http2 https://<domain>`).

---

## 3. False Positives When Local VPN / TUN Mode is Active

### Symptom
- Running `nc -zv <SERVER_IP> 443` or `curl` on a client machine where Clash TUN (`utun*` / `Meta` / `tun0`) is active immediately reports `Connection succeeded!`, even when the remote server's port 443 is completely blocked by a cloud firewall.
- Or traffic succeeds only because it is routed through an existing working VPN node rather than the direct ISP line.

### Root Cause
1. TUN virtual interfaces (`gvisor` / `system` stack) intercept outbound TCP SYN packets via split routes (`1/8`, `2/7`, ..., `128.0/1`) and complete the 3-way TCP handshake locally on the client machine before dialing upstream.
2. `dns-hijack: [any:53]` returns Fake-IPs in `198.18.0.0/16`, which cannot be routed when binding a socket directly to a physical interface.

### Fix
1. Bind test tools directly to the physical interface (`nc -b <PHYS_IF>` on macOS, `curl --interface <PHYS_IF> --noproxy '*'`) and resolve domains against a public DNS server (`dig -b <LOCAL_PHYS_IP> @223.5.5.5`).
2. For end-to-end verification, launch an isolated Mihomo process with `interface-name: <PHYS_IF>` and `log-level: debug`, and test via its RESTful API (`/proxies/<Name>/delay?url=https://www.gstatic.com/generate_204&timeout=5000`).

---

## 4. Cloud VPC Firewall Traps (GCP, AWS, Oracle, Alicloud)

### Symptom
- `xray` (TCP) and `hysteria-server` (UDP) are `active (running)` and listening on port `443`, OS firewall (`ufw`/`firewalld`) is inactive or open, `ICMP` and `TCP 22` reach the server, but `tcpdump -ni any port 443` on the server sees 0 packets.

### Root Cause
- **GCP**: A VM with empty `Network Tags: []` only allows `default-allow-icmp`, `default-allow-ssh` (`tcp:22`), and `default-allow-rdp` (`tcp:3389`). Even checking "Allow HTTPS traffic" (`https-server` tag) only opens `tcp:443` and drops `udp:443` (breaking Hysteria 2).
- **AWS / Alicloud / Tencent**: Security groups often open `TCP 443` without `UDP 443`.

### Fix
Always verify cloud firewall rules for **both `TCP` and `UDP`** on the proxy port. If the user cannot access their cloud console immediately on a default GCP VM, `TCP 3389` (`default-allow-rdp`) is open by default and can be used as an emergency port.

---

## 5. Clash Verge Subscription Enhancement Pitfalls (Merge + Script)

### Pitfall A: Custom Extended Nodes Appearing Twice in Proxy Groups
- **Cause**: In Clash Verge Rev's profile enhancement pipeline, `Merge` runs **before** `Script`. When the Merge template sets `include-all-proxies: true` on proxy groups, and the Script also manually prepends custom node names into `g.proxies` without deleting `include-all-proxies: true`, Mihomo includes `g.proxies` first and then appends all `config.proxies` (which also contains the custom nodes) a second time.
- **Fix**: In the Script, for any group where `g["include-all-proxies"]` is true, expand all deduplicated proxy names into `g.proxies` once and `delete g["include-all-proxies"]`. Also skip ad-block groups (`🛑 广告拦截` / `REJECT`-only groups).

### Pitfall B: Domain-Based Proxy Nodes Timing Out
- **Cause**: Minimal remote subscriptions often omit the `dns:` section and leave `ipv6: true`. On client networks without IPv6, Mihomo either lacks upstream `nameserver` / `proxy-server-nameserver` entries or resolves Cloudflare/CDN domain nodes to unreachable IPv6 `AAAA` addresses.
- **Fix**: Set `config.ipv6 = false` and inject `config.dns` (`ipv6: false`, `default-nameserver`, `nameserver`, `proxy-server-nameserver`) at the top of `main(config)` in the extension script.
