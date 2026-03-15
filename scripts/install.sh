#!/usr/bin/env bash
# install.sh — Install OpenClaw watchdog + update scripts (no sudo required)
# Usage: ./scripts/install.sh

set -euo pipefail

SHARE_DIR="${HOME}/.local/share/openclaw"
BIN_DIR="${HOME}/bin"
PLIST_SRC="$(cd "$(dirname "$0")/.." && pwd)/launchd/ai.openclaw.watchdog.plist"
PLIST_DEST="${HOME}/Library/LaunchAgents/ai.openclaw.watchdog.plist"
WATCHDOG_SRC="$(cd "$(dirname "$0")" && pwd)/openclaw-watchdog.sh"
UPDATE_SRC="$(cd "$(dirname "$0")" && pwd)/openclaw-update.sh"

echo "Installing OpenClaw Zero-Downtime system..."

# Create dirs
mkdir -p "${SHARE_DIR}" "${BIN_DIR}"

# Install scripts
cp "${WATCHDOG_SRC}" "${SHARE_DIR}/openclaw-watchdog.sh"
cp "${UPDATE_SRC}"   "${SHARE_DIR}/openclaw-update.sh"
chmod +x "${SHARE_DIR}/openclaw-watchdog.sh"
chmod +x "${SHARE_DIR}/openclaw-update.sh"
echo "  ✓ Scripts installed to ${SHARE_DIR}/"

# Symlink to ~/bin (ensure it's in PATH)
ln -sf "${SHARE_DIR}/openclaw-update.sh"   "${BIN_DIR}/openclaw-update"
ln -sf "${SHARE_DIR}/openclaw-watchdog.sh" "${BIN_DIR}/openclaw-watchdog"
echo "  ✓ openclaw-update + openclaw-watchdog symlinked to ${BIN_DIR}/"

# Ensure ~/bin is in PATH (add to .zshrc / .bashrc if missing)
for rc in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
  if [ -f "$rc" ] && ! grep -q 'PATH.*HOME/bin' "$rc" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
    echo "  ✓ Added ~/bin to PATH in $(basename $rc)"
  fi
done

# Set gateway.reload.mode = hybrid
if command -v node &>/dev/null; then
  node -e "
const fs = require('fs');
const p = process.env.HOME + '/.openclaw/openclaw.json';
if (!fs.existsSync(p)) { console.log('  ⚠ openclaw.json not found — skip reload.mode'); process.exit(0); }
const d = JSON.parse(fs.readFileSync(p));
if (!d.gateway) d.gateway = {};
if (!d.gateway.reload) d.gateway.reload = {};
if (d.gateway.reload.mode !== 'hybrid') {
  d.gateway.reload.mode = 'hybrid';
  fs.writeFileSync(p, JSON.stringify(d, null, 2));
  console.log('  ✓ Set gateway.reload.mode = hybrid');
} else {
  console.log('  ✓ gateway.reload.mode already set to hybrid');
}
" 2>/dev/null || echo "  ⚠ Could not update openclaw.json"
fi

# Install LaunchAgent plist (watchdog probe every 5 min)
if [ -f "${PLIST_SRC}" ]; then
  cp "${PLIST_SRC}" "${PLIST_DEST}"
  launchctl unload "${PLIST_DEST}" 2>/dev/null || true
  launchctl load   "${PLIST_DEST}"
  echo "  ✓ Watchdog LaunchAgent installed + loaded (probes every 5 min)"
else
  echo "  ⚠ Plist not found at ${PLIST_SRC} — skipping LaunchAgent"
fi

echo ""
echo "Installation complete."
echo "  Scripts: ${SHARE_DIR}/"
echo "  PATH:    ${BIN_DIR}/"
echo "  Logs:    ~/.openclaw/watchdog/"
echo ""
echo "To configure Discord alerts:"
echo "  Edit ${PLIST_DEST}"
echo "  Set OPENCLAW_DISCORD_BOT_TOKEN + OPENCLAW_ALERT_CHANNEL"
echo "  Then: launchctl unload ~/Library/LaunchAgents/ai.openclaw.watchdog.plist"
echo "        launchctl load   ~/Library/LaunchAgents/ai.openclaw.watchdog.plist"
echo ""
echo "To run a zero-downtime update:"
echo "  openclaw-update"
