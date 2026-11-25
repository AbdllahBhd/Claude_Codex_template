#!/usr/bin/env bash
# test-hooks.sh — behaviour tests for .claude/hooks/*.sh (run from repo root).
# Each case builds a throwaway git repo, feeds the hook fake JSON, and checks
# exit code + output. No network, no project files touched.
#
#   bash scripts/test-hooks.sh

set -uo pipefail

TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$TEMPLATE/.claude/hooks"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

new_repo() {
  local d; d=$(mktemp -d)
  git -C "$d" init -q -b main && git -C "$d" config core.autocrlf false \
    && git -C "$d" config user.email t@t && git -C "$d" config user.name t
  mkdir -p "$d/sub/deeper"; echo "x" >"$d/file.txt"
  git -C "$d" add -A && git -C "$d" commit -qm init
  echo "$d"
}

# The exact command string settings.json wires for a hook script.
wired_cmd() { grep -o "\"command\": \"bash [^,]*$1[^,]*\"" "$TEMPLATE/.claude/settings.json" | head -1 | sed 's/^"command": "//; s/"$//; s/\\"/"/g'; }

echo "== syntax"
for f in "$HOOKS"/*.sh; do
  if bash -n "$f"; then ok "bash -n $(basename "$f")"; else bad "bash -n $(basename "$f")"; fi
done

echo "== T1 wired commands run from a subdirectory"
R=$(new_repo)
mkdir -p "$R/.claude" "$R/scripts"; cp -r "$HOOKS" "$R/.claude/hooks"
printf '#!/usr/bin/env bash\ntouch .synced\n' >"$R/scripts/sync-codex.sh"
for h in validate-code sync-codex-on-edit done-gate session-guard repo-guard skill-nudge; do
  C=$(wired_cmd "$h.sh")
  if [ -z "$C" ]; then bad "$h is wired in settings.json"; continue; fi
  has "$C" '$CLAUDE_PROJECT_DIR' || bad "$h command uses \$CLAUDE_PROJECT_DIR" "$C"
  OUT=$(cd "$R/sub/deeper" && echo '{}' | CLAUDE_PROJECT_DIR="$R" bash -c "$C" 2>&1)
  has "$OUT" "No such file" && bad "$h runs from a subfolder" "$OUT" || ok "$h runs from a subfolder (wired command)"
done
printf 'const api_key = "%s";\n' "abcdefghijklmnopqrstuvwx" >"$R/sub/leak.ts"
OUT=$(cd "$R/sub/deeper" && printf '{"tool_input":{"file_path":"%s"}}' "$R/sub/leak.ts" \
  | CLAUDE_PROJECT_DIR="$R" bash -c "$(wired_cmd validate-code.sh)" 2>&1); RC=$?
[ $RC -eq 2 ] && ok "validate-code blocks a planted secret" || bad "validate-code secret" "rc=$RC $OUT"
(cd "$R/sub/deeper" && echo '{"tool_input":{"file_path":"x/.claude/skills/a/SKILL.md"}}' \
  | CLAUDE_PROJECT_DIR="$R" bash -c "$(wired_cmd sync-codex-on-edit.sh)" >/dev/null 2>&1)
[ -f "$R/.synced" ] && ok "sync-codex-on-edit really ran the sync from a subfolder" || bad "sync did not run"

echo "== T2 done-gate"
R=$(new_repo); C=$(mktemp)
gate() { (cd "$R/sub" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R" "$@" bash "$HOOKS/done-gate.sh" 2>&1); }
runs() { wc -l <"$C" | tr -d ' '; }
OUT=$(gate env DONE_GATE_CMD="echo run >>'$C'; exit 0"); RC=$?
[ $RC -eq 0 ] && [ "$(runs)" -eq 1 ] && ok "passing gate runs once" || bad "pass" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_CMD="echo run >>'$C'; exit 0"); RC=$?
[ $RC -eq 0 ] && [ "$(runs)" -eq 1 ] && ok "unchanged tree skips the gate" || bad "skip unchanged" "runs=$(runs)"
echo "change" >>"$R/file.txt"
OUT=$(gate env DONE_GATE_CMD="echo run >>'$C'; exit 0"); RC=$?
[ $RC -eq 0 ] && [ "$(runs)" -eq 2 ] && ok "a change re-runs the gate" || bad "rerun after change" "rc=$RC runs=$(runs)"
echo "c2" >>"$R/file.txt"
OUT=$(gate env DONE_GATE_CMD="echo 'src/a.php:3 error: missing docblock'; exit 1"); RC=$?
[ $RC -eq 2 ] && has "$OUT" "a.php:3" && ok "real lint failure blocks with details" || bad "code failure" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_CMD='echo "D:\code\app.ts:3 error TS2322: bad"; echo tail-line; exit 1'); RC=$?
[ $RC -eq 2 ] && has "$OUT" 'D:\code\app.ts' && has "$OUT" "tail-line" && ok "Windows paths in output are not truncated" || bad "backslash output" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD="echo 'src/a.ts:1 error: x is undefined'; echo 'Error: Environment not initialized'; exit 1"); RC=$?
[ $RC -eq 2 ] && ok "code error + env-down text still blocks" || bad "mixed log" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_ENV_PROBE=true DONE_GATE_CMD="echo 'Error: service \"cli\" is not running'; exit 1"); RC=$?
[ $RC -eq 2 ] && ok "env-down text but environment UP -> blocks" || bad "probe up" "rc=$RC $OUT"
B=$(runs)
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD="echo run >>'$C'; echo 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock'; exit 1"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ok "Docker down -> NOT RUN, no block" || bad "env down" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD="echo run >>'$C'; echo 'Error: service \"cli\" is not running'; exit 1"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && [ "$(runs)" -eq $((B+2)) ] && ok "env-down run is not stamped (next stop re-runs)" || bad "env-down stamp" "rc=$RC runs=$(runs) $OUT"
OUT=$(gate env DONE_GATE_MODE=manual DONE_GATE_CMD="exit 1"); RC=$?
[ $RC -eq 0 ] && ok "manual mode never blocks" || bad "manual" "rc=$RC"
OUT=$(cd "$R" && echo '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$R" DONE_GATE_CMD="exit 1" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "stop_hook_active prevents a loop" || bad "loop guard"
if command -v npm >/dev/null 2>&1; then
  R2=$(new_repo)
  printf '{"name":"t","version":"1.0.0","scripts":{"lint":"node -e \\"console.log(String.fromCharCode(108)+\\x27int.js:2 error bad\\x27);process.exit(1)\\""}}\n' >"$R2/package.json"
  OUT=$(cd "$R2" && echo '{}' | CLAUDE_PROJECT_DIR="$R2" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
  [ $RC -eq 2 ] && has "$OUT" "lint FAILED" && ok "npm lint script detected and enforced" || bad "npm detection" "rc=$RC $OUT"
else
  echo "  skip npm detection (npm not installed)"
fi

echo "== T3/T4 session-guard"
R=$(new_repo); T=$(mktemp)
usage() { printf '{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":9}}}\n' "$1" "$2" >>"$T"; }
TP=$(cd "$(dirname "$T")" && pwd -W 2>/dev/null)/$(basename "$T"); [ "${TP#/}" = "$TP" ] || TP=$T
TPJ=${TP//\\/\\\\}   # JSON-escaped, as Claude Code sends Windows paths
sg() { (cd "$R/sub" && printf '{"session_id":"s1","transcript_path":"%s"}' "$TPJ" | CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/session-guard.sh" 2>&1); }
usage 1000 99000
OUT=$(sg); [ -z "$OUT" ] && ok "100k context: silent" || bad "small context" "$OUT"
usage 1000 148000
OUT=$(sg); [ -z "$OUT" ] && ok "149k context (just under 150k): silent" || bad "below threshold" "$OUT"
usage 2000 148000
OUT=$(sg); has "$OUT" "150k" && ok "150k context: warns (JSON-escaped path)" || bad "big context" "$OUT"
has "$OUT" "docs/handoff.md" && ok "context warning asks for a handoff in docs/handoff.md" || bad "handoff path" "$OUT"
if has "$OUT" "ONE short line, then continue"; then bad "wrapper contradicts handoff step" "$OUT"; else ok "wrapper does not cap the reply at one line"; fi
OUT=$(sg); [ -z "$OUT" ] && ok "same level: warns only once" || bad "repeat warning" "$OUT"
usage 2000 300000
OUT=$(sg); has "$OUT" "302k" && ok "next step (+150k): warns again" || bad "step warning" "$OUT"
usage 2000 20000
OUT=$(sg); [ -z "$OUT" ] && ok "after /compact: silent" || bad "post-compact" "$OUT"
usage 2000 160000
OUT=$(sg); has "$OUT" "162k" && ok "re-armed: warns again after growing back" || bad "re-arm" "$OUT"
git -C "$R" checkout -qb feat/other
OUT=$(sg); has "$OUT" "branch changed" && ok "branch change: warns" || bad "branch" "$OUT"
OUT=$(sg); [ -z "$OUT" ] && ok "branch warning only once" || bad "branch repeat" "$OUT"
seq 1 400 >"$R/task_plan.md"
OUT=$(sg); has "$OUT" "task_plan.md is 400 lines" && ok "400-line plan: warns" || bad "plan size" "$OUT"

echo "== T9 repo-guard"
R=$(new_repo); O=$(new_repo); O2=$(new_repo)
rg() { (printf '{"session_id":"s1","cwd":"%s","tool_input":{"command":"%s"}}' "$2" "$1" | CLAUDE_PROJECT_DIR="$R" REPO_GUARD_ALLOW="" bash "$HOOKS/repo-guard.sh" 2>&1); }
OUT=$(rg "cd sub && ls" "$R/sub"); [ -z "$OUT" ] && ok "cd inside project: silent" || bad "inside" "$OUT"
OUT=$(rg "cd .." "$R"); [ -z "$OUT" ] && ok "cd .. from a subfolder back to root: silent" || bad "cd .. false alarm" "$OUT"
OUT=$(rg "cd $O && git status" "$O"); has "$OUT" additionalContext && ok "cd into another repo: warns" || bad "outside cd" "$OUT"
OUT=$(rg "ls" "$O"); [ -z "$OUT" ] && ok "same folder warned once" || bad "repeat" "$OUT"
OUT=$(rg "git -C $O2 log -1" "$R"); has "$OUT" additionalContext && ok "git -C another repo: warns" || bad "git -C" "$OUT"
OUT=$(rg "ls -la" "$R"); [ -z "$OUT" ] && ok "no cd, inside project: silent" || bad "no cd" "$OUT"
W=$(cd "$O2" && pwd -W 2>/dev/null) || W=""
if [ -n "$W" ]; then   # Git Bash only: JSON-escaped Windows path whose folder starts with "n"
  N="$O2/nvidia_x"; mkdir -p "$N"; WN=$(cd "$N" && pwd -W); WNJ=${WN//\//\\\\\\\\}
  OUT=$(rg "cd $WNJ && ls" "$R"); has "$OUT" nvidia_x && ok "escaped Windows path (\\\\n...) decoded and warned" || bad "win cd decode" "$OUT"
fi
OUT=$(REPO_GUARD_ALLOW="$O2" bash -c "printf '{\"session_id\":\"s2\",\"cwd\":\"%s\",\"tool_input\":{\"command\":\"ls\"}}' '$O2' | CLAUDE_PROJECT_DIR='$R' bash '$HOOKS/repo-guard.sh'"); [ -z "$OUT" ] && ok "allowed prefix: silent" || bad "allowlist" "$OUT"

echo "== T11 skill-nudge"
R=$(new_repo); mkdir -p "$R/.claude/skills/testing-patterns" "$R/tests"; touch "$R/.claude/skills/testing-patterns/SKILL.md"
sn() { printf '{"session_id":"s1","tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/skill-nudge.sh" 2>&1; }
OUT=$(sn "$R/tests/OrderTest.php"); has "$OUT" testing-patterns && ok "test file: nudges testing-patterns" || bad "test nudge" "$OUT"
OUT=$(sn "$R/tests/OtherTest.php"); [ -z "$OUT" ] && ok "nudges once per session" || bad "repeat nudge" "$OUT"
OUT=$(printf '{"session_id":"s-win","tool_input":{"file_path":"%s"}}' 'D:\\proj\\tests\\x_test.dart' | CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/skill-nudge.sh" 2>&1)
has "$OUT" testing-patterns && ok "JSON-escaped Windows path parsed (nudges)" || bad "win path" "$OUT"
OUT=$(sn "$R/src/App.tsx"); [ -z "$OUT" ] && ok "skill not shipped: silent" || bad "missing skill" "$OUT"
OUT=$(sn "$R/README.md"); [ -z "$OUT" ] && ok "other file: silent" || bad "other file" "$OUT"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
