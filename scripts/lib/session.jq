# session.jq — shared jq definitions over .vibe-learn/session-log.jsonl.
# Load with: jq -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" 'include "session"; ...'
# (the second path covers installs that copy scripts into one flat directory).

# A prompt that invokes a vibe-learn learning command on any host: Claude Code
# and plugin slash commands, Codex prompt files (typed, or expanded: Codex sends
# the file body, which starts with a vibe-learn marker comment) and skill
# phrasing, Copilot's "Use /learn", Grok and Cursor /vibe-learn. The command
# must end at whitespace or the end of the prompt, so "/learn/route.ts is
# broken" is work, as are "learn ...", "use digest auth ...", "vibe-learn has a
# bug ..." and "read .codex/prompts/learn.md and fix it".
def learning_prompt:
  # One literal pattern on the lowercased prompt: jq compiles a regex on every
  # call, and the "i" flag makes this one several times slower.
  (. // "" | tostring | ascii_downcase)
  | test("^\\s*(/(vibe-learn:)?(learn|digest|quiz|explain)|/prompts:(learn|digest|quiz|explain)|[/$]vibe-learn|use [/$]?vibe-learn\\s+to|use /(learn|digest|quiz|explain))(\\s|$)|^\\s*read (~/)?\\.codex/prompts/(learn|digest|quiz|explain)\\.md\\s+and\\s+follow\\b|^\\s*<!-- vibe-learn:(learn|digest|quiz|explain) -->");

# A user_prompt event that starts a learning turn. capture-prompt.sh writes
# kind at capture time (it survives capture_prompts: false); logs written
# before that are classified from the prompt text.
def learning_event: .event == "user_prompt" and (.kind == "learning" or (.prompt | learning_prompt));

# Log events in order (an array) → the same events with `_turn`, numbered by
# counting prompts. Stored `turn` fields come from session-meta.json, which
# stops counting if it is emptied. Events before the first prompt are turn 0,
# which is never a learning turn.
def number_turns:
  [foreach .[] as $e (0;
     if $e.event == "user_prompt" then . + 1 else . end;
     $e + {_turn: .})];

# A command that only runs vibe-learn's own helpers (knowledge.sh, briefing.sh).
def own_helper:
  (. // "" | tostring)
  | test("(^|[/\\s])(knowledge|briefing)\\.sh(\\s|$)|^\\s*vibe-learn(-knowledge)?(\\s|$)");

# Numbered events → {"<turn>": true} for every learning turn: a turn whose
# prompt invokes a learning command, and each turn after one that does nothing
# but answer (no tool calls, or only vibe-learn's own helpers), such as the
# answers in a multi-turn /quiz. The first turn that edits or runs anything
# else is work again.
def learning_turns:
  reduce (group_by(._turn)[]) as $g ({prev: false, out: {}};
    ($g | map(select(.event == "user_prompt")) | first) as $p
    | ($p != null
       and (($p | learning_event)
            or (.prev and ($g | all(.event != "tool_use" or (.tool == "Bash" and (.command | own_helper))))))) as $l
    | .prev = $l
    | if $l then .out[$g[0]._turn | tostring] = true else . end)
  | .out;

# Numbered events → the events outside learning turns: the session's work.
def work_events($learning): map(select($learning[._turn | tostring] | not));
def work_events: learning_turns as $l | work_events($l);

# A typed slash or $ command (/compact, $skill), not a request in words.
def typed_command: test("^\\s*[/$][a-z][a-z0-9_.:-]*(\\s|$)");

# A path relative to the project root; paths outside it stay as they are.
def relative_to($root):
  if $root != "" and startswith($root + "/") then .[($root | length) + 1:]
  else ltrimstr("./") end;

# The program a command runs: its first word after VAR=value prefixes.
def program: sub("^\\s*([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)*"; "") | split(" ")[0] // "";

# Log events (an array, in order) → the session facts that the pause summary
# and the briefing read. $meta is session-meta.json (or {}); $root is the
# project directory, for relative paths. Learning turns are left out of
# goal, files, commands, and failures.
def session_facts($meta; $root):
  number_turns as $all
  | ($all | learning_turns) as $learning
  | ($all | work_events($learning)) as $work
  | [$all[] | select(.event == "user_prompt")] as $prompts
  | [$work[] | select(.event == "user_prompt" and ((.prompt // "") | tostring) != "")] as $asks
  | ($asks | map(select((.prompt | typed_command | not)
                        and (.prompt | [splits("\\s+")] | map(select(. != "")) | length) >= 6))
     | first) as $first_substantial
  | ($asks | map(select(.prompt | typed_command | not)) | .[:3] | max_by(.prompt | length)) as $longest_early
  | ($first_substantial // $longest_early) as $goal
  | [$work[] | select(.event == "tool_use" and .tool == "Bash")
     | ((.command // "") | tostring) as $c
     | {turn: ._turn, command: $c, first_line: ($c | split("\n")[0] // ""),
        lines: ($c | split("\n") | length), exit_code: (.context.exit_code // 0)}] as $commands
  # One pass from the end: each failure pairs with the next exit-0 run of the
  # same command, else of the same program; with neither it is still open.
  | (reduce ($commands | reverse[]) as $c ({cmd: {}, prog: {}, out: []};
      ($c.first_line | program) as $p
      | if $c.exit_code != 0 then
          (.cmd[$c.command] // .prog[$p]) as $fix
          | .out += [{turn: $c.turn, command: $c.first_line, exit_code: $c.exit_code,
                      fixed_by: (if $fix then {turn: $fix.turn, command: $fix.first_line} else null end)}]
        else .cmd[$c.command] = $c | .prog[$p] = $c end)
     | .out | reverse) as $failures
  | [$work[] | select(.event == "tool_use" and (.action == "created" or .action == "edited" or .action == "deleted")
                     and ((.file // "") != ""))
     | {path: (.file | relative_to($root)), action, turn: ._turn}] as $file_ops
  # group_by sorts by path and keeps log order inside a group, so .[0].i is
  # where each file first appears.
  | ([$file_ops | to_entries[] | .value + {i: .key}] | group_by(.path) | sort_by(.[0].i)) as $by_file
  | ($work | map(._turn) | max // null) as $last_work
  | {
      session_id: ($meta.session_id // null),
      started_at: ($meta.started_at // ($all[0].timestamp // null)),
      harness: ($meta.harness // null),
      model: ($meta.model // null),
      goal: ($goal.prompt // null),
      goal_turn: ($goal._turn // null),
      turns: {
        work: ($prompts | map(select($learning[._turn | tostring] | not)) | length),
        learning: ($prompts | map(select($learning[._turn | tostring])) | length),
        last: ($prompts | last | ._turn // null),
        last_is_learning: (($prompts | last | ._turn // 0 | tostring) as $t | $learning[$t] // false)
      },
      files: [$by_file[] as $ops
              | {path: $ops[0].path,
                 created: ($ops | map(select(.action == "created")) | length),
                 edited: ($ops | map(select(.action == "edited")) | length),
                 deleted: ($ops | map(select(.action == "deleted")) | length),
                 turns: ($ops | map(.turn) | unique)}],
      commands: ($commands | map(del(.command))),
      failures: $failures,
      last_turn: {
        turn: $last_work,
        prompt: (first($work[] | select(.event == "user_prompt" and ._turn == $last_work) | .prompt // "") // null),
        files: [$file_ops[] | select(.turn == $last_work) | {path, action}],
        commands: [$commands[] | select(.turn == $last_work) | {first_line, exit_code}]
      }
    };
