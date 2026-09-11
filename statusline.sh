#!/bin/bash
set -euo pipefail

# ─── ANSI Helpers (Standard 16-color palette) ────────────────────────────────
R="\033[0m" B="\033[1m" I="\033[3m"
FG_WHITE="\033[97m"
FG_BRIGHT_RED="\033[91m"
FG_BRIGHT_YELLOW="\033[93m"
FG_BRIGHT_GREEN="\033[92m"
FG_BRIGHT_CYAN="\033[96m"
FG_BRIGHT_MAGENTA="\033[95m"
NUM_COLOR="${FG_WHITE}${B}"

# ─── Utility Functions ───────────────────────────────────────────────────────
function format_num() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n / 1000000
    else if (n >= 1000) printf "%.1fK", n / 1000
    else print n
  }'
}

function format_reset_date() {
  local sec=$1
  if [ -z "$sec" ] || [ "$sec" = "0" ] || [ "$sec" = "null" ]; then
    echo "N/A"
    return
  fi
  local target_epoch=$(($(date +%s) + sec))
  if date -r 0 >/dev/null 2>&1; then
    # BSD date (macOS)
    date -r "$target_epoch" "+%a %b %d at %H:%M"
  else
    # GNU date (Linux)
    date -d "@$target_epoch" "+%a %b %d at %H:%M" 2>/dev/null || date -u -d "@$target_epoch" "+%a %b %d at %H:%M"
  fi
}

function format_time() {
  local sec=$1
  if [ -z "$sec" ] || [ "$sec" = "0" ] || [ "$sec" = "null" ]; then
    echo "N/A"
    return
  fi
  local h=$((sec / 3600))
  local m=$(((sec % 3600) / 60))
  if [ "$h" -gt 24 ]; then
    local d=$((h / 24))
    h=$((h % 24))
    echo "${d}d ${h}h"
  elif [ "$h" -gt 0 ]; then
    echo "${h}h ${m}m"
  else
    echo "${m}m"
  fi
}

function build_bar() {
  local pct=$1
  local bar_len=${2:-15}
  
  local filled=$((pct * bar_len / 100))
  local remainder=$(( (pct * bar_len) % 100 ))
  local bar_color="$FG_WHITE"
  [ "$pct" -ge 60 ] && bar_color="$FG_BRIGHT_YELLOW"
  [ "$pct" -ge 90 ] && bar_color="$FG_BRIGHT_RED"

  local bar=""
  for ((i = 0; i < bar_len; i++)); do
    if [ "$i" -lt "$filled" ]; then bar="${bar}█"
    elif [ "$i" -eq "$filled" ]; then
      [ "$remainder" -ge 75 ] && bar="${bar}▓" || { [ "$remainder" -ge 50 ] && bar="${bar}▒" || { [ "$remainder" -ge 25 ] && bar="${bar}░" || bar="${bar}·"; }; }
    else bar="${bar}·"; fi
  done
  echo "${bar_color}${bar}${R}"
}

