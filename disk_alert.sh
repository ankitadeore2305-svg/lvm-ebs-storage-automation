#!/bin/bash
###############################################################################
# disk_alert.sh
# Monitors disk usage on a target mount point and sends an alert when usage
# crosses a configurable threshold. Designed to run via cron for continuous
# monitoring of LVM-backed volumes (e.g. /data).
#
# Usage:
#   ./disk_alert.sh [MOUNT_POINT] [THRESHOLD_PERCENT]
#
# Example:
#   ./disk_alert.sh /data 80
#
# Cron example (check every 5 minutes):
#   */5 * * * * /opt/scripts/disk_alert.sh /data 80 >> /var/log/disk_alert.log 2>&1
###############################################################################

MOUNT_POINT="${1:-/data}"
THRESHOLD="${2:-80}"
LOG_FILE="/var/log/disk_alert.log"
HOSTNAME_TAG="$(hostname)"

# --- Optional: set this to enable email alerts (requires mailutils/mailx) ---
ALERT_EMAIL=""

# --- Optional: set this to enable Slack alerts via webhook ---
SLACK_WEBHOOK_URL=""

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

# Verify the mount point exists
if ! mountpoint -q "$MOUNT_POINT"; then
    log "ERROR: $MOUNT_POINT is not a valid mount point. Exiting."
    exit 1
fi

# Get usage percentage (strip the % sign)
USAGE=$(df -h --output=pcent "$MOUNT_POINT" | tail -1 | tr -dc '0-9')
AVAIL=$(df -h --output=avail "$MOUNT_POINT" | tail -1 | xargs)
SIZE=$(df -h --output=size "$MOUNT_POINT" | tail -1 | xargs)

if [ -z "$USAGE" ]; then
    log "ERROR: Could not determine disk usage for $MOUNT_POINT."
    exit 1
fi

log "Checked $MOUNT_POINT — Usage: ${USAGE}% | Size: ${SIZE} | Available: ${AVAIL}"

if [ "$USAGE" -ge "$THRESHOLD" ]; then
    MESSAGE="⚠️ ALERT [$HOSTNAME_TAG]: $MOUNT_POINT usage is at ${USAGE}% (threshold: ${THRESHOLD}%). Available: ${AVAIL}."
    log "$MESSAGE"

    # Console/log alert (always happens)
    echo "$MESSAGE"

    # Email alert (optional)
    if [ -n "$ALERT_EMAIL" ] && command -v mail >/dev/null 2>&1; then
        echo "$MESSAGE" | mail -s "Disk Alert: $MOUNT_POINT at ${USAGE}%" "$ALERT_EMAIL"
    fi

    # Slack alert (optional)
    if [ -n "$SLACK_WEBHOOK_URL" ] && command -v curl >/dev/null 2>&1; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$MESSAGE\"}" \
            "$SLACK_WEBHOOK_URL" >/dev/null
    fi

    exit 2   # non-zero exit so cron/monitoring systems can detect the alert state
else
    log "OK: $MOUNT_POINT usage (${USAGE}%) is below threshold (${THRESHOLD}%)."
    exit 0
fi
