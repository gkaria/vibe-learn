# prototype/boundary/boundary.jq — PROTOTYPE for `vibe-learn boundary`. Throwaway: it
# lives on the prototype/boundary-report branch to answer "is this report
# useful, and are these rules the right ones?", not to ship as is.
#
# What the assistant's tool calls reached for outside the code it was asked to
# write: hosts, risky command shapes, sensitive and outside-the-project paths,
# and changes the prompt did not ask for, each tied to its turn and prompt.
# It reads what the assistant asked for, never what processes did.
include "session";

# ── Text helpers ────────────────────────────────────────────────────────────

# Hide secret values before anything is shown: KEY=value, Bearer tokens, and
# user:password@ in URLs.
def redact:
  gsub("(?<k>(?i:[A-Za-z0-9_-]*(api[_-]?key|access[_-]?key|secret|token|password|passwd|pwd)[A-Za-z0-9_]*)\\s*[=:]\\s*)[\"']?[^\\s\"'&;]+[\"']?"; "\(.k)•••")
  | gsub("(?i:bearer)\\s+[^\\s\"']+"; "Bearer •••")
  | gsub("://[^/@\\s:]+:[^/@\\s]+@"; "://•••@");

def pad($n): . + (if ($n - length) > 0 then " " * ($n - length) else "" end);
def clip($n): if length > $n then .[0:$n - 1] + "…" else . end;

# ── Commands → hosts ────────────────────────────────────────────────────────

def segments: [splits("\\s*(?:&&|\\|\\||;|\\||\\n)\\s*")] | map(select(length > 0));
def strip_prefix: sub("^\\s*(sudo\\s+(-\\S+\\s+)*)?([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)*"; "");
def local_host: test("^(localhost|127\\.|0\\.0\\.0\\.0$|\\[?::1\\]?$)|\\.(local|localhost)$");
def file_like: test("\\.(txt|json|sh|tar|gz|tgz|zip|js|ts|py|md|html|log|ya?ml|toml|lock|csv|xml|pem|key|sql|env)$");

# Hosts named in the command: URLs, git@host:repo, and the target of ssh,
# curl, wget, nc and friends when written without a scheme.
def explicit_hosts:
  ( [scan("\\b[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^/@\\s'\"]*@)?(\\[[0-9a-fA-F:]+\\]|[A-Za-z0-9.-]+)") | .[0]]
  + [scan("(?:^|[\\s'\"])[A-Za-z0-9._-]+@([A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+):") | .[0]]
  + [ segments[] | strip_prefix
      | select(test("^(ssh|scp|sftp|rsync|curl|wget|nc|ncat|telnet)\\s"))
      | split(" ")[1:][] | gsub("^[\"']|[\"']$"; "")
      | select((test("^-") or test("://") or file_like) | not)
      | (capture("^(?:[A-Za-z0-9._-]+@)?(?<h>[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+)(?::|/|$)") | .h) ] )
  | map(ascii_downcase | rtrimstr(".")) | unique;

