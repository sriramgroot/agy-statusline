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
used_pct = ctx.get("used_percentage", 0) or 0.0
ctx_used = ctx.get("total_input_tokens", 0) or 0
ctx_total = ctx.get("context_window_size", 0) or 0

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
reset_5h = q5h.get("reset_in_seconds", 0) or 0

rem_wk = qwk.get("remaining_fraction", 1.0)
swk_pct = (1.0 - rem_wk) * 100.0 if rem_wk is not None else 0.0
reset_wk = qwk.get("reset_in_seconds", 0) or 0

# Colors (Vertical Vital Signs Palette)
CYAN = "\033[1;38;2;0;247;255m"
ORANGE = "\033[1;38;2;228;149;56m"
YELLOW = "\033[1;38;2;216;184;112m"
SAGE = "\033[1;38;2;156;192;159m"
DIM = "\033[1;2m"
GREEN = "\033[38;2;26;255;0m"
RED = "\033[38;2;255;0;0m"
WHITE = "\033[97;1m"
FRAME = "\033[97m"
RESET = "\033[0m"

# Format State Indicator
if state in ["idle", "reviewing", "reviewing_changes"]:
    s_str = f"{CYAN}● READY{RESET}"
elif state == "thinking":
    s_str = f"{YELLOW}◆ THINKING{RESET}"
elif state == "working":
    s_str = f"{CYAN}⚙ WORKING{RESET}"
elif state == "tool_use":
    s_str = f"{ORANGE}🔧 TOOL{RESET}"
else:
    s_str = f"{WHITE}⏳ {state.upper()}{RESET}"

def format_tokens(n):
    if n >= 1000000:
        return f"{n/1000000:.1f}M"
    elif n >= 1000:
        return f"{n/1000:.1f}K"
    return str(n)

def format_time_rel(sec):
    if not sec or sec <= 0:
        return "N/A"
    h = sec // 3600
    m = (sec % 3600) // 60
    if h > 24:
        d = h // 24
        return f"{d}d {h%24}h"
    elif h > 0:
        return f"{h}h {m}m"
    return f"{m}m"

def format_reset_date(sec):
    if not sec or sec <= 0:
        return "N/A"
    target_epoch = time.time() + sec
    try:
        return time.strftime("%a %b %d at %H:%M", time.localtime(target_epoch))
    except Exception:
        return "N/A"

def build_bar(pct, width=8):
    p = max(0, min(100, int(pct + 0.5)))
    filled = (p * width + 50) // 100
    empty = width - filled
    return "▰" * filled + "▱" * empty

bar_ctx = build_bar(used_pct, 10)
bar_5h = build_bar(s5_pct, 8)
bar_wk = build_bar(swk_pct, 8)

fmt_used = format_tokens(ctx_used)
fmt_total = format_tokens(ctx_total)
fmt_5h_rel = format_time_rel(reset_5h)
fmt_wk_date = format_reset_date(reset_wk)

# Line 1: State ~ Model ~ Project Title
line1 = f"{s_str} ~ {CYAN}{model_name}{RESET} ~ {DIM}{folder_name}{RESET}"
line2 = f"{ORANGE}cw {bar_ctx} {used_pct:.1f} % ~ {fmt_used} / {fmt_total}{RESET}"

# Combined single line for 5h and weekly quotas
part_5h = f"{YELLOW}5h {bar_5h} {s5_pct:.1f} % (in {fmt_5h_rel}){RESET}" if fmt_5h_rel != "N/A" else f"{YELLOW}5h {bar_5h} {s5_pct:.1f} %{RESET}"
part_wk = f"{SAGE}7d {bar_wk} {swk_pct:.1f} % (resets on {fmt_wk_date}){RESET}" if fmt_wk_date != "N/A" else f"{SAGE}7d {bar_wk} {swk_pct:.1f} %{RESET}"

line3 = f"{part_5h} ~ {part_wk}"

status_icon = f"{RED}✗{RESET}" if vcs_dirty else f"{GREEN}✓{RESET}"
vcs_part = vcs_branch if vcs_branch else "no-vcs"
line4 = f"{DIM}{vcs_part}{RESET} {status_icon}"

lines = [line1, line2, line3, line4]

def visible_len(s):
    ansi_escape = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return len(ansi_escape.sub("", s))

max_w = max(visible_len(l) for l in lines) + 4

top_border = f"{FRAME}╭" + "─" * max_w + f"╮{RESET}"
bottom_border = f"{FRAME}╰" + "─" * max_w + f"╯{RESET}"

def make_boxed_line(content):
    vlen = visible_len(content)
    pad = max_w - vlen - 2
    return f"{FRAME}│{RESET} " + content + " " * pad + f"{FRAME}│{RESET}"

print(top_border)
for l in lines:
    print(make_boxed_line(l))
print(bottom_border)

PYEOF
