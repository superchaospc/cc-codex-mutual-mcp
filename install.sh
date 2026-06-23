#!/usr/bin/env bash
# Wire Claude Code <-> desktop Codex.app as each other's MCP server (both directions)
# plus the one-shot `claude_agent` whole-task wrapper. Idempotent; preserves any
# MCP servers Codex already has.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="$SKILL_DIR/scripts/claude-agent-mcp.mjs"

# --- platform note -------------------------------------------------------------
# This bridge targets the macOS desktop Codex.app (its bundled CLI). On Linux the
# `codex` CLI lives elsewhere and there is no Codex.app — set CODEX_BIN yourself.
if [[ "$(uname)" != "Darwin" ]]; then
  echo "NOTE: non-macOS detected ($(uname)). The default Codex.app path won't exist;" >&2
  echo "      set CODEX_BIN=/path/to/codex (the Codex CLI) before running this." >&2
fi

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

# --- install the wrapper to a stable location ----------------------------------
# Register the wrapper from CODEX_HOME (default ~/.codex), NOT from the skill dir,
# so the bridge keeps working even if the skill is moved, renamed, or removed.
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
WRAPPER="$CODEX_HOME/claude-agent-mcp.mjs"
mkdir -p "$CODEX_HOME"
cp "$WRAPPER_SRC" "$WRAPPER"

echo "Codex binary : $CODEX_BIN"
echo "claude binary: $CLAUDE_BIN"
echo "wrapper      : $WRAPPER (copied from skill)"
echo

# --- A) CC -> Codex ------------------------------------------------------------
echo "[A] CC -> Codex  (server 'codex' in ~/.claude.json)"
"$CLAUDE_BIN" mcp remove codex -s user >/dev/null 2>&1 || true
"$CLAUDE_BIN" mcp add codex -s user -- "$CODEX_BIN" mcp-server
echo "    done."

# --- B) Codex -> CC, leaf tools ------------------------------------------------
echo "[B] Codex -> CC leaf tools  (server 'claude_code' in ~/.codex/config.toml)"
"$CODEX_BIN" mcp remove claude_code >/dev/null 2>&1 || true
"$CODEX_BIN" mcp add claude_code -- "$CLAUDE_BIN" mcp serve
echo "    done."

# --- C) Codex -> CC, whole-task wrapper ----------------------------------------
echo "[C] Codex -> CC whole-task  (server 'claude_agent' in ~/.codex/config.toml)"
"$CODEX_BIN" mcp remove claude_agent >/dev/null 2>&1 || true
# Pass CLAUDE_BIN through to the wrapper's environment so it spawns the right claude.
# Only fall back to a no-env registration if THIS codex truly lacks `--env` — never
# swallow other failures (which would silently drop CLAUDE_BIN and break the wrapper).
if "$CODEX_BIN" mcp add --help 2>&1 | grep -q -- '--env'; then
  "$CODEX_BIN" mcp add claude_agent --env "CLAUDE_BIN=$CLAUDE_BIN" -- node "$WRAPPER"
else
  "$CODEX_BIN" mcp add claude_agent -- node "$WRAPPER"
  if [[ "$CLAUDE_BIN" != "/opt/homebrew/bin/claude" ]]; then
    echo "    WARN: this 'codex mcp add' has no --env flag, so CLAUDE_BIN was not passed." >&2
    echo "          Your claude is at '$CLAUDE_BIN' but the wrapper defaults to" >&2
    echo "          /opt/homebrew/bin/claude. Set CLAUDE_BIN in the wrapper's env or" >&2
    echo "          edit $WRAPPER, or the agent will fail to launch." >&2
  fi
fi
echo "    done."

echo
echo "All three servers registered."

# --- auto-verify ---------------------------------------------------------------
# A "registered" server is not necessarily a working one — run the token-free
# self-test so the installer reports real execution, not just registration.
# Skip with SKIP_VERIFY=1.
if [[ "${SKIP_VERIFY:-0}" == "1" ]]; then
  echo "Skipping verification (SKIP_VERIFY=1). Run it later with:"
  echo "  bash $SKILL_DIR/scripts/selftest.sh"
elif [[ -f "$SKILL_DIR/scripts/selftest.sh" ]]; then
  echo "Verifying (token-free self-test)…"
  echo
  CLAUDE_BIN="$CLAUDE_BIN" CODEX_BIN="$CODEX_BIN" bash "$SKILL_DIR/scripts/selftest.sh" || {
    echo >&2
    echo "Self-test reported problems — see FAILs above and SKILL.md's 'four gotchas'." >&2
    exit 1
  }
else
  echo "Verify with:"
  echo "  claude mcp list   # expect: codex ... Connected"
  echo "  $CODEX_BIN mcp list   # expect: claude_code AND claude_agent"
fi
