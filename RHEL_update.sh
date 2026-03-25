#!/bin/bash

# -----------------------------
# CONFIG
# -----------------------------
LOG_FILE="$HOME/devbox_update.log"
S3_BUCKET="s3://aws-163544304364-repo"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Ensure AWS CLI works in cron
AWS_CMD=$(which aws)

# Items to back up
ITEMS=(
    "/home/kkhoja/Code/100-days-of-Python"
    "/home/kkhoja/Code/Boto3"
    "/home/kkhoja/Code/My-Notes"
    "/home/kkhoja/Code/Terraform-Notes"
    "/home/kkhoja/Code/shell-script"
)

SUCCESSFUL_ITEMS=()
FAILED_ITEMS=()

# -----------------------------
# LOG FUNCTION
# -----------------------------
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log "=============================="
log "Starting DevBox Update: $(date)"
log "=============================="

# -----------------------------
# SYSTEM UPDATE
# -----------------------------
log "Updating system packages..."

sudo apt update -y >> "$LOG_FILE" 2>&1
sudo apt upgrade -y >> "$LOG_FILE" 2>&1
sudo apt dist-upgrade -y >> "$LOG_FILE" 2>&1

# -----------------------------
# CLEANUP
# -----------------------------
log "Cleaning up..."
sudo apt autoremove -y >> "$LOG_FILE" 2>&1
sudo apt-get clean >> "$LOG_FILE" 2>&1

# -----------------------------
# SERVICE RESTART (SAFE)
# -----------------------------
restart_if_exists () {
    SERVICE=$1
    if systemctl list-unit-files | grep -q "^$SERVICE"; then
        log "Restarting $SERVICE..."
        sudo systemctl restart $SERVICE >> "$LOG_FILE" 2>&1
    else
        log "$SERVICE not installed, skipping..."
    fi
}

restart_if_exists docker.service
restart_if_exists kubelet.service

# -----------------------------
# PYTHON SAFE MODE
# -----------------------------
log "Checking Python packages..."

if command -v pip3 &> /dev/null; then
    pip3 list --outdated >> "$LOG_FILE" 2>&1

    for pkg in $(pip3 list --outdated --format=columns | awk 'NR>2 {print $1}'); do
        pip3 install --upgrade --user "$pkg" >> "$LOG_FILE" 2>&1
    done

    pip3 list --outdated >> "$LOG_FILE" 2>&1
else
    log "pip3 not found, skipping Python updates"
fi

# -----------------------------
# AWS CLI VALIDATION
# -----------------------------
log "Checking AWS CLI..."

AWS_OK=true

if [ -z "$AWS_CMD" ]; then
    log "AWS CLI not found"
    AWS_OK=false
else
    if ! $AWS_CMD sts get-caller-identity &> /dev/null; then
        log "AWS CLI not configured properly"
        AWS_OK=false
    fi
fi

# -----------------------------
# S3 BACKUP (GLACIER IR)
# -----------------------------
if [ "$AWS_OK" = true ]; then
    log "Starting S3 backup (Glacier Instant Retrieval)..."

    for ITEM in "${ITEMS[@]}"; do
        ITEM_NAME=$(basename "$ITEM")

        if [ -d "$ITEM" ]; then
            $AWS_CMD s3 cp "$ITEM/" "$S3_BUCKET/$ITEM_NAME/" \
                --recursive \
                --storage-class GLACIER_IR >> "$LOG_FILE" 2>&1
        else
            $AWS_CMD s3 cp "$ITEM" "$S3_BUCKET/$ITEM_NAME" \
                --storage-class GLACIER_IR >> "$LOG_FILE" 2>&1
        fi

        if [ $? -eq 0 ]; then
            log "SUCCESS: $ITEM"
            SUCCESSFUL_ITEMS+=("$ITEM")
        else
            log "FAILED: $ITEM"
            FAILED_ITEMS+=("$ITEM")
        fi

        sleep 2
    done

    log "S3 Backup Complete (Glacier IR)"
else
    log "Skipping S3 backup (AWS not ready)"
fi

# -----------------------------
# SUMMARY
# -----------------------------
log "=============================="
log "Backup Summary"
log "=============================="

if [ ${#SUCCESSFUL_ITEMS[@]} -ne 0 ]; then
    log "Successful:"
    for ITEM in "${SUCCESSFUL_ITEMS[@]}"; do
        log "$ITEM"
    done
else
    log "No successful backups"
fi

if [ ${#FAILED_ITEMS[@]} -ne 0 ]; then
    log "Failed:"
    for ITEM in "${FAILED_ITEMS[@]}"; do
        log "$ITEM"
    done
else
    log "No failed backups"
fi

# -----------------------------
# DONE
# -----------------------------
log "=============================="
log "DevBox Update Completed: $(date)"
log "=============================="
