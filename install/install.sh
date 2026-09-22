#!/usr/bin/env bash
#
# Flow Factory installer.
#
#   ./install/install.sh <project-root>     install on this Mac and into a project
#   ./install/install.sh --machine          install on this Mac only
#   ./install/install.sh --help
#
# Three sections, each announced as it starts:
#
#   1/3  This machine    skills, contracts, templates and the status line,
#                        once per machine. Re-running refreshes them.
#   2/3  Your project    a few questions about how the project works, then
#                        flow-factory.toml and .flow/ at its root.
#   3/3  Check           every file an installed skill refers to exists.
#
# Nothing is written to the project until the answers are shown and
# confirmed, so quitting at any question leaves the project as it was. The
# machine half has no questions and is safe to repeat.
#
# Answers may arrive from a pipe as well as a keyboard, one per line, which is
# how the installer is tested. Runs on the bash macOS ships (3.2).

set -euo pipefail

FACTORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/ui.sh
. "$FACTORY_ROOT/install/lib/ui.sh"
# shellcheck source=lib/settings.sh
. "$FACTORY_ROOT/install/lib/settings.sh"

# An unmatched glob must expand to nothing, not to itself. A literal `*` that
# survives reaches rm and cp as a filename.
shopt -s nullglob

MACHINE_DIR="$HOME/.flow-factory"
SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# --- arguments --------------------------------------------------------------

usage() {
    cat <<'USAGE'
Flow Factory installer

  ./install/install.sh <project-root>    install on this Mac and into a project
  ./install/install.sh --machine         install on this Mac only, no project
  ./install/install.sh                   same as passing the current directory

  --verbose      list every file as it is placed
  --no-color     plain output; NO_COLOR=1 does the same
  --help         this text

Run it from a checkout of the factory. The argument is the project to install
into, never the factory itself.
USAGE
}

PROJECT_ROOT=''
MACHINE_ONLY=no
VERBOSE=no
for arg in "$@"; do
    case $arg in
        -h|--help)   usage; exit 0 ;;
        --machine)   MACHINE_ONLY=yes ;;
        --verbose)   VERBOSE=yes ;;
        --no-color)  FLOW_NO_COLOR=1 ;;
        -*)          printf 'unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
        *)           PROJECT_ROOT=$arg ;;
    esac
done
ui_init

# When the project is the current directory the user did not name it, so it
# is confirmed before anything is written into it.
PROJECT_ASSUMED=no
if [ "$MACHINE_ONLY" = no ] && [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT=$PWD
    PROJECT_ASSUMED=yes
fi

# Ctrl-C at a question. The machine half is idempotent and the project half
# writes nothing before the summary, so the message can be exact.
PHASE=machine
on_interrupt() {
    blank; blank
    case $PHASE in
        machine) say "  Stopped. Run the installer again to finish the machine half." ;;
        ask)     say "  Stopped. The skills stay installed; nothing was written to the project." ;;
        *)       say "  Stopped." ;;
    esac
    exit 130
}
trap on_interrupt INT

# ===========================================================================
# Before anything: is this a factory checkout, and is Claude Code here?
# ===========================================================================

for required in machine skills project/flow-factory.toml project/.flow/README.md install/lib/ui.sh; do
    [ -e "$FACTORY_ROOT/$required" ] \
        || die "$FACTORY_ROOT is not a Flow Factory checkout: no $required" \
               "Run the installer from a clone of the factory repository."
done

# Claude Code is absent when ~/.claude is absent, not when skills/ is. A user
# who has never added a skill has the first and not the second.
[ -d "$HOME/.claude" ] \
    || die "Claude Code was not found on this machine: no $HOME/.claude" \
           "Install Claude Code, start it once, then run this installer again."

