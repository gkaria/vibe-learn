#!/bin/bash
# briefing.sh — Generate static vibe-learn session briefing artifacts.

set -euo pipefail

TARGET_DIR=""
LATEST=false

for arg in "$@"; do
  case "$arg" in
    --latest)
      LATEST=true
      ;;
    --help|-h)
      cat <<EOF
Usage:
  vibe-learn briefing [target-dir] [--latest]

Generates .vibe-learn/briefing/index.html plus a session page and
NotebookLM-ready source pack for the current session log.

With --latest the index shows only the current session, skipping
previously generated session cards.
EOF
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown briefing flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$arg"
      else
        echo "ERROR: briefing accepts at most one target directory." >&2
        exit 1
      fi
      ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

LOG_DIR="$TARGET_DIR/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
META_FILE="$LOG_DIR/session-meta.json"
SUMMARY_FILE="$LOG_DIR/pause-summary.txt"
BRIEFING_DIR="$LOG_DIR/briefing"
SESSIONS_DIR="$BRIEFING_DIR/sessions"
EXPORTS_DIR="$BRIEFING_DIR/exports"
INDEX_FILE="$BRIEFING_DIR/index.html"

PROJECT_NAME="$(basename "$TARGET_DIR")"
NOW_DATE="$(date -u +"%Y-%m-%d")"
NOW_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$SESSIONS_DIR" "$EXPORTS_DIR"

html_escape() {
  jq -Rr @html
}

json_string() {
  jq -Rs .
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//'
}

# Render a git diff as syntax-highlighted HTML spans (one span per line, display:block).
render_diff_as_html() {
  printf '%s\n' "$1" | awk '
    function he(s,    r) {
      r = s
      gsub(/&/, "\\&amp;", r)
      gsub(/</, "\\&lt;", r)
      gsub(/>/, "\\&gt;", r)
      return r
    }
    /^\+\+\+ |^--- |^diff --git|^index [0-9a-f]/ {
      print "<span class=\"dh\">" he($0) "</span>"
      next
    }
    /^@@/ { print "<span class=\"dk\">" he($0) "</span>"; next }
    /^\+/  { print "<span class=\"da\">" he($0) "</span>"; next }
    /^-/   { print "<span class=\"dd\">" he($0) "</span>"; next }
    { print "<span class=\"dc\">" he($0) "</span>" }
  '
}

write_empty_briefing() {
  local message="No vibe-learn session log was found for $PROJECT_NAME."
  cat > "$INDEX_FILE" <<EMPTY_EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>vibe-learn — $PROJECT_NAME</title>
  <style>
    :root{--bg:#faf9f5;--surface:#f1efe7;--text:#141413;--muted:#706f68;--line:#d8d4c8;--accent:#d97757;--radius:8px;}
    *{box-sizing:border-box;}
    body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 Lora,Georgia,serif;}
    main{max-width:600px;margin:80px auto;padding:0 24px;}
    h1{font:700 32px/1.1 Poppins,Arial,sans-serif;margin:0 0 8px;}
    .brand{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--muted);margin-bottom:20px;}
    .panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:24px 28px;margin-top:24px;}
    p{color:var(--muted);margin:0 0 8px;}
    code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;background:var(--surface);padding:2px 5px;border-radius:4px;border:1px solid var(--line);}
  </style>
</head>
<body>
  <main>
    <div class="brand">vibe-learn</div>
    <h1>No session data yet</h1>
    <div class="panel">
      <p>$message</p>
      <p>Run an agent session with vibe-learn installed, then run <code>vibe-learn dashboard</code> again.</p>
    </div>
  </main>
</body>
</html>
EMPTY_EOF
  echo "No session log found. Wrote briefing placeholder: $INDEX_FILE"
}

if [ ! -s "$SESSION_LOG" ]; then
  write_empty_briefing
  exit 0
fi

SESSION_ID="unknown"
STARTED_AT=""
if [ -f "$META_FILE" ]; then
  SESSION_ID="$(jq -r '.session_id // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")"
  STARTED_AT="$(jq -r '.started_at // empty' "$META_FILE" 2>/dev/null || true)"
fi

SESSION_DATE="$NOW_DATE"
SESSION_TOKEN="$(date -u +"%H%M%S")"
if [ -n "$STARTED_AT" ]; then
  SESSION_DATE="$(printf '%s' "$STARTED_AT" | cut -c1-10)"
  SESSION_TOKEN="$(printf '%s' "$STARTED_AT" | sed 's/[^0-9]//g' | cut -c9-14)"
fi
if [ "$SESSION_ID" != "unknown" ]; then
  SESSION_TOKEN="$(slugify "$SESSION_ID")"
fi
SESSION_SLUG="$(slugify "$SESSION_DATE-$PROJECT_NAME-$SESSION_TOKEN")"
SESSION_FILE="$SESSIONS_DIR/$SESSION_SLUG.html"
PACK_FILE="$EXPORTS_DIR/$SESSION_SLUG-notebooklm-pack.md"

GOAL="$(jq -r 'select(.event=="user_prompt") | .prompt' "$SESSION_LOG" 2>/dev/null | tail -1)"
GOAL="${GOAL:-No prompt captured for this session.}"

PAUSE_SUMMARY=""
if [ -f "$SUMMARY_FILE" ]; then
  PAUSE_SUMMARY="$(head -c 4000 "$SUMMARY_FILE")"
fi

FILES_CREATED="$(jq -r 'select(.event=="tool_use" and .action=="created") | .file // empty' "$SESSION_LOG" 2>/dev/null | sort -u)"
FILES_EDITED="$(jq -r 'select(.event=="tool_use" and .action=="edited") | .file // empty' "$SESSION_LOG" 2>/dev/null | sort -u)"
FILES_DELETED="$(jq -r 'select(.event=="tool_use" and .action=="deleted") | .file // empty' "$SESSION_LOG" 2>/dev/null | sort -u)"
ALL_FILES="$(printf '%s\n%s\n' "$FILES_CREATED" "$FILES_EDITED" | sort -u)"
COMMANDS="$(jq -r 'select(.event=="tool_use" and .tool=="Bash") | [.command, (.context.exit_code // 0)] | @tsv' "$SESSION_LOG" 2>/dev/null)"
FAILURES="$(printf '%s\n' "$COMMANDS" | awk -F '\t' '$2 != "" && $2 != "0" {print}')"

CREATED_COUNT="$(printf '%s\n' "$FILES_CREATED" | sed '/^$/d' | wc -l | tr -d ' ')"
EDITED_COUNT="$(printf '%s\n' "$FILES_EDITED" | sed '/^$/d' | wc -l | tr -d ' ')"
DELETED_COUNT="$(printf '%s\n' "$FILES_DELETED" | sed '/^$/d' | wc -l | tr -d ' ')"
COMMAND_COUNT="$(printf '%s\n' "$COMMANDS" | sed '/^$/d' | wc -l | tr -d ' ')"
FAILURE_COUNT="$(printf '%s\n' "$FAILURES" | sed '/^$/d' | wc -l | tr -d ' ')"
FILES_TOTAL="$(( CREATED_COUNT + EDITED_COUNT + DELETED_COUNT ))"

FAILURE_TAG=""
[ "${FAILURE_COUNT:-0}" -gt 0 ] && FAILURE_TAG="<span class=\"tag danger\">${FAILURE_COUNT} failed</span>"

