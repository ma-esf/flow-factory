#!/usr/bin/env bash
#
# The Claude Code status line: model, effort, context used, branch.
#
#   Opus 5 · high · 8% 84k/1M · main*
#
# Claude Code runs this once per refresh, hands it the session as JSON on
# stdin and renders whatever it prints. Settings point at it with:
#
#   "statusLine": { "type": "command", "command": "~/.flow-factory/statusline.sh" }
#
# It is not a skill and reads no project settings. A status line that stopped
# to look for flow-factory.toml would be blank in every repository the factory
# is not installed in, which is most of the ones a session opens.

set -uo pipefail

input=$(cat)

# ---------------------------------------------------------------------------
# Reading the session JSON
#
# Two readers, because neither tool is on a stock macOS. jq is a Homebrew
# install; python3 arrives with the Xcode command line tools, which anyone
# using this already has, because that is where their git came from. Trying
# both makes the status line work on a machine that has either, and a status
# line is not worth making anybody install a JSON parser for.
#
# Both emit the same shell assignments, already quoted, so a display name with
# a space in it cannot split into two words or run as a command.
#
# The field names come from the status JSON Claude Code sends. effort is absent
# for a model that has no effort levels, and context_window is absent before
# the first request of a session, so both are read with a default and the
# segment is dropped rather than printed empty.
# ---------------------------------------------------------------------------
read_with_jq() {
    printf '%s' "$input" | jq -r '
      @sh "model=\(.model.display_name // .model.id // "")",
      @sh "effort=\(.effort.level // "")",
      @sh "pct=\(.context_window.used_percentage // "")",
      @sh "used=\(.context_window.total_input_tokens // 0)",
      @sh "window=\(.context_window.context_window_size // 0)",
      @sh "cwd=\(.workspace.current_dir // .cwd // "")"
    '
}

read_with_python() {
    printf '%s' "$input" | python3 -c '
import json, shlex, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
def g(*path, default=""):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return default if cur is None else cur
out = {
    "model":  g("model", "display_name") or g("model", "id"),
    "effort": g("effort", "level"),
    "pct":    g("context_window", "used_percentage"),
    "used":   g("context_window", "total_input_tokens", default=0),
    "window": g("context_window", "context_window_size", default=0),
    "cwd":    g("workspace", "current_dir") or g("cwd"),
}
for k, v in out.items():
    print("%s=%s" % (k, shlex.quote(str(v))))
'
}

model=""; effort=""; pct=""; used=0; window=0; cwd=""

if command -v jq >/dev/null 2>&1; then
    fields=$(read_with_jq 2>/dev/null) || fields=""
elif command -v python3 >/dev/null 2>&1; then
    fields=$(read_with_python 2>/dev/null) || fields=""
else
    fields=""
fi
[ -n "$fields" ] && eval "$fields"

# ---------------------------------------------------------------------------
# Colour
#
# On unless NO_COLOR is set. Not gated on whether stdout is a terminal, which
# is the obvious check and the wrong one: Claude Code captures this script's
# output into a string and draws it itself, so stdout is a pipe on every real
# run. A tty check leaves the status line correct under manual testing and
# colourless in the product.
# ---------------------------------------------------------------------------
if [ -n "${NO_COLOR:-}" ]; then
    DIM=""; OFF=""; CYAN=""; MAGENTA=""; GREEN=""; YELLOW=""; RED=""
else
    DIM=$'\033[2m';  OFF=$'\033[0m'
    CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'
fi

segments=()

[ -n "$model" ]  && segments+=("${CYAN}${model}${OFF}")
[ -n "$effort" ] && segments+=("${MAGENTA}${effort}${OFF}")

# ---------------------------------------------------------------------------
# Context used
#
# The percentage is what the eye wants and the token counts are what answers
# "how much room is left", so both are printed and the counts are dimmed.
#
# Rounded with printf rather than bash arithmetic, which cannot divide the
# float the session sends. The comparisons that follow are integer, on the
# rounded value.
# ---------------------------------------------------------------------------
if [ -n "$pct" ]; then
    rounded=$(printf '%.0f' "$pct" 2>/dev/null) || rounded=""
fi
if [ -n "${rounded:-}" ]; then
    if   [ "$rounded" -ge 90 ]; then level=$RED
    elif [ "$rounded" -ge 70 ]; then level=$YELLOW
    else                             level=$GREEN
    fi
    if [ "$window" -gt 0 ]; then
        # Half a thousand added before the divide, so 84_600 reads 85k and not
        # 84k. Integer division truncates; every other rounding here is to the
        # nearest.
        k=$(( (used + 500) / 1000 ))
        if [ "$window" -ge 1000000 ]; then
            size="$(( window / 1000000 ))M"
        else
            size="$(( window / 1000 ))k"
        fi
        segments+=("${level}${rounded}%${OFF}${DIM} ${k}k/${size}${OFF}")
    else
        segments+=("${level}${rounded}%${OFF}")
    fi
fi

# ---------------------------------------------------------------------------
# Branch
#
# Not in the session JSON, which carries a branch only for a worktree, so it is
# read from the repository the session is in. A detached HEAD is named as one
# rather than left blank, because a blank segment reads as "no repository" and
# a detached HEAD during a rebase or a bisect is exactly when the status line
# is worth looking at.
#
# The dirty mark is one character and costs a second git call. It stops at the
# first line: whether anything differs is the question, not how much.
# ---------------------------------------------------------------------------
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [ -z "$branch" ]; then
        head=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
        [ -n "$head" ] && branch="detached@$head"
    fi
    if [ -n "$branch" ]; then
        dirty=""
        [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null | head -n 1)" ] && dirty="*"
        segments+=("${YELLOW}${branch}${dirty}${OFF}")
    fi
fi

# Nothing to say. Printing an empty line is right: Claude Code keeps the last
# text it was given, so a status line that prints nothing on a bad read would
# leave a stale model and branch on screen.
if [ ${#segments[@]} -eq 0 ]; then
    printf '\n'
    exit 0
fi

separator=""
for segment in "${segments[@]}"; do
    printf '%s%s' "$separator" "$segment"
    separator="${DIM} · ${OFF}"
done
printf '\n'
