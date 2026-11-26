#!/usr/bin/env bash
# test-hooks.sh — behaviour tests for .claude/hooks/*.sh (run from repo root).
# Each case builds a throwaway git repo, feeds the hook fake JSON, and checks
# exit code + output. No network, no project files touched.
#
#   bash scripts/test-hooks.sh

set -uo pipefail
unset TEMPLATE_DIR TEMPLATE_REF   # a developer's own setting must not leak into cases

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
for h in validate-code sync-codex-on-edit done-gate session-guard repo-guard skill-nudge delegate-guard; do
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

echo "== v3 validate-code debug notes"
R=$(new_repo)
vc() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOKS/validate-code.sh" 2>&1; }
printf 'void main() {\n  print("x");\n  debugPrint("y");\n}\n' >"$R/a.dart"
OUT=$(vc "$R/a.dart"); has "$OUT" "print" && ok "Dart bare print( noted" || bad "dart print" "$OUT"
printf 'void main() {\n  debugPrint("y");\n}\n' >"$R/b.dart"
OUT=$(vc "$R/b.dart"); [ -z "$OUT" ] && ok "Dart debugPrint alone: silent" || bad "dart debugPrint" "$OUT"
printf 'export const a = 1;\nconsole.log(a);\n' >"$R/c.mjs"
OUT=$(vc "$R/c.mjs"); has "$OUT" "console.log" && ok "*.mjs console.log noted" || bad "mjs" "$OUT"

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
echo "c3" >>"$R/file.txt"
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD='printf "Cannot connect to the Docker daemon at x\n\tdetail\tcol\r\nliteral \\\\n end\001\n"; exit 1'); RC=$?
SM=$(printf '%s\n' "$OUT" | grep '"systemMessage"')
if ! command -v python3 >/dev/null 2>&1; then echo "  SKIP notice JSON check (no python3)"
elif [ $RC -eq 0 ] && printf '%s' "$SM" | python3 -c 'import json,sys; m=json.loads(sys.stdin.read())["systemMessage"]; assert "literal \\n end" in m and "\tcol" in m, m'; then
  ok "NOT RUN notice with newlines/tabs/literal \\n is valid JSON"
