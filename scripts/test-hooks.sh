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

echo "== v3 file ownership"
# Every tracked path must have an owner in docs/template-files.md (first match
# wins); sync-template.sh relies on it to know what it may overwrite.
TF="$TEMPLATE/docs/template-files.md"
if [ -f "$TF" ]; then
  GLOBS=$(sed -n 's/^| `\([^`]*\)` | \(template\|project\|merged\) |.*/\1/p' "$TF")
  UNLISTED=""
  while IFS= read -r f; do
    hit=""; while IFS= read -r g; do [[ $f == $g ]] && { hit=1; break; }; done <<<"$GLOBS"
    [ -z "$hit" ] && UNLISTED="$UNLISTED $f"
  done < <(git -C "$TEMPLATE" ls-files)
  [ -z "$UNLISTED" ] && ok "every tracked file has an owner in docs/template-files.md" || bad "unlisted paths" "$UNLISTED"
else bad "docs/template-files.md exists"; fi

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
  echo '{"hooks":{"Stop":["A"]},"permissions":{"allow":["Bash(ls)"]},"env":{"MY_KEY":"1"}}' >"$P/.claude/settings.json"
  git -C "$P" add -A && git -C "$P" commit -qm project
  echo 'echo v2' >"$T/.claude/hooks/h.sh"; echo 'rule v2' >"$T/.claude/rules/r.md"; git -C "$T" rm -q .claude/rules/gone.md
  echo '{"hooks":{"Stop":["A","B"]},"permissions":{"allow":["Bash(ls)"]},"env":{}}' >"$T/.claude/settings.json"
  git -C "$T" add -A && git -C "$T" commit -qm two
  st() { (cd "$P" && bash "$SYNC" "$T" --ref main "$@" 2>&1); }
  OUT=$(st); RC=$?
  { has "$OUT" "updated" && has "$OUT" ".claude/hooks/h.sh"; } && ok "dry run: old unmodified hook listed as updated" || bad "dry updated" "rc=$RC $OUT"
  printf '%s\n' "$OUT" | grep -q 'locally modified.*rules/r.md' && ok "dry run: edited rule listed as locally modified" || bad "dry modified" "$OUT"
  printf '%s\n' "$OUT" | grep -q 'removed upstream.*gone.md' && ok "dry run: removed-upstream file listed" || bad "dry removed" "$OUT"
  [ -z "$(git -C "$P" status --porcelain)" ] && ok "dry run leaves the project untouched" || bad "dry run wrote" "$(git -C "$P" status --porcelain)"
  OUT=$(st --apply); RC=$?
  [ "$(cat "$P/.claude/hooks/h.sh")" = "echo v2" ] && ok "--apply updates the old hook" || bad "apply hook" "rc=$RC $OUT"
  [ "$(cat "$P/.claude/rules/r.md")" = "my own rule" ] && ok "--apply keeps the locally modified rule" || bad "apply rule"
  [ -f "$P/.claude/rules/gone.md" ] && ok "--apply never deletes removed-upstream files" || bad "apply deleted"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hooks"]["Stop"]==["A","B"] and d["env"]["MY_KEY"]=="1", d' "$P/.claude/settings.json" \
    && ok "--apply merges template hooks and keeps the project env" || bad "settings merge" "$(cat "$P/.claude/settings.json")"
  grep -q "$(git -C "$T" rev-parse HEAD)" "$P/.claude/template-version" 2>/dev/null && ok "--apply writes .claude/template-version" || bad "stamp" "$OUT"
  git -C "$P" add -A && git -C "$P" commit -qm synced
  OUT=$(st --apply); RC=$?
  [ $RC -eq 0 ] && [ -z "$(git -C "$P" status --porcelain)" ] && has "$OUT" "no changes" && ok "second --apply: no changes" || bad "second apply" "rc=$RC $OUT $(git -C "$P" status --porcelain)"
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
  dg() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$R" DELEGATE_GUARD="$1" bash "$DG" 2>&1; }
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
  devices*) printf 'List of devices attached\nemulator-5554\tdevice\n' ;;
esac
exit 0
FAKE
  printf '#!/usr/bin/env bash\necho "$*" >>"$FAKE_DIR/emulator.log"\nsleep 30\n' >"$FA/emulator"
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
  : >"$AL"
  OUT=$(cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" bash "$EMU" down 2>&1); RC=$?
  grep -q '^emu kill' "$AL" && ok "down: adb emu kill" || bad "down" "rc=$RC $OUT $(cat "$AL")"
  OUT=$(cd "$R" && env PATH="$FA:$PATH" FAKE_DIR="$FA" bash "$EMU" status 2>&1); RC=$?
  [ $RC -eq 0 ] && has "$OUT" "emulator-5554" && has "$OUT" "boot" && ok "status: device and boot state" || bad "status" "rc=$RC $OUT"
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
  *screencap*) printf 'PNGDATA' ;;
esac
exit 0
FAKE
  chmod +x "$FU/adb"
  ui() { rm -f "$FU/n" "$FU/adb.log"; env PATH="$FU:$PATH" FAKE_DIR="$FU" UI_POLL=0.1 FAKE_DUMPS="$1" bash "$UI" "${@:2}" 2>&1; }
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
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
