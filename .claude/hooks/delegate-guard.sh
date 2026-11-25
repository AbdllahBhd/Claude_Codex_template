#!/usr/bin/env bash
# PreToolUse hook (Agent|Task and browser MCP tools). Audit 2026-11-25: half of
# all Agent calls named no model (so they inherited Opus), and ~4,000 browser
# calls ran in main threads, each screenshot re-read on every later turn.
#   - Agent/Task with no `model` whose agent file sets none either → one warning
#     per session pointing to workflow.md's model table. An agent file with an
#     explicit `model:` line (even `inherit`, as code-reviewer has) is a choice: silent.
#   - Browser tool called from the main thread (no `agent_id` in the hook input,
#     per https://code.claude.com/docs/en/hooks) → one reminder per session.
# DELEGATE_GUARD=strict → deny model-less Agent calls (exit 2); =off → silent.

set -uo pipefail

INPUT=$(cat)
MODE="${DELEGATE_GUARD:-warn}"
[ "$MODE" = "off" ] && exit 0

# No jq dependency: bash regex. The prompt is JSON-escaped, so a "model" key
# quoted inside it appears as \"model\" and does not match.
field() { local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""; [[ $INPUT =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"; }
TOOL=$(field tool_name)
SESSION=$(field session_id)
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

once() {  # once <key>: true the first time this session sees <key>
  local dir
  dir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || echo "${TMPDIR:-/tmp}")/session-guard"
  mkdir -p "$dir" 2>/dev/null || return 0
  grep -qxF "$1" "$dir/delegate-${SESSION:-unknown}" 2>/dev/null && return 1
  echo "$1" >>"$dir/delegate-${SESSION:-unknown}"
}
# Lines between the opening and closing `---` of an agent file.
frontmatter() { awk '{sub(/\r$/, "")} NR == 1 && $0 != "---" {exit} NR > 1 && $0 == "---" {exit} NR > 1 {print}' "$1"; }
context() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$1"
}

case "$TOOL" in
  Agent|Task)
    [ -n "$(field model)" ] && exit 0
    # Sanitised: it goes into the JSON reply unescaped.
    TYPE=$(field subagent_type | tr -cd 'A-Za-z0-9:_-'); TYPE=${TYPE:-general-purpose}
    # A plugin agent (plugin:name) lives outside these folders: its model is unknowable here.
    case "$TYPE" in *:*) exit 0 ;; esac
    # Claude Code matches the frontmatter `name:`, not the file name; project wins over user.
    for f in "$ROOT/.claude/agents/"*.md "$HOME/.claude/agents/"*.md; do
      [ -f "$f" ] || continue
      FM=$(frontmatter "$f")
      NAME=$(printf '%s\n' "$FM" | sed -n 's/^name:[[:space:]]*//p' | head -1 | tr -d "\"' ")
      [ "${NAME:-$(basename "$f" .md)}" = "$TYPE" ] || continue
      printf '%s\n' "$FM" | grep -qE '^model:[[:space:]]*[^[:space:]]' && exit 0
      break
    done
    MSG="delegate-guard: this $TYPE subagent call names no model, so it inherits the session's (most expensive) model. Pick one from the model table in .claude/rules/workflow.md (Context discipline): haiku for test runs and lookups, sonnet for scripted browser checks and tight builds, session model only where judgment decides quality."
    if [ "$MODE" = "strict" ]; then
      echo "$MSG Re-issue the call with a model parameter (DELEGATE_GUARD=strict)." >&2
      exit 2
    fi
    once agent && context "$MSG"
    ;;
  mcp__Claude_Browser__*|mcp__claude-in-chrome__*)
    [ -n "$(field agent_id)" ] && exit 0
    once browser && context "delegate-guard: browser work in the main thread re-pays every screenshot on each later turn. Unless the user is watching this step, move browser checks to a sonnet subagent that returns text (workflow.md, Screenshots stay out of the main thread)."
    ;;
esac
exit 0