else bad "notice JSON" "rc=$RC $OUT"; fi
FB=$(mktemp -d)   # fake docker: `ps` prints $FAKE_PORTS
printf '#!/usr/bin/env bash\n[ "$1" = ps ] && printf "%%s\\n" "$FAKE_PORTS"; exit 0\n' >"$FB/docker"; chmod +x "$FB/docker"
DOWN="echo 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock'; exit 1"
echo "c4" >>"$R/file.txt"
OUT=$(gate env PATH="$FB:$PATH" FAKE_PORTS="0.0.0.0:8896->80/tcp, :::8896->80/tcp" DONE_GATE_ENV_PORT=8896 DONE_GATE_CMD="$DOWN"); RC=$?
[ $RC -eq 2 ] && ok "ENV_PORT published -> env up -> blocks" || bad "env port up" "rc=$RC $OUT"
OUT=$(gate env PATH="$FB:$PATH" FAKE_PORTS="0.0.0.0:8890->80/tcp" DONE_GATE_ENV_PORT=8896 DONE_GATE_CMD="$DOWN"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ok "only another site's port published -> NOT RUN" || bad "env port other" "rc=$RC $OUT"
ND=$(mktemp -d)   # PATH with every tool the gate needs, but no docker
for b in bash git grep tail cat tr mktemp rm mkdir xargs timeout env sed head wc printf; do
  p=$(command -v "$b") && [ "${p#/}" != "$p" ] && ln -s "$p" "$ND/$b"
done
OUT=$(gate env PATH="$ND" DONE_GATE_CMD="echo 'Error: spawn docker ENOENT'; exit 1"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ok "spawn docker ENOENT, docker absent -> NOT RUN" || bad "ENOENT" "rc=$RC $OUT"
OUT=$(gate env PATH="$ND" DONE_GATE_CMD="echo \"The command 'docker' could not be found in this WSL 2 distro.\"; exit 1"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ok "docker missing in WSL -> NOT RUN" || bad "WSL docker" "rc=$RC $OUT"
echo "c5" >>"$R/file.txt"
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD="echo 'Error: The environment has not yet been initialized. Run wp-env start'; exit 1"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ok "wp-env 'has not yet been initialized' -> NOT RUN" || bad "wp-env init" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD="printf '\033[1mFOUND 3 ERRORS AFFECTING 2 LINES\033[0m\nError: Environment not initialized\n'; exit 1"); RC=$?
[ $RC -eq 2 ] && ok "ANSI-wrapped phpcs FOUND n ERRORS + env-down text still blocks" || bad "ansi phpcs" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_ENV_PROBE=false DONE_GATE_CMD="echo 'Error: connect ENOENT /var/run/docker.sock'; exit 1"); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ok "connect ENOENT docker.sock -> NOT RUN" || bad "docker.sock ENOENT" "rc=$RC $OUT"
mkdir -p "$R/.claude/hooks/local"
printf 'echo "local/extra.sh:1 error: project rule broken"; exit 1\n' >"$R/.claude/hooks/local/extra.sh"
OUT=$(gate env DONE_GATE_CMD="exit 0"); RC=$?
[ $RC -eq 2 ] && has "$OUT" "project rule broken" && ok "failing .claude/hooks/local/*.sh blocks" || bad "local gate fail" "rc=$RC $OUT"
printf 'exit 0\n' >"$R/.claude/hooks/local/extra.sh"
OUT=$(gate env DONE_GATE_CMD="exit 0"); RC=$?
[ $RC -eq 0 ] && ok "passing local gate lets the stop through" || bad "local gate pass" "rc=$RC $OUT"
OUT=$(gate env DONE_GATE_MODE=manual DONE_GATE_CMD="exit 1"); RC=$?
[ $RC -eq 0 ] && ok "manual mode never blocks" || bad "manual" "rc=$RC"
OUT=$(cd "$R" && echo '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$R" DONE_GATE_CMD="exit 1" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "stop_hook_active prevents a loop" || bad "loop guard"
R0=$(new_repo)
OUT=$(cd "$R0" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R0" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "no stack and no DONE_GATE_CMD: silent pass" || bad "no stack" "rc=$RC $OUT"
OUT=$(cd "$R0" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R0/missing" DONE_GATE_CMD="exit 1" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && has "$OUT" "systemMessage" && ok "unreachable project dir -> NOT RUN to the user, no block" || bad "bad ROOT" "rc=$RC $OUT"
mkdir -p "$R0/.claude/hooks/local"
printf 'echo "CHECK-A FAILED: stages"; for i in $(seq 1 40); do echo "a-detail $i"; done; echo "CHECK-B FAILED: unity"; exit 1\n' >"$R0/.claude/hooks/local/areas.sh"
OUT=$(cd "$R0" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R0" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 2 ] && has "$OUT" "CHECK-A FAILED" && has "$OUT" "CHECK-B FAILED" && ok "long local-* gate log keeps its first failure label" || bad "local tail" "rc=$RC $(printf '%s' "$OUT" | head -3)"
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
{ has "$OUT" "finish the current step" && has "$OUT" "do not start a new step"; } && ok "context warning: finish the step, no new step" || bad "stop wording" "$OUT"
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

echo "== v3 session-guard: template behind"
R=$(new_repo); TD=$(new_repo); OLD=$(git -C "$TD" rev-parse HEAD)
echo two >>"$TD/file.txt"; git -C "$TD" commit -qam two; echo three >>"$TD/file.txt"; git -C "$TD" commit -qam three
mkdir -p "$R/.claude"
tg() { (cd "$R" && printf '{"session_id":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$R" "${@:2}" bash "$HOOKS/session-guard.sh" 2>&1); }
printf 'commit %s\nref main\n' "$OLD" >"$R/.claude/template-version"
OUT=$(tg tb1 env TEMPLATE_DIR="$TD"); has "$OUT" "2 commits newer" && has "$OUT" "sync-template.sh" && ok "template behind: notice" || bad "behind" "$OUT"
OUT=$(tg tb1 env TEMPLATE_DIR="$TD"); [ -z "$OUT" ] && ok "behind notice once per session" || bad "behind repeat" "$OUT"
printf 'commit %s\n' "$(git -C "$TD" rev-parse HEAD)" >"$R/.claude/template-version"
OUT=$(tg tb2 env TEMPLATE_DIR="$TD"); [ -z "$OUT" ] && ok "template up to date: silent" || bad "up to date" "$OUT"
OUT=$(tg tb3 env -u TEMPLATE_DIR); [ -z "$OUT" ] && ok "TEMPLATE_DIR unset: silent" || bad "unset" "$OUT"
printf 'commit %s\n' "0123456789abcdef0123456789abcdef01234567" >"$R/.claude/template-version"
OUT=$(tg tb4 env TEMPLATE_DIR="$TD"); [ -z "$OUT" ] && ok "stamp commit unknown to TEMPLATE_DIR: silent" || bad "unknown stamp" "$OUT"
rm "$R/.claude/template-version"
OUT=$(tg tb5 env TEMPLATE_DIR="$TD"); has "$OUT" "never synced" && ok "no stamp: never-synced notice" || bad "never synced" "$OUT"
OUT=$(tg tb6 env TEMPLATE_DIR="/nonexistent/x"); [ -z "$OUT" ] && ok "unreadable TEMPLATE_DIR: silent" || bad "bad dir" "$OUT"

echo "== v3 context cap in settings.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("autoCompactWindow")==300000, d.get("autoCompactWindow")' "$TEMPLATE/.claude/settings.json" 2>/dev/null \
  && ok "settings.json is valid JSON with autoCompactWindow=300000" || bad "autoCompactWindow"

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
mkdir -p "$R/.claude/skills/ui-quality"; touch "$R/.claude/skills/ui-quality/SKILL.md"
OUT=$(sn "$R/wp-content/themes/t/template/single.html"); has "$OUT" ui-quality && ok "*/template/*.html: nudges ui-quality" || bad "template html nudge" "$OUT"

echo "== v3 file ownership"
# Every tracked path must have an owner in docs/template-files.md (first match
# wins); sync-template.sh relies on it to know what it may overwrite. A synced
# project (stamped .claude/template-version) has its own files: skip there.
ownership_audit() { # $1 = repo root; prints "skip", "" (all owned) or the unlisted paths
  local root=$1 tf="$1/docs/template-files.md" globs unlisted="" f g hit
  [ -f "$root/.claude/template-version" ] && { echo skip; return; }
  [ -f "$tf" ] || { echo " (no docs/template-files.md)"; return; }
  globs=$(sed -n 's/^| `\([^`]*\)` | \(template\|project\|merged\) |.*/\1/p' "$tf")
  while IFS= read -r f; do
    hit=""; while IFS= read -r g; do [[ $f == $g ]] && { hit=1; break; }; done <<<"$globs"
    [ -z "$hit" ] && unlisted="$unlisted $f"
  done < <(git -C "$root" ls-files)
  echo "$unlisted"
}
TF="$TEMPLATE/docs/template-files.md"
U=$(ownership_audit "$TEMPLATE")
[ -z "$U" ] && ok "every tracked file has an owner in docs/template-files.md" || bad "unlisted paths" "$U"
R=$(new_repo); mkdir -p "$R/docs" "$R/.claude"; cp "$TEMPLATE/docs/template-files.md" "$R/docs/"
echo "commit x" >"$R/.claude/template-version"; touch "$R/app.unlisted"; git -C "$R" add -A; git -C "$R" commit -qm p
U=$(ownership_audit "$R"); [ "$U" = skip ] && ok "ownership audit skipped in a synced project" || bad "audit in project" "$U"
grep -q '^| `.gitattributes` | project |' "$TF" && ok ".gitattributes is project-owned" || bad ".gitattributes owner"

echo "== v3 sync-template"
SYNC="$TEMPLATE/scripts/sync-template.sh"
if ! command -v python3 >/dev/null 2>&1; then echo "  SKIP sync-template (no python3)"
elif [ ! -f "$SYNC" ]; then bad "scripts/sync-template.sh exists"
else
  T=$(new_repo); P=$(new_repo)
  mkdir -p "$T/docs" "$T/.claude/hooks" "$T/.claude/rules"
  cp "$TF" "$T/docs/template-files.md"
  echo 'echo v1' >"$T/.claude/hooks/h.sh"; echo 'rule v1' >"$T/.claude/rules/r.md"; echo gone >"$T/.claude/rules/gone.md"
  echo '{"hooks":{"Stop":["A"]},"permissions":{"allow":["Bash(ls)"]},"env":{}}' >"$T/.claude/settings.json"
  git -C "$T" add -A && git -C "$T" commit -qm one
  mkdir -p "$P/.claude"; cp -r "$T/.claude/hooks" "$T/.claude/rules" "$P/.claude/"
  echo 'my own rule' >"$P/.claude/rules/r.md"
  echo '{"hooks":{"Stop":["A","bash .claude/hooks/local/x.sh","bash .claude/hooks/old.sh"],"PostToolUse":["MINE"]},"permissions":{"allow":["Bash(ls)"]},"env":{"MY_KEY":"1"}}' >"$P/.claude/settings.json"
  git -C "$P" add -A && git -C "$P" commit -qm project
  echo 'echo v2' >"$T/.claude/hooks/h.sh"; echo 'rule v2' >"$T/.claude/rules/r.md"; git -C "$T" rm -q .claude/rules/gone.md
  echo '{"hooks":{"Stop":["A","B"]},"permissions":{"allow":["Bash(ls)","Bash(cat)"]},"env":{}}' >"$T/.claude/settings.json"
  git -C "$T" add -A && git -C "$T" commit -qm two
  st() { (cd "$P" && bash "$SYNC" "$T" --ref main "$@" 2>&1); }
  OUT=$(st); RC=$?
  { has "$OUT" "updated" && has "$OUT" ".claude/hooks/h.sh"; } && ok "dry run: old unmodified hook listed as updated" || bad "dry updated" "rc=$RC $OUT"
  printf '%s\n' "$OUT" | grep -q 'locally modified.*rules/r.md' && ok "dry run: edited rule listed as locally modified" || bad "dry modified" "$OUT"
  printf '%s\n' "$OUT" | grep -q 'removed upstream.*gone.md' && ok "dry run: removed-upstream file listed" || bad "dry removed" "$OUT"
  printf '%s\n' "$OUT" | grep -qE '^ *\+ *"B"' && ok "dry run: settings.json merge shown as a diff" || bad "dry settings diff" "$OUT"
  [ -z "$(git -C "$P" status --porcelain)" ] && ok "dry run leaves the project untouched" || bad "dry run wrote" "$(git -C "$P" status --porcelain)"
  OUT=$(st --apply); RC=$?
  [ "$(cat "$P/.claude/hooks/h.sh")" = "echo v2" ] && ok "--apply updates the old hook" || bad "apply hook" "rc=$RC $OUT"
  [ "$(cat "$P/.claude/rules/r.md")" = "my own rule" ] && ok "--apply keeps the locally modified rule" || bad "apply rule"
  [ -f "$P/.claude/rules/gone.md" ] && ok "--apply never deletes removed-upstream files" || bad "apply deleted"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hooks"]["Stop"]==["A","B","bash .claude/hooks/local/x.sh"] and d["hooks"]["PostToolUse"]==["MINE"] and d["env"]["MY_KEY"]=="1", d' "$P/.claude/settings.json" \
    && ok "--apply merges hooks per event: template entries, project-only hooks kept, old template hooks dropped; env kept" || bad "settings merge" "$(cat "$P/.claude/settings.json")"
  grep -q "$(git -C "$T" rev-parse HEAD)" "$P/.claude/template-version" 2>/dev/null && ok "--apply writes .claude/template-version" || bad "stamp" "$OUT"
  git -C "$P" add -A && git -C "$P" commit -qm synced
  OUT=$(st --apply); RC=$?
  [ $RC -eq 0 ] && [ -z "$(git -C "$P" status --porcelain)" ] && has "$OUT" "no changes" && ok "second --apply: no changes" || bad "second apply" "rc=$RC $OUT $(git -C "$P" status --porcelain)"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["permissions"]["allow"].remove("Bash(cat)"); json.dump(d,open(p,"w"))' "$P/.claude/settings.json"
  git -C "$P" commit -qam "drop cat"; echo 'echo v3' >"$T/.claude/hooks/h.sh"; git -C "$T" commit -qam three
  OUT=$(st --apply); RC=$?
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "Bash(cat)" not in d["permissions"]["allow"], d' "$P/.claude/settings.json" \
    && [ "$(cat "$P/.claude/hooks/h.sh")" = "echo v3" ] && ok "--apply keeps an allow rule the project removed out" || bad "removed allow re-added" "rc=$RC $OUT $(cat "$P/.claude/settings.json")"
  git -C "$P" add -A && git -C "$P" commit -qm three
  X=$(mktemp -d); echo 'echo v3' >"$X/out.sh"; ln -sf "$X/out.sh" "$P/.claude/hooks/h.sh"
  echo 'echo v4' >"$T/.claude/hooks/h.sh"; echo 'café' >"$T/.claude/rules/café.md"; git -C "$T" add -A && git -C "$T" commit -qm four
  OUT=$(st --apply); RC=$?
  [ "$(cat "$T/.claude/rules/café.md")" = "$(cat "$P/.claude/rules/café.md" 2>/dev/null)" ] && ok "--apply handles non-ASCII paths" || bad "non-ASCII path" "rc=$RC $OUT"
  [ "$(cat "$X/out.sh")" = "echo v3" ] && has "$OUT" "symlink" && ok "--apply never writes through a symlink" || bad "symlink write" "rc=$RC $OUT $(cat "$X/out.sh")"
  OUT=$(cd "$P/sub" && bash "$SYNC" "../../$(basename "$T")" --ref main 2>&1); RC=$?
  [ $RC -eq 0 ] && has "$OUT" "Template:" && ok "relative template path works from a subfolder" || bad "relative TPL" "rc=$RC $OUT"
  git -C "$P" add -A && git -C "$P" commit -qm four; STAMP=$(cat "$P/.claude/template-version")
  mkdir -p "$P/scripts"; printf '#!/usr/bin/env bash\nexit 1\n' >"$P/scripts/sync-codex.sh"
  echo new >"$T/.claude/rules/n.md"; git -C "$T" add -A && git -C "$T" commit -qm five
  OUT=$(st --apply); RC=$?
  [ $RC -ne 0 ] && [ "$(cat "$P/.claude/template-version")" = "$STAMP" ] && has "$OUT" "sync-codex" && ok "failed sync-codex: no new stamp, non-zero exit" || bad "sync-codex failure" "rc=$RC $OUT"
  # Real-shaped settings: {matcher, hooks:[{type, command}]} groups, merged per command.
  T2=$(new_repo); P2=$(new_repo); mkdir -p "$T2/docs" "$T2/.claude"; cp "$TF" "$T2/docs/template-files.md"
  G='{"type":"command","command":"bash .claude/hooks/guard.sh"}'
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":['"$G"']}]},"permissions":{"allow":["Bash(ls)","Bash(rm:*)"]}}' >"$T2/.claude/settings.json"
  git -C "$T2" add -A && git -C "$T2" commit -qm one
  (cd "$P2" && bash "$SYNC" "$T2" --ref main --apply >/dev/null 2>&1)
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":['"$G"',{"type":"command","command":"bash .claude/hooks/local/mine.sh"}]}]},"permissions":{"allow":["Bash(ls)","Bash(rm:*)"]}}' >"$P2/.claude/settings.json"
  git -C "$P2" add -A && git -C "$P2" commit -qm mine
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":['"$G"']}],"Stop":[{"hooks":[{"type":"command","command":"bash .claude/hooks/done.sh"}]}]},"permissions":{"allow":["Bash(ls)"]}}' >"$T2/.claude/settings.json"
  git -C "$T2" commit -qam two
  OUT=$(cd "$P2" && bash "$SYNC" "$T2" --ref main --apply 2>&1); RC=$?
  E=$(python3 -c '
import json,sys; d=json.load(open(sys.argv[1])); h=d["hooks"]
cmds=[x["command"] for g in h["PreToolUse"] if g.get("matcher")=="Bash" for x in g["hooks"]]
assert cmds==["bash .claude/hooks/guard.sh","bash .claude/hooks/local/mine.sh"], cmds
assert "Stop" in h, h' "$P2/.claude/settings.json" 2>&1)
  [ -z "$E" ] && ok "--apply merges hook groups per command: template guard and project local hook both kept" || bad "dict hook merge" "rc=$RC $E $OUT"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["permissions"]["allow"]==["Bash(ls)"], d' "$P2/.claude/settings.json" \
    && ok "--apply drops an allow rule the template removed" || bad "template-removed rule kept" "$(cat "$P2/.claude/settings.json")"
  git -C "$P2" add -A && git -C "$P2" commit -qm two
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]["Stop"][0]["hooks"][0]["timeout"]=600; json.dump(d,open(p,"w"))' "$P2/.claude/settings.json"
  git -C "$P2" commit -qam "own timeout"
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash .claude/hooks/guard.sh","timeout":30}]}],"Stop":[{"hooks":[{"type":"command","command":"bash .claude/hooks/done.sh","timeout":300}]}]},"permissions":{"allow":["Bash(ls)"]}}' >"$T2/.claude/settings.json"
  git -C "$T2" commit -qam three
  OUT=$(cd "$P2" && bash "$SYNC" "$T2" --ref main --apply 2>&1); RC=$?
  E=$(python3 -c '
import json,sys; h=json.load(open(sys.argv[1]))["hooks"]
assert h["Stop"][0]["hooks"][0].get("timeout")==600, h["Stop"]
g=[x for x in h["PreToolUse"][0]["hooks"] if x["command"].endswith("guard.sh")][0]
assert g.get("timeout")==30, g' "$P2/.claude/settings.json" 2>&1)
  [ -z "$E" ] && ok "--apply keeps a project's own field on a template hook (Stop timeout 600), takes the template's other changes" || bad "per-hook fields" "rc=$RC $E"
  T4=$(new_repo); P4=$(new_repo); mkdir -p "$T4/docs" "$T4/.claude" "$P4/.claude"; cp "$TF" "$T4/docs/template-files.md"
  echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash .claude/hooks/done.sh","timeout":120}]}]}}' >"$T4/.claude/settings.json"
  git -C "$T4" add -A && git -C "$T4" commit -qm one
  echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash .claude/hooks/done.sh","timeout":30}]}]}}' >"$P4/.claude/settings.json"
  (cd "$P4" && bash "$SYNC" "$T4" --ref main --apply >/dev/null 2>&1)
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["hooks"]["Stop"][0]["hooks"][0]["timeout"]==120' "$P4/.claude/settings.json" 2>/dev/null \
    && ok "no base (first sync): template hook fields win" || bad "no-base field merge" "$(cat "$P4/.claude/settings.json")"
  # Per-project lists: .claude/template-exclude (never added) and .claude/template-keep (adapted, kept quietly).
  T3=$(new_repo); P3=$(new_repo); mkdir -p "$T3/docs" "$T3/.claude/agents" "$T3/.claude/commands" "$T3/.claude/rules"; cp "$TF" "$T3/docs/template-files.md"
  echo a >"$T3/.claude/agents/a.md"; echo b >"$T3/.claude/agents/b.md"; echo c >"$T3/.claude/commands/cx.md"; echo r >"$T3/.claude/rules/x.md"
  git -C "$T3" add -A && git -C "$T3" commit -qm one
  mkdir -p "$P3/.claude"; printf '# vendored elsewhere\r\n.claude/agents/   # whole folder\r\n.claude/commands/c*.md\r\n' >"$P3/.claude/template-exclude"
  git -C "$P3" add -A && git -C "$P3" commit -qm lists
  OUT=$(cd "$P3" && bash "$SYNC" "$T3" --ref main 2>&1); RC=$?
  { ! has "$OUT" "new               .claude/agents" && ! has "$OUT" "cx.md" && has "$OUT" "new               .claude/rules/x.md" && has "$OUT" "excluded"; } \
    && ok "template-exclude: prefix and glob entries are not listed as new (CRLF, comments ok)" || bad "exclude dry" "rc=$RC $OUT"
  OUT=$(cd "$P3" && bash "$SYNC" "$T3" --ref main --apply 2>&1); RC=$?
  [ ! -e "$P3/.claude/agents" ] && [ ! -e "$P3/.claude/commands/cx.md" ] && [ -f "$P3/.claude/rules/x.md" ] \
    && ok "template-exclude: --apply never adds excluded paths" || bad "exclude apply" "rc=$RC $OUT"
  echo k >"$T3/.claude/rules/k.md"; echo y >"$T3/.claude/rules/y.md"; git -C "$T3" add -A && git -C "$T3" commit -qm two
  echo "adapted k" >"$P3/.claude/rules/k.md"; echo "adapted y" >"$P3/.claude/rules/y.md"; echo ".claude/rules/k.md" >"$P3/.claude/template-keep"
  git -C "$P3" add -A && git -C "$P3" commit -qm adapted
  OUT=$(cd "$P3" && bash "$SYNC" "$T3" --ref main --apply 2>&1); RC=$?
  { ! has "$OUT" "locally modified  .claude/rules/k.md" && has "$OUT" "locally modified  .claude/rules/y.md" && has "$OUT" "template-keep" \
    && [ "$(cat "$P3/.claude/rules/k.md")" = "adapted k" ]; } \
    && ok "template-keep: listed adapted file kept without the locally-modified advice" || bad "keep list" "rc=$RC $OUT"
fi

echo "== v3 /next command"
NX="$TEMPLATE/.claude/commands/next.md"
if [ -f "$NX" ]; then
  miss=""
  for k in task_plan.md "git log -5" "git status" "docs/handoff.md" "fresh session" "Never start the work" "Relation"; do
    grep -qF "$k" "$NX" || miss="$miss [$k]"
  done
  [ -z "$miss" ] && ok "next.md has every step" || bad "next.md missing:$miss"
else bad "next.md exists"; fi
grep -q '`/next`' "$TEMPLATE/README.md" && ok "README lists /next" || bad "README lists /next"
grep -q '/next' "$TEMPLATE/.claude/rules/delivery.md" && ok "delivery.md points to /next" || bad "delivery.md points to /next"
[ -f "$TEMPLATE/.agents/skills/next/SKILL.md" ] && ok ".agents/skills/next mirrored" || bad ".agents/skills/next mirrored"

echo "== v3 delegate-guard"
DG="$HOOKS/delegate-guard.sh"
if [ ! -f "$DG" ]; then bad "delegate-guard.sh exists"
else
  R=$(new_repo); mkdir -p "$R/.claude/agents"
  printf -- '---\nname: code-reviewer\nmodel: inherit\n---\n' >"$R/.claude/agents/code-reviewer.md"
  DH=$(mktemp -d)   # empty HOME: the developer's own ~/.claude/agents must not leak in
  dg() { printf '%s' "$2" | HOME="$DH" CLAUDE_PROJECT_DIR="$R" DELEGATE_GUARD="$1" bash "$DG" 2>&1; }
  ag() { printf '{"session_id":"%s","tool_name":"Agent","tool_input":{"description":"d","prompt":"say \\"model\\": x","subagent_type":"%s"%s}}' "$1" "$2" "${3:+,\"model\":\"$3\"}"; }
  OUT=$(dg "" "$(ag a1 general-purpose)"); RC=$?
  [ $RC -eq 0 ] && has "$OUT" "additionalContext" && has "$OUT" "workflow.md" && ok "Agent without model: warning, not deny" || bad "no-model warn" "rc=$RC $OUT"
  OUT=$(dg "" "$(ag a1 general-purpose)"); [ -z "$OUT" ] && ok "warning once per session" || bad "warn once" "$OUT"
  OUT=$(dg "" "$(ag a2 code-reviewer)"); [ -z "$OUT" ] && ok "agent file with explicit model (inherit): silent" || bad "code-reviewer silent" "$OUT"
  OUT=$(dg "" "$(ag a3 general-purpose sonnet)"); [ -z "$OUT" ] && ok "Agent with model: silent" || bad "with model" "$OUT"
  OUT=$(dg strict "$(ag a4 general-purpose)"); RC=$?
  [ $RC -eq 2 ] && has "$OUT" "model" && ok "DELEGATE_GUARD=strict denies (exit 2)" || bad "strict" "rc=$RC $OUT"
  OUT=$(dg off "$(ag a5 general-purpose)"); RC=$?
  [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "DELEGATE_GUARD=off: silent" || bad "off" "rc=$RC $OUT"
  OUT=$(dg strict "$(ag a6 superpowers:code-reviewer)"); RC=$?
  [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "plugin agent type (x:y): never denied, its model is unknowable" || bad "plugin type" "rc=$RC $OUT"
  printf -- '---\nname: my-rev\nmodel: sonnet\n---\n' >"$R/.claude/agents/reviewer.md"
  OUT=$(dg strict "$(ag a7 my-rev)"); RC=$?
  [ $RC -eq 0 ] && ok "agent found by frontmatter name, not file name" || bad "name lookup" "rc=$RC $OUT"
  printf -- '---\nname: body-only\n---\nmodel: sonnet in the body\n' >"$R/.claude/agents/body-only.md"
  OUT=$(dg "" "$(ag a8 body-only)"); has "$OUT" "additionalContext" && ok "model: in the body (not frontmatter) does not count" || bad "body model" "$OUT"
  OUT=$(dg "" "$(ag a9 'x\\\"}')"); has "$OUT" '\' && bad "subagent_type escaped into JSON output" "$OUT" || ok "subagent_type sanitised before going into JSON"
  br() { printf '{"session_id":"%s","tool_name":"mcp__Claude_Browser__computer","tool_input":{"action":"screenshot"}%s}' "$1" "${2:+,\"agent_id\":\"$2\",\"agent_type\":\"general-purpose\"}"; }
  OUT=$(dg "" "$(br b1)"); has "$OUT" "sonnet" && has "$OUT" "subagent" && ok "main-thread browser call: reminder" || bad "browser remind" "$OUT"
  OUT=$(dg "" "$(br b1)"); [ -z "$OUT" ] && ok "browser reminder once per session" || bad "browser once" "$OUT"
  OUT=$(dg "" "$(br b2 ag-1)"); [ -z "$OUT" ] && ok "browser call inside a subagent: silent" || bad "browser in subagent" "$OUT"
  grep -q 'delegate-guard.sh' "$TEMPLATE/.claude/settings.json" && ok "settings.json wires delegate-guard" || bad "wired"
fi
grep -q 'parallel subagents per wave' "$TEMPLATE/.claude/rules/workflow.md" && ok "workflow.md fan-out cap" || bad "workflow.md fan-out cap"
grep -q 'spawn_agent' "$TEMPLATE/AGENTS.md" && ok "AGENTS.md Codex fan-out cap" || bad "AGENTS.md Codex fan-out cap"

echo "== v3 android-emu"
EMU="$TEMPLATE/scripts/android-emu.sh"
if [ ! -f "$EMU" ]; then bad "scripts/android-emu.sh exists"
else
  bash -n "$EMU" && ok "bash -n android-emu.sh" || bad "bash -n android-emu.sh"
  FA=$(mktemp -d); AL="$FA/adb.log"
  # fake adb: logs args; getprop flips to 1 after $FAKE_BOOT_AFTER calls; df reports $FAKE_DF_KB free
  cat >"$FA/adb" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/adb.log"
case "$*" in
  *getprop\ sys.boot_completed*) n=$(( $(cat "$FAKE_DIR/n" 2>/dev/null || echo 0) + 1 )); echo $n >"$FAKE_DIR/n"
    [ "$n" -ge "${FAKE_BOOT_AFTER:-1}" ] && echo 1 || echo ;;
  *df*) printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\n/dev/block/dm-5 6000000 0 %s 9%% /data\n' "${FAKE_DF_KB:-4000000}" ;;
  devices*) printf 'List of devices attached\n%b\n' "${FAKE_DEVICES:-}" ;;
esac
exit 0
FAKE
  printf '#!/usr/bin/env bash\necho "$*" >>"$FAKE_DIR/emulator.log"\nsleep "${FAKE_EMU_LIFE:-30}"\n' >"$FA/emulator"
  chmod +x "$FA/adb" "$FA/emulator"
  emu() { (cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" AVD=test_avd EMU_POLL=0.1 EMU_LOG="$FA/emu.log" "$@" bash "$EMU" up 2>&1); }
  R=$(new_repo)
  OUT=$(emu FAKE_BOOT_AFTER=3 EMU_BOOT_TIMEOUT=10); RC=$?
  [ $RC -eq 0 ] && has "$(cat "$FA/emulator.log" 2>/dev/null)" "-avd test_avd" && ok "up: launches the AVD and returns 0 once booted" || bad "up boots" "rc=$RC $OUT"
  : >"$FA/n"; echo 0 >"$FA/n"
  OUT=$(emu FAKE_BOOT_AFTER=999 EMU_BOOT_TIMEOUT=1); RC=$?
  [ $RC -eq 1 ] && has "$OUT" "did not boot" && ok "up: exit 1 with a message on boot timeout" || bad "up timeout" "rc=$RC $OUT"
  echo 0 >"$FA/n"
  OUT=$(emu FAKE_BOOT_AFTER=1 EMU_BOOT_TIMEOUT=10 FAKE_DF_KB=200000); RC=$?
  has "$OUT" "-wipe-data" && ok "up: low /data space prints -wipe-data advice" || bad "low space" "rc=$RC $OUT"
  echo 0 >"$FA/n"; : >"$AL"; : >"$FA/emulator.log"
  OUT=$(emu FAKE_BOOT_AFTER=2 EMU_BOOT_TIMEOUT=10 FAKE_DEVICES='R58M123\tdevice\nemulator-5554\toffline'); RC=$?
  { [ $RC -eq 0 ] && has "$(cat "$FA/emulator.log")" "-port 5556" && grep -q -- '-s emulator-5556 shell getprop' "$AL" && ! grep -v -- '-s emulator-5556' "$AL" | grep -q getprop; } \
    && ok "up with a phone attached: own -port, every adb call targets emulator-<port>" || bad "up + phone" "rc=$RC $OUT $(cat "$AL" "$FA/emulator.log")"
  echo 0 >"$FA/n"; START=$SECONDS
  OUT=$(emu FAKE_BOOT_AFTER=999 EMU_BOOT_TIMEOUT=10 FAKE_EMU_LIFE=0); RC=$?
  [ $RC -eq 1 ] && has "$OUT" "exited" && [ $((SECONDS - START)) -lt 5 ] && ok "up: emulator that dies fails fast, not at the timeout" || bad "emu died" "rc=$RC $((SECONDS - START))s $OUT"
  : >"$AL"
  OUT=$(cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" FAKE_DEVICES='R58M123\tdevice\nemulator-5554\tdevice' bash "$EMU" down 2>&1); RC=$?
  grep -q '^-s emulator-5554 emu kill' "$AL" && ok "down: adb emu kill on the emulator" || bad "down" "rc=$RC $OUT $(cat "$AL")"
  : >"$AL"; OUT=$(cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" FAKE_DEVICES='R58M123\tdevice' bash "$EMU" down 2>&1); RC=$?
  ! grep -q 'emu kill' "$AL" && has "$OUT" "no emulator" && ok "down with only a phone: nothing killed" || bad "down phone" "rc=$RC $OUT $(cat "$AL")"
  OUT=$(cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" FAKE_DEVICES='emulator-5554\tdevice' bash "$EMU" status 2>&1); RC=$?
  [ $RC -eq 0 ] && has "$OUT" "emulator-5554" && has "$OUT" "boot" && ok "status: device and boot state" || bad "status" "rc=$RC $OUT"
  OUT=$(cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" FAKE_DEVICES='R58M123\tdevice' FAKE_BOOT_AFTER=1 bash "$EMU" status 2>&1)
  has "$OUT" "boot: no emulator" && ok "status with only a phone: no emulator, not the phone's boot state" || bad "status phone" "$OUT"
  pkill -f "$FA/emulator" 2>/dev/null
fi

echo "== v3 android-ui"
UI="$TEMPLATE/scripts/android-ui.sh"; FX="$TEMPLATE/scripts/fixtures"
if [ ! -f "$UI" ]; then bad "scripts/android-ui.sh exists"
else
  bash -n "$UI" && ok "bash -n android-ui.sh" || bad "bash -n android-ui.sh"
  FU=$(mktemp -d)
  # fake adb: logs args; `exec-out cat` serves the Nth file of $FAKE_DUMPS (last one repeats)
  cat >"$FU/adb" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/adb.log"
case "$*" in
  *exec-out\ cat*) n=$(( $(cat "$FAKE_DIR/n" 2>/dev/null || echo 0) + 1 )); echo $n >"$FAKE_DIR/n"
    set -- $FAKE_DUMPS; [ "$n" -gt $# ] && n=$#; eval "cat \"\${$n}\"" ;;
  *uiautomator\ dump*) [ -n "${FAKE_DUMP_FAIL:-}" ] && echo "ERROR: could not get idle state." || echo "UI hierchary dumped to: /sdcard/ui.xml" ;;
  *screencap*) printf 'PNGDATA' ;;
esac
exit 0
FAKE
  chmod +x "$FU/adb"
  ui() { rm -f "$FU/n" "$FU/adb.log"; env PATH="$FU:$PATH" FAKE_DIR="$FU" UI_POLL=0.1 FAKE_DUMPS="$1" FAKE_DUMP_FAIL="${FAKE_DUMP_FAIL:-}" bash "$UI" "${@:2}" 2>&1; }
  OUT=$(ui "$FX/ui-form.xml" tap "Save"); RC=$?
  [ $RC -eq 0 ] && grep -q 'input tap 300 1100' "$FU/adb.log" && ok "tap \"Save\" taps the bounds centre" || bad "tap" "rc=$RC $OUT $(cat "$FU/adb.log")"
  OUT=$(ui "$FX/ui-home.xml" tap "Add note"); RC=$?
  grep -q 'input tap 960 2180' "$FU/adb.log" && ok "tap matches content-desc too" || bad "tap desc" "rc=$RC $OUT"
  OUT=$(ui "$FX/ui-home.xml" tap "Nope"); RC=$?
  [ $RC -eq 1 ] && ! grep -q 'input tap' "$FU/adb.log" && ok "tap on missing text: exit 1, no tap" || bad "tap missing" "rc=$RC $OUT"
  OUT=$(ui "$FX/ui-home.xml $FX/ui-home.xml $FX/ui-form.xml" wait-for "Save" 5); RC=$?
  [ $RC -eq 0 ] && ok "wait-for: 0 when the text appears" || bad "wait-for appears" "rc=$RC $OUT"
  OUT=$(ui "$FX/ui-home.xml" wait-for "Save" 1); RC=$?
  [ $RC -eq 1 ] && has "$OUT" "Save" && ok "wait-for: 1 on timeout" || bad "wait-for timeout" "rc=$RC $OUT"
  OUT=$(ui "$FX/ui-anr.xml" wait-for "Save" 5); RC=$?
  [ $RC -ne 0 ] && has "$OUT" "ANR" && has "$OUT" "Notes isn't responding" && ok "wait-for names an ANR dialog" || bad "wait-for ANR" "rc=$RC $OUT"
  OUT=$(ui "$FX/ui-home.xml" shot "$FU/s.png"); RC=$?
  [ "$(cat "$FU/s.png" 2>/dev/null)" = PNGDATA ] && grep -q 'exec-out screencap -p' "$FU/adb.log" && ok "shot writes exec-out screencap" || bad "shot" "rc=$RC $OUT"
  OUT=$(ui "$FX/ui-home.xml" type "hello world"); grep -q 'input text hello%sworld' "$FU/adb.log" && ok "type escapes spaces" || bad "type" "$(cat "$FU/adb.log")"
  OUT=$(ui "$FX/ui-home.xml" back); grep -q 'input keyevent 4' "$FU/adb.log" && ok "back sends keyevent 4" || bad "back"
  OUT=$(env ADB_SERIAL=emulator-5556 PATH="$FU:$PATH" FAKE_DIR="$FU" bash "$UI" key 66 2>&1; cat "$FU/adb.log")
  has "$OUT" "-s emulator-5556 shell input keyevent 66" && ok "ADB_SERIAL is passed to adb" || bad "serial" "$OUT"
  OUT=$(FAKE_DUMP_FAIL=1 ui "$FX/ui-form.xml" tap "Save"); RC=$?
  [ $RC -eq 1 ] && ! grep -q 'input tap' "$FU/adb.log" && has "$OUT" "uiautomator dump failed" && ok "failed dump: exit 1, stale ui.xml never read" || bad "dump failure" "rc=$RC $OUT $(cat "$FU/adb.log")"
  OUT=$(ui "$FX/ui-form.xml" tap "Save"); grep -n 'rm -f /sdcard/ui.xml' "$FU/adb.log" | grep -q '^1:' && ok "dump removes the old ui.xml first" || bad "dump rm" "$(cat "$FU/adb.log")"
  for s in "$UI" "$EMU"; do grep -q "MSYS_NO_PATHCONV=1" "$s" && grep -q "MSYS2_ARG_CONV_EXCL" "$s" || miss="$miss $s"; done
  [ -z "${miss:-}" ] && ok "android scripts stop Git Bash rewriting /sdcard and /data" || bad "MSYS path conversion" "$miss"; unset miss
fi

echo "== v3 browser/device guidance"
TP="$TEMPLATE/.claude/skills/testing-patterns/SKILL.md"
miss=""
for k in "## Browser checks" "## Android/device checks" "≤25" "file://" "uiautomator dump" "android-ui.sh"; do grep -qF "$k" "$TP" || miss="$miss [$k]"; done
[ -z "$miss" ] && ok "testing-patterns has browser + device sections" || bad "testing-patterns missing:$miss"
diff -q "$TP" "$TEMPLATE/.agents/skills/testing-patterns/SKILL.md" >/dev/null && ok ".agents testing-patterns in sync" || bad ".agents testing-patterns out of sync"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TEMPLATE/.claude/launch.json.example" 2>/dev/null && ok "launch.json.example parses" || bad "launch.json.example parses"
  miss=$(python3 - "$TEMPLATE/.claude/settings.json" <<'PY'
import json,sys
allow=json.load(open(sys.argv[1]))["permissions"]["allow"]
need=["adb devices","adb exec-out screencap","adb shell uiautomator dump","adb shell getprop"]
print(" ".join(n for n in need if not any(a.startswith("Bash("+n) for a in allow)))
PY
)
  [ -z "$miss" ] && ok "settings allows read-only adb" || bad "settings adb allow missing: $miss"
else echo "  SKIP json checks (no python3)"; fi

echo "== v3 done-gate FVM + Dart workspace"
FF=$(mktemp -d); FL="$FF/calls.log"
for b in fvm flutter dart; do printf '#!/usr/bin/env bash\necho "%s $*" >>"%s"\nexit 0\n' "$b" "$FL" >"$FF/$b"; chmod +x "$FF/$b"; done
BASEP=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e flutter -e fvm -e dart | paste -sd: -)
R=$(new_repo); printf 'name: app\n' >"$R/pubspec.yaml"; echo '{"flutter":"3.24.0"}' >"$R/.fvmrc"
OUT=$(cd "$R" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R" FVM_CACHE_PATH="$FF" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
grep -q '^fvm flutter analyze' "$FL" && ! grep -q '^flutter ' "$FL" && ok ".fvmrc: gate runs fvm flutter analyze, not plain flutter" || bad "fvm" "rc=$RC $OUT $(cat "$FL")"
: >"$FL"; mkdir -p "$R/scripts"; printf '#!/usr/bin/env bash\necho "wrapper $*" >>"%s"\n' "$FL" >"$R/scripts/flutter.sh"; echo c >>"$R/file.txt"
OUT=$(cd "$R" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R" FVM_CACHE_PATH="$FF" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
grep -q '^wrapper analyze' "$FL" && ! grep -q '^fvm ' "$FL" && ok ".fvmrc + scripts/flutter.sh: gate uses the wrapper" || bad "wrapper" "rc=$RC $OUT $(cat "$FL")"
: >"$FL"; printf '#!/usr/bin/env bash\necho "dart $(basename "$PWD") $*" >>"%s"\nexit 0\n' "$FL" >"$FF/dart"
W=$(new_repo); mkdir -p "$W/packages/core" "$W/apps/web"
printf 'name: ws\nenvironment:\n  sdk: ^3.6.0\nworkspace:\n  - packages/core\n  - apps/web\n' >"$W/pubspec.yaml"
printf 'name: core\nresolution: workspace\n' >"$W/packages/core/pubspec.yaml"; printf 'name: web\nresolution: workspace\n' >"$W/apps/web/pubspec.yaml"
OUT=$(cd "$W" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$W" FVM_CACHE_PATH="$FF" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
grep -q '^dart core analyze' "$FL" && grep -q '^dart web analyze' "$FL" && ok "pub workspace: dart analyze runs in every member" || bad "workspace" "rc=$RC $OUT $(cat "$FL")"
: >"$FL"; mkdir -p "$W/scripts" "$W/packages/core/test" "$W/apps/web/test"; echo '{"flutter":"3.24.0"}' >"$W/.fvmrc"
printf '#!/usr/bin/env bash\necho "wrapper $(basename "$PWD") $*" >>"%s"\n' "$FL" >"$W/scripts/flutter.sh"
printf 'name: web\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n' >"$W/apps/web/pubspec.yaml"; echo c >>"$W/file.txt"
OUT=$(cd "$W" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$W" DONE_GATE_FULL=1 FVM_CACHE_PATH="$FF" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
{ grep -q '^wrapper core analyze --no-pub' "$FL" && grep -q '^wrapper web analyze --no-pub' "$FL" && ! grep -q '^dart ' "$FL"; } \
  && ok ".fvmrc wrapper + workspace: every member analyzed with the pinned wrapper" || bad "fvm workspace analyze" "rc=$RC $OUT $(cat "$FL")"
grep -q '^wrapper core test' "$FL" && grep -q '^wrapper web test' "$FL" && ok "workspace + DONE_GATE_FULL: tests run per member" || bad "workspace tests" "rc=$RC $(cat "$FL")"

echo "== v3 done-gate FVM cache, never an unpinned SDK"
FC=$(mktemp -d); mkdir -p "$FC/versions/3.47.5/bin"; : >"$FL"
for b in flutter dart; do printf '#!/usr/bin/env bash\necho "cache-%s $*" >>"%s"\nexit 0\n' "$b" "$FL" >"$FC/versions/3.47.5/bin/$b"; chmod +x "$FC/versions/3.47.5/bin/$b"; done
GF=$(mktemp -d); printf '#!/usr/bin/env bash\necho "global-flutter $*" >>"%s"\n' "$FL" >"$GF/flutter"; chmod +x "$GF/flutter"
R=$(new_repo); printf 'name: app\n' >"$R/pubspec.yaml"; echo '{"flutter":"3.47.5"}' >"$R/.fvmrc"
OUT=$(cd "$R" && echo '{}' | CLAUDE_PROJECT_DIR="$R" FVM_CACHE_PATH="$FC" PATH="$GF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
grep -q '^cache-flutter analyze' "$FL" && ! grep -q '^global-flutter' "$FL" && ok ".fvmrc, no wrapper, no fvm: pinned SDK from FVM_CACHE_PATH" || bad "fvm cache" "rc=$RC $OUT $(cat "$FL")"
: >"$FL"; echo c >>"$R/file.txt"
OUT=$(cd "$R" && echo '{}' | CLAUDE_PROJECT_DIR="$R" FVM_CACHE_PATH="$(mktemp -d)" PATH="$GF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && ! grep -q '^global-flutter' "$FL" && ok "pin not installed: NOT RUN, never the global flutter" || bad "unpinned sdk" "rc=$RC $OUT $(cat "$FL")"

echo "== v3 done-gate wrapper SDK's dart for pure-Dart members"
: >"$FL"; W=$(new_repo); mkdir -p "$W/scripts" "$W/packages/core/test" "$W/apps/web/test"; echo '{"flutter":"3.47.5"}' >"$W/.fvmrc"
printf 'name: ws\nworkspace:\n  - packages/core\n  - apps/web\n' >"$W/pubspec.yaml"
printf 'name: core\nresolution: workspace\n' >"$W/packages/core/pubspec.yaml"
printf 'name: web\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n' >"$W/apps/web/pubspec.yaml"
printf '#!/usr/bin/env bash\n[ "$1" = --which ] && { echo "%s"; exit 0; }\necho "wrapper $(basename "$PWD") $*" >>"%s"\n' "$FC/versions/3.47.5/bin/flutter" "$FL" >"$W/scripts/flutter.sh"
printf '#!/usr/bin/env bash\necho "cache-dart $(basename "$PWD") $*" >>"%s"\n' "$FL" >"$FC/versions/3.47.5/bin/dart"
OUT=$(cd "$W" && echo '{}' | CLAUDE_PROJECT_DIR="$W" DONE_GATE_FULL=1 PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
{ grep -q '^cache-dart core analyze --fatal-infos' "$FL" && grep -q '^cache-dart core test' "$FL" && grep -q '^wrapper web analyze --no-pub' "$FL" && ! grep -q '^wrapper core' "$FL" && ! grep -q '^dart ' "$FL"; } \
  && ok "wrapper: pure-Dart member runs the pinned SDK's dart analyze --fatal-infos / dart test" || bad "wrapper dart" "rc=$RC $OUT $(cat "$FL")"

echo "== v3 done-gate workspace_members parsing"
: >"$FL"; printf '#!/usr/bin/env bash\necho "dart $(basename "$PWD") $*" >>"%s"\nexit 0\n' "$FL" >"$FF/dart"
W=$(new_repo); mkdir -p "$W/packages/core" "$W/apps/web"
printf 'name: core\nresolution: workspace\n' >"$W/packages/core/pubspec.yaml"; printf 'name: web\nresolution: workspace\n' >"$W/apps/web/pubspec.yaml"
printf 'name: ws\r\nworkspace:\r\n- packages/core   # the engine\r\n- "apps/web"\r\ndev_dependencies:\r\n  lints: ^5.0.0\r\n' >"$W/pubspec.yaml"
OUT=$(cd "$W" && echo '{}' | CLAUDE_PROJECT_DIR="$W" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
{ grep -q '^dart core analyze' "$FL" && grep -q '^dart web analyze' "$FL" && [ "$(wc -l <"$FL")" -eq 2 ]; } \
  && ok "column-0 items, trailing comments, CRLF: every member found" || bad "members parse" "rc=$RC $OUT $(cat "$FL")"
printf 'name: ws\nworkspace:\n  - packages/core\n  - packages/gone\n' >"$W/pubspec.yaml"
OUT=$(cd "$W" && echo '{}' | CLAUDE_PROJECT_DIR="$W" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 2 ] && has "$OUT" "packages/gone" && ok "listed member missing on disk blocks" || bad "missing member" "rc=$RC $OUT"

: >"$FL"; mkdir -p "$W/packages/my pkg"; printf 'name: mp\nresolution: workspace\n' >"$W/packages/my pkg/pubspec.yaml"
printf 'name: ws\nworkspace:\n  - packages/core\n  - packages/my pkg\n' >"$W/pubspec.yaml"
OUT=$(cd "$W" && echo '{}' | CLAUDE_PROJECT_DIR="$W" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && grep -q '^dart my pkg analyze' "$FL" && ok "member path with a space is one member" || bad "member space" "rc=$RC $OUT $(cat "$FL")"
R=$(new_repo); mkdir -p "$R/.claude/hooks/local"
printf 'echo "Binding has not yet been initialized."; exit 1\n' >"$R/.claude/hooks/local/ft.sh"
OUT=$(cd "$R" && echo '{}' | CLAUDE_PROJECT_DIR="$R" DONE_GATE_ENV_PROBE=false bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
[ $RC -eq 2 ] && ok "Flutter 'Binding has not yet been initialized' blocks (not wp-env)" || bad "binding init" "rc=$RC $OUT"

: >"$FL"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho "dart $(basename "$PWD") $*" >>"%s"\nexit 0\n' "$FL" >"$FF/dart"
echo c >>"$W/file.txt"
OUT=$(cd "$W" && echo '{}' | CLAUDE_PROJECT_DIR="$W" PATH="$FF:$BASEP" bash "$HOOKS/done-gate.sh" 2>&1); RC=$?
grep -q '^dart core analyze' "$FL" && grep -q '^dart my pkg analyze' "$FL" && ok "a gate reading stdin cannot swallow the remaining members" || bad "member stdin" "rc=$RC $OUT $(cat "$FL")"

echo "== v3 done-gate pinned-Flutter wrapper (ported from DoWee)"
R=$(new_repo); C=$(mktemp)
touch "$R/pubspec.yaml"; echo '{"flutter":"3.47.5"}' >"$R/.fvmrc"; mkdir -p "$R/scripts"
# Fake pinned-SDK wrapper: logs each call; FAKE_* env vars choose the outcome.
cat >"$R/scripts/flutter.sh" <<EOW
#!/usr/bin/env bash
echo "\$*" >>'$C'
case "\$1" in
  --which) [ "\${FAKE_NO_SDK:-0}" = 1 ] && { echo "flutter.sh: Flutter 3.47.5 not found" >&2; exit 127; }; echo fake-flutter ;;
  analyze) [ "\${FAKE_ANALYZE_FAIL:-0}" != 0 ] && { [ "\$FAKE_ANALYZE_FAIL" = 1 ] && echo "  error • Undefined name 'x' • lib/main.dart:3:5 • undefined_identifier"; echo "\${FAKE_EXTRA:-}"; exit 1; }; echo "No issues found!" ;;
  test) [ "\${FAKE_TEST_FAIL:-0}" = 1 ] && { echo "Some tests failed."; echo "\${FAKE_EXTRA:-}"; exit 1; }; echo "All tests passed!" ;;
esac
EOW
fg() { (cd "$R/sub" && echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R" PATH="$BASEP" "$@" bash "$HOOKS/done-gate.sh" 2>&1); }
calls() { grep -c "^$1" "$C" 2>/dev/null || true; }
OUT=$(fg env FAKE_NO_SDK=1); RC=$?
[ $RC -eq 0 ] && has "$OUT" "NOT RUN" && has "$OUT" "systemMessage" && [ "$(calls analyze)" -eq 0 ] && ok "no pinned SDK -> NOT RUN to the user, no block" || bad "no sdk" "rc=$RC $OUT"
sed -i 's|^  --which) \[|  --which) printf "line one\\r\\n\\tline two\\n" >\&2; [|' "$R/scripts/flutter.sh"
OUT=$(fg env FAKE_NO_SDK=1)
[ "$(printf '%s' "$OUT" | wc -l | tr -d ' ')" -eq 0 ] && ! has "$OUT" $'\t' && ! has "$OUT" $'\r' && ok "multi-line SDK error stays one valid JSON line" || bad "user_note escaping" "$OUT"
sed -i 's|printf "line one\\r\\n\\tline two\\n" >\&2; ||' "$R/scripts/flutter.sh"
OUT=$(fg env); RC=$?
[ $RC -eq 0 ] && [ "$(calls analyze)" -eq 1 ] && [ "$(calls test)" -eq 0 ] && ok "analyze runs through scripts/flutter.sh, tests opt-in" || bad "flutter analyze" "rc=$RC $(cat "$C")"
OUT=$(fg env); [ "$(calls analyze)" -eq 1 ] && ok "unchanged tree skips flutter analyze" || bad "flutter skip" "$(cat "$C")"
OUT=$(fg env DONE_GATE_FULL=1); RC=$?
[ $RC -eq 0 ] && [ "$(calls test)" -eq 1 ] && ok "DONE_GATE_FULL=1 runs flutter test" || bad "full tests" "rc=$RC $(cat "$C")"
echo "c" >>"$R/file.txt"
OUT=$(fg env FAKE_ANALYZE_FAIL=1); RC=$?
[ $RC -eq 2 ] && has "$OUT" "lib/main.dart:3:5" && ok "analyzer error blocks with details" || bad "analyze fail" "rc=$RC $OUT"
OUT=$(fg env DONE_GATE_FULL=1 FAKE_TEST_FAIL=1); RC=$?
[ $RC -eq 2 ] && has "$OUT" "tests FAILED" && ok "failing flutter test blocks under DONE_GATE_FULL" || bad "test fail" "rc=$RC $OUT"
ENVTXT="Cannot connect to the Docker daemon at unix:///var/run/docker.sock"
OUT=$(fg env DONE_GATE_ENV_PROBE=false FAKE_ANALYZE_FAIL=1 FAKE_EXTRA="$ENVTXT"); RC=$?
[ $RC -eq 2 ] && ok "indented 'error •' analyze line + env-down text still blocks" || bad "flutter marker error" "rc=$RC $OUT"
for line in "  warning • Unused import • lib/a.dart:1:8 • unused_import" "  info • Prefer const • lib/a.dart:2:3 • prefer_const"; do
  OUT=$(fg env DONE_GATE_ENV_PROBE=false FAKE_ANALYZE_FAIL=2 FAKE_EXTRA="$line"$'\n'"$ENVTXT"); RC=$?
  [ $RC -eq 2 ] && ok "indented '${line:2:7}' analyze line + env-down text still blocks" || bad "flutter marker ${line:2:7}" "rc=$RC $OUT"
done
OUT=$(fg env DONE_GATE_ENV_PROBE=false DONE_GATE_FULL=1 FAKE_TEST_FAIL=1 FAKE_EXTRA="$ENVTXT"); RC=$?
[ $RC -eq 2 ] && ok "'Some tests failed' + env-down text still blocks" || bad "flutter test marker" "rc=$RC $OUT"

echo "== v3 project lessons in the docs"
lesson() { grep -qF -- "$2" "$TEMPLATE/$1" && ok "$1: $2" || bad "$1 lacks: $2"; }
TPS=.claude/skills/testing-patterns/SKILL.md
lesson $TPS "non-local"; lesson $TPS "PHPUnit running in the container"; lesson $TPS "globalSetup"; lesson $TPS "workers: 1"
lesson .claude/rules/workflow.md "pgrep -f"; lesson .claude/rules/workflow.md "running shell script"
lesson .claude/rules/workflow.md "unscoped"; lesson .claude/rules/workflow.md "labelled"
lesson .claude/rules/pr.md "anchored"; lesson CATALOG.md "dotenv-cli"

echo "== v3 usage-report"
UR="$TEMPLATE/scripts/usage-report.py"
if ! command -v python3 >/dev/null 2>&1; then echo "  SKIP usage-report (no python3)"
elif [ ! -f "$UR" ]; then bad "scripts/usage-report.py exists"
else
  ur() { python3 -I "$UR" --root "$TEMPLATE/scripts/fixtures/usage" --json "$@" 2>&1; }
  chk() { printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); $2" 2>&1; }
  OUT=$(ur)
  E=$(chk "$OUT" 'assert abs(d["total_usd"]-0.05286)<1e-9, d["total_usd"]; assert list(d["projects"])==["x-develope-demo"], d["projects"]; assert d["projects"]["x-develope-demo"]["sessions"]==2')
  [ -z "$E" ] && ok "usage-report: exact total, dedup by message id, mount variants merged" || bad "usage total" "$E $OUT"
  OUT=$(ur --until 2026-11-25)
  E=$(chk "$OUT" 'assert abs(d["total_usd"]-0.05166)<1e-9, d["total_usd"]; assert abs(d["subagent_usd"]-0.0006)<1e-9, d["subagent_usd"]; assert (d["agent_calls"],d["agent_calls_no_model"])==(2,1); assert (d["main_browser_calls"],d["main_images"])==(1,1); assert (d["sessions_over_150k"],d["sessions_over_400k"])==(1,0); assert d["max_context"]["s1"]==200005')
  [ -z "$E" ] && ok "usage-report: --until, subagent share, Agent-without-model, main-thread browser, context peaks" || bad "usage details" "$E $OUT"
  OUT=$(python3 -I "$UR" --root "$TEMPLATE/scripts/fixtures/usage" 2>&1); RC=$?
  [ $RC -eq 0 ] && has "$OUT" "x-develope-demo" && has "$OUT" "Prices as of" && ok "usage-report: text report" || bad "usage text" "rc=$RC $OUT"
  UT=$(mktemp -d); mkdir -p "$UT/-mnt-x-demo" "$UT/-media-john-doe-x-demo"
  L='{"type":"assistant","timestamp":"2026-11-20T10:00:00Z","sessionId":"s9","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000000},"content":[{"type":"tool_use","name":"Agent","input":{}}]}}'
  printf '%s\n%s\n' "$L" "$L" >"$UT/-mnt-x-demo/s9.jsonl"; printf '%s\n' "$L" >"$UT/-media-john-doe-x-demo/s9.jsonl"
  OUT=$(LOGNAME=john.doe USER=john.doe python3 -I "$UR" --root "$UT" --json 2>&1)
  E=$(chk "$OUT" 'assert abs(d["total_usd"]-12)<1e-9, d["total_usd"]; assert d["agent_calls"]==3, d["agent_calls"]')
  [ -z "$E" ] && ok "usage-report: lines without a message/tool id are each counted" || bad "id-less dedup" "$E $OUT"
  E=$(chk "$OUT" 'assert list(d["projects"])==["x-demo"], d["projects"]')
  [ -z "$E" ] && ok "usage-report: /media/<user with . or -> merges with /mnt" || bad "dotted user" "$E $OUT"
  OUT=$(python3 -I "$UR" --root "$UT" --since 2026-13-01 2>&1); RC=$?
  [ $RC -ne 0 ] && has "$OUT" "YYYY-MM-DD" && ok "usage-report: bad --since date rejected" || bad "date check" "rc=$RC $OUT"
  python3 -I "$UR" --help | grep -q UTC && ok "usage-report: --help says dates are UTC" || bad "UTC help"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
