#!/bin/bash
set -euo pipefail

export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
LOG_FILE="/home/kkhoja/jenkins-autostart.log"

sleep 20

echo "[$(date)] Jenkins autostart check" >> "$LOG_FILE"

# If Jenkins is installed as a systemd service, try to start it.
if systemctl list-unit-files 2>/dev/null | grep -q '^jenkins\.service'; then
  if systemctl is-active --quiet jenkins; then
    echo "[$(date)] Jenkins service already active" >> "$LOG_FILE"
  else
    sudo -n systemctl start jenkins >> "$LOG_FILE" 2>&1 || echo "[$(date)] Could not start jenkins.service (needs sudo or service missing runtime deps)" >> "$LOG_FILE"
  fi
fi

# If Jenkins is running as a container, try to start that container.
if command -v docker >/dev/null 2>&1; then
  docker start jenkins >> "$LOG_FILE" 2>&1 || true
fi
if command -v podman >/dev/null 2>&1; then
  podman start jenkins >> "$LOG_FILE" 2>&1 || true
fi

echo "[$(date)] Jenkins autostart script finished" >> "$LOG_FILE"
