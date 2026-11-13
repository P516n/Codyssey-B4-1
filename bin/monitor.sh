#!/usr/bin/env bash
# ==============================================================================
# Script Name : monitor.sh
# Description : System resource monitoring & health check automation script
# Target OS   : Ubuntu 24.04 LTS (Bash 5.2+)
# Author      : agent-dev
# Group       : agent-core
# Permission  : 750 (rwxr-x---)
# ==============================================================================

# strict mode for undefined variables
set -u

# --- Configuration & Paths ---
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"
TARGET_PORT="${AGENT_PORT:-15034}"
TARGET_PROC_PATTERN="${TARGET_PROC_PATTERN:-agent[-_]app}"

# Threshold configuration
CPU_THRESHOLD=20.0
MEM_THRESHOLD=10.0
DISK_THRESHOLD=80

# Log Rotation configuration (10MB, max 10 files)
MAX_LOG_SIZE=$((10 * 1024 * 1024)) # 10MB in bytes
MAX_LOG_FILES=10

# Ensure log directory exists (if permitted)
if [ ! -d "$AGENT_LOG_DIR" ]; then
    mkdir -p "$AGENT_LOG_DIR" 2>/dev/null || true
fi

# ==============================================================================
# Helper Functions
# ==============================================================================

# 1. CPU Usage (%) calculation using /proc/stat
get_cpu_usage() {
    local prev_idle prev_total idle total diff_idle diff_total usage
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    prev_idle=$((idle + iowait))
    prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    sleep 0.5

    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    idle=$((idle + iowait))
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    diff_idle=$((idle - prev_idle))
    diff_total=$((total - prev_total))

    if [ "$diff_total" -gt 0 ]; then
        awk -v dt="$diff_total" -v di="$diff_idle" 'BEGIN { printf "%.1f", ((dt - di) / dt) * 100 }'
    else
        echo "0.0"
    fi
}

# 2. Memory Usage (%) calculation using free
get_mem_usage() {
    free -m | awk '
        /Mem:/ {
            if ($2 > 0) {
                printf "%.1f", ($3 / $2) * 100
            } else {
                print "0.0"
            }
        }
    '
}

# 3. Disk Usage (Root partition Used %) calculation using df
get_disk_usage() {
    df -h / | awk 'NR==2 { gsub("%", "", $5); print $5 }'
}

# 4. Check Firewall status (UFW or firewalld)
check_firewall() {
    local fw_active=false
    local fw_name=""

    # Check UFW
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -qi "Status: active"; then
            fw_active=true
            fw_name="UFW"
        fi
    fi

    # Check firewalld if UFW is not active
    if [ "$fw_active" = false ] && command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -qi "running"; then
            fw_active=true
            fw_name="firewalld"
        fi
    fi

    if [ "$fw_active" = false ]; then
        echo "[WARNING] Firewall is inactive or not configured (UFW/firewalld)!"
    fi
}

# 5. Log Rotation (Max 10MB, Keep 10 files)
rotate_logs() {
    if [ -f "$LOG_FILE" ]; then
        local current_size
        current_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$current_size" -ge "$MAX_LOG_SIZE" ]; then
            # Remove the oldest file if it exceeds the limit
            [ -f "${LOG_FILE}.${MAX_LOG_FILES}" ] && rm -f "${LOG_FILE}.${MAX_LOG_FILES}"

            # Shift existing rotated files
            for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
                if [ -f "${LOG_FILE}.${i}" ]; then
                    mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
                fi
            done

            # Rotate current log file
            mv "$LOG_FILE" "${LOG_FILE}.1"
            touch "$LOG_FILE"
            chmod 660 "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

# 6. Generate Statistics Report from recent log entries
generate_statistics() {
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        return
    fi

    echo "====== STATISTICS REPORT ======"
    awk '
        BEGIN {
            cpu_sum = 0; mem_sum = 0; count = 0;
            cpu_max = -1; cpu_min = 9999;
            mem_max = -1; mem_min = 9999;
            cpu_max_time = ""; cpu_min_time = "";
            mem_max_time = ""; mem_min_time = "";
        }
        {
            # Match line format: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
            match($0, /\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] PID:[0-9]+ CPU:([0-9.]+)% MEM:([0-9.]+)% DISK_USED:([0-9]+)%/, arr)
            if (arr[1] != "") {
                ts = arr[1]
                c = arr[2] + 0.0
                m = arr[3] + 0.0

                cpu_sum += c
                mem_sum += m
                count++

                if (c > cpu_max) { cpu_max = c; cpu_max_time = ts }
                if (c < cpu_min) { cpu_min = c; cpu_min_time = ts }
                if (m > mem_max) { mem_max = m; mem_max_time = ts }
                if (m < mem_min) { mem_min = m; mem_min_time = ts }
            }
        }
        END {
            if (count > 0) {
                printf "[CPU]\n"
                printf "Average : %.1f%%\n", cpu_sum / count
                printf "Maximum : %.1f%% at %s\n", cpu_max, cpu_max_time
                printf "Minimum : %.1f%% at %s\n", cpu_min, cpu_min_time
                printf "[Memory]\n"
                printf "Average : %.1f%%\n", mem_sum / count
                printf "Maximum : %.1f%% at %s\n", mem_max, mem_max_time
                printf "Minimum : %.1f%% at %s\n", mem_min, mem_min_time
                printf "[Samples]\n"
                printf "Data Points: %d samples\n\n", count
            }
        }
    ' "$LOG_FILE"
}

