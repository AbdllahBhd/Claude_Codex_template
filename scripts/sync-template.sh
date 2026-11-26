#!/usr/bin/env bash
# sync-template.sh — pull template updates into this project (run from the
# project). Dry run by default; never commits, never touches project-owned paths.
#
#   bash scripts/sync-template.sh <template-dir> [--ref <branch>] [--apply]
#
# Ownership comes from the TEMPLATE's docs/template-files.md. Per template-owned
# file it reports:
#   new               not in the project yet
#   unchanged         identical to the template
#   updated           project copy equals an older template version -> safe to replace
#   locally modified  project copy matches no template version -> kept, diff shown
#   removed upstream  the template dropped it -> listed, never deleted
# Paths matching .claude/template-exclude (project-owned, one entry per line:
# `dir/` = prefix, else a glob; `#` comments) are skipped entirely: never
# added, updated or listed — for template parts a project does without.
# Paths matching .claude/template-keep (same format) are adapted on purpose:
# when they differ from the template they are kept and only counted.
# .claude/settings.json is "merged" (three-way against the last synced
# template version): template hooks + permissions arrive, project-only hooks and
# allow rules stay, rules the project removed stay removed, the project keeps env
# and everything else (needs python3; without it the diff is printed and the
# file is left alone).
# --apply copies new + updated files, merges settings.json, runs
# scripts/sync-codex.sh and records the template commit in .claude/template-version.

set -uo pipefail

usage() { echo "usage: bash scripts/sync-template.sh <template-dir> [--ref <branch>] [--apply]" >&2; exit 1; }

TPL=""; REF="${TEMPLATE_REF:-main}"; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage ;;
    *) [ -z "$TPL" ] || usage; TPL=$1; shift ;;
  esac
done
[ -n "$TPL" ] || usage
# Resolve before cd: a relative path is relative to where the user ran us.
TPL_ARG=$TPL
TPL=$(CDPATH= cd -- "$TPL" 2>/dev/null && pwd) || { echo "sync-template: $TPL_ARG is not a directory" >&2; exit 1; }

PROJ=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "sync-template: run it inside the project's git repo" >&2; exit 1; }
cd "$PROJ" || exit 1
COMMIT=$(git -C "$TPL" rev-parse --verify -q "$REF^{commit}") || { echo "sync-template: '$REF' is not a commit in $TPL" >&2; exit 1; }
OWNERS=$(git -C "$TPL" show "$COMMIT:docs/template-files.md" 2>/dev/null) || { echo "sync-template: $TPL has no docs/template-files.md at $REF" >&2; exit 1; }

STAMP_FILE=.claude/template-version
BASE=""
[ -f "$STAMP_FILE" ] && BASE=$(sed -n 's/^commit //p' "$STAMP_FILE" | head -1)
[ -n "$BASE" ] && ! git -C "$TPL" cat-file -e "$BASE^{commit}" 2>/dev/null && BASE=""

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# "glob<TAB>owner" rows, in file order: the first matching row wins.
printf '%s\n' "$OWNERS" | sed -n 's/^| `\([^`]*\)` | \(template\|project\|merged\) |.*/\1\t\2/p' >"$TMP/rules"
owner_of() { # $1 = path
  local g o
  while IFS=$'\t' read -r g o; do
    # shellcheck disable=SC2053  # $g is a glob on purpose
    [[ $1 == $g ]] && { echo "$o"; return; }
  done <"$TMP/rules"
  echo project   # unlisted = not ours to touch
}

# Was this project copy ever shipped by the template? With a stamp, compare to
# the stamped version; without one, to every historical version of the path.
known_version() { # $1 = path, $2 = project blob
  local c
  if [ -n "$BASE" ] && git -C "$TPL" cat-file -e "$BASE:$1" 2>/dev/null; then
    [ "$(git -C "$TPL" rev-parse "$BASE:$1")" = "$2" ]; return
  fi
  for c in $(git -C "$TPL" log --format=%H "$COMMIT" -- "$1"); do
    [ "$(git -C "$TPL" rev-parse -q --verify "$c:$1" 2>/dev/null)" = "$2" ] && return 0
  done
  return 1
}