SKILL_COUNT=0
for d in "$FACTORY_ROOT"/skills/*/; do SKILL_COUNT=$((SKILL_COUNT + 1)); done

# The questions come from the settings template, one beside each key it sets.
# Read and checked here, before the machine half writes anything, so a
# template missing a question fails on a machine it has not touched yet.
load_questions "$FACTORY_ROOT/project/flow-factory.toml"
check_questions

banner "Flow Factory" "one route for every piece of work: captured, triaged, built, shipped, closed out"
blank
if [ "$MACHINE_ONLY" = yes ]; then
    note "Skills land on this Mac once and serve every project. No project is touched in this run."
else
    note "Two things happen. $SKILL_COUNT skills land on this Mac once and serve every project. Then a few questions about your project become its flow-factory.toml."
fi

# ===========================================================================
# 1/3  This machine
# ===========================================================================

section "1/3" "This machine"

# --- skills ---
# Copy, never symlink. find and grep -r take a symlinked directory as an
# argument and do not descend into it, so any later check over the skills
# directory would read nothing and report a pass. The destination is removed
# first so a file dropped from a skill does not survive the install.
mkdir -p "$SKILLS_DIR"
NEW=0 REPLACED=0
for src in "$FACTORY_ROOT"/skills/*/; do
    name=$(basename -- "$src")
    dest="$SKILLS_DIR/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        REPLACED=$((REPLACED + 1)); [ "$VERBOSE" = no ] || sub "replaced  $name"
        rm -rf -- "$dest"
    else
        NEW=$((NEW + 1)); [ "$VERBOSE" = no ] || sub "installed $name"
    fi
    cp -R -- "${src%/}" "$dest"
done
if [ "$REPLACED" -eq 0 ]; then
    row ok "$SKILL_COUNT skills" "~/.claude/skills/flow-*  all new"
elif [ "$NEW" -eq 0 ]; then
    row ok "$SKILL_COUNT skills" "~/.claude/skills/flow-*  all refreshed"
else
    row ok "$SKILL_COUNT skills" "~/.claude/skills/flow-*  $NEW new, $REPLACED refreshed"
fi

