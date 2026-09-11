#!/bin/bash
set -euo pipefail

INPUT_JSON=$(cat)

python3 - "$INPUT_JSON" << 'PYEOF'
import sys, json, os, re, time

data_str = sys.argv[1] if len(sys.argv) > 1 else "{}"
try:
    data = json.loads(data_str)
except Exception:
    data = {}

state = data.get("agent_state", "idle")
ctx = data.get("context_window", {})
used_pct = ctx.get("used_percentage", 0) or 0

vcs = data.get("vcs", {})
vcs_branch = vcs.get("branch", "")
vcs_dirty = vcs.get("dirty", False)

cwd = data.get("workspace", {}).get("current_dir") or data.get("cwd") or os.getcwd()
folder_name = os.path.basename(cwd) if cwd else "workspace"

model_info = data.get("model", {})
model_name = model_info.get("display_name", "")

quota = data.get("quota", {})
q5h = quota.get("gemini-5h") or quota.get("3p-5h") or {}
qwk = quota.get("gemini-weekly") or quota.get("3p-weekly") or {}

rem_5h = q5h.get("remaining_fraction", 1.0)
s5_pct = (1.0 - rem_5h) * 100.0 if rem_5h is not None else 0.0

rem_wk = qwk.get("remaining_fraction", 1.0)
swk_pct = (1.0 - rem_wk) * 100.0 if rem_wk is not None else 0.0

reset_wk = qwk.get("reset_in_seconds", 0) or 0

LAVENDER = "\033[38;2;198;160;246m"
PEACH = "\033[38;2;238;212;159m"
DIM = "\033[2;38;2;202;211;245m"
ORANGE = "\033[1;38;2;245;169;127m"
BLUE = "\033[38;2;138;173;244m"
GREEN = "\033[38;2;166;218;149m"
BRIGHT_GREEN = "\033[92;1m"
BRIGHT_YELLOW = "\033[93;1m"
BRIGHT_CYAN = "\033[96;1m"
BRIGHT_MAGENTA = "\033[95;1m"
WHITE = "\033[97;1m"
FRAME = "\033[97m"
RESET = "\033[0m"

if state in ["idle", "reviewing", "reviewing_changes"]:
    s_str = f"{BRIGHT_GREEN}● READY{RESET}"
elif state == "thinking":
    s_str = f"{BRIGHT_YELLOW}◆ THINKING{RESET}"
elif state == "working":
    s_str = f"{BRIGHT_CYAN}⚙ WORKING{RESET}"
elif state == "tool_use":
    s_str = f"{BRIGHT_MAGENTA}🔧 TOOL{RESET}"
else:
    s_str = f"{WHITE}⏳ {state.upper()}{RESET}"

def format_reset_date(sec):
    if not sec or sec <= 0:
        return "N/A"
    target_epoch = time.time() + sec
    try:
        return time.strftime("%a %b %d at %H:%M", time.localtime(target_epoch))
    except Exception:
        return "N/A"

fmt_reset_wk = format_reset_date(reset_wk)

def build_bar(pct, width=10):
    p = max(0, min(100, int(pct + 0.5)))
    filled = (p * width + 50) // 100
    empty = width - filled
    return "━" * filled + "─" * empty

bar_ctx = build_bar(used_pct, 15)
bar_5h = build_bar(s5_pct, 10)
bar_wk = build_bar(swk_pct, 10)

v_star = "*" if vcs_dirty else ""
vcs_str = f"{PEACH}:{vcs_branch}{v_star}{RESET}" if vcs_branch else ""
row1 = f"{s_str}{DIM} · {RESET}{LAVENDER}[{folder_name}]{RESET}{vcs_str}{DIM} · {RESET}{ORANGE}{model_name}{RESET}"

line_ctx = f"{BLUE}ctx {bar_ctx} {used_pct:.1f}%{RESET}"
line_5h = f"{GREEN}5h {bar_5h} {s5_pct:.1f}%{RESET}"
line_wk = f"{GREEN}weekly {bar_wk} {swk_pct:.1f}% (resets on {fmt_reset_wk}){RESET}" if fmt_reset_wk != "N/A" else f"{GREEN}weekly {bar_wk} {swk_pct:.1f}%{RESET}"
row2 = f"{line_ctx}{DIM} · {RESET}{line_5h}{DIM} · {RESET}{line_wk}"

def visible_len(s):
    ansi_escape = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return len(ansi_escape.sub("", s))

w1 = visible_len(row1)
w2 = visible_len(row2)
box_width = max(w1, w2) + 4

top_border = f"{FRAME}╭" + "─" * box_width + f"╮{RESET}"
bottom_border = f"{FRAME}╰" + "─" * box_width + f"╯{RESET}"

def make_boxed_line(content):
    vlen = visible_len(content)
    pad = box_width - vlen - 2
    return f"{FRAME}│{RESET} " + content + " " * pad + f"{FRAME}│{RESET}"

empty_line = f"{FRAME}│{RESET}" + " " * box_width + f"{FRAME}│{RESET}"

print(top_border)
print(make_boxed_line(row1))
print(empty_line)
print(make_boxed_line(row2))
print(bottom_border)
PYEOF
