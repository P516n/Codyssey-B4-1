#!/usr/bin/env bash
# ==============================================================================
# Script Name : cleanup_archive.sh
# Description : Time-based log retention policy (compression, archive, deletion)
# Bonus Task 2:
#   - Compress *.log older than 7 days in /var/log/agent-app/
#   - Move compressed logs to /var/log/monitor/agent-app/archive/
#   - Delete archives (*.gz) older than 30 days in archive directory
#   - Safe error handling: Missing directories, permissions, zero target files
# Target OS   : Ubuntu 24.04 LTS (Bash 5.2+)
# Author      : agent-dev
# ==============================================================================

set -u

# --- Directory Paths ---
SRC_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"

CURRENT_LOG_NAME="monitor.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting log archive & retention task..."

# 1. Validate Source Directory
if [ ! -d "$SRC_LOG_DIR" ]; then
    echo "[WARNING] Source log directory does not exist: ${SRC_LOG_DIR}. Exiting safely."
    exit 0
fi

# Check Read/Write Permission on Source Directory
if [ ! -r "$SRC_LOG_DIR" ] || [ ! -w "$SRC_LOG_DIR" ]; then
    echo "[ERROR] Insufficient permissions on source directory: ${SRC_LOG_DIR}" >&2
    exit 1
fi

# 2. Ensure Archive Directory Exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "[INFO] Archive directory not found. Creating: ${ARCHIVE_DIR}"
    mkdir -p "$ARCHIVE_DIR" 2>/dev/null || {
        echo "[ERROR] Failed to create archive directory: ${ARCHIVE_DIR}" >&2
        exit 1
    }
fi

if [ ! -w "$ARCHIVE_DIR" ]; then
    echo "[ERROR] Archive directory is not writable: ${ARCHIVE_DIR}" >&2
    exit 1
fi

# 3. Step 1: Find and Compress logs older than 7 days
# Note: Exclude the active log file (monitor.log) from being compressed directly if it is currently written to.
echo "[STEP 1] Checking for logs older than 7 days in ${SRC_LOG_DIR}..."

COMPRESSED_COUNT=0
# Find files matching *.log or *.log.* older than 7 days, excluding active monitor.log
while IFS= read -r -d '' logfile; do
    filename=$(basename "$logfile")
    
    # Skip the active log file itself to avoid corruption
    if [ "$filename" = "$CURRENT_LOG_NAME" ]; then
        continue
    fi

    echo "  -> Compressing: ${filename} ..."
    if gzip -c "$logfile" > "${ARCHIVE_DIR}/${filename}-$(date +%Y%m%d%H%M%S).gz" 2>/dev/null; then
        rm -f "$logfile"
        COMPRESSED_COUNT=$((COMPRESSED_COUNT + 1))
    else
        echo "  [WARNING] Failed to compress and move: ${logfile}" >&2
    fi
done < <(find "$SRC_LOG_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.log.*" \) -mtime +7 -print0 2>/dev/null)

if [ "$COMPRESSED_COUNT" -eq 0 ]; then
    echo "[INFO] No log files older than 7 days found to compress."
else
    echo "[INFO] Successfully archived ${COMPRESSED_COUNT} file(s) to ${ARCHIVE_DIR}."
fi

# 4. Step 2: Delete archives older than 30 days
echo "[STEP 2] Checking for archives older than 30 days in ${ARCHIVE_DIR}..."

DELETED_COUNT=0
while IFS= read -r -d '' archivefile; do
    echo "  -> Deleting expired archive: $(basename "$archivefile")"
    if rm -f "$archivefile" 2>/dev/null; then
        DELETED_COUNT=$((DELETED_COUNT + 1))
    else
        echo "  [WARNING] Failed to delete archive: ${archivefile}" >&2
    fi
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.gz" -mtime +30 -print0 2>/dev/null)

if [ "$DELETED_COUNT" -eq 0 ]; then
    echo "[INFO] No archive files older than 30 days found to delete."
else
    echo "[INFO] Successfully deleted ${DELETED_COUNT} expired archive file(s)."
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log retention task completed successfully."
exit 0

