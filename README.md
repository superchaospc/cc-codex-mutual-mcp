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

## Why wire them together

Two coding agents from different vendors, with different strengths — calling each other inside one
task instead of you copy-pasting between two windows.

- **Complementary models, cross-vendor review.** Claude (Opus) and GPT/Codex have different blind
  spots. Have one write and the other review (e.g. Claude implements, then `mcp__codex__codex` gets a
  genuine second pair of eyes) — something single-model self-review can't give you, since a model
  rarely catches its own blind spots.
- **No context switching.** Without the bridge you'd finish in CC → copy → open Codex → paste →
  re-explain the background → carry results back. With it, one "let codex do X" lands the files
  directly, **context intact, nothing re-explained**.
- **Two delegation granularities.** `claude_agent` / `mcp__codex__codex` hand off a *whole subtask*
  (the other agent plans + executes autonomously, returns the result); `claude_code`'s leaf tools let
  the caller borrow *one concrete action* (Bash/Edit/…). So the agents can both "outsource a package"
  and "borrow a tool".
- **Route around each other's limits/quota.** When one side is rate-limited (or the task suits the
  other's tooling — Codex's computer-use, a particular Claude skill), finish the work on whichever
  side still has capacity.

**When it's *not* worth it:** trivial tasks one agent can finish alone (the extra hop just adds
latency), flaky moments where the [four gotchas](#the-four-gotchas) cost more to debug than they
save, and cross-model delegation stacking token cost on both sides. Use it for cross-vendor review
and for offloading a subtask to the better-suited agent — not for the sake of using it.

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

The fastest path is the bundled self-test — it proves the pieces actually *execute*, not just that
they're registered, and the default checks spend **no API tokens** (the wrapper is driven against a
stub claude; `claude mcp serve` runs tools without model inference):

```bash
bash scripts/selftest.sh          # free checks (protocol, leaf tool, registrations)
bash scripts/selftest.sh --live   # also run a real headless claude agent (uses tokens)
```

Or check by hand:

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

### 为什么要这样互通

本质是让**两个不同厂商、各有强项的编码 agent 在一次任务里互相调用**,而不是你在两个窗口之间人肉复制粘贴。

- **模型互补、跨厂商交叉审查。** Claude(Opus)和 GPT/Codex 的盲区不一样。让一个写、另一个审(比如 Claude 实现完,直接 `mcp__codex__codex` 拿到真正的「第二双眼睛」)—— 这是单模型自审给不了的,因为模型很难发现自己的盲区。
- **不切上下文、省掉人肉搬运。** 没有这套桥,你得:CC 里干完 → 复制 → 打开 Codex → 粘贴 → 重新解释背景 → 再把结果搬回来。有了桥,一句「让 codex 做 X」文件直接落地,**上下文不丢、不用重讲背景**。
- **两种委派粒度。** `claude_agent` / `mcp__codex__codex` 是把**整个子任务**甩出去(对方自主规划+执行,只收最终结果);`claude_code` 的叶子工具则让调用方只借**一个具体动作**(Bash/Edit…)。等于既能「整包外包」也能「借个工具用」。
- **绕开各自的限制 / 配额。** 当一边被限流(或任务更适合对方的工具——Codex 的 computer-use、某个 Claude skill),就在还有额度的那边把活干完。

**什么时候不值得:** 一个 agent 就能干完的简单任务(互调只是徒增延迟);桥不稳时[四个坑](#四个坑)的排查成本可能高过收益;跨模型委派会**叠加两边的 token 成本**。它的价值在跨厂商交叉审查、把子任务外包给更合适的那个 agent —— 别为了用而用。

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

最快的方式是自带的自检脚本——它证明各部件「能跑」而不只是「已注册」,默认检查**不花任何 API token**(wrapper 用桩 claude 驱动;`claude mcp serve` 执行工具不走模型推理):

```bash
bash scripts/selftest.sh          # 免费检查(协议层、叶子工具、注册状态)
bash scripts/selftest.sh --live   # 额外跑一个真实的 headless claude agent(会花 token)
```

或手动检查:

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
