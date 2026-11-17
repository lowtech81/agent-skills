# Agent Skills Marketplace (`lowtech81/agent-skills`)

一个遵循开放 [Agent Skills 规范 (`SKILL.md`)](https://agentskills.io) 的多智能体技能市场仓库，原生兼容所有主流 AI 编程助手与终端智能体：

- **Google Antigravity / Gemini CLI** (`plugin.json` / `gemini-extension.json` / `~/.gemini/config/skills/`)
- **Claude Code** (`.claude-plugin/marketplace.json` / `~/.claude/skills/`)
- **OpenCode** (`~/.config/opencode/skills/`)
- **OpenAI Codex CLI** (`~/.codex/skills/` / `.agents/skills/`)
- **Universal Skills CLI (`npx skills`)**（支持 Cursor、Windsurf、Cline、Goose 等全部兼容 Agent）

---

## 已收录 Skills 目录

| Skill 名称 | 分类 | 功能简介 | 文档 |
| :--- | :--- | :--- | :--- |
| **[`vps-proxy-deploy`](./skills/vps-proxy-deploy)** | `devops` / `network` | 在 Linux VPS (`x86_64` / `arm64`) 上一键部署与排障双协议代理（`VLESS + XTLS-Vision + REALITY` 与 `Hysteria 2`），支持绕过本地 VPN 绑定物理网卡进行真机直连核验，并导出 Shadowrocket / Clash / v2rayN / Sing-box 配置。 | [查看详情](./skills/vps-proxy-deploy/README.md) |

---

## 快速安装指南（支持全平台 Agent）

### 方式 1：通过通用 `npx skills` CLI 安装（推荐，自动适配所有 Agent）

如果你使用 **Claude Code**、**OpenCode**、**Codex**、**Gemini CLI**、**Cursor** 或 **Antigravity**：

```bash
# 安装指定 Skill（如 vps-proxy-deploy）
npx skills add lowtech81/agent-skills --skill vps-proxy-deploy

# 或交互式选择仓库中的所有 Skills
npx skills add lowtech81/agent-skills
```

### 方式 2：一键安装脚本（同时部署到 Gemini / Claude Code / OpenCode / Codex）

```bash
# 安装全部 Skills 到所有本地 Agent 目录
curl -fsSL https://raw.githubusercontent.com/lowtech81/agent-skills/main/scripts/install.sh | bash

# 仅安装指定 Skill（例如 vps-proxy-deploy）到指定 Agent（gemini | claude | opencode | codex | all）
curl -fsSL https://raw.githubusercontent.com/lowtech81/agent-skills/main/scripts/install.sh | bash -s -- vps-proxy-deploy all
```

### 方式 3：各 Agent 原生插件市场 / 扩展命令安装

- **Claude Code (Plugin Marketplace)**：
  ```text
  /plugin marketplace add lowtech81/agent-skills
  /plugin install vps-proxy-deploy@lowtech81-agent-skills
  ```
- **Google Antigravity**：
  ```bash
  git clone https://github.com/lowtech81/agent-skills.git ~/.gemini/config/plugins/lowtech81-agent-skills
  ```
- **Gemini CLI**：
  ```bash
  gemini extensions install https://github.com/lowtech81/agent-skills
  ```
- **OpenCode / Codex 手动克隆单个或全部 Skill**：
  ```bash
  git clone https://github.com/lowtech81/agent-skills.git /tmp/agent-skills
  bash /tmp/agent-skills/scripts/install.sh --all
  ```

---

## 仓库目录结构

本仓库采用多生态兼容的混合清单结构，新增 Skill 时只需在 `skills/<new-skill-name>/` 下创建标准 `SKILL.md`，并在 `.claude-plugin/marketplace.json` 中注册即可：

```text
agent-skills/
├── README.md                                  # 技能市场总览与跨平台安装说明
├── plugin.json                                # Google Antigravity 插件清单
├── gemini-extension.json                      # Gemini CLI 扩展清单
├── .claude-plugin/
│   ├── plugin.json                            # Claude Code 插件清单
│   └── marketplace.json                       # Claude Code Marketplace 技能目录索引
├── scripts/
│   └── install.sh                             # 跨 Agent (Gemini/Claude/OpenCode/Codex) 一键安装脚本
└── skills/
    └── vps-proxy-deploy/                      # [Skill #1] VPS 双协议代理部署与核验
        ├── SKILL.md                           # 标准 Agent Skill 定义文件
        ├── README.md                          # Skill 独立说明文档
        ├── scripts/
        │   ├── deploy_dual_proxy.sh           # 服务端双协议部署脚本
        │   ├── verify_direct.sh               # 客户端物理网卡直连核验脚本
        │   └── clash_verge_inject.js          # [可选] Clash Verge 订阅扩展模板
        └── references/
            └── troubleshooting-and-lessons.md # 实战排障与底层原理参考手册
```
