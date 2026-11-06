#!/usr/bin/env bash
#
# Regression test for ./install-copilot. Each case_* function is one case: it
# runs ./install-copilot under a throwaway HOME and asserts on what lands on
# disk, the record, the printed lines and the exit code. Add a case by adding a
# function.
#
#   tests/install-copilot.sh              run every case
#   tests/install-copilot.sh case_a ...   run the named cases
#
# Stops at the first failed assertion and names it. Never reads or writes the
# real HOME, and needs no logged-in Copilot.

set -euo pipefail
unset CDPATH
shopt -s nullglob

FACTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$SCRATCH"' EXIT
export HOME="$SCRATCH/no-home"
unset COPILOT_HOME
# A case must never reach the network, as in tests/install.sh.
NETWORK=(https:// http:// ssh:// git:// git@)
export GIT_CONFIG_COUNT=${#NETWORK[@]}
for i in "${!NETWORK[@]}"; do
    export "GIT_CONFIG_KEY_$i=url.$SCRATCH/no-network/.insteadOf" "GIT_CONFIG_VALUE_$i=${NETWORK[$i]}"
done
GIT_ID=(-c user.name=test -c user.email=test@example.invalid)
CLAUDE_ONLY='AskUserQuestion|EnterWorktree|ExitWorktree|CLAUDE_CODE_SESSION_ID|~/\.claude/|claude -n|/code-review|Agent tool'

CASE=""
RUNS=0

fail() { printf 'FAIL %s: %s\n' "$CASE" "$*" >&2; exit 1; }

# A scratch HOME holding nothing: Copilot needs no directory of its own first.
new_home() {
    local h="$SCRATCH/$CASE/${1:-home}"
    mkdir -p "$h"
    printf '%s' "$h"
}

# A factory checkout cloned from a scratch origin, both under directory $1,
# holding this tree as it stands.
make_factory() {
    mkdir -p "$1/origin"
    cp -R "$FACTORY/install" "$FACTORY/install-copilot" "$FACTORY/skills" "$FACTORY/machine" \
        "$FACTORY/project" "$FACTORY/copilot" "$FACTORY/.gitignore" "$1/origin/"
    git -C "$1/origin" -c init.defaultBranch=main init -q
    git -C "$1/origin" add -A
    git -C "$1/origin" "${GIT_ID[@]}" commit -qm copy
    git clone -q "$1/origin" "$1/factory"
    printf '%s' "$1/factory"
}
CHECKOUT=$(make_factory "$SCRATCH/shared")

copy_factory() { make_factory "$SCRATCH/$CASE"; }
commit_origin() {
    git -C "$SCRATCH/$CASE/origin" add -A
    git -C "$SCRATCH/$CASE/origin" "${GIT_ID[@]}" commit -qm "$1"
}

# Run script $3 (default install-copilot) of checkout $2 under HOME $1. Sets OUT
# and STATUS.
run_with() {
    local h=$1 factory=$2 script=$3
    shift 3
    RUNS=$((RUNS + 1))
    OUT="$SCRATCH/$CASE/out.$RUNS"
    STATUS=0
    HOME="$h" "$factory/$script" "$@" </dev/null >"$OUT" 2>&1 || STATUS=$?
}
run_install() {
    local h=$1 factory=${2:-$CHECKOUT}
    shift; [ $# -eq 0 ] || shift
    run_with "$h" "$factory" install-copilot "$@"
}

expect_status() {
    [ "$STATUS" -eq "$1" ] || fail "exit $STATUS, expected $1. Output:
$(cat "$OUT")"
}
expect_line() {
    grep -qF -- "$1" "$OUT" || fail "no line containing '$1'. Output:
$(cat "$OUT")"
}

shipped() {
    local d
    for d in "$CHECKOUT"/skills/*/; do basename -- "$d"; done
}

installed_home() {
    local h
    h=$(new_home)
    run_install "$h"
    expect_status 0
    printf '%s' "$h"
}

# ---------------------------------------------------------------------------

case_fresh_install_without_claude_places_every_skill() {
    local h name
    h=$(installed_home)
    for name in $(shipped); do
        [ -f "$h/.copilot/skills/$name/SKILL.md" ] || fail "$name not placed"
    done
    [ -f "$h/.flow-factory-copilot/tracker-contract.md" ] || fail "no machine files"
    [ ! -e "$h/.claude" ] || fail "~/.claude was written"
    [ ! -e "$h/.flow-factory" ] || fail "~/.flow-factory was written"
    expect_line "restart Copilot first"
}

case_overlay_takes_the_place_of_its_source() {
    local h
    h=$(installed_home)
    cmp -s "$CHECKOUT/copilot/skills/flow-grilling/SKILL.md" "$h/.copilot/skills/flow-grilling/SKILL.md" \
        || fail "flow-grilling is not the overlay"
    # A file with no overlay is the source.
    cmp -s "$CHECKOUT/skills/flow-tdd/mocking.md" "$h/.copilot/skills/flow-tdd/mocking.md" \
        || fail "flow-tdd/mocking.md differs from its source"
    cmp -s "$CHECKOUT/skills/flow-tdd/LICENSE" "$h/.copilot/skills/flow-tdd/LICENSE" \
        || fail "a LICENSE was changed"
}

case_paths_are_rewritten_for_copilot() {
    local h
    h=$(installed_home)
    ! grep -rnE '~/\.flow-factory(/|[^-]|$)' "$h/.copilot/skills" "$h/.flow-factory-copilot" \
        || fail "a placed file still names ~/.flow-factory"
    grep -qF '~/.copilot/skills/flow-grill-with-docs/SKILL.md' "$h/.copilot/skills/flow-triage/SKILL.md" \
        || fail "flow-triage does not read grill-with-docs from ~/.copilot/skills"
    grep -qF './install-copilot --init' "$h/.flow-factory-copilot/settings-contract.md" \
        || fail "settings-contract still names ./install --init"
}

case_no_claude_only_construct_is_placed() {
    local h
    h=$(installed_home)
    ! grep -rnE -- "$CLAUDE_ONLY" "$h/.copilot/skills" "$h/.flow-factory-copilot" \
        || fail "a Claude-only construct was placed"
}

case_every_claude_specific_source_has_an_overlay() {
    local rel
    while IFS= read -r rel; do
        [ -f "$FACTORY/copilot/$rel" ] || fail "$rel holds a Claude-only construct and has no copilot/$rel"
    done < <(cd -- "$FACTORY" && grep -rlE -- "$CLAUDE_ONLY" skills machine)
}

case_ported_hashes_match_the_sources() {
    local path sum rel
    while read -r path sum; do
        case $path in ''|\#*) continue ;; esac
        [ -f "$FACTORY/copilot/$path" ] || fail "copilot/PORTED lists $path, which has no overlay"
        [ "$(shasum -a 256 "$FACTORY/$path" | cut -d' ' -f1)" = "$sum" ] \
            || fail "$path changed since copilot/$path was ported. Re-port it, then update copilot/PORTED"
    done < "$FACTORY/copilot/PORTED"
    while IFS= read -r rel; do
        [ ! -f "$FACTORY/$rel" ] || grep -q "^$rel " "$FACTORY/copilot/PORTED" \
            || fail "copilot/$rel is not listed in copilot/PORTED"
    done < <(cd -- "$FACTORY/copilot" && find skills machine -type f)
}

case_unported_construct_stops_writing_nothing() {
    local f h
    f=$(copy_factory)
    printf '\nAsk with AskUserQuestion.\n' >> "$SCRATCH/$CASE/origin/skills/flow-park/SKILL.md"
    commit_origin "an unported line"
    git -C "$f" pull -q
    h=$(new_home)
    run_install "$h" "$f"
    expect_status 1
    expect_line "skills/flow-park/SKILL.md"
    [ ! -e "$h/.copilot" ] && [ ! -e "$h/.flow-factory-copilot" ] || fail "something was written"
}

case_stale_port_is_warned() {
    local f h
    f=$(copy_factory)
    printf '\nA new rule.\n' >> "$SCRATCH/$CASE/origin/skills/flow-grilling/SKILL.md"
    commit_origin "a source change"
    git -C "$f" pull -q
    h=$(new_home)
    run_install "$h" "$f"
    expect_status 0
    expect_line "WARNING: skills/flow-grilling/SKILL.md changed since copilot/skills/flow-grilling/SKILL.md was ported"
}

case_rerun_changes_nothing() {
    local h before
    h=$(installed_home)
    before=$(cd -- "$h" && find . -type f ! -name 'out*' -exec shasum {} + | sort)
    run_install "$h"
    expect_status 0
    expect_line "nothing to remove"
    [ "$(cd -- "$h" && find . -type f ! -name 'out*' -exec shasum {} + | sort)" = "$before" ] \
        || fail "a rerun changed a file"
}

case_record_lists_what_was_placed() {
    local h rec
    h=$(installed_home)
    rec="$h/.flow-factory-copilot/install-record.txt"
    grep -qxF "target copilot" "$rec" || fail "no target line"
    grep -qxF "file $h/.copilot/skills/flow-park/SKILL.md" "$rec" || fail "flow-park not recorded"
    grep -qxF "file $h/.flow-factory-copilot/tracker-contract.md" "$rec" || fail "contract not recorded"
    while read -r _ path; do
        [ -f "$path" ] || fail "recorded $path is not on disk"
    done < <(grep '^file ' "$rec")
}

case_update_removes_a_withdrawn_skill() {
    local f h o="$SCRATCH/$CASE/origin"
    f=$(copy_factory)
    h=$(new_home)
    mkdir -p "$o/skills/flow-release"
    printf 'Cut a release.\n' > "$o/skills/flow-release/SKILL.md"
    commit_origin "ship flow-release"
    run_install "$h" "$f"
    expect_status 0
    [ -f "$h/.copilot/skills/flow-release/SKILL.md" ] || fail "flow-release was not placed"
    git -C "$o" rm -rq skills/flow-release
    commit_origin "withdraw flow-release"
    run_install "$h" "$f"
    expect_status 0
    expect_line "pulled "
    expect_line "removed flow-release, no longer shipped"
    [ ! -e "$h/.copilot/skills/flow-release" ] || fail "the withdrawn skill is still there"
    ! grep -qF "/flow-release/" "$h/.flow-factory-copilot/install-record.txt" || fail "still recorded"
}

case_unrecorded_skill_is_left_alone() {
    local h
    h=$(new_home)
    mkdir -p "$h/.copilot/skills/flow-park" "$h/.copilot/skills/flow-mine"
    printf 'mine\n' > "$h/.copilot/skills/flow-park/SKILL.md"
    printf 'mine\n' > "$h/.copilot/skills/flow-mine/SKILL.md"
    run_install "$h"
    expect_status 0
    expect_line "left alone flow-park, which this installer did not place"
    expect_line "left alone flow-mine, which this installer did not place"
    [ "$(cat "$h/.copilot/skills/flow-park/SKILL.md")" = mine ] || fail "flow-park was replaced"
}

case_linked_machine_dir_stops_writing_nothing() {
    local h
    h=$(new_home)
    mkdir -p "$SCRATCH/$CASE/elsewhere"
    ln -s "$SCRATCH/$CASE/elsewhere" "$h/.flow-factory-copilot"
    run_install "$h"
    expect_status 1
    expect_line "is a link"
    [ ! -e "$h/.copilot" ] || fail "~/.copilot was written"
}

case_copilot_home_is_honoured() {
    local h ch
    h=$(new_home)
    ch="$SCRATCH/$CASE/copilot home"
    RUNS=$((RUNS + 1)); OUT="$SCRATCH/$CASE/out.$RUNS"; STATUS=0
    HOME="$h" COPILOT_HOME="$ch" "$CHECKOUT/install-copilot" </dev/null >"$OUT" 2>&1 || STATUS=$?
    expect_status 0
    [ -f "$ch/skills/flow-triage/SKILL.md" ] || fail "not placed under COPILOT_HOME"
    [ ! -e "$h/.copilot" ] || fail "~/.copilot was written"
    grep -qF "$ch/skills/flow-grill-with-docs/SKILL.md" "$ch/skills/flow-triage/SKILL.md" \
        || fail "flow-triage does not name the COPILOT_HOME skills path"
}

case_sits_beside_the_claude_install() {
    local h
    h=$(new_home)
    mkdir -p "$h/.claude"
    run_with "$h" "$CHECKOUT" install
    expect_status 0
    run_install "$h"
    expect_status 0
    expect_line "VS Code reads both directories"
    [ -f "$h/.flow-factory/install-record.txt" ] && [ -f "$h/.flow-factory-copilot/install-record.txt" ] \
        || fail "the two records are not both there"
    ! grep -q "\.copilot" "$h/.flow-factory/install-record.txt" || fail "the Claude record lists Copilot files"
    ! grep -q "\.claude" "$h/.flow-factory-copilot/install-record.txt" || fail "the Copilot record lists Claude files"
    cmp -s "$CHECKOUT/machine/tracker-contract.md" "$h/.flow-factory/tracker-contract.md" \
        || fail "the Claude install's contract was overwritten"
}

case_init_fits_a_project_on_a_copilot_only_machine() {
    local h p a
    h=$(installed_home)
    p="$SCRATCH/$CASE/project"
    mkdir -p "$p"
    git -C "$p" -c init.defaultBranch=trunk init -q
    printf 'x\n' > "$p/README"
    git -C "$p" add README
    git -C "$p" "${GIT_ID[@]}" commit -qm first
    a="$SCRATCH/$CASE/answers.toml"
    printf '%s\n' 'git.default_branch = "trunk"' > "$a"
    run_install "$h" "$CHECKOUT" --init "$p" "$a"
    expect_status 0
    expect_line "Project fitted."
    [ -f "$p/flow-factory.toml" ] && [ -d "$p/.cortex/tickets" ] || fail "the project was not fitted"
    grep -qxF "project $p" "$h/.flow-factory-copilot/install-record.txt" || fail "project not recorded"
    grep -qF '~/.flow-factory-copilot/tracker-contract.md' "$p/.cortex/README.md" \
        || fail ".cortex/README.md does not name this install's contracts"
    ! grep -qE '~/\.flow-factory(/|[^-]|$)' "$p/.cortex/README.md" \
        || fail ".cortex/README.md still names ~/.flow-factory"
    grep -qxF '/.copilot/worktrees/' "$p/.git/info/exclude" || fail "/.copilot/worktrees/ is not excluded"
    ! grep -qF '.claude/worktrees' "$p/.git/info/exclude" || fail "/.claude/worktrees/ was excluded"
    [ ! -e "$h/.flow-factory" ] || fail "~/.flow-factory was written"
}

case_check_reads_the_copilot_record_and_writes_nothing() {
    local h p a
    h=$(installed_home)
    p="$SCRATCH/$CASE/project"
    mkdir -p "$p"
    git -C "$p" -c init.defaultBranch=trunk init -q
    printf 'x\n' > "$p/README"
    git -C "$p" add README
    git -C "$p" "${GIT_ID[@]}" commit -qm first
    a="$SCRATCH/$CASE/answers.toml"
    printf '%s\n' 'git.default_branch = "trunk"' > "$a"
    cp "$h/.flow-factory-copilot/install-record.txt" "$SCRATCH/$CASE/record.before"
    run_install "$h" "$CHECKOUT" --check "$p" "$a"
    expect_status 0
    expect_line "no origin"
    [ ! -e "$p/flow-factory.toml" ] && [ ! -e "$p/.cortex" ] || fail "--check wrote into the project"
    cmp -s "$SCRATCH/$CASE/record.before" "$h/.flow-factory-copilot/install-record.txt" \
        || fail "--check changed the record"
    [ ! -e "$h/.flow-factory" ] || fail "~/.flow-factory was written"
}

case_flow_init_names_the_copilot_installer() {
    local h f
    h=$(installed_home)
    f="$h/.copilot/skills/flow-init/SKILL.md"
    [ -f "$f" ] || fail "flow-init was not placed"
    grep -qF '"<checkout>/install-copilot" --check' "$f" || fail "flow-init does not check through ./install-copilot"
    grep -qF '"<checkout>/install-copilot" --init' "$f" || fail "flow-init does not fit through ./install-copilot"
    grep -qF '~/.flow-factory-copilot/install-record.txt' "$f" || fail "flow-init does not read this install's record"
    ! grep -qE '"<checkout>/install" |\.claude/worktrees' "$f" || fail "flow-init still names the Claude Code install"
}

case_init_without_the_copilot_install_stops() {
    local h p a
    h=$(new_home)
    p="$SCRATCH/$CASE/project"
    mkdir -p "$p"
    git -C "$p" init -q
    a="$SCRATCH/$CASE/answers.toml"
    : > "$a"
    run_install "$h" "$CHECKOUT" --init "$p" "$a"
    expect_status 1
    expect_line "no ~/.flow-factory-copilot/install-record.txt"
}

case_unknown_argument_stops_writing_nothing() {
    local h
    h=$(new_home)
    run_install "$h" "$CHECKOUT" --bogus
    expect_status 1
    expect_line "usage: ./install-copilot"
    [ ! -e "$h/.copilot" ] || fail "~/.copilot was written"
}

# ---------------------------------------------------------------------------

if [ $# -gt 0 ]; then
    CASES=("$@")
else
    CASES=($(declare -F | awk '$3 ~ /^case_/ { print $3 }'))
fi
for CASE in "${CASES[@]}"; do
    mkdir -p "$SCRATCH/$CASE"
    "$CASE"
    printf 'ok %s\n' "$CASE"
done