# A symlinked path (or parent) may point outside the project: never write through it.
through_symlink() { # $1 = path
  local p=$1
  while [ "$p" != . ] && [ "$p" != / ]; do [ -L "$p" ] && return 0; p=$(dirname "$p"); done
  return 1
}

# Entries of a project list file, without comments, CRLF or a leading ./
list_entries() { # $1 = file
  [ -f "$1" ] && sed -e 's/\r$//' -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e 's#^\./##' -e '/^$/d' "$1"
}
listed() { # $1 = path, $2 = entries
  local g
  [ -n "$2" ] || return 1
  while IFS= read -r g; do
    # shellcheck disable=SC2053  # $g is a glob on purpose
    case $g in */) [[ $1 == "$g"* ]] && return 0 ;; *) [[ $1 == $g ]] && return 0 ;; esac
  done <<<"$2"
  return 1
}
EXCLUDE=$(list_entries .claude/template-exclude)
KEEP=$(list_entries .claude/template-keep)

# -z everywhere: core.quotePath would otherwise quote non-ASCII names.
NEW=(); UPDATED=(); MODIFIED=(); REMOVED=(); SYMLINKED=(); SETTINGS=""; EXCLUDED=0; KEPT=0
while IFS= read -r -d '' path; do
  listed "$path" "$EXCLUDE" && { EXCLUDED=$((EXCLUDED + 1)); continue; }
  case "$(owner_of "$path")" in
    template) ;;
    merged) [ "$path" = .claude/settings.json ] || continue
            if through_symlink "$path"; then SYMLINKED+=("$path"); else SETTINGS=1; fi
            continue ;;
    *) continue ;;
  esac
  if through_symlink "$path"; then SYMLINKED+=("$path"); continue; fi
  if [ ! -e "$path" ]; then NEW+=("$path"); continue; fi
  tblob=$(git -C "$TPL" rev-parse "$COMMIT:$path")
  pblob=$(git hash-object -- "$path")
  [ "$tblob" = "$pblob" ] && continue
  listed "$path" "$KEEP" && { KEPT=$((KEPT + 1)); continue; }
  if known_version "$path" "$pblob"; then UPDATED+=("$path"); else MODIFIED+=("$path"); fi
done < <(git -C "$TPL" ls-tree -r -z --name-only "$COMMIT")

# Template-owned project files the template no longer ships (but once did).
while IFS= read -r -d '' path; do
  [ "$(owner_of "$path")" = template ] || continue
  listed "$path" "$EXCLUDE" && continue
  git -C "$TPL" cat-file -e "$COMMIT:$path" 2>/dev/null && continue
  [ -n "$(git -C "$TPL" log -1 --format=%H "$COMMIT" -- "$path")" ] && REMOVED+=("$path")
done < <(git ls-files -z)

# settings.json, per hook event + matcher (per command) and permission list:
# template entries, minus those the project removed since the last sync, plus
# the project's own; entries the template shipped and later dropped go too.
# Commands calling .claude/hooks/ (not local/) are template-owned. Project env and other keys win.
SETTINGS_CHANGED=""
if [ -n "$SETTINGS" ]; then
  git -C "$TPL" show "$COMMIT:.claude/settings.json" >"$TMP/tpl-settings.json"
  { [ -n "$BASE" ] && git -C "$TPL" show "$BASE:.claude/settings.json" 2>/dev/null; } >"$TMP/base-settings.json" \
    || echo '{}' >"$TMP/base-settings.json"
  if [ ! -f .claude/settings.json ]; then
    cp "$TMP/tpl-settings.json" "$TMP/merged-settings.json"; SETTINGS_CHANGED=1
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "settings  .claude/settings.json — python3 missing, not merged. Template version differs by:"
    diff -u .claude/settings.json "$TMP/tpl-settings.json"
  else
    python3 - .claude/settings.json "$TMP/tpl-settings.json" "$TMP/base-settings.json" "$TMP/merged-settings.json" <<'PY' || exit 1
