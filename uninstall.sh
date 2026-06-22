#!/usr/bin/env bash
# Remove the Claude Code <-> Codex mutual-MCP bridge. Leaves any other MCP
# servers (e.g. node_repl) untouched.
set -uo pipefail

CODEX_BIN="${CODEX_BIN:-/Applications/Codex.app/Contents/Resources/codex}"

echo "Removing CC -> Codex server 'codex'..."
claude mcp remove codex -s user 2>/dev/null || true

if [[ -x "$CODEX_BIN" ]]; then
  echo "Removing Codex -> CC servers 'claude_code' and 'claude_agent'..."
  "$CODEX_BIN" mcp remove claude_code 2>/dev/null || true
  "$CODEX_BIN" mcp remove claude_agent 2>/dev/null || true
else
  echo "WARN: Codex binary not found at $CODEX_BIN — remove claude_code/claude_agent manually." >&2
fi

echo "Done. The wrapper script stays inside the skill dir; nothing else to clean up."