# --- machine files ---
# Every file under machine/. Compare and overwrite, never skip because the file
# exists: a machine copy left in place can carry an instruction the factory has
# since withdrawn. cp keeps the mode of a file it overwrites, so an executable
# is made executable again by hand.
mkdir -p "$MACHINE_DIR"
PLACED=0 UNCHANGED=0 UPDATED=0
while IFS= read -r src; do
    rel=${src#"$FACTORY_ROOT"/machine/}
    dest="$MACHINE_DIR/$rel"
    mkdir -p "$(dirname -- "$dest")"
    if [ ! -e "$dest" ]; then
        PLACED=$((PLACED + 1));    [ "$VERBOSE" = no ] || sub "placed    $rel"
    elif cmp -s "$src" "$dest"; then
        UNCHANGED=$((UNCHANGED + 1)); [ "$VERBOSE" = no ] || sub "unchanged $rel"
    else
        UPDATED=$((UPDATED + 1));  [ "$VERBOSE" = no ] || sub "updated   $rel"
    fi
    cp -- "$src" "$dest"
    if [ -x "$src" ]; then chmod +x "$dest"; fi
done < <(find "$FACTORY_ROOT/machine" -type f ! -name '.gitkeep' | sort)
MACHINE_DETAIL="~/.flow-factory/  "
[ "$PLACED"    -eq 0 ] || MACHINE_DETAIL="$MACHINE_DETAIL$PLACED new, "
[ "$UPDATED"   -eq 0 ] || MACHINE_DETAIL="$MACHINE_DETAIL$UPDATED updated, "
[ "$UNCHANGED" -eq 0 ] || MACHINE_DETAIL="$MACHINE_DETAIL$UNCHANGED unchanged, "
row ok "contracts and templates" "${MACHINE_DETAIL%, }"

# --- status line ---
# The one file the factory writes that it does not own. ~/.claude/settings.json
# is the user's and holds far more than a status line, so the rules are narrow:
# a statusLine that is already there and is not ours is never replaced; the
# file is rewritten only after the new JSON parses, with the old one kept
# beside it; settings that will not parse are left alone and named. A failure
# here never stops the install. The status line is a convenience and every
# skill works without it.
STATUSLINE_SCRIPT="$MACHINE_DIR/statusline.sh"
if [ ! -x "$STATUSLINE_SCRIPT" ]; then
    row skip "status line" "this checkout ships no statusline.sh"
elif ! command -v python3 >/dev/null 2>&1; then
    row warn "status line" "skipped: no python3 to edit settings.json safely"
    sub "add to $CLAUDE_SETTINGS: \"statusLine\": { \"type\": \"command\", \"command\": \"$STATUSLINE_SCRIPT\" }"
else
    STATUSLINE_RESULT=$(
        SETTINGS="$CLAUDE_SETTINGS" COMMAND="$STATUSLINE_SCRIPT" python3 - <<'SETTINGS_EDIT'
import json, os, shutil, sys

settings = os.environ["SETTINGS"]
command = os.environ["COMMAND"]
ours = {"type": "command", "command": command}

if os.path.exists(settings):
    try:
        with open(settings) as fh:
            data = json.load(fh)
    except Exception as exc:
        print("invalid\t%s" % exc)
        sys.exit(0)
    if not isinstance(data, dict):
        print("invalid\tthe file holds %s, not an object" % type(data).__name__)
        sys.exit(0)
    existed = True
else:
    data = {}
    existed = False

existing = data.get("statusLine")
if existing == ours or (isinstance(existing, dict) and existing.get("command") == command):
    # Ours already, possibly with keys the user added on it. Theirs to keep.
    print("unchanged\t")
    sys.exit(0)
if existing is not None:
    print("foreign\t%s" % json.dumps(existing))
    sys.exit(0)

data["statusLine"] = ours
# The temporary file sits beside the settings, not in /tmp: a rename across
# filesystems is not atomic, and the point of writing a copy first is that the
# settings file is either the old one or the new one, never half of each.
backup = settings + ".before-flow-factory"
tmp = settings + ".flow-factory-tmp"
os.makedirs(os.path.dirname(settings), exist_ok=True)
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
try:
    with open(tmp) as fh:
        json.load(fh)
except Exception as exc:
    os.unlink(tmp)
    print("failed\tthe rewritten settings did not parse: %s" % exc)
    sys.exit(0)
if existed:
    shutil.copy2(settings, backup)
os.replace(tmp, settings)
print("%s\t%s" % ("added" if existed else "created", backup if existed else ""))
SETTINGS_EDIT
    )
    STATUSLINE_STATE=${STATUSLINE_RESULT%%$'\t'*}
    STATUSLINE_DETAIL=${STATUSLINE_RESULT#*$'\t'}
    case $STATUSLINE_STATE in
        created)   row ok "status line" "~/.claude/settings.json  created; shows once Claude Code restarts" ;;
        added)     row ok "status line" "~/.claude/settings.json  added; the old file is beside it as settings.json.before-flow-factory" ;;
        unchanged) row ok "status line" "~/.claude/settings.json  already points at it" ;;
        foreign)   row warn "status line" "kept the one already configured, not replaced"
                   sub "to use the factory's instead, set statusLine.command to $STATUSLINE_SCRIPT" ;;
        invalid)   row warn "status line" "skipped: settings.json does not parse as JSON and was left alone"
                   sub "$STATUSLINE_DETAIL" ;;
        *)         row warn "status line" "skipped: $STATUSLINE_DETAIL" ;;
    esac
fi

# --- dispatch prerequisites ---
# From machine/dispatch-prerequisites.md. A failed probe warns; it does not
# stop the install. Only /flow-conductor, which launches a session per issue
# by driving iTerm2, needs these; every other skill works without them.
PROBE_FAILURES=()
probe() {
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then
        [ "$VERBOSE" = no ] || sub "pass  $name"
    else
        [ "$VERBOSE" = no ] || sub "FAIL  $name"
        PROBE_FAILURES+=("$name")
    fi
}
probe "iTerm2 is installed" \
    osascript -e 'id of application id "com.googlecode.iterm2"'
