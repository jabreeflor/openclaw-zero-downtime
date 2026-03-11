#!/usr/bin/env bash
# install.sh — Install OpenClaw watchdog + update scripts
# Usage: ./scripts/install.sh

set -euo pipefail

SHARE_DIR="/usr/local/share/openclaw"
PLIST_SRC="$(dirname "$0")/../launchd/ai.openclaw.watchdog.plist"
PLIST_DEST="${HOME}/Library/LaunchAgents/ai.openclaw.watchdog.plist"
WATCHDOG_SRC="$(dirname "$0")/openclaw-watchdog.sh"
UPDATE_SRC="$(dirname "$0")/openclaw-update.sh"

echo "Installing OpenClaw Zero-Downtime system..."

# Create share dir
sudo mkdir -p "${SHARE_DIR}"

# Install scripts
sudo cp "${WATCHDOG_SRC}" "${SHARE_DIR}/openclaw-watchdog.sh"
sudo cp "${UPDATE_SRC}" "${SHARE_DIR}/openclaw-update.sh"
sudo chmod +x "${SHARE_DIR}/openclaw-watchdog.sh"
sudo chmod +x "${SHARE_DIR}/openclaw-update.sh"
echo "  ✓ Scripts installed to ${SHARE_DIR}/"

# Symlink update script to PATH
sudo ln -sf "${SHARE_DIR}/openclaw-update.sh" /usr/local/bin/openclaw-update
echo "  ✓ openclaw-update available in PATH"

# Install LaunchAgent plist
cp "${PLIST_SRC}" "${PLIST_DEST}"
echo "  ✓ LaunchAgent plist installed"

# Load plist (unload first if already loaded)
launchctl unload "${PLIST_DEST}" 2>/dev/null || true
launchctl load "${PLIST_DEST}"
echo "  ✓ LaunchAgent loaded (watchdog active)"

echo ""
echo "Done. Watchdog will probe OpenClaw every 5 minutes."
echo "Logs: ~/.openclaw/watchdog/watchdog.log"
echo ""
echo "To configure Discord alerts, edit:"
echo "  ${PLIST_DEST}"
echo "and set OPENCLAW_DISCORD_BOT_TOKEN + OPENCLAW_ALERT_CHANNEL"
echo "then: launchctl unload ${PLIST_DEST} && launchctl load ${PLIST_DEST}"
echo ""
echo "To run a zero-downtime update:"
echo "  openclaw-update"
