#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): skills only load when Claude chooses to, and a
# 5-project audit found testing/UI skills almost never loaded. When a test or
# UI file is edited, remind Claude ONCE per session to load the matching
# skill. Never blocks.

set -uo pipefail

INPUT=$(cat)
[ "${SKIP_SKILL_NUDGE:-0}" = "1" ] && exit 0

# Runs after every edit: parse with bash regex (no subprocess) and bail fast.
RE_FILE='"file_path"[[:space:]]*:[[:space:]]*"([^"]*)"'
RE_SID='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ $INPUT =~ $RE_FILE ]] || exit 0
FILE=${BASH_REMATCH[1]//\\\\//}; FILE=${FILE//\\//}
SESSION=""; [[ $INPUT =~ $RE_SID ]] && SESSION=${BASH_REMATCH[1]}

SKILL=""
case "$FILE" in
  */test/*|*/tests/*|*.test.*|*.spec.*|*Test.php|*_test.dart|*/test_*.py|*_test.py|*/phpunit.xml*)
    SKILL="testing-patterns" ;;
  *.tsx|*.jsx|*.vue|*.svelte|*.css|*.scss|*_screen.dart|*_page.dart|*/presentation/*|*/templates/*.html|*/parts/*.html|*/patterns/*.php|*/theme.json)
    SKILL="ui-quality" ;;
esac
[ -z "$SKILL" ] && exit 0
# Only nudge for skills this project actually ships.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[ -f "$ROOT/.claude/skills/$SKILL/SKILL.md" ] || exit 0

STATE_DIR="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || echo "${TMPDIR:-/tmp}")/session-guard"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE="$STATE_DIR/nudge-${SESSION:-unknown}"
grep -qxF "$SKILL" "$STATE" 2>/dev/null && exit 0
echo "$SKILL" >>"$STATE"

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"skill-nudge: you are editing %s files. If the %s skill is not loaded in this session yet, load it now (Skill tool) and apply it to this change."}}\n' \
  "$([ "$SKILL" = testing-patterns ] && echo test || echo UI)" "$SKILL"
exit 0
