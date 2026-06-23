# cc-codex-mutual-mcp

[![Release](https://img.shields.io/github/v/release/superchaospc/cc-codex-mutual-mcp?sort=semver)](https://github.com/superchaospc/cc-codex-mutual-mcp/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#requirements)
[![Claude Code skill](https://img.shields.io/badge/Claude%20Code-skill-d97757.svg)](https://docs.anthropic.com/en/docs/claude-code/skills)

**English** | [中文说明](#中文说明)

Wire **Claude Code** and the desktop **Codex.app** (OpenAI Codex) as each other's MCP server, so a
session in either coding agent can hand real work to the other. This is a [Claude Code
skill](https://docs.anthropic.com/en/docs/claude-code/skills) — it also auto-discovers in Codex,
which uses the same `SKILL.md` format. Drop it in `~/.claude/skills/` (and/or symlink into
`~/.codex/skills/`) and it triggers when you ask either agent to "let codex/claude do X".

## What it sets up

Three MCP server registrations across two directions:

| Direction | Server | Command | Exposes |
|---|---|---|---|
| Claude Code → Codex | `codex` | `<codex> mcp-server` | `mcp__codex__codex` (full Codex session) + `mcp__codex__codex-reply` |
| Codex → Claude Code | `claude_code` | `claude mcp serve` | CC's leaf tools — Bash, Read, Edit, Write, Grep, Glob, WebSearch… |
| Codex → Claude Code | `claude_agent` | `node scripts/claude-agent-mcp.mjs` | one tool `claude_agent` = run a whole headless Claude agent |

`claude mcp serve` is a **native** Claude Code subcommand — no wrapper is required to make CC callable
from Codex. The bundled `claude_agent` wrapper is optional sugar: it gives Codex a single
"delegate a whole task" entry point (Claude plans + executes autonomously and returns its final text),
instead of only atomic leaf tools.

## Requirements

- macOS with the desktop **Codex.app** installed (its bundled CLI is at
  `/Applications/Codex.app/Contents/Resources/codex`).
- **Claude Code** CLI (`claude`) on PATH.
- **Node.js** on PATH (for the `claude_agent` wrapper).

## Install

```bash
bash install.sh
```

The installer autodetects the Codex / `claude` / `node` binaries, registers all three servers
idempotently, and **preserves** any MCP servers Codex already has (e.g. `node_repl`). Override
detection with env vars if needed: `CODEX_BIN=… CLAUDE_BIN=… bash install.sh`.

### Verify

```bash
claude mcp list   # codex … ✔ Connected
/Applications/Codex.app/Contents/Resources/codex mcp list   # claude_code AND claude_agent
```

Then prove it executes, not just connects:

- In Claude Code: *"have codex write a hello-world script to /tmp/hw.sh"* → CC opens a real Codex
  session and the file appears.
- In Codex: *"use claude_code's Bash tool to `echo hi > /tmp/cc.txt`"* (leaf tool), or *"use
  claude_agent to create and read back a marker file"* (whole task).

## The four gotchas

A freshly *registered* bridge often looks dead. These are why:

1. **`Agent` tool is broken in `claude mcp serve`** (`Agent type 'general-purpose' not found`).
   Tell Codex to use a concrete leaf tool ("use claude_code's Bash…") or the `claude_agent` wrapper.
2. **Codex's default sandbox silently cancels write MCP calls** (`sandbox: read-only` +
   `approval: never`). Use `codex exec --dangerously-bypass-approvals-and-sandbox` or raise trust.
3. **Headless `claude -p` → Codex MCP can hang.** For scripted "have Codex do X", skip the MCP hop:
   `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "…"`.
4. **Recursion.** The wrapper spawns `claude` with `--strict-mcp-config --mcp-config '{"mcpServers":{}}'`
   so the inner agent doesn't re-load the `codex` server. Keep that guard if you edit it.

## Wrapper configuration

`scripts/claude-agent-mcp.mjs` reads two env vars:

- `CLAUDE_BIN` — path to the `claude` binary (default `/opt/homebrew/bin/claude`). The installer
  passes the detected path through.
- `CLAUDE_AGENT_TIMEOUT_MS` — kill timeout for a hung agent (default `600000` = 10 min).

## Uninstall

```bash
bash uninstall.sh
```

Removes the three registrations; leaves other MCP servers untouched.

## License

MIT

---

## 中文说明

把 **Claude Code** 和桌面版 **Codex.app**(OpenAI Codex)互相注册成对方的 MCP server,这样在任一编码助手里的会话都能把真实任务交给另一个去做。这是一个 [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) —— 它用同样的 `SKILL.md` 格式,在 Codex 里也能被自动发现。把它放进 `~/.claude/skills/`(并/或软链到 `~/.codex/skills/`),当你让任一助手「让 codex/claude 去做某事」时就会触发。

### 它配置了什么

跨两个方向的三个 MCP server 注册:

| 方向 | Server | 命令 | 暴露的能力 |
|---|---|---|---|
| Claude Code → Codex | `codex` | `<codex> mcp-server` | `mcp__codex__codex`(完整 Codex 会话)+ `mcp__codex__codex-reply` |
| Codex → Claude Code | `claude_code` | `claude mcp serve` | CC 的原子叶子工具 —— Bash、Read、Edit、Write、Grep、Glob、WebSearch… |
| Codex → Claude Code | `claude_agent` | `node scripts/claude-agent-mcp.mjs` | 单个工具 `claude_agent` = 跑一个完整的 headless Claude agent |

`claude mcp serve` 是 Claude Code **原生**子命令 —— 让 CC 能被 Codex 调用并不需要任何 wrapper。自带的 `claude_agent` wrapper 只是可选的语法糖:它给 Codex 一个「把整个任务委派出去」的单一入口(Claude 自主规划 + 执行,返回最终文本),而不只是一堆原子叶子工具。

### 依赖

- macOS,装了桌面版 **Codex.app**(其自带 CLI 在 `/Applications/Codex.app/Contents/Resources/codex`)。
- **Claude Code** CLI(`claude`)在 PATH 中。
- **Node.js** 在 PATH 中(给 `claude_agent` wrapper 用)。

### 安装

```bash
bash install.sh
```

安装脚本会自动探测 Codex / `claude` / `node` 三个二进制,幂等地注册全部三个 server,并**保留** Codex 已有的 MCP server(如 `node_repl`)。需要时可用环境变量覆盖探测:`CODEX_BIN=… CLAUDE_BIN=… bash install.sh`。

### 验证

```bash
claude mcp list   # codex … ✔ Connected
/Applications/Codex.app/Contents/Resources/codex mcp list   # claude_code 和 claude_agent
```

然后证明它「能跑」而不只是「能连」:

- 在 Claude Code 里:*「让 codex 写一个 hello-world 脚本到 /tmp/hw.sh」* → CC 会开一个真正的 Codex 会话,文件随之出现。
- 在 Codex 里:*「用 claude_code 的 Bash 工具执行 `echo hi > /tmp/cc.txt`」*(叶子工具),或 *「用 claude_agent 创建并读回一个标记文件」*(整任务)。

### 四个坑

刚「注册」好的桥往往看起来是死的,原因在这:

1. **`claude mcp serve` 里的 `Agent` 工具是坏的**(报 `Agent type 'general-purpose' not found`)。让 Codex 改用具体的叶子工具(「用 claude_code 的 Bash…」)或 `claude_agent` wrapper。
2. **Codex 默认沙箱会静默取消写类 MCP 调用**(`sandbox: read-only` + `approval: never`)。用 `codex exec --dangerously-bypass-approvals-and-sandbox`,或提升信任级别。
3. **Headless `claude -p` → Codex MCP 可能卡死**。脚本化的「让 Codex 做 X」请跳过 MCP 这一跳:`codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "…"`。
4. **递归**。wrapper 会用 `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` 启动 `claude`,这样内层 agent 不会再加载 `codex` server。改 wrapper 时务必保留这个保护。

### wrapper 配置

`scripts/claude-agent-mcp.mjs` 读两个环境变量:

- `CLAUDE_BIN` —— `claude` 二进制路径(默认 `/opt/homebrew/bin/claude`),安装脚本会把探测到的路径传进去。
- `CLAUDE_AGENT_TIMEOUT_MS` —— 卡死 agent 的强杀超时(默认 `600000` = 10 分钟)。

### 卸载

```bash
bash uninstall.sh
```

移除这三个注册;其它 MCP server 原封不动。

### 许可证

MIT
