---
name: cc-codex-mutual-mcp
description: >-
  Wire Claude Code and the desktop Codex.app (OpenAI Codex) as each other's MCP server, so each
  coding agent can hand work to the other. Use this WHENEVER the user wants to "让 cc 和 codex 互相
  指挥/调用", "wire codex and claude code as MCP servers", "让 codex 能调用 claude / 让 claude 能调
  codex", "cross-tool delegation between claude code and codex", "set up the mutual MCP bridge",
  "为什么 codex 看不到 claude code / claude 调不动 codex", or asks to install/repair/remove this
  two-way bridge. Sets up BOTH directions plus a one-shot `claude_agent` whole-task wrapper, and bakes
  in the four gotchas that silently break the bridge (Agent tool dead in serve mode, Codex sandbox/
  approval cancelling calls, headless claude -p hanging, recursion). Trigger even if the user only
  names one direction — wiring is symmetric and usually both are wanted. NOT for adding arbitrary
  third-party MCP servers, and NOT for sharing skill files between the two tools (that's a symlink job,
  see the share-skill-with-codex skill).
---

# Wire Claude Code ⇄ Codex as mutual MCP servers

Claude Code (CC) and the desktop **Codex.app** can each act as an MCP *server* for the other, so a
session in one tool can delegate real work to the other. This skill installs and verifies that
two-way bridge, plus a thin `claude_agent` wrapper that gives Codex a single "delegate a whole task"
entry point.

There are **three** registrations, in two directions:

| Direction | Server name | Command | What it exposes |
|---|---|---|---|
| CC → Codex | `codex` (in `~/.claude.json`) | `<codex> mcp-server` | `mcp__codex__codex` (full Codex session) + `mcp__codex__codex-reply` |
| Codex → CC | `claude_code` (in `~/.codex/config.toml`) | `claude mcp serve` | CC's atomic leaf tools: Bash, Read, Edit, Write, Grep, Glob, WebSearch… |
| Codex → CC | `claude_agent` (in `~/.codex/config.toml`) | `node scripts/claude-agent-mcp.mjs` | ONE tool `claude_agent` = run a full headless Claude agent, return final text |

`claude mcp serve` is an **official, native** Claude Code subcommand (verify with `claude mcp serve
--help`). You do **not** need a wrapper to make CC callable from Codex — the wrapper only improves
*granularity* (one-shot whole-task delegation vs. atomic leaf tools).

## Prerequisites — check before installing

Run these and confirm both exist:

- **Codex.app present**: the bundled CLI lives at `/Applications/Codex.app/Contents/Resources/codex`
  (it is NOT on PATH — it's the desktop app's binary). If the user installed Codex elsewhere, find it
  and use that absolute path everywhere below.
- **`claude` on PATH**: `command -v claude` (Claude Code CLI). Note its absolute path — the wrapper
  needs it.
- **`node` on PATH**: `command -v node` (for the `claude_agent` wrapper).

If Codex.app is missing, stop and tell the user to install it first; this bridge is specifically for
the desktop Codex app's bundled CLI, not a generic `codex` on PATH.

## Install

Prefer the bundled installer — it detects the Codex binary + `claude`/`node` paths, registers all
three servers idempotently, and **preserves** any MCP servers Codex already has (e.g. `node_repl`)
rather than clobbering them:

```bash
bash <skill-dir>/install.sh
```

If the user wants it done by hand, or the installer's autodetection guesses wrong, run the three
registrations explicitly:

```bash
# A) CC → Codex  (user scope, lands in ~/.claude.json)
claude mcp add codex -s user -- /Applications/Codex.app/Contents/Resources/codex mcp-server

# B) Codex → CC, leaf tools  (lands in ~/.codex/config.toml)
codex mcp add claude_code -- claude mcp serve

# C) Codex → CC, whole-task wrapper
codex mcp add claude_agent -- node <skill-dir>/scripts/claude-agent-mcp.mjs
```

`codex mcp add` here means the Codex CLI's own server-management subcommand — i.e.
`/Applications/Codex.app/Contents/Resources/codex mcp add …`. The wrapper reads `CLAUDE_BIN` from the
environment (default `/opt/homebrew/bin/claude`); if `claude` is elsewhere, the installer writes the
correct path, or set `CLAUDE_BIN` yourself.

## Verify (do this — a "registered" server is not a "working" one)

```bash
claude mcp list          # expect: codex … ✔ Connected
codex mcp list           # expect: claude_code AND claude_agent listed
```

Then prove each direction actually executes, not just connects:

- **CC → Codex**: in a CC session, say *"have codex write a hello-world script to /tmp/hw.sh"*. CC
  should spin up a real Codex session via `mcp__codex__codex` and the file should appear.
- **Codex → CC**: in a Codex session, say *"use claude_code's Bash tool to `echo hi > /tmp/cc.txt`"*
  (leaf tool), or *"use claude_agent to create and read back a marker file"* (whole task).

## The four gotchas (bake these into any troubleshooting)

These are why a freshly "registered" bridge appears dead. Read them before debugging.

1. **`Agent` tool is broken in `claude mcp serve`** — it reports `Agent type 'general-purpose' not
   found` (no sub-agent types registered in serve mode). Codex's model instinctively reaches for
   `Agent` when told to "delegate to Claude Code". Tell Codex to use a **concrete leaf tool**
   instead ("use claude_code's Bash to…", "use claude_code's Edit to…"), or use the `claude_agent`
   wrapper for whole tasks.

2. **Codex's default sandbox silently cancels MCP calls** — Codex defaults to `sandbox: read-only` +
   `approval: never`, which *cancels* write-side MCP calls with no error. For Codex to drive CC write
   ops headlessly, run `codex exec --dangerously-bypass-approvals-and-sandbox`, or raise the
   project's trust level.

3. **Headless `claude -p` → Codex MCP can hang** — delegating through a non-interactive
   `claude -p "… mcp__codex__codex …"` sometimes stalls forever (the spawned `codex mcp-server` child
   never finishes its handshake; empty output, no file). The *interactive* CC session calling
   `mcp__codex__codex` is fine. For reliable scripted "have Codex do X", skip the MCP hop and call
   `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "…"` directly — Codex
   still authors the work, just without the flaky nested MCP server.

4. **Recursion** — the `claude_agent` wrapper spawns `claude` with `--strict-mcp-config --mcp-config
   '{"mcpServers":{}}'` so the inner agent does NOT re-load the `codex` server (which would loop
   codex → wrapper → claude → codex). Keep that guard if you edit the wrapper.

## Teach Codex how to use the bridge (optional but recommended)

Codex auto-loads `~/.codex/AGENTS.md` every session. Adding a short delegation cheatsheet there makes
Codex reach for the right tool without being told each time. A safe, secret-free snippet to append:

```markdown
## Delegating to Claude Code
- `claude_agent` = hand off a WHOLE task (Claude plans + executes autonomously, returns final text).
- `claude_code` = call ONE atomic leaf tool (Bash/Read/Edit/Write/Grep/Glob/WebSearch).
- The `Agent` tool from claude_code is BROKEN in serve mode — never use it; use a leaf tool or claude_agent.
```

Append only this generic cheatsheet. Do **not** copy private/operational content into a published or
shared `AGENTS.md`.

## Uninstall

```bash
bash <skill-dir>/uninstall.sh
# or by hand:
claude mcp remove codex -s user
codex mcp remove claude_code
codex mcp remove claude_agent
```

The wrapper script lives inside the skill dir, so removing the registrations is enough; nothing is
left in `~/.codex/` except the (untouched) pre-existing servers.
