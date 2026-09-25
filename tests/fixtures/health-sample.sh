#!/bin/bash
# health-sample.sh DAY_OFFSET — print the mockup's sample health rows.
#
# Mirrors docs/mockups/assistant-health.html: claude-code moves from 2.4.1 to
# 2.5.0 on the mockup's Sep 22 and three signals rise; codex stays flat over
# the same days. The mockup's Sep 25 is shifted to today minus DAY_OFFSET
# (default 0), so date windows behave the same on any day. Tool use shifts
# toward search after the change, as a regression might.

OFFSET="${1:-0}"

date_for() {
  # $1: days before the mockup's last day (Sep 25)
  local back=$(( $1 + OFFSET ))
  date -u -d "-$back days" +%Y-%m-%d 2>/dev/null || date -u -v "-${back}d" +%Y-%m-%d
}

row() {
  # day harness version model bash% rework% epp ttg
  local d
  d="$(date_for $((25 - $1)))"
  jq -cn --arg d "$d" --arg h "$2" --arg v "$3" --arg m "$4" \
    --argjson b "$5" --argjson r "$6" --argjson e "$7" --argjson t "$8" --arg sid "s$1-$2-$RANDOM" '
    {version: 1, session_id: $sid, segment: {index: 1, count: 1, first_turn: 1, last_turn: 6},
     started_at: "\($d)T10:00:00Z", ended_at: "\($d)T11:00:00Z",
     harness: $h, harness_version: $v, model: $m, effort: "high", git_head: "abc1234",
     metrics: {prompts: 6, turns: 6, tool_events: 40, events_per_prompt: $e,
               bash_runs: 20, bash_failures: 0, bash_fail_rate: ($b / 100),
               failed_file_ops: 0, files_touched: 10, files_reworked: 1, rework_rate: ($r / 100),
               check_runs: 4, check_recoveries: 1, check_unrecovered: 0, turns_to_green: $t},
     usage: {
       tools: ({"2.4.1": {read: 20, shell: 12, edit: 10, search: 6},
                "2.5.0": {read: 22, search: 16, shell: 18, edit: 14},
                "0.61.0": {shell: 26, edit: 8, plan: 3}}[$v]),
       skills: (if $t >= 2 then {explain: 1} else {} end),
       commands: (if $h == "claude-code" and $e >= 9 then {learn: 1} else {} end)}}'
}

row 10 claude-code 2.4.1 claude-opus-5.5  6 11 5.8 1
row 11 claude-code 2.4.1 claude-opus-5.5  9 13 6.4 2
row 12 claude-code 2.4.1 claude-opus-5.5  7 12 6.0 1
row 12 codex       0.61.0 gpt-5.6         9 10 5.3 1
row 13 claude-code 2.4.1 claude-opus-5.5 10 10 6.2 1
row 14 claude-code 2.4.1 claude-opus-5.5  8 14 5.9 2
row 16 claude-code 2.4.1 claude-opus-5.5  7 12 6.3 1
row 17 claude-code 2.4.1 claude-opus-5.5  9 11 6.1 2
row 17 codex       0.61.0 gpt-5.6         8 11 5.6 2
row 18 claude-code 2.4.1 claude-opus-5.5  8 13 6.0 1
row 19 claude-code 2.4.1 claude-opus-5.5  6 12 6.2 1
row 20 claude-code 2.4.1 claude-opus-5.5 10 12 6.0 2
row 21 claude-code 2.4.1 claude-opus-5.5  8 12 6.2 1
row 22 claude-code 2.5.0 claude-opus-5.5 18 20 8.6 2
row 22 claude-code 2.5.0 claude-opus-5.5 22 22 9.0 3
row 22 codex       0.61.0 gpt-5.6         9 10 5.5 1
row 23 claude-code 2.5.0 claude-opus-5.5 19 21 8.4 2
row 23 codex       0.61.0 gpt-5.6        10  9 5.3 1
row 24 claude-code 2.5.0 claude-opus-5.5 20 23 9.1 3
row 24 codex       0.61.0 gpt-5.6         8 10 5.4 1
row 24 claude-code 2.5.0 claude-opus-5.5 23 21 9.1 3
row 25 claude-code 2.5.0 claude-opus-5.5 24 27 9.2 3
