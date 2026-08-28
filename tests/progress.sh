#!/usr/bin/env bash
# progress.sh — "eye-watch" progress telemetry for long scripts (#392)
#
# Source this file, then use:
#   progress_start "stage" [max_idle_sec]   # begin a stage (prints "[stage] start")
#   progress_tick done total                # heartbeat: elapsed + ETA (throttled)
#   progress_done                           # end a stage (prints "[stage] done in Ns")
#
# A background watchdog warns if a stage makes no progress (no tick) for
# longer than max_idle_sec. Set PROGRESS_QUIET=1 to silence output (CI).
#
# Example:
#   source "$(dirname "$0")/progress.sh"
#   progress_start "load" 60
#   for i in $(seq 1 1000); do ... ; progress_tick "$i" 1000; done
#   progress_done

_progress_ts() { date +%s; }

PROGRESS_STAGE=""
PROGRESS_START=0
PROGRESS_LAST=0
PROGRESS_HB=""
PROGRESS_WATCHDOG=""
PROGRESS_DONE=0

progress_start() {
  PROGRESS_STAGE="${1:-stage}"
  local max_idle="${2:-0}"
  PROGRESS_START=$(_progress_ts)
  PROGRESS_LAST=$PROGRESS_START
  PROGRESS_DONE=0
  PROGRESS_HB="/tmp/progress-hb-$$"
  echo "$PROGRESS_START" > "$PROGRESS_HB"
  [ "${PROGRESS_QUIET:-0}" = 1 ] || echo "[$PROGRESS_STAGE] start" >&2

  # background watchdog: warn if no heartbeat for > max_idle seconds
  if [ "$max_idle" -gt 0 ] 2>/dev/null; then
    (
      local_hb="$PROGRESS_HB"; local_stage="$PROGRESS_STAGE"; local_max="$max_idle"
      while true; do
        sleep 15
        now=$(date +%s)
        last=$(cat "$local_hb" 2>/dev/null || echo 0)
        if [ $((now - last)) -gt "$local_max" ]; then
          echo "  [!] [$local_stage] no progress in >${local_max}s (hung?)" >&2
        fi
      done
    ) &
    PROGRESS_WATCHDOG=$!
  fi
}

progress_tick() {
  local done="${1:-0}" total="${2:-0}"
  local now; now=$(_progress_ts)
  [ -n "$PROGRESS_HB" ] && echo "$now" > "$PROGRESS_HB"
  # throttle: at most one line per 2s
  if [ $((now - PROGRESS_LAST)) -lt 2 ]; then return; fi
  PROGRESS_LAST=$now
  [ "${PROGRESS_QUIET:-0}" = 1 ] && return
  local elapsed=$((now - PROGRESS_START))
  if [ "$total" -gt 0 ] 2>/dev/null && [ "$done" -gt 0 ] 2>/dev/null; then
    local pct=$((done * 100 / total))
    local eta=$((elapsed * (total - done) / done))
    echo "  [$PROGRESS_STAGE] $done/$total (${pct}%, ${elapsed}s elapsed, ~${eta}s left)" >&2
  else
    echo "  [$PROGRESS_STAGE] $done done (${elapsed}s elapsed)" >&2
  fi
}

progress_done() {
  [ -n "$PROGRESS_WATCHDOG" ] && kill "$PROGRESS_WATCHDOG" 2>/dev/null
  PROGRESS_WATCHDOG=""
  [ -n "$PROGRESS_HB" ] && rm -f "$PROGRESS_HB"
  local elapsed=$(( $(_progress_ts) - PROGRESS_START ))
  [ "${PROGRESS_QUIET:-0}" = 1 ] || echo "[$PROGRESS_STAGE] done in ${elapsed}s" >&2
}
