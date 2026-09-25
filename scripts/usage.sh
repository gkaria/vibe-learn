#!/bin/bash
# usage.sh — sourced helper: which tools and skills a session used.
#
# vl_session_usage HARNESS TRANSCRIPT ROOT SESSION_ID SINCE
#   Prints {"tools":{family:count},"skills":{name:count}} for the session, or
#   `null` when the host's record can't be read. Tools are grouped into
#   families (read, search, shell, edit, web, subagent, plan, skill,
#   mcp:<server>, other) because every host names them differently. Only
#   family, server, and skill names leave this function: never arguments.
#
# Sources, all read-only and undocumented by their hosts (pinned by fixtures
# in tests/usage.bats; a format change yields null, never an error):
#   claude-code  transcript_path: assistant tool_use blocks
#   codex        transcript_path: response_item function/custom/web-search calls,
#                plus the <skill><name> message an explicit $skill injects
#   cursor       transcript_path: assistant tool_use blocks (model-side names)
#   grok         $GROK_HOME/sessions/<@uri root>/<id>/chat_history.jsonl
#   opencode     $XDG_DATA_HOME/opencode/opencode.db `part` rows (needs sqlite3)
# SINCE (ISO-8601) drops transcript lines from before this session started,
# for hosts that resume into the same file.

# One {name, ns, path, skill} object per tool call on stdin → usage JSON.
_vl_usage_aggregate() {
  jq -n -c '
    def family($name; $ns):
      ($name // "" | ascii_downcase) as $n
      | ($ns // "" | ascii_downcase) as $s
      | if ($s | startswith("mcp__")) then "mcp:" + ($s | ltrimstr("mcp__") | sub("__.*$"; "") | sub("_+$"; ""))
        elif $s == "web" then "web"
        elif $s == "collaboration" then "subagent"
        elif ($n | startswith("mcp__")) then "mcp:" + ($n | ltrimstr("mcp__") | sub("__.*$"; ""))
        elif ($n | IN("read", "read_file", "view", "view_image", "notebookread", "readmcpresource", "fetchmcpresource")) then "read"
        elif ($n | IN("grep", "glob", "ls", "list", "list_dir", "codebase_search", "semanticsearch", "semantic_search",
                      "file_search", "grep_search", "search", "toolsearch", "tool_search", "getdynamictools", "find")) then "search"
        elif ($n | IN("bash", "shell", "exec", "exec_command", "write_stdin", "run_terminal_command", "local_shell",
                      "bashoutput", "killshell", "killbash", "awaitshell")) then "shell"
        elif ($n | IN("write", "edit", "multiedit", "strreplace", "apply_patch", "patch", "search_replace",
                      "delete", "delete_file", "notebookedit", "editnotebook")) then "edit"
        elif ($n | IN("webfetch", "websearch", "web_fetch", "web_search", "web_search_call", "fetch")) then "web"
        elif ($n | IN("task", "agent", "spawn_agent", "spawn_subagent", "wait_agent", "close_agent", "send_input")) then "subagent"
        elif ($n | IN("todowrite", "todoread", "todo_write", "update_plan", "createplan")) then "plan"
        elif $n == "skill" then "skill"
        elif ($n | test("^[a-z0-9_-]+__[a-z0-9_]")) then "mcp:" + ($n | sub("__.*$"; ""))
        else "other" end;
    def skill_from_path:
      [scan("/skills[A-Za-z0-9_-]*/(?:[^\\s\"'\''|;&]*/)?([^/\\s\"'\''|;&]+)/SKILL\\.md") | .[0]];

    reduce (inputs | objects) as $e ({tools: {}, skills: {}};
      (if $e.name then .tools[family($e.name; $e.ns)] += 1 else . end)
      | reduce ((([$e.skill] | map(strings)) + ($e.path // "" | tostring | skill_from_path)) | unique[]) as $k (.;
          .skills[$k] += 1)
    )
    | .tools |= (to_entries | sort_by(-.value, .key) | from_entries)
    | .skills |= (to_entries | sort_by(-.value, .key) | from_entries)
  ' 2>/dev/null
}

_vl_usage_extract() {
  local harness="$1" transcript="$2" root="$3" sid="$4" since="$5"
  local dir file db
  case "$harness" in
    claude-code)
      [ -f "$transcript" ] || return 1
      jq -R -c --arg since "${since:0:19}" '
        fromjson? | objects
        | select(.type == "assistant" and ((.timestamp // "")[0:19] >= $since))
        | .message.content[]? | select(.type == "tool_use")
        | {name, path: (.input.file_path // .input.path // .input.command // null),
           skill: (if .name == "Skill" then .input.skill else null end)}' "$transcript"
      ;;
    codex)
      [ -f "$transcript" ] || return 1
      jq -R -c --arg since "${since:0:19}" '
        fromjson? | objects
        | select(.type == "response_item" and ((.timestamp // "")[0:19] >= $since))
        | .payload
        | if .type == "function_call" or .type == "custom_tool_call" then
            {name, ns: .namespace, path: ((.arguments // .input // "") | tostring)}
          elif .type == "web_search_call" then {name: "web_search_call"}
          elif .type == "tool_search_call" then {name: "tool_search"}
          elif .type == "local_shell_call" then {name: "local_shell", path: (.action.command // "" | tostring)}
          elif .type == "message" and .role == "user" then
            (.content[]?.text // "" | [scan("<skill>\\s*<name>([^<]+)</name>") | .[0]] | .[] | {skill: .})
          else empty end' "$transcript"
      ;;
    cursor)
      [ -f "$transcript" ] || return 1
      jq -R -c '
        fromjson? | objects | select(.role == "assistant")
        | .message.content[]? | select(.type == "tool_use")
        | {name, ns: (if .name == "CallDynamicTool" then "mcp__" + (.input.namespace // "unknown") else null end),
           path: (.input.path // .input.command // null)}' "$transcript"
      ;;
    grok)
      [ -n "$root" ] && [ -n "$sid" ] || return 1
      dir=$(printf '%s' "$root" | jq -Rr '@uri' 2>/dev/null) || return 1
      file="${GROK_HOME:-$HOME/.grok}/sessions/$dir/$sid/chat_history.jsonl"
      [ -f "$file" ] || return 1
      jq -R -c '
        fromjson? | objects | .tool_calls[]?
        | {name, path: ((.arguments // "") | tostring)}' "$file"
      ;;
    opencode)
      command -v sqlite3 >/dev/null 2>&1 || return 1
      db="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db"
      [ -f "$db" ] || return 1
      case "$sid" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
      sqlite3 -readonly -cmd '.timeout 500' "$db" "
        SELECT json_object(
          'name', json_extract(data, '\$.tool'),
          'path', json_extract(data, '\$.state.input.filePath'),
          'skill', CASE WHEN json_extract(data, '\$.tool') = 'skill' THEN json_extract(data, '\$.state.input.name') END)
        FROM part
        WHERE session_id = '$sid' AND json_extract(data, '\$.type') = 'tool'
        ORDER BY time_created;"
      ;;
    *)
      return 1
      ;;
  esac
}

vl_session_usage() {
  local out
  out=$(_vl_usage_extract "$@" 2>/dev/null) || { printf 'null'; return 0; }
  out=$(printf '%s\n' "$out" | _vl_usage_aggregate) || { printf 'null'; return 0; }
  printf '%s' "${out:-null}"
}
