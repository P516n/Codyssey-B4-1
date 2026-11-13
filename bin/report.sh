#!/usr/bin/env bash
# ==============================================================================
# Script Name : report.sh
# Description : Parses monitor.log and generates statistical reports
# Bonus Task 1: CPU/MEM/DISK average, min, max, sample count & time filtering
# Target OS   : Ubuntu 24.04 LTS (Bash 5.2+)
# Author      : agent-dev
# ==============================================================================

set -u

AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"

START_TIME=""
END_TIME=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --file PATH          Path to monitor.log (Default: ${LOG_FILE})"
    echo "  -s, --start \"DATETIME\"   Filter logs after this datetime (Format: YYYY-MM-DD HH:MM:SS)"
    echo "  -e, --end \"DATETIME\"     Filter logs before this datetime (Format: YYYY-MM-DD HH:MM:SS)"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Example:"
    echo "  $0"
    echo "  $0 -s \"2026-02-25 13:58:00\" -e \"2026-02-25 14:05:00\""
    exit 1
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            LOG_FILE="$2"
            shift 2
            ;;
        -s|--start)
            START_TIME="$2"
            shift 2
            ;;
        -e|--end)
            END_TIME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            # Positional fallback: $1 = START_TIME, $2 = END_TIME
            if [ -z "$START_TIME" ]; then
                START_TIME="$1"
                shift
            elif [ -z "$END_TIME" ]; then
                END_TIME="$1"
                shift
            else
                usage
            fi
            ;;
    esac
done

if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] Log file not found: ${LOG_FILE}" >&2
    exit 1
fi

if [ ! -s "$LOG_FILE" ]; then
    echo "[INFO] Log file is empty: ${LOG_FILE}"
    exit 0
fi

awk -v start="$START_TIME" -v end="$END_TIME" '
    BEGIN {
        cpu_sum = 0; mem_sum = 0; disk_sum = 0; count = 0;
        cpu_max = -1; cpu_min = 99999;
        mem_max = -1; mem_min = 99999;
        disk_max = -1; disk_min = 99999;
        cpu_max_time = ""; cpu_min_time = "";
        mem_max_time = ""; mem_min_time = "";
        disk_max_time = ""; disk_min_time = "";
    }
    {
        # Expected log format:
        # [YYYY-MM-DD HH:MM:SS] PID:XXXX CPU:XX.X% MEM:XX.X% DISK_USED:XX%
        match($0, /\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] PID:[0-9]+ CPU:([0-9.]+)% MEM:([0-9.]+)% DISK_USED:([0-9]+)%/, arr)
        
        if (arr[1] != "") {
            ts = arr[1]
            c = arr[2] + 0.0
            m = arr[3] + 0.0
            d = arr[4] + 0.0

            # Time range filter (lexicographical comparison works for ISO timestamps)
            if (start != "" && ts < start) next;
            if (end != "" && ts > end) next;

            cpu_sum += c
            mem_sum += m
            disk_sum += d
            count++

            if (c > cpu_max) { cpu_max = c; cpu_max_time = ts }
            if (c < cpu_min) { cpu_min = c; cpu_min_time = ts }
            if (m > mem_max) { mem_max = m; mem_max_time = ts }
            if (m < mem_min) { mem_min = m; mem_min_time = ts }
            if (d > disk_max) { disk_max = d; disk_max_time = ts }
            if (d < disk_min) { disk_min = d; disk_min_time = ts }
        }
    }
    END {
        if (count == 0) {
            print "====== STATISTICS REPORT ======"
            print "No matching log samples found within specified time range."
            exit 0
        }

        print "    ====== STATISTICS REPORT ======"
        print "      [CPU]"
        printf "        Average : %.1f%%\n", cpu_sum / count
        printf "        Maximum : %.1f%% at %s\n", cpu_max, cpu_max_time
        printf "        Minimum : %.1f%% at %s\n", cpu_min, cpu_min_time
        print "      [Memory]"
        printf "        Average : %.1f%%\n", mem_sum / count
        printf "        Maximum : %.1f%% at %s\n", mem_max, mem_max_time
        printf "        Minimum : %.1f%% at %s\n", mem_min, mem_min_time
        print "      [Disk (Root)]"
        printf "        Average : %.1f%%\n", disk_sum / count
        printf "        Maximum : %d%% at %s\n", disk_max, disk_max_time
        printf "        Minimum : %d%% at %s\n", disk_min, disk_min_time
        print "      [Samples]"
        printf "        Data Points: %d samples\n", count
    }
' "$LOG_FILE"

