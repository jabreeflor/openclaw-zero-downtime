#!/usr/bin/env bash
# openclaw-watchdog.sh
# Health watchdog for OpenClaw gateway — runs via launchd every 5 minutes.
# - Probes gateway with `openclaw health --json`
# - Two consecutive failures → triggers `openclaw gateway restart`
# - Posts Discord alert on downtime detected and on recovery

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
OPENCLAW="${OPENCLAW_BIN:-/opt/homebrew/bin/openclaw}"
STATE_DIR="${HOME}/.openclaw/watchdog"
FAIL_COUNT_FILE="${STATE_DIR}/fail_count"
DOWN_SINCE_FILE="${STATE_DIR}/down_since"
DISCORD_WEBHOOK="${OPENCLAW_WATCHDOG_WEBHOOK:-}"          # optional: Discord webhook URL
DISCORD_BOT_TOKEN="${OPENCLAW_DISCORD_BOT_TOKEN:-}"       # optional: bot token
DISCORD_ALERT_CHANNEL="${OPENCLAW_ALERT_CHANNEL:-}"       # channel ID to post alerts
MAX_FAILURES=2                                            # failures before restart
HEALTH_TIMEOUT=10                                         # seconds for health probe
LOG="${STATE_DIR}/watchdog.log"

mkdir -p "${STATE_DIR}"

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG}"
}

# Rotate log if > 1MB
if [[ -f "${LOG}" ]] && [[ $(wc -c < "${LOG}") -gt 1048576 ]]; then
  mv "${LOG}" "${LOG}.1"
fi

# ── State helpers ─────────────────────────────────────────────────────────────
get_fail_count() {
  [[ -f "${FAIL_COUNT_FILE}" ]] && cat "${FAIL_COUNT_FILE}" || echo 0
}

set_fail_count() {
  echo "$1" > "${FAIL_COUNT_FILE}"
}

get_down_since() {
  [[ -f "${DOWN_SINCE_FILE}" ]] && cat "${DOWN_SINCE_FILE}" || echo ""
}

set_down_since() {
  echo "$1" > "${DOWN_SINCE_FILE}"
}

clear_down_state() {
  rm -f "${FAIL_COUNT_FILE}" "${DOWN_SINCE_FILE}"
}

# ── Discord alert ─────────────────────────────────────────────────────────────
discord_alert() {
  local message="$1"
  
  # Try webhook first
  if [[ -n "${DISCORD_WEBHOOK}" ]]; then
    curl -s -X POST "${DISCORD_WEBHOOK}" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"${message}\"}" \
      --max-time 10 || true
    return
  fi
  
  # Fall back to bot token + channel
  if [[ -n "${DISCORD_BOT_TOKEN}" && -n "${DISCORD_ALERT_CHANNEL}" ]]; then
    curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_ALERT_CHANNEL}/messages" \
      -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"${message}\"}" \
      --max-time 10 || true
    return
  fi
  
  log "ALERT (no Discord config): ${message}"
}

# ── Health probe ──────────────────────────────────────────────────────────────
probe_gateway() {
  if "${OPENCLAW}" health --json --timeout "${HEALTH_TIMEOUT}000" > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

# ── Duration formatter ────────────────────────────────────────────────────────
format_duration() {
  local seconds=$1
  local minutes=$(( seconds / 60 ))
  local hours=$(( minutes / 60 ))
  
  if [[ ${hours} -gt 0 ]]; then
    echo "${hours}h $((minutes % 60))m"
  elif [[ ${minutes} -gt 0 ]]; then
    echo "${minutes}m $((seconds % 60))s"
  else
    echo "${seconds}s"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
log "Probing OpenClaw gateway..."

if probe_gateway; then
  # Gateway is healthy
  fail_count=$(get_fail_count)
  down_since=$(get_down_since)
  
  if [[ -n "${down_since}" ]]; then
    # Recovery — was previously down
    now=$(date +%s)
    down_duration=$(format_duration $(( now - down_since )))
    log "✅ Gateway recovered after ${down_duration} downtime."
    discord_alert "✅ **OpenClaw gateway recovered** after ${down_duration} downtime. All systems nominal."
    clear_down_state
  else
    log "✅ Gateway healthy."
    clear_down_state
  fi
else
  # Probe failed
  fail_count=$(get_fail_count)
  fail_count=$(( fail_count + 1 ))
  set_fail_count "${fail_count}"
  
  log "⚠️ Health probe failed (${fail_count}/${MAX_FAILURES})."
  
  if [[ -z "$(get_down_since)" ]]; then
    set_down_since "$(date +%s)"
  fi
  
  if [[ "${fail_count}" -ge "${MAX_FAILURES}" ]]; then
    log "🔴 Consecutive failures reached threshold — restarting gateway..."
    discord_alert "🔴 **OpenClaw gateway DOWN** — ${fail_count} consecutive probe failures. Restarting now..."
    
    # Attempt restart
    if "${OPENCLAW}" gateway restart 2>&1 | tee -a "${LOG}"; then
      log "Restart command issued. Waiting 10s for startup..."
      sleep 10
      
      # Re-probe after restart
      if probe_gateway; then
        down_since=$(get_down_since)
        now=$(date +%s)
        down_duration=$(format_duration $(( now - down_since )))
        log "✅ Gateway back online after restart (was down ~${down_duration})."
        discord_alert "✅ **OpenClaw restarted successfully** — back online after ~${down_duration}."
        clear_down_state
      else
        log "❌ Gateway still not responding after restart attempt."
        discord_alert "❌ **OpenClaw restart attempted but gateway still unreachable.** Manual intervention may be needed."
      fi
    else
      log "❌ Restart command failed."
      discord_alert "❌ **OpenClaw restart command failed.** Check logs at \`~/.openclaw/watchdog/watchdog.log\`."
    fi
  fi
fi