import json, sys
proj, tpl, base = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:4])


def template_cmd(c):
    return ".claude/hooks/" in c and ".claude/hooks/local/" not in c


def merge(t, mine, b, key=lambda x: x, drop_mine=lambda x: False):
    """Three-way: template entries, minus those the project removed since the
    base, plus the project's own (unless drop_mine says they are stale)."""
    tk, mk, bk = ({key(x) for x in l} for l in (t, mine, b))
    kept = [x for x in t if not (key(x) in bk and key(x) not in mk)]
    return kept + [x for x in mine if key(x) not in tk and not drop_mine(x)]


def groups(entries):  # {matcher: [hook, ...]} for {matcher, hooks} entries
    out = {}
    for e in entries:
        if isinstance(e, dict):
            out.setdefault(e.get("matcher"), []).extend(h for h in e.get("hooks", []) if isinstance(h, dict))
    return out


def merge_event(t, mine, b):
    # Plain-string entries (no matcher groups): whole-entry merge.
    strs = merge([x for x in t if isinstance(x, str)], [x for x in mine if isinstance(x, str)],
                 [x for x in b if isinstance(x, str)],
                 drop_mine=lambda x: x in b or template_cmd(x))
    # {matcher, hooks} groups: merged per command inside each matcher, so a
    # project edit to a template group keeps both sides.
    tg, mg, bg = groups(t), groups(mine), groups(b)
    cmd = lambda h: h.get("command", "")
    out = []
    for m in list(tg) + [m for m in mg if m not in tg]:
        base_cmds = {cmd(h) for h in bg.get(m, [])}
        hooks = merge(tg.get(m, []), mg.get(m, []), bg.get(m, []), key=cmd,
                      drop_mine=lambda h: cmd(h) in base_cmds or template_cmd(cmd(h)))
        # A field the project set on a template hook (e.g. a longer Stop
        # timeout) wins over the template's value; untouched fields update.
        # Without the hook in the base, a project value may just be stale:
        # the template wins.
        mine_by, base_by = ({cmd(h): h for h in l} for l in (mg.get(m, []), bg.get(m, [])))
        hooks = [{**h, **{k: v for k, v in mine_by[cmd(h)].items() if base_by[cmd(h)].get(k) != v}}
                 if cmd(h) in mine_by and cmd(h) in base_by else h for h in hooks]
        if hooks:
            src = next((e for e in t + mine if isinstance(e, dict) and e.get("matcher") == m), {})
            out.append({**{k: v for k, v in src.items() if k != "hooks"}, "hooks": hooks})
    return strs + out


out = dict(proj)
for k, v in tpl.items():
    if k == "hooks":
        mine_h, base_h = proj.get(k, {}), base.get(k, {})
        hooks = {}
        for ev in list(v) + [e for e in mine_h if e not in v]:
            merged = merge_event(v.get(ev, []), mine_h.get(ev, []), base_h.get(ev, []))
            if merged:
                hooks[ev] = merged
        out[k] = hooks
    elif k == "permissions":
        perms = dict(proj.get(k, {}))
        for pk, pv in v.items():
            if isinstance(pv, list):
                b = base.get(k, {}).get(pk, [])
                perms[pk] = merge(pv, perms.get(pk, []), b, drop_mine=lambda x, b=b: x in b)
            else:
                perms.setdefault(pk, pv)
        out[k] = perms
    elif k == "env":
        out[k] = {**v, **proj.get(k, {})}
    else:
        out.setdefault(k, v)
