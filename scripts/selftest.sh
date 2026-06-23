#!/usr/bin/env bash
# Self-test for the Claude Code <-> Codex mutual-MCP bridge.
#
# Proves the pieces actually EXECUTE, not just that they are "registered"
# (a registered MCP server is not necessarily a working one). Most checks need
# NO API tokens:
#   1. claude_agent wrapper protocol  — driven against a STUB claude (free,
#      deterministic); also asserts the recursion guard is still wired.
#   2. claude_code leaf Bash tool     — `claude mcp serve` runs tools directly,
#      no model inference, so this is free too.
#   3. registrations present          — `claude mcp list` / `codex mcp list`.
#   4. (--live) whole-task wrapper    — spawns a REAL headless claude; uses tokens.
#
# Usage:
#   bash scripts/selftest.sh            # free checks (1-3)
#   bash scripts/selftest.sh --live     # also run the token-spending live check (4)
#
# Honors CLAUDE_BIN / CODEX_BIN overrides, same as install.sh.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$SKILL_DIR/scripts/claude-agent-mcp.mjs"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
CODEX_BIN="${CODEX_BIN:-/Applications/Codex.app/Contents/Resources/codex}"
LIVE=0
[[ "${1:-}" == "--live" ]] && LIVE=1

pass=0; fail=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
skip(){ printf '  \033[33mSKIP\033[0m %s\n' "$1"; }

# Run a command with a hard timeout, no `sleep`/`timeout` dependency (macOS-safe).
to(){ perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$@"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "== 1. claude_agent wrapper protocol (stub claude, no tokens) =="
if ! command -v node >/dev/null 2>&1; then
  no "node not on PATH (wrapper cannot run)"
elif [[ ! -f "$WRAPPER" ]]; then
  no "wrapper not found at $WRAPPER"
else
  STUB="$TMP/stub-claude.sh"
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
# Records the argv it was spawned with, then prints a sentinel as "agent output".
printf '%s\n' "$@" > "$STUB_ARGV_OUT"
echo "STUB_CLAUDE_RAN"
EOF
  chmod +x "$STUB"
  OUT="$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"claude_agent","arguments":{"prompt":"hi"}}}' \
    | CLAUDE_BIN="$STUB" STUB_ARGV_OUT="$TMP/argv.txt" to 30 node "$WRAPPER" 2>/dev/null)"
  echo "$OUT" | grep -q '"name":"claude_agent"' && ok "tools/list advertises claude_agent" || no "tools/list missing claude_agent"
  echo "$OUT" | grep -q 'STUB_CLAUDE_RAN'        && ok "tools/call spawned claude and returned its output" || no "tools/call did not return agent output"
  if [[ -f "$TMP/argv.txt" ]]; then
    grep -q -- '--strict-mcp-config' "$TMP/argv.txt" \
      && grep -q '"mcpServers":{}' "$TMP/argv.txt" \
      && ok "recursion guard present (--strict-mcp-config + empty --mcp-config)" \
      || no "recursion guard MISSING — inner agent could re-load codex and loop"
  else
    no "stub claude was never invoked"
  fi
fi

echo "== 2. claude_code leaf Bash via 'claude mcp serve' (no model tokens) =="
if [[ -z "$CLAUDE_BIN" ]]; then
  no "claude not found (set CLAUDE_BIN)"
else
  M="$TMP/leaf.txt"
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"selftest","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"Bash\",\"arguments\":{\"command\":\"echo leaf-ok > '$M'\"}}}" \
    | to 60 "$CLAUDE_BIN" mcp serve >/dev/null 2>&1
  grep -q 'leaf-ok' "$M" 2>/dev/null && ok "claude mcp serve executed the Bash leaf tool" || no "Bash leaf tool did not run (file not written)"
fi

echo "== 3. registrations present =="
if [[ -n "$CLAUDE_BIN" ]]; then
  "$CLAUDE_BIN" mcp list 2>/dev/null | grep -q '^codex' && ok "CC knows server 'codex' (CC -> Codex)" || no "server 'codex' not registered in Claude Code"
else
  skip "claude not found; cannot check CC -> Codex registration"
fi
if [[ -x "$CODEX_BIN" ]]; then
  CL="$("$CODEX_BIN" mcp list 2>/dev/null)"
  echo "$CL" | grep -q 'claude_code'  && ok "Codex knows server 'claude_code' (leaf tools)"  || no "server 'claude_code' not registered in Codex"
  echo "$CL" | grep -q 'claude_agent' && ok "Codex knows server 'claude_agent' (whole task)" || no "server 'claude_agent' not registered in Codex"
else
  skip "Codex binary not at $CODEX_BIN; cannot check Codex -> CC registrations"
fi

echo "== 4. live whole-task wrapper (real claude; uses tokens) =="
if [[ "$LIVE" != "1" ]]; then
  skip "pass --live to run (spends API tokens)"
elif [[ -z "$CLAUDE_BIN" ]]; then
  no "claude not found (set CLAUDE_BIN)"
else
  M="$TMP/live.txt"
  R="$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"claude_agent\",\"arguments\":{\"prompt\":\"Use your Write tool to put the exact text live-ok into the file $M, then reply with just DONE.\",\"allowedTools\":\"Write,Read\"}}}" \
    | CLAUDE_BIN="$CLAUDE_BIN" to 300 node "$WRAPPER" 2>/dev/null)"
  grep -q 'live-ok' "$M" 2>/dev/null && ok "real claude agent executed end-to-end and wrote the file" || no "live agent did not write the marker (output: $(echo "$R" | tail -c 200))"
fi

echo
echo "----------------------------------------"
printf 'Result: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] && { echo "Bridge self-test OK."; exit 0; } || { echo "Bridge has problems — see FAILs above (and SKILL.md 'four gotchas')."; exit 1; }
