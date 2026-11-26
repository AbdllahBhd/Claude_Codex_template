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
#   - Flutter/Dart: `.fvmrc` → `scripts/flutter.sh` if present, else the FVM
#     cache (`${FVM_CACHE_PATH:-~/fvm}/versions/<pin>`), else `fvm`; never an
#     unpinned SDK (NOT RUN). A pub workspace root analyzes each member package.
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

# Message shown to the USER only — does not make Claude take another turn.
# Any text is escaped (backslash first) so a captured multi-line log cannot
# make the JSON invalid — Claude Code drops an invalid notice silently.
user_note() {
  local m=${1//\\/\\\\}; m=${m//\"/\\\"}
  m=${m//$'\r'/\\r}; m=${m//$'\n'/\\n}; m=${m//$'\t'/\\t}
  m=$(printf '%s' "$m" | tr -d '\000-\010\013\014\016-\037\177')
  printf '{"systemMessage":"%s"}\n' "$m"
}

# Run from the project root no matter where Claude cd'ed to. A wrong
# CLAUDE_PROJECT_DIR would otherwise disable every gate without a word; Claude
# cannot fix the variable, so tell the user instead of blocking.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { user_note "done-gate: NOT RUN — cannot enter the project directory $ROOT (check CLAUDE_PROJECT_DIR)."; exit 0; }

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
# No fallback to a predictable /tmp name: another user could pre-create it.
LOGDIR=$(mktemp -d 2>/dev/null) || { user_note "done-gate: NOT RUN — mktemp -d failed (check TMPDIR)."; exit 0; }
trap 'rm -rf "$LOGDIR"' EXIT
NL=$'\n'
CODE_FAILURES=""
ENV_FAILURES=""
ENV_DETAIL=""
SDK_NOTE=""
RAN=""

# Output that SUGGESTS the environment is down. Never trusted alone: a failure
# counts as environment-down only if (a) it matches, (b) the log shows no code
# error markers, and (c) the environment probe confirms it is down.
ENV_DOWN='Cannot connect to the Docker daemon|spawn docker ENOENT|connect ENOENT [^ ]*docker\.sock|could not be found in this WSL|docker: (command )?not found|Docker daemon (is )?not (running|reachable)|service "?[A-Za-z0-9_-]+"? is not running|wp-env (is )?not (running|started)|[Ee]nvironment (is )?not initiali[sz]ed|[Ee]nvironment has not yet been initiali[sz]ed|UNC paths are not supported|CMD\.EXE was started with the above path'
# Markers of real code findings (tsc, eslint, phpcs, phpunit, dart, pytest...).
CODE_ERR='error TS[0-9]+|[A-Za-z0-9_./\\-]+\.[A-Za-z]{1,5}[:(][0-9]+([:,][0-9]+)?\)?:? *(error|ERROR|Error|warning)|FOUND [0-9]+ ERRORS?|✖ [0-9]+ problems?|^FAILURES!|^Tests: .*[0-9]+ failed|^E +[A-Za-z]+Error|^ *(error|ERROR|warning|info) [•-] |Some tests failed'

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
  # </dev/null: a prompting tool (fvm install?) must neither hang the stop nor
  # read the workspace-member list the caller loops over.
  if ! "$@" >"$log" 2>&1 </dev/null; then
    if env_down_failure "$log"; then
      ENV_FAILURES="$ENV_FAILURES $label"
      [ -z "$ENV_DETAIL" ] && ENV_DETAIL=$(tail -3 "$log")
    else
      # A local gate often bundles several checks; 30 lines would cut the
      # labels of the earliest failing ones.
      local keep=30; [[ $label == local-* ]] && keep=100
      CODE_FAILURES="${CODE_FAILURES}${NL}--- $label FAILED ($*) ---${NL}$(tail -"$keep" "$log")"
    fi
  fi
}

has_npm_script() { [ -f package.json ] && grep -q "\"$1\"[[:space:]]*:" package.json; }
has_composer_script() { [ -f composer.json ] && grep -q "\"$1\"[[:space:]]*:" composer.json; }
full() { [ "${DONE_GATE_FULL:-0}" = "1" ]; }
in_dir() { local d=$1; shift; (cd "$d" && "$@"); }
# Members listed under `workspace:` in pubspec.yaml (block list form; YAML
# allows the `- item` lines at column 0, a trailing comment and CRLF).
workspace_members() {
  awk '{sub(/\r$/, "")} /^workspace:/ {w=1; next} w && /^[^[:space:]#-]/ {w=0}
       w && /^[[:space:]]*-/ {sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, "")
                              gsub(/["\047]/, ""); sub(/[[:space:]]+$/, ""); print}' pubspec.yaml
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
  if [ -f .fvmrc ] && [ -f scripts/flutter.sh ]; then
    FLUTTER=(bash "$PWD/scripts/flutter.sh")
    # Exit 127 from `--which` = the pinned SDK is not on this machine: no code
    # change fixes that, so it is NOT RUN, not a block. A wrapper without
    # --which fails differently and is simply used.
    # On success its last line names the flutter binary (or `fvm flutter`),
    # whose own dart runs pure-Dart members: `flutter test` cannot run tests
    # that resolve package URIs (CI runs `dart test`).
    WHICH=$(bash scripts/flutter.sh --which 2>&1)
    case $? in
      127) SDK_NOTE=$WHICH; FLUTTER=() ;;
      0) W=${WHICH##*$'\n'}
         if [ -f "$W" ] && [ -x "$W" ]; then [ -x "$(dirname "$W")/dart" ] && DART=("$(dirname "$W")/dart")
         elif [ "${W%% *}" = fvm ]; then DART=(fvm dart)
         elif W=$(command -v "${W%% *}") && [ -x "$(dirname "$W")/dart" ]; then DART=("$(dirname "$W")/dart")
         fi ;;
    esac
  elif [ -f .fvmrc ]; then
    # Never fall back to a global SDK here: it rarely matches the pin. A cache
    # moved with `fvm config --cache-path` is found only via fvm or FVM_CACHE_PATH.
    PIN=$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc | head -1)
    SDK="${FVM_CACHE_PATH:-$HOME/fvm}/versions/$PIN/bin"
    # A version name never holds / or ..: one that does could point outside the cache.
    case $PIN in */*|*..*) SDK_NOTE="the .fvmrc pin '$PIN' is not a Flutter version name" ;; esac
    if [ -n "$SDK_NOTE" ]; then :
    elif [ -n "$PIN" ] && [ -x "$SDK/flutter" ]; then FLUTTER=("$SDK/flutter"); [ -x "$SDK/dart" ] && DART=("$SDK/dart")
    elif command -v fvm >/dev/null 2>&1; then FLUTTER=(fvm flutter); DART=(fvm dart)
    else SDK_NOTE="Flutter ${PIN:-?} pinned in .fvmrc is not in ${SDK%/bin} and fvm is not on PATH"
    fi
  elif command -v flutter >/dev/null 2>&1; then FLUTTER=(flutter)
  fi
  # A pinned SDK pins dart too: never pair it with the global dart.
  [ ! -f .fvmrc ] && [ ${#DART[@]} -eq 0 ] && command -v dart >/dev/null 2>&1 && DART=(dart)
  MEMBERS=$(workspace_members)
  if [ -n "$SDK_NOTE" ]; then :
  elif [ -n "$MEMBERS" ] && [ $(( ${#DART[@]} + ${#FLUTTER[@]} )) -gt 0 ]; then
    # A pub workspace root analyzes nothing useful on its own: run each member,
    # Flutter members (and every member when no pinned dart is known) with
    # flutter, pure Dart members with dart (--fatal-infos, as flutter analyze).
    while IFS= read -r m; do
      if [ ! -d "$m" ]; then   # pub would fail on it too: never skip silently
        RAN="$RAN member-$m"
        CODE_FAILURES="${CODE_FAILURES}${NL}--- workspace member $m is listed in pubspec.yaml but missing ---"
        continue
      fi
      if [ ${#FLUTTER[@]} -gt 0 ] && { [ ${#DART[@]} -eq 0 ] || grep -qE 'sdk:[[:space:]]*flutter' "$m/pubspec.yaml" 2>/dev/null; }; then
        run_gate "analyze ${m//\//-}" in_dir "$m" "${FLUTTER[@]}" analyze --no-pub
        full && [ -d "$m/test" ] && run_gate "tests ${m//\//-}" in_dir "$m" "${FLUTTER[@]}" test
      else
        run_gate "analyze ${m//\//-}" in_dir "$m" "${DART[@]}" analyze --fatal-infos
        full && [ -d "$m/test" ] && run_gate "tests ${m//\//-}" in_dir "$m" "${DART[@]}" test
      fi
    done <<<"$MEMBERS"
  elif [ ${#FLUTTER[@]} -gt 0 ]; then
    run_gate "analyze" "${FLUTTER[@]}" analyze --no-pub
    full && run_gate "tests" "${FLUTTER[@]}" test
  elif [ ${#DART[@]} -gt 0 ]; then
    run_gate "analyze" "${DART[@]}" analyze --fatal-infos
  fi
fi

# Project-owned extra gates (template sync never touches .claude/hooks/local/).
for f in .claude/hooks/local/*.sh; do
  [ -f "$f" ] && run_gate "local-$(basename "$f" .sh)" bash "$f"
done

[ -z "$RAN" ] && [ -z "$SDK_NOTE" ] && exit 0   # no gate defined for this stack

if [ -n "$CODE_FAILURES" ]; then
  printf 'DONE-GATE BLOCKED: quality gates failed on the code.\nFix these before finishing:%s\n' "$CODE_FAILURES" >&2
  exit 2
fi

# NOT RUN goes to the user only (systemMessage): sending it to Claude would
# force an extra turn on every stop while the environment stays down.
NOTE=""
[ -n "$SDK_NOTE" ] && NOTE="done-gate: NOT RUN for Flutter — ${SDK_NOTE}. Run analyze/tests on a machine with the pinned SDK before merging."
[ -n "$ENV_FAILURES" ] && NOTE="${NOTE:+$NOTE$NL}done-gate: NOT RUN for${ENV_FAILURES} — the environment is down (Docker/wp-env). Start it and re-check before merging.${NL}${ENV_DETAIL}"
[ -n "$NOTE" ] && { user_note "$NOTE"; exit 0; }

[ -n "$STAMP" ] && printf '%s' "$FINGERPRINT" >"$STAMP"
exit 0
