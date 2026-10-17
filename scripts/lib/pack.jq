# pack.jq — the NotebookLM source pack (markdown) from the briefing facts,
# written to be read aloud: prose per question, a table only for the files.
# Load with: jq -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" 'include "pack"; ...'

include "briefing";

# A command as one line: its first line, and how many lines it had.
def one_line($lines): if $lines > 1 then "`\(.)` (+\($lines - 1) lines)" else "`\(.)`" end;

# A list read aloud: "a", "a and b", "a, b, and c".
def spoken: if length <= 2 then concat(" and ") else (.[:-1] | concat(", ")) + ", and " + .[-1] end;

def times($n): if $n == 1 then "once" elif $n == 2 then "twice" else "\($n) times" end;

# A prompt quoted on one line, so a multi-line prompt cannot start a markdown block.
def quoted: split("\n") | concat(" ") | if length > 300 then .[:300] + "…" else . end | "\"\(.)\"";

def pack($f):
  ($f | work_commands) as $cmds
  # The line count of a failed command, from the timeline entry it came from.
  | def lines_of($turn; $first):
      first($f.timeline[] | select(.kind == "command" and .turn == $turn and (.text | split("\n")[0]) == $first)
            | .text | split("\n") | length) // 1;
    def files_for($action): $f | paths_with($action) | map("`\(.)`");
    def turn_story($t):
      [$f.timeline[] | select(.turn == $t and .kind != "prompt")] as $ev
      | [($ev | map(select(.kind == "file" and .action == "created") | "`\(.text)`") | unique | select(. != []) | "created " + spoken),
         ($ev | map(select(.kind == "file" and .action == "edited") | "`\(.text)`") | unique | select(. != []) | "edited " + spoken),
         ($ev | map(select(.kind == "file" and .action == "deleted") | "`\(.text)`") | unique | select(. != []) | "deleted " + spoken),
         ($ev | map(select(.kind == "command")
                    | (.text | split("\n")) as $l
                    | ($l[0] | one_line($l | length)) + (if .exit_code != 0 then " (failed, exit \(.exit_code))" else "" end))
              | select(. != []) | "ran " + spoken)]
      | if . == [] then "The agent answered without changing files or running commands."
        else "The agent " + spoken + "." end;
  ([$f.concepts[:5][] | select(.status == "shaky")] | length) as $shaky
  | [
  "# \($f.project): session briefing for \($f.date)",

  # The framing first: NotebookLM reads the opening as the brief for the episode.
  ($f | audio_prompt),

  "Project \($f.project), session \($f.session_id // "unknown") on \($f.date)"
    + (if $f.harness then ", built with \($f.harness)" + (if $f.model then " (\($f.model))" else "" end) else "" end)
    + ". \(plural($f.turns.work; "work turn"; "work turns")) in total"
    + (if $f.turns.learning > 0 then ", plus \(plural($f.turns.learning; "learning turn"; "learning turns")) (/learn, /digest, /quiz, /explain) that this pack leaves out" else "" end)
    + ". Generated \($f.generated_at).",

  "## What was built and why",

  (if $f.goal then "You asked: \($f.goal | quoted)\(if $f.goal_turn then " (turn \($f.goal_turn))" else "" end)."
   else "No request was captured for this session." end)
  + ($f | follow_ups
     | if . == [] then "" else " Later you asked " + (map(.text | quoted) | spoken) + "." end)
  + " "
  + ([(files_for("created") | select(. != []) | "created \(plural(length; "file"; "files")), " + spoken),
      (files_for("edited") | select(. != []) | "edited \(plural(length; "file"; "files")), " + spoken),
      (files_for("deleted") | select(. != []) | "deleted " + spoken)]
     | if . == [] then "The agent changed no files." else "The agent " + concat("; ") + "." end)
  + " It ran \(plural($cmds | length; "command"; "commands"))"
  + (if ($f.failures | length) > 0 then ", and \($f.failures | length) of them failed." else ", and none failed." end),

  (if $f.files == [] then empty else
    "| File | Area | What happened |\n|------|------|---------------|\n"
    + ($f.files | map("| `\(.path)` | \(.path | file_area) | \([(if .created > 0 then "created" else empty end),
                         (if .edited > 0 then "edited" + (if .edited > 1 then " \(.edited) times" else "" end) else empty end),
                         (if .deleted > 0 then "deleted" else empty end)] | concat(", ")) |") | concat("\n")) end),

  "## How the session went",

  ([$f.timeline[] | select(.kind == "prompt" and (.learning | not))] as $asks
   | ($asks[:40] | map("Turn \(.turn): you asked \(.text | quoted). \(turn_story(.turn))") | concat("\n\n"))
     + (if ($asks | length) > 40 then "\n\n\(($asks | length) - 40) more turns follow in the session page's timeline." else "" end)
   | if . == "" then "No work turns were recorded." else . end),

  "## What to understand",

  (if $f.concepts == [] then
     "No concepts from your knowledge ledger are linked to this session yet. Running /quiz, /explain, or /digest records the concepts you meet and the files they come from."
   else
     ($f.concepts[:5]) as $c
     | def names($s): [$c[] | select(.status == $s)
                       | .label + (if .files != [] then " (in " + (.files | map("`\(.)`") | spoken) + ")" else "" end)];
       (if $c[0].match == "files" then "These concepts from your knowledge ledger live in the files this session changed."
        else "These concepts from your knowledge ledger came up on \($f.date)." end)
       + (names("shaky") | if . == [] then "" else "\n\nWhat you struggled with: " + spoken + ". Your quizzes marked \(if length == 1 then "it" else "them" end) shaky." end)
       + (names("new") | if . == [] then "" else "\n\nMet this session, not yet quizzed: " + spoken + "." end)
       + (names("solid") | if . == [] then "" else "\n\nSolid: " + spoken + "." end)
   end),

  "## What broke and how it was fixed",

  (if $f.failures == [] then "Nothing failed in this session's work turns."
   else $f.failures | group_by([.command, .fixed_by]) | sort_by(.[0].turn)
     | map((map(.turn) | unique) as $turns | .[0] as $x
           | ($x.command | one_line(lines_of($x.turn; $x.command)))
             + " failed \(times(length)) with exit \($x.exit_code)"
             + " (turn\(if ($turns | length) > 1 then "s \($turns[0]) to \($turns[-1])" else " \($turns[0])" end))"
             + (if .[0].fixed_by then
                  (if .[0].fixed_by.command == .[0].command then " and passed in turn \(.[0].fixed_by.turn)."
                   else " and was fixed in turn \($x.fixed_by.turn), when " + ($x.fixed_by.command | one_line(lines_of($x.fixed_by.turn; $x.fixed_by.command))) + " succeeded." end)
                else ". It still fails: nothing later in the session ran it successfully." end))
     | concat("\n\n") end),

  "## Code excerpts",

  (if $f.diff == "" then "No git diff was available when this briefing was generated."
   else (if $f.diff | contains("```") then "~~~~" else "```" end) as $fence
     | "The changes as a diff (new files the session created are shown whole, up to 60 lines each):\n\n\($fence)diff\n\($f.diff)\n\($fence)" end),

  "## Questions to discuss",

  "- What changed in the main execution path, and why that way?\n- Which file would you inspect first if this broke in production?\n- Were the changes checked by tests or a build, and what is still unverified?"
  + (if ($f.failures | map(select(.fixed_by == null)) | length) > 0 then "\n- What does the command that still fails mean for shipping this?" else "" end)
  + (if $shaky > 0 then "\n- Which part of the concepts you struggled with does this session's code make concrete?" else "" end)
  ] | concat("\n\n") + "\n";
