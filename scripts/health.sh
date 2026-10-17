#!/bin/bash
# health.sh — session log + meta → assistant health rows.
#
# Usage: health.sh [LOG_DIR]   (default: ./.vibe-learn)
#
# Prints one JSON line per session segment: a new segment starts wherever the
# turn's (model, effort) changes, so a session with no switch prints one line.
# Read-only; prints nothing when the log has no prompts or tool events.
# bootstrap.sh appends the output to health.jsonl before it rotates the log.
# The first segment's row also carries `usage`: tool families and skills for
# the whole session (from the host's transcript, see usage.sh) and slash
# commands typed in prompts. Learning turns (/learn, /digest, /quiz, /explain;
# see learning_event in lib/session.jq) are left out of segments and metrics,
# but usage still counts them: it records what the host ran.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=identity.sh
. "$SCRIPT_DIR/identity.sh"
# shellcheck source=usage.sh
[ -f "$SCRIPT_DIR/usage.sh" ] && . "$SCRIPT_DIR/usage.sh"

LOG_DIR="${1:-.vibe-learn}"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
META_FILE="$LOG_DIR/session-meta.json"

[ -s "$SESSION_LOG" ] || exit 0

META=""
[ -f "$META_FILE" ] && META=$(jq -c 'objects' "$META_FILE" 2>/dev/null)
[ -n "$META" ] || META='{}'

