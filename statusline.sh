#!/bin/bash
set -euo pipefail

# ─── Catppuccin Macchiato Color Palette ──────────────────────────────────────
LAVENDER="\033[38;2;198;160;246m"
PEACH="\033[38;2;238;212;159m"
DIM="\033[2;38;2;202;211;245m"
ORANGE="\033[1;38;2;245;169;127m"
BLUE="\033[38;2;138;173;244m"
GREEN="\033[38;2;166;218;149m"
RESET="\033[0m"

# ─── Utility Functions ───────────────────────────────────────────────────────
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

function build_bar() {
  local pct=$1
  local bar_len=${2:-15}
  
  local p=${pct%.*}
  p=${p:-0}
  [ "$p" -lt 0 ] && p=0
  [ "$p" -gt 100 ] && p=100
  
  local filled=$(( (p * bar_len + 50) / 100 ))
  local empty=$((bar_len - filled))
  
  local bar=""
  for ((i = 0; i < filled; i++)); do bar="${bar}━"; done
  for ((i = 0; i < empty; i++)); do bar="${bar}─"; done
  echo "$bar"
}

# ─── Parse JSON from stdin ─────────────────────────────────────────────────
{
  read -r STATE
  read -r USED_PCT
  read -r CTX_USED
  read -r CTX_TOTAL
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r CWD
  read -r MODEL
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
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    ((1 - (.quota["gemini-5h"].remaining_fraction // .quota["3p-5h"].remaining_fraction // 1)) * 100),
    ((1 - (.quota["gemini-weekly"].remaining_fraction // .quota["3p-weekly"].remaining_fraction // 1)) * 100),
    (.quota["gemini-5h"].reset_in_seconds // .quota["3p-5h"].reset_in_seconds // 0),
    (.quota["gemini-weekly"].reset_in_seconds // .quota["3p-weekly"].reset_in_seconds // 0)
  ' 2>/dev/null || printf "idle\n0\n0\n0\n\nfalse\n\n\n0\n0\n0\n0\n"
)"

# ─── Computed Values ─────────────────────────────────────────────────────────
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")
S5_FMT=$(LC_NUMERIC=C printf "%.1f" "$SESS_5HR")
SW_FMT=$(LC_NUMERIC=C printf "%.1f" "$SESS_WEEKLY")

PCT_INT=${USED_PCT%.*}; PCT_INT=${PCT_INT:-0}
S5_INT=${SESS_5HR%.*}; S5_INT=${S5_INT:-0}
SW_INT=${SESS_WEEKLY%.*}; SW_INT=${SW_INT:-0}

# Folder Basename
DIR_NAME=""
if [ -n "$CWD" ]; then
  DIR_NAME=$(basename "$CWD")
else
  DIR_NAME=$(basename "$(pwd)")
fi

# Format Reset Date
FMT_RESET_WK=$(format_reset_date "$RESET_WK")

# ─── Generate Progress Bars ──────────────────────────────────────────────────
BAR_CTX=$(build_bar "$PCT_INT" 15)
BAR_5H=$(build_bar "$S5_INT" 10)
BAR_WK=$(build_bar "$SW_INT" 10)

# ─── Build Line 1: [folder]:branch · model ──────────────────────────────────
VCS_STR=""
if [ -n "$VCS_BRANCH" ]; then
  [ "$VCS_DIRTY" = "true" ] && VCS_STR="${PEACH}:${VCS_BRANCH}*${RESET}" || VCS_STR="${PEACH}:${VCS_BRANCH}${RESET}"
fi

LINE1="${LAVENDER}[${DIR_NAME}]${RESET}${VCS_STR}${DIM} · ${RESET}${ORANGE}${MODEL}${RESET}"

# ─── Build Line 2: ctx ... · 5h ... · weekly ... ─────────────────────────────
LINE_CTX="${BLUE}ctx ${BAR_CTX} ${PCT_FMT}%${RESET}"
LINE_5H="${GREEN}5h ${BAR_5H} ${S5_FMT}%${RESET}"

if [ "$FMT_RESET_WK" = "N/A" ]; then
  LINE_WK="${GREEN}weekly ${BAR_WK} ${SW_FMT}%${RESET}"
else
  LINE_WK="${GREEN}weekly ${BAR_WK} ${SW_FMT}% (resets on ${FMT_RESET_WK})${RESET}"
fi

LINE2="${LINE_CTX}${DIM} · ${RESET}${LINE_5H}${DIM} · ${RESET}${LINE_WK}"

# ─── Render Output ───────────────────────────────────────────────────────────
echo -e "${LINE1}"
echo -e "${LINE2}"
