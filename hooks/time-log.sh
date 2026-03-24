#!/usr/bin/env bash
# time-log.sh — Append a timestamped event to the persistent time log.
# Called by every hook (Tier 1 via time-inject.sh, Tier 2/3 directly).
#
# Usage: time-log.sh <EventName>
# Reads hook JSON from stdin, extracts session_id, writes one JSONL line.

set -euo pipefail

EVENT="${1:-unknown}"
LOG_DIR="${HOME}/.claude/hooks"
LOG_FILE="${LOG_DIR}/time_events.jsonl"
MAX_BYTES="${CLAUDE_TIME_LOG_MAX_BYTES:-524288}" # 500KB default

mkdir -p "$LOG_DIR"

# Read stdin (hook input JSON) — may be empty for some events
INPUT=""
if ! [ -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Extract session_id if available
SESSION_ID=""
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi

# Current timestamp — UTC ISO 8601, works on both GNU and BSD date
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build the log line (minimal JSON, no jq dependency for writing)
if [ -n "$SESSION_ID" ]; then
  echo "{\"ts\":\"${TS}\",\"event\":\"${EVENT}\",\"sid\":\"${SESSION_ID}\"}" >> "$LOG_FILE"
else
  echo "{\"ts\":\"${TS}\",\"event\":\"${EVENT}\"}" >> "$LOG_FILE"
fi

# Prune if log exceeds max size — keep the newest half
if [ -f "$LOG_FILE" ]; then
  FILE_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$FILE_SIZE" -gt "$MAX_BYTES" ]; then
    TOTAL_LINES=$(wc -l < "$LOG_FILE")
    KEEP=$((TOTAL_LINES / 2))
    tail -n "$KEEP" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
fi

exit 0
