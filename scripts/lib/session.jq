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
