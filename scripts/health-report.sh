#!/bin/bash
# health-report.sh — `vibe-learn health`: compare recent sessions against the
# baseline before the latest harness / model / effort change.
#
# Usage:
#   vibe-learn health [target-dir] [--days=14|all] [--by=harness|model] [--all]
#                     [--json] [--save] [--redact]
#
#   --days=N    window of sessions to compare (default 14; "all" for no limit)
#   --by=K      group sessions by harness (default) or by model
#   --all       pool ~/.vibe-learn/health.jsonl across projects
#   --json      print the computed view as JSON instead of text
#   --save      also write .vibe-learn/health-reports/<date>-health.md
#   --redact    replace project names with project-1, project-2, ...
#
# Reads .vibe-learn/health.jsonl (or the global log with --all) plus the
# session in progress, computed on the fly by health.sh. Read-only apart from
# --save. Session signals are hints, not proof.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_DIR=""
DAYS=14
BY=harness
ALL=false
FORMAT=text
SAVE=false
REDACT=false

for arg in "$@"; do
  case "$arg" in
    --days=*) DAYS="${arg#--days=}" ;;
    --by=*) BY="${arg#--by=}" ;;
    --all) ALL=true ;;
    --json) FORMAT=json ;;
    --views) FORMAT=views ;;  # every by x window combination, for briefing.sh
    --save) SAVE=true ;;
    --redact) REDACT=true ;;
    --help|-h)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown health flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$arg"
      else
        echo "ERROR: health accepts at most one target directory." >&2
        exit 1
      fi
      ;;
  esac
done

case "$DAYS" in
  all) ;;
  ''|*[!0-9]*|0)
    echo "ERROR: --days must be a positive integer or 'all' (got '${DAYS}')." >&2
    exit 1
    ;;
esac
case "$BY" in
  harness|model) ;;
  *)
    echo "ERROR: --by must be 'harness' or 'model' (got '${BY}')." >&2
    exit 1
    ;;
esac

TARGET_DIR="${TARGET_DIR:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
LOG_DIR="$TARGET_DIR/.vibe-learn"
GLOBAL_HOME="$HOME/.vibe-learn"
PROJECT_NAME="$(basename "$TARGET_DIR")"
TODAY="$(date +%Y-%m-%d)"

cutoff_for() {
  # $1: days. Window is the last N days inclusive of today; GNU date, then BSD.
  date -d "-$(($1 - 1)) days" +%Y-%m-%d 2>/dev/null || date -v "-$(($1 - 1))d" +%Y-%m-%d
}
CUTOFF=""
[ "$DAYS" = "all" ] || CUTOFF="$(cutoff_for "$DAYS")"
CUTOFF_14="$(cutoff_for 14)"

# Settings: defaults, then ~/.vibe-learn/config.json, then the project's config.json.
CONFIG_FILES=()
for f in "$GLOBAL_HOME/config.json" "$LOG_DIR/config.json"; do
  [ -f "$f" ] && CONFIG_FILES+=("$f")
done
SETTINGS='{}'
if [ "${#CONFIG_FILES[@]}" -gt 0 ]; then
  SETTINGS="$(jq -cn '[inputs | objects | .health | objects] | add // {}' "${CONFIG_FILES[@]}" 2>/dev/null || echo '{}')"
fi

if [ "$ALL" = true ]; then
  HISTORY="$GLOBAL_HOME/health.jsonl"
else
  HISTORY="$LOG_DIR/health.jsonl"
fi

CURRENT_ROWS=""
if [ -d "$LOG_DIR" ]; then
  CURRENT_ROWS="$(bash "$SCRIPT_DIR/health.sh" "$LOG_DIR" 2>/dev/null || true)"
fi

HISTORY_ROWS=""
if [ -s "$HISTORY" ]; then
  HISTORY_ROWS="$(cat "$HISTORY")"
fi