infer_area() {
  local file="$1"
  case "$file" in
    *test*|tests/*|*.bats|*spec*|*_test.*|*.test.*) echo "tests" ;;
    adapters/*) echo "adapter" ;;
    scripts/*) echo "script" ;;
    *auth*|*login*|*password*|*token*|*secret*|*oauth*|*permission*|*cred*) echo "auth" ;;
    *db*|*database*|*migration*|*schema*|*model.py|*model.ts) echo "database" ;;
    config/*|*.json|*.toml|*.yaml|*.yml) echo "config" ;;
    README.md|CLAUDE.md|CHANGELOG.md|docs/*|specs/*|*.md) echo "docs" ;;
    *) echo "source" ;;
  esac
}

render_file_rows() {
  local action="$1"
  local files="$2"
  local file area escaped_file
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    area="$(infer_area "$file")"
    escaped_file="$(printf '%s' "$file" | html_escape)"
    printf '<li class="file-row" data-area="%s"><span class="pill action-%s">%s</span><code class="fpath">%s</code><span class="area area-%s">%s</span></li>\n' \
      "$area" "$action" "$action" "$escaped_file" "$area" "$area"
  done <<EOF
$files
EOF
}

render_command_rows() {
  local cmd exit_code escaped_cmd class label
  while IFS="$(printf '\t')" read -r cmd exit_code; do
    [ -z "${cmd:-}" ] && continue
    escaped_cmd="$(printf '%s' "$cmd" | head -c 240 | html_escape)"
    class="ok"
    label="exit ${exit_code:-0}"
    if [ "${exit_code:-0}" != "0" ]; then
      class="fail"
      label="failed ${exit_code:-unknown}"
    fi
    printf '<li class="command-row %s" data-kind="command"><code class="cmd-text">%s</code><span class="status">%s</span></li>\n' \
      "$class" "$escaped_cmd" "$label"
  done <<EOF
$COMMANDS
EOF
}

render_timeline() {
  jq -r '
    if .event == "user_prompt" then
      "<li data-kind=\"prompt\"><span class=\"dot prompt\"></span><div class=\"tl-body\"><strong class=\"tl-type\">Prompt</strong><p>\(.prompt | @html)</p></div></li>"
    elif .event == "tool_use" and .tool == "Bash" then
      "<li data-kind=\"command\"><span class=\"dot command\"></span><div class=\"tl-body\"><strong class=\"tl-type\">Command</strong><p><code>\((.command // "") | @html)</code></p></div></li>"
    elif .event == "tool_use" then
      "<li data-kind=\"file\"><span class=\"dot file\"></span><div class=\"tl-body\"><strong class=\"tl-type\">\(.action // "changed")</strong><p><code>\((.file // "file") | @html)</code></p></div></li>"
    else empty end
  ' "$SESSION_LOG" 2>/dev/null
}

# Dynamic heuristic checklist based on actual session content.
render_study_queue() {
  local cmd_list="$COMMANDS"
  local all_files="$ALL_FILES"

  printf '<label class="study-item"><input type="checkbox"><span>Read through each changed file and explain its purpose in your own words.</span></label>\n'

  if printf '%s\n' "$cmd_list" | grep -qiE '\b(npm|pip|pip3|brew|gem|cargo|yarn|pnpm)\b.*\binstall\b'; then
    printf '<label class="study-item priority"><input type="checkbox"><span>New dependencies were installed — understand what each adds and why it was needed.</span></label>\n'
  fi

  if [ "${FAILURE_COUNT:-0}" -gt 0 ]; then
    printf '<label class="study-item priority"><input type="checkbox"><span>%d command(s) failed during this session — inspect each failure and confirm the issue was resolved.</span></label>\n' "$FAILURE_COUNT"
  fi

  if printf '%s\n' "$all_files" | grep -qiE '(auth|login|password|token|secret|jwt|oauth|permission|cred)'; then
    printf '<label class="study-item"><input type="checkbox"><span>Auth or security-related files were touched — trace the access control flow end to end.</span></label>\n'
  fi

  if printf '%s\n' "$all_files" | grep -qiE '(db|database|migration|schema|model\.py|model\.ts|orm)'; then
    printf '<label class="study-item"><input type="checkbox"><span>Database or schema files changed — confirm the data model is correct and migrations apply cleanly.</span></label>\n'
  fi

  if printf '%s\n' "$all_files" | grep -qiE '\.(json|toml|yaml|yml)$|^config/'; then
    printf '<label class="study-item"><input type="checkbox"><span>Configuration files were updated — verify environment-specific settings are correct.</span></label>\n'
  fi

  if printf '%s\n' "$all_files" | grep -qiE '^adapters/|hooks\.(json|toml)|hooks\.sh'; then
    printf '<label class="study-item"><input type="checkbox"><span>Adapter or hook files were modified — trace the event flow from trigger to output.</span></label>\n'
  fi

  if printf '%s\n' "$all_files" | grep -qiE '(\.bats$|\.test\.|\.spec\.|_test\.|test_|spec_)'; then
    printf '<label class="study-item"><input type="checkbox"><span>Tests were added or changed — run the suite and understand what each test verifies.</span></label>\n'
  fi

  if ! printf '%s\n' "$cmd_list" | grep -qiE '\b(bats|jest|pytest|py\.test|cargo test|go test|npm test|make test|rake test|rspec|mocha|vitest|phpunit)\b'; then
    printf '<label class="study-item"><input type="checkbox"><span>No automated test run was observed — confirm the changed behavior is covered by tests.</span></label>\n'
  fi
}

# --- Knowledge ledger (optional input) ---
# A missing or malformed ledger never fails the briefing; every ledger-derived
# fragment below stays empty so the output matches the no-ledger rendering.
LEDGER_FILE="$LOG_DIR/knowledge.json"
LEDGER_OK=false
if [ -f "$LEDGER_FILE" ]; then
  if jq -e '.concepts | type == "array"' "$LEDGER_FILE" >/dev/null 2>&1; then
    LEDGER_OK=true
  else
    echo "WARN: $LEDGER_FILE is not a valid knowledge ledger — skipping knowledge state." >&2
  fi
fi

SHAKY_COUNT=0
LEDGER_STUDY_ITEMS=""
KNOWLEDGE_ROWS_HTML=""
KNOWLEDGE_PACK=""
KNOWLEDGE_NAV=""
KNOWLEDGE_SECTION=""
AUDIO_EXTRA=""
AUDIO_EXTRA_JS=""
LEDGER_TOTAL=0

render_knowledge_rows() {
  local label status quizzed sessions pill
  while IFS="$(printf '\t')" read -r label status quizzed sessions; do
    [ -z "${label:-}" ] && continue
    case "$status" in
      shaky) pill="action-deleted" ;;
      solid) pill="action-created" ;;
      *)     pill="action-edited" ;;
    esac
    printf '<li class="file-row" data-status="%s"><span class="pill %s">%s</span><code class="fpath">%s</code><span class="area area-docs">last quizzed %s · %s session(s)</span></li>\n' \
      "$status" "$pill" "$status" "$(printf '%s' "$label" | html_escape)" "$(printf '%s' "$quizzed" | html_escape)" "$sessions"
  done <<EOF
$KNOWLEDGE_TSV
EOF
}

if [ "$LEDGER_OK" = true ]; then
  LEDGER_TOTAL="$(jq -r '.concepts | length' "$LEDGER_FILE")"
  SHAKY_COUNT="$(jq -r '[.concepts[] | select(.status == "shaky")] | length' "$LEDGER_FILE")"

  # Study queue: shaky concepts, plus never-quizzed concepts seen in 2+ sessions. Cap 5.
  LEDGER_STUDY_ITEMS="$(jq -r '
    [.concepts[] | select(.status == "shaky" or (.status == "new" and ((.sessions // 0) >= 2)))]
    | sort_by((if .status == "shaky" then 0 else 1 end), (.last_quizzed // ""))
    | .[:5][]
    | [(.label // .name // "concept"), (.status // "new"), (.last_quizzed // "never")]
    | @tsv' "$LEDGER_FILE" 2>/dev/null)"

  # Knowledge state: up to 10 concepts, needs-attention first.
  KNOWLEDGE_TSV="$(jq -r '
    [.concepts[]]
    | sort_by((if .status == "solid" then 1 else 0 end), (.last_seen // ""))
    | .[:10][]
    | [(.label // .name // "concept"), (.status // "new"), (.last_quizzed // "never"), ((.sessions // 0) | tostring)]
    | @tsv' "$LEDGER_FILE" 2>/dev/null)"

  if [ "$LEDGER_TOTAL" -gt 0 ]; then
    KNOWLEDGE_ROWS_HTML="$(render_knowledge_rows)"

    KNOWLEDGE_NAV="
      <a href=\"#knowledge\">Knowledge state <span class=\"nbadge\">$LEDGER_TOTAL</span></a>"
    KNOWLEDGE_SECTION="

      <section id=\"knowledge\">
        <h2>Knowledge State</h2>
        <p class=\"export-intro\">From .vibe-learn/knowledge.json — what /quiz has confirmed and what still needs work. $SHAKY_COUNT shaky.</p>
        <ul class=\"list\">$KNOWLEDGE_ROWS_HTML</ul>
      </section>"

    NEEDS_ATTENTION_ROWS="$(printf '%s\n' "$KNOWLEDGE_TSV" | awk -F '\t' 'NF && $2 != "solid" {printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}')"
    SOLID_ROWS="$(printf '%s\n' "$KNOWLEDGE_TSV" | awk -F '\t' 'NF && $2 == "solid" {printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}')"
    [ -z "$NEEDS_ATTENTION_ROWS" ] && NEEDS_ATTENTION_ROWS="| (nothing — every quizzed concept is solid) | | | |"
    [ -z "$SOLID_ROWS" ] && SOLID_ROWS="| (none yet — run /quiz) | | | |"
    KNOWLEDGE_PACK="

## Your knowledge state

Tracked in .vibe-learn/knowledge.json by /quiz, /learn, and /digest.

### Needs attention

| Concept | Status | Last quizzed | Sessions |
|---------|--------|--------------|----------|
$NEEDS_ATTENTION_ROWS

### Solid

| Concept | Status | Last quizzed | Sessions |
|---------|--------|--------------|----------|
$SOLID_ROWS"
  fi

  if [ "$SHAKY_COUNT" -gt 0 ]; then
    AUDIO_EXTRA=' Spend extra time on the concepts listed under "Your knowledge state — needs attention"; the listener has struggled with these before.'
    AUDIO_EXTRA_JS="$(printf '%s' "$AUDIO_EXTRA" | jq -Rr '@json | .[1:-1]')"
  fi
fi

# Assistant health: a trend page, a session card, and an index row, only when
# health.jsonl has rows. Without it every output stays byte-identical.
HEALTH_FILE="$LOG_DIR/health.jsonl"
HEALTH_PAGE="$BRIEFING_DIR/health.html"
HEALTH_REPORT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/health-report.sh"
HEALTH_VIEWS=""
HEALTH_NAV=""
HEALTH_SECTION=""
HEALTH_INDEX_ROW=""

if [ -s "$HEALTH_FILE" ]; then
  if ! HEALTH_ROWS="$(jq -n '[inputs | objects] | length' "$HEALTH_FILE" 2>/dev/null)"; then
    echo "Warning: $HEALTH_FILE is not valid JSON Lines; skipping assistant health." >&2
  elif [ "$HEALTH_ROWS" -gt 0 ] && [ -f "$HEALTH_REPORT" ]; then
    HEALTH_VIEWS="$(bash "$HEALTH_REPORT" "$TARGET_DIR" --views 2>/dev/null || true)"
  fi
fi

HEALTH_CARD_JQ="$(cat <<'JQ'
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
    | "<div class=\"brief-grid\">" + join("") + "</div>" end) as $tiles
| (if $c == null then "<span class=\"muted\">No tool activity in this session yet.</span>"
   elif ($has_base | not) then "<span class=\"muted\">Building your baseline: \($x.baseline.sessions // 0) of \($s.min_sessions) earlier sessions on \($c.series | @html). Comparisons start after \($s.min_sessions).</span>"
   elif ($flags | length) > 0 then "<span><strong>\($flags | length) of \(mkeys | length)</strong> signals rose on average after \($x.marker.change | @html) (\($x.marker.at | day_label)); the chips show by how much.</span>"
   else "<span>Within your usual range on all \(mkeys | length) signals for \($c.series | @html).</span>" end) as $footer
| (if $c != null and ($c.eligible | not) then "<span class=\"muted\">Under \($s.min_events) tool events so far, so this session will not count yet.</span> " else "" end) as $short
| ($c.usage // null) as $u
| (def names($m; $prefix): $m | to_entries | map($prefix + .key + (if .value > 1 then " ×\(.value)" else "" end)) | join(", ");
   if $u == null then "" else
     ([(if $u.tools then "Tools: " + ($u.tools | to_entries | .[:8] | map("\(.key) \(.value)") | join(" · ") | if . == "" then "none" else . end) else empty end),
       (if ($u.skills // {}) != {} then "Skills: " + names($u.skills; "") else empty end),
       (if ($u.commands // {}) != {} then "Commands: " + names($u.commands; "/") else empty end)]
      | if length == 0 then "" else "<p class=\"usage\">" + (map(@html) | join(" &nbsp;·&nbsp; ")) + "</p>" end) end) as $usage_line
| (if $c == null then "" else "\($c.model // "unknown model") via \([$c.harness, $c.harness_version] | map(select(. != null)) | join(" "))" end) as $who
| "

      <section id=\"health\">
        <style>
          #health .health-head{display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap;border-bottom:1px solid var(--line);padding-bottom:8px;margin-bottom:16px;}
          #health .health-head h2{border:0;padding:0;margin:0;}
          #health .who{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--muted);}
          #health .delta{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;border-radius:999px;padding:1px 7px;border:1px solid var(--line);margin-left:6px;white-space:nowrap;vertical-align:3px;}
          #health .delta.bad{color:var(--danger);background:#fde8e4;border-color:#f0c8c0;}
          #health .card-footer{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;font-size:14px;}
          #health .muted{color:var(--muted);}
          #health .usage{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--muted);margin:0 0 12px;overflow-wrap:anywhere;}
        </style>
        <div class=\"health-head\"><h2>Assistant health</h2><span class=\"who\">\($who | @html)</span></div>
        \($tiles)
        \($usage_line)
        <div class=\"card-footer\"><span>\($short)\($footer)</span><a href=\"../health.html\">See the trend →</a></div>
      </section>"
JQ
)"

write_health_page() {
  local views_json
  views_json="$(printf '%s' "$HEALTH_VIEWS" | jq -c . | sed 's#</#<\\/#g')"
  cat > "$HEALTH_PAGE" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>vibe-learn — $PROJECT_NAME — assistant health</title>
EOF
  cat >> "$HEALTH_PAGE" <<'EOF'
  <style>
    :root{
      --bg:#faf9f5; --surface:#f1efe7; --surface-2:#e8e6dc;
      --text:#141413; --muted:#706f68; --line:#d8d4c8;
      --accent:#d97757; --accent-blue:#6a9bcc; --accent-green:#788c5d;
      --danger:#9f3d32; --warning:#b5792a; --success:#617a4b;
      --radius:8px; --shadow:0 1px 3px rgba(20,20,19,.1);
    }
    *{box-sizing:border-box;}
    body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 Lora,Georgia,serif;overflow-x:hidden;}
    a{color:var(--accent-blue);text-decoration:none;}
    a:hover{text-decoration:underline;}
    code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;background:var(--surface-2);padding:1px 6px;border-radius:4px;}
    h1,h2,h3{font-family:Poppins,Arial,sans-serif;font-weight:700;line-height:1.15;margin:0 0 12px;}
    h1{font-size:clamp(22px,3vw,36px);}
    h3{font-size:15px;}
    p{margin:0 0 10px;}
    .muted{color:var(--muted);}
    .site-header{background:var(--surface);border-bottom:1px solid var(--line);padding:20px 32px;display:flex;justify-content:space-between;align-items:flex-start;gap:24px;flex-wrap:wrap;}
    .eyebrow{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:var(--muted);margin-bottom:6px;letter-spacing:.03em;}
    .eyebrow a{color:var(--muted);}
    .goal{color:var(--muted);font-size:14px;margin:4px 0 0;}
    .button,button{border:1px solid var(--line);background:var(--surface);color:var(--text);border-radius:var(--radius);padding:8px 14px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;text-decoration:none;cursor:pointer;box-shadow:var(--shadow);}
    .button:hover,button:hover{background:var(--surface-2);text-decoration:none;}
    .page{max-width:980px;margin:0 auto;padding:32px;}
    .callout{background:var(--surface);border:1px solid var(--line);border-left:3px solid var(--warning);border-radius:var(--radius);padding:16px 20px;margin-bottom:20px;}
    .callout h3{font-size:16px;margin-bottom:6px;}
    .callout .cause{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--muted);margin-bottom:10px;}
    .callout .deltas{display:grid;grid-template-columns:max-content max-content 1fr;gap:3px 18px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;margin-bottom:10px;}
    .callout .deltas .to{color:var(--danger);font-weight:600;}
    .callout .control{font-size:14px;margin:0;}
    .quiet{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:14px 20px;margin-bottom:20px;font-size:14px;}
    .controls{display:flex;flex-wrap:wrap;gap:10px 22px;margin:8px 0 12px;align-items:center;}
    .control-group{display:flex;align-items:center;gap:6px;}
    .label{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:10.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin-right:4px;}
    .filters{display:flex;gap:6px;flex-wrap:wrap;}
    .filters button{padding:5px 11px;font-size:11px;}
    .filters button.active{background:var(--accent);border-color:var(--accent);color:#fff;}
    .chart-card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:16px 18px 12px;}
    .chart-title{font-family:Poppins,Arial,sans-serif;font-weight:700;font-size:14px;margin-bottom:4px;}
    .chart-card svg{display:block;width:100%;height:auto;}
    .chart-card .grid{stroke:var(--line);stroke-width:1;}
    .chart-card .tick,.chart-card .axis-label{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;fill:var(--muted);}
    .chart-card .band{fill:var(--surface-2);}
    .chart-card .marker{stroke:var(--warning);stroke-width:1.5;stroke-dasharray:4 4;}
    .chart-card .marker-label{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;fill:var(--warning);}
    .chart-card .pt{stroke:var(--surface);stroke-width:1.5;}
    .chart-card .pt.dim{opacity:.35;}
    .legend{display:flex;gap:18px;flex-wrap:wrap;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:var(--muted);margin-top:6px;}
    .swatch{display:inline-block;width:10px;height:10px;border-radius:999px;margin-right:6px;vertical-align:-1px;}
    .swatch.sq{border-radius:2px;}
    .caption{font-size:11.5px;color:var(--muted);margin-top:6px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;}
    table.metrics{width:100%;border-collapse:separate;border-spacing:0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;margin-top:20px;background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);overflow:hidden;}
    table.metrics th,table.metrics td{padding:9px 12px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap;}
    table.metrics tr:last-child td{border-bottom:0;}
    table.metrics th:first-child,table.metrics td:first-child{text-align:left;}
    table.metrics th{font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);font-weight:600;background:var(--surface-2);}
    table.metrics .sel{background:rgba(217,119,87,.08);}
    table.metrics th.sel{background:rgba(217,119,87,.16);color:var(--text);}
    table.metrics td.flag{color:var(--danger);font-weight:700;}
    table.metrics .sub{color:var(--muted);font-size:11px;margin-left:6px;}
    .subhead{font-size:14px;margin:28px 0 0;}
    table.metrics.usage th,table.metrics.usage td{white-space:normal;text-align:left;}
    ul.status{list-style:none;padding:0;margin:16px 0 0;display:grid;gap:4px;font-size:14px;color:var(--muted);}
    .notes{margin-top:32px;border-top:1px dashed var(--line);padding-top:14px;font-size:13.5px;color:var(--muted);}
    .notes h3{font-size:11px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;text-transform:uppercase;letter-spacing:.07em;}
    .notes ul{margin:0;padding-left:18px;display:grid;gap:4px;}
    @media(max-width:840px){
      .site-header{padding:16px 20px;}
      .page{padding:20px;}
      table.metrics{display:block;overflow-x:auto;}
    }
  </style>
</head>
<body>
EOF
  cat >> "$HEALTH_PAGE" <<EOF
  <header class="site-header">
    <div>
      <div class="eyebrow"><a href="index.html">vibe-learn</a> / $PROJECT_NAME / assistant health</div>
      <h1>Assistant health</h1>
      <p class="goal">Signals from your real sessions in this project. Session signals are hints, not proof.</p>
    </div>
    <a class="button" href="index.html">← Index</a>
  </header>
EOF
  cat >> "$HEALTH_PAGE" <<'EOF'
  <main class="page">
    <div id="callouts"></div>
    <div class="controls">
      <div class="control-group">
        <span class="label">Metric</span>
        <div class="filters" data-control="metric">
          <button type="button" data-value="bash_fail_rate">Bash failure rate</button>
          <button type="button" data-value="rework_rate">Rework</button>
          <button type="button" data-value="events_per_prompt">Events / prompt</button>
          <button type="button" data-value="turns_to_green">Turns to green</button>
        </div>
      </div>
    </div>
    <div class="controls">
      <div class="control-group">
        <span class="label">Group by</span>
        <div class="filters" data-control="by">
          <button type="button" data-value="harness">Harness</button>
          <button type="button" data-value="model">Model</button>
        </div>
      </div>
      <div class="control-group">
        <span class="label">Window</span>
        <div class="filters" data-control="win">
          <button type="button" data-value="14">14d</button>
          <button type="button" data-value="all">All</button>
        </div>
      </div>
    </div>
    <div class="chart-card">
      <div class="chart-title" id="chart-title"></div>
      <div id="chart"></div>
      <div class="legend" id="legend"></div>
      <div class="caption" id="chart-caption"></div>
    </div>
    <table class="metrics" id="metrics-table"></table>
    <h3 class="subhead" id="usage-head" hidden>Tool use per session</h3>
    <table class="metrics usage" id="usage-table"></table>
    <ul class="status" id="status"></ul>
    <div class="notes">
      <h3>How to read this</h3>
      <ul id="notes"></ul>
    </div>
  </main>
  <script>
EOF
  printf '    const DATA = %s;\n' "$views_json" >> "$HEALTH_PAGE"
  cat >> "$HEALTH_PAGE" <<'EOF'
    const M = {
      bash_fail_rate: { name: "Bash failure rate", title: "Bash failure rate per session", axis: "Failed commands (%)", rate: true },
      rework_rate: { name: "Rework rate", title: "Rework rate per session", axis: "Files re-edited in 3+ turns (%)", rate: true },
      events_per_prompt: { name: "Events per prompt", title: "Tool events per user prompt", axis: "Tool events per prompt", rate: false },
      turns_to_green: { name: "Turns to green", title: "Turns from a failing check to a passing one", axis: "Turns", rate: false },
    };
    const KEYS = Object.keys(M);
    const S = DATA.settings;
    const PALETTE = ["var(--accent-blue)", "var(--accent)", "var(--accent-green)", "var(--warning)", "#6a4a88", "#4a7a3d", "var(--muted)"];
    const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const DAY = 86400000;
    const state = { metric: KEYS[0], by: "harness", win: "14" };

    const view = () => DATA.views[state.by + "|" + state.win];
    const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    const oneDec = v => (Math.round(v * 10) / 10).toFixed(1);
    const disp = (k, v) => M[k].rate ? v * 100 : v;
    const fmt = (k, v) => v == null ? "-" : M[k].rate ? Math.round(v * 100) + "%" : oneDec(v);
    const fmtDelta = (k, d) => (d >= 0 ? "+" : "") + (M[k].rate ? Math.round(d * 100) + " pts" : oneDec(d));
    const dayLabel = iso => MONTHS[+iso.slice(5, 7) - 1] + " " + (+iso.slice(8, 10));
    const seriesLine = x => x.label + (x.sub ? " (" + x.sub + ")" : "");
    const avg = a => a.reduce((s, v) => s + v, 0) / (a.length || 1);
    const sd = a => { const m = avg(a); return Math.sqrt(avg(a.map(v => (v - m) ** 2))); };

    function renderCallouts() {
      const v = view();
      const flagged = v.series.filter(x => x.status === "flagged");
      const el = document.getElementById("callouts");
      if (!flagged.length) {
        el.innerHTML = v.sessions
          ? `<div class="quiet">Nothing flagged in this window.</div>`
          : `<div class="quiet">No finished sessions in this window yet. Rows are added to health.jsonl when the next session starts.</div>`;
        return;
      }
      el.innerHTML = flagged.map(x => {
        const lines = x.flags.map(f =>
          `<span>${M[f.metric].name}</span><span>${fmt(f.metric, f.before)} → <span class="to">${fmt(f.metric, f.after)}</span></span><span class="muted">${fmtDelta(f.metric, f.delta)}</span>`
        ).join("");
        const c = x.control;
        const control = c
          ? `<p class="control">${esc(seriesLine(c))} held steady over the same days (${M[c.metric].name.toLowerCase()} ${fmt(c.metric, c.value)} vs ${fmt(c.metric, c.before)} before), so the change is a likelier cause than harder tasks.</p>`
          : "";
        return `<div class="callout">
          <h3>Something changed around ${dayLabel(x.marker.at)}</h3>
          <div class="cause">${esc(x.key)}: ${esc(x.marker.change)}${x.marker.sub ? " · " + esc(x.marker.sub) : ""} · ${x.since.sessions} sessions since, ${x.baseline.sessions} before</div>
          <div class="deltas">${lines}</div>${control}</div>`;
      }).join("");
    }

    function renderChart() {
      const k = state.metric, m = M[k], v = view();
      const chart = document.getElementById("chart");
      const legend = document.getElementById("legend");
      const caption = document.getElementById("chart-caption");
      document.getElementById("chart-title").textContent = m.title;

      const pts = [];
      v.series.forEach((x, si) => x.points.forEach(p => {
        if (p.m[k] != null) pts.push(Object.assign({}, p, { key: x.key, si, val: disp(k, p.m[k]), ms: Date.parse(p.t) }));
      }));
      if (!pts.length) {
        chart.innerHTML = `<p class="muted">No sessions with this signal in the window.</p>`;
        legend.innerHTML = caption.textContent = "";
        return;
      }

      const periods = [...new Set(pts.map(p => p.period))];
      const color = p => PALETTE[periods.indexOf(p.period) % PALETTE.length];
      const W = 760, H = 280, L = 56, R = 18, T = 26, B = 46;
      const t0 = Math.min(...pts.map(p => p.ms)), t1 = Math.max(...pts.map(p => p.ms));
      const lo = t0 - DAY / 2, hi = t1 + DAY / 2;
      const x = t => L + (t - lo) / (hi - lo) * (W - L - R);
      const maxV = Math.max(1, ...pts.map(p => p.val));
      const step = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100].find(st => Math.ceil(maxV * 1.1 / st) <= 5) || 100;
      const ticks = Math.ceil(maxV * 1.1 / step), ymax = ticks * step;
      const y = d => T + (1 - d / ymax) * (H - T - B);

      let s = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(m.title)}">`;
      for (let i = 0; i <= ticks; i++) {
        const d = step * i;
        s += `<line class="grid" x1="${L}" x2="${W - R}" y1="${y(d)}" y2="${y(d)}"/>`;
        s += `<text class="tick" x="${L - 8}" y="${y(d) + 4}" text-anchor="end">${m.rate ? d + "%" : d.toFixed(d % 1 ? 1 : 0)}</text>`;
      }

      const focus = v.series.find(x => x.status === "flagged") || v.series.find(x => x.marker);
      let bandNote = "";
      if (focus) {
        const base = pts.filter(p => p.key === focus.key && p.eligible && p.t < focus.marker.at).map(p => p.val);
        if (base.length) {
          const bm = avg(base), bs = sd(base);
          s += `<rect class="band" x="${L}" width="${W - L - R}" y="${y(bm + bs)}" height="${y(Math.max(0, bm - bs)) - y(bm + bs)}"/>`;
          bandNote = `<span><span class="swatch sq" style="background:var(--surface-2);border:1px solid var(--line)"></span>usual range: ${esc(focus.key)} before ${dayLabel(focus.marker.at)}, mean ± 1 sd</span>`;
        }
      }

      const days = Math.round((t1 - t0) / DAY);
      const every = Math.max(1, Math.ceil((days + 1) / 6));
      for (let d = 0; d <= days; d += every) {
        const t = t0 + d * DAY;
        s += `<text class="tick" x="${x(t)}" y="${H - B + 18}" text-anchor="middle">${dayLabel(new Date(t).toISOString())}</text>`;
      }
      v.series.filter(xs => xs.marker).forEach(xs => {
        const mx = x(Date.parse(xs.marker.at));
        s += `<line class="marker" x1="${mx}" x2="${mx}" y1="${T - 8}" y2="${H - B}"/>`;
        s += `<text class="marker-label" x="${mx - 6}" y="${T - 12}" text-anchor="end">${esc(xs.marker.label)}</text>`;
      });

      const byDay = {};
      pts.forEach(p => (byDay[p.t.slice(0, 10)] = byDay[p.t.slice(0, 10)] || []).push(p));
      pts.forEach(p => {
        const same = byDay[p.t.slice(0, 10)], i = same.indexOf(p);
        const cx = x(Date.parse(p.t.slice(0, 10) + "T12:00:00Z")) + (i - (same.length - 1) / 2) * 11, cy = y(p.val);
        const cls = "pt" + (p.eligible ? "" : " dim");
        const tip = `<title>${dayLabel(p.t)} · ${esc(p.period)}${p.sub ? " · " + esc(p.sub) : ""}${p.project ? " · " + esc(p.project) : ""} · ${fmt(k, p.m[k])}${p.eligible ? "" : ` · under ${S.min_events} tool events, not counted`}</title>`;
        s += p.si === 0
          ? `<circle class="${cls}" cx="${cx}" cy="${cy}" r="5.5" style="fill:${color(p)}">${tip}</circle>`
          : `<rect class="${cls}" x="${cx - 5}" y="${cy - 5}" width="10" height="10" rx="1.5" style="fill:${color(p)}">${tip}</rect>`;
      });
      s += `<text class="axis-label" transform="rotate(-90)" x="${-(T + (H - T - B) / 2)}" y="14" text-anchor="middle">${esc(m.axis)}</text>`;
      s += `<text class="axis-label" x="${L + (W - L - R) / 2}" y="${H - 6}" text-anchor="middle">Session date</text>`;
      s += `</svg>`;
      chart.innerHTML = s;

      const seen = {};
      pts.forEach(p => { if (!seen[p.period]) seen[p.period] = p; });
      legend.innerHTML = periods.map(name => {
        const p = seen[name];
        return `<span><span class="swatch${p.si === 0 ? "" : " sq"}" style="background:${color(p)}"></span>${esc(name)}${p.sub ? " (" + esc(p.sub) + ")" : ""}</span>`;
      }).join("") + bandNote;
      caption.textContent = `Source: .vibe-learn/health.jsonl · ${v.sessions} sessions · ${dayLabel(new Date(t0).toISOString())}–${dayLabel(new Date(t1).toISOString())} · one point per session segment, hover for details. Faded points had under ${S.min_events} tool events and are not counted.`;
    }

    function renderTable() {
      const v = view();
      const el = document.getElementById("metrics-table");
      if (!v.series.length) { el.innerHTML = ""; return; }
      const head = `<tr><th>${state.by === "harness" ? "Harness" : "Model"}</th><th>Sessions</th>` +
        KEYS.map(k => `<th class="${k === state.metric ? "sel" : ""}">${M[k].name}</th>`).join("") + `</tr>`;
      const body = v.series.map(xs => xs.periods.map(p => {
        const flagged = new Set(p.latest ? xs.flags.map(f => f.metric) : []);
        const cells = KEYS.map(k => {
          const cls = [k === state.metric ? "sel" : "", flagged.has(k) ? "flag" : ""].join(" ").trim();
          return `<td class="${cls}">${fmt(k, p.means[k])}${flagged.has(k) ? " !" : ""}</td>`;
        }).join("");
        return `<tr><td>${esc(p.label)}${p.sub ? `<span class="sub">${esc(p.sub)}</span>` : ""}</td><td>${p.sessions}</td>${cells}</tr>`;
      }).join("")).join("");
      el.innerHTML = `<thead>${head}</thead><tbody>${body}</tbody>`;
    }

    function renderUsage() {
      const v = view();
      const rows = v.series.flatMap(xs => xs.periods.filter(p => p.usage));
      const el = document.getElementById("usage-table");
      document.getElementById("usage-head").hidden = !rows.length;
      if (!rows.length) { el.innerHTML = ""; return; }
      const names = (m, prefix) => Object.entries(m || {}).map(([k, n]) => esc(prefix + k) + (n > 1 ? " ×" + n : "")).join(", ");
      const body = rows.map(p => {
        const u = p.usage;
        const tools = u.sessions ? Object.entries(u.tools).slice(0, 8).map(([k, n]) => `${esc(k)} ${n}`).join(" · ") || "none" : "unknown";
        const extras = [u.skills && Object.keys(u.skills).length ? "skills: " + names(u.skills, "") : "",
                        u.commands && Object.keys(u.commands).length ? "commands: " + names(u.commands, "/") : ""].filter(Boolean).join("; ");
        return `<tr><td>${esc(p.label)}${p.sub ? `<span class="sub">${esc(p.sub)}</span>` : ""}</td><td>${tools}</td><td>${extras || "-"}</td></tr>`;
      }).join("");
      el.innerHTML = `<thead><tr><th>${state.by === "harness" ? "Harness" : "Model"}</th><th>Tools (average calls per session)</th><th>Skills and commands</th></tr></thead><tbody>${body}</tbody>`;
    }

    function renderStatus() {
      const lines = view().series.filter(x => x.status !== "flagged" && (x.status !== "steady" || x.marker)).map(x => {
        if (x.status === "building")
          return `${esc(x.key)}: building your baseline, ${x.baseline.sessions} of ${S.min_sessions} sessions with ${S.min_events}+ tool events`;
        if (x.status === "waiting")
          return `${esc(x.key)}: changed on ${dayLabel(x.marker.at)} (${esc(x.marker.change)}); ${x.since.sessions} of ${S.min_sessions} sessions since, comparison starts after ${S.min_sessions}`;
        return `${esc(x.key)}: no signal moved past the threshold since ${dayLabel(x.marker.at)} (${esc(x.marker.change)})`;
      });
      document.getElementById("status").innerHTML = lines.map(l => `<li>${l}</li>`).join("");
    }

    function renderNotes() {
      const within = state.by === "harness" ? "harness version, model, or effort" : "harness, harness version, or effort";
      document.getElementById("notes").innerHTML = [
        `A dashed line marks a change of ${within}. The baseline is the sessions before the latest change in the window, not a rolling average, so a regression keeps showing instead of being absorbed.`,
        `A signal is flagged (!) when its average since the change is ${S.rate_threshold_pts} or more points higher for rates, or ${S.count_threshold} or more higher for counts, with at least ${S.min_sessions} sessions on each side.`,
        `The "held steady" sentence appears when another ${state.by} has ${S.control_min_sessions}+ sessions before and after the change and its own signal stayed within the threshold.`,
        `Tool use is read from each host's own session record and grouped into families (read, search, shell, edit, web, subagent, plan, skill, one per MCP server). Only names are kept, never arguments.`,
        `These come from your real work, not a controlled test: harder tasks look like a worse assistant.`,
        `The same numbers are in the terminal with <code>vibe-learn health</code>. <code>vibe-learn health --save --redact</code> writes a markdown report you can share.`,
      ].map(n => `<li>${n}</li>`).join("");
    }

    function syncButtons() {
      document.querySelectorAll("[data-control]").forEach(group => {
        group.querySelectorAll("button").forEach(b => b.classList.toggle("active", b.dataset.value === state[group.dataset.control]));
      });
    }

    function render() { syncButtons(); renderCallouts(); renderChart(); renderTable(); renderUsage(); renderStatus(); renderNotes(); }

    document.querySelectorAll("[data-control]").forEach(group => group.addEventListener("click", e => {
      const b = e.target.closest("button");
      if (!b) return;
      state[group.dataset.control] = b.dataset.value;
      render();
    }));

    const firstFlag = view().series.find(x => x.flags.length);
    if (firstFlag) state.metric = firstFlag.flags[0].metric;
    render();
  </script>
</body>
</html>
EOF
}

if [ -n "$HEALTH_VIEWS" ]; then
  HEALTH_FLAGS="$(printf '%s' "$HEALTH_VIEWS" | jq -r '.views["harness|14"].flags_total // 0')"
  HEALTH_NAV="
      <a href=\"#health\">Assistant health <span class=\"nbadge\">$HEALTH_FLAGS</span></a>"
  HEALTH_SECTION="$(printf '%s' "$HEALTH_VIEWS" | jq -r "$HEALTH_CARD_JQ")"
  HEALTH_INDEX_ROW="
        <div class=\"stat-row\"><span class=\"stat-label\"><a href=\"health.html\">Assistant health</a></span><span class=\"stat-value $([ "$HEALTH_FLAGS" -gt 0 ] && echo "danger" || echo "ok")\">$HEALTH_FLAGS flagged</span></div>"
  write_health_page
else
  rm -f "$HEALTH_PAGE"
fi

render_ledger_study_items() {
  local label status quizzed cls when
  while IFS="$(printf '\t')" read -r label status quizzed; do
    [ -z "${label:-}" ] && continue
    cls=""
    [ "$status" = "shaky" ] && cls=" priority"
    if [ "$quizzed" = "never" ]; then when="never quizzed"; else when="last quizzed $quizzed"; fi
    printf '<label class="study-item%s"><input type="checkbox"><span>&ldquo;%s&rdquo; is marked %s (%s) &mdash; review it before extending this code.</span></label>\n' \
      "$cls" "$(printf '%s' "$label" | html_escape)" "$status" "$(printf '%s' "$when" | html_escape)"
  done <<EOF
$LEDGER_STUDY_ITEMS
EOF
}

DIFF_EXCERPT=""
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  DIFF_EXCERPT="$(git -C "$TARGET_DIR" diff --unified=3 -- . ':(exclude).vibe-learn' 2>/dev/null | head -c 12000 || true)"
fi

if [ -n "$DIFF_EXCERPT" ]; then
  DIFF_RENDERED="$(render_diff_as_html "$DIFF_EXCERPT")"
  DIFF_JSON="$(printf '%s' "$DIFF_EXCERPT" | json_string)"
else
  DIFF_RENDERED='<span class="dc">No git diff excerpt was available when the session briefing was generated.</span>'
  DIFF_JSON='""'
fi

GOAL_HTML="$(printf '%s' "$GOAL" | html_escape)"
SUMMARY_HTML="$(printf '%s' "${PAUSE_SUMMARY:-No pause summary was available.}" | html_escape)"
GOAL_JSON="$(printf '%s' "$GOAL" | json_string)"

cat > "$PACK_FILE" <<EOF
# Session Briefing Source Pack

Project: $PROJECT_NAME
Session date: $SESSION_DATE
Session id: $SESSION_ID
Generated: $NOW_TS
Goal: $GOAL

## What changed

- Files created: $CREATED_COUNT
- Files edited: $EDITED_COUNT
- Files deleted: $DELETED_COUNT
- Commands run: $COMMAND_COUNT
- Failed commands: $FAILURE_COUNT

## Why it matters

This pack is generated from the vibe-learn session log. Use it to understand
what the agent changed, which files deserve inspection, and what you should be
ready to debug or extend.

## Timeline

$(jq -r '
  if .event == "user_prompt" then
    "- Prompt: \(.prompt)"
  elif .event == "tool_use" and .tool == "Bash" then
    "- Command: \(.command // "") (exit \(.context.exit_code // 0))"
  elif .event == "tool_use" then
    "- File \(.action // "changed"): \(.file // "file")"
  else empty end
' "$SESSION_LOG" 2>/dev/null)

## Important files

### Created
$FILES_CREATED

### Edited
$FILES_EDITED

### Deleted
$FILES_DELETED

## Commands and failures

$(printf '%s\n' "$COMMANDS" | awk -F '\t' 'NF {printf "- %s (exit %s)\n", $1, $2}')

## Key code excerpts

\`\`\`diff
$DIFF_EXCERPT
\`\`\`

## Review questions

- What changed in the main execution path?
- Which touched files would I inspect first if the app broke?
- Were tests or build checks run after the changes?
- Did any command fail, and what follow-up does that imply?$KNOWLEDGE_PACK

## Suggested audio framing

Create a maintainer-focused audio overview. Explain what changed, why it
matters, what to inspect first, and what could break. Assume the listener owns
this codebase and needs enough technical depth to support it.$AUDIO_EXTRA
EOF

PACK_TEXT_JSON="$(cat "$PACK_FILE" | json_string)"

FILE_ROWS="$(
  render_file_rows "created" "$FILES_CREATED"
  render_file_rows "edited" "$FILES_EDITED"
  render_file_rows "deleted" "$FILES_DELETED"
)"
COMMAND_ROWS="$(render_command_rows)"
TIMELINE_ROWS="$(render_timeline)"
STUDY_QUEUE="$(render_ledger_study_items; render_study_queue)"

render_index_cards() {
  local skip_old="$LATEST"
  find "$SESSIONS_DIR" -maxdepth 1 -type f -name '*.html' -print | sort -r | while IFS= read -r file; do
    local base href pack_href
    base="$(basename "$file")"
    href="sessions/$base"
    pack_href="exports/${base%.html}-notebooklm-pack.md"
    if [ "$file" = "$SESSION_FILE" ]; then
      cat <<CARD
        <article class="card" data-failures="${FAILURE_COUNT:-0}" data-has-pack="true">
          <div class="card-meta">
            <span class="tag">$SESSION_DATE</span>
            <span class="tag">$FILES_TOTAL files</span>
            <span class="tag">$COMMAND_COUNT commands</span>
            $FAILURE_TAG
          </div>
          <h3 class="card-title">$SESSION_SLUG</h3>
          <p class="card-goal">$GOAL_HTML</p>
          <div class="actions">
            <a class="button primary" href="$href">Open briefing</a>
            <a class="button" href="$pack_href" download>Audio pack</a>
          </div>
        </article>
CARD
    elif [ "$skip_old" = "false" ]; then
      local title
      title="$(printf '%s' "${base%.html}" | html_escape)"
      cat <<CARD
        <article class="card" data-failures="unknown" data-has-pack="unknown">
          <div class="card-meta">
            <span class="tag">previously generated</span>
          </div>
          <h3 class="card-title">$title</h3>
          <p class="card-goal">Previously generated session briefing.</p>
          <div class="actions">
            <a class="button primary" href="$href">Open briefing</a>
          </div>
        </article>
CARD
    fi
  done
}

cat > "$SESSION_FILE" <<'STYLE_BLOCK'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
STYLE_BLOCK

cat >> "$SESSION_FILE" <<EOF
  <title>vibe-learn — $PROJECT_NAME — $SESSION_DATE</title>
EOF

cat >> "$SESSION_FILE" <<'STYLE_BLOCK'
  <style>
    :root{
      --bg:#faf9f5; --surface:#f1efe7; --surface-2:#e8e6dc;
      --text:#141413; --muted:#706f68; --line:#d8d4c8;
      --accent:#d97757; --accent-blue:#6a9bcc; --accent-green:#788c5d;
      --danger:#9f3d32; --warning:#b5792a; --success:#617a4b;
      --radius:8px; --shadow:0 1px 3px rgba(20,20,19,.1);
    }
    *{box-sizing:border-box;}
    body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 Lora,Georgia,serif;overflow-x:hidden;}
    a{color:var(--accent-blue);text-decoration:none;}
    a:hover{text-decoration:underline;}
    code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;}
    h1,h2,h3,h4{font-family:Poppins,Arial,sans-serif;font-weight:700;line-height:1.15;margin:0 0 12px;}
    h1{font-size:clamp(22px,3vw,36px);}
    h2{font-size:20px;border-bottom:1px solid var(--line);padding-bottom:8px;margin-bottom:20px;}
    h3{font-size:15px;}
    p{margin:0 0 10px;}
    strong.tl-type{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;}

    /* Site header */
    .site-header{background:var(--surface);border-bottom:1px solid var(--line);padding:20px 32px;display:flex;justify-content:space-between;align-items:flex-start;gap:24px;flex-wrap:wrap;}
    .header-left .eyebrow{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:var(--muted);margin-bottom:6px;letter-spacing:.03em;}
    .header-left .eyebrow a{color:var(--muted);}
    .header-left .eyebrow a:hover{color:var(--text);text-decoration:none;}
    .header-left .goal{color:var(--muted);font-size:14px;margin:4px 0 0;overflow-wrap:anywhere;word-break:break-word;}

    /* Two-column layout */
    .layout{display:grid;grid-template-columns:190px minmax(0,1fr);gap:40px;max-width:1180px;margin:0 auto;padding:32px;}
    .layout>*{min-width:0;}

    /* Sticky nav */
    nav{position:sticky;top:24px;align-self:start;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;display:grid;gap:2px;}
    nav a{display:flex;justify-content:space-between;align-items:center;padding:7px 10px;border-radius:6px;color:var(--muted);transition:background .1s,color .1s;}
    nav a:hover,nav a.active{background:var(--surface-2);color:var(--text);text-decoration:none;}
    nav .nbadge{background:var(--surface-2);border-radius:999px;padding:1px 6px;font-size:10px;min-width:18px;text-align:center;}
    nav a.active .nbadge{background:var(--accent);color:#fff;}

    /* Sections */
    section{margin-bottom:40px;scroll-margin-top:24px;}

    /* Buttons */
    .actions{display:flex;gap:8px;flex-wrap:wrap;}
    button,.button{border:1px solid var(--line);background:var(--surface);color:var(--text);border-radius:var(--radius);padding:8px 14px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;text-decoration:none;cursor:pointer;box-shadow:var(--shadow);transition:background .1s,color .1s;}
    button:hover,.button:hover{background:var(--surface-2);}
    button.primary,.button.primary{background:var(--accent);border-color:var(--accent);color:#fff;}
    button.primary:hover,.button.primary:hover{opacity:.9;}

    /* Overview / Session brief */
    .brief-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:16px;}
    .brief-card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:16px 18px;box-shadow:var(--shadow);}
    .brief-card h3{font-size:11px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);margin-bottom:10px;}
    .brief-card .bvalue{font-size:28px;font-weight:700;font-family:Poppins,Arial,sans-serif;line-height:1;margin-bottom:6px;}
    .brief-card .bvalue.ok{color:var(--success);}
    .brief-card .bvalue.warn{color:var(--warning);}
    .brief-card .bvalue.danger{color:var(--danger);}
    .brief-card .bdetail{font-size:13px;color:var(--muted);line-height:1.4;}
    .summary-panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:18px 22px;font-size:14px;line-height:1.7;white-space:pre-wrap;word-break:break-word;overflow-wrap:anywhere;max-height:320px;overflow-y:auto;}

    /* Timeline */
    .filters{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:14px;}
    .filters button{padding:5px 11px;font-size:11px;}
    .filters button.active{background:var(--accent);border-color:var(--accent);color:#fff;}
    ol.timeline{list-style:none;padding:0;margin:0;display:grid;gap:8px;}
    ol.timeline li{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:11px 14px;display:flex;gap:12px;align-items:flex-start;}
    ol.timeline li p{margin:4px 0 0;color:var(--muted);font-size:13px;overflow-wrap:anywhere;word-break:break-word;}
    .dot{flex-shrink:0;width:10px;height:10px;border-radius:999px;margin-top:3px;background:var(--accent);}
    .dot.command{background:var(--accent-blue);}
    .dot.file{background:var(--accent-green);}
    .tl-body{min-width:0;flex:1;}

    /* File tour */
    ul.list{list-style:none;padding:0;margin:0;display:grid;gap:6px;}
    .file-row{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:9px 14px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;min-width:0;max-width:100%;}
    .fpath{flex:1 1 auto;min-width:0;overflow-wrap:anywhere;word-break:break-word;}
    .pill{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:10px;border-radius:999px;padding:2px 7px;border:1px solid;white-space:nowrap;}
    .pill.action-created{background:#e8f0e1;color:var(--success);border-color:#c8d8b8;}
    .pill.action-edited{background:#e8eef5;color:#4a7aa8;border-color:#c0d0e0;}
    .pill.action-deleted{background:#fde8e4;color:var(--danger);border-color:#f0c8c0;}
    .area{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:10px;border-radius:4px;padding:2px 6px;border:1px solid;white-space:nowrap;}
    .area-tests{background:#e8f0e1;color:var(--success);border-color:#c8d8b8;}
    .area-adapter{background:#e8eef5;color:#4a7aa8;border-color:#c0d0e0;}
    .area-script{background:#f3ede0;color:#8a6830;border-color:#ddd0b0;}
    .area-config{background:#ece7f0;color:#6a4a88;border-color:#ccc0d8;}
    .area-docs{background:var(--surface-2);color:var(--muted);border-color:var(--line);}
    .area-auth{background:#fde8e4;color:var(--danger);border-color:#f0c8c0;}
    .area-database{background:#e4f0e8;color:#4a7a3d;border-color:#b8d8c0;}
    .area-source{background:var(--surface);color:var(--muted);border-color:var(--line);}

    /* Command log */
    .command-row{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:9px 14px;display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;min-width:0;max-width:100%;}
    .command-row.fail{border-color:rgba(159,61,50,.4);background:#f8ece9;}
    .cmd-text{flex:1 1 auto;min-width:0;overflow-wrap:anywhere;word-break:break-word;}
    .status{flex-shrink:0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:10px;border-radius:999px;padding:2px 7px;border:1px solid var(--line);background:var(--surface-2);}
    .fail .status{color:var(--danger);border-color:rgba(159,61,50,.35);background:#fde8e4;}
    .ok .status{color:var(--success);border-color:#c8d8b8;background:#e8f0e1;}

    /* Code excerpts */
    .diff-wrapper{position:relative;}
    .diff-toolbar{display:flex;justify-content:flex-end;margin-bottom:8px;}
    pre{white-space:pre;overflow-x:auto;background:#1e1c18;color:#e8e4d8;border-radius:var(--radius);padding:18px;max-height:560px;overflow-y:auto;margin:0;font-size:12px;line-height:1.55;tab-size:2;}
    pre .dh{color:#6a6860;display:block;}
    pre .dk{color:#6a9bcc;display:block;font-weight:600;}
    pre .da{color:#7db368;display:block;background:rgba(90,138,74,.13);}
    pre .dd{color:#c07070;display:block;background:rgba(192,80,80,.12);}
    pre .dc{color:#c8c4b4;display:block;}

    /* Study queue */
    .study-list{display:grid;gap:8px;}
    .study-item{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:12px 16px;display:flex;gap:12px;align-items:flex-start;cursor:pointer;font-size:14px;transition:background .1s;}
    .study-item:hover{background:var(--surface-2);}
    .study-item input[type=checkbox]{width:15px;height:15px;flex-shrink:0;margin-top:2px;accent-color:var(--accent);}
    .study-item.priority{border-left:3px solid var(--warning);padding-left:13px;}
    .study-item span{line-height:1.55;overflow-wrap:anywhere;}

    /* Audio export */
    .pack-preview{max-height:320px;font-size:11.5px;}
    .export-intro{font-size:14px;color:var(--muted);margin-bottom:14px;}

    /* Responsive */
    @media(max-width:840px){
      .site-header{padding:16px 20px;}
      .layout{display:block;padding:20px;}
      nav{position:static;display:flex;flex-wrap:wrap;gap:4px;margin-bottom:24px;}
      nav a{flex:0 0 auto;}
      .brief-grid{grid-template-columns:1fr 1fr;}
    }
    @media(max-width:520px){
      .brief-grid{grid-template-columns:1fr;}
      .command-row{display:block;}
      .status{display:inline-block;margin-top:6px;}
    }
  </style>
</head>
STYLE_BLOCK

cat >> "$SESSION_FILE" <<EOF
<body>
  <header class="site-header">
    <div class="header-left">
      <div class="eyebrow"><a href="../index.html">vibe-learn</a> / $PROJECT_NAME / $SESSION_DATE</div>
      <h1>Session briefing</h1>
      <p class="goal">$GOAL_HTML</p>
    </div>
    <div class="actions">
      <a class="button primary" href="../exports/$(basename "$PACK_FILE")" download>NotebookLM pack</a>
      <button type="button" data-copy-pack>Copy source pack</button>
      <button type="button" data-copy-prompt>Copy audio prompt</button>
      <a class="button" href="../index.html">← Index</a>
    </div>
  </header>
  <div class="layout">
    <nav aria-label="Sections">
      <a href="#overview">Session brief</a>$HEALTH_NAV
      <a href="#timeline">Timeline <span class="nbadge" id="tl-count"></span></a>
      <a href="#files">Files <span class="nbadge">$FILES_TOTAL</span></a>
      <a href="#commands">Commands <span class="nbadge">$COMMAND_COUNT</span></a>
      <a href="#code">Code excerpts</a>
      <a href="#study">Study queue</a>$KNOWLEDGE_NAV
      <a href="#audio">Audio export</a>
    </nav>
    <main>

      <section id="overview">
        <h2>Session brief</h2>
        <div class="brief-grid">
          <div class="brief-card">
            <h3>What changed</h3>
            <div class="bvalue">$FILES_TOTAL</div>
            <div class="bdetail">$CREATED_COUNT created · $EDITED_COUNT edited · $DELETED_COUNT deleted</div>
          </div>
          <div class="brief-card">
            <h3>Why it matters</h3>
            <div class="bdetail" style="margin-top:4px;">These files shape the parts of the system you may need to debug, extend, or support.</div>
          </div>
          <div class="brief-card">
            <h3>Inspect first</h3>
            <div class="bdetail" style="margin-top:4px;">Adapter, script, config, auth, db, and test files — in that order.</div>
          </div>
          <div class="brief-card">
            <h3>What could break</h3>
            <div class="bvalue $([ "${FAILURE_COUNT:-0}" -gt 0 ] && echo "danger" || echo "ok")">$FAILURE_COUNT</div>
            <div class="bdetail">$([ "${FAILURE_COUNT:-0}" -gt 0 ] && printf "failed command(s) — inspect first" || printf "no failures detected")</div>
          </div>
        </div>
        <div class="summary-panel">$SUMMARY_HTML</div>
      </section>$HEALTH_SECTION

      <section id="timeline">
        <h2>Session Timeline</h2>
        <div class="filters">
          <button type="button" class="active" data-filter="all">All</button>
          <button type="button" data-filter="file">Files</button>
          <button type="button" data-filter="command">Commands</button>
          <button type="button" data-filter="prompt">Prompts</button>
        </div>
        <ol class="timeline" data-timeline>$TIMELINE_ROWS</ol>
      </section>

      <section id="files">
        <h2>File Tour</h2>
        <ul class="list">$FILE_ROWS</ul>
      </section>

      <section id="commands">
        <h2>Command Log</h2>
        <ul class="list">$COMMAND_ROWS</ul>
      </section>

      <section id="code">
        <h2>Code Excerpts</h2>
        <div class="diff-wrapper">
          <div class="diff-toolbar">
            <button type="button" data-copy-diff>Copy diff</button>
          </div>
          <pre id="diff-pre">$DIFF_RENDERED</pre>
        </div>
      </section>

      <section id="study">
        <h2>Study Queue</h2>
        <div class="study-list">$STUDY_QUEUE</div>
      </section>$KNOWLEDGE_SECTION

      <section id="audio">
        <h2>Audio Export</h2>
        <p class="export-intro">Upload the source pack to NotebookLM to generate a maintainer-focused audio overview — no setup required.</p>
        <div class="actions" style="margin-bottom:14px;">
          <a class="button primary" href="../exports/$(basename "$PACK_FILE")" download>Download NotebookLM pack</a>
          <button type="button" data-copy-pack>Copy source pack</button>
          <button type="button" data-copy-prompt>Copy audio prompt</button>
        </div>
        <pre class="pack-preview">$(cat "$PACK_FILE" | html_escape)</pre>
      </section>

    </main>
  </div>
  <script>
    const packText = $PACK_TEXT_JSON;
    const diffText = $DIFF_JSON;
    const audioPrompt = "Create a maintainer-focused audio overview. Explain what changed, why it matters, what to inspect first, and what could break. Assume the listener owns this codebase and needs enough technical depth to support it.$AUDIO_EXTRA_JS";

    function copyText(text, button) {
      if (!text) return;
      navigator.clipboard?.writeText(text).then(() => {
        const old = button.textContent;
        const oldBg = button.style.background;
        button.textContent = "Copied!";
        button.style.background = "var(--accent-green)";
        button.style.color = "#fff";
        button.style.borderColor = "var(--accent-green)";
        setTimeout(() => {
          button.textContent = old;
          button.style.background = oldBg;
          button.style.color = "";
          button.style.borderColor = "";
        }, 1400);
      });
    }

    document.querySelectorAll("[data-copy-pack]").forEach(b => b.addEventListener("click", () => copyText(packText, b)));
    document.querySelectorAll("[data-copy-prompt]").forEach(b => b.addEventListener("click", () => copyText(audioPrompt, b)));
    document.querySelectorAll("[data-copy-diff]").forEach(b => b.addEventListener("click", () => copyText(diffText, b)));

    const tlItems = document.querySelectorAll("[data-timeline] li");
    const tlCount = document.getElementById("tl-count");
    if (tlCount) tlCount.textContent = tlItems.length;

    document.querySelectorAll("[data-filter]").forEach(btn => {
      btn.addEventListener("click", () => {
        document.querySelectorAll("[data-filter]").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        const f = btn.dataset.filter;
        tlItems.forEach(li => { li.hidden = f !== "all" && li.dataset.kind !== f; });
      });
    });

    const sections = document.querySelectorAll("section[id]");
    const navLinks = document.querySelectorAll("nav a[href^='#']");
    const obs = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting)
          navLinks.forEach(a => a.classList.toggle("active", a.getAttribute("href") === "#" + e.target.id));
      });
    }, { rootMargin: "-20% 0px -65% 0px" });
    sections.forEach(s => obs.observe(s));
  </script>
</body>
</html>
EOF

INDEX_CARDS="$(render_index_cards)"

cat > "$INDEX_FILE" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>vibe-learn — $PROJECT_NAME</title>
  <style>
    :root{--bg:#faf9f5;--surface:#f1efe7;--surface-2:#e8e6dc;--text:#141413;--muted:#706f68;--line:#d8d4c8;--accent:#d97757;--accent-blue:#6a9bcc;--danger:#9f3d32;--success:#617a4b;--radius:8px;--shadow:0 1px 3px rgba(20,20,19,.1);}
    *{box-sizing:border-box;}
    body{margin:0;overflow-x:hidden;background:var(--bg);color:var(--text);font:16px/1.6 Lora,Georgia,serif;}
    a{color:var(--accent-blue);text-decoration:none;}
    a:hover{text-decoration:underline;}
    h1,h2,h3{font-family:Poppins,Arial,sans-serif;font-weight:700;line-height:1.15;margin:0 0 10px;}
    p{margin:0 0 8px;}
    .muted{color:var(--muted);}
    .site-header{background:var(--surface);border-bottom:1px solid var(--line);padding:28px 40px;}
    .site-header h1{font-size:36px;margin-bottom:4px;}
    .site-header p{color:var(--muted);font-size:15px;}
    .layout{display:grid;grid-template-columns:220px minmax(0,1fr);gap:32px;max-width:1100px;margin:0 auto;padding:36px 40px;}
    .layout>*{min-width:0;}
    .sidebar-panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:20px;position:sticky;top:24px;max-width:100%;}
    .sidebar-heading{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);margin-bottom:14px;}
    .stat-row{display:flex;justify-content:space-between;align-items:baseline;padding:7px 0;border-bottom:1px solid var(--line);}
    .stat-row:last-child{border:none;padding-bottom:0;}
    .stat-label{font-size:13px;color:var(--muted);}
    .stat-value{font-size:14px;font-weight:700;font-family:Poppins,Arial,sans-serif;overflow-wrap:anywhere;word-break:break-word;text-align:right;max-width:120px;}
    .stat-value.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;}
    .stat-value.danger{color:var(--danger);}
    .stat-value.ok{color:var(--success);}
    .cards{display:grid;gap:14px;}
    .card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:20px 24px;box-shadow:var(--shadow);min-width:0;max-width:100%;transition:border-color .15s,box-shadow .15s;}
    .card:hover{border-color:rgba(217,119,87,.5);box-shadow:0 2px 10px rgba(217,119,87,.12);}
    .card-meta{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px;}
    .tag{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;border-radius:4px;padding:2px 7px;background:var(--surface-2);border:1px solid var(--line);color:var(--muted);white-space:nowrap;}
    .tag.danger{background:#fde8e4;color:var(--danger);border-color:#f0c8c0;}
    .card-title{font-size:15px;margin-bottom:6px;overflow-wrap:anywhere;word-break:break-word;}
    .card-goal{font-size:13px;color:var(--muted);margin-bottom:16px;overflow-wrap:anywhere;word-break:break-word;line-height:1.5;}
    .actions{display:flex;gap:8px;flex-wrap:wrap;}
    .button{border:1px solid var(--line);border-radius:var(--radius);padding:8px 14px;color:var(--text);text-decoration:none;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;background:var(--surface);box-shadow:var(--shadow);transition:background .1s;}
    .button:hover{background:var(--surface-2);text-decoration:none;}
    .button.primary{background:var(--accent);border-color:var(--accent);color:#fff;}
    .button.primary:hover{opacity:.9;}
    .section-heading{font-size:18px;margin-bottom:16px;}
    @media(max-width:760px){
      .site-header{padding:20px 24px;}
      .site-header h1{font-size:28px;}
      .layout{display:block;padding:20px 24px;}
      .sidebar-panel{position:static;margin-bottom:24px;}
    }
  </style>
</head>
<body>
  <header class="site-header">
    <h1>vibe-learn</h1>
    <p>Session briefings from your agent-built sessions &mdash; $PROJECT_NAME</p>
  </header>
  <div class="layout">
    <aside>
      <div class="sidebar-panel">
        <div class="sidebar-heading">This project</div>
        <div class="stat-row"><span class="stat-label">Project</span><span class="stat-value mono">$PROJECT_NAME</span></div>
        <div class="stat-row"><span class="stat-label">Latest</span><span class="stat-value mono">$SESSION_DATE</span></div>
        <div class="stat-row"><span class="stat-label">Files</span><span class="stat-value">$FILES_TOTAL</span></div>
        <div class="stat-row"><span class="stat-label">Commands</span><span class="stat-value">$COMMAND_COUNT</span></div>
        <div class="stat-row"><span class="stat-label">Failures</span><span class="stat-value $([ "${FAILURE_COUNT:-0}" -gt 0 ] && echo "danger" || echo "ok")">$FAILURE_COUNT</span></div>
        <div class="stat-row"><span class="stat-label">Audio pack</span><span class="stat-value ok">yes</span></div>$HEALTH_INDEX_ROW
      </div>
    </aside>
    <section>
      <h2 class="section-heading">Recent Sessions</h2>
      <div class="cards">
        $INDEX_CARDS
      </div>
    </section>
  </div>
</body>
</html>
EOF

echo "Session briefing index:  $INDEX_FILE"
echo "Session briefing:        $SESSION_FILE"
echo "NotebookLM pack:         $PACK_FILE"
