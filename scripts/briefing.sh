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
- Did any command fail, and what follow-up does that imply?

## Suggested audio framing

Create a maintainer-focused audio overview. Explain what changed, why it
matters, what to inspect first, and what could break. Assume the listener owns
this codebase and needs enough technical depth to support it.
EOF

PACK_TEXT_JSON="$(cat "$PACK_FILE" | json_string)"

FILE_ROWS="$(
  render_file_rows "created" "$FILES_CREATED"
  render_file_rows "edited" "$FILES_EDITED"
  render_file_rows "deleted" "$FILES_DELETED"
)"
COMMAND_ROWS="$(render_command_rows)"
TIMELINE_ROWS="$(render_timeline)"
STUDY_QUEUE="$(render_study_queue)"

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
      <a href="#overview">Session brief</a>
      <a href="#timeline">Timeline <span class="nbadge" id="tl-count"></span></a>
      <a href="#files">Files <span class="nbadge">$FILES_TOTAL</span></a>
      <a href="#commands">Commands <span class="nbadge">$COMMAND_COUNT</span></a>
      <a href="#code">Code excerpts</a>
      <a href="#study">Study queue</a>
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
      </section>

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
      </section>

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
    const audioPrompt = "Create a maintainer-focused audio overview. Explain what changed, why it matters, what to inspect first, and what could break. Assume the listener owns this codebase and needs enough technical depth to support it.";

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
        <div class="stat-row"><span class="stat-label">Audio pack</span><span class="stat-value ok">yes</span></div>
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