# ─── Parse JSON from stdin (Single jq pass) ─────────────────────────────────
{
  read -r STATE
  read -r USED_PCT
  read -r CTX_USED
  read -r CTX_TOTAL
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r SANDBOX
  read -r ARTIFACTS
  read -r SUBAGENTS
  read -r BG_TASKS
  read -r MODEL
  read -r COLS
  read -r SESS_5HR
  read -r SESS_WEEKLY
  read -r RESET_5H
  read -r RESET_WK
} <<< "$(
  jq -r '
    (.agent_state // "idle"),
    (.context_window.used_percentage // 0),
    (.context_window.total_input_tokens // 0),
    (.context_window.context_window_size // 0),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.sandbox.enabled // false),
    (.artifact_count // 0),
    (if .subagents | type == "array" then (.subagents | length) else 0 end),
    (.task_count // 0),
    (.model.display_name // ""),
    (.terminal_width // 80),
    ((1 - (.quota["gemini-5h"].remaining_fraction // .quota["3p-5h"].remaining_fraction // 1)) * 100),
    ((1 - (.quota["gemini-weekly"].remaining_fraction // .quota["3p-weekly"].remaining_fraction // 1)) * 100),
    (.quota["gemini-5h"].reset_in_seconds // .quota["3p-5h"].reset_in_seconds // 0),
    (.quota["gemini-weekly"].reset_in_seconds // .quota["3p-weekly"].reset_in_seconds // 0)
  ' 2>/dev/null || printf "idle\n0\n0\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n0\n0\n0\n0\n"
)"

# ─── Computed Values ─────────────────────────────────────────────────────────
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")

# Extract integer percentages for the progress bars
PCT_INT=${USED_PCT%.*}; PCT_INT=${PCT_INT:-0}
S5_INT=${SESS_5HR%.*}; S5_INT=${S5_INT:-0}
SW_INT=${SESS_WEEKLY%.*}; SW_INT=${SW_INT:-0}

S5_FMT=$(LC_NUMERIC=C printf "%.1f" "$SESS_5HR")
SW_FMT=$(LC_NUMERIC=C printf "%.1f" "$SESS_WEEKLY")

# Format Context Tokens (e.g. 5.2K / 128.0K)
FMT_USED=$(format_num "$CTX_USED")
FMT_TOTAL=$(format_num "$CTX_TOTAL")

# Format Reset Times
FMT_RESET_5H=$(format_time "$RESET_5H")
FMT_RESET_WK=$(format_reset_date "$RESET_WK")

# ─── State Indicator ─────────────────────────────────────────────────────────
case "$STATE" in
  idle) S="${FG_BRIGHT_GREEN}${B}● READY${R}" ;;
  thinking) S="${FG_BRIGHT_YELLOW}${B}◆ THINKING${R}" ;;
  working) S="${FG_BRIGHT_CYAN}${B}⚙ WORKING${R}" ;;
  tool_use) S="${FG_BRIGHT_MAGENTA}${B}🔧 TOOL${R}" ;;
  *) S="${FG_WHITE}${B}⏳ $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
esac

# ─── VCS & Model ─────────────────────────────────────────────────────────────
V=""
if [ -n "$VCS_BRANCH" ]; then
  [ "$VCS_DIRTY" = "true" ] && V="${FG_WHITE} ╱ ${VCS_BRANCH}*" || V="${FG_WHITE} ╱ ${VCS_BRANCH}"
fi
M=""
[ -n "$MODEL" ] && M="${FG_WHITE} ╱ ${FG_BRIGHT_MAGENTA}${I}${MODEL}${R}"

# ─── Generate Progress Bars ──────────────────────────────────────────────────
BAR_CTX=$(build_bar "$PCT_INT" 15)
BAR_5H=$(build_bar "$S5_INT" 15)
BAR_WK=$(build_bar "$SW_INT" 15)

# ─── Format Lines ────────────────────────────────────────────────────────────
ART_FMT="${FG_WHITE}artifacts ${NUM_COLOR}${ARTIFACTS}${R}"

LINE1="${S}${M}${V}"

# Ensure right-padding on labels so the progress bars align nicely
CTX_LABEL=$(printf "%-13s" "ctx ${FMT_USED}/${FMT_TOTAL}")
LINE_CTX=" ${FG_WHITE}${CTX_LABEL}${R} ${BAR_CTX} ${NUM_COLOR}${PCT_FMT}%${R}"
LINE_5H=" ${FG_WHITE}5h quota     ${R} ${BAR_5H} ${NUM_COLOR}${S5_FMT}%${R} ${FG_WHITE}(resets in ${FMT_RESET_5H})${R}"
if [ "$FMT_RESET_WK" = "N/A" ]; then
  LINE_WK=" ${FG_WHITE}weekly quota ${R} ${BAR_WK} ${NUM_COLOR}${SW_FMT}%${R} ${FG_WHITE}(resets N/A)${R}"
else
  LINE_WK=" ${FG_WHITE}weekly quota ${R} ${BAR_WK} ${NUM_COLOR}${SW_FMT}%${R} ${FG_WHITE}(resets on ${FMT_RESET_WK})${R}"
fi
LINE_ART=" ${ART_FMT}"

# ─── Render Output ───────────────────────────────────────────────────────────
echo -e "${FG_WHITE}╭─${R} ${LINE1}"
echo -e "${FG_WHITE}│${R}"
echo -e "${FG_WHITE}├─${R}${LINE_CTX}"
echo -e "${FG_WHITE}│${R}"
echo -e "${FG_WHITE}├─${R}${LINE_5H}"
echo -e "${FG_WHITE}│${R}"
echo -e "${FG_WHITE}├─${R}${LINE_WK}"
echo -e "${FG_WHITE}│${R}"
echo -e "${FG_WHITE}╰─${R}${LINE_ART}"
