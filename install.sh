#!/usr/bin/env bash
# Wire Claude Code <-> desktop Codex.app as each other's MCP server (both directions)
# plus the one-shot `claude_agent` whole-task wrapper. Idempotent; preserves any
# MCP servers Codex already has.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SKILL_DIR/scripts/claude-agent-mcp.mjs"

# --- locate the three binaries -------------------------------------------------
CODEX_BIN="${CODEX_BIN:-/Applications/Codex.app/Contents/Resources/codex}"
if [[ ! -x "$CODEX_BIN" ]]; then
  echo "ERROR: Codex binary not found at $CODEX_BIN" >&2
  echo "       Install the desktop Codex.app, or set CODEX_BIN=/path/to/codex" >&2
  exit 1
fi

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
if [[ -z "$CLAUDE_BIN" ]]; then
  echo "ERROR: 'claude' (Claude Code CLI) not found on PATH. Set CLAUDE_BIN=/path/to/claude" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: 'node' not found on PATH (needed by the claude_agent wrapper)." >&2
  exit 1
fi

echo "Codex binary : $CODEX_BIN"
echo "claude binary: $CLAUDE_BIN"
echo "wrapper      : $WRAPPER"
echo

# --- A) CC -> Codex ------------------------------------------------------------
echo "[A] CC -> Codex  (server 'codex' in ~/.claude.json)"
claude mcp remove codex -s user >/dev/null 2>&1 || true
claude mcp add codex -s user -- "$CODEX_BIN" mcp-server
echo "    done."

# --- B) Codex -> CC, leaf tools ------------------------------------------------
echo "[B] Codex -> CC leaf tools  (server 'claude_code' in ~/.codex/config.toml)"
"$CODEX_BIN" mcp remove claude_code >/dev/null 2>&1 || true
"$CODEX_BIN" mcp add claude_code -- "$CLAUDE_BIN" mcp serve
echo "    done."

# --- C) Codex -> CC, whole-task wrapper ----------------------------------------
echo "[C] Codex -> CC whole-task  (server 'claude_agent' in ~/.codex/config.toml)"
"$CODEX_BIN" mcp remove claude_agent >/dev/null 2>&1 || true
# pass CLAUDE_BIN through to the wrapper's environment so it spawns the right claude
"$CODEX_BIN" mcp add claude_agent --env "CLAUDE_BIN=$CLAUDE_BIN" -- node "$WRAPPER" \
  || "$CODEX_BIN" mcp add claude_agent -- node "$WRAPPER"
echo "    done."

echo
echo "All three servers registered. Verify with:"
echo "  claude mcp list   # expect: codex ... Connected"
echo "  $CODEX_BIN mcp list   # expect: claude_code AND claude_agent"
