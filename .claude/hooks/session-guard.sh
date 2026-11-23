#!/usr/bin/env bash
# UserPromptSubmit hook: keeps sessions short, the #1 usage driver.
# Evidence (5-project audit, 2026-11): 65–87% of all cost was the main thread
# re-reading 400k–970k contexts in sessions that spanned up to 20 branches.
#
# On each prompt it checks, and tells Claude (plain stdout = added context) to
# relay a ONE-LINE suggestion to the user when:
#   - the git branch changed since this session started (new task)
#   - the last context size passed CONTEXT_WARN_TOKENS (default 250000),
#     then again every CONTEXT_WARN_STEP tokens (default 150000)
#   - task_plan.md grew past 300 lines / 40 KB (archive finished tasks)
# Each warning fires once per crossing. Never blocks (always exit 0).
#
# Context size is read from the transcript's last "usage" entry: there is no
# documented hook field for it, so treat it as an estimate.

set -uo pipefail

INPUT=$(cat)
[ "${SKIP_SESSION_GUARD:-0}" = "1" ] && exit 0

field() { printf '%s' "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'; }
SESSION=$(field session_id)
TRANSCRIPT=$(field transcript_path | sed 's#\\\\#\\#g')

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

STATE_DIR="$(git rev-parse --git-dir 2>/dev/null || echo "${TMPDIR:-/tmp}")/session-guard"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE="$STATE_DIR/${SESSION:-unknown}"
# Drop state of sessions older than 14 days.
find "$STATE_DIR" -type f -mtime +14 -delete 2>/dev/null

get() { grep "^$1=" "$STATE" 2>/dev/null | tail -1 | cut -d= -f2-; }
put() { { grep -v "^$1=" "$STATE" 2>/dev/null; echo "$1=$2"; } >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }

MSG=""

# --- 1. Branch changed since the session started ----------------------------
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
  START_BRANCH=$(get start_branch)
  if [ -z "$START_BRANCH" ]; then
    put start_branch "$BRANCH"
  elif [ "$BRANCH" != "$START_BRANCH" ] && [ "$(get warned_branch)" != "$BRANCH" ]; then
    put warned_branch "$BRANCH"
    MSG="$MSG
- The git branch changed from '$START_BRANCH' to '$BRANCH' in this session: a new task should start in a fresh session (/clear, or a new session), carrying over only task_plan.md."
  fi
fi

# --- 2. Context size --------------------------------------------------------
WARN_AT=${CONTEXT_WARN_TOKENS:-250000}
STEP=${CONTEXT_WARN_STEP:-150000}
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  USAGE=$(tail -c 3000000 "$TRANSCRIPT" 2>/dev/null | grep -o '"usage"[[:space:]]*:[[:space:]]*{[^}]*}' | tail -1)
  num() { printf '%s' "$USAGE" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9]*" | grep -o '[0-9]*$' | head -1; }
  IN=$(num input_tokens); CW=$(num cache_creation_input_tokens); CR=$(num cache_read_input_tokens)
  CTX=$(( ${IN:-0} + ${CW:-0} + ${CR:-0} ))
  if [ "$CTX" -lt "$WARN_AT" ]; then
    # Back under the threshold (e.g. after /compact): re-arm the warning.
    [ -n "$(get ctx_level)" ] && [ "$(get ctx_level)" != "-1" ] && put ctx_level -1
  else
    LEVEL=$(( (CTX - WARN_AT) / STEP ))
    LAST=$(get ctx_level)
    if [ "$LEVEL" -gt "${LAST:--1}" ]; then
      put ctx_level "$LEVEL"
      MSG="$MSG
- Context is about $((CTX / 1000))k tokens: every message now re-reads all of it. Recommend /compact (name what must survive: modified files, plan status, test commands) or a fresh session once the current step is done."
    fi
  fi
fi

# --- 3. task_plan.md size ---------------------------------------------------
if [ -f task_plan.md ] && [ -z "$(get warned_plan)" ]; then
  LINES=$(wc -l <task_plan.md | tr -d ' ')
  BYTES=$(wc -c <task_plan.md | tr -d ' ')
  if [ "$LINES" -gt 300 ] || [ "$BYTES" -gt 40000 ]; then
    put warned_plan 1
    MSG="$MSG
- task_plan.md is $LINES lines / $((BYTES / 1024)) KB: move finished tasks to docs/plan-archive.md so every read stays cheap (workflow.md, Plan first)."
  fi
fi

if [ -n "$MSG" ]; then
  printf 'session-guard (usage hygiene): tell the user in ONE short line, then continue with their request:%s\n' "$MSG"
fi
exit 0