# render FORMAT — FORMAT is text, markdown, json, or views.
render() {
  {
    printf '%s\n' "$HISTORY_ROWS" | jq -Rc 'fromjson? | objects | {current: false, row: .}'
    printf '%s\n' "$CURRENT_ROWS" | jq -Rc 'fromjson? | objects | {current: true, row: .}'
  } | jq -rn \
    --arg format "$1" \
    --arg by "$BY" \
    --arg days "$DAYS" \
    --arg cutoff "$CUTOFF" \
    --arg cutoff14 "$CUTOFF_14" \
    --arg project "$PROJECT_NAME" \
    --arg scope "$([ "$ALL" = true ] && echo all || echo project)" \
    --arg today "$TODAY" \
    --argjson redact "$REDACT" \
    --argjson user_settings "$SETTINGS" '
  ({min_events: 5, min_sessions: 5, rate_threshold_pts: 10, count_threshold: 2, control_min_sessions: 3}
    + ($user_settings | with_entries(select(.value | type == "number")))) as $s

  | def mkeys: ["bash_fail_rate", "rework_rate", "events_per_prompt", "turns_to_green"];
    def mname($k): {bash_fail_rate: "bash failure rate", rework_rate: "rework rate",
                    events_per_prompt: "events per prompt", turns_to_green: "turns to green"}[$k];
    def is_rate($k): $k == "bash_fail_rate" or $k == "rework_rate";
    def thr($k): if is_rate($k) then $s.rate_threshold_pts / 100 else $s.count_threshold end;
    def one_decimal: (. * 10 | round) / 10 | tostring | if test("\\.") then . else . + ".0" end;
    def fmt($k; $v): if $v == null then "-" elif is_rate($k) then "\($v * 100 | round)%" else ($v | one_decimal) end;
    def fmt_delta($k; $d): (if $d >= 0 then "+" else "" end)
      + (if is_rate($k) then "\($d * 100 | round) pts" else ($d | one_decimal) end);
    def mean_of($k): [.[] | .metrics[$k] | numbers] | if length == 0 then null else add / length end;
    def count_of($k): [.[] | .metrics[$k] | numbers] | length;
    def means: . as $rows | reduce mkeys[] as $k ({}; .[$k] = ($rows | mean_of($k)));
    def day_label: (.[5:7] | tonumber) as $m | (.[8:10] | tonumber) as $d
      | "\(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][$m - 1]) \($d)";
    def lpad($n): tostring | if length >= $n then . else (" " * ($n - length)) + . end;
    def rpad($n): tostring | if length >= $n then . else . + (" " * ($n - length)) end;

    def cfg_fields($by): if $by == "harness" then ["harness_version", "model", "effort"]
                         else ["harness", "harness_version", "effort"] end;
    def series_key($by): (if $by == "harness" then .harness else .model end) // "unknown";
    # Carry each identity field forward so a missing value never looks like a change.
    def with_cfg($by): cfg_fields($by) as $f
      | [foreach .[] as $r ({};
          reduce $f[] as $k (.; if $r[$k] != null then .[$k] = $r[$k] else . end);
          $r + {_cfg: .})];
    def changed($a; $b; $by): any(cfg_fields($by)[]; $a[.] != null and $b[.] != $a[.]);
    def period_label($by; $key): if $by == "harness" then ([$key, ._cfg.harness_version] | map(select(. != null)) | join(" ")) else $key end;
    def period_sub($by; $eff): (if $by == "harness" then [._cfg.model] else [([._cfg.harness, ._cfg.harness_version] | map(select(. != null)) | join(" "))] end)
      + [(._cfg.effort | if . and $eff then "effort \(.)" else null end)]
      | map(select(. != null and . != "")) | join(" · ");
    def change_text($a; $b; $by): [cfg_fields($by)[] as $k | select($a[$k] != null and $b[$k] != $a[$k])
      | if $k == "effort" then "effort \($a[$k]) → \($b[$k])" else "\($a[$k]) → \($b[$k])" end] | join(", ");

    def analyze_series($by; $eff; $key; $rows):
      ($rows | with_cfg($by)) as $r
      | [range(1; $r | length) | select(changed($r[. - 1]._cfg; $r[.]._cfg; $by))] as $marks
      | ($marks | last) as $m
      | ([0] + $marks) as $starts
      | [range(0; $starts | length) as $i | $r[$starts[$i]:($starts[$i + 1] // ($r | length))]] as $chunks
      | (if $m == null then $r else $r[:$m] end | map(select(.eligible))) as $base
      | (if $m == null then [] else $r[$m:] end | map(select(.eligible))) as $since
      | [mkeys[] as $k
          | select($m != null and ($base | count_of($k)) >= $s.min_sessions and ($since | count_of($k)) >= $s.min_sessions)
          | ($base | mean_of($k)) as $b | ($since | mean_of($k)) as $a
          | select($a - $b >= thr($k) - 1e-9)
          | {metric: $k, before: $b, after: $a, delta: ($a - $b)}] as $flags
      | {
          key: $key,
          sessions: ($r | length),
          periods: [$chunks[] | {
            label: (.[-1] | period_label($by; $key)),
            sub: (.[-1] | period_sub($by; $eff)),
            from: .[0].started_at, to: .[-1].started_at,
            sessions: length,
            eligible: (map(select(.eligible)) | length),
            means: (map(select(.eligible)) | means),
            latest: false
          }] | (if length > 0 and $m != null then .[-1].latest = true else . end),
          marker: (if $m == null then null else {
            at: $r[$m].started_at,
            label: ($r[$m] | period_label($by; $key)),
            sub: ($r[$m] | period_sub($by; $eff)),
            change: change_text($r[$m - 1]._cfg; $r[$m]._cfg; $by)
          } end),
          baseline: {sessions: ($base | length), means: ($base | means)},
          since: {sessions: ($since | length), means: ($since | means)},
          flags: $flags,
          status: (if ($flags | length) > 0 then "flagged"
                   elif ($base | length) < $s.min_sessions then "building"
                   elif $m != null and ($since | length) < $s.min_sessions then "waiting"
                   else "steady" end),
          points: [$r[] | {t: .started_at, period: period_label($by; $key), sub: period_sub($by; $eff),
                           project: .project, eligible, m: (.metrics | {bash_fail_rate, rework_rate, events_per_prompt, turns_to_green})}]
        };

    def analyze($rows; $by; $cutoff):
      ($rows | map(select(.current | not) | select($cutoff == "" or (.started_at // "")[0:10] >= $cutoff))) as $done
      # Effort is only worth a label when it varies within the window.
      | ($done | map(.effort) | unique | length > 1) as $eff
      | ($done | group_by(series_key($by)) | map(. as $g | analyze_series($by; $eff; $g[0] | series_key($by); $g | sort_by(.started_at // "", .segment.index // 1)))) as $series
      | ($series | map(select(.status == "flagged") | . as $fs
          | ($fs.flags[0].metric) as $lead
          | ([$done[] | select(series_key($by) != $fs.key and .eligible and (.started_at // "") >= $fs.marker.at)]
              | group_by(series_key($by))
              | map(select(length >= $s.control_min_sessions)
                  | {key: (.[0] | series_key($by)), sessions: length, value: mean_of($lead), rows: .}
                  | select(.value != null and ((.value - $fs.baseline.means[$lead]) | fabs) < thr($lead)))
              | sort_by(-.sessions) | first) as $c
          | {key: $fs.key, control: (if $c == null then null else
              ($c.rows | with_cfg($by) | .[-1]) as $last
              | {key: $c.key, label: ($last | period_label($by; $c.key)), sub: ($last | period_sub($by; $eff)),
                 metric: $lead, value: $c.value, sessions: $c.sessions} end)})
          | map({key: .key, value: .control}) | from_entries) as $controls
      | {
          by: $by,
          cutoff: (if $cutoff == "" then null else $cutoff end),
          sessions: ($done | length),
          series: [$series[] | . + {control: $controls[.key]}],
          flags_total: ([$series[].flags[]] | length),
          current: [$rows[] | select(.current) | . as $cur
            | ($series | map(select(.key == ($cur | series_key($by)))) | first) as $cs
            | {series: ($cur | series_key($by)), harness, harness_version, model, effort,
               segment, metrics, eligible,
               usual: ($cs.baseline // null),
               flags: ([($cs.flags // [])[].metric])}]
        };

    # Rows: history plus the session in progress (minus any segment already saved).
    [inputs] as $input
    | ($input | map(select(.current | not) | .row | "\(.session_id)#\(.segment.index // 1)")) as $saved
    | ($input | map(select(.current | not) | .row | .project) + [$project] | map(select(. != null)) | unique) as $projects
    | ($projects | sort_by(. as $p | ($input | map(.row.project) | index($p)) // -1) | to_entries
        | map({key: .value, value: "project-\(.key + 1)"}) | from_entries) as $redaction
    | def redact_project: if $redact and . != null then ($redaction[.] // "project") else . end;
    ($input
      | map(select(.current == false or ((.row | "\(.session_id)#\(.segment.index // 1)") as $id | $saved | index($id) | not)))
      | map(.row + {current: .current,
                    project: ((.row.project // (if .current then $project else null end)) | redact_project),
                    eligible: ((.row.metrics.tool_events // 0) >= $s.min_events)}
            | del(.git_head))) as $all_rows

    | ($project | redact_project) as $shown_project
    | ($days | if . == "all" then null else tonumber end) as $days_n
    | (if $format == "views" then
        {version: 1, project: $shown_project, scope: $scope, generated_at: $today, settings: $s,
         views: {
           "harness|14": analyze($all_rows; "harness"; $cutoff14), "harness|all": analyze($all_rows; "harness"; ""),
           "model|14": analyze($all_rows; "model"; $cutoff14), "model|all": analyze($all_rows; "model"; "")
         }}
       else
        (analyze($all_rows; $by; $cutoff) + {version: 1, project: $shown_project, scope: $scope, days: $days_n, generated_at: $today, settings: $s}) as $v
        | if $format == "json" then $v else

        # ---- Text and markdown renderers ----
        def series_line($x): "\($x.label)" + (if ($x.sub // "") != "" then " (\($x.sub))" else "" end);
        def window_text: if $v.days == null then "all time" else "last \($v.days) days" end;
        def scope_text: if $v.scope == "all" then "all projects" else $v.project end;
        def flagged: [$v.series[] | select(.status == "flagged")];
        def headline($fs): "\(series_line($fs.marker)), since \($fs.marker.at | day_label) (\($fs.marker.change))";
        def control_text($fs): $fs.control as $c | if $c == null then null else
          "\(series_line($c)) held steady over the same days (\(mname($c.metric)) \(fmt($c.metric; $c.value)) vs \(fmt($c.metric; $fs.baseline.means[$c.metric])) before), so the change is a likelier cause than harder tasks." end;
        def status_text($x): if $x.status == "building" then
            "\($x.key): building your baseline, \($x.baseline.sessions) of \($s.min_sessions) sessions with \($s.min_events)+ tool events"
          elif $x.status == "waiting" then
            "\($x.key): changed on \($x.marker.at | day_label) (\($x.marker.change)); \($x.since.sessions) of \($s.min_sessions) sessions since, comparison starts after \($s.min_sessions)"
          else "\($x.key): no signal moved past the threshold since \($x.marker.at | day_label) (\($x.marker.change))" end;
        def table_rows: [$v.series[] | . as $x | $x.periods[] | . as $p
          | {label: ($p.label + (if $p.sub != "" then " · " + $p.sub else "" end)), sessions: $p.sessions,
             cells: [mkeys[] as $k | fmt($k; $p.means[$k]) + (if $p.latest and ([$x.flags[].metric] | index($k)) then " !" else "" end)]}];
        def caveat: "These come from your real work, not a controlled test: harder tasks look like a worse assistant.";
        def current_line: $v.current | if length == 0 then null else .[-1] as $c
          | "Current session (in progress, \($c.series)): " + ([mkeys[] as $k | "\(mname($k)) \(fmt($k; $c.metrics[$k]))"] | join(" · ")) end;

        if $format == "text" then
          (table_rows) as $tr
          | ([$tr[].label | length] + [if $by == "harness" then 7 else 5 end] | max) as $w
          | (["sessions", "bash fail", "rework", "events/prompt", "turns to green"]) as $heads
          | [
              "Assistant health - \(scope_text) - \(window_text) (\($v.sessions) sessions)",
              "",
              (if (flagged | length) > 0 then
                 "Flagged",
                 (flagged[] | . as $fs
                   | "  \(headline($fs)):",
                     ($fs.flags[] | "    \(mname(.metric) | rpad(18)) \(fmt(.metric; .before) | lpad(4)) -> \(fmt(.metric; .after))"),
                     (control_text($fs) | select(. != null) | "  " + .)),
                 ""
               elif ($v.series | length) == 0 then
                 "No finished sessions in this window yet. Rows are added to health.jsonl when the next session starts.", ""
               else
                 "Nothing flagged.", ""
               end),
              ([$v.series[] | select(.status != "flagged" and (.status != "steady" or .marker != null)) | "  " + status_text(.)] | if length > 0 then (.[], "") else empty end),
              (if ($tr | length) > 0 then
                 ("  " + ("" | rpad($w)) + "  " + ([$heads[] | lpad(length)] | join("  "))),
                 ($tr[] | "  " + (.label | rpad($w)) + "  " + ([.sessions, .cells[]] as $c | [range(0; 5) as $i | $c[$i] | lpad($heads[$i] | length)] | join("  "))),
                 ""
               else empty end),
              (current_line | select(. != null)),
              (current_line | select(. != null) | ""),
              caveat
            ] | join("\n")
        else
          [
            "# Assistant health — \(scope_text)",
            "",
            "_\(window_text | .[:1] | ascii_upcase)\(window_text | .[1:]) · \($v.sessions) sessions · generated \($v.generated_at) by [vibe-learn](https://github.com/gkaria/vibe-learn). Session signals are hints, not proof._",
            "",
            (if (flagged | length) > 0 then
               "## Flagged", "",
               (flagged[] | . as $fs
                 | "- **\(headline($fs))**: " + ([$fs.flags[] | "\(mname(.metric)) \(fmt(.metric; .before)) → \(fmt(.metric; .after))"] | join(", ")),
                   (control_text($fs) | select(. != null) | "  - " + .)),
               ""
             else "Nothing flagged.", "" end),
            ([$v.series[] | select(.status != "flagged" and (.status != "steady" or .marker != null)) | "- " + status_text(.)] | if length > 0 then (.[], "") else empty end),
            (table_rows | if length > 0 then
               "## By \($by)", "",
               "| \(if $by == "harness" then "Harness" else "Model" end) | Sessions | Bash failure rate | Rework rate | Events / prompt | Turns to green |",
               "|---|---:|---:|---:|---:|---:|",
               (.[] | "| \(.label) | \(.sessions) | \(.cells | join(" | ")) |"),
               ""
             else empty end),
            "_\(caveat) A `!` marks a signal that rose past the threshold (\($s.rate_threshold_pts) points for rates, \($s.count_threshold) for counts) against the sessions before the latest change, with at least \($s.min_sessions) sessions on each side._"
          ] | join("\n")
        end
      end end)
  '
}

render "$FORMAT"

if [ "$SAVE" = true ]; then
  MARKDOWN="$(render markdown)"
  mkdir -p "$LOG_DIR/health-reports"
  REPORT_FILE="$LOG_DIR/health-reports/$TODAY-health.md"
  printf '%s\n' "$MARKDOWN" > "$REPORT_FILE"
  echo "Saved health report: $REPORT_FILE" >&2
fi