IFS="$VL_SEP" read -r HARNESS TRANSCRIPT META_VERSION META_MODEL SESSION_ID STARTED_AT <<EOF
$(printf '%s' "$META" | jq -r --arg sep "$VL_SEP" \
  '[(.harness // ""), (.transcript_path // ""), (.harness_version // ""), (.model // ""),
    (.session_id // ""), (.started_at // "")] | map(tostring) | join($sep)')
EOF

# Claude Code and Codex write their version into the transcript after
# SessionStart has already fired, so fill it in now if bootstrap couldn't.
VERSION="$META_VERSION"
if [ -z "$VERSION" ]; then
  VERSION=$(vl_harness_version "$HARNESS" "$TRANSCRIPT")
fi

HOST_MODEL=""
HOST_EFFORT=""
if [ -z "$META_MODEL" ] && [ "$HARNESS" != "grok" ]; then
  IFS="$VL_SEP" read -r HOST_MODEL HOST_EFFORT <<EOF
$(vl_host_config "$HARNESS" "$TRANSCRIPT" "" "")
EOF
fi

USAGE=null
if command -v vl_session_usage >/dev/null 2>&1; then
  ROOT=$(cd "$LOG_DIR/.." 2>/dev/null && pwd)
  USAGE=$(vl_session_usage "$HARNESS" "$TRANSCRIPT" "$ROOT" "$SESSION_ID" "$STARTED_AT")
  printf '%s' "$USAGE" | jq -e 'type == "object" or . == null' >/dev/null 2>&1 || USAGE=null
fi

jq -Rn -c -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" \
  --argjson meta "$META" \
  --argjson usage "$USAGE" \
  --arg version "$VERSION" \
  --arg host_model "$HOST_MODEL" \
  --arg host_effort "$HOST_EFFORT" '
  include "session";
  def nonempty: if . == "" then null else . end;
  def round_to($n): if . == null then null else (. * pow(10; $n) | round) / pow(10; $n) end;
  # A check is a test, lint, or build tool in command position: the start of a
  # command after &&, ||, ;, | or (, past env assignments and runners like npx.
  # A heredoc body is text, not commands, so only its first line counts.
  # sub, not gsub: jq 1.6 gsub loops on patterns that can match empty.
  # strip_prefix runs twice for nesting such as `env CI=1 npx jest`.
  def strip_prefix:
    sub("^([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)+"; "")
    | sub("^(env(\\s+(-u\\s+\\S+|-\\S+))*|time|npx|bunx|pnpm (exec|dlx)|yarn dlx|uv run|poetry run|bundle exec|python3? -m)\\s+"; "");
  def is_check:
    (if test("<<") then split("\n")[0] else . end)
    | [splits("&&|\\|\\||[;|(\n]")]
    | any(.[];
        sub("^\\s+"; "")
        | (strip_prefix | strip_prefix)
        | test("^(\\S*/)?(pytest|jest|vitest|bats|mocha|rspec|tsc|eslint|ruff|mypy)(\\s|$)|^\\S*/test(\\s|$)|^(go|bun|deno|mix|dotnet|swift|rails) test\\b|^cargo (test|check|clippy)\\b|^(npm|pnpm|yarn) (run )?(test|lint|build)\\b|^make (test|check)\\b"));

  # Learning turns (/learn, /digest, /quiz, /explain) are not session work:
  # their prompts and tool calls stay out of every metric and segment. Typed
  # commands still count them in usage.commands.
  ([inputs | fromjson? | select(type == "object")] | number_turns) as $all
  | ($all | work_events) as $events
  | ($events | map(select(.event == "user_prompt" or .event == "tool_use"))) as $work
  | if ($work | length) == 0 then empty else

  # Model and effort are resolved over every turn, learning turns included: a
  # switch recorded in the turn_end of a learning turn still applies to later work.
  ($all | map(select(.event == "turn_end"))) as $ends
  | ($ends | map(select(.model != null)) | first | .model) as $first_model
  | ($ends | map(select(.effort != null)) | first | .effort) as $first_effort
  | {
      model: ($meta.model // ($host_model | nonempty) // $first_model),
      effort: ($meta.effort // ($host_effort | nonempty) // $first_effort)
    } as $initial

  # Configuration per turn: a turn_end sets it for its turn; turns without one
  # (or with a null field) carry the previous value forward. Only work turns
  # then form segments.
  | ($events | map(._turn) | unique) as $turns
  | ($turns | map({key: tostring, value: true}) | from_entries) as $is_work
  | ($ends | map({key: (._turn | tostring), value: .}) | from_entries) as $end_by_turn
  | [foreach ($all | map(._turn) | unique)[] as $t ($initial;
      ($end_by_turn[$t | tostring] // {}) as $te
      | {model: ($te.model // .model), effort: ($te.effort // .effort)};
      {turn: $t, cfg: .}
    ) | select($is_work[.turn | tostring])] as $turn_cfg
  # Recovery distance counts work turns only: learning turns in between do not
  # make a fix look slower.
  | ($turns | to_entries | map({key: (.value | tostring), value: .key}) | from_entries) as $work_ordinal

  | (reduce $turn_cfg[] as $tc ([];
      if length > 0 and .[-1].cfg == $tc.cfg then .[-1].turns += [$tc.turn]
      else . + [{cfg: $tc.cfg, turns: [$tc.turn]}] end
    )) as $segments

  | ($work | group_by(._turn) | map({key: (.[0]._turn | tostring), value: .}) | from_entries) as $work_by_turn
  | ($segments | length) as $count
  | range(0; $count) as $i
  | $segments[$i] as $seg
  | ($seg.turns | min) as $first_turn
  | ($seg.turns | max) as $last_turn
  | [$seg.turns[] as $t | $work_by_turn[$t | tostring][]?] as $sw
  | ($sw | map(select(.event == "tool_use"))) as $tools
  | ($tools | map(select(.tool == "Bash"))) as $bash
  | ($tools | map(select(.action == "created" or .action == "edited" or .action == "deleted") | select((.file // "") != ""))) as $file_ops
  | ($file_ops | group_by(.file) | map(map(._turn) | unique | length)) as $turns_per_file
  | ($bash | map(select((.command // "") | is_check))) as $checks
  | ($checks | group_by(.command) | map(
      sort_by(._turn) as $runs
      | (reduce $runs[] as $r ({pending: null, gaps: []};
          if ($r.context.exit_code // 0) != 0 then
            (if .pending == null then .pending = $work_ordinal[$r._turn | tostring] else . end)
          elif .pending != null then
            .gaps += [$work_ordinal[$r._turn | tostring] - .pending] | .pending = null
          else . end
        )) + {last_failed: (($runs[-1].context.exit_code // 0) != 0)}
    )) as $check_keys
  | ($check_keys | map(.gaps[]) ) as $gaps
  | ($sw | map(select(.event == "user_prompt")) | length) as $prompts
  | ($bash | length) as $bash_runs
  | ($bash | map(select((.context.exit_code // 0) != 0)) | length) as $bash_failures
  | ($turns_per_file | length) as $files_touched
  | ($turns_per_file | map(select(. >= 3)) | length) as $files_reworked
  | (if $i == 0 then
      {tools: ($usage.tools // null), skills: ($usage.skills // null),
       commands: ([$all[] | select(.event == "user_prompt") | .prompt // "" | tostring
                   | capture("^\\s*(?:/|\\$)(?<c>[a-z][a-z0-9_.:-]*)(?=\\s|$)")? | .c]
                  | group_by(.) | map({key: .[0], value: length}) | sort_by(-.value, .key) | from_entries)}
    else null end) as $session_usage
  | {
      version: 1,
      session_id: ($meta.session_id // null),
      segment: {index: ($i + 1), count: $count, first_turn: $first_turn, last_turn: $last_turn},
      started_at: (if $i == 0 then ($meta.started_at // $sw[0].timestamp) else $sw[0].timestamp end // null),
      ended_at: ($sw[-1].timestamp // null),
      harness: ($meta.harness // null),
      harness_version: ($version | nonempty),
      model: $seg.cfg.model,
      effort: $seg.cfg.effort,
      git_head: ($meta.git_head // null),
      metrics: {
        prompts: $prompts,
        turns: ($seg.turns | length),
        tool_events: ($tools | length),
        events_per_prompt: (($tools | length) / ([$prompts, 1] | max) | round_to(1)),
        bash_runs: $bash_runs,
        bash_failures: $bash_failures,
        bash_fail_rate: (if $bash_runs < 3 then null else ($bash_failures / $bash_runs | round_to(2)) end),
        failed_file_ops: ($tools | map(select(.action == "failed" and .tool != "Bash")) | length),
        files_touched: $files_touched,
        files_reworked: $files_reworked,
        rework_rate: (if $files_touched < 3 then null else ($files_reworked / $files_touched | round_to(2)) end),
        check_runs: ($checks | length),
        check_recoveries: ($gaps | length),
        check_unrecovered: ($check_keys | map(select(.last_failed)) | length),
        turns_to_green: (if ($gaps | length) == 0 then null else ($gaps | add / length | round_to(1)) end)
      }
    } + (if $session_usage then {usage: $session_usage} else {} end)
  end
' < "$SESSION_LOG" 2>/dev/null
