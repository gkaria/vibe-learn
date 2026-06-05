// vibe-learn OpenCode plugin
// INSTALL_DIR_PLACEHOLDER is replaced with the actual install path.

import { spawnSync } from "node:child_process";

const VIBE_LEARN_DIR = "INSTALL_DIR_PLACEHOLDER";
const recentFileEvents = new Map();

function scriptPath(name) {
  return `${VIBE_LEARN_DIR}/scripts/${name}`;
}

function runScript(name, payload) {
  spawnSync(scriptPath(name), {
    input: JSON.stringify(payload),
    encoding: "utf8",
    stdio: ["pipe", "ignore", "ignore"],
  });
}

// Normalise a tool.execute.after payload into the shape observe.sh expects.
// input: { tool, sessionID, callID, args }
// output: { title, output, metadata }
function normalizeTool(input, output) {
  const rawTool = input?.tool || input?.name || "";
  const tool = String(rawTool).toLowerCase();
  const args = input?.args || input?.input || {};
  const exitCode =
    output?.metadata?.exitCode ??
    output?.metadata?.exit_code ??
    output?.exitCode ??
    0;

  if (tool === "bash" || tool === "shell") {
    return {
      tool_name: "Bash",
      tool_input: { command: args.command || args.cmd || "" },
      tool_response: { exit_code: exitCode },
    };
  }

  if (tool === "write") {
    const filePath = args.filePath || args.file_path || args.path || "";
    markFileEvent(filePath);
    return {
      tool_name: "Write",
      tool_input: { file_path: filePath },
      tool_response: {},
    };
  }

  if (tool === "edit") {
    const filePath = args.filePath || args.file_path || args.path || "";
    markFileEvent(filePath);
    return {
      tool_name: "Edit",
      tool_input: { file_path: filePath },
      tool_response: {},
    };
  }

  return null;
}

function markFileEvent(file) {
  if (!file) return;
  recentFileEvents.set(file, Date.now());
}

function recentlyLoggedFile(file) {
  const timestamp = recentFileEvents.get(file);
  if (!timestamp) return false;
  return Date.now() - timestamp < 1500;
}

// server is the standard PluginModule export name.
export const server = async (ctx) => {
  // ctx.directory is the project working directory (from PluginInput type).
  const cwd = ctx.directory || process.cwd();

  return {
    // event receives every SDK event; we filter by .type.
    // EventSessionCreated { type: "session.created", properties: { info: Session } }
    // EventFileEdited     { type: "file.edited",     properties: { file: string } }
    // EventSessionIdle    { type: "session.idle",    properties: { sessionID: string } }
    event: async ({ event }) => {
      if (event.type === "session.created") {
        runScript("bootstrap.sh", {
          cwd,
          session_id: event.properties?.info?.id || "opencode",
        });
      } else if (event.type === "file.edited") {
        const file = event.properties?.file;
        if (!file) return;
        if (recentlyLoggedFile(file)) return;
        markFileEvent(file);
        runScript("observe.sh", {
          cwd,
          tool_name: "Edit",
          tool_input: { file_path: file },
          tool_response: {},
        });
      } else if (event.type === "session.idle") {
        runScript("pause-summary.sh", {
          cwd,
          hook_event_name: "Stop",
        });
      }
    },

    // tool.execute.after fires after every tool call.
    // input: { tool: string, sessionID, callID, args }
    // output: { title, output, metadata }
    "tool.execute.after": async (input, output) => {
      const normalized = normalizeTool(input, output);
      if (!normalized) return;
      runScript("observe.sh", {
        cwd,
        ...normalized,
      });
    },
  };
};
