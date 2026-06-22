#!/usr/bin/env node
// Thin MCP (stdio) bridge: exposes ONE tool, `claude_agent`, that runs a full
// headless Claude Code agent (`claude -p`) and returns its final text.
//
// Why this exists: `claude mcp serve` exposes only atomic leaf tools (Bash/Read/
// Edit/...) and its `Agent` tool is broken in serve mode. This wrapper gives
// Codex a single one-shot "delegate a whole task to a Claude agent" entry point,
// mirroring how Codex's own `codex` MCP tool works.
//
// Registered in Codex via:
//   codex mcp add claude_agent -- node /absolute/path/to/claude-agent-mcp.mjs
//
// Config: set CLAUDE_BIN if `claude` is not at /opt/homebrew/bin/claude, and
// CLAUDE_AGENT_TIMEOUT_MS to change the 10-minute kill timeout.
//
// Recursion guard: the spawned claude runs with --strict-mcp-config + an empty
// --mcp-config so it does NOT re-load the `codex` MCP server (no infinite loop).

import { spawn } from "node:child_process";
import readline from "node:readline";

const CLAUDE_BIN = process.env.CLAUDE_BIN || "/opt/homebrew/bin/claude";
const TIMEOUT_MS = Number(process.env.CLAUDE_AGENT_TIMEOUT_MS || 600000);
const DEFAULT_ALLOWED = "Read,Edit,Write,Bash,Grep,Glob,WebSearch,WebFetch";

const TOOL = {
  name: "claude_agent",
  description:
    "Delegate a complete task to a full Claude Code agent (headless `claude -p`). " +
    "Claude plans and executes autonomously using its own tools (read/edit/write files, run bash, search) " +
    "and returns its final answer. Use this for whole tasks ('fix the bug in auth.py', 'add tests for X'), " +
    "not for single shell commands. Runs with permissions bypassed so it can act without prompting.",
  inputSchema: {
    type: "object",
    properties: {
      prompt: {
        type: "string",
        description: "The full task / instruction for the Claude agent to carry out.",
      },
      cwd: {
        type: "string",
        description: "Working directory for the agent. Defaults to the bridge's cwd.",
      },
      allowedTools: {
        type: "string",
        description:
          "Comma-separated tool allowlist for the agent. Defaults to: " + DEFAULT_ALLOWED,
      },
      model: {
        type: "string",
        description: "Optional Claude model id (e.g. claude-opus-4-8, claude-sonnet-4-6).",
      },
    },
    required: ["prompt"],
  },
};

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}
function result(id, res) {
  send({ jsonrpc: "2.0", id, result: res });
}
function error(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

function runClaude(args) {
  return new Promise((resolve) => {
    const prompt = String(args.prompt ?? "");
    if (!prompt.trim()) {
      return resolve({ isError: true, text: "Error: `prompt` is required and was empty." });
    }
    const cliArgs = [
      "-p",
      prompt,
      "--output-format",
      "text",
      "--permission-mode",
      "bypassPermissions",
      "--strict-mcp-config",
      "--mcp-config",
      '{"mcpServers":{}}',
      "--allowedTools",
      String(args.allowedTools || DEFAULT_ALLOWED),
    ];
    if (args.model) cliArgs.push("--model", String(args.model));

    const child = spawn(CLAUDE_BIN, cliArgs, {
      cwd: args.cwd && String(args.cwd) ? String(args.cwd) : process.cwd(),
      env: { ...process.env, PATH: `/opt/homebrew/bin:${process.env.PATH || ""}` },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let out = "";
    let err = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
    }, TIMEOUT_MS);

    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", (e) => {
      clearTimeout(timer);
      resolve({ isError: true, text: `Failed to launch claude (${CLAUDE_BIN}): ${e.message}` });
    });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (signal === "SIGKILL") {
        return resolve({
          isError: true,
          text: `claude agent timed out after ${TIMEOUT_MS}ms and was killed.\n` +
            (out ? `Partial output:\n${out}` : ""),
        });
      }
      const text = out.trim() || err.trim() || `(claude exited ${code} with no output)`;
      resolve({ isError: code !== 0 && !out.trim(), text });
    });
  });
}

async function handle(msg) {
  const { id, method, params } = msg;
  // Notifications (no id) — nothing to reply.
  if (id === undefined || id === null) return;

  switch (method) {
    case "initialize":
      return result(id, {
        protocolVersion: params?.protocolVersion || "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "claude-agent-bridge", version: "1.0.0" },
      });
    case "ping":
      return result(id, {});
    case "tools/list":
      return result(id, { tools: [TOOL] });
    case "tools/call": {
      if (params?.name !== TOOL.name) {
        return error(id, -32602, `Unknown tool: ${params?.name}`);
      }
      const r = await runClaude(params?.arguments || {});
      return result(id, { content: [{ type: "text", text: r.text }], isError: !!r.isError });
    }
    default:
      return error(id, -32601, `Method not found: ${method}`);
  }
}

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  const s = line.trim();
  if (!s) return;
  let msg;
  try {
    msg = JSON.parse(s);
  } catch {
    return; // ignore non-JSON lines
  }
  Promise.resolve(handle(msg)).catch((e) => {
    if (msg && msg.id != null) error(msg.id, -32603, `Internal error: ${e.message}`);
  });
});
