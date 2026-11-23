#!/usr/bin/env bash
# PostToolUse hook (Bash): warns Claude when a command worked OUTSIDE this
# project. Evidence: brand sessions ran ~140 commands inside a sibling repo,
# loading two repos' context and breaking "one session per project".
# Checks (a) the shell's cwd after the command, (b) absolute cd/pushd/git -C
# targets. Never blocks; warns once per folder per session.

set -uo pipefail

INPUT=$(cat)
[ "${SKIP_REPO_GUARD:-0}" = "1" ] && exit 0
json_str() { printf '%s' "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"\\\\]\|\\\\.\)*\"" | head -1 | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'; }
# Runs on every Bash call: read simple fields with bash regex (no subprocess).
RE_CWD='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
RE_SID='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'
CWD=""; SESSION=""
[[ $INPUT =~ $RE_CWD ]] && CWD=${BASH_REMATCH[1]//\\\\/\\}
[[ $INPUT =~ $RE_SID ]] && SESSION=${BASH_REMATCH[1]}

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT_ABS=$(cd "$ROOT" 2>/dev/null && pwd -P) || exit 0

CANDIDATES=""
# (a) where the shell ended up
[ -n "$CWD" ] && CANDIDATES="$CWD"
# (b) absolute targets named in the command (relative ones are covered by (a))
case "$INPUT" in
  *'cd '*|*pushd*|*'-C '*)
    # JSON-unescape: protect "\\" first so a path like C:\nvidia is not read as "\n".
    CMD=$(json_str command | sed 's/\\\\/\x01/g; s/\\n/\n/g; s/\\"/"/g; s/\x01/\\/g')
    T=$(printf '%s\n' "$CMD" | grep -oE "(^|[;&|(]|&&)[[:space:]]*(cd|pushd)[[:space:]]+(\"[^\"]+\"|'[^']+'|[^[:space:];&|)]+)|git[[:space:]]+-C[[:space:]]+(\"[^\"]+\"|'[^']+'|[^[:space:];&|)]+)" \
      | sed -E "s/^[^a-z]*(cd|pushd|git[[:space:]]+-C)[[:space:]]+//; s/^[\"']//; s/[\"']$//" \
      | grep -E '^(/|~/|[A-Za-z]:[\\/]|\\\\)')
    [ -n "$T" ] && CANDIDATES="$CANDIDATES
$T" ;;
esac
[ -z "$CANDIDATES" ] && exit 0
# Fast path: no absolute targets and the shell is still inside the project.
if [ -z "${T:-}" ]; then
  CWD_ABS=$(cd "$CWD" 2>/dev/null && pwd -P) || exit 0
  case "$CWD_ABS/" in "$ROOT_ABS"/*) exit 0 ;; esac
fi

STATE_DIR="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || echo "${TMPDIR:-/tmp}")/session-guard"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE="$STATE_DIR/repo-${SESSION:-unknown}"

OUTSIDE=""
while IFS= read -r t; do
  [ -z "$t" ] && continue
  t=${t/#\~/$HOME}
  ABS=$(cd "$t" 2>/dev/null && pwd -P) || continue
  case "$ABS/" in "$ROOT_ABS"/*) continue ;; esac
  # Scratch space is fine (REPO_GUARD_ALLOW: colon-separated path prefixes).
  ALLOWED=0
  IFS=: read -ra PREFIXES <<<"${REPO_GUARD_ALLOW-/tmp:${TMPDIR:-/tmp}}"
  for p in "${PREFIXES[@]}"; do [ -n "$p" ] && case "$ABS" in "$p"|"$p"/*) ALLOWED=1 ;; esac; done
  [ "$ALLOWED" = 1 ] && continue
  grep -qxF "$ABS" "$STATE" 2>/dev/null && continue
  echo "$ABS" >>"$STATE"
  OUTSIDE="$OUTSIDE $ABS"
done <<EOF
$CANDIDATES
EOF

[ -z "$OUTSIDE" ] && exit 0

MSG="repo-guard: this command worked outside the project ($ROOT_ABS) in:$OUTSIDE. If that is a different repo, its work belongs in its own session; tell the user in one line unless they asked for this."
MSG=${MSG//\\/\\\\}; MSG=${MSG//\"/\\\"}
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
exit 0
