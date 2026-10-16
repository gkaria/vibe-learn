# session.jq — shared jq definitions over .vibe-learn/session-log.jsonl.
# Load with: jq -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" 'include "session"; ...'
# (the second path covers installs that copy scripts into one flat directory).

# A prompt that invokes a vibe-learn learning command on any host: Claude Code
# and plugin slash commands, Codex prompt files and skill phrasing, Copilot's
# "Use /learn", Grok and Cursor /vibe-learn. A prompt that merely starts with
# "learn ..." or "use digest auth ..." is work, not a learning turn.
def learning_prompt:
  (. // "" | tostring) as $p
  | ["^/(vibe-learn:)?(learn|digest|quiz|explain)(?![\\w-])",
     "^/prompts:(learn|digest|quiz|explain)(?![\\w-])",
     "^[/$]?vibe-learn(?![\\w-])",
     "^use (/?vibe-learn|/(learn|digest|quiz|explain))(?![\\w-])",
     "^read \\.codex/prompts/(learn|digest|quiz|explain)\\.md"]
  | any(.[]; . as $re | $p | test("^\\s*" + ($re | ltrimstr("^")); "i"));

# A user_prompt event that starts a learning turn. capture-prompt.sh writes
# kind at capture time (it survives capture_prompts: false); logs written
# before that are classified from the prompt text.
def learning_event: .event == "user_prompt" and (.kind == "learning" or (.prompt | learning_prompt));

# Log events in order (an array) → the same events with `_turn`, numbered by
# counting prompts. Stored `turn` fields come from session-meta.json, which
# stops counting if it is emptied. Events before the first prompt are turn 1.
def number_turns:
  [foreach .[] as $e (0;
     if $e.event == "user_prompt" then . + 1 else . end;
     $e + {_turn: ([., 1] | max)})];

# Numbered events → {"<turn>": true} for every learning turn.
def learning_turns:
  map(select(learning_event) | {key: (._turn | tostring), value: true}) | from_entries;

# Numbered events → the events outside learning turns: the session's work.
def work_events:
  learning_turns as $l | map(select($l[._turn | tostring] | not));
