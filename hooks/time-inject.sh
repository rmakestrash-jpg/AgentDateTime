#!/usr/bin/env bash
# time-inject.sh — Log event AND inject time context into Claude's conversation.
# Called by Tier 1 hooks (UserPromptSubmit, PreToolUse, PostToolUse,
# SessionStart, SubagentStart, PostToolUseFailure).
#
# Usage: time-inject.sh <EventName>
# Reads hook JSON from stdin, logs it, then outputs context for Claude.
#
# Output method varies by event:
#   SessionStart, UserPromptSubmit → plain stdout (Claude sees it directly)
#   PreToolUse, PostToolUse, SubagentStart, PostToolUseFailure → JSON with additionalContext

set -euo pipefail

EVENT="${1:-unknown}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${HOME}/.claude/hooks/time_events.jsonl"

# Capture stdin before it's consumed
INPUT=""
if ! [ -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Current timestamp — captured BEFORE logging so gap calculations
# reference the previous event, not the one we're about to write.
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Local time with offset (for human context)
# Works on GNU (Linux) and BSD (macOS)
if date --version &>/dev/null 2>&1; then
  # GNU date
  LOCAL_TIME=$(date +"%a %l:%M %p %Z (UTC%:z)" | tr -s ' ')
else
  # BSD date (macOS)
  LOCAL_TIME=$(date +"%a %l:%M %p %Z (UTC%z)" | tr -s ' ')
fi

# ─── Helper: compute duration string from two ISO timestamps ───
duration_between() {
  local start_ts="$1" end_ts="$2"
  
  # Convert to epoch seconds — handle both GNU and BSD date
  local start_epoch end_epoch
  if date --version &>/dev/null 2>&1; then
    start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || echo 0)
    end_epoch=$(date -d "$end_ts" +%s 2>/dev/null || echo 0)
  else
    start_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$start_ts" +%s 2>/dev/null || echo 0)
    end_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$end_ts" +%s 2>/dev/null || echo 0)
  fi
  
  local diff=$(( end_epoch - start_epoch ))
  if [ "$diff" -lt 0 ]; then diff=0; fi
  
  if [ "$diff" -lt 60 ]; then
    echo "${diff}s"
  elif [ "$diff" -lt 3600 ]; then
    echo "$(( diff / 60 ))m $(( diff % 60 ))s"
  elif [ "$diff" -lt 86400 ]; then
    echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m"
  else
    echo "$(( diff / 86400 ))d $(( (diff % 86400) / 3600 ))h"
  fi
}

# ─── Helper: get the last log entry matching an event ───
last_event_ts() {
  local event_name="$1"
  if [ -f "$LOG_FILE" ] && command -v jq &>/dev/null; then
    grep "\"event\":\"${event_name}\"" "$LOG_FILE" 2>/dev/null | tail -1 | jq -r '.ts // empty' 2>/dev/null || true
  fi
}

# ─── Helper: count events since a timestamp ───
count_events_since() {
  local since_ts="$1" event_name="${2:-}"
  if [ ! -f "$LOG_FILE" ] || ! command -v jq &>/dev/null; then
    echo 0
    return
  fi
  if [ -n "$event_name" ]; then
    jq -r "select(.ts > \"${since_ts}\" and .event == \"${event_name}\") | .ts" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' '
  else
    jq -r "select(.ts > \"${since_ts}\") | .ts" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' '
  fi
}

# ─── Build context based on event type ───

case "$EVENT" in

  SessionStart)
    # Full orientation — gap since last session, history
    CONTEXT="[TIME AWARENESS] Session started: ${TS} (${LOCAL_TIME})"
    
    LAST_END=$(last_event_ts "SessionEnd")
    if [ -n "$LAST_END" ]; then
      GAP=$(duration_between "$LAST_END" "$TS")
      CONTEXT="${CONTEXT}\nLast session ended: ${LAST_END} (${GAP} ago)"
    fi
    
    LAST_COMPACT=$(last_event_ts "PostCompact")
    if [ -n "$LAST_COMPACT" ]; then
      CONTEXT="${CONTEXT}\nLast compaction: ${LAST_COMPACT}"
    fi
    
    # Output as plain stdout (SessionStart stdout → Claude's context)
    echo -e "$CONTEXT"
    ;;

  UserPromptSubmit)
    # One-line timestamp with gap since last prompt
    LAST_PROMPT=$(last_event_ts "UserPromptSubmit")
    
    LINE="[TIME] ${TS} (${LOCAL_TIME})"
    
    if [ -n "$LAST_PROMPT" ]; then
      GAP=$(duration_between "$LAST_PROMPT" "$TS")
      LINE="${LINE} | since last prompt: ${GAP}"
      
      # Count tool calls since last prompt for activity summary
      TOOL_COUNT=$(count_events_since "$LAST_PROMPT" "PreToolUse")
      FAIL_COUNT=$(count_events_since "$LAST_PROMPT" "PostToolUseFailure")
      if [ "$TOOL_COUNT" -gt 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
        LINE="${LINE} | tools: ${TOOL_COUNT}"
        if [ "$FAIL_COUNT" -gt 0 ]; then
          LINE="${LINE} (${FAIL_COUNT} failed)"
        fi
      fi
    fi
    
    # Check for notable events since last prompt
    COMPACT_COUNT=$(count_events_since "${LAST_PROMPT:-$TS}" "PostCompact")
    if [ "$COMPACT_COUNT" -gt 0 ]; then
      LINE="${LINE} | ⚠ context was compacted"
    fi
    
    # Output as plain stdout (UserPromptSubmit stdout → Claude's context)
    echo "$LINE"
    ;;

  PreToolUse)
    # Minimal — just a timestamp, fires very frequently
    # Output as JSON with additionalContext
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[TIME] ${TS}","permissionDecision":"allow"}}
EOF
    ;;

  PostToolUse)
    # Timestamp after tool completion — pairs with PreToolUse for duration
    LAST_PRE=$(last_event_ts "PreToolUse")
    ADDON="[TIME] ${TS}"
    if [ -n "$LAST_PRE" ]; then
      DUR=$(duration_between "$LAST_PRE" "$TS")
      ADDON="${ADDON} (tool took ${DUR})"
    fi
    
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"${ADDON}"}}
EOF
    ;;

  SubagentStart)
    # Mark when subagent began
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"[TIME] ${TS} subagent spawned"}}
EOF
    ;;

  PostToolUseFailure)
    # Timestamp on failure
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"[TIME] ${TS} tool failure"}}
EOF
    ;;

  *)
    # Unknown event passed to inject — just log, no output
    ;;
esac

# Log the event AFTER reading the log for gap calculations
echo "$INPUT" | "$SCRIPT_DIR/time-log.sh" "$EVENT"

exit 0