probe "macOS Automation permission lets this terminal drive iTerm2" \
    osascript -e 'tell application id "com.googlecode.iterm2" to count windows'
probe "the session is not inside tmux" \
    [ -z "${TMUX:-}" ]
# Probe 4 has to match the shell a new iTerm2 pane runs, not the one this
# script is in. Read the profile, then probe with no inherited environment.
ITERM_PROFILE=$(defaults read com.googlecode.iterm2 "New Bookmarks" 2>/dev/null || true)
PROBES_RUN=4
case $ITERM_PROFILE in
    *'"Custom Command" = Yes'*)
        PROBES_RUN=3
        [ "$VERBOSE" = no ] || sub "skip  'claude' resolves in a new pane: the iTerm2 profile runs a custom command"
        ;;
    *)
        probe "'claude' resolves in a new iTerm2 pane" \
            env -i HOME="$HOME" TERM=xterm "$SHELL" -lic 'command -v claude'
        ;;
esac
if [ ${#PROBE_FAILURES[@]} -eq 0 ]; then
    row ok "/flow-conductor" "can dispatch: all $PROBES_RUN prerequisites hold"
else
    row warn "/flow-conductor" "cannot dispatch yet: ${#PROBE_FAILURES[@]} of $PROBES_RUN prerequisites missing"
    for p in "${PROBE_FAILURES[@]}"; do sub "$G_DOT $p"; done
    sub "only /flow-conductor is affected. ~/.flow-factory/dispatch-prerequisites.md says how to fix each."
fi

# ===========================================================================
# The version stamp
#
# The factory ships in numbered releases, and a release is a tag, so the stamp
# asks git what release this tree is: `v0.1.0` on the tagged commit,
# `v0.1.0-3-g47cd209` three commits past it, and the short hash before any tag
# exists. A dirty tree is stamped with the count of differing files, because
# the pointer file records what was actually placed, and a run from a dirty
# tree places files that no commit contains.
# ===========================================================================
factory_stamp() {
    local release dirty
    release=$(git -C "$FACTORY_ROOT" describe --tags --always 2>/dev/null) \
        || die "the factory root $FACTORY_ROOT is not a git repository"
    dirty=$(git -C "$FACTORY_ROOT" status --porcelain | wc -l | tr -d ' ')
    if [ "$dirty" -eq 0 ]; then
        printf '%s' "$release"
    else
        printf '%s plus uncommitted changes to %s files' "$release" "$dirty"
    fi
}

if [ "$MACHINE_ONLY" = yes ]; then
    blank
    printf '  %s%s Done%s in %ss. The skills are live in every Claude Code session; no restart needed.\n' \
        "$C_GREEN" "$G_OK" "$C_RESET" "$SECONDS"
    blank
    note "To set up a project, run the installer again with the project's path: ./install/install.sh <project-root>"
    blank
    exit 0
fi

# ===========================================================================
# 2/3  Your project
# ===========================================================================

PHASE=ask
section "2/3" "Your project"

[ -d "$PROJECT_ROOT" ] || die "no such directory: $PROJECT_ROOT"
PROJECT_ROOT=$(cd -- "$PROJECT_ROOT" && pwd)
git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$PROJECT_ROOT is not a git repository" \
           "The skills work through git, so the project has to be one."
[ "$PROJECT_ROOT" != "$FACTORY_ROOT" ] \
    || die "that is the factory checkout, not a project" \
           "Name the project to install into: ./install/install.sh <project-root>"

PROJECT_SHOWN=$PROJECT_ROOT
case $PROJECT_ROOT in "$HOME"/*) PROJECT_SHOWN="~${PROJECT_ROOT#"$HOME"}" ;; esac
EXISTING_SETTINGS="$PROJECT_ROOT/flow-factory.toml"

row info "project" "$PROJECT_SHOWN"
if [ -f "$EXISTING_SETTINGS" ]; then
    row info "flow-factory.toml" "exists; its answers are the defaults below"
fi
if [ "$PROJECT_ASSUMED" = yes ]; then
    choose GO "Install into this project?" yes '' \
        "yes|it is the current directory" "no|stop here"
    [ "$GO" = yes ] || { blank; say "  Nothing was written. Name the project: ./install/install.sh <project-root>"; blank; exit 0; }
fi
blank
# Every question below comes from project/flow-factory.toml: its wording, its
# hint, its options, its order and the key it writes. Nothing here names a
# key. A key added to that template with an `ask:` and a `group:` line beside
# it is asked, and one removed from there stops being asked, with no change to
# this file.

CORE_N=$(q_count core)
OPT_N=$(q_count optional)
DEF_N=$(q_count defaults)

APP_N=$(q_count app)
if [ "$APP_N" -gt 0 ]; then
    note "$CORE_N quick questions, then the services your app runs, then two choices covering the last $((OPT_N + DEF_N)) keys. Enter takes the value in brackets. Everything goes into flow-factory.toml, where you can change it later."
else
    note "$CORE_N quick questions, then two choices covering the other $((OPT_N + DEF_N)) keys. Enter takes the value in brackets. Everything goes into flow-factory.toml, where you can change it later."
fi

# Ask one key: a menu when the template gives it choices, a line of text
# otherwise, re-asked until the validator the key names is satisfied.
ask_key() {
    local key=$1 i kind dflt hint reply why opts=() line
    i=$(q_find "$key")
    kind=$(toml_kind "${Q_VALUE[$i]}")
    key_default "$key"; dflt=$KEY_DEFAULT
    hint=${Q_HINT[$i]}
    [ -z "$KEY_DEFAULT_SOURCE" ] || hint="Suggested from $KEY_DEFAULT_SOURCE. $hint"
    if [ -n "${Q_CHOICES[$i]}" ]; then
        while IFS= read -r line; do opts+=("$line"); done <<< "${Q_CHOICES[$i]}"
        choose reply "${Q_ASK[$i]}" "$dflt" "$hint" "${opts[@]}"
    else
        while :; do
            ask reply "${Q_ASK[$i]}" "$dflt" "$hint"
            # A single dash empties a key that has a default. Enter cannot say
            # it, because Enter means keep, and a blank line reads the same as
            # both.
            [ "$reply" != "-" ] || reply=''
            [ -n "${Q_VERIFY[$i]}" ] || break
            why=$("verify_${Q_VERIFY[$i]}" "$PROJECT_ROOT" "$reply") && break
            hint=$why
        done
    fi
    answer "$key" "$kind" "$reply"
}

# Record a key without putting it to the user: either the default it would
# have been offered, or nothing at all.
take_key() {
    local key=$1 how=$2 kind
    kind=$(toml_kind "${Q_VALUE[$(q_find "$key")]}")
    if [ "$how" = empty ]; then
        answer "$key" "$kind" ''
        return
    fi
    key_default "$key"
    # Verbatim when the default came from a file, so a list item carrying a
    # comma is not read back as two.
    if [ -n "$KEY_DEFAULT_TOML" ]; then
        answer_toml "$key" "$kind" "$KEY_DEFAULT_TOML"
    else
        answer "$key" "$kind" "$KEY_DEFAULT"
    fi
}

# The app: three index-matched lists gathered together, so no answer can
# leave them different lengths, and each element typed on its own, because a
# start command carries commas that a comma-separated line would split on.
# The three questions and their hints are the template's. Only the shape of
# the loop is here, because a loop is not something a comment line can say.
ask_app() {
    local svc_key cmd_key port_key i_svc i_cmd i_port
    local svcs=() cmds=() ports=() svc cmd port why recorded reply
    set -- $(q_group app)
    svc_key=$1 cmd_key=$2 port_key=$3
    i_svc=$(q_find "$svc_key"); i_cmd=$(q_find "$cmd_key"); i_port=$(q_find "$port_key")

    # On a re-install, the services already recorded are the answer unless the
    # user says otherwise. Retyping three lines per service to change nothing
    # is the likeliest way to end up with them wrong.
    recorded=$(existing_answer "$svc_key" list) || recorded=''
    if [ -n "$recorded" ]; then
        choose reply "This project already runs: $recorded" keep '' \
            "keep|leave the services as they are" \
            "again|describe them again from the start" \
            "none|this project has no app to run"
        case $reply in
            keep) take_key "$svc_key" default; take_key "$cmd_key" default
                  take_key "$port_key" default; return ;;
            none) answer_items "$svc_key"; answer_items "$cmd_key"
                  answer_items "$port_key"; return ;;
        esac
    fi

    while :; do
        ask svc "${Q_ASK[$i_svc]}" '' "${Q_HINT[$i_svc]}"
        [ -n "$svc" ] || break
        while :; do
            ask cmd "${Q_ASK[$i_cmd]}" '' "${Q_HINT[$i_cmd]}"
            [ -n "$cmd" ] && break
            hint "a service needs a start command"
        done
        while :; do
            ask port "${Q_ASK[$i_port]}" '' "${Q_HINT[$i_port]}"
            why=$(verify_port "$PROJECT_ROOT" "$port") && break
            hint "$why"
        done
        svcs+=("$svc"); cmds+=("$cmd"); ports+=("$port")
        row ok "$svc" "$cmd  on $port"
    done

    if [ ${#svcs[@]} -eq 0 ]; then
        answer_items "$svc_key"; answer_items "$cmd_key"; answer_items "$port_key"
    else
        answer_items "$svc_key"  "${svcs[@]}"
        answer_items "$cmd_key"  "${cmds[@]}"
        answer_items "$port_key" "${ports[@]}"
    fi
}

for key in $(q_group core); do ask_key "$key"; done
[ "$APP_N" -eq 0 ] || ask_app

# --- the optional group ---
# Empty is an answer here. Under the settings contract it says the project has
# no such thing, which is a different state from a key nobody asked, spelled
# the same way. So the group is always put to the user, and one choice can
# answer all of it at once.
SUGGESTED=''
for key in $(q_group optional); do
    idx=$(q_find "$key")
    [ -n "${Q_DETECT[$idx]}" ] || continue
    found=$("detect_${Q_DETECT[$idx]}" "$PROJECT_ROOT")
    [ -n "$found" ] || continue
    SUGGESTED="${SUGGESTED:+$SUGGESTED, }$key = ${found%%|*}"
done

blank
hint "$OPT_N more keys say where this project keeps its docs, its tests, its reports and its decisions. Most projects leave them empty, which is how a skill is told there is no such thing."
if [ -f "$EXISTING_SETTINGS" ]; then
    choose OPT "Docs, tests, reports and decisions" keep '' \
        "keep|the answers already in flow-factory.toml" \
        "each|go through the $OPT_N one at a time" \
        "none|empty them all: this project has none of these"
elif [ -n "$SUGGESTED" ]; then
    choose OPT "Docs, tests, reports and decisions" detected '' \
        "detected|take what was found ($SUGGESTED), leave the rest empty" \
        "each|go through the $OPT_N one at a time" \
        "none|empty them all: this project has none of these"
else
    choose OPT "Docs, tests, reports and decisions" none '' \
        "none|empty them all: this project has none of these" \
        "each|go through the $OPT_N one at a time"
fi
case $OPT in
    each)
        blank
        hint "A path is relative to the project root, and a list is comma separated. Enter keeps the value in brackets, and a single dash empties it."
        for key in $(q_group optional); do ask_key "$key"; done
        ;;
    none) for key in $(q_group optional); do take_key "$key" empty;   done ;;
    *)    for key in $(q_group optional); do take_key "$key" default; done ;;
esac

# --- the keys whose defaults stand ---
blank
printf '  %s%s more keys come with a default:%s\n' "$C_BOLD" "$DEF_N" "$C_RESET"
for key in $(q_group defaults); do key_default "$key"; kv "$key" "$KEY_DEFAULT"; done
choose DEF "Keep these?" keep '' "keep|as shown" "change|set them one at a time"
if [ "$DEF" = change ]; then
    for key in $(q_group defaults); do ask_key "$key"; done
else
    for key in $(q_group defaults); do take_key "$key" default; done
fi

# --- the summary, then the write ---
blank
printf '  %sflow-factory.toml will say:%s\n' "$C_BOLD" "$C_RESET"
for group in core app optional defaults; do
    for key in $(q_group "$group"); do kv "$key" "$(answered "$key")"; done
done
WRITE_LABEL="write it to $PROJECT_SHOWN"
[ ! -f "$EXISTING_SETTINGS" ] || WRITE_LABEL="$WRITE_LABEL, replacing the current file"
choose CONFIRM "Write it?" yes '' \
    "yes|$WRITE_LABEL" "no|stop; the project is untouched"
if [ "$CONFIRM" != yes ]; then
    blank
    say "  Nothing was written to the project. The skills on this Mac stay installed."
    blank
    exit 0
fi

PHASE=write
blank
SETTINGS_TMP=$(mktemp)
trap 'rm -f -- "$SETTINGS_TMP"' EXIT
write_settings "$FACTORY_ROOT/project/flow-factory.toml" "$SETTINGS_TMP"
mkdir -p "$PROJECT_ROOT/.flow/issues" "$PROJECT_ROOT/.flow/candidates"
row ok ".flow/" "issues/ and candidates/, where work items live as markdown"
if [ -f "$EXISTING_SETTINGS" ]; then
    mv -- "$SETTINGS_TMP" "$EXISTING_SETTINGS"
    row ok "flow-factory.toml" "replaced with the answers above"
else
    mv -- "$SETTINGS_TMP" "$EXISTING_SETTINGS"
    row ok "flow-factory.toml" "written with the answers above"
fi
trap - EXIT

STAMP=$(factory_stamp)
TODAY=$(date +%Y-%m-%d)
sed -e "s|<factory version>|$STAMP|" -e "s|<YYYY-MM-DD>|$TODAY|" \
    "$FACTORY_ROOT/project/.flow/README.md" > "$PROJECT_ROOT/.flow/README.md"
row ok ".flow/README.md" "records Flow Factory $STAMP, installed $TODAY"

# ===========================================================================
# 3/3  Check: every reference an installed skill makes resolves
#
# The installer is the only moment a machine is known to be clean, so the
# check runs here rather than in a skill. find -L, because an install that
# ever links instead of copying would make a plain find read nothing and
# report a pass.
# ===========================================================================

PHASE=check
section "3/3" "Check"

INSTALLED_FILES=$(mktemp)
MISSES=$(mktemp)
trap 'rm -f -- "$INSTALLED_FILES" "$MISSES"' EXIT
find -L "$SKILLS_DIR" -type f -path "$SKILLS_DIR/flow-*" > "$INSTALLED_FILES"
: > "$MISSES"

# A ~/.flow-factory/<path> reference. Trailing sentence punctuation is dropped.
while IFS= read -r ref; do
    [ -e "$HOME/.flow-factory/${ref#\~/.flow-factory/}" ] \
        || printf 'machine file not installed: %s\n' "$ref" >> "$MISSES"
done < <(xargs grep -hoE '~/\.flow-factory/[A-Za-z0-9._/-]+' < "$INSTALLED_FILES" \
    | sed 's/[.,)]$//' | sort -u)

# A flow-<name> reference, with or without the leading slash. A dot only makes
# it a filename when something follows the dot, as in flow-worktree-share.txt;
# a command ending a sentence carries a dot too. sed prepends a space so a
# name starting a line has a character before it.
while IFS= read -r name; do
    [ -d "$SKILLS_DIR/$name" ] \
        || printf 'skill referenced but not installed: %s\n' "$name" >> "$MISSES"
done < <(xargs sed 's/^/ /' < "$INSTALLED_FILES" \
    | grep -oE '[^A-Za-z0-9._-]flow-[a-z0-9-]+([.][A-Za-z0-9]+)?' \
    | grep -v '\.' | sed 's|^.||' | sort -u)

REF_COUNT=$(xargs grep -hoE '(~/\.flow-factory/[A-Za-z0-9._/-]+|/flow-[a-z0-9-]+)' < "$INSTALLED_FILES" | sort -u | wc -l | tr -d ' ')
if [ -s "$MISSES" ]; then
    row fail "references" "$(wc -l < "$MISSES" | tr -d ' ') do not resolve on this machine"
    while IFS= read -r m; do sub "$m"; done < "$MISSES"
    die "the install is incomplete" \
        "A skill names a file this install did not place. That is a factory bug; report it with the lines above."
fi
row ok "references" "every skill's $REF_COUNT references to other skills and machine files resolve"

# ===========================================================================
# Done
# ===========================================================================

blank
printf '  %s%s Done%s in %ss. The skills are live in every Claude Code session; no restart needed.\n' \
    "$C_GREEN" "$G_OK" "$C_RESET" "$SECONDS"
blank
printf '  %sNext%s\n' "$C_BOLD" "$C_RESET"
say "    open Claude Code in $PROJECT_SHOWN and type"
printf '      %s/flow-backlog%s      what there is to work on\n' "$C_CYAN" "$C_RESET"
printf '      %s/flow-park%s         capture an idea into .flow/ without losing your thread\n' "$C_CYAN" "$C_RESET"
printf '      %s/flow-triage%s       turn a capture into a buildable ticket\n' "$C_CYAN" "$C_RESET"
printf '      %s/flow-ship-issue%s   build, verify and ship it\n' "$C_CYAN" "$C_RESET"
say "    every skill: docs/skills.md in the factory checkout"
# A key whose `unset:` tag says stop, answered empty. Every skill that reads
# one refuses the step rather than guess at it, so it is named here while the
# person who answered is still looking.
#
# One row per group, not per key: three keys describing an app that nobody
# described are one fact, and three rows saying it read like three problems.
WARNED=no
for grp in core app optional defaults; do
    EMPTY_KEYS='' EMPTY_N=0
    for idx in "${!Q_KEYS[@]}"; do
        [ "${Q_GROUP[$idx]}" = "$grp" ] || continue
        [ "${Q_UNSET[$idx]}" = stop ] || continue
        [ -z "$(answered "${Q_KEYS[$idx]}")" ] || continue
        EMPTY_KEYS="${EMPTY_KEYS:+$EMPTY_KEYS, }${Q_KEYS[$idx]}"
        EMPTY_N=$((EMPTY_N + 1))
    done
    [ "$EMPTY_N" -gt 0 ] || continue
    [ "$WARNED" = yes ] || { blank; WARNED=yes; }
    if [ "$EMPTY_N" -eq 1 ]; then
        row warn "$EMPTY_KEYS" "left empty; skills that need it stop and ask rather than guess"
    else
        row warn "$EMPTY_N keys left empty" "skills that need them stop and ask rather than guess"
        sub "$EMPTY_KEYS"
    fi
done
[ "$WARNED" = no ] || sub "fill them in at $PROJECT_SHOWN/flow-factory.toml whenever you like"
if [ ${#PROBE_FAILURES[@]} -gt 0 ]; then
    row warn "/flow-conductor" "waits on the ${#PROBE_FAILURES[@]} prerequisite(s) listed above"
fi
blank
