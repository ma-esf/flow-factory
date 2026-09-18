#!/usr/bin/env bash
#
# Flow Factory installer. Performs the thirteen steps recorded in
# install-steps.md: the machine half once per machine, then the project half
# once per project.
#
#   ./install/install.sh <project-root>
#
# Run it from a checkout of the factory, and name the project to install into.
# The project root defaults to the current directory, so the argument can be
# left off only when the current directory is that project.
#
# It leaves either a complete install or a named failure. The project half
# builds the settings file in a temporary copy and moves it into place only
# once every question is answered, so an interrupted run does not leave a
# half-answered file behind.

set -euo pipefail

FACTORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=${1:-$PWD}

# An unmatched glob must expand to nothing, not to itself. A literal `*` that
# survives reaches rm and cp as a filename.
shopt -s nullglob

MACHINE_DIR="$HOME/.flow-factory"
SKILLS_DIR="$HOME/.claude/skills"

EMPTY_ANSWERS=()
PROBE_FAILURES=()

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
fail() { printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

# Read one answer. End of input is a failure, not an empty answer: a run whose
# input ran out has not answered the remaining keys. The locals carry a prefix
# because the caller passes the name of its own variable, and a plain name here
# would shadow it and return an empty answer for every question.
ask() {
    local __prompt=$1 __var=$2 __reply
    printf '%s' "$__prompt"
    IFS= read -r __reply || fail "input ended before '$__prompt' was answered"
    printf -v "$__var" '%s' "$__reply"
}

# ---------------------------------------------------------------------------
# The version stamp
#
# install-steps.md leaves the choice open: refuse a dirty factory tree, or
# stamp the commit plus the count of differing files. This stamps, because the
# pointer file's job is to record what was actually placed, and a run from a
# dirty tree places files that no commit contains. Refusing would also make the
# installer unable to install its own uncommitted changes, which is the state
# every change to the factory passes through.
# ---------------------------------------------------------------------------
factory_stamp() {
    local commit dirty
    commit=$(git -C "$FACTORY_ROOT" rev-parse --short HEAD) \
        || fail "the factory root $FACTORY_ROOT is not a git repository"
    dirty=$(git -C "$FACTORY_ROOT" status --porcelain | wc -l | tr -d ' ')
    if [ "$dirty" -eq 0 ]; then
        printf '%s' "$commit"
    else
        printf '%s plus uncommitted changes to %s files' "$commit" "$dirty"
    fi
}

# Check the factory checkout before placing anything, so a missing source is
# found before the steps above it have written to the machine.
for required in machine skills project/flow-factory.toml project/.flow/README.md; do
    [ -e "$FACTORY_ROOT/$required" ] \
        || fail "$FACTORY_ROOT is not a factory checkout: no $required"
done

# ===========================================================================
# The machine half, once per machine
# ===========================================================================

step "Step 1. Find the agent's skills directory"
[ -d "$SKILLS_DIR" ] \
    || fail "no $SKILLS_DIR. Claude Code was not found on this machine."
say "found $SKILLS_DIR"

step "Step 2. Create $MACHINE_DIR"
mkdir -p "$MACHINE_DIR"
say "ready $MACHINE_DIR"

step "Step 3. Place the machine files"
# Every file under machine/. A file the skills read but the installer never
# places is a broken reference the final check would report against a ticket
# that did nothing wrong.
#
# Compare and overwrite, never skip because the file exists. A machine copy
# left in place can carry an instruction the factory has since withdrawn.
while IFS= read -r src; do
    rel=${src#"$FACTORY_ROOT"/machine/}
    dest="$MACHINE_DIR/$rel"
    mkdir -p "$(dirname -- "$dest")"
    if [ ! -e "$dest" ]; then
        say "  placed    $rel"
    elif cmp -s "$src" "$dest"; then
        say "  unchanged $rel"
    else
        say "  OVERWROTE $rel"
    fi
    cp -- "$src" "$dest"
done < <(find "$FACTORY_ROOT/machine" -type f ! -name '.gitkeep' | sort)

step "Step 4. Copy each skill directory into $SKILLS_DIR"
# Copy, never symlink. find and grep -r take a symlinked directory as an
# argument and do not descend into it, so any later check over the skills
# directory would read nothing and report a pass.
#
# The destination is removed first so a file dropped from a skill does not
# survive the install.
for src in "$FACTORY_ROOT"/skills/*/; do
    name=$(basename -- "$src")
    dest="$SKILLS_DIR/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        say "  replaced  $name"
        rm -rf -- "$dest"
    else
        say "  installed $name"
    fi
    cp -R -- "${src%/}" "$dest"
done

# ===========================================================================
# The dispatch probes, from machine/dispatch-prerequisites.md
#
# A failed probe warns; it does not stop the install. Probes 2, 3 and 4 are
# facts about the session that will dispatch and the terminal profile it runs,
# not about the machine, and they can hold tomorrow and fail today. Probe 1 is
# a machine fact, but it breaks dispatch alone and leaves every placed file
# correct. Only the final check sets a non-zero exit code.
# ===========================================================================

step "Dispatch prerequisites"

probe() {
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then
        say "  pass  $name"
    else
        say "  FAIL  $name"
        PROBE_FAILURES+=("$name")
    fi
}

probe "1. iTerm2 is installed" \
    osascript -e 'id of application id "com.googlecode.iterm2"'
probe "2. macOS Automation permission is granted" \
    osascript -e 'tell application id "com.googlecode.iterm2" to count windows'
probe "3. The session is not inside tmux" \
    [ -z "${TMUX:-}" ]

# Probe 4 has to match the shell a new iTerm2 pane runs, not the one this
# script is in. Read the profile, then probe with no inherited environment.
ITERM_PROFILE=$(defaults read com.googlecode.iterm2 "New Bookmarks" 2>/dev/null || true)
case $ITERM_PROFILE in
    *'"Custom Command" = Yes'*) CUSTOM_COMMAND=yes ;;
    *)                          CUSTOM_COMMAND=no  ;;
esac
if [ "$CUSTOM_COMMAND" = yes ]; then
    say "  SKIP  4. 'claude' resolves in a new pane"
    say "        the iTerm2 profile runs a custom command; probe it with that"
    say "        command's own flags, as dispatch-prerequisites.md says."
else
    probe "4. 'claude' resolves in a new pane" \
        env -i HOME="$HOME" TERM=xterm "$SHELL" -lic 'command -v claude'
fi

if [ ${#PROBE_FAILURES[@]} -gt 0 ]; then
    say ""
    say "  ${#PROBE_FAILURES[@]} prerequisite(s) failed. The install continues;"
    say "  /flow-conductor cannot dispatch until they are fixed:"
    for p in "${PROBE_FAILURES[@]}"; do say "    - $p"; done
fi

# ===========================================================================
# The project half, once per project
# ===========================================================================

step "Step 5. Find the project root"
[ -d "$PROJECT_ROOT" ] || fail "no such directory: $PROJECT_ROOT"
PROJECT_ROOT=$(cd -- "$PROJECT_ROOT" && pwd)
git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || fail "$PROJECT_ROOT is not a git repository"
[ "$PROJECT_ROOT" != "$FACTORY_ROOT" ] \
    || fail "the project root is the factory checkout. Pass the project as an argument."
say "$PROJECT_ROOT"

step "Step 6. Create the work-items folder"
mkdir -p "$PROJECT_ROOT/.flow/issues" "$PROJECT_ROOT/.flow/candidates"
say "ready .flow/issues and .flow/candidates"

step "Step 7. Prepare flow-factory.toml"
# Built in a temporary copy of the template, which carries the comments and the
# unset: tag for every key, and moved into place at step 12. The project's own
# answers are written over the template's values, one line each.
SETTINGS_TMP=$(mktemp)
trap 'rm -f -- "$SETTINGS_TMP"' EXIT
cp -- "$FACTORY_ROOT/project/flow-factory.toml" "$SETTINGS_TMP"
say "template read from project/flow-factory.toml"

# Write one key's value into the pending settings file. The value arrives
# already in TOML form, so a string carries its quotes and a list its brackets.
set_key() {
    local key=$1 value=$2 tmp
    tmp=$(mktemp)
    KEY="$key" VALUE="$value" awk '
        BEGIN { key = ENVIRON["KEY"]; value = ENVIRON["VALUE"]; done = 0 }
        $0 ~ "^" key " = " && !done { print key " = " value; done = 1; next }
        { print }
        END { if (!done) exit 1 }
    ' "$SETTINGS_TMP" > "$tmp" || { rm -f -- "$tmp"; fail "no line for key '$key' in the template"; }
    mv -- "$tmp" "$SETTINGS_TMP"
}

# Escape what TOML treats as special inside a quoted string. Backslash first,
# or the backslashes this adds get escaped a second time.
esc() {
    local v=$1
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    printf '%s' "$v"
}

# Turn one plain answer into TOML. Every question goes through here, so the
# user types a value and never TOML, and no answer can write a line a skill
# cannot read.
toml_value() {
    local kind=$1 raw=$2 out i item
    case $kind in
        string) printf '"%s"' "$(esc "$raw")" ;;
        list)
            if [ -z "$raw" ]; then printf '[]'; return; fi
            # Split on commas and trim each element. read -a rather than word
            # splitting, which would let a glob in an answer match the disk.
            local parts=()
            IFS=, read -ra parts <<< "$raw"
            out="["
            for i in "${!parts[@]}"; do
                item=${parts[$i]}
                item=${item#"${item%%[![:space:]]*}"}
                item=${item%"${item##*[![:space:]]}"}
                [ "$i" -eq 0 ] || out="$out, "
                out="$out\"$(esc "$item")\""
            done
            printf '%s]' "$out"
            ;;
    esac
}

# Ask one must-ask key. An empty answer is written as an empty value and the
# key is recorded, because under the settings contract an empty value says the
# project has no such thing, which is a different state from a key nobody
# asked, spelled the same way.
ask_key() {
    local key=$1 kind=$2 hint=$3 reply value
    ask "  $key ($hint): " reply
    case $kind in
        string|list) value=$(toml_value "$kind" "$reply") ;;
        bool)
            while :; do
                case $reply in
                    true|yes|y)  value=true;  break ;;
                    false|no|n)  value=false; break ;;
                    "")          value=false; break ;;
                esac
                say "    true or false"
                ask "  $key ($hint): " reply
            done
            ;;
    esac
    if [ -z "$reply" ]; then
        EMPTY_ANSWERS+=("$key")
    fi
    set_key "$key" "$value"
}

step "Step 8. Answer git.default_branch"
# The one step that looks detectable and is not. The repository can be read,
# but a repository showing one branch is the repository answering, not the
# project. Detect the value, then have the user confirm it; a guess that
# happens to be right still hides the case where it is wrong.
DETECTED_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[ -n "$DETECTED_BRANCH" ] && [ "$DETECTED_BRANCH" != "HEAD" ] \
    || fail "cannot read a branch name from $PROJECT_ROOT"
say "  detected '$DETECTED_BRANCH' from the repository"
while :; do
    ask "  type 'y' to confirm '$DETECTED_BRANCH', or the correct branch name: " REPLY_BRANCH
    case $REPLY_BRANCH in
        y|Y)  BRANCH=$DETECTED_BRANCH; break ;;
        "")   say "  an answer is needed; the detected value is not written unconfirmed" ;;
        *)
            # Checked against the repository, which catches a typo and a
            # refusal typed as a word. A wrong value here is the one
            # install-steps.md measured: the range collapses and a review
            # reports success over a file it never read.
            if git -C "$PROJECT_ROOT" show-ref --quiet --verify "refs/heads/$REPLY_BRANCH" \
               || git -C "$PROJECT_ROOT" show-ref --quiet "refs/remotes/$REPLY_BRANCH"; then
                BRANCH=$REPLY_BRANCH; break
            fi
            say "  '$REPLY_BRANCH' is not a branch in this repository"
            ;;
    esac
done
set_key "git.default_branch" "\"$BRANCH\""
say "  git.default_branch = \"$BRANCH\""

step "Step 9. Answer test.command"
# Not asked through ask_key. Under the settings contract this key's unset
# behaviour is stop, not "does not apply", so an empty answer does not belong
# in the list of keys where empty says the project has no such thing.
ask "  test.command (the command that runs this project's tests): " REPLY_TEST
set_key "test.command" "$(toml_value string "$REPLY_TEST")"
if [ -z "$REPLY_TEST" ]; then
    say "  left empty. Every skill that runs tests will stop and name this key."
fi

step "Step 10. Answer the document, tracker and Jira keys"
say "  Empty is an answer here. It says the project has no such thing."
ask_key "docs.context"         string "the file holding this project's domain vocabulary"
ask_key "docs.glossaries"      list   "glossaries in order, comma separated; the first is written to"
ask_key "project.decision_docs" list  "decision documents beyond docs/adr/, comma separated"
ask_key "test.dir"             string "where a new test file must land"
ask_key "test.guide_path"      string "the testing guide read before writing a test"
ask_key "source.backend_dir"   string "the backend source directory, if the project separates them"
ask_key "tracker.epic_field"   string "the header field naming an epic, for example Epic"
ask_key "jira.enabled"         bool   "true or false"

step "Step 11. Answer the GitHub keys"
while :; do
    ask "  github.merge_strategy (squash, merge or rebase): " REPLY_MERGE
    case $REPLY_MERGE in
        squash|merge|rebase) set_key "github.merge_strategy" "\"$REPLY_MERGE\""; break ;;
        *) say "  one of squash, merge or rebase" ;;
    esac
done
while :; do
    ask "  github.attribution (none or tool): " REPLY_ATTR
    case $REPLY_ATTR in
        none|tool) set_key "github.attribution" "\"$REPLY_ATTR\""; break ;;
        *) say "  one of none or tool" ;;
    esac
done

step "Step 12. Confirm the keys whose defaults stand"
# A replacement is a plain value, not TOML. It goes through the same builder
# as every other answer, so a reply of gh becomes "gh" and feat/, fix/ becomes
# a two-element list, and neither can leave a line a skill cannot read.
confirm_default() {
    local key=$1 kind=$2 shown=$3 reply value
    while :; do
        ask "  $key = $shown. Type 'y' to keep it, or a replacement: " reply
        case $reply in
            y|Y|"") say "    kept"; return ;;
        esac
        if [ "$kind" = bool ]; then
            case $reply in
                true|yes) value=true ;;
                false|no) value=false ;;
                *) say "    true or false"; continue ;;
            esac
        else
            value=$(toml_value "$kind" "$reply")
        fi
        set_key "$key" "$value"
        say "    set to $value"
        return
    done
}
confirm_default "branch.prefixes"   list   '["feat/", "fix/", "docs/", "wip/"]'
confirm_default "pr.create_mode"    string '"manual"'
confirm_default "github.labels"     list   '[]'
confirm_default "github.assignees"  list   '[]'
confirm_default "privacy.redact_client_data" bool 'true'

SETTINGS_EXISTED=no
[ -e "$PROJECT_ROOT/flow-factory.toml" ] && SETTINGS_EXISTED=yes
mv -- "$SETTINGS_TMP" "$PROJECT_ROOT/flow-factory.toml"
trap - EXIT
if [ "$SETTINGS_EXISTED" = yes ]; then
    say "  OVERWROTE flow-factory.toml. The answers it held are gone."
else
    say "  placed flow-factory.toml"
fi

if [ ${#EMPTY_ANSWERS[@]} -gt 0 ]; then
    say ""
    say "  Answered empty, meaning this project has no such thing:"
    for k in "${EMPTY_ANSWERS[@]}"; do say "    - $k"; done
fi

step "Step 13. Place the pointer file"
STAMP=$(factory_stamp)
TODAY=$(date +%Y-%m-%d)
sed -e "s|<factory commit>|$STAMP|" -e "s|<YYYY-MM-DD>|$TODAY|" \
    "$FACTORY_ROOT/project/.flow/README.md" > "$PROJECT_ROOT/.flow/README.md"
say "  Flow Factory $STAMP, installed $TODAY"

# ===========================================================================
# The final check: every reference an installed skill makes resolves
#
# PRD.md item 9. The installer is the only moment a machine is known to be
# clean, so the check runs here rather than in a skill.
#
# find -L, because an install that ever links instead of copying would make a
# plain find read nothing and report a pass.
# ===========================================================================

step "Final check. Every reference in an installed skill resolves"

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

# A /flow-<name> slash command. A dot makes it a filename only when something
# follows the dot, as in flow-worktree-share.txt. A command at the end of a
# sentence carries a dot too, and treating that as a filename skipped it.
while IFS= read -r name; do
    [ -d "$SKILLS_DIR/$name" ] \
        || printf 'skill referenced but not installed: /%s\n' "$name" >> "$MISSES"
done < <(xargs grep -hoE '/flow-[a-z0-9-]+([.][A-Za-z0-9]+)?' < "$INSTALLED_FILES" \
    | grep -v '\.' | sed 's|^/||' | sort -u)

if [ -s "$MISSES" ]; then
    say ""
    cat "$MISSES"
    fail "$(wc -l < "$MISSES" | tr -d ' ') reference(s) do not resolve on this machine"
fi

say "  every reference resolves"
say ""
say "Install complete."
