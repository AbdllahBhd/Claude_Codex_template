#!/usr/bin/env bash
# android-emu.sh — start/stop/inspect an Android emulator without blind sleeps.
# Audit 2026-11-25: the boot loop was rewritten ~17 times across sessions and
# 1,220 `sleep`s cost about an hour of waiting. Use this instead.
#
#   bash scripts/android-emu.sh up       # boot $AVD (or the first AVD) and wait until ready
#   bash scripts/android-emu.sh down     # stop the emulator and the Gradle daemon
#   bash scripts/android-emu.sh status   # devices, boot state, free RAM, heaviest processes
#
# Env: AVD (name), ADB_SERIAL (device), EMU_HEADLESS=1 (-no-window),
#      EMU_BOOT_TIMEOUT (secs, default 240), EMU_MIN_FREE_MB (default 1024),
#      EMU_LOG (default $TMPDIR/android-emu.log).

set -uo pipefail
# Git Bash would rewrite /sdcard and /data into Windows paths for adb.exe.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

BOOT_TIMEOUT="${EMU_BOOT_TIMEOUT:-240}"
POLL="${EMU_POLL:-2}"
LOG="${EMU_LOG:-${TMPDIR:-/tmp}/android-emu.log}"
MIN_FREE_MB="${EMU_MIN_FREE_MB:-1024}"

adb_() { adb ${ADB_SERIAL:+-s "$ADB_SERIAL"} "$@"; }
# Without ADB_SERIAL, target a running emulator, never an attached phone.
pick_emulator() {
  [ -n "${ADB_SERIAL:-}" ] && return 0
  ADB_SERIAL=$(adb devices 2>/dev/null | awk '$1 ~ /^emulator-[0-9]+$/ && $2 == "device" {print $1; exit}')
}
free_port() {
  local p=5554 used
  used=$(adb devices 2>/dev/null | awk '{print $1}')
  while printf '%s\n' "$used" | grep -qx "emulator-$p"; do p=$((p + 2)); done
  echo "$p"
}
booted() { [ "$(adb_ shell getprop sys.boot_completed 2>/dev/null | tr -d '\r[:space:]')" = "1" ]; }

check_space() {
  local kb
  kb=$(adb_ shell df -k /data 2>/dev/null | awk 'NR==2 {print $4}')
  case "$kb" in ''|*[!0-9]*) return 0 ;; esac
  if [ $((kb / 1024)) -lt "$MIN_FREE_MB" ]; then
    echo "android-emu: only $((kb / 1024)) MB free on /data (< $MIN_FREE_MB MB): installs will fail."
    echo "  Fix: bash scripts/android-emu.sh down, then start once with: emulator -avd ${AVD:-<avd>} -wipe-data"
  fi
}

up() {
  pick_emulator
  if [ -n "${ADB_SERIAL:-}" ] && booted; then echo "android-emu: $ADB_SERIAL already booted"; check_space; return 0; fi
  local port="" pid="" avd=""
  case "${ADB_SERIAL:-}" in
    "") port=$(free_port) ;;
    emulator-*) adb devices 2>/dev/null | grep -q "^$ADB_SERIAL[[:space:]]" || port=${ADB_SERIAL#emulator-} ;;
    *) echo "android-emu: $ADB_SERIAL is not booted and is not an emulator" >&2; return 1 ;;
  esac
  if [ -n "$port" ]; then
    avd="${AVD:-$(emulator -list-avds 2>/dev/null | head -1)}"
    [ -n "$avd" ] || { echo "android-emu: no AVD (set AVD=<name>; list with: emulator -list-avds)" >&2; return 1; }
    # An explicit port gives a known serial, so a phone on USB never gets the calls.
    local args=(-avd "$avd" -port "$port" -no-snapshot-save -no-audio)
    [ "${EMU_HEADLESS:-0}" = "1" ] && args+=(-no-window)
    # Detached so the emulator outlives this shell and never ties up the agent's tool call.
    if command -v setsid >/dev/null 2>&1; then
      setsid nohup emulator "${args[@]}" </dev/null >"$LOG" 2>&1 &
    else
      nohup emulator "${args[@]}" </dev/null >"$LOG" 2>&1 &
    fi
    pid=$!
    ADB_SERIAL="emulator-$port"
    echo "android-emu: starting $avd as $ADB_SERIAL (log: $LOG), waiting up to ${BOOT_TIMEOUT}s"
  else
    echo "android-emu: $ADB_SERIAL is still booting, waiting up to ${BOOT_TIMEOUT}s"
  fi
  local deadline=$((SECONDS + BOOT_TIMEOUT))
  until booted; do
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      echo "android-emu: the emulator exited before booting. Last log lines:" >&2
      tail -n 5 "$LOG" 2>/dev/null >&2
      return 1
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "android-emu: ${avd:-$ADB_SERIAL} did not boot within ${BOOT_TIMEOUT}s. Last log lines:" >&2
      tail -n 5 "$LOG" 2>/dev/null >&2
      return 1
    fi
    sleep "$POLL"
  done
  echo "android-emu: ${avd:-$ADB_SERIAL} booted"
  check_space
}

down() {
  pick_emulator
  [ -n "${ADB_SERIAL:-}" ] && adb_ emu kill >/dev/null 2>&1 && echo "android-emu: emulator stopped" || echo "android-emu: no emulator to stop"
  # Gradle daemons hold GBs of RAM after a build; stop them via gradle itself (no pkill -f).
  local g
  for g in ./android/gradlew ./gradlew; do
    [ -x "$g" ] && { "$g" --stop >/dev/null 2>&1; echo "android-emu: gradle daemon stopped ($g)"; return 0; }
  done
  command -v gradle >/dev/null 2>&1 && gradle --stop >/dev/null 2>&1 && echo "android-emu: gradle daemon stopped"
  return 0
}

status() {
  pick_emulator
  adb devices 2>/dev/null | sed 1d | sed '/^$/d' | sed 's/^/device: /'
  booted && echo "boot: completed" || echo "boot: not booted"
  command -v free >/dev/null 2>&1 && free -m | awk 'NR==2 {print "RAM free: " $7 " MB of " $2 " MB"}'
  echo "heaviest processes:"
  ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6 || ps | head -6
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  *) echo "usage: bash scripts/android-emu.sh up|down|status" >&2; exit 2 ;;
esac