# Hosts a command reaches without naming them: package registries, the git
# remote, the GitHub API behind gh. $origin is the origin remote's host.
def implied_hosts($origin):
  [ segments[] | strip_prefix
    | if test("^(npm|pnpm|yarn|bun)\\s+(i|install|add|ci|update|up|upgrade|dlx|create)(\\s|$)|^(npx|bunx|pnpx)\\s") then {host: "registry.npmjs.org", via: (split(" ")[0])}
      elif test("^(pip3?|uv\\s+pip|python3?\\s+-m\\s+pip)\\s+install(\\s|$)|^(uv\\s+(add|sync)|poetry\\s+(add|install)|pipx\\s+install)(\\s|$)") then {host: "pypi.org", via: "pip"}
      elif test("^cargo\\s+(add|install|build|fetch|update)(\\s|$)") then {host: "crates.io", via: "cargo"}
      elif test("^go\\s+(get|install|mod\\s+download)(\\s|$)") then {host: "proxy.golang.org", via: "go"}
      elif test("^(gem\\s+install|bundle\\s+(install|update))(\\s|$)") then {host: "rubygems.org", via: "gem"}
      elif test("^brew\\s+(install|upgrade|reinstall)(\\s|$)") then {host: "ghcr.io", via: "brew"}
      elif test("^docker\\s+(pull|run|build)|^docker\\s+compose\\s+(up|pull|build)") then {host: "registry-1.docker.io", via: "docker"}
      elif test("^(apt|apt-get|dnf|yum|apk)\\s+(install|update|upgrade|add)") then {host: "OS package mirror", via: (split(" ")[0])}
      elif test("^gh\\s") then {host: "api.github.com", via: "gh"}
      elif test("^git\\s+(clone|fetch|pull|push|ls-remote|submodule\\s+update)(\\s|$)") and (explicit_hosts | length == 0)
        then {host: ($origin // "git remote"), via: "git"}
      else empty end ];

def host_match($pat):
  if ($pat | startswith("*.")) then (. == $pat[2:] or endswith($pat[1:])) else . == $pat end;

# ── Commands → risky shapes ─────────────────────────────────────────────────

def risk_rules: [
  {id: "pipe-to-shell", ask: "run a downloaded script", level: "review", label: "Runs a downloaded script",
   re: "\\b(curl|wget)\\b[^|]*\\|\\s*(sudo\\s+)?(ba|z|da)?sh\\b|\\b(ba|z)?sh\\s+(-c\\s+)?[\"']?\\$\\((curl|wget)\\b|\\beval\\s+[\"']?\\$\\((curl|wget)\\b",
   why: "The script runs before anyone reads it, with your permissions, from whoever controls that URL today. Download it, read it, then run it."},
  {id: "cloud-metadata", ask: "call the cloud metadata service", level: "review", label: "Asks the cloud metadata service",
   re: "169\\.254\\.169\\.254|metadata\\.google\\.internal|fd00:ec2::254",
   why: "On a cloud machine this address hands out the machine's credentials. App code rarely needs it; it is the first thing an attacker asks for."},
  {id: "decode-and-run", ask: "decode and run hidden text", level: "review", label: "Decodes and runs hidden text",
   re: "base64\\s+(-d|--decode|-D)[^|]*\\|\\s*(ba|z)?sh\\b",
   why: "Encoding hides what will run. Decode it to a file and read it first."},
  {id: "raw-shell", ask: "open a raw network shell", level: "review", label: "Opens a raw network shell",
   re: "/dev/tcp/|\\bnc\\b[^|;&]*\\s-e\\s|\\bncat\\b[^|;&]*--exec|\\bsocat\\b[^|;&]*exec:",
   why: "This wires a shell to a network socket, which is how a reverse shell works. There is almost never a development reason for it."},
  {id: "secret-in-command", ask: "put a secret on the command line", level: "review", label: "Secret on the command line", flags: "i",
   re: "(api[_-]?key|access[_-]?key|secret|token|password|passwd)[A-Za-z0-9_]*\\s*[=:]\\s*[\"']?[A-Za-z0-9_./+=-]{8,}([\"'\\s;&|]|$)|bearer\\s+[A-Za-z0-9._-]{8,}|://[^/@\\s:]+:[^/@\\s]+@",
   why: "Command lines are kept in shell history, process lists and logs, including this one. Read secrets from an env file or a secret manager instead."},
  {id: "reads-secrets", ask: "read a secrets file", level: "review", label: "Reads a secrets file",
   re: "\\b(cat|less|more|head|tail|cp|scp|base64|xxd)\\b[^|;&]*(\\.env\\b|id_rsa|id_ed25519|\\.aws/credentials|\\.ssh/|\\.netrc|\\.npmrc|\\.pypirc|\\.pem\\b)",
   why: "Printing a secret puts it into the assistant's context and transcript. Ask what the code needs from it instead."},
  {id: "env-dump", ask: "print every environment variable", level: "review", label: "Prints every environment variable",
   re: "^\\s*(printenv|env|export\\s+-p)\\s*($|\\|)|[;&|]\\s*(printenv|env)\\s*($|\\|)",
   why: "Environment variables often hold tokens. Printing all of them copies every one into the transcript."},
  {id: "tls-off", ask: "turn off TLS checks", level: "review", label: "Turns off TLS checks",
   re: "\\bcurl\\b[^|;&]*\\s(-k|--insecure)(\\s|$)|NODE_TLS_REJECT_UNAUTHORIZED=0|GIT_SSL_NO_VERIFY=(1|true)|--trusted-host|strict-ssl\\s+false|sslVerify\\s+false|--no-check-certificate|verify\\s*=\\s*False",
   why: "Without certificate checks anyone on the network path can pose as the server. Fine against localhost; a habit worth noticing elsewhere."},
  {id: "force-push", ask: "force-push", level: "review", label: "Force-pushes over history",
   re: "\\bgit\\s+push\\b[^;&|]*\\s(--force(?!-with-lease)|-f)(\\s|$)",
   why: "Overwrites the remote branch, including other people's commits. --force-with-lease refuses when the remote moved."},
  {id: "persistence", ask: "change what runs at login", level: "review", label: "Changes what runs at login or on a schedule",
   re: "\\bcrontab\\b|launchctl\\s+(load|bootstrap)|systemctl\\s+(--user\\s+)?enable|>>?\\s*~/\\.(bashrc|zshrc|profile|bash_profile|zprofile)",
   why: "This keeps running after the session ends. Check that you want it."},
  {id: "security-off", ask: "turn off a system protection", level: "review", label: "Turns off a system protection",
   re: "setenforce\\s+0|ufw\\s+disable|spctl\\s+--master-disable|csrutil\\s+disable|Set-MpPreference",
   why: "Disables a protection for the whole machine, not just this project."},
  {id: "world-writable", ask: "make files writable by everyone", level: "review", label: "Makes files writable by everyone",
   re: "\\bchmod\\s+(-R\\s+)?(0?777|a\\+w|o\\+w)\\b",
   why: "Any user or process on the machine can then change these files. The narrower fix is usually the right owner."},
  {id: "sudo", ask: "need root", level: "note", label: "Runs as root",
   re: "(^|[;&|]\\s*)sudo\\s",
   why: "Root can change anything on the machine. Worth knowing which step needed it."},
  {id: "broad-delete", ask: "delete a broad path", level: "note", label: "Recursive delete of a broad path",
   re: "\\brm\\s+(-[a-zA-Z]*[rR][a-zA-Z]*\\s+)+(-\\S+\\s+)*[\"']?(/|~|\\$HOME|\\*|\\.\\.)",
   why: "A path like / or ~ or * is one typo away from deleting far more than intended."},
  {id: "skip-hooks", ask: "skip git hooks", level: "note", label: "Skips git hooks",
   re: "\\bgit\\b[^;&|]*\\s--no-verify\\b|\\bHUSKY=0\\b",
   why: "Hooks usually run the checks the team agreed on. Skipping them hides what they would have caught."},
  {id: "discard-work", ask: "discard uncommitted work", level: "note", label: "Discards uncommitted work",
   re: "\\bgit\\s+(reset\\s+--hard|clean\\s+-[a-zA-Z]*f|checkout\\s+--\\s+\\.|filter-branch|filter-repo)",
   why: "Changes thrown away this way do not come back."},
  {id: "global-install", ask: "install outside the project", level: "note", label: "Installs outside the project",
   re: "\\b(npm|pnpm|yarn)\\s+(i|install|add)\\b[^;&|]*\\s(-g|--global)\\b|--break-system-packages|\\bsudo\\s+pip",
   why: "Global packages affect every project on the machine and are not in the lockfile."}
];

def risks_of:
  . as $c
  | ($c | explicit_hosts) as $hosts
  | [ risk_rules[] | . as $r | select($c | test($r.re; ($r.flags // "")))
      | if .id == "tls-off" and ($hosts | length) > 0 and ($hosts | all(local_host)) then .level = "note" | .why = "Against localhost this is usually fine: a dev certificate. The habit is worth noticing anywhere else." else . end
      | . + {at: ([$c | redact | match($r.re; ($r.flags // "")) | .offset] | first // 0)}
      | del(.re, .flags) ];

# ── Paths → categories ──────────────────────────────────────────────────────

def category_label: {
  secrets: "secrets", "credentials-config": "credentials config", "agent-config": "assistant config",
  recorder: "vibe-learn's own log", "shell-startup": "shell startup", ci: "CI", dependencies: "dependencies",
  infra: "infrastructure", "git-internals": "git internals", protected: "protected by policy",
  system: "system files", temp: "temp", outside: "outside the project"}[.] // .;

def glob_re: gsub("[.+^$()|{}\\[\\]\\\\]"; "\\\(.)") | gsub("\\*\\*"; "\u0000") | gsub("\\*"; "[^/]*") | gsub("\u0000"; ".*") | "^" + . + "$";

# A path → {path, display, inside, category, level}. category is null for
# ordinary files inside the project, which the report leaves out.
def classify($root; $home; $protected):
  (if startswith("~/") then $home + .[1:] else . end) as $abs
  | ($abs | startswith("/")) as $absolute
  | (if $absolute | not then {rel: ltrimstr("./"), inside: true}
     elif $root != "" and ($abs | startswith($root + "/")) then {rel: $abs[($root | length) + 1:], inside: true}
     else {rel: $abs, inside: false} end) as $p
  | ($p.rel) as $r
  | (if $p.inside then
       if ($protected | any(. as $g | $r | test($g | glob_re))) then "protected"
       elif ($r | test("(^|/)\\.env(\\.|$)")) and ($r | test("\\.(example|sample|template|dist)$") | not) then "secrets"
       elif $r | test("\\.(pem|key|p12|pfx)$|(^|/)id_(rsa|ed25519|ecdsa)") then "secrets"
       elif $r | test("^\\.vibe-learn/") then "recorder"
       elif $r | test("^(\\.claude|\\.codex|\\.cursor|\\.grok|\\.opencode|\\.github/hooks)/|^\\.mcp\\.json$|^(CLAUDE|AGENTS)\\.md$") then "agent-config"
       elif $r | test("^\\.github/workflows/|^\\.gitlab-ci\\.yml$|^\\.circleci/|^Jenkinsfile$|^azure-pipelines|^\\.buildkite/") then "ci"
       elif $r | test("(^|/)\\.(npmrc|pypirc|netrc)$") then "credentials-config"
       elif $r | test("^\\.git/") then "git-internals"
       elif $r | test("(^|/)(package(-lock)?\\.json|pnpm-lock\\.yaml|yarn\\.lock|requirements[^/]*\\.txt|pyproject\\.toml|poetry\\.lock|uv\\.lock|Cargo\\.(toml|lock)|go\\.(mod|sum)|Gemfile(\\.lock)?|composer\\.(json|lock))$") then "dependencies"
       elif $r | test("(^|/)(Dockerfile|docker-compose[^/]*\\.ya?ml)$|\\.tf$") then "infra"
       else null end
     else
       ($abs | if $home != "" and startswith($home + "/") then .[($home | length) + 1:] else null end) as $h
       | if $h == null then
           (if $abs | test("^(/tmp|/private/tmp|/var/folders|/dev/null)") then "temp"
            elif $abs | test("^/(etc|usr|bin|sbin|System|Library)/") then "system"
            else "outside" end)
         elif $h | test("^\\.(ssh|aws|gnupg|kube|azure)/|^\\.config/gcloud/|^\\.docker/config\\.json$") then "secrets"
         elif $h | test("^\\.(claude|codex|cursor|copilot|grok)(/|\\.json$)|^\\.config/opencode/") then "agent-config"
         elif $h | test("^\\.(bashrc|zshrc|profile|bash_profile|zprofile|zshenv)$|^\\.config/fish/") then "shell-startup"
         elif $h | test("^\\.(gitconfig|npmrc|pypirc|netrc)$") then "credentials-config"
         else "outside" end
     end) as $cat
  | {path: $r,
     display: (if $p.inside then $r elif $home != "" and ($r | startswith($home + "/")) then "~" + $r[($home | length):] else $r end),
     inside: $p.inside, category: $cat,
     level: (if $cat == null then null elif ($cat | IN("dependencies", "infra", "git-internals", "temp")) then "note" else "review" end)};

# Words in a prompt that make a change in that category expected.
def scope_words: {
  ci: "\\b(ci|workflows?|pipelines?|actions?|build)\\b",
  dependencies: "depend|install|packages?\\b|librar|upgrade|bump|\\b(npm|pip|yarn|pnpm|cargo|gem)\\b|versions?\\b",
  "agent-config": "claude|codex|cursor|copilot|grok|agent|hooks?\\b|settings|permission|\\bmcp\\b|instructions",
  secrets: "\\benv\\b|\\.env|secret|keys?\\b|credential|token|config|auth|jwt|login|oauth",
  "credentials-config": "npmrc|pypirc|credential|registry|config",
  infra: "docker|deploy|infra|terraform|container",
  "shell-startup": "shell|bashrc|zshrc|profile|path\\b",
  recorder: "vibe-learn",
  protected: "migrat|schema",
  "git-internals": "\\bgit\\b"};

# ── Facts ───────────────────────────────────────────────────────────────────

# $log, $base: log events (arrays). $tx: transcript tool calls [{ts,name,input}]
# or null when no transcript was read. $meta: session-meta.json. $policy:
# {allowed_hosts?, protected_paths?}. $origin: host of the origin remote.
def boundary_facts($log; $base; $tx; $txstatus; $meta; $policy; $root; $home; $origin; $project):
  ($log | number_turns) as $ev
  | ($ev | learning_turns) as $learning
  | ($ev | map(select(.event == "user_prompt")) | map({key: (._turn | tostring), value: .}) | from_entries) as $prompts
  | ($ev | map(select(.event == "user_prompt")) | map({turn: ._turn, ts: (.timestamp // "")[0:19]})) as $starts
  | (($policy.protected_paths // []) | map(strings)) as $protected
  | ($policy.allowed_hosts | if type == "array" then map(strings | ascii_downcase) else null end) as $allowed
  | ($tx // []) as $calls
  | def turn_at($ts): ($ts[0:19]) as $t | ([$starts[] | select(.ts <= $t) | .turn] | last) // 0;
    def prompt_of($t): $prompts[$t | tostring].prompt;
    def is_learning($t): $learning[$t | tostring] == true;

  # Bash commands, with the transcript's full text where the log cut it at 200.
    ([$calls[] | select(.name == "Bash") | .input.command | strings]) as $full
  | [ $ev[] | select(.event == "tool_use" and .tool == "Bash" and (.command | type) == "string")
      | . as $e
      | (if ($e.command | length) >= 200 then ([$full[] | select(startswith($e.command))] | first) else null end) as $f
      | {turn: ._turn, command: ($f // .command),
         truncated: (($e.command | length) >= 200 and $f == null),
         recovered: ($f != null and ($f | length) > ($e.command | length))} ] as $cmds

  # Network reach.
  | ([ $cmds[] as $c
       | (($c.command | segments[] | strip_prefix | . as $s | explicit_hosts[] | {host: ., kind: "named", via: ($s | program)}),
          ($c.command | implied_hosts($origin)[] | . + {kind: "implied"}))
       | . + {turn: $c.turn} ]
     + [ $calls[] as $k | ($k.ts | turn_at(.)) as $t
         | if $k.name == "WebFetch" then
             ($k.input.url // "" | capture("^[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^/@]*@)?(?<h>[^/:?#]+)") | {host: (.h | ascii_downcase), kind: "tool", via: "WebFetch", turn: $t})
           elif ($k.name | IN("WebSearch", "web_search")) then {host: "web search", kind: "tool", via: $k.name, turn: $t}
           elif ($k.name | startswith("mcp__")) then {host: ("mcp:" + ($k.name | ltrimstr("mcp__") | sub("__.*$"; ""))), kind: "mcp", via: ($k.name | split("__") | .[2:] | join("__")), turn: $t}
           else empty end ]) as $hits
  | ([ $base[] | select(.event == "tool_use" and .tool == "Bash" and (.command | type) == "string")
       | .command | (explicit_hosts[]), (implied_hosts($origin)[] | .host) ] | unique) as $seen
  | ($hits | group_by(.host) | map(
      (.[0].host) as $h
      | (map(.kind) | unique) as $kinds
      | ($h | local_host) as $local
      | ($h | test("^(mcp:|web search$|git remote$|OS package mirror$)")) as $abstract
      | ($seen | index($h) != null) as $before
      | (if $allowed == null or $abstract then null elif $local then true else ($allowed | any(. as $p | $h | host_match($p))) end) as $ok
      | {host: $h, kinds: $kinds, via: (map(.via) | unique), turns: (map(.turn) | unique),
         seen_before: $before, allowed: $ok,
         level: (if $local then "local"
                 elif ($h | test("^169\\.254\\.")) then "review"
                 elif $ok == false then "review"
                 elif $ok == null and ($kinds | index("named")) and ($before | not) and ($abstract | not) then "review"
                 else "note" end)})
     | sort_by((if .level == "review" then 0 elif .level == "note" then 1 else 2 end), .turns[0], .host)) as $reach

  # Risky command shapes.
  | ([ $cmds[] as $c | $c.command | risks_of[]
       | . + {turn: $c.turn, prompt: prompt_of($c.turn), command: ($c.command | redact), recovered: $c.recovered} ]
     | sort_by((if .level == "review" then 0 else 1 end), .turn)) as $risks

  # Paths: writes from the hook log, reads from the transcript.
  | ([ $ev[] | select(.event == "tool_use" and (.file | type) == "string" and .file != "" and .action != "failed")
       | {op: "wrote", turn: ._turn, file} ]
     + [ $calls[] | select(.name | IN("Read", "NotebookRead", "Grep", "Glob", "LS"))
         | (.input.file_path // .input.notebook_path // .input.path | strings) as $f
         | {op: "read", turn: (.ts | turn_at(.)), file: $f} ]) as $touches
  | ([ $touches[] | . as $t | ($t.file | classify($root; $home; $protected)) as $c
       | select($c.category != null)
       | select($t.op == "wrote" or ($c.category | IN("secrets", "credentials-config", "agent-config", "shell-startup", "system", "outside")))
       | $c + {op: $t.op, turn: $t.turn} ]
     | group_by([.op, .path])
     | map(.[0] + {turns: (map(.turn) | unique)} | del(.turn))
     | sort_by((if .level == "review" then 0 else 1 end), (if .inside then 1 else 0 end), .turns[0])) as $paths

  # Scope surprises: work turns whose writes fall in a category the prompt
  # never mentions.
  | ([ $touches | map(select(.op == "wrote")) | group_by(.turn)[]
       | (.[0].turn) as $t | (prompt_of($t)) as $pr
       | select((is_learning($t) | not) and ($pr | type) == "string" and $pr != "")
       | [ .[] | (.file | classify($root; $home; $protected)) | select(.category != null and .category != "temp" and .category != "outside")
           | select(scope_words[.category] as $w | $w == null or ($pr | ascii_downcase | test($w) | not)) ]
       | select(length > 0)
       | {turn: $t, prompt: $pr,
          areas: (group_by(.category) | map({category: .[0].category, paths: (map(.display) | unique)}))} ]) as $surprises

  # What this report cannot see.
  | ($cmds | map(select(.truncated))) as $cut
  | ([$calls[] | select(.name | IN("Task", "Agent"))] | length) as $subagents
  | ([$ev[] | select(.event == "user_prompt" and (.prompt | type) != "string")] | length) as $uncaptured
  | ([ "Processes the commands started (install scripts, test runners, build tools) can reach the network without a tool call. This lists what the assistant asked for, not every connection the machine made.",
       (if $txstatus == "missing" then "No host transcript found, so web fetches, MCP calls and file reads are not in this report."
        elif $txstatus == "unsupported" then "Reading \($meta.harness // "this assistant")'s transcript is not in the prototype yet, so web fetches, MCP calls and file reads are not in this report."
        else empty end),
       (if ($cut | length) > 0 then "\($cut | length) command(s) were cut at 200 characters in the log and not found in the transcript (turn \($cut | map(.turn) | unique | map(tostring) | join(", "))). Anything after the cut is unseen." else empty end),
       (if $subagents > 0 then "\($subagents) subagent run(s): their own tool calls are in separate transcripts, not read here." else empty end),
       (if $uncaptured > 0 then "\($uncaptured) prompt(s) were not captured (capture_prompts is off), so those turns get no scope check." else empty end),
       (if $allowed == null then "No allowed_hosts in .vibe-learn/policy.json, so named hosts not seen in the previous session are flagged instead." else empty end),
       "\"Seen before\" compares with the previous session only, the one bootstrap keeps.",
       "The assistant can write to .vibe-learn/ like any project file. This is a record to learn from, not tamper-proof evidence." ]) as $blind

  | {schema: "boundary-prototype",
     project: $project, session_id: $meta.session_id, harness: $meta.harness, harness_version: $meta.harness_version, model: $meta.model,
     sources: {log_events: ($log | length), prompts_captured: ([$ev[] | select(.event == "user_prompt" and (.prompt | type) == "string")] | length), transcript: $txstatus, transcript_calls: ($calls | length),
               baseline_events: ($base | length), policy: ($allowed != null or ($protected | length) > 0)},
     summary: {
       review_turns: ([($reach[] | select(.level == "review") | .turns[]), ($risks[] | select(.level == "review") | .turn),
                       ($paths[] | select(.level == "review") | .turns[]), ($surprises[] | .turn)] | unique),
       work_turns: ([$ev[] | select(.event == "user_prompt" and (is_learning(._turn) | not))] | length),
       hosts: ($reach | map(select(.level != "local")) | length),
       new_hosts: ($reach | map(select(.level != "local" and (.seen_before | not) and (.host | test("^(mcp:|web search$)") | not))) | length),
       not_allowed: ($reach | map(select(.allowed == false)) | length),
       risks: ($risks | length), paths: ($paths | length), surprises: ($surprises | length)},
     reach: $reach, risks: $risks, paths: $paths, surprises: $surprises, blind_spots: $blind};

# ── Text ────────────────────────────────────────────────────────────────────

def mark: if . == "review" then "⚠" elif . == "local" then " " else "·" end;
def turns_text: "turn" + (if length > 1 then "s " else " " end) + (map(tostring) | join(","));
def quoted: if type == "string" then "\"" + (redact | clip(70)) + "\"" else "(prompt not captured)" end;

def render_text($learn):
  . as $f
  | ($f.reach | map(.host | length) | max // 0) as $hw
  | ($f.paths | map(.display | length) | max // 0 | [., 48] | min) as $pw
  | [ "vibe-learn boundary  ·  PROTOTYPE",
      "\($f.project)  ·  session \($f.session_id // "?")  ·  \([$f.harness, $f.harness_version, $f.model] | map(strings) | join(" "))",
      "",
      "What this session's tool calls reached for, from the hook log\(if $f.sources.transcript == "read" then " and the host transcript" else "" end).",
      "A record to learn from, not a guard: see \"What this can't see\".",
      "",
      (if ($f.summary.review_turns | length) == 0 then "  Nothing to review in \($f.summary.work_turns) work turn(s)."
       else "  Turns worth a look: \($f.summary.review_turns | map(tostring) | join(", ")) of \($f.summary.work_turns) work turns" end),
      "  \($f.summary.hosts) hosts (\($f.summary.new_hosts) new\(if $f.sources.policy then ", \($f.summary.not_allowed) not allowed" else "" end))  ·  \($f.summary.risks) risky commands  ·  \($f.summary.paths) sensitive paths  ·  \($f.summary.surprises) scope surprises",
      "",
      "Network reach",
      (if ($f.reach | length) == 0 then "  nothing named or implied" else
        ($f.reach[] | "  \(.level | mark) \(.host | pad($hw))  \(.via | join(", ")) · \(.turns | turns_text)\(
            [ (if .level == "local" then "local" else empty end),
              (if .kinds == ["implied"] then "implied" else empty end),
              (if .level != "local" and (.host | test("^(mcp:|web search$)") | not) then (if .seen_before then "seen before" else "new" end) else empty end),
              (if .allowed == false then "not in allowed_hosts" elif .allowed == true and .level != "local" then "allowed" else empty end),
              (if (.host | test("^169\\.254\\.")) then "cloud metadata address" else empty end),
              (if (.host | startswith("mcp:")) then "MCP server: third-party code with its own network access" else empty end)
            ] | if length > 0 then " · " + join(" · ") else "" end)") end),
      "",
      "Risky commands",
      (if ($f.risks | length) == 0 then "  none matched" else
        ($f.risks[] | "  \(.level | mark) turn \(.turn)  \(.label)\(if .recovered then "  (past the log's 200-character cut; full text from the transcript)" else "" end)",
                      "      $ \(if .at > 70 then "…" + .command[(.at - 40):] else .command end | gsub("\\s*\\n\\s*"; " ↵ ") | clip(110))",
                      "      asked: \(.prompt | quoted)",
                      "      why: \(.why)") end),
      "",
      "Sensitive paths",
      (if ($f.paths | length) == 0 then "  none" else
        ($f.paths[] | "  \(.level | mark) \(.op | pad(5)) \(.display | clip(48) | pad($pw))  \(.category | category_label)\(if .inside or .category == "outside" then "" else " (outside the project)" end) · \(.turns | turns_text)") end),
      "",
      "Scope surprises",
      (if ($f.surprises | length) == 0 then
         (if $f.sources.prompts_captured == 0 then "  skipped: no prompts were captured to compare with" else "  none: every sensitive change matched what its prompt asked for" end) else
        ($f.surprises[] | "  ⚠ turn \(.turn) \(.prompt | quoted)",
                          "      also changed \(.areas | map("\(.category | category_label): \(.paths | join(", "))") | join("; "))") end),
      "",
      "What this can't see",
      ($f.blind_spots[] | "  - " + .),
      "",
      "Ask about it",
      ( ([$f.risks[] | select(.level == "review") | "  \($learn) why did turn \(.turn) \(.ask)?"] | .[0:2][]),
        ([$f.surprises[] | "  \($learn) why did turn \(.turn) touch \(.areas | map(.category | category_label) | join(" and "))?"] | .[0:1][]),
        "  vibe-learn boundary --json   for the facts as JSON" )
    ]
  | join("\n");
