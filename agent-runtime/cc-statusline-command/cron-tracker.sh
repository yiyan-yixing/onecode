#!/bin/bash
# Tracks session-only cron task changes (CronCreate/CronDelete) to cron-session.json
# so the gateway UI can display them alongside durable tasks.
# Receives PostToolUse event JSON on stdin.

SESSION_FILE="/home/work/.claude/cron-session.json"
LOCK_FILE="/home/work/.claude/cron-session.json.lock"

# Read stdin (PostToolUse event)
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // .toolName // ""' 2>/dev/null)

# Only handle cron-related tools
if [ "$TOOL" != "CronCreate" ] && [ "$TOOL" != "CronDelete" ]; then
  exit 0
fi

# Acquire lock
exec 9>"$LOCK_FILE"
flock -w 2 9 || exit 0

# Initialize file if missing
if [ ! -f "$SESSION_FILE" ]; then
  echo '[]' > "$SESSION_FILE"
fi

if [ "$TOOL" = "CronCreate" ]; then
  # Extract cron fields from tool input
  CRON=$(echo "$INPUT" | jq -r '.tool_input.cron // ""' 2>/dev/null)
  PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null)
  RECURRING=$(echo "$INPUT" | jq -r '.tool_input.recurring // true' 2>/dev/null)
  JOB_ID=$(echo "$INPUT" | jq -r '.tool_result // .result // ""' 2>/dev/null | head -1)

  if [ -z "$CRON" ]; then
    exit 0
  fi

  # Build new task entry
  NAME=$(echo "$PROMPT" | head -c 60)
  ENTRY=$(jq -n \
    --arg cron "$CRON" \
    --arg name "$NAME" \
    --arg prompt "$PROMPT" \
    --argjson recurring "$RECURRING" \
    --arg id "$JOB_ID" \
    '{cron:$cron, name:$name, prompt:$prompt, recurring:$recurring, id:$id, sessionOnly:true}')

  # Append to array (deduplicate by cron+prompt)
  jq --argjson entry "$ENTRY" '
    del(.[] | select(.cron == $entry.cron and .prompt == $entry.prompt)) + [$entry]
  ' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

elif [ "$TOOL" = "CronDelete" ]; then
  JOB_ID=$(echo "$INPUT" | jq -r '.tool_input.id // ""' 2>/dev/null)

  if [ -n "$JOB_ID" ]; then
    # Remove by id
    jq --arg id "$JOB_ID" 'del(.[] | select(.id == $id))' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  fi
fi

# Release lock
flock -u 9
