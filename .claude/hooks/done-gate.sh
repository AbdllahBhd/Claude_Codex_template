#!/usr/bin/env bash
# Stop hook: the "definition of done" gate (wired in .claude/settings.json).
# Fires when Claude tries to end its turn. If lint/typecheck FAIL because of
# the code, Claude is blocked from stopping (exit 2) and must fix them first.
#
# Built to be cheap and honest (evidence: 5-project usage audit, 2026-11):
#   - Skips silently when nothing changed since the last passing run, so
#     chat-only turns cost no gate time.
#   - When the ENVIRONMENT is down (Docker, wp-env, UNC paths), it does NOT
#     block: it reports "NOT RUN" to the user instead of sending Claude off
#     to repair containers.
#   - Flutter/Dart: `.fvmrc` → `scripts/flutter.sh` if present, else `fvm
#     flutter`/`fvm dart`; a pub workspace root analyzes each member package.
#
# Configuration (env vars, e.g. in .claude/settings.json "env"):
#   DONE_GATE_MODE=manual   owner runs gates by hand (localhost-first projects)
#   DONE_GATE_CMD="..."     one custom gate command (any stack: pytest, ruff...)
#   DONE_GATE_FULL=1        also run the test suite on this stop
#   DONE_GATE_ENV_PROBE=".." command that exits 0 when the environment is UP
#                           (default: docker answers and has running containers),
#                           e.g. "curl -fsS -o /dev/null http://localhost:8896"
#   DONE_GATE_ENV_PORT=8896 environment is UP only if a running container
#                           publishes this host port (several sites, one Docker)
#   SKIP_DONE_GATE=1        disable entirely
# Project-specific extra gates: .claude/hooks/local/*.sh (each one runs; a
# non-zero exit blocks like any other gate).
#
# Loop protection: stop_hook_active=true means we already blocked once.

set -uo pipefail

INPUT=$(cat)

[ "${SKIP_DONE_GATE:-0}" = "1" ] && exit 0
[ "${DONE_GATE_MODE:-auto}" = "manual" ] && exit 0
printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

# Run from the project root no matter where Claude cd'ed to.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

