#!/usr/bin/env bash
# gate-scope.sh — decide how much verification a branch's diff needs.
#
#   bash scripts/gate-scope.sh [base] [head]     (defaults: develop, HEAD)
#
# Prints TIER=cosmetic|targeted|full plus the files that decided it:
#   cosmetic  only styles/markup/assets/docs changed  -> lint + look at the result
#   targeted  code changed, no shared-core path hit   -> tests for touched modules
#   full      a shared-core path changed              -> the full suite
#
# Shared core is declared per project in .claude/gate-core-paths (one extended
# regex per line, e.g. ^lib/models/ or ^supabase/migrations/). WITHOUT that file,
# any code change is treated as full — the safe default.
# Extra cosmetic patterns may be added in .claude/gate-cosmetic-paths.

set -euo pipefail

BASE="${1:-develop}"
HEAD="${2:-HEAD}"
git rev-parse --verify -q "$BASE" >/dev/null || BASE=main

COSMETIC='\.(css|scss|sass|less|html?|svg|png|jpe?g|webp|gif|ico|avif|woff2?|ttf|otf|md|txt)$|^docs/'
[ -f .claude/gate-cosmetic-paths ] && \
  COSMETIC="$COSMETIC|$(grep -vE '^\s*(#|$)' .claude/gate-cosmetic-paths | paste -sd'|')"

FILES=$(git diff --name-only "$BASE...$HEAD")
if [ -z "$FILES" ]; then echo "TIER=none (no changes vs $BASE)"; exit 0; fi

CODE=$(printf '%s\n' "$FILES" | grep -vE "$COSMETIC" || true)
if [ -z "$CODE" ]; then
  echo "TIER=cosmetic"
  echo "Only styles/markup/assets/docs changed — run lint and verify visually; no test suites."
  exit 0
fi

if [ ! -f .claude/gate-core-paths ]; then
  echo "TIER=full"
  echo "Code changed and no .claude/gate-core-paths is declared (safe default). Code files:"
  printf '  %s\n' $CODE
  exit 0
fi

CORE=$(grep -vE '^\s*(#|$)' .claude/gate-core-paths | paste -sd'|')
HIT=$(printf '%s\n' "$CODE" | grep -E "$CORE" || true)
if [ -n "$HIT" ]; then
  echo "TIER=full"
  echo "Shared-core paths changed:"
  printf '  %s\n' $HIT
else
  echo "TIER=targeted"
  echo "Run the tests covering these files only:"
  printf '  %s\n' $CODE
fi