with open(sys.argv[4], "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1],encoding="utf-8"))!=json.load(open(sys.argv[2],encoding="utf-8")))' \
      .claude/settings.json "$TMP/merged-settings.json" || SETTINGS_CHANGED=1
  fi
fi

echo "Template: $TPL @ $REF (${COMMIT:0:12})${BASE:+, last synced ${BASE:0:12}}"
for p in ${NEW[@]+"${NEW[@]}"}; do echo "new               $p"; done
for p in ${UPDATED[@]+"${UPDATED[@]}"}; do echo "updated           $p"; done
if [ -n "$SETTINGS_CHANGED" ]; then
  echo "merge             .claude/settings.json (template hooks/permissions, your own hooks/rules/env kept)"
  [ -f .claude/settings.json ] && diff -u --label "project/.claude/settings.json" --label "merged" \
    .claude/settings.json "$TMP/merged-settings.json" | head -60 | sed 's/^/    /'
fi
[ "$KEPT" -gt 0 ] && echo "kept              $KEPT adapted file(s) listed in .claude/template-keep"
[ "$EXCLUDED" -gt 0 ] && echo "excluded          $EXCLUDED template path(s) listed in .claude/template-exclude"
for p in ${SYMLINKED[@]+"${SYMLINKED[@]}"}; do echo "skipped (symlink) $p  (a symlinked path may point outside the project — update it by hand)"; done
for p in ${REMOVED[@]+"${REMOVED[@]}"}; do echo "removed upstream  $p  (kept — delete it yourself if unused)"; done
for p in ${MODIFIED[@]+"${MODIFIED[@]}"}; do
  echo "locally modified  $p  (kept — move your change into .claude/rules/local-*.md or .claude/hooks/local/)"
  git -C "$TPL" show "$COMMIT:$p" >"$TMP/tpl-file"
  diff -u --label "template/$p" --label "project/$p" "$TMP/tpl-file" "$p" | head -40 | sed 's/^/    /'
done

CHANGES=$(( ${#NEW[@]} + ${#UPDATED[@]} ))
[ -n "$SETTINGS_CHANGED" ] && CHANGES=$((CHANGES + 1))
OLD_STAMP=""; [ -f "$STAMP_FILE" ] && OLD_STAMP=$(sed -n 's/^commit //p' "$STAMP_FILE" | head -1)

if [ "$APPLY" != 1 ]; then
  if [ "$CHANGES" -eq 0 ]; then echo "no changes to apply."; else echo "$CHANGES change(s). Re-run with --apply to write them (nothing is committed)."; fi
  exit 0
fi

if [ "$CHANGES" -eq 0 ] && [ "$OLD_STAMP" = "$COMMIT" ]; then echo "no changes to apply."; exit 0; fi

for p in ${NEW[@]+"${NEW[@]}"} ${UPDATED[@]+"${UPDATED[@]}"}; do
  mkdir -p "$(dirname "$p")"
  git -C "$TPL" show "$COMMIT:$p" >"$p"
  [ "$(git -C "$TPL" ls-tree "$COMMIT" -- "$p" | cut -d' ' -f1)" = 100755 ] && chmod +x "$p"
done
[ -n "$SETTINGS_CHANGED" ] && { mkdir -p .claude; cp "$TMP/merged-settings.json" .claude/settings.json; }
if [ "$CHANGES" -gt 0 ] && [ -f scripts/sync-codex.sh ] && ! bash scripts/sync-codex.sh >/dev/null; then
  echo "sync-template: files written, but scripts/sync-codex.sh failed — not stamped. Fix it and re-run --apply." >&2
  exit 1
fi
mkdir -p .claude
printf 'commit %s\nref %s\ndate %s\n' "$COMMIT" "$REF" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$STAMP_FILE"
echo "applied $CHANGES change(s); stamped $STAMP_FILE. Review with git diff, run the tests, then commit."