# Message shown to the USER only — does not make Claude take another turn.
# Any text is escaped (backslash first) so a captured multi-line log cannot
# make the JSON invalid — Claude Code drops an invalid notice silently.
user_note() {
  local m=${1//\\/\\\\}; m=${m//\"/\\\"}
  m=${m//$'\r'/\\r}; m=${m//$'\n'/\\n}; m=${m//$'\t'/\\t}
  m=$(printf '%s' "$m" | tr -d '\000-\010\013\014\016-\037\177')
  printf '{"systemMessage":"%s"}\n' "$m"
}

# UNC working directory (\\wsl.localhost\... opened from Windows): npm spawns
# CMD.EXE, which cannot use UNC paths — every gate would fail falsely.
case "$PWD" in
  //*) user_note "done-gate: NOT RUN — UNC working directory. Open WSL projects from inside WSL."; exit 0 ;;
esac

# --- Skip when nothing changed since the last pass -------------------------
# Fingerprint = HEAD + tracked changes + untracked (non-ignored) contents.
# Gitignored files (.env, ignored codegen) are not part of it: a change there
# alone does not re-run the gate.
FINGERPRINT=""
STAMP=""
if GIT_DIR=$(git rev-parse --git-dir 2>/dev/null); then
  STAMP="$GIT_DIR/done-gate.last"
  FINGERPRINT=$({
    git rev-parse HEAD 2>/dev/null
    git status --porcelain 2>/dev/null
    git diff HEAD 2>/dev/null
    git ls-files -o --exclude-standard -z 2>/dev/null | xargs -0 -r git hash-object -- 2>/dev/null
    printf '%s %s' "${DONE_GATE_FULL:-0}" "${DONE_GATE_CMD:-}"
  } | git hash-object --stdin)
  [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$FINGERPRINT" ] && exit 0
fi

# --- Gates ------------------------------------------------------------------
LOGDIR=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/done-gate-$$")
mkdir -p "$LOGDIR"; trap 'rm -rf "$LOGDIR"' EXIT
NL=$'\n'
CODE_FAILURES=""
ENV_FAILURES=""
ENV_DETAIL=""
RAN=""

# Output that SUGGESTS the environment is down. Never trusted alone: a failure
# counts as environment-down only if (a) it matches, (b) the log shows no code
# error markers, and (c) the environment probe confirms it is down.
ENV_DOWN='Cannot connect to the Docker daemon|spawn docker ENOENT|could not be found in this WSL|docker: (command )?not found|Docker daemon (is )?not (running|reachable)|service "?[A-Za-z0-9_-]+"? is not running|wp-env (is )?not (running|started)|[Ee]nvironment (is )?not initiali[sz]ed|UNC paths are not supported|CMD\.EXE was started with the above path'
# Markers of real code findings (tsc, eslint, phpcs, phpunit, dart, pytest...).
CODE_ERR='error TS[0-9]+|[A-Za-z0-9_./\\-]+\.[A-Za-z]{1,5}[:(][0-9]+([:,][0-9]+)?\)?:? *(error|ERROR|Error|warning)|FOUND [0-9]+ ERRORS?|✖ [0-9]+ problems?|^FAILURES!|^Tests: .*[0-9]+ failed|^E +[A-Za-z]+Error|^(error|ERROR) [•-] '

# Is the environment UP? Default: Docker answers and has running containers.
# DONE_GATE_ENV_PORT narrows it to this project's container; DONE_GATE_ENV_PROBE
# replaces the check entirely (exit 0 = environment up).
env_up() {
  if [ -n "${DONE_GATE_ENV_PROBE:-}" ]; then bash -c "$DONE_GATE_ENV_PROBE" >/dev/null 2>&1; return; fi
  command -v docker >/dev/null 2>&1 || return 1
  # A half-broken Docker Desktop can hang its pipe: never wait more than 10s.
  local t=""; command -v timeout >/dev/null 2>&1 && t="timeout 10"
  if [ -n "${DONE_GATE_ENV_PORT:-}" ]; then
    # No pipe into grep -q: under pipefail its early exit SIGPIPEs docker.
    local ports; ports=$($t docker ps --format '{{.Ports}}' 2>/dev/null) || return 1
    [[ $ports == *":$DONE_GATE_ENV_PORT->"* ]]; return
  fi
  $t docker info >/dev/null 2>&1 || return 1
  [ -n "$($t docker ps -q 2>/dev/null)" ]
}

env_down_failure() { # $1 = log
  grep -qE "$ENV_DOWN" "$1" || return 1
  grep -qE "$CODE_ERR" "$1" && return 1
  grep -qE 'UNC paths are not supported|CMD\.EXE was started' "$1" && return 0
  ! env_up
}

run_gate() { # $1 = label, rest = command
  local label=$1; shift
  local log="$LOGDIR/${label// /_}.log"
  RAN="$RAN $label"
  if ! "$@" >"$log" 2>&1; then
    if env_down_failure "$log"; then
      ENV_FAILURES="$ENV_FAILURES $label"
      [ -z "$ENV_DETAIL" ] && ENV_DETAIL=$(tail -3 "$log")
    else
      CODE_FAILURES="${CODE_FAILURES}${NL}--- $label FAILED ($*) ---${NL}$(tail -30 "$log")"
    fi
  fi
}

has_npm_script() { [ -f package.json ] && grep -q "\"$1\"[[:space:]]*:" package.json; }
has_composer_script() { [ -f composer.json ] && grep -q "\"$1\"[[:space:]]*:" composer.json; }
full() { [ "${DONE_GATE_FULL:-0}" = "1" ]; }
in_dir() { local d=$1; shift; (cd "$d" && "$@"); }
# Members listed under `workspace:` in pubspec.yaml (block list form).
workspace_members() {
  awk '/^workspace:/ {w=1; next} w && /^[^[:space:]#]/ {w=0}
       w && /^[[:space:]]*-/ {sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/["\047]/, ""); print}' pubspec.yaml
}

if [ -n "${DONE_GATE_CMD:-}" ]; then
  run_gate "custom" bash -c "$DONE_GATE_CMD"
elif [ -f package.json ]; then
  has_npm_script lint      && run_gate "lint" npm run lint --silent
  has_npm_script typecheck && run_gate "typecheck" npm run typecheck --silent
  full && has_npm_script test && run_gate "tests" npm test --silent
elif [ -f composer.json ] && command -v composer >/dev/null 2>&1; then
  has_composer_script lint && run_gate "lint" composer run-script lint
  full && has_composer_script test && run_gate "tests" composer run-script test
elif [ -f pubspec.yaml ]; then
  # FVM-pinned projects must not run the global SDK; a project wrapper wins.
  # Arrays + absolute wrapper path: members run from their own directory.
  FLUTTER=(); DART=()
  if [ -f .fvmrc ] && [ -f scripts/flutter.sh ]; then FLUTTER=(bash "$PWD/scripts/flutter.sh")
  elif [ -f .fvmrc ] && command -v fvm >/dev/null 2>&1; then FLUTTER=(fvm flutter); DART=(fvm dart)
  elif command -v flutter >/dev/null 2>&1; then FLUTTER=(flutter)
  fi
  # The wrapper pins dart too: never pair it with the global dart.
  [ ${#DART[@]} -eq 0 ] && [ "${FLUTTER[0]:-}" != bash ] && command -v dart >/dev/null 2>&1 && DART=(dart)
  MEMBERS=$(workspace_members)
  if [ -n "$MEMBERS" ] && [ $(( ${#DART[@]} + ${#FLUTTER[@]} )) -gt 0 ]; then
    # A pub workspace root analyzes nothing useful on its own: run each member,
    # Flutter members (and every member when only the pinned wrapper exists)
    # with flutter, pure Dart members with dart.
    for m in $MEMBERS; do
      [ -d "$m" ] || continue
      if [ ${#FLUTTER[@]} -gt 0 ] && { [ ${#DART[@]} -eq 0 ] || grep -qE 'sdk:[[:space:]]*flutter' "$m/pubspec.yaml" 2>/dev/null; }; then
        run_gate "analyze ${m//\//-}" in_dir "$m" "${FLUTTER[@]}" analyze --no-pub
        full && [ -d "$m/test" ] && run_gate "tests ${m//\//-}" in_dir "$m" "${FLUTTER[@]}" test
      else
        run_gate "analyze ${m//\//-}" in_dir "$m" "${DART[@]}" analyze
        full && [ -d "$m/test" ] && run_gate "tests ${m//\//-}" in_dir "$m" "${DART[@]}" test
      fi
    done
  elif [ ${#FLUTTER[@]} -gt 0 ]; then
    run_gate "analyze" "${FLUTTER[@]}" analyze --no-pub
    full && run_gate "tests" "${FLUTTER[@]}" test
  elif [ ${#DART[@]} -gt 0 ]; then
    run_gate "analyze" "${DART[@]}" analyze
  fi
fi

# Project-owned extra gates (template sync never touches .claude/hooks/local/).
for f in .claude/hooks/local/*.sh; do
  [ -f "$f" ] && run_gate "local-$(basename "$f" .sh)" bash "$f"
done

[ -z "$RAN" ] && exit 0   # no gate defined for this stack

if [ -n "$CODE_FAILURES" ]; then
  printf 'DONE-GATE BLOCKED: quality gates failed on the code.\nFix these before finishing:%s\n' "$CODE_FAILURES" >&2
  exit 2
fi

# NOT RUN goes to the user only (systemMessage): sending it to Claude would
# force an extra turn on every stop while the environment stays down.
if [ -n "$ENV_FAILURES" ]; then
  user_note "done-gate: NOT RUN for${ENV_FAILURES} — the environment is down (Docker/wp-env). Start it and re-check before merging.${NL}${ENV_DETAIL}"
  exit 0
fi

[ -n "$STAMP" ] && printf '%s' "$FINGERPRINT" >"$STAMP"
exit 0
