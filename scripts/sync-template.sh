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
# .claude/settings.json is "merged": template owns hooks + permissions, the
# project keeps env and everything else (needs python3; without it the diff is
# printed and the file is left alone).
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

NEW=(); UPDATED=(); MODIFIED=(); REMOVED=(); SETTINGS=""
while IFS= read -r path; do
  case "$(owner_of "$path")" in
    template) ;;
    merged) [ "$path" = .claude/settings.json ] && SETTINGS=1; continue ;;
    *) continue ;;
  esac
  if [ ! -e "$path" ]; then NEW+=("$path"); continue; fi
  tblob=$(git -C "$TPL" rev-parse "$COMMIT:$path")
  pblob=$(git hash-object -- "$path")
  [ "$tblob" = "$pblob" ] && continue
  if known_version "$path" "$pblob"; then UPDATED+=("$path"); else MODIFIED+=("$path"); fi
done < <(git -C "$TPL" ls-tree -r --name-only "$COMMIT")

# Template-owned project files the template no longer ships (but once did).
while IFS= read -r path; do
  [ "$(owner_of "$path")" = template ] || continue
  git -C "$TPL" cat-file -e "$COMMIT:$path" 2>/dev/null && continue
  [ -n "$(git -C "$TPL" log -1 --format=%H "$COMMIT" -- "$path")" ] && REMOVED+=("$path")
done < <(git ls-files)

# settings.json: template hooks + permissions (allow/ask/deny lists unioned),
# project env and other keys win; template env keys the project lacks are added.
SETTINGS_CHANGED=""
if [ -n "$SETTINGS" ]; then
  git -C "$TPL" show "$COMMIT:.claude/settings.json" >"$TMP/tpl-settings.json"
  if [ ! -f .claude/settings.json ]; then
    cp "$TMP/tpl-settings.json" "$TMP/merged-settings.json"; SETTINGS_CHANGED=1
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "settings  .claude/settings.json — python3 missing, not merged. Template version differs by:"
    diff -u .claude/settings.json "$TMP/tpl-settings.json"
  else
    python3 - .claude/settings.json "$TMP/tpl-settings.json" "$TMP/merged-settings.json" <<'PY' || exit 1
import json, sys
proj, tpl = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3])
out = dict(proj)
for k, v in tpl.items():
    if k == "hooks":
        out[k] = v
    elif k == "permissions":
        perms = dict(proj.get(k, {}))
        for pk, pv in v.items():
            if isinstance(pv, list):
                mine = perms.get(pk, [])
                perms[pk] = pv + [x for x in mine if x not in pv]
            else:
                perms.setdefault(pk, pv)
        out[k] = perms
    elif k == "env":
        out[k] = {**v, **proj.get(k, {})}
    else:
        out.setdefault(k, v)
with open(sys.argv[3], "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))!=json.load(open(sys.argv[2])))' \
      .claude/settings.json "$TMP/merged-settings.json" || SETTINGS_CHANGED=1
  fi
fi

echo "Template: $TPL @ $REF (${COMMIT:0:12})${BASE:+, last synced ${BASE:0:12}}"
for p in "${NEW[@]}"; do echo "new               $p"; done
for p in "${UPDATED[@]}"; do echo "updated           $p"; done
[ -n "$SETTINGS_CHANGED" ] && echo "merge             .claude/settings.json (template hooks/permissions, your env kept)"
for p in "${REMOVED[@]}"; do echo "removed upstream  $p  (kept — delete it yourself if unused)"; done
for p in "${MODIFIED[@]}"; do
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

for p in "${NEW[@]}" "${UPDATED[@]}"; do
  mkdir -p "$(dirname "$p")"
  git -C "$TPL" show "$COMMIT:$p" >"$p"
  [ "$(git -C "$TPL" ls-tree "$COMMIT" -- "$p" | cut -d' ' -f1)" = 100755 ] && chmod +x "$p"
done
[ -n "$SETTINGS_CHANGED" ] && { mkdir -p .claude; cp "$TMP/merged-settings.json" .claude/settings.json; }
[ "$CHANGES" -gt 0 ] && [ -f scripts/sync-codex.sh ] && bash scripts/sync-codex.sh >/dev/null
mkdir -p .claude
printf 'commit %s\nref %s\ndate %s\n' "$COMMIT" "$REF" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$STAMP_FILE"
echo "applied $CHANGES change(s); stamped $STAMP_FILE. Review with git diff, run the tests, then commit."