# ==============================================================================
# Main Execution
# ==============================================================================

echo "====== SYSTEM MONITOR RESULT ======"
echo ""

# --- 1. Health Check (Exit on Failure) ---
echo "[HEALTH CHECK]"

# 1-1. Process Check
APP_PID=$(pgrep -f "$TARGET_PROC_PATTERN" | head -n 1 || true)
if [ -z "$APP_PID" ]; then
    echo "Checking process '${TARGET_PROC_PATTERN}'... [FAIL] (Process not running)"
    exit 1
fi
echo "Checking process '${TARGET_PROC_PATTERN}'... [OK] (PID: ${APP_PID})"

# 1-2. Port Listen Check
# Check if port is in LISTEN state using ss
PORT_CHECK=$(ss -tuln 2>/dev/null | grep -E "(:${TARGET_PORT}[[:space:]]|:${TARGET_PORT}$)" || true)
if [ -z "$PORT_CHECK" ]; then
    echo "Checking port ${TARGET_PORT}... [FAIL] (Port not listening)"
    exit 1
fi
echo "Checking port ${TARGET_PORT}... [OK]"
echo ""

# --- 2. Firewall Status Check (Warning only) ---
check_firewall

# --- 3. Resource Monitoring ---
CPU_USAGE=$(get_cpu_usage)
MEM_USAGE=$(get_mem_usage)
DISK_USAGE=$(get_disk_usage)

echo "[RESOURCE MONITORING]"
echo "CPU Usage : ${CPU_USAGE}%"
echo "MEM Usage : ${MEM_USAGE}%"
echo "DISK Used  : ${DISK_USAGE}%"
echo ""

# --- 4. Threshold Warnings (Warning only) ---
# CPU > 20%
if awk "BEGIN {exit !($CPU_USAGE > $CPU_THRESHOLD)}"; then
    echo "[WARNING] CPU threshold exceeded (${CPU_USAGE}% > ${CPU_THRESHOLD}%)"
fi

# MEM > 10%
if awk "BEGIN {exit !($MEM_USAGE > $MEM_THRESHOLD)}"; then
    echo "[WARNING] Memory threshold exceeded (${MEM_USAGE}% > ${MEM_THRESHOLD}%)"
fi

# DISK > 80%
if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    echo "[WARNING] Disk threshold exceeded (${DISK_USAGE}% > ${DISK_THRESHOLD}%)"
fi
echo ""

# --- 5. Logging ---
# Perform log rotation if file exceeds 10MB
rotate_logs

CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")
LOG_LINE="[${CURRENT_TIME}] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}%"

# Append to log file
if echo "$LOG_LINE" >> "$LOG_FILE" 2>/dev/null; then
    LOG_SUCCESS=true
else
    # Fallback if standard permission denied (display warning)
    echo "[WARNING] Failed to write log to ${LOG_FILE}. Check file permissions!"
    LOG_SUCCESS=false
fi

# --- 6. Statistics Report ---
generate_statistics

if [ "$LOG_SUCCESS" = true ]; then
    echo "[INFO] Log appended: ${LOG_FILE}"
fi

exit 0

