# cc-codex-mutual-mcp

[![Release](https://img.shields.io/github/v/release/superchaospc/cc-codex-mutual-mcp?sort=semver)](https://github.com/superchaospc/cc-codex-mutual-mcp/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#requirements)
[![Claude Code skill](https://img.shields.io/badge/Claude%20Code-skill-d97757.svg)](https://docs.anthropic.com/en/docs/claude-code/skills)

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
