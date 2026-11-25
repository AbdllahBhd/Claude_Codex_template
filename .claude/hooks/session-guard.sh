#!/usr/bin/env bash
# UserPromptSubmit hook: keeps sessions short, the #1 usage driver.
# Evidence (5-project audit, 2026-11): 65–87% of all cost was the main thread
# re-reading 400k–970k contexts in sessions that spanned up to 20 branches.
#
# On each prompt it checks, and tells Claude (plain stdout = added context) to
# relay a ONE-LINE suggestion to the user when:
#   - the git branch changed since this session started (new task)
#   - the last context size passed CONTEXT_WARN_TOKENS (default 150000),
#     then again every CONTEXT_WARN_STEP tokens (default 150000); Claude must
#     also write a ready-to-paste handoff prompt to docs/handoff.md
#   - task_plan.md grew past 300 lines / 40 KB (archive finished tasks)
#   - first prompt only: the template clone at $TEMPLATE_DIR (machine-local:
#     set it in .claude/settings.local.json "env") has commits on
#     $TEMPLATE_REF (default main) newer than .claude/template-version
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
- Tell the user in ONE line: the git branch changed from '$START_BRANCH' to '$BRANCH' in this session: a new task should start in a fresh session (/clear, or a new session), carrying over only task_plan.md."
  fi
fi

# --- 2. Context size --------------------------------------------------------
WARN_AT=${CONTEXT_WARN_TOKENS:-150000}
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
- Context is about $((CTX / 1000))k tokens: every message now re-reads all of it. (a) Tell the user in ONE line and recommend a fresh session. (b) As soon as the current step is done (not mid-step), write a ready-to-paste handoff prompt to docs/handoff.md (overwrite it; format: reporting.md, Handoff prompt) and show it to the user in a code block."
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
- Tell the user in ONE line: task_plan.md is $LINES lines / $((BYTES / 1024)) KB: move finished tasks to docs/plan-archive.md so every read stays cheap (workflow.md, Plan first)."
  fi
fi

# --- 4. Template updates (first prompt of the session; no fetch) ------------
if [ -z "$(get template_checked)" ]; then
  put template_checked 1
  TD=${TEMPLATE_DIR:-}; TREF=${TEMPLATE_REF:-main}
  if [ -n "$TD" ] && git -C "$TD" rev-parse --verify -q "$TREF^{commit}" >/dev/null 2>&1; then
    BASE=""; [ -f .claude/template-version ] && BASE=$(sed -n 's/^commit //p' .claude/template-version | head -1)
    if [ -z "$BASE" ]; then
      MSG="$MSG
- Tell the user in ONE line: this project was never synced with the template — run a dry run: bash \"$TD/scripts/sync-template.sh\" \"$TD\" --ref $TREF"
    elif git -C "$TD" cat-file -e "$BASE^{commit}" 2>/dev/null; then
      t=""; command -v timeout >/dev/null 2>&1 && t="timeout 5"
      N=$($t git -C "$TD" rev-list --count "$BASE..$TREF" 2>/dev/null)
      [ "${N:-0}" -gt 0 ] 2>/dev/null && MSG="$MSG
- Tell the user in ONE line: the template is $N commits newer than this project's last sync — run scripts/sync-template.sh \"$TD\" --ref $TREF (dry run first)."
    fi
  fi
fi

if [ -n "$MSG" ]; then
  printf 'session-guard (usage hygiene): act on each item below, then continue with their request:%s\n' "$MSG"
fi
exit 0
