# briefing.jq — fills the briefing page templates (lib/briefing-*.html).
# Load with: jq -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" 'include "briefing"; ...'
# (the second path covers installs that copy scripts into one flat directory).
# Every value from the log, the ledger, or the project is untrusted text: it
# goes through @html, or through script_json inside a <script>.

include "session";

# concat($sep) without jq's join, which copies the whole string on every step
# (30 s for a 40,000-row timeline; this takes milliseconds).
def concat($sep): .[:1] + (.[1:] | map($sep + .)) | add // "";

# The template (the input string) with each {{name}} replaced by $v[name]. One
# pass, so a value is never searched for placeholders; a name with no value is
# an error, since the templates and this file ship together.
def fill($v):
  split("{{")
  | .[0] + (.[1:] | map(index("}}") as $i | .[:$i] as $k
      | if $i != null and ($v | has($k)) then ($v[$k] | tostring) + .[$i + 2:]
        else error("briefing template: no value for {{\($k)}}") end)
    | concat(""));

# JSON that is safe inside a <script>: "<" only occurs inside JSON strings,
# where < means the same, so no </script> or <!-- survives.
def script_json: tojson | split("<") | concat("\\u003c");

# --- Facts --------------------------------------------------------------------

# Log events (an array, in order) → the briefing's facts: session_facts (goal,
# files, commands, failures, all without learning turns) plus the whole
# timeline, the ledger, the git diff, and this session's pause summary. $ctx
# carries project, date, slug, now, root, ledger (or null), diff, and
# summary. The shape is public (vibe-learn briefing --json, docs/briefing.md):
# renaming or removing a field needs schema_version 2.
def briefing_facts($meta; $ctx):
  number_turns as $all
  | ($all | learning_turns) as $l
  | {schema_version: 1, project: $ctx.project, date: $ctx.date, slug: ($ctx.slug // null), generated_at: $ctx.now}
  + session_facts($meta; $ctx.root)
  + {
      timeline: [$all[] | ($l[._turn | tostring] // false) as $learning
        | if .event == "user_prompt" then
            {turn: ._turn, kind: "prompt", learning: $learning, text: (.prompt // "" | tostring)}
          elif .event == "tool_use" and .tool == "Bash" then
            {turn: ._turn, kind: "command", learning: $learning, text: (.command // "" | tostring),
             exit_code: (.context.exit_code // 0)}
          elif .event == "tool_use" then
            {turn: ._turn, kind: "file", learning: $learning,
             text: (.file // "file" | tostring | relative_to($ctx.root)), action: (.action // "changed" | tostring)}
          else empty end],
      knowledge: (if $ctx.ledger == null then null else
        [$ctx.ledger.concepts[] | objects
         | {name: (.name // null), label: (.label // .name // "concept" | tostring),
            status: (.status // "new" | tostring), sessions: (.sessions // 0),
            first_seen: (.first_seen // null), last_seen: (.last_seen // null),
            last_quizzed: (.last_quizzed // null),
            files: (if (.files | type) == "array" then [.files[] | strings] else [] end)}] as $c
        | {total: ($c | length), shaky: ([$c[] | select(.status == "shaky")] | length), concepts: $c} end),
      diff: $ctx.diff,
      pause_summary: (if $ctx.summary == "" then null else $ctx.summary end)
    }
  # What to understand: ledger concepts whose files this session changed (with
  # those files), else concepts seen, touched, or quizzed on the session date.
  | (.files | map(.path)) as $paths
  | .date as $date
  | .concepts = (if .knowledge == null then [] else
      [.knowledge.concepts[] | . + {files: [.files[] | select(. as $p | any($paths[]; . == $p))]}] as $all
      | ([$all[] | select(.files != []) | . + {match: "files"}]
         | if . != [] then . else
             [$all[] | select(.first_seen == $date or .last_seen == $date or .last_quizzed == $date) | . + {match: "date"}]
           end)
      | sort_by({shaky: 0, new: 1}[.status] // 2, .label) end);

# Files the session's work changed, each counted once.
def file_total: .files | length;

# --- Index --------------------------------------------------------------------

# A session's index card numbers, from its facts.
def card_summary: {slug, date, goal, files: (.files | length), commands: (.commands | length), failures: (.failures | length)};

def session_card:
  "
        <article class=\"card\" data-failures=\"\(.failures)\" data-has-pack=\"true\">
          <div class=\"card-meta\">
            <span class=\"tag\">\(.date | @html)</span>
            <span class=\"tag\">\(.files) files</span>
            <span class=\"tag\">\(.commands) commands</span>
            \(if .failures > 0 then "<span class=\"tag danger\">\(.failures) failed</span>" else "" end)
          </div>
          <h3 class=\"card-title\">\(.slug | @html)</h3>
          <p class=\"card-goal\">\(.goal // "No prompt captured for this session." | @html)</p>
          <div class=\"actions\">
            <a class=\"button primary\" href=\"sessions/\(.slug | @uri).html\">Open briefing</a>
            <a class=\"button\" href=\"exports/\(.slug | @uri)-notebooklm-pack.md\" download>Audio pack</a>
          </div>
        </article>";

# The index (template as input): this session's card first, then $others (page
# names, newest first), with numbers from $stored (card_summary of each
# sessions/<slug>.json) where a page has one. $health_flags is null without
# health history.
def index_page($f; $others; $stored; $health_flags):
  ($f.failures | length) as $fails
  | (reduce $stored[] as $s ({}; .[$s.slug // ""] = $s)) as $by_slug
  | fill({
      project: ($f.project | @html),
      date: ($f.date | @html),
      files: ($f | file_total),
      commands: ($f.commands | length),
      failures: $fails,
      failure_class: (if $fails > 0 then "danger" else "ok" end),
      health_row: (if $health_flags == null then "" else "
        <div class=\"stat-row\"><span class=\"stat-label\"><a href=\"health.html\">Assistant health</a></span><span class=\"stat-value \(if $health_flags > 0 then "danger" else "ok" end)\">\($health_flags) flagged</span></div>" end),
      cards: (($f | card_summary | session_card)
        + ($others | map(. as $slug | $by_slug[$slug] // null
            | if . != null then session_card else "
        <article class=\"card\" data-failures=\"unknown\" data-has-pack=\"unknown\">
          <div class=\"card-meta\">
            <span class=\"tag\">previously generated</span>
          </div>
          <h3 class=\"card-title\">\($slug | @html)</h3>
          <p class=\"card-goal\">Previously generated session briefing.</p>
          <div class=\"actions\">
            <a class=\"button primary\" href=\"sessions/\($slug | @uri).html\">Open briefing</a>
          </div>
        </article>" end) | concat("")))
    });

# --- Session page -------------------------------------------------------------

# The Assistant health card: health-report.sh --views as input.
def mkeys: ["bash_fail_rate", "rework_rate", "events_per_prompt", "turns_to_green"];
def is_rate($k): $k == "bash_fail_rate" or $k == "rework_rate";
def one_decimal: (. * 10 | round) / 10 | tostring | if test("\\.") then . else . + ".0" end;
def fmt($k; $v): if $v == null then "-" elif is_rate($k) then "\($v * 100 | round)%" else ($v | one_decimal) end;
def fmt_delta($k; $d): (if $d >= 0 then "+" else "" end)
  + (if is_rate($k) then "\($d * 100 | round) pts" else ($d | one_decimal) end);
def day_label: (.[5:7] | tonumber) as $m | (.[8:10] | tonumber) as $d
  | "\(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][$m - 1]) \($d)";
def tile_name($k): {bash_fail_rate: "Bash failures", rework_rate: "Rework",
                    events_per_prompt: "Events / prompt", turns_to_green: "Turns to green"}[$k];
def detail($k; $m):
  if $k == "bash_fail_rate" then "\($m.bash_failures // 0) of \($m.bash_runs // 0) commands"
  elif $k == "rework_rate" then "\($m.files_reworked // 0) of \($m.files_touched // 0) files"
  elif $k == "events_per_prompt" then "\($m.tool_events // 0) events, \($m.prompts // 0) prompts"
  elif ($m.check_runs // 0) == 0 then "no checks run"
  else "\($m.check_recoveries // 0) failing check(s) fixed" end;

def health_card:
  .settings as $s
  | .views["harness|14"] as $v
  | ($v.current | last) as $c
  | ($v.series | map(select(.key == ($c.series // ""))) | first) as $x
  | (($x.baseline.sessions // 0) >= $s.min_sessions) as $has_base
  | ($x.flags // []) as $flags
  | (if $c == null then "" else
      [mkeys[] as $k
       | ($flags | map(select(.metric == $k)) | first) as $f
       | $c.metrics[$k] as $cv | $x.baseline.means[$k] as $usual
       | ($has_base and $cv != null and $usual != null
          and ($cv - $usual) >= (if is_rate($k) then $s.rate_threshold_pts / 100 else $s.count_threshold end)) as $high
       | "<div class=\"brief-card\"><h3>\(tile_name($k))</h3>"
         + "<div class=\"bvalue\(if $high then " danger" else "" end)\">\(fmt($k; $cv))"
         + (if $f then "<span class=\"delta bad\" title=\"average since \($x.marker.at | day_label) vs before\">\(fmt_delta($k; $f.delta))</span>" else "" end)
         + "</div><div class=\"bdetail\">\(detail($k; $c.metrics) | @html)"
         + (if $has_base then "<br>usual \(fmt($k; $usual))" else "" end)
         + "</div></div>"]
      | "<div class=\"brief-grid\">" + concat("") + "</div>" end) as $tiles
  | (if $c == null then "<span class=\"muted\">No tool activity in this session yet.</span>"
     elif ($has_base | not) then "<span class=\"muted\">Building your baseline: \($x.baseline.sessions // 0) of \($s.min_sessions) earlier sessions on \($c.series | @html). Comparisons start after \($s.min_sessions).</span>"
     elif ($flags | length) > 0 then "<span><strong>\($flags | length) of \(mkeys | length)</strong> signals rose on average after \($x.marker.change | @html) (\($x.marker.at | day_label)); the chips show by how much.</span>"
     else "<span>Within your usual range on all \(mkeys | length) signals for \($c.series | @html).</span>" end) as $footer
  | (if $c != null and ($c.eligible | not) then "<span class=\"muted\">Under \($s.min_events) tool events so far, so this session will not count yet.</span> " else "" end) as $short
  | ($c.usage // null) as $u
  | (def names($m; $prefix): $m | to_entries | map($prefix + .key + (if .value > 1 then " ×\(.value)" else "" end)) | concat(", ");
     if $u == null then "" else
       ([(if $u.tools then "Tools: " + ($u.tools | to_entries | .[:8] | map("\(.key) \(.value)") | concat(" · ") | if . == "" then "none" else . end) else empty end),
         (if ($u.skills // {}) != {} then "Skills: " + names($u.skills; "") else empty end),
         (if ($u.commands // {}) != {} then "Commands: " + names($u.commands; "/") else empty end)]
        | if length == 0 then "" else "<p class=\"usage\">" + (map(@html) | concat(" &nbsp;·&nbsp; ")) + "</p>" end) end) as $usage_line
  | (if $c == null then "" else "\($c.model // "unknown model") via \([$c.harness, $c.harness_version] | map(select(. != null)) | concat(" "))" end) as $who
  | "

        <section id=\"health\">
          <div class=\"health-head\"><h2>Assistant health</h2><span class=\"who\">\($who | @html)</span></div>
          \($tiles)
          \($usage_line)
          <div class=\"card-footer\"><span>\($short)\($footer)</span><a href=\"../health.html\">See the trend →</a></div>
        </section>";

def file_area:
  if test("test|\\.bats$|spec") then "tests"
  elif test("^adapters/") then "adapter"
  elif test("^scripts/") then "script"
  elif test("auth|login|password|token|secret|oauth|permission|cred") then "auth"
  elif test("db|database|migration|schema|model\\.py$|model\\.ts$") then "database"
  elif test("^config/|\\.json$|\\.toml$|\\.yaml$|\\.yml$") then "config"
  elif test("^(README|CLAUDE|CHANGELOG)\\.md$|^docs/|^specs/|\\.md$") then "docs"
  else "source" end;

# The session's own commands (learning turns left out), in order.
def work_commands: [.timeline[] | select(.kind == "command" and (.learning | not))];

# Paths with at least one $action ("created", "edited", "deleted"), sorted.
def paths_with($action): [.files[] | select(.[$action] > 0) | .path] | sort;

# Up to 10 ledger concepts, the ones that need attention first.
def knowledge_rows:
  .knowledge.concepts | sort_by((if .status == "solid" then 1 else 0 end), (.last_seen // "")) | .[:10];

def diff_html:
  if . == "" then "<span class=\"dc\">No git diff excerpt was available when the session briefing was generated.</span>"
  else split("\n") | map(
      (if test("^\\+\\+\\+ |^--- |^diff --git|^index [0-9a-f]") then "dh"
       elif startswith("@@") then "dk" elif startswith("+") then "da" elif startswith("-") then "dd"
       else "dc" end) as $c
      | "<span class=\"\($c)\">\(@html)</span>") | concat("\n") end;

def study_queue:
  . as $f
  | [work_commands[].text] as $cmds
  | [paths_with("created")[], paths_with("edited")[]] as $paths
  | def any_cmd(re): any($cmds[]; test(re; "i"));
    def any_path(re): any($paths[]; test(re; "i"));
    def item($text; $priority): "<label class=\"study-item\(if $priority then " priority" else "" end)\"><input type=\"checkbox\"><span>\($text)</span></label>";
    ([if $f.knowledge then
        $f.knowledge.concepts[] | select(.status == "shaky" or (.status == "new" and .sessions >= 2))
      else empty end]
     | sort_by((if .status == "shaky" then 0 else 1 end), (.last_quizzed // "")) | .[:5]
     | map(item("&ldquo;\(.label | @html)&rdquo; is marked \(.status | @html) (\(if .last_quizzed then "last quizzed \(.last_quizzed)" else "never quizzed" end | @html)) &mdash; review it before extending this code."; .status == "shaky")))
    + [item("Read through each changed file and explain its purpose in your own words."; false)]
    + (if any_cmd("\\b(npm|pip|pip3|brew|gem|cargo|yarn|pnpm)\\b.*\\binstall\\b") then [item("New dependencies were installed — understand what each adds and why it was needed."; true)] else [] end)
    + (if ($f.failures | length) > 0 then [item("\($f.failures | length) command(s) failed during this session — inspect each failure and confirm the issue was resolved."; true)] else [] end)
    + (if any_path("(auth|login|password|token|secret|jwt|oauth|permission|cred)") then [item("Auth or security-related files were touched — trace the access control flow end to end."; false)] else [] end)
    + (if any_path("(db|database|migration|schema|model\\.py|model\\.ts|orm)") then [item("Database or schema files changed — confirm the data model is correct and migrations apply cleanly."; false)] else [] end)
    + (if any_path("\\.(json|toml|yaml|yml)$|^config/") then [item("Configuration files were updated — verify environment-specific settings are correct."; false)] else [] end)
    + (if any_path("^adapters/|hooks\\.(json|toml)|hooks\\.sh") then [item("Adapter or hook files were modified — trace the event flow from trigger to output."; false)] else [] end)
    + (if any_path("(\\.bats$|\\.test\\.|\\.spec\\.|_test\\.|test_|spec_)") then [item("Tests were added or changed — run the suite and understand what each test verifies."; false)] else [] end)
    + (if any_cmd("\\b(bats|jest|pytest|py\\.test|cargo test|go test|npm test|make test|rake test|rspec|mocha|vitest|phpunit)\\b") then [] else [item("No automated test run was observed — confirm the changed behavior is covered by tests."; false)] end)
    | concat("\n");

# The brief for NotebookLM's audio overview: the pack's first paragraph and
# the page's "Copy audio prompt". It asks for extra time only when a concept
# the page lists under What to understand is shaky.
def audio_prompt:
  "Create a maintainer-focused audio overview of this session. Explain what changed, why it matters, what to inspect first, and what could break. Assume the listener owns this codebase and needs enough technical depth to support it."
  + (if any(.concepts[:5][]; .status == "shaky") then
       " Spend extra time on the concepts under \"What you struggled with\"; the listener has struggled with these before."
     else "" end);

# A project file as a link from sessions/<page>.html, three levels below the
# project root; a path outside the project stays plain text.
def file_link:
  if startswith("/") or startswith("../") or . == ".." then "<code>\(@html)</code>"
  else "<a href=\"../../../\(split("/") | map(@uri) | concat("/"))\"><code>\(@html)</code></a>" end;

def plural($n; $one; $many): "\($n) \(if $n == 1 then $one else $many end)";

# The header's one-line summary: who, how much, and what is still broken.
def counts_line:
  ([.failures[] | select(.fixed_by == null)] | length) as $open
  | (.failures | length) as $fails
  | [.harness, .model] + [plural(.turns.work; "work turn"; "work turns"), plural(.files | length; "file"; "files"),
      (if $fails == 0 then "no failed commands"
       elif $open == 0 then "\(plural($fails; "failed command"; "failed commands")), all fixed"
       else "\(plural($fails; "failed command"; "failed commands")), \($open) still failing" end)]
  | map(select(. != null) | tostring) | concat(" · ");

# Up to three later work prompts of four or more words: the follow-up requests.
def follow_ups:
  .goal_turn as $g
  | [.timeline[] | select(.kind == "prompt" and (.learning | not) and .turn != $g
                          and (.text | typed_command | not)
                          and (.text | [splits("\\s+")] | map(select(. != "")) | length) >= 4)] | .[:3];

# 1 · What was built and why: the goal, the follow-up requests, the files by area.
def built_html:
  . as $f
  | follow_ups as $asks
  | ["        <blockquote class=\"ask\">\(.goal // "No prompt captured for this session." | @html)</blockquote>",
     (if .goal_turn then "        <p class=\"ask-meta\">Turn \(.goal_turn) · the first substantial request in this session</p>" else empty end),
     (if $asks != [] then "        <h3>Follow-up requests</h3>\n        <ol class=\"asks\">"
        + ($asks | map("<li><span class=\"turn\">turn \(.turn)</span><span>\(if (.text | length) > 300 then .text[:300] + "…" else .text end | @html)</span></li>") | concat(""))
        + "</ol>" else empty end),
     (if .files == [] then "        <p class=\"empty\">No files were changed in this session's work turns.</p>"
      else "        <h3>Files, by area</h3>\n        <div class=\"areas\">"
        + ([.files[] | . + {area: (.path | file_area)}] | group_by(.area)
           | sort_by(.[0].area as $a | ["source", "tests", "script", "adapter", "auth", "database", "config", "docs"] | index($a))
           | map("<div class=\"area-group\"><h4><span class=\"area area-\(.[0].area)\">\(.[0].area)</span>\(plural(length; "file"; "files"))</h4><ul class=\"flist\">"
                 + (map("<li>\(.path | file_link)<span class=\"ops\">\([(if .created > 0 then "created" else empty end),
                          (if .edited > 0 then "edited" + (if .edited > 1 then " \(.edited)×" else "" end) else empty end),
                          (if .deleted > 0 then "deleted" else empty end)] | concat(", "))</span></li>") | concat(""))
                 + "</ul></div>") | concat(""))
        + "</div>" end)]
  | concat("\n");

# 2 · What to understand: up to five concepts, with the files they came from.
def understand_html:
  if .concepts == [] then
    "        <p class=\"empty\">No knowledge-ledger concepts are linked to this session yet. <code>/quiz</code>, <code>/explain</code>, and <code>/digest</code> record the concepts you meet and the files they come from.</p>"
  else
    (if .concepts[0].match == "files" then "        <p class=\"lede\">Concepts from your knowledge ledger that live in the files this session changed.</p>"
     else "        <p class=\"lede\">Concepts from your knowledge ledger seen on \(.date | @html). None are linked to this session's files yet.</p>" end)
    + "\n        <ul class=\"concepts\">"
    + (.concepts[:5] | map(
        "<li class=\"concept \(.status | @html)\"><div class=\"concept-head\"><strong>\(.label | @html)</strong><span class=\"chip status-\(.status | @html)\">\(.status | @html)</span></div>"
        + (if .files != [] then "<div class=\"concept-files\">in \(.files | map(file_link) | concat(", "))</div>" else "" end)
        + "<div class=\"concept-meta\">\(if .last_quizzed then "last quizzed \(.last_quizzed | @html)" else "not quizzed yet" end) · ask <code>/quiz \(.label | @html)</code></div></li>") | concat(""))
    + "</ul>"
    + (if (.concepts | length) > 5 then "\n        <p class=\"lede\">\((.concepts | length) - 5) more under <a href=\"#knowledge\">Knowledge state</a>.</p>" else "" end)
  end;

# 3 · What broke: failures of the same command with the same fix grouped,
# still-failing ones first, at most five.
def broke_html:
  if .failures == [] then "        <p class=\"empty\">Nothing failed in this session's work turns.</p>"
  else
    (.failures | group_by([.command, .fixed_by]) | sort_by((if .[0].fixed_by then 1 else 0 end), .[0].turn)) as $groups
    | "        <ul class=\"breaks\">"
      + ($groups[:5] | map(
          (map(.turn) | unique) as $turns
          | "<li class=\"break \(if .[0].fixed_by then "fixed" else "open" end)\"><div><code>\(.[0].command | @html)</code> failed"
            + (if length > 1 then " \(length)×" else "" end)
            + " (exit \(.[0].exit_code | @html)) · turn\(if ($turns | length) > 1 then "s \($turns[0])–\($turns[-1])" else " \($turns[0])" end)</div>"
            + (if .[0].fixed_by then "<div class=\"fix\">→ fixed in turn \(.[0].fixed_by.turn) by <code>\(.[0].fixed_by.command | @html)</code></div>"
               else "<div class=\"fix\">→ still failing: nothing later in the session ran it successfully</div>" end)
            + "</li>") | concat(""))
      + "</ul>"
      + (if ($groups | length) > 5 then "\n        <p class=\"lede\">\(($groups | length) - 5) more in the <a href=\"#commands\">command log</a>.</p>" else "" end)
  end;

# The session page (template as input). $health is health-report.sh --views,
# or null; $pack is the rendered NotebookLM pack.
def session_page($f; $health; $pack):
  ($f.failures | length) as $fails
  | ($f.knowledge.total // 0) as $concepts
  | ($health.views["harness|14"].flags_total // 0) as $flags
  | fill({
      project: ($f.project | @html),
      date: ($f.date | @html),
      goal: ($f.goal // "No prompt captured for this session." | @html),
      counts: ($f | counts_line | @html),
      concept_count: ($f.concepts[:5] | length),
      built: ($f | built_html),
      understand: ($f | understand_html),
      broke: ($f | broke_html),
      learning_events: ([$f.timeline[] | select(.learning)] | length),
      pack_name: ("\($f.slug)-notebooklm-pack.md" | @html),
      health_nav: (if $health == null then "" else "
      <a href=\"#health\">Assistant health <span class=\"nbadge\">\($flags)</span></a>" end),
      knowledge_nav: (if $concepts > 0 then "
      <a href=\"#knowledge\">Knowledge state <span class=\"nbadge\">\($concepts)</span></a>" else "" end),
      files: ($f | file_total),
      commands: ($f.commands | length),
      created: ($f | paths_with("created") | length),
      edited: ($f | paths_with("edited") | length),
      deleted: ($f | paths_with("deleted") | length),
      failures: $fails,
      failure_class: (if $fails > 0 then "danger" else "ok" end),
      failure_detail: (if $fails > 0 then "failed command(s) — inspect first" else "no failures detected" end),
      summary: ($f.pause_summary // "No pause summary was available." | @html),
      health_section: (if $health == null then "" else $health | health_card end),
      timeline: ([$f.timeline[]
        | (if .learning then " data-learning=\"true\"" else "" end) as $attr
        | (if .learning then " <span class=\"pill learning\">learning</span>" else "" end) as $chip
        | if .kind == "prompt" then
            "<li data-kind=\"prompt\"\($attr)><span class=\"dot prompt\"></span><div class=\"tl-body\"><strong class=\"tl-type\">Prompt</strong>\($chip)<p>\(.text | @html)</p></div></li>"
          elif .kind == "command" then
            "<li data-kind=\"command\"\($attr)><span class=\"dot command\"></span><div class=\"tl-body\"><strong class=\"tl-type\">Command</strong>\($chip)<p><code>\(.text | @html)</code></p></div></li>"
          else
            "<li data-kind=\"file\"\($attr)><span class=\"dot file\"></span><div class=\"tl-body\"><strong class=\"tl-type\">\(.action | @html)</strong>\($chip)<p><code>\(.text | @html)</code></p></div></li>"
          end] | concat("\n")),
      file_rows: ([("created", "edited", "deleted") as $a | $f | paths_with($a)[]
        | file_area as $area
        | "<li class=\"file-row\" data-area=\"\($area)\"><span class=\"pill action-\($a)\">\($a)</span><code class=\"fpath\">\(@html)</code><span class=\"area area-\($area)\">\($area)</span></li>"]
        | concat("\n")),
      command_rows: ([$f | work_commands[]
        | (.exit_code != 0) as $failed
        | "<li class=\"command-row \(if $failed then "fail" else "ok" end)\" data-kind=\"command\"><code class=\"cmd-text\">\(.text[:240] | @html)</code><span class=\"status\">\(if $failed then "failed" else "exit" end) \(.exit_code | @html)</span></li>"]
        | concat("\n")),
      diff_html: ($f.diff | diff_html),
      study: ($f | study_queue),
      knowledge_section: (if $concepts > 0 then "

      <section id=\"knowledge\">
        <h2>Knowledge State</h2>
        <p class=\"export-intro\">From .vibe-learn/knowledge.json — what /quiz has confirmed and what still needs work. \($f.knowledge.shaky) shaky.</p>
        <ul class=\"list\">\([$f | knowledge_rows[]
          | {shaky: "action-deleted", solid: "action-created"}[.status] as $pill
          | "<li class=\"file-row\" data-status=\"\(.status | @html)\"><span class=\"pill \($pill // "action-edited")\">\(.status | @html)</span><code class=\"fpath\">\(.label | @html)</code><span class=\"area area-docs\">last quizzed \(.last_quizzed // "never" | @html) · \(.sessions | @html) session(s)</span></li>"]
          | concat("\n"))</ul>
      </section>" else "" end),
      pack_html: ($pack | @html),
      pack_json: ($pack | script_json),
      diff_json: ($f.diff | script_json),
      audio_prompt: ($f | audio_prompt | script_json)
    });
