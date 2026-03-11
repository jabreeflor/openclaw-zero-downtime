# OpenClaw Zero-Downtime

Health watchdog + zero-downtime update system for OpenClaw gateway on macOS.

## What's included

| File | Purpose |
|---|---|
| `scripts/openclaw-watchdog.sh` | Health probe every 5min — auto-restarts on 2 consecutive failures, Discord alerts |
| `scripts/openclaw-update.sh` | Zero-downtime `npm update -g openclaw` with health verification |
| `scripts/install.sh` | One-command install |
| `launchd/ai.openclaw.watchdog.plist` | launchd plist for periodic watchdog |

---

## Architecture

OpenClaw already provides:
- **`gateway.reload.mode = "hybrid"`** — hot-applies config changes that are safe, restarts only when required. Most day-to-day config edits are zero-downtime by default.
- **LaunchAgent with `KeepAlive`** — auto-restarts the gateway on crash, typically within 5–10s.

What this system adds:
1. **Active health monitoring** — probes every 5 min instead of waiting for a heartbeat to notice
2. **Faster recovery** — two failed probes triggers an explicit restart (vs waiting for launchd to notice a crash)
3. **Discord alerting** — know immediately when the gateway goes down or recovers
4. **Controlled version updates** — measures the restart window, verifies health before declaring success

### Why not dual-instance / nginx?

For a single-machine LaunchAgent deployment, dual-instance adds complexity with marginal benefit. Discord and Telegram queue messages during brief outages (typically <15s for a gateway restart), so the effective user-visible downtime is already near-zero. The investment is better spent on fast detection + fast recovery.

---

## Install

```bash
git clone https://github.com/jabreeflor/openclaw-zero-downtime.git
cd openclaw-zero-downtime
chmod +x scripts/*.sh
./scripts/install.sh
```

---

## Configuration

### Discord alerts (optional but recommended)

Edit `~/Library/LaunchAgents/ai.openclaw.watchdog.plist` and set either:

**Option A — Discord Webhook:**
```xml
<key>OPENCLAW_WATCHDOG_WEBHOOK</key>
<string>https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN</string>
```

**Option B — Bot token:**
```xml
<key>OPENCLAW_DISCORD_BOT_TOKEN</key>
<string>YOUR_BOT_TOKEN</string>
<key>OPENCLAW_ALERT_CHANNEL</key>
<string>YOUR_CHANNEL_ID</string>
```

Then reload:
```bash
launchctl unload ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
launchctl load ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
```

### Hot-reload config (already in OpenClaw)

Ensure your `~/.openclaw/openclaw.json` has:
```json
{
  "gateway": {
    "reload": {
      "mode": "hybrid"
    }
  }
}
```

`hybrid` is the default. This means most config edits are applied live with no restart.

**Hot-safe changes (no restart):**
- Agent prompts, heartbeat settings
- Channel allow/block lists
- Most agent behavior settings

**Requires restart:**
- Gateway port / bind mode
- Auth token changes
- Provider/model config

---

## Usage

### Check watchdog status
```bash
launchctl list | grep openclaw.watchdog
cat ~/.openclaw/watchdog/watchdog.log
```

### Run a zero-downtime update
```bash
openclaw-update
```

Output:
```
[2026-03-10 23:00:01] Current version: 2026.3.8 (3caab92)
[2026-03-10 23:00:01] Running: npm update -g openclaw
[2026-03-10 23:00:14] New version: 2026.3.10 (abc1234)
[2026-03-10 23:00:14] Version changed: 2026.3.8 → 2026.3.10. Restarting gateway...
[2026-03-10 23:00:30] Waiting for gateway... (3s elapsed)
[2026-03-10 23:00:33] ✅ Gateway healthy. Total restart window: 19s.
```

### Manual health probe
```bash
openclaw health --json
```

### Run watchdog manually
```bash
/usr/local/share/openclaw/openclaw-watchdog.sh
```

---

## Logs

| Log | Location |
|---|---|
| Watchdog | `~/.openclaw/watchdog/watchdog.log` |
| Update | `~/.openclaw/watchdog/update.log` |
| Gateway (OpenClaw native) | `/tmp/openclaw/openclaw-YYYY-MM-DD.log` |
| launchd stdout | `/tmp/openclaw-watchdog.log` |

---

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
rm ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
sudo rm -rf /usr/local/share/openclaw
sudo rm /usr/local/bin/openclaw-update
```
