#!/usr/bin/env bash
# android-ui.sh — drive an Android device by on-screen text, not coordinates or
# sleeps. Audit 2026-11-25: an adb helper like this was rebuilt and sourced 329
# times across sessions. Read the UI dump first; screenshot only to prove layout.
#
#   bash scripts/android-ui.sh dump                    # UI hierarchy XML to stdout
#   bash scripts/android-ui.sh tap "Save"              # tap the node whose text/content-desc is "Save"
#   bash scripts/android-ui.sh wait-for "Save" [secs]  # poll the dump (default 20 s); names an ANR dialog
#   bash scripts/android-ui.sh shot out.png            # screenshot
#   bash scripts/android-ui.sh type "hello world" | key 66 | back
#   bash scripts/android-ui.sh swipe [x1 y1 x2 y2 [ms]]  # default: scroll down
#
# Env: ADB_SERIAL (device; default: the only one), UI_POLL (secs between dumps).

set -uo pipefail

POLL="${UI_POLL:-1}"
adb_() { adb ${ADB_SERIAL:+-s "$ADB_SERIAL"} "$@"; }

# A failed dump leaves the previous ui.xml behind: delete it first and trust
# the file only when uiautomator says it wrote it.
dump() {
  local msg
  adb_ shell rm -f /sdcard/ui.xml >/dev/null 2>&1
  msg=$(adb_ shell uiautomator dump /sdcard/ui.xml 2>&1)
  case "$msg" in
    *"dumped to"*) adb_ exec-out cat /sdcard/ui.xml ;;
    *) echo "android-ui: uiautomator dump failed: $(printf '%s' "$msg" | tr -d '\r' | tail -1)" >&2; return 1 ;;
  esac
}

# One <node .../> per line, so grep/sed can work node by node.
nodes() { sed 's/<node /\n<node /g'; }

anr() {  # prints the ANR dialog title; false when there is none
  local line
  line=$(printf '%s' "$1" | nodes | grep -m1 -E "isn't responding|isn&apos;t responding")
  if [ -n "$line" ]; then
    printf '%s' "$line" | sed -n 's/.* text="\([^"]*\)".*/\1/p' | sed "s/&apos;/'/g"
  elif printf '%s' "$1" | grep -q 'android:id/aerr_'; then
    echo "an app isn't responding"
  else
    return 1
  fi
}

has_text() { printf '%s' "$1" | grep -qF -e "text=\"$2\"" -e "content-desc=\"$2\""; }

tap() {
  local xml line b x1 y1 x2 y2
  xml=$(dump) || return 1
  line=$(printf '%s' "$xml" | nodes | grep -m1 -F -e "text=\"$1\"" -e "content-desc=\"$1\"")
  if [ -z "$line" ]; then
    echo "android-ui: no node with text or content-desc \"$1\" on screen" >&2
    return 1
  fi
  b=$(printf '%s' "$line" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
  read -r x1 y1 x2 y2 <<<"$b"
  [ -n "${y2:-}" ] || { echo "android-ui: \"$1\" has no bounds" >&2; return 1; }
  adb_ shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}

wait_for() {
  local secs="${2:-20}" xml title deadline
  deadline=$((SECONDS + secs))
  while :; do
    xml=$(dump 2>/dev/null)   # a dump fails while the UI animates: keep polling
    has_text "$xml" "$1" && return 0
    if title=$(anr "$xml"); then
      echo "android-ui: ANR dialog on screen: \"$title\" — the app's main thread is blocked; check: adb logcat -d | grep -A20 ANR" >&2
      return 2
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "android-ui: \"$1\" did not appear within ${secs}s (run: bash scripts/android-ui.sh dump)" >&2
      return 1
    fi
    sleep "$POLL"
  done
}

case "${1:-}" in
  dump) dump ;;
  tap) tap "${2:?text}" ;;
  wait-for) wait_for "${2:?text}" "${3:-}" ;;
  shot) adb_ exec-out screencap -p >"${2:?file}" ;;
  type) adb_ shell input text "$(printf '%s' "${2:?text}" | sed 's/ /%s/g')" ;;
  key) adb_ shell input keyevent "${2:?keycode}" ;;
  back) adb_ shell input keyevent 4 ;;
  swipe) shift; [ $# -ge 4 ] || set -- 540 1600 540 600 300
         adb_ shell input swipe "$@" ;;
  *) echo "usage: bash scripts/android-ui.sh dump|tap <text>|wait-for <text> [secs]|shot <file>|type <s>|key <k>|swipe [x1 y1 x2 y2 [ms]]|back" >&2; exit 2 ;;
esac
