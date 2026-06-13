#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '
  .context_window |
  if .used_percentage != null then (.used_percentage | floor)
  elif .percent_used != null then (.percent_used | floor)
  elif (.used_tokens != null and .total_tokens != null and .total_tokens > 0) then
    ((.used_tokens / .total_tokens * 100) | floor)
  else 0
  end
' 2>/dev/null)
PCT=${PCT:-0}
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
BAR=""; for ((i=0; i<FILLED; i++)); do BAR="${BAR}█"; done
for ((i=0; i<EMPTY; i++)); do BAR="${BAR}░"; done

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

# Git branch, staged/modified counts, and clickable repo link
BRANCH=""
GIT_STATUS=""
REPO_LINK="${DIR##*/}"
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=" | $(git branch --show-current 2>/dev/null)"
    STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    [ "$STAGED" -gt 0 ] && GIT_STATUS=" ${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_STATUS="${GIT_STATUS} ${YELLOW}~${MODIFIED}${RESET}"

    REMOTE=$(git remote get-url origin 2>/dev/null | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
    if [ -n "$REMOTE" ]; then
        REPO_NAME=$(basename "$REMOTE")
        REPO_LINK=$(printf '%b' "\e]8;;${REMOTE}\a${REPO_NAME}\e]8;;\a")
    fi
fi

# Line 1: model, repo link, git branch, git status
echo -e "${CYAN}[$MODEL]${RESET} ${REPO_LINK}${BRANCH}${GIT_STATUS}"
# Line 2: context bar, cost, duration
COST_FMT=$(printf '$%.2f' "$COST")
echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET} | ${MINS}m ${SECS}s"