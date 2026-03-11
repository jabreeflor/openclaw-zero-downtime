#!/usr/bin/env bash
# openclaw-update.sh
# Zero-downtime OpenClaw version update.
# Runs: npm update -g openclaw → waits for new binary → graceful restart → health verify.

set -euo pipefail

OPENCLAW="${OPENCLAW_BIN:-/opt/homebrew/bin/openclaw}"
DISCORD_WEBHOOK="${OPENCLAW_WATCHDOG_WEBHOOK:-}"
DISCORD_BOT_TOKEN="${OPENCLAW_DISCORD_BOT_TOKEN:-}"
DISCORD_ALERT_CHANNEL="${OPENCLAW_ALERT_CHANNEL:-}"
RESTART_WAIT=15          # seconds to wait after issuing restart
HEALTH_POLL_INTERVAL=3   # seconds between health probes post-restart
HEALTH_MAX_WAIT=60       # max seconds to wait for healthy state
LOG="${HOME}/.openclaw/watchdog/update.log"

mkdir -p "$(dirname "${LOG}")"

# ── Helpers ───────────────────────────────────────────────────────────────────
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG}"
}

discord_alert() {
  local message="$1"
  if [[ -n "${DISCORD_WEBHOOK}" ]]; then
    curl -s -X POST "${DISCORD_WEBHOOK}" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"${message}\"}" --max-time 10 || true
    return
  fi
  if [[ -n "${DISCORD_BOT_TOKEN}" && -n "${DISCORD_ALERT_CHANNEL}" ]]; then
    curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_ALERT_CHANNEL}/messages" \
      -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"${message}\"}" --max-time 10 || true
    return
  fi
  log "DISCORD (no config): ${message}"
}

get_version() {
  "${OPENCLAW}" --version 2>/dev/null | awk '{print $NF}' || echo "unknown"
}

probe_gateway() {
  "${OPENCLAW}" health --json --timeout 8000 > /dev/null 2>&1
}

wait_for_healthy() {
  local elapsed=0
  while [[ ${elapsed} -lt ${HEALTH_MAX_WAIT} ]]; do
    if probe_gateway; then
      return 0
    fi
    sleep "${HEALTH_POLL_INTERVAL}"
    elapsed=$(( elapsed + HEALTH_POLL_INTERVAL ))
    log "  Waiting for gateway... (${elapsed}s elapsed)"
  done
  return 1
}

# ── Main ──────────────────────────────────────────────────────────────────────
log "═══════════════════════════════════"
log "OpenClaw update starting..."

current_version=$(get_version)
log "Current version: ${current_version}"

discord_alert "🔄 **OpenClaw update starting** — current: \`${current_version}\`. Brief restart expected."

# Run update
log "Running: npm update -g openclaw"
if ! npm update -g openclaw 2>&1 | tee -a "${LOG}"; then
  log "❌ npm update failed. Aborting."
  discord_alert "❌ **OpenClaw update failed** at npm step. Gateway unchanged."
  exit 1
fi

new_version=$(get_version)
log "New version: ${new_version}"

if [[ "${current_version}" == "${new_version}" ]]; then
  log "ℹ️  Already on latest version (${current_version}). No restart needed."
  discord_alert "ℹ️ **OpenClaw already up to date** — version \`${current_version}\`. No restart needed."
  exit 0
fi

log "Version changed: ${current_version} → ${new_version}. Restarting gateway..."

restart_start=$(date +%s)

# Issue restart (LaunchAgent KeepAlive will handle respawn)
if ! "${OPENCLAW}" gateway restart 2>&1 | tee -a "${LOG}"; then
  log "⚠️  Restart command returned non-zero. Gateway may already be restarting via LaunchAgent."
fi

log "Waiting ${RESTART_WAIT}s for startup..."
sleep "${RESTART_WAIT}"

# Wait for healthy
if wait_for_healthy; then
  restart_end=$(date +%s)
  downtime=$(( restart_end - restart_start ))
  log "✅ Gateway healthy. Total restart window: ${downtime}s."
  discord_alert "✅ **OpenClaw updated** \`${current_version}\` → \`${new_version}\` — back online (${downtime}s window)."
else
  log "❌ Gateway did not become healthy within ${HEALTH_MAX_WAIT}s after update."
  discord_alert "❌ **OpenClaw update to \`${new_version}\` — gateway not responding** after ${HEALTH_MAX_WAIT}s. Check logs: \`~/.openclaw/watchdog/update.log\`"
  exit 1
fi
