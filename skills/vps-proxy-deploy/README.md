# vps-proxy-deploy

一个通用的 AI Agent Skill，用于在 Linux VPS（支持 `x86_64` 与 `arm64`，兼容 Debian / Ubuntu / Rocky / CentOS）上一键部署双协议代理服务（**VLESS + XTLS-Vision + REALITY** 与 **Hysteria 2**），并在客户端通过绑定物理网卡进行真实的直连连通性验证。

## 核心特性

1. **双协议主力 + 备用架构**
   - **TCP 主力协议**：`VLESS + XTLS-Vision + REALITY`（免域名、免买证书，自动探测低风险 TLS 1.3 + HTTP/2 伪装目标，规避 `www.apple.com` / `www.microsoft.com` 等已被 DPI 重点标记的公共 SNI）。
   - **UDP 加速/备用协议**：`Hysteria 2`（基于 QUIC，适合高丢包与晚高峰环境，内置自签证书 SHA256 指纹固定 `pinSHA256` 与反向代理伪装）。
2. **跨客户端内核兼容保障**
   - 自动将服务端 Xray 核心锁定为 **`v1.8.24`**，解决新版 `Xray 26.x` 后量子密钥交换状态机变更导致的 Clash Verge (`Mihomo v1.19.x`) `REALITY Authentication: false` 握手失败问题。
3. **绕过本机 VPN 的真机物理直连核验**
   - 自动识别客户端物理网卡（macOS `en0` / Linux 默认物理网卡，排除 `utun*`、`tun*`、`wg*`、`Meta`），避免因本地 TUN 用户态 TCP 栈代答三次握手造成的“假连通”误判。
4. **通用客户端配置导出**
   - 自动生成标准分享链接（`vless://` / `hysteria2://`）、Base64 通用订阅文件（适用于 Shadowrocket / v2rayN / v2rayNG / NekoBox）以及独立 `clash-meta.yaml` 配置。
   - **可选扩展**：提供 Clash Verge 订阅扩展脚本模板（`scripts/clash_verge_inject.js`），解决 `include-all-proxies: true` 导致扩展节点重复出现两次及无 IPv6 环境下域名节点解析超时的问题。

## 目录结构

```text
vps-proxy-deploy/
├── SKILL.md                             # Agent Skill 核心工作流与触发规则
├── README.md                            # 项目说明文档
├── scripts/
│   ├── deploy_dual_proxy.sh             # 服务端双协议自动部署脚本 (Xray v1.8.24 + Hysteria 2 + BBR)
│   ├── verify_direct.sh                 # 客户端绕过本地 VPN 绑定物理网卡直连验证脚本
│   └── clash_verge_inject.js            # [可选] Clash Verge 订阅扩展注入脚本模板
└── references/
    └── troubleshooting-and-lessons.md   # 常见排障案例与底层原理解析手册
```

## 安装为全局 Skill

从技能市场仓库一键安装（自动适配 Gemini / Claude Code / OpenCode / Codex）：

```bash
# 第二个参数可指定目标：gemini | claude | opencode | codex | all
curl -fsSL https://raw.githubusercontent.com/lowtech81/agent-skills/main/scripts/install.sh | bash -s -- vps-proxy-deploy gemini
```

也可以克隆整个市场仓库后本地执行：

```bash
git clone https://github.com/lowtech81/agent-skills.git /tmp/agent-skills
bash /tmp/agent-skills/scripts/install.sh vps-proxy-deploy claude
```
