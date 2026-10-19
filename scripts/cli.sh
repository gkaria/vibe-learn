#!/bin/bash
# cli.sh — vibe-learn command dispatcher

set -euo pipefail

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
vibe-learn — learn from agent-built coding sessions

Usage:
  vibe-learn install    [target-dir] [--assistant=claude-code|copilot-cli|codex|opencode|grok|cursor|all] [--create]
  vibe-learn briefing   [target-dir] [--latest] [--if-stale] [--json [--session <id>]]
  vibe-learn recap      [target-dir] [--days=7] [--save]
  vibe-learn health     [target-dir] [--days=14|all] [--by=harness|model] [--all] [--json] [--save] [--redact]
  vibe-learn audio-prep [target-dir]
  vibe-learn boundary   [target-dir] [--json] [--demo]   (prototype)
  vibe-learn doctor     [target-dir]
  vibe-learn knowledge  forget <name> | list [--status=<s>] | due [--days=14]  [--dir=<project>]
  vibe-learn completion bash|zsh
  vibe-learn help
EOF
}

# Shell completion, generated from this file so it cannot drift: the
# subcommands are the top-level labels of the dispatch case below, and each
# one's flags are the --flags on its usage line.
subcommands() { sed -n 's/^  \([a-z][a-z-]*\)\(|[^)]*\)\{0,1\})$/\1/p' "${BASH_SOURCE[0]}"; }
flags_of() { usage | grep -E "^  vibe-learn $1( |$)" | grep -oE -- '--[a-z-]+=?' | sort -u | paste -sd ' ' - || true; }

completion() {
  local cmd cmds
  cmds="$(subcommands | paste -sd ' ' -)"
  case "$1" in
    bash)
      echo '# vibe-learn bash completion: eval "$(vibe-learn completion bash)"'
      echo '_vibe_learn() {'
      echo '  local cur="${COMP_WORDS[COMP_CWORD]}" flags=""'
      echo '  if [ "$COMP_CWORD" -eq 1 ]; then'
      echo "    COMPREPLY=(\$(compgen -W \"$cmds\" -- \"\$cur\"))"
      echo '    return'
      echo '  fi'
      echo '  case "${COMP_WORDS[1]}" in'
      for cmd in $cmds; do echo "    $cmd) flags=\"$(flags_of "$cmd")\" ;;"; done
      echo '  esac'
      echo '  case "$cur" in'
      echo '    -*) COMPREPLY=($(compgen -W "$flags" -- "$cur"))'
      echo '        if [ "${#COMPREPLY[@]}" -eq 1 ] && [ "${COMPREPLY[0]%=}" != "${COMPREPLY[0]}" ] && type compopt >/dev/null 2>&1; then compopt -o nospace; fi ;;'
      echo '    *) COMPREPLY=() ;;  # -o dirnames completes the target directory'
      echo '  esac'
      echo '}'
      echo 'complete -o dirnames -F _vibe_learn vibe-learn'
      ;;
    zsh)
      echo '#compdef vibe-learn'
      echo '# vibe-learn zsh completion: eval "$(vibe-learn completion zsh)" after compinit'
      echo '_vibe_learn() {'
      echo '  local -a flags'
      echo '  if (( CURRENT == 2 )); then'
      echo "    compadd -- $cmds"
      echo '    return'
      echo '  fi'
      echo '  case $words[2] in'
      for cmd in $cmds; do echo "    $cmd) flags=($(flags_of "$cmd")) ;;"; done
      echo '  esac'
      echo '  if [[ $PREFIX == -* ]]; then'
      echo "    compadd -S '' -- \${(M)flags:#*=}"
      echo '    compadd -- ${flags:#*=}'
      echo '  else'
      echo '    _files -/'
      echo '  fi'
      echo '}'
      echo 'compdef _vibe_learn vibe-learn'
      ;;
    *)
      echo "Usage: vibe-learn completion bash|zsh" >&2
      return 1
      ;;
  esac
}

COMMAND="${1:-help}"

case "$COMMAND" in
  install)
    shift
    exec "$VIBE_LEARN_DIR/scripts/install.sh" "$@"
    ;;
  briefing)
    shift
    exec "$VIBE_LEARN_DIR/scripts/briefing.sh" "$@"
    ;;
  recap)
    shift
    exec "$VIBE_LEARN_DIR/scripts/recap.sh" "$@"
    ;;
  health)
    shift
    exec "$VIBE_LEARN_DIR/scripts/health-report.sh" "$@"
    ;;
  boundary)
    shift
    # Prototype: runs from a checkout or the plugin, not from ~/.vibe-learn.
    [ -f "$VIBE_LEARN_DIR/prototype/boundary/boundary.sh" ] || { echo "ERROR: 'vibe-learn boundary' is a prototype; run it from a vibe-learn checkout on the prototype/boundary-report branch." >&2; exit 1; }
    exec "$VIBE_LEARN_DIR/prototype/boundary/boundary.sh" "$@"
    ;;
  audio-prep)
    shift
    exec "$VIBE_LEARN_DIR/scripts/audio-prep.sh" "$@"
    ;;
  doctor)
    shift
    exec "$VIBE_LEARN_DIR/scripts/doctor.sh" "$@"
    ;;
  knowledge)
    shift
    exec "$VIBE_LEARN_DIR/scripts/knowledge.sh" "$@"
    ;;
  completion)
    completion "${2:-}"
    ;;
  dashboard) # retired, so not completed
    echo "ERROR: 'vibe-learn dashboard' is now 'vibe-learn briefing'" >&2
    exit 1
    ;;
  help|--help|-h)
    usage
    ;;
  --assistant=*|--assistant)
    # Backward compatibility with the old shim, where vibe-learn arguments went
    # directly to install.sh.
    exec "$VIBE_LEARN_DIR/scripts/install.sh" "$@"
    ;;
  *)
    if [ -d "$COMMAND" ]; then
      exec "$VIBE_LEARN_DIR/scripts/install.sh" "$@"
    fi
    echo "ERROR: Unknown command '$COMMAND'." >&2
    echo "" >&2
    usage >&2
    exit 1
    ;;
esac
