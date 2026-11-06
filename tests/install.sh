#!/usr/bin/env bash
#
# Regression test for ./install. Each case_* function is one case: it runs
# ./install under a throwaway HOME and asserts on what lands on disk, the
# record, the printed lines and the exit code. Add a case by adding a function.
#
#   tests/install.sh              run every case
#   tests/install.sh case_a ...   run the named cases
#
# Stops at the first failed assertion and names it. Never reads or writes the
# real HOME, and needs no logged-in Claude.

set -euo pipefail
unset CDPATH
shopt -s nullglob

FACTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# The physical path, which the installer records.
SCRATCH=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$SCRATCH"' EXIT
# Every run sets its own HOME. This one catches a helper that forgets.
export HOME="$SCRATCH/no-home"
# ./install pulls, and a case must never reach the network. The URL forms a
# factory checkout's remote takes are rewritten to a path that does not
# exist, so such a pull fails at once and prints the line run_install
# refuses. GIT_CONFIG_COUNT needs git 2.31.
NETWORK=(https:// http:// ssh:// git:// git@)
export GIT_CONFIG_COUNT=${#NETWORK[@]}
for i in "${!NETWORK[@]}"; do
    export "GIT_CONFIG_KEY_$i=url.$SCRATCH/no-network/.insteadOf" "GIT_CONFIG_VALUE_$i=${NETWORK[$i]}"
done
PULL_FAILED="the pull failed"
# gh as every case meets it unless the case puts its own first on PATH:
# installed and logged out, so no case reaches GitHub through it.
mkdir -p "$SCRATCH/gh-logged-out"
printf '#!/bin/sh\nexit 1\n' > "$SCRATCH/gh-logged-out/gh"
chmod +x "$SCRATCH/gh-logged-out/gh"
export PATH="$SCRATCH/gh-logged-out:$PATH"
# The rest of the machine check's tools, the same way: each fails, so no case
# launches iTerm2, reads its real preferences, reaches GitHub or runs this
# machine's login shell or claude.
mkdir -p "$SCRATCH/no-machine"
for tool in osascript defaults curl claude login-shell; do
    printf '#!/bin/sh\nexit 1\n' > "$SCRATCH/no-machine/$tool"
    chmod +x "$SCRATCH/no-machine/$tool"
done
export PATH="$SCRATCH/no-machine:$PATH" SHELL="$SCRATCH/no-machine/login-shell"
unset TMUX
# An update that would ask at a terminal is taken without asking, so a case
# that brings one tests what the update places. A case about the question
# clears it.
export FLOW_FACTORY_UPDATE=yes
GIT_ID=(-c user.name=test -c user.email=test@example.invalid)

CASE=""
RUNS=0

fail() { printf 'FAIL %s: %s\n' "$CASE" "$*" >&2; exit 1; }

# A scratch HOME holding only .claude/, as a machine with Claude Code has.
new_home() {
    local h="$SCRATCH/$CASE/${1:-home}"
    mkdir -p "$h/.claude"
    printf '%s' "$h"
}

# A factory checkout cloned from a scratch origin, both under directory $1,
# holding this tree as it stands, uncommitted changes included. The origin is
# a working repository, so a case changes it by committing there.
make_factory() {
    mkdir -p "$1/origin"
    cp -R "$FACTORY/install" "$FACTORY/skills" "$FACTORY/machine" "$FACTORY/project" "$FACTORY/.gitignore" "$1/origin/"
    git -C "$1/origin" -c init.defaultBranch=main init -q
    git -C "$1/origin" add -A
    git -C "$1/origin" "${GIT_ID[@]}" commit -qm copy
    git clone -q "$1/origin" "$1/factory"
    printf '%s' "$1/factory"
}

# The checkout every run uses unless a case names its own. Never the real one:
# ./install would pull it.
CHECKOUT=$(make_factory "$SCRATCH/shared")

# Run ./install from a factory checkout under HOME $1, with nothing on stdin
# and any further arguments passed on. Sets OUT to the file holding stdout and
# stderr, and STATUS to the exit code. A failed pull fails the case unless it
# sets PULL_MAY_FAIL, because a pull reaching past the scratch origin fails.
run_install() {
    local h=$1 factory=${2:-$CHECKOUT}
    shift; [ $# -eq 0 ] || shift
    RUNS=$((RUNS + 1))
    OUT="$SCRATCH/$CASE/out.$RUNS"
    STATUS=0
    HOME="$h" "$factory/install" "$@" </dev/null >"$OUT" 2>&1 || STATUS=$?
    [ -n "${PULL_MAY_FAIL:-}" ] || ! grep -qF "$PULL_FAILED" "$OUT" || fail "the pull failed. Output:
$(cat "$OUT")"
}

# Run ./install from checkout $2 under HOME $1 at a terminal, with update
# approval cleared, and answer its question with $3. BSD script gives the run a
# terminal. The answer waits a second so it lands after the run starts, and
# stdin stays open two more, because script turns its end into an EOF that a
# read could take first.
run_install_at_terminal() {
    local h=$1 factory=$2 answer=$3
    RUNS=$((RUNS + 1))
    OUT="$SCRATCH/$CASE/out.$RUNS"
    STATUS=0
    { sleep 1; printf '%s\n' "$answer"; sleep 2; } \
        | FLOW_FACTORY_UPDATE='' HOME="$h" script -q /dev/null "$factory/install" 2>&1 \
        | tr -d '\r' >"$OUT" || STATUS=$?
    ! grep -qF "$PULL_FAILED" "$OUT" || fail "the pull failed. Output:
$(cat "$OUT")"
}

# Run ./install --init under HOME $1 on project root $2 with answers file $3.
run_init() {
    run_install "$1" "$CHECKOUT" --init "$2" "$3"
}

# The same, for ./install --check.
run_check() {
    run_install "$1" "$CHECKOUT" --check "$2" "$3"
}

expect_status() {
    [ "$STATUS" -eq "$1" ] || fail "exit $STATUS, expected $1. Output:
$(cat "$OUT")"
}

expect_line() {
    grep -qF -- "$1" "$OUT" || fail "no line containing '$1'. Output:
$(cat "$OUT")"
}

refuse_line() {
    ! grep -qiF -- "$1" "$OUT" || fail "unexpected '$1' in output"
}

shipped() {
    local d
    for d in "$CHECKOUT"/skills/*/; do basename -- "$d"; done
}

# Every file the factory ships, each skills/<path> or machine/<path>. A Finder
# .DS_Store is git-ignored and not the factory.
shipped_files() {
    (cd "$CHECKOUT" && find skills machine -type f ! -name .gitkeep ! -name .DS_Store)
}

# Every file machine/ ships, as a path below it.
machine_files() { shipped_files | sed -n 's|^machine/||p'; }

# A checkout of this case's own, for a case that must change a shipped file.
# Its origin is $SCRATCH/$CASE/origin.
copy_factory() { make_factory "$SCRATCH/$CASE"; }

# Commit every change in this case's origin, with message $1.
commit_origin() {
    git -C "$SCRATCH/$CASE/origin" add -A
    git -C "$SCRATCH/$CASE/origin" "${GIT_ID[@]}" commit -qm "$1"
}

# ---------------------------------------------------------------------------

case_fresh_install_places_every_file() {
    local h name
    h=$(new_home)
    run_install "$h"
    expect_status 0
    for name in $(shipped); do
        diff -r -x .DS_Store "$CHECKOUT/skills/$name" "$h/.claude/skills/$name" >/dev/null \
            || fail "skill $name differs from skills/$name"
    done
    diff -r -x .gitkeep -x .DS_Store -x install-record.txt "$CHECKOUT/machine" "$h/.flow-factory" >/dev/null \
        || fail "~/.flow-factory differs from machine/"
}

case_announces_both_paths_before_any_write() {
    local h first_write paths
    h=$(new_home)
    run_install "$h"
    expect_status 0
    # The first line that reports a write, including creating a directory.
    first_write=$(grep -nE '^ *(placed|unchanged|OVERWROTE|installed|replaced|created|recorded|removed) ' "$OUT" \
        | head -1 | cut -d: -f1)
    [ -n "$first_write" ] || fail "no line reports a write"
    paths=$(head -n $((first_write - 1)) "$OUT" | grep -oE '(~|/)[^ ]*' | sort | tr '\n' ' ')
    [ "$paths" = '~/.claude/skills/flow-* ~/.flow-factory/ ' ] \
        || fail "before the first write, the paths named were '$paths'"
}

case_record_lists_what_was_placed() {
    local h rec expected listed f
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    [ -f "$rec" ] || fail "no record at ~/.flow-factory/install-record.txt"
    grep -qxF "version $(git -C "$CHECKOUT" describe --tags --always)" "$rec" \
        || fail "no version line naming $(git -C "$CHECKOUT" describe --tags --always)"
    grep -qxF "checkout $CHECKOUT" "$rec" || fail "no line 'checkout $CHECKOUT'"
    grep -qx 'mode copy' "$rec" || fail "no line 'mode copy'"
    ! grep -q '^project ' "$rec" || fail "a project line, before any project was initialised"
    expected=$(shipped_files | wc -l | tr -d ' ')
    listed=$(grep -c '^file ' "$rec" || true)
    [ "$listed" -eq "$expected" ] || fail "$listed file lines, expected $expected"
    while IFS= read -r f; do
        [ -f "$f" ] || fail "the record lists $f, which is not on disk"
    done < <(sed -n 's/^file //p' "$rec")
}

case_unrecorded_skill_survives_two_installs() {
    local h run
    h=$(new_home)
    mkdir -p "$h/.claude/skills/flow-mine"
    printf 'Hand the result to /flow-gone.\n' > "$h/.claude/skills/flow-mine/SKILL.md"
    cp -Rp "$h/.claude/skills/flow-mine" "$SCRATCH/$CASE/flow-mine.before"
    for run in 1 2; do
        run_install "$h"
        expect_status 0
        expect_line "left alone flow-mine"
        diff -r "$SCRATCH/$CASE/flow-mine.before" "$h/.claude/skills/flow-mine" >/dev/null \
            || fail "flow-mine changed on run $run"
    done
    # The second run replaces what the first recorded.
    expect_line "replaced  flow-tdd"
}

case_unrecorded_shipped_name_is_left_alone() {
    local h
    h=$(new_home)
    mkdir -p "$h/.claude/skills/flow-tdd"
    printf 'my own\n' > "$h/.claude/skills/flow-tdd/SKILL.md"
    run_install "$h"
    expect_status 0
    expect_line "left alone flow-tdd"
    [ "$(cat "$h/.claude/skills/flow-tdd/SKILL.md")" = "my own" ] || fail "flow-tdd was overwritten"
    ! grep -q "^file $h/.claude/skills/flow-tdd/" "$h/.flow-factory/install-record.txt" \
        || fail "the record claims flow-tdd, which this run did not place"
}

case_reference_to_unshipped_skill_fails() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    printf '\nWhen done, run /flow-release.\n' >> "$factory/skills/flow-tdd/SKILL.md"
    # A directory of that name on disk, unrecorded, must not satisfy it.
    mkdir -p "$h/.claude/skills/flow-release"
    printf 'stale\n' > "$h/.claude/skills/flow-release/SKILL.md"
    run_install "$h" "$factory"
    [ "$STATUS" -ne 0 ] || fail "exit 0 with a reference to an unshipped skill"
    expect_line "skill referenced but not installed: flow-release"
}

case_rerun_keeps_project_lines() {
    local h rec
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    printf 'project /work/app\n' >> "$rec"
    run_install "$h"
    expect_status 0
    grep -qx 'project /work/app' "$rec" || fail "the rerun dropped the project line"
}

case_record_is_written_before_skills_are_copied() {
    local h bin
    h=$(new_home)
    # A cp that fails on one skill file stops the copy partway.
    bin="$SCRATCH/$CASE/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\ncase "$*" in *flow-tdd/SKILL.md*) exit 1 ;; esac\nexec /bin/cp "$@"\n' > "$bin/cp"
    chmod +x "$bin/cp"
    PATH="$bin:$PATH" run_install "$h"
    [ "$STATUS" -ne 0 ] || fail "exit 0 with a failing copy"
    [ -f "$h/.claude/skills/flow-ask/SKILL.md" ] || fail "the copy stopped before it started"
    run_install "$h"
    expect_status 0
    refuse_line "left alone"
}

case_git_ignored_files_are_not_placed() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    printf '.DS_Store\n' > "$factory/.gitignore"
    git -C "$factory" add .gitignore
    git -C "$factory" "${GIT_ID[@]}" commit -qm ignore
    printf 'junk\n' > "$factory/skills/flow-tdd/.DS_Store"
    run_install "$h" "$factory"
    expect_status 0
    [ ! -e "$h/.claude/skills/flow-tdd/.DS_Store" ] || fail "a git-ignored file was placed"
    ! grep -q '\.DS_Store' "$h/.flow-factory/install-record.txt" || fail "a git-ignored file was recorded"
}

case_linked_machine_file_stops_a_copy_run() {
    local h target
    h=$(new_home)
    target="$SCRATCH/$CASE/checkout-copy.md"
    printf 'mine\n' > "$target"
    mkdir -p "$h/.flow-factory"
    ln -s "$target" "$h/.flow-factory/tracker-contract.md"
    expect_stop_writing_nothing "$h"
    expect_line "~/.flow-factory/tracker-contract.md is a link"
    expect_line "./install --link"
    [ "$(cat "$target")" = mine ] || fail "the install wrote through the link"
}

case_linked_machine_directory_stops_a_copy_run() {
    local h target
    h=$(new_home)
    target="$SCRATCH/$CASE/checkout-templates"
    mkdir -p "$h/.flow-factory"
    cp -R "$FACTORY/machine/templates" "$target"
    printf 'mine\n' > "$target/ticket.md"
    ln -s "$target" "$h/.flow-factory/templates"
    expect_stop_writing_nothing "$h"
    expect_line "~/.flow-factory/templates is a link"
    expect_line "./install --link"
    [ "$(cat "$target/ticket.md")" = mine ] || fail "the install wrote through the linked directory"
}

case_home_with_trailing_slash_installs() {
    local h
    h=$(new_home)
    run_install "$h/"
    expect_status 0
    refuse_line "left alone"
    [ -f "$h/.flow-factory/tracker-contract.md" ] || fail "no machine file placed"
    # A rerun with HOME spelled the plain way still finds its own record.
    run_install "$h"
    expect_status 0
    refuse_line "left alone"
}

case_linked_machine_dir_stops_writing_nothing() {
    local h target
    h=$(new_home)
    target="$SCRATCH/$CASE/elsewhere"
    mkdir -p "$target"
    ln -s "$target" "$h/.flow-factory"
    expect_stop_writing_nothing "$h"
    [ -z "$(ls -A "$target")" ] || fail "the install wrote into the link target"
    expect_line "~/.flow-factory is a link"
}

case_nothing_placed_is_not_reported_as_checked() {
    local h name
    h=$(new_home)
    for name in $(shipped); do
        mkdir -p "$h/.claude/skills/$name"
        printf 'old copy\n' > "$h/.claude/skills/$name/SKILL.md"
    done
    run_install "$h"
    expect_status 0
    refuse_line "every reference resolves"
    expect_line "no skill was placed"
}

# Run the install with any further arguments, from FACTORY_UNDER_TEST when it
# is set, and expect a stop that leaves HOME $1 exactly as it was, each link
# still a link to the same path.
expect_stop_writing_nothing() {
    local h=$1
    shift
    rm -rf -- "$h.before"
    cp -Rp "$h" "$h.before"
    run_install "$h" "${FACTORY_UNDER_TEST:-$CHECKOUT}" "$@"
    [ "$STATUS" -ne 0 ] || fail "exit 0, expected a stop"
    diff -r --no-dereference "$h.before" "$h" >/dev/null || fail "HOME changed. Output:
$(cat "$OUT")"
}

# The link leads to a copy of this case's own, so a run that wrote through it
# would change that copy and not the checkout later cases install from.
case_copy_run_stops_on_an_unrecorded_linked_skill() {
    local h theirs
    h=$(new_home)
    theirs="$SCRATCH/$CASE/flow-park"
    cp -R "$CHECKOUT/skills/flow-park" "$theirs"
    mkdir -p "$h/.claude/skills"
    ln -s "$theirs" "$h/.claude/skills/flow-park"
    # HOME has no ~/.flow-factory yet, so the stop comes before it is made.
    expect_stop_writing_nothing "$h"
    diff -r "$CHECKOUT/skills/flow-park" "$theirs" >/dev/null || fail "the run wrote through the link"
    expect_line "~/.claude/skills/flow-park is a link"
    expect_line "./install --link"
}

# Blocks the replace a recorded skill gets, which put a copy over the link.
case_copy_run_stops_on_a_recorded_skill_swapped_for_a_link() {
    local h theirs
    h=$(new_home)
    theirs="$SCRATCH/$CASE/flow-park"
    cp -R "$CHECKOUT/skills/flow-park" "$theirs"
    run_install "$h"
    expect_status 0
    rm -rf -- "$h/.claude/skills/flow-park"
    ln -s "$theirs" "$h/.claude/skills/flow-park"
    expect_stop_writing_nothing "$h"
    diff -r "$CHECKOUT/skills/flow-park" "$theirs" >/dev/null || fail "the run wrote through the link"
    expect_line "~/.claude/skills/flow-park is a link"
    expect_line "./install --link"
}

# The copy step removes each recorded skill before copying it, so through such
# a link it would delete the checkout's own sources.
case_skills_dir_that_is_the_checkouts_stops_writing_nothing() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    rm -rf -- "$h/.claude/skills"
    ln -s "$factory/skills" "$h/.claude/skills"
    FACTORY_UNDER_TEST=$factory expect_stop_writing_nothing "$h"
    [ -z "$(git -C "$factory" status --porcelain -- skills)" ] || fail "the checkout's skills changed"
    expect_line "~/.claude/skills is this checkout's skills/"
}

case_something_in_the_way_of_a_machine_file_stops_writing_nothing() {
    local h
    h=$(new_home home-copy)
    mkdir -p "$h/.flow-factory/tracker-contract.md"
    expect_stop_writing_nothing "$h"
    expect_line "~/.flow-factory/tracker-contract.md is a directory where a file goes"
    h=$(new_home home-link)
    mkdir -p "$h/.flow-factory/tracker-contract.md"
    expect_stop_writing_nothing "$h" --link
    expect_line "~/.flow-factory/tracker-contract.md is a directory where a file goes"
    h=$(new_home home-file)
    mkdir -p "$h/.flow-factory"
    printf 'not a directory\n' > "$h/.flow-factory/templates"
    expect_stop_writing_nothing "$h" --link
    expect_line "~/.flow-factory/templates is a file where a directory goes"
    h=$(new_home home-dangling)
    mkdir -p "$h/.flow-factory"
    ln -s "$SCRATCH/$CASE/removed-worktree/machine/templates" "$h/.flow-factory/templates"
    expect_stop_writing_nothing "$h" --link
    expect_line "~/.flow-factory/templates is a link to nothing"
    h=$(new_home home-machine-file)
    printf 'not a directory\n' > "$h/.flow-factory"
    expect_stop_writing_nothing "$h" --link
    expect_line "~/.flow-factory is not a directory"
}

# An update can turn a machine file into a directory, or back. What the earlier
# run placed there is withdrawn and removed first, so it is never in the way.
case_update_turns_a_machine_file_into_a_directory_and_back() {
    local mode h o factory
    for mode in copy link; do
        o="$SCRATCH/$CASE/$mode/origin"
        factory=$(make_factory "$SCRATCH/$CASE/$mode")
        h=$(new_home "home-$mode")
        printf 'one\n' > "$o/machine/extra"
        git -C "$o" add -A && git -C "$o" "${GIT_ID[@]}" commit -qm "ship a file"
        install_in_mode "$mode" "$h" "$factory"
        rm -- "$o/machine/extra"
        mkdir "$o/machine/extra" && printf 'one\n' > "$o/machine/extra/one.md"
        git -C "$o" add -A && git -C "$o" "${GIT_ID[@]}" commit -qm "a directory now"
        install_in_mode "$mode" "$h" "$factory"
        expect_line "removed extra, no longer shipped"
        placed_in_mode "$mode" "$h/.flow-factory/extra/one.md" "$factory/machine/extra/one.md"
        grep -qx "file $h/.flow-factory/extra/one.md" "$h/.flow-factory/install-record.txt" \
            || fail "the record does not list extra/one.md in $mode mode"
        rm -r -- "$o/machine/extra" && printf 'one\n' > "$o/machine/extra"
        git -C "$o" add -A && git -C "$o" "${GIT_ID[@]}" commit -qm "a file again"
        install_in_mode "$mode" "$h" "$factory"
        expect_line "removed extra/one.md, no longer shipped"
        placed_in_mode "$mode" "$h/.flow-factory/extra" "$factory/machine/extra"
    done
}

# Run the install under HOME $2 from checkout $3 in mode $1, copy or link, and
# expect it to pass.
install_in_mode() {
    if [ "$1" = link ]; then run_install "$2" "$3" --link; else run_install "$2" "$3"; fi
    expect_status 0
}

# Expect $2 to be what mode $1 places for source $3: a copy, or a link to it.
placed_in_mode() {
    if [ "$1" = link ]; then
        [ -L "$2" ] && [ "$2" -ef "$3" ] || fail "$2 is not a link to $3"
    else
        [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$3" "$2" || fail "$2 is not a copy of $3"
    fi
}

# The removal of withdrawn files cannot empty a directory that holds a folder
# of the person's own, so that directory is in the way, and says so first.
case_update_stops_when_a_withdrawn_directory_holds_a_persons_folder() {
    local h factory o="$SCRATCH/$CASE/origin"
    h=$(new_home)
    factory=$(copy_factory)
    mkdir "$o/machine/extra" && printf 'one\n' > "$o/machine/extra/one.md"
    commit_origin "ship a directory"
    run_install "$h" "$factory"
    expect_status 0
    mkdir "$h/.flow-factory/extra/drafts"
    rm -r -- "$o/machine/extra" && printf 'one\n' > "$o/machine/extra"
    commit_origin "a file now"
    # The pull that brings the change runs first, and writes only the checkout.
    git -C "$factory" pull -q --ff-only
    FACTORY_UNDER_TEST=$factory expect_stop_writing_nothing "$h"
    expect_line "~/.flow-factory/extra is a directory where a file goes"
}

# A path an earlier run placed that the person has since made a folder is not
# removed, so what the folder holds is checked like anything else.
case_update_stops_on_what_a_recorded_path_now_holds() {
    local h factory o="$SCRATCH/$CASE/origin"
    h=$(new_home)
    factory=$(copy_factory)
    printf 'one\n' > "$o/machine/extra"
    commit_origin "ship a file"
    run_install "$h" "$factory"
    expect_status 0
    rm -- "$h/.flow-factory/extra"
    mkdir "$h/.flow-factory/extra" && printf 'mine\n' > "$h/.flow-factory/extra/sub"
    rm -- "$o/machine/extra" && mkdir -p "$o/machine/extra/sub" && printf 'x\n' > "$o/machine/extra/sub/x.md"
    commit_origin "a directory now"
    git -C "$factory" pull -q --ff-only
    FACTORY_UNDER_TEST=$factory expect_stop_writing_nothing "$h"
    expect_line "~/.flow-factory/extra/sub is a file where a directory goes"
}

# ---------------------------------------------------------------------------
# Link mode: ./install --link, for the machine that builds the factory.

# The record lists the links, never a file behind one: rm -f on such a path
# deletes the checkout's own file through the link.
case_link_install_links_every_entry_and_records_the_links() {
    local h rec name rel dest expected=""
    h=$(new_home)
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    grep -qx 'mode link' "$rec" || fail "no line 'mode link'"
    for name in $(shipped); do
        dest="$h/.claude/skills/$name"
        [ -L "$dest" ] && [ "$dest" -ef "$CHECKOUT/skills/$name" ] \
            || fail "~/.claude/skills/$name is not a link to the checkout's skills/$name"
        expected+="file $dest"$'\n'
    done
    while IFS= read -r rel; do
        dest="$h/.flow-factory/$rel"
        [ -L "$dest" ] && [ "$dest" -ef "$CHECKOUT/machine/$rel" ] \
            || fail "~/.flow-factory/$rel is not a link to the checkout's machine/$rel"
        expected+="file $dest"$'\n'
    done < <(machine_files)
    [ "$(grep '^file ' "$rec" | sort)" = "$(printf '%s' "$expected" | sort)" ] \
        || fail "the record's file lines are not the links placed:
$(diff <(printf '%s' "$expected" | sort) <(grep '^file ' "$rec" | sort))"
}

case_second_link_run_changes_nothing() {
    local h rec name rel
    h=$(new_home)
    rec="$h/.flow-factory/install-record.txt"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    grep '^file ' "$rec" > "$SCRATCH/$CASE/files.before"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    for name in $(shipped); do expect_line "  unchanged $name"; done
    while IFS= read -r rel; do expect_line "  unchanged $rel"; done < <(machine_files)
    refuse_line "linked "
    grep '^file ' "$rec" | cmp -s "$SCRATCH/$CASE/files.before" - \
        || fail "the second run changed the record's file lines"
}

# The dev machine's statusline.sh once pointed into a worktree, not at main.
case_link_run_leaves_a_foreign_link_alone() {
    local h theirs rec
    h=$(new_home)
    theirs="$SCRATCH/$CASE/theirs"
    mkdir -p "$theirs/flow-park" "$h/.claude/skills" "$h/.flow-factory"
    printf 'mine\n' | tee "$theirs/flow-park/SKILL.md" "$theirs/contract.md" "$SCRATCH/$CASE/before" >/dev/null
    ln -s "$theirs/flow-park" "$h/.claude/skills/flow-park"
    ln -s "$theirs/contract.md" "$h/.flow-factory/tracker-contract.md"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    expect_line "left alone flow-park, a link to $theirs/flow-park"
    expect_line "left alone tracker-contract.md, a link to $theirs/contract.md"
    [ "$(readlink "$h/.claude/skills/flow-park")" = "$theirs/flow-park" ] || fail "the flow-park link was changed"
    [ "$(readlink "$h/.flow-factory/tracker-contract.md")" = "$theirs/contract.md" ] \
        || fail "the tracker-contract.md link was changed"
    cmp -s "$SCRATCH/$CASE/before" "$theirs/flow-park/SKILL.md" || fail "flow-park's target changed"
    cmp -s "$SCRATCH/$CASE/before" "$theirs/contract.md" || fail "tracker-contract.md's target changed"
    rec="$h/.flow-factory/install-record.txt"
    ! grep -qE "^file $h/(.claude/skills/flow-park|.flow-factory/tracker-contract.md)\$" "$rec" \
        || fail "the record claims a link this run left alone"
}

# A pull that moves HEAD hands over to the pulled installer. Without the flag
# that run is a copy run, and on a fresh HOME it places copies without a word.
case_link_run_that_pulls_stays_in_link_mode() {
    local h factory name rel
    h=$(new_home)
    factory=$(copy_factory)
    printf '\nA line the pull brings.\n' >> "$SCRATCH/$CASE/origin/machine/tracker-contract.md"
    commit_origin "change a contract"
    run_install "$h" "$factory" --link
    expect_status 0
    expect_line "pulled "
    grep -qx 'mode link' "$h/.flow-factory/install-record.txt" || fail "the pulled installer ran as a copy run"
    for name in $(shipped); do
        [ -L "$h/.claude/skills/$name" ] || fail "~/.claude/skills/$name is not a link"
    done
    while IFS= read -r rel; do
        [ -L "$h/.flow-factory/$rel" ] || fail "~/.flow-factory/$rel is not a link"
    done < <(machine_files)
}

# In link mode every skill directory is a link, and a check that does not
# follow links reads nothing there and reports a pass.
case_link_run_final_check_finds_a_broken_reference() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    printf '\nWhen done, run /flow-gone.\n' >> "$factory/skills/flow-tdd/SKILL.md"
    run_install "$h" "$factory" --link
    [ "$STATUS" -ne 0 ] || fail "exit 0 with a reference to an unshipped skill"
    expect_line "skill referenced but not installed: flow-gone"
}

# Switching an install from copies to links is not done in place.
case_link_run_stops_over_recorded_copies() {
    local h
    h=$(new_home)
    run_install "$h"
    expect_status 0
    expect_stop_writing_nothing "$h" --link
    expect_line "~/.claude/skills/flow-park is a copy an earlier run placed"
    expect_line "~/.flow-factory/tracker-contract.md is a copy an earlier run placed"
}

# A removed worktree leaves every link it placed leading nowhere. A live link
# elsewhere may be a person testing a branch, so it stays.
case_link_run_replaces_the_dangling_links_it_placed() {
    local h factory theirs name rel
    h=$(new_home)
    factory=$(copy_factory)
    theirs="$SCRATCH/$CASE/theirs"
    run_install "$h" "$factory" --link
    expect_status 0
    cp -R "$CHECKOUT/skills/flow-park" "$theirs"
    ln -sfn "$theirs" "$h/.claude/skills/flow-park"
    rm -rf -- "$factory"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    expect_line "left alone flow-park, a link to $theirs"
    expect_line "replaced  flow-tdd, a link to nothing"
    expect_line "replaced  tracker-contract.md, a link to nothing"
    for name in $(shipped); do
        [ "$name" = flow-park ] || [ "$h/.claude/skills/$name" -ef "$CHECKOUT/skills/$name" ] \
            || fail "~/.claude/skills/$name does not lead to the checkout"
    done
    while IFS= read -r rel; do
        [ "$h/.flow-factory/$rel" -ef "$CHECKOUT/machine/$rel" ] \
            || fail "~/.flow-factory/$rel does not lead to the checkout"
    done < <(machine_files)
    [ "$(readlink "$h/.claude/skills/flow-park")" = "$theirs" ] || fail "the live link was re-pointed"
    # A later uninstall removes what the record lists.
    ! grep -qx "file $h/.claude/skills/flow-park" "$h/.flow-factory/install-record.txt" \
        || fail "the record still claims the link left alone"
}

# A link run's line for a skill vouches for the link it placed. Once the link
# is moved aside, the directory a person makes there is theirs.
case_copy_run_leaves_a_directory_where_a_link_run_placed_a_link() {
    local h
    h=$(new_home)
    mkdir -p "$h/.claude/skills/flow-park" "$h/.flow-factory"
    printf 'mine\n' > "$h/.claude/skills/flow-park/NOTES.md"
    printf 'mode link\nfile %s\n' "$h/.claude/skills/flow-park" > "$h/.flow-factory/install-record.txt"
    run_install "$h"
    expect_status 0
    expect_line "left alone flow-park, which this installer did not place"
    [ "$(cat "$h/.claude/skills/flow-park/NOTES.md")" = mine ] || fail "the person's flow-park was replaced"
}

# With no record at all, the dead link would otherwise be left alone, and the
# final check would fail after every write.
case_link_run_replaces_an_unrecorded_dangling_link() {
    local h
    h=$(new_home)
    mkdir -p "$h/.claude/skills"
    ln -s "$SCRATCH/$CASE/removed-worktree/skills/flow-park" "$h/.claude/skills/flow-park"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    expect_line "replaced  flow-park, a link to nothing"
    [ "$h/.claude/skills/flow-park" -ef "$CHECKOUT/skills/flow-park" ] || fail "flow-park does not lead to the checkout"
}

# A linked directory of machine files is someone's checkout, and the record
# must not name files behind it. What that checkout holds, even a directory
# where the factory places a file, is not the run's to stop on.
case_link_run_leaves_files_behind_a_linked_directory_alone() {
    local h theirs
    h=$(new_home)
    theirs="$SCRATCH/$CASE/templates"
    cp -R "$CHECKOUT/machine/templates" "$theirs"
    printf 'mine\n' > "$theirs/ticket.md"
    rm -- "$theirs/spec.md" && mkdir "$theirs/spec.md"
    mkdir -p "$h/.flow-factory"
    ln -s "$theirs" "$h/.flow-factory/templates"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    expect_line "left alone templates/ticket.md, behind a link this installer does not write through"
    expect_line "left alone templates/spec.md, behind a link this installer does not write through"
    [ "$(cat "$theirs/ticket.md")" = mine ] || fail "the run wrote through the linked directory"
    ! grep -q "^file $h/.flow-factory/templates/" "$h/.flow-factory/install-record.txt" \
        || fail "the record names files behind a link"
}

# A dev machine's stage.sh, placed by hand, is such a plain copy.
case_link_run_replaces_a_plain_machine_file_with_a_link() {
    local h
    h=$(new_home)
    mkdir -p "$h/.flow-factory"
    cp "$CHECKOUT/machine/stage.sh" "$h/.flow-factory/stage.sh"
    printf 'an old copy\n' > "$h/.flow-factory/tracker-contract.md"
    run_install "$h" "$CHECKOUT" --link
    expect_status 0
    expect_line "  linked    stage.sh"
    expect_line "  OVERWROTE tracker-contract.md"
    [ -L "$h/.flow-factory/stage.sh" ] && [ -L "$h/.flow-factory/tracker-contract.md" ] \
        || fail "a plain machine file was not replaced by a link"
}

# From another checkout every live link would be left alone, and the record
# rewritten to name the checkout nothing leads to.
case_link_run_from_another_checkout_stops_writing_nothing() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory" --link
    expect_status 0
    expect_stop_writing_nothing "$h" --link
    expect_line "this machine is linked to the checkout $factory"
}

# A Finder .DS_Store in a linked skill makes macOS sed abort under a UTF-8
# locale, and the check then reads nothing after it.
case_link_run_final_check_reads_past_a_binary_file() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    printf '\0\0\0\1Bud1\377\376\200\201\0' > "$factory/skills/flow-ask/.DS_Store"
    printf '\nWhen done, run /flow-gone.\n' >> "$factory/skills/flow-tdd/SKILL.md"
    # LC_ALL, which overrides any locale the environment sets.
    LC_ALL=en_US.UTF-8 run_install "$h" "$factory" --link
    [ "$STATUS" -ne 0 ] || fail "exit 0 with a reference to an unshipped skill"
    expect_line "skill referenced but not installed: flow-gone"
}

# The old installer took the project as its argument. That habit must not
# quietly run a machine install instead.
case_unknown_argument_stops_writing_nothing() {
    local h arg
    h=$(new_home)
    cp -Rp "$h" "$h.before"
    # The empty argument is an unset variable in `./install "$PROJECT"`.
    for arg in "$SCRATCH/$CASE" ""; do
        run_install "$h" "$CHECKOUT" "$arg"
        [ "$STATUS" -ne 0 ] || fail "exit 0 with the argument '$arg'"
        diff -r "$h.before" "$h" >/dev/null || fail "HOME changed with the argument '$arg'"
        expect_line "usage: ./install"
    done
    run_install "$h" "$CHECKOUT" --link "$SCRATCH/$CASE"
    [ "$STATUS" -ne 0 ] || fail "exit 0 with --link and a project"
    diff -r "$h.before" "$h" >/dev/null || fail "HOME changed with --link and a project"
    expect_line "usage: ./install"
}

case_stops_without_claude_code() {
    local h
    h=$(new_home)
    rmdir "$h/.claude"
    printf 'keep\n' > "$h/.profile"
    expect_stop_writing_nothing "$h"
    expect_line "Claude Code"
}

case_stops_without_git() {
    local h bin f
    h=$(new_home)
    # Every command this machine has, except git.
    bin="$SCRATCH/$CASE/bin"
    mkdir -p "$bin"
    for f in /bin/* /usr/bin/*; do
        case $(basename -- "$f") in git|git-*) continue ;; esac
        [ -e "$bin/$(basename -- "$f")" ] || ln -s "$f" "$bin/"
    done
    PATH="$bin" expect_stop_writing_nothing "$h"
    expect_line "git is not on PATH"
}

case_new_skills_dir_says_restart_first() {
    local h
    h=$(new_home)
    run_install "$h"
    expect_status 0
    expect_line "Next: restart Claude Code first, then fit a project with ./install --init."
    expect_line "/fewer-permission-prompts"
}

case_existing_skills_dir_says_no_restart() {
    local h
    h=$(new_home)
    mkdir "$h/.claude/skills"
    run_install "$h"
    expect_status 0
    expect_line "Next: fit a project with ./install --init."
    refuse_line "restart"
    expect_line "/fewer-permission-prompts"
}

# ---------------------------------------------------------------------------
# Update: a second ./install pulls the checkout and places what it pulled.

# Install under HOME $1 from checkout $2, whose origin ships a skill
# flow-release, then withdraw flow-release in the origin.
install_then_withdraw() {
    local h=$1 factory=$2 o="$SCRATCH/$CASE/origin"
    mkdir -p "$o/skills/flow-release/references"
    printf 'Cut a release.\n' > "$o/skills/flow-release/SKILL.md"
    printf 'notes\n' > "$o/skills/flow-release/references/notes.md"
    commit_origin "ship flow-release"
    run_install "$h" "$factory"
    expect_status 0
    [ -f "$h/.claude/skills/flow-release/SKILL.md" ] || fail "flow-release was not placed"
    rm -rf -- "$o/skills/flow-release"
    commit_origin "withdraw flow-release"
}

case_update_removes_a_withdrawn_skill() {
    local h factory n
    h=$(new_home)
    factory=$(copy_factory)
    install_then_withdraw "$h" "$factory"
    run_install "$h" "$factory"
    expect_status 0
    expect_line "pulled "
    expect_line "removed flow-release, no longer shipped"
    refuse_line "left alone flow-release"
    [ ! -e "$h/.claude/skills/flow-release" ] || fail "flow-release is still on disk"
    ! grep -q '/flow-release/' "$h/.flow-factory/install-record.txt" || fail "the record still lists flow-release"
    n=0
    for d in "$h/.claude/skills"/flow-*/; do n=$((n + 1)); done
    [ "$n" -eq "$(shipped | wc -l)" ] || fail "$n flow-* directories, expected $(shipped | wc -l)"
}

# Blocks deleting every flow-* directory that has no source.
case_update_keeps_an_unrecorded_skill() {
    local h factory mine
    h=$(new_home)
    factory=$(copy_factory)
    install_then_withdraw "$h" "$factory"
    mine="$h/.claude/skills/flow-mine"
    mkdir -p "$mine"
    printf 'my own\n' > "$mine/SKILL.md"
    cp -p "$mine/SKILL.md" "$SCRATCH/$CASE/flow-mine.before"
    run_install "$h" "$factory"
    expect_status 0
    cmp -s "$SCRATCH/$CASE/flow-mine.before" "$mine/SKILL.md" || fail "flow-mine changed or is gone"
}

case_update_overwrites_a_changed_machine_file() {
    local h factory o="$SCRATCH/$CASE/origin"
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    printf '\nA new rule.\n' >> "$o/machine/tracker-contract.md"
    commit_origin "change the tracker contract"
    run_install "$h" "$factory"
    expect_status 0
    expect_line "OVERWROTE tracker-contract.md"
    expect_line "unchanged settings-contract.md"
    cmp -s "$o/machine/tracker-contract.md" "$h/.flow-factory/tracker-contract.md" \
        || fail "tracker-contract.md is not the origin's"
}

# Commit to this case's origin an install whose closing line differs.
change_origin_installer() {
    local o="$SCRATCH/$CASE/origin"
    # cat into the file keeps its mode, which a mv of a new file would lose.
    sed 's/^say "Install complete."$/say "Install complete, by the pulled installer."/' "$o/install" \
        > "$SCRATCH/$CASE/install.new"
    cat "$SCRATCH/$CASE/install.new" > "$o/install"
    commit_origin "change the installer"
}

# Blocks an update that places the new files with the old installer.
case_update_runs_the_pulled_installer_once() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    change_origin_installer
    run_install "$h" "$factory"
    expect_status 0
    expect_line "taken without asking: FLOW_FACTORY_UPDATE=yes"
    expect_line "Install complete, by the pulled installer."
    [ "$(grep -c '^== Update the checkout' "$OUT")" -eq 1 ] || fail "the run pulled more than once. Output:
$(cat "$OUT")"
}

# The merge that takes an update can land and still exit non-zero, in a hook.
# The tree is new, so the new installer must place it.
case_update_hands_over_after_a_pull_that_lands_and_fails() {
    local h factory bin
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    change_origin_installer
    bin="$SCRATCH/$CASE/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\n"%s" "$@" || exit\ncase " $* " in *" merge "*) exit 1 ;; esac\n' "$(command -v git)" > "$bin/git"
    chmod +x "$bin/git"
    PATH="$bin:$PATH" run_install "$h" "$factory"
    expect_status 0
    expect_line "Install complete, by the pulled installer."
}

# With no terminal and no FLOW_FACTORY_UPDATE=yes, an update is shown and left
# where it is, and the checkout is installed as it stands. A second run must
# not take it either: the checkout never moved, so it is shown again.
case_update_without_a_terminal_is_shown_and_not_taken() {
    local h factory before
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    change_origin_installer
    before=$(git -C "$factory" rev-parse HEAD)
    FLOW_FACTORY_UPDATE='' run_install "$h" "$factory"
    expect_status 0
    expect_line "1 commit(s) ahead of this checkout:"
    expect_line "change the installer"
    expect_line "not pulled: there is no terminal to ask at"
    expect_line "Install complete."
    refuse_line "pulled installer"
    [ "$(git -C "$factory" rev-parse HEAD)" = "$before" ] || fail "the checkout moved"
    FLOW_FACTORY_UPDATE='' run_install "$h" "$factory"
    expect_status 0
    expect_line "not pulled: there is no terminal to ask at"
    [ "$(git -C "$factory" rev-parse HEAD)" = "$before" ] || fail "the second run moved the checkout"
}

# At a terminal the update is asked about, and a no leaves the checkout where it
# was and installs it as it stands.
case_update_declined_at_a_terminal_is_not_taken() {
    local h factory before
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    change_origin_installer
    before=$(git -C "$factory" rev-parse HEAD)
    run_install_at_terminal "$h" "$factory" n
    expect_status 0
    expect_line "Install this update? [y/N]"
    expect_line "not pulled: the update was declined"
    expect_line "Install complete."
    refuse_line "pulled installer"
    [ "$(git -C "$factory" rev-parse HEAD)" = "$before" ] || fail "the checkout moved"
}

# A yes at the terminal takes the update and hands over to the new installer.
case_update_approved_at_a_terminal_is_taken() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    change_origin_installer
    run_install_at_terminal "$h" "$factory" y
    expect_status 0
    expect_line "Install this update? [y/N]"
    expect_line "pulled "
    expect_line "Install complete, by the pulled installer."
    [ "$(git -C "$factory" rev-parse HEAD)" = "$(git -C "$SCRATCH/$CASE/origin" rev-parse HEAD)" ] \
        || fail "the checkout is not at the origin's commit"
}

case_update_leaves_a_recorded_project_alone() {
    local h factory p o="$SCRATCH/$CASE/origin"
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    p=$(new_project)
    run_install "$h" "$factory" --init "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    cp -p "$p/flow-factory.toml" "$SCRATCH/$CASE/settings.before"
    # A template change an update must not carry into the project.
    printf '\n# A new key.\n' >> "$o/project/flow-factory.toml"
    commit_origin "change the template"
    run_install "$h" "$factory"
    expect_status 0
    expect_line "pulled "
    cmp -s "$SCRATCH/$CASE/settings.before" "$p/flow-factory.toml" || fail "the project's flow-factory.toml changed"
    grep -qxF "project $p" "$h/.flow-factory/install-record.txt" || fail "the update dropped the project line"
}

case_update_on_a_diverged_checkout_installs_it_as_it_stands() {
    local PULL_MAY_FAIL=1 h factory o="$SCRATCH/$CASE/origin"
    h=$(new_home)
    factory=$(copy_factory)
    printf 'origin\n' > "$o/skills/flow-tdd/origin-note.md"
    commit_origin "ahead"
    printf 'local\n' > "$factory/skills/flow-tdd/local-note.md"
    git -C "$factory" add -A
    git -C "$factory" "${GIT_ID[@]}" commit -qm local
    run_install "$h" "$factory"
    expect_status 0
    expect_line "$PULL_FAILED"
    expect_line "installed as it stands"
    grep -qxF "version $(git -C "$factory" describe --tags --always)" "$h/.flow-factory/install-record.txt" \
        || fail "the record's version is not $(git -C "$factory" describe --tags --always)"
    [ -f "$h/.claude/skills/flow-tdd/local-note.md" ] || fail "the checkout was not installed as it stands"
}

case_update_removes_withdrawn_links_without_following_them() {
    local h rec gone target
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    gone="$h/.claude/skills/flow-gone"
    target="$SCRATCH/$CASE/target.md"
    printf 'mine\n' > "$target"
    cp -p "$target" "$target.before"
    mkdir -p "$gone"
    ln -s "$target" "$gone/SKILL.md"
    ln -s "$SCRATCH/$CASE/missing.md" "$gone/extra.md"
    ln -s "$SCRATCH/$CASE/missing.md" "$h/.flow-factory/old-contract.md"
    printf 'file %s\n' "$gone/SKILL.md" "$gone/extra.md" "$h/.flow-factory/old-contract.md" >> "$rec"
    run_install "$h"
    expect_status 0
    expect_line "removed flow-gone, no longer shipped"
    expect_line "removed old-contract.md, no longer shipped"
    [ ! -e "$gone" ] && [ ! -L "$gone" ] || fail "flow-gone is still on disk"
    [ ! -L "$h/.flow-factory/old-contract.md" ] || fail "the dangling old-contract.md is still on disk"
    cmp -s "$target.before" "$target" || fail "the link's target changed"
    ! grep -qE 'flow-gone|old-contract' "$rec" || fail "the record still lists a removed file"
}

case_update_removes_a_withdrawn_skill_holding_a_ds_store() {
    local h factory
    h=$(new_home)
    factory=$(copy_factory)
    install_then_withdraw "$h" "$factory"
    printf 'view\n' > "$h/.claude/skills/flow-release/references/.DS_Store"
    printf 'view\n' > "$h/.claude/skills/flow-release/.DS_Store"
    run_install "$h" "$factory"
    expect_status 0
    [ ! -e "$h/.claude/skills/flow-release" ] || fail "flow-release is still on disk"
    refuse_line "kept ~/.claude/skills/flow-release"
}

# A removal that fails must stop the run, not report the file removed.
case_update_stops_when_a_withdrawn_file_cannot_be_removed() {
    local h rec locked
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    locked="$h/.claude/skills/flow-gone"
    mkdir -p "$locked"
    printf 'old\n' > "$locked/SKILL.md"
    printf 'file %s\n' "$locked/SKILL.md" >> "$rec"
    chmod a-w "$locked"
    run_install "$h"
    chmod u+w "$locked"
    [ "$STATUS" -ne 0 ] || fail "exit 0 with a file it could not remove"
    expect_line "cannot remove $locked/SKILL.md"
    refuse_line "removed flow-gone"
}

case_update_leaves_a_recorded_path_with_dot_dot_alone() {
    local h
    h=$(new_home)
    run_install "$h"
    expect_status 0
    printf 'mine\n' > "$h/victim.txt"
    printf 'file %s\n' "$h/.flow-factory/../victim.txt" >> "$h/.flow-factory/install-record.txt"
    run_install "$h"
    expect_status 0
    expect_line "left alone $h/.flow-factory/../victim.txt"
    [ -f "$h/victim.txt" ] || fail "a file outside the factory's directories was removed"
}

# A factory inside another repository must not pull that repository.
case_update_never_pulls_a_repository_the_factory_sits_in() {
    local h outer before
    h=$(new_home)
    outer="$SCRATCH/$CASE/outer"
    mkdir -p "$outer/origin/vendor"
    cp -R "$(dirname -- "$CHECKOUT")/origin/." "$outer/origin/vendor/factory"
    rm -rf -- "$outer/origin/vendor/factory/.git"
    git -C "$outer/origin" -c init.defaultBranch=main init -q
    git -C "$outer/origin" add -A
    git -C "$outer/origin" "${GIT_ID[@]}" commit -qm outer
    git clone -q "$outer/origin" "$outer/clone"
    printf 'later\n' > "$outer/origin/later.txt"
    git -C "$outer/origin" add -A
    git -C "$outer/origin" "${GIT_ID[@]}" commit -qm later
    before=$(git -C "$outer/clone" rev-parse HEAD)
    run_install "$h" "$outer/clone/vendor/factory"
    expect_status 0
    expect_line "not pulled: the factory is not the top level of a checkout"
    [ "$(git -C "$outer/clone" rev-parse HEAD)" = "$before" ] || fail "the install pulled the outer repository"
}

# rm -f refuses a directory, and under set -e that would stop every later
# install at the same path.
case_update_leaves_a_directory_where_a_withdrawn_file_was() {
    local h rec
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    mkdir -p "$h/.flow-factory/old-contract.md" "$h/.claude/skills/flow-gone/notes"
    printf 'mine\n' > "$h/.claude/skills/flow-gone/notes/mine.md"
    printf 'file %s\n' "$h/.flow-factory/old-contract.md" "$h/.claude/skills/flow-gone/notes" >> "$rec"
    run_install "$h"
    expect_status 0
    expect_line "left alone old-contract.md, no longer shipped, now a directory"
    expect_line "left alone flow-gone/notes, no longer shipped, now a directory"
    [ -f "$h/.claude/skills/flow-gone/notes/mine.md" ] || fail "a file in the directory is gone"
    ! grep -qE 'old-contract|flow-gone' "$rec" || fail "the record still claims a directory"
}

# rm -f on the path would follow the directory link and delete a file in
# someone's own checkout.
case_update_leaves_withdrawn_files_behind_a_linked_directory() {
    local h rec notes theirs refs
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    # A machine directory, a skill directory and a directory inside a skill,
    # each a link into someone's checkout.
    notes="$SCRATCH/$CASE/their-notes"
    theirs="$SCRATCH/$CASE/their-skill"
    refs="$SCRATCH/$CASE/their-references"
    mkdir -p "$notes" "$theirs" "$refs" "$h/.claude/skills/flow-gone2"
    printf 'mine\n' | tee "$notes/notes.md" "$theirs/SKILL.md" "$refs/a.md" "$SCRATCH/$CASE/before" >/dev/null
    ln -s "$notes" "$h/.flow-factory/old"
    ln -s "$theirs" "$h/.claude/skills/flow-gone"
    ln -s "$refs" "$h/.claude/skills/flow-gone2/references"
    printf 'file %s\n' "$h/.flow-factory/old/notes.md" "$h/.claude/skills/flow-gone/SKILL.md" \
        "$h/.claude/skills/flow-gone2/references/a.md" >> "$rec"
    run_install "$h"
    expect_status 0
    expect_line "left alone old/notes.md, no longer shipped"
    expect_line "left alone flow-gone, no longer shipped"
    expect_line "left alone flow-gone2/references/a.md, no longer shipped"
    for f in "$notes/notes.md" "$theirs/SKILL.md" "$refs/a.md"; do
        cmp -s "$SCRATCH/$CASE/before" "$f" || fail "$f changed"
    done
}

# ---------------------------------------------------------------------------
# Project mode: ./install --init <project root> <answers file>

# A HOME with the factory installed, as --init needs.
installed_home() {
    local h
    h=$(new_home)
    run_install "$h"
    expect_status 0
    printf '%s' "$h"
}

# A scratch repository with one commit on branch trunk. The commit holds a
# .gitignore, so a write to it would show.
new_project() {
    local p="$SCRATCH/$CASE/${1:-project}"
    mkdir -p "$p"
    git -C "$p" -c init.defaultBranch=trunk init -q
    printf 'node_modules/\n' > "$p/.gitignore"
    git -C "$p" add .gitignore
    git -C "$p" "${GIT_ID[@]}" commit -qm first
    printf '%s' "$p"
}

# An answers file holding one line per argument.
answers() {
    local a="$SCRATCH/$CASE/answers.toml"
    printf '%s\n' "$@" > "$a"
    printf '%s' "$a"
}

# Both answers differ from the template on purpose: an answer equal to the
# template's value would not show in a diff.
WORKED_EXAMPLE=('git.default_branch = "trunk"' 'test.command = "npm test"')

expect_gitignore_untouched() {
    git -C "$1" diff --exit-code -- .gitignore >/dev/null || fail ".gitignore changed"
}

case_init_writes_the_worked_example() {
    local h p a rec changes
    h=$(installed_home)
    p=$(new_project)
    a=$(answers "${WORKED_EXAMPLE[@]}")
    run_init "$h" "$p" "$a"
    expect_status 0
    changes=$(diff "$FACTORY/project/flow-factory.toml" "$p/flow-factory.toml" | grep '^[<>]' || true)
    [ "$changes" = '< git.default_branch = "main"
> git.default_branch = "trunk"
< test.command = ""
> test.command = "npm test"' ] || fail "the diff against the template is not the two answers:
$changes"
    [ -d "$p/.cortex/tickets" ] && [ -d "$p/.cortex/candidates" ] || fail "no .cortex/tickets or candidates"
    grep -qF "Flow Factory $(git -C "$CHECKOUT" describe --tags --always)" "$p/.cortex/README.md" \
        || fail ".cortex/README.md does not carry the factory version"
    grep -qF "installed $(date +%Y-%m-%d)." "$p/.cortex/README.md" || fail ".cortex/README.md has no date"
    rec="$h/.flow-factory/install-record.txt"
    [ "$(grep -c '^project ' "$rec")" -eq 1 ] || fail "not exactly one project line"
    grep -qxF "project $p" "$rec" || fail "no line 'project $p'"
    expect_gitignore_untouched "$p"
}

# A worktree of project $1 as /flow-worktree-create makes it: under
# .claude/worktrees/, with .cortex and flow-factory.toml linked back.
new_worktree() {
    local wt="$1/.claude/worktrees/wt"
    git -C "$1" worktree add -q "$wt" -b wt
    ln -s "$1/.cortex" "$wt/.cortex"
    ln -s "$1/flow-factory.toml" "$wt/flow-factory.toml"
    printf '%s' "$wt"
}

case_init_leaves_git_status_clean_in_checkout_and_worktree() {
    local h p wt
    h=$(installed_home)
    p=$(new_project)
    run_init "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    [ -z "$(git -C "$p" status --porcelain)" ] || fail "git status after the write:
$(git -C "$p" status --porcelain)"
    wt=$(new_worktree "$p")
    [ -z "$(git -C "$wt" status --porcelain)" ] || fail "git status in the worktree:
$(git -C "$wt" status --porcelain)"
    [ -z "$(git -C "$p" status --porcelain)" ] || fail "git status in the checkout once a worktree exists:
$(git -C "$p" status --porcelain)"
    expect_gitignore_untouched "$p"
}

case_init_second_identical_run_changes_nothing() {
    local h p a f
    h=$(installed_home)
    p=$(new_project)
    a=$(answers "${WORKED_EXAMPLE[@]}")
    run_init "$h" "$p" "$a"
    expect_status 0
    mkdir "$SCRATCH/$CASE/before"
    cp -p "$p/flow-factory.toml" "$p/.git/info/exclude" "$h/.flow-factory/install-record.txt" \
        "$SCRATCH/$CASE/before/"
    run_init "$h" "$p" "$a"
    expect_status 0
    for f in "$p/flow-factory.toml" "$p/.git/info/exclude" "$h/.flow-factory/install-record.txt"; do
        cmp -s "$SCRATCH/$CASE/before/${f##*/}" "$f" || fail "the second run changed $f"
    done
    expect_line "unchanged flow-factory.toml"
    expect_line "unchanged /.cortex in"
    expect_line "unchanged /flow-factory.toml in"
    expect_line "unchanged /.claude/worktrees/ in"
    expect_line "unchanged ~/.flow-factory/install-record.txt"
    refuse_line "wrote"
    refuse_line "excluded "
    refuse_line "recorded"
    expect_gitignore_untouched "$p"
}

case_init_root_below_the_top_level() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    mkdir "$p/app"
    printf 'x\n' > "$p/app/keep"
    git -C "$p" add app/keep
    git -C "$p" "${GIT_ID[@]}" commit -qm app
    run_init "$h" "$p/app" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    [ -f "$p/app/flow-factory.toml" ] && [ -d "$p/app/.cortex/tickets" ] \
        || fail "the settings or the tracker are not in the project root"
    [ "$(grep -v '^#' "$p/.git/info/exclude")" = '/app/.cortex
/app/flow-factory.toml
/.claude/worktrees/' ] || fail "exclude lines: $(grep -v '^#' "$p/.git/info/exclude")"
    [ -z "$(git -C "$p" status --porcelain)" ] || fail "git status after the write:
$(git -C "$p" status --porcelain)"
    grep -qxF "project $p/app" "$h/.flow-factory/install-record.txt" || fail "no line 'project $p/app'"
    expect_line "not the repository's top level"
    expect_gitignore_untouched "$p"
}

case_init_names_a_tracked_settings_file() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    cp "$FACTORY/project/flow-factory.toml" "$p/flow-factory.toml"
    git -C "$p" add flow-factory.toml
    git -C "$p" "${GIT_ID[@]}" commit -qm settings
    run_init "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    ! grep -q 'flow-factory.toml' "$p/.git/info/exclude" || fail "an exclude line for a tracked flow-factory.toml"
    grep -qxF '/.cortex' "$p/.git/info/exclude" || fail "no exclude line for .cortex"
    expect_line "not excluded: flow-factory.toml is tracked"
    expect_gitignore_untouched "$p"
}

# What --init writes in a linked worktree, `git worktree remove` deletes
# without asking, tickets included.
case_init_stops_on_a_linked_worktree() {
    local h p wt
    h=$(installed_home)
    p=$(new_project)
    wt="$p/.claude/worktrees/wt"
    git -C "$p" worktree add -q "$wt" -b wt
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")" "$wt"
    expect_line "is in a linked worktree. Run --init on the main checkout, $p"
}

case_init_stops_when_cortex_is_a_file() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    printf 'notes\n' > "$p/.cortex"
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_line ".cortex exists and is not a directory"
}

case_init_stops_when_settings_is_a_directory() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    mkdir "$p/flow-factory.toml"
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_line "flow-factory.toml exists and is not a file"
}

# A symlink committed as .cortex, as a `git add` in a worktree leaves it.
# Excluded, the tracker is expendable to git, and a checkout of that branch
# deletes every ticket without a word.
case_init_leaves_a_tracker_symlink_committed_on_another_branch_unexcluded() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    git -C "$p" checkout -q -b other
    ln -s /elsewhere "$p/.cortex"
    git -C "$p" add .cortex
    git -C "$p" "${GIT_ID[@]}" commit -qm link
    git -C "$p" checkout -q trunk
    run_init "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    ! grep -qxF '/.cortex' "$p/.git/info/exclude" || fail "an exclude line for a tracker another branch commits"
    expect_line "not excluded: .cortex is committed on refs/heads/other"
    printf 'ticket\n' > "$p/.cortex/tickets/one.md"
    git -C "$p" checkout -q other 2>/dev/null && fail "git let a checkout delete the tracker"
    [ -f "$p/.cortex/tickets/one.md" ] || fail "the ticket is gone"
}

# Run --init under HOME $1 with answers $3, on project $2 or on root $4 inside
# it, and expect a stop that leaves HOME and the project exactly as they were.
expect_init_stop() {
    local h=$1 p=$2 a=$3 root=${4:-$2}
    snapshot "$h" "$p"
    run_init "$h" "$root" "$a"
    [ "$STATUS" -ne 0 ] || fail "exit 0, expected a stop. Output:
$(cat "$OUT")"
    expect_unchanged "$h" "$p"
}

# Copy HOME $1 and project $2 aside, for expect_unchanged to compare against.
snapshot() {
    rm -rf -- "$1.before" "$2.before"
    cp -Rp "$1" "$1.before"
    cp -Rp "$2" "$2.before"
}

expect_unchanged() {
    diff -r "$1.before" "$1" >/dev/null || fail "HOME changed. Output:
$(cat "$OUT")"
    diff -r --no-dereference "$2.before" "$2" >/dev/null || fail "the project changed. Output:
$(cat "$OUT")"
}

# One case per stop --init must make, each with valid answers beside the
# fault, so the fault is the only reason to stop.
INIT_STOPS=(no_record unknown_key malformed_value bad_pr_create_mode bad_attribution
    bad_port app_lengths_differ no_commit not_a_repository missing_default_branch
    bad_worktree_dir)

case_init_every_stop_has_a_case() {
    local s
    [ "${#INIT_STOPS[@]}" -eq 11 ] || fail "${#INIT_STOPS[@]} stops listed, expected 11"
    for s in "${INIT_STOPS[@]}"; do
        declare -F "case_init_stops_$s" >/dev/null || fail "no case for the stop $s"
    done
}

case_init_stops_no_record() {
    local h p
    h=$(new_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_line "Run ./install first"
}

case_init_stops_unknown_key() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'test.runner = "jest"')"
    expect_line "unknown key 'test.runner'"
}

case_init_stops_malformed_value() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    # A file of the project's own, named as a temporary settings file might
    # be. A stop must not delete it.
    printf 'mine\n' > "$p/flow-factory.toml.tmp"
    expect_init_stop "$h" "$p" "$(answers 'git.default_branch = "trunk"' 'test.command = npm test')"
    expect_line "malformed value for 'test.command'"
}

# TOML defines \t and \\ but not \d, so the value below is not a TOML string.
case_init_stops_on_an_escape_toml_does_not_define() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers 'git.default_branch = "trunk"' 'test.command = "grep \d"')"
    expect_line "malformed value for 'test.command'"
}

case_init_accepts_the_escapes_toml_defines() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    run_init "$h" "$p" "$(answers 'git.default_branch = "trunk"' 'test.command = "run \"a\\\\b\" é"')"
    expect_status 0
    grep -qxF 'test.command = "run \"a\\\\b\" é"' "$p/flow-factory.toml" || fail "the escaped value was not written as given"
}

case_init_stops_on_a_bare_repository() {
    local h p
    h=$(installed_home)
    p="$SCRATCH/$CASE/project.git"
    git -C "$(new_project)" "${GIT_ID[@]}" clone -q --bare . "$p"
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_line "no work tree"
}

case_init_stops_on_a_factory_without_the_readme_template() {
    local h p factory
    h=$(installed_home)
    p=$(new_project)
    factory=$(copy_factory)
    rm "$factory/project/.cortex/README.md"
    cp -Rp "$p" "$p.before"
    run_install "$h" "$factory" --init "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    [ "$STATUS" -ne 0 ] || fail "exit 0 with no README template"
    diff -r "$p.before" "$p" >/dev/null || fail "the project changed"
    expect_line "project/.cortex/README.md"
}

# A settings file committed on a tag no branch holds. Excluded, git would treat
# it as expendable and a checkout of that tag would overwrite it without a
# word. case_init_leaves_a_tracker_symlink_committed_on_another_branch_unexcluded
# covers a branch.
case_init_leaves_settings_committed_on_a_tag_unexcluded() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    git -C "$p" checkout -q --detach
    cp "$FACTORY/project/flow-factory.toml" "$p/flow-factory.toml"
    git -C "$p" add flow-factory.toml
    git -C "$p" "${GIT_ID[@]}" commit -qm settings
    git -C "$p" tag v1
    git -C "$p" checkout -q trunk
    run_init "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    ! grep -q 'flow-factory.toml' "$p/.git/info/exclude" || fail "an exclude line for a settings file a tag commits"
    expect_line "not excluded: flow-factory.toml is committed on refs/tags/v1"
    git -C "$p" checkout -q v1 2>/dev/null && fail "git let a checkout overwrite the settings"
    expect_gitignore_untouched "$p"
}

case_init_record_with_no_final_newline_keeps_its_last_line() {
    local h p rec last
    h=$(installed_home)
    p=$(new_project)
    rec="$h/.flow-factory/install-record.txt"
    last=$(tail -n 1 "$rec")
    printf '%s' "$(cat "$rec")" > "$rec.cut" && mv "$rec.cut" "$rec"
    run_init "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    [ "$(tail -n 2 "$rec")" = "$last
project $p" ] || fail "the record ends: $(tail -n 2 "$rec")"
}

case_init_stops_bad_pr_create_mode() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'pr.create_mode = "auto"')"
    expect_line "'pr.create_mode'"
}

case_init_stops_bad_attribution() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'github.attribution = "vendor"')"
    expect_line "'github.attribution'"
}

# A worktree directory outside the top level, absolute, or with a trailing
# slash would put worktrees where the exclude line does not reach.
case_init_stops_bad_worktree_dir() {
    local h p dir
    h=$(installed_home)
    p=$(new_project)
    for dir in '../x' '/abs' 'x/' 'a/../b'; do
        expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" "worktree.dir = \"$dir\"")"
        expect_line "'worktree.dir' must be a relative path below the top level"
    done
}

# A project's worktree.dir is the directory --init keeps out of git, and the
# default one is not.
case_init_excludes_the_projects_worktree_dir() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    run_init "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'worktree.dir = ".worktrees"')"
    expect_status 0
    [ "$(grep -v '^#' "$p/.git/info/exclude")" = '/.cortex
/flow-factory.toml
/.worktrees/' ] || fail "exclude lines: $(grep -v '^#' "$p/.git/info/exclude")"
    grep -qxF 'worktree.dir = ".worktrees"' "$p/flow-factory.toml" || fail "flow-factory.toml does not carry worktree.dir"
}

case_init_stops_bad_port() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'app.services = ["web", "api"]' \
        'app.start_commands = ["npm start", "npm run api"]' 'app.ports = ["30{NN}", "80{N}"]')"
    expect_line "bad port \"80{N}\" in 'app.ports'"
}

# Both pass the shape check: 80{NN}80 gives ports such as 802080, and 0 asks
# the system for any free port.
case_init_stops_on_a_port_out_of_range() {
    local h p port
    h=$(installed_home)
    p=$(new_project)
    for port in '80{NN}80' '0'; do
        expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'app.services = ["web"]' \
            'app.start_commands = ["npm start"]' "app.ports = [\"$port\"]")"
        expect_line "bad port \"$port\" in 'app.ports'"
    done
}

case_init_stamp_counts_uncommitted_changes_to_project() {
    local h p factory
    h=$(installed_home)
    p=$(new_project)
    factory=$(copy_factory)
    printf 'A local note.\n' >> "$factory/project/.cortex/README.md"
    run_install "$h" "$factory" --init "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    grep -qF "plus uncommitted changes to 1 files" "$p/.cortex/README.md" \
        || fail "the README stamp does not count the change to project/: $(tail -n 3 "$p/.cortex/README.md")"
}

case_init_stops_app_lengths_differ() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'app.services = ["web", "api"]' \
        'app.start_commands = ["npm start"]' 'app.ports = ["30{NN}", "80{NN}"]')"
    expect_line "'app.services', 'app.start_commands' and 'app.ports' must be the same length"
}

case_init_stops_no_commit() {
    local h p
    h=$(installed_home)
    p="$SCRATCH/$CASE/project"
    mkdir -p "$p"
    git -C "$p" -c init.defaultBranch=trunk init -q
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_line "has no commit"
}

case_init_stops_not_a_repository() {
    local h p
    h=$(installed_home)
    p="$SCRATCH/$CASE/project"
    mkdir -p "$p"
    printf 'node_modules/\n' > "$p/.gitignore"
    expect_init_stop "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_line "is not a git repository"
}

case_init_stops_missing_default_branch() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    expect_init_stop "$h" "$p" "$(answers 'git.default_branch = "develop"' 'test.command = "npm test"')"
    expect_line "'git.default_branch' is \"develop\", which names neither a local branch nor origin/develop"
}

# ---------------------------------------------------------------------------
# Check mode: ./install --check <project root> <answers file>

ORIGIN_LOSES="/flow-close-out, /flow-comments-review, /flow-pr-summary, /flow-worktree-close and /flow-worktree-create error, /flow-status and /flow-reground stop"
NETWORK_LOSES="/flow-close-out, /flow-comments-review, /flow-new-github-issue, /flow-pr-summary, /flow-ship-ticket, /flow-stakeholder-update, /flow-worktree-close and /flow-worktree-create error, /flow-status and /flow-reground stop"

# The ticket's worked example: one commit on main, and an origin that answers
# without a main. Its answers are WORKED_ANSWERS.
worked_example_project() {
    local p
    p=$(new_project)
    git -C "$p" branch -m main
    git init -q --bare -b trunk "$SCRATCH/$CASE/origin.git"
    git -C "$p" remote add origin "$SCRATCH/$CASE/origin.git"
    printf '%s' "$p"
}
WORKED_ANSWERS=('git.default_branch = "main"' 'test.command = "npm test"')

case_check_worked_example_writes_nothing() {
    local h p
    h=$(installed_home)
    p=$(worked_example_project)
    snapshot "$h" "$p"
    run_check "$h" "$p" "$(answers "${WORKED_ANSWERS[@]}")"
    expect_status 0
    expect_line "origin has no branch main: $ORIGIN_LOSES. Fix: git push origin main"
    expect_unchanged "$h" "$p"
}

# Expect origin line $1 and refuse the other two; `none` refuses all three.
expect_origin_line() {
    local line
    for line in "has no branch" "no origin:" "origin cannot be reached"; do
        if [ "$line" = "$1" ]; then expect_line "$line"; else refuse_line "$line"; fi
    done
}

case_check_tells_the_origin_cases_apart() {
    local h a p
    h=$(installed_home)
    a=$(answers "${WORKED_EXAMPLE[@]}")

    p=$(new_project none)
    run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "no origin: $NETWORK_LOSES. Fix: git remote add origin <url>"
    expect_origin_line "no origin:"

    p=$(new_project with)
    git clone -q --bare "$p" "$SCRATCH/$CASE/with.git"
    git -C "$p" remote add origin "$SCRATCH/$CASE/with.git"
    run_check "$h" "$p" "$a"
    expect_status 0
    expect_origin_line none

    p=$(new_project missing)
    git -C "$p" remote add origin "$SCRATCH/$CASE/nowhere.git"
    run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "origin cannot be reached, fatal: '$SCRATCH/$CASE/nowhere.git' does not appear to be a git repository: "
    expect_origin_line "origin cannot be reached"
}

# A logged-in gh in this case's bin/, printed for a PATH. `repo view` answers
# permission $1, fails when $1 is empty, and hangs when it is HANG. `label
# list` prints labels $2..., JSON-encoded as the installer asks for them.
# Each call's arguments go to bin/calls.
stub_gh() {
    local bin="$SCRATCH/$CASE/bin"
    mkdir -p "$bin"
    printf '%s\n' "$1" > "$bin/permission"
    shift
    : > "$bin/labels"
    [ $# -eq 0 ] || printf '"%s"\n' "$@" > "$bin/labels"
    cat > "$bin/gh" <<'EOF'
#!/bin/sh
d=$(dirname "$0")
echo "$*" >> "$d/calls"
case "$1 $2" in
    "auth status") exit 0 ;;
    "repo view")
        read -r p < "$d/permission"
        [ -n "$p" ] || { echo "GraphQL: Could not resolve to a Repository" >&2; exit 1; }
        [ "$p" != HANG ] || exec sleep 30
        echo "$p" ;;
    "label list") cat "$d/labels" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$bin/gh"
    printf '%s' "$bin:$PATH"
}

# A project whose origin, github.com:owner/repo.git, carries its default
# branch, trunk. Its core.sshCommand is a stand-in for ssh: it resolves every
# host to github.com, and serves origin from a local bare repository, so
# nothing leaves the machine.
project_with_origin() {
    local p d="$SCRATCH/$CASE/$1-ssh"
    p=$(new_project "$1")
    mkdir -p "$d/repos/owner"
    git clone -q --bare "$p" "$d/repos/owner/repo.git"
    cat > "$d/ssh" <<'EOF'
#!/bin/sh
# The last argument is git's remote command, such as git-upload-pack 'x'.
for last; do :; done
case " $* " in *" -G "*) echo "hostname github.com"; exit 0 ;; esac
cd "$(dirname "$0")/repos" && exec sh -c "git ${last#git-}"
EOF
    chmod +x "$d/ssh"
    git -C "$p" config core.sshCommand "$d/ssh"
    git -C "$p" remote add origin github.com:owner/repo.git
    printf '%s' "$p"
}

case_check_gh_outcomes() {
    local h a p bin
    h=$(installed_home)
    a=$(answers "${WORKED_EXAMPLE[@]}")
    p=$(project_with_origin project)

    PATH=$(stub_gh READ) run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "you cannot push to origin, gh reports READ: /flow-ship-ticket errors, and /flow-worktree-close cannot delete the remote branch. Fix: ask a repository admin for write access"

    PATH=$(stub_gh WRITE) run_check "$h" "$p" "$a"
    expect_status 0
    [ "$(cat "$OUT")" = "no gaps" ] || fail "every check passed, and the output is not 'no gaps':
$(cat "$OUT")"

    PATH=$(stub_gh "") run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "gh cannot reach origin, GraphQL: Could not resolve to a Repository: every gh step fails, in /flow-close-out, /flow-comments-review, /flow-new-github-issue, /flow-pr-summary, /flow-ship-ticket and /flow-stakeholder-update"
    refuse_line "cannot push"

    # The logged-out gh every case gets.
    run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "not checked: gh reaching origin, because gh auth status fails for github.com"

    # No gh at all: this bash, and the system's commands, which hold none.
    bin="$SCRATCH/$CASE/no-gh"
    mkdir -p "$bin"
    ln -s "$BASH" "$bin/bash"
    ! PATH="$bin:/usr/bin:/bin" command -v gh >/dev/null || fail "this machine has gh in /usr/bin or /bin"
    PATH="$bin:/usr/bin:/bin" run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "not checked: gh reaching origin, because gh is not installed"
}

case_check_names_each_missing_label() {
    local h p
    h=$(installed_home)
    p=$(project_with_origin project)
    PATH=$(stub_gh WRITE bug) run_check "$h" "$p" \
        "$(answers "${WORKED_EXAMPLE[@]}" 'github.labels = ["Bug", "nope"]')"
    expect_status 0
    [ "$(grep -c nope "$OUT")" -eq 1 ] || fail "not exactly one line naming nope. Output:
$(cat "$OUT")"
    expect_line 'label "nope" does not exist on origin: /flow-new-github-issue errors. Fix: gh label create "nope" --repo github.com/owner/repo'
    refuse_line '"bug"'

    # Unchecked labels are named once, with the reason gh was skipped.
    run_check "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'github.labels = ["nope"]')"
    expect_status 0
    expect_line "not checked: gh reaching origin, and the labels, because gh auth status fails for github.com"
}

# ssh reads a config in which the aliases resolve and every connection is
# `ProxyCommand false`, and https goes through a closed local proxy, so
# origin itself is never reached.
case_check_names_origin_to_gh_as_host_owner_repo() {
    local h p a url want calls="$SCRATCH/$CASE/bin/calls" cfg="$SCRATCH/$CASE/ssh_config"
    h=$(installed_home)
    a=$(answers "${WORKED_EXAMPLE[@]}" 'github.labels = ["nope"]')
    printf 'Host github-work\n    HostName github.com\nHost github-443\n    HostName ssh.github.com\nHost *\n    ProxyCommand false\n' > "$cfg"
    for url in github-work:owner/repo.git github-443:owner/repo.git me@github.com:owner/repo \
            deploy@ghe.example:team/app.git; do
        case $url in *team/app*) want=ghe.example/team/app ;; *) want=github.com/owner/repo ;; esac
        p=$(new_project "p$RUNS")
        git -C "$p" remote add origin "$url"
        GIT_SSH_COMMAND="ssh -F $cfg" PATH=$(stub_gh WRITE) run_check "$h" "$p" "$a"
        expect_status 0
        grep -qxF "repo view $want --json viewerPermission -q .viewerPermission" "$calls" \
            || fail "gh was not asked for $want, from $url:
$(cat "$calls")"
        grep -qxF "auth status --hostname ${want%%/*}" "$calls" \
            || fail "gh auth status was not asked about ${want%%/*}, from $url:
$(cat "$calls")"
        rm -f -- "$calls"
    done

    # A path names no repository on any gh host, so gh is not asked.
    p=$(new_project path)
    git clone -q --bare "$p" "$p.git"
    git -C "$p" remote add origin "$p.git"
    PATH=$(stub_gh WRITE) run_check "$h" "$p" "$a"
    expect_status 0
    expect_line "gh cannot reach origin, which is a path: every gh step fails, in "
    expect_line "not checked: the labels, because gh cannot reach origin"
    [ ! -f "$calls" ] || fail "gh was called for a path:
$(cat "$calls")"

    # The harness's rewrites would hide the https URL, so the proxy alone
    # keeps this run local, and no_proxy must not route around it.
    p=$(new_project https)
    git -C "$p" remote add origin https://x-access-token:SECRET@github.example.com/owner/repo.git
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.proxy GIT_CONFIG_VALUE_0=http://127.0.0.1:9 \
        no_proxy= NO_PROXY= PATH=$(stub_gh WRITE) run_check "$h" "$p" "$a"
    expect_status 0
    grep -qF "label list --repo github.example.com/owner/repo " "$calls" \
        || fail "gh was not asked for github.example.com/owner/repo:
$(cat "$calls")"
    expect_line "Fix: gh label create \"nope\" --repo github.example.com/owner/repo"
    refuse_line SECRET
}

# A network that drops packets answers nothing. Each call gives up after 10
# seconds, so two hangs end in about 20, well before their 30-second sleeps.
case_check_gives_up_on_a_silent_network() {
    local h p start
    h=$(installed_home)
    p=$(new_project)
    git -C "$p" remote add origin flow-test.invalid:owner/repo.git
    # ssh -G answers, as it reads only the config, and a connection hangs.
    git -C "$p" config core.sshCommand \
        "sh -c 'case \" \$* \" in *\" -G \"*) echo hostname github.com ;; *) exec sleep 30 ;; esac' ssh"
    start=$SECONDS
    PATH=$(stub_gh HANG) run_check "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    [ $((SECONDS - start)) -lt 28 ] || fail "the check took $((SECONDS - start)) seconds"
    expect_line "origin cannot be reached, no answer in 10 seconds: "
    expect_line "gh cannot reach origin, no answer in 10 seconds: "
}

# ssh warns before it fails, as it does when it adds a host key, or, from
# OpenSSH 10, on a key exchange that is not post-quantum. The reason shown is
# the failure. The ssh here also records how it was run.
case_check_reason_skips_a_warning() {
    local h p d="$SCRATCH/$CASE"
    h=$(installed_home)
    p=$(new_project)
    git -C "$p" remote add origin flow-test.invalid:owner/repo.git
    cat > "$d/ssh" <<EOF
#!/bin/sh
case " \$* " in *" -G "*) exit 255 ;; esac
echo "\$* GCM_INTERACTIVE=\$GCM_INTERACTIVE" > "$d/ssh-run"
echo "Warning: Permanently added flow-test.invalid to the list of known hosts." >&2
echo "** WARNING: connection is not using a post-quantum key exchange algorithm." >&2
echo "git@flow-test.invalid: Permission denied (publickey)." >&2
exit 255
EOF
    chmod +x "$d/ssh"
    git -C "$p" config core.sshCommand "$d/ssh"
    run_check "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    expect_line "origin cannot be reached, git@flow-test.invalid: Permission denied (publickey).: "
    # No prompt, a 5-second connect timeout, no update to known_hosts, and no
    # sign-in window from Git Credential Manager.
    grep -qF -- "-o BatchMode=yes -o ConnectTimeout=5 -o UpdateHostKeys=no " "$d/ssh-run" \
        && grep -qF "GCM_INTERACTIVE=never" "$d/ssh-run" \
        || fail "ssh ran as: $(cat "$d/ssh-run")"
}

# GIT_SSH names a program, which may take no ssh options, so the check leaves
# it to git rather than override it with GIT_SSH_COMMAND.
# The alias still reaches gh resolved, through the ssh on PATH, which here
# resolves every host to github.com. myssh fails without a word, and the
# line still gives a reason.
case_check_keeps_git_ssh() {
    local h p bin="$SCRATCH/$CASE/ssh" calls="$SCRATCH/$CASE/bin/calls"
    h=$(installed_home)
    mkdir -p "$bin"
    printf '#!/bin/sh\necho "$*" > "%s/called"\nexit 255\n' "$bin" > "$bin/myssh"
    printf '#!/bin/sh\necho hostname github.com\n' > "$bin/ssh"
    chmod +x "$bin/myssh" "$bin/ssh"
    p=$(new_project)
    git -C "$p" remote add origin github-work:owner/repo.git
    GIT_SSH="$bin/myssh" PATH="$bin:$(stub_gh WRITE)" run_check "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    expect_status 0
    [ -f "$bin/called" ] || fail "GIT_SSH was not run. Output:
$(cat "$OUT")"
    expect_line "origin cannot be reached, fatal: Could not read from remote repository.: "
    grep -qF "repo view github.com/owner/repo " "$calls" || fail "gh was not asked for github.com/owner/repo:
$(cat "$calls")"
}

case_check_names_tracked_worktrees_only() {
    local h a p
    h=$(installed_home)
    a=$(answers "${WORKED_EXAMPLE[@]}")
    p=$(new_project tracked)
    mkdir -p "$p/.claude/worktrees/old"
    printf 'x\n' > "$p/.claude/worktrees/old/file"
    git -C "$p" add .claude/worktrees/old/file
    git -C "$p" "${GIT_ID[@]}" commit -qm worktree
    run_check "$h" "$p" "$a"
    expect_status 0
    expect_line ".claude/worktrees/ is tracked: /flow-worktree-create is wrong, git add -A in the main checkout stages each worktree. Fix: git -C \"$p\" rm -r --cached .claude/worktrees/"
    # From a root below the top level, the fix still names the top level.
    mkdir "$p/app"
    run_check "$h" "$p/app" "$a"
    expect_status 0
    expect_line "Fix: git -C \"$p\" rm -r --cached .claude/worktrees/"

    p=$(new_project untracked)
    mkdir -p "$p/.claude/worktrees/old"
    printf 'x\n' > "$p/.claude/worktrees/old/file"
    run_check "$h" "$p" "$a"
    expect_status 0
    refuse_line ".claude/worktrees/"
}

# The check looks for tracked worktrees in the project's worktree.dir.
case_check_names_a_tracked_worktree_dir_from_the_settings() {
    local h p
    h=$(installed_home)
    p=$(new_project)
    mkdir -p "$p/.worktrees/old"
    printf 'x\n' > "$p/.worktrees/old/file"
    git -C "$p" add .worktrees/old/file
    git -C "$p" "${GIT_ID[@]}" commit -qm worktree
    run_check "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}" 'worktree.dir = ".worktrees"')"
    expect_status 0
    expect_line ".worktrees/ is tracked: /flow-worktree-create is wrong"
    refuse_line ".claude/worktrees/"
}

# A gap never stops the check; a project it cannot read does.
case_check_stops_on_not_a_repository() {
    local h p
    h=$(installed_home)
    p="$SCRATCH/$CASE/project"
    mkdir -p "$p"
    snapshot "$h" "$p"
    run_check "$h" "$p" "$(answers "${WORKED_EXAMPLE[@]}")"
    [ "$STATUS" -ne 0 ] || fail "exit 0, expected a stop. Output:
$(cat "$OUT")"
    expect_unchanged "$h" "$p"
    expect_line "is not a git repository"
}

# --check shares --init's stops, and its stop names the mode that was run.
case_check_stops_on_a_linked_worktree() {
    local h p wt
    h=$(installed_home)
    p=$(new_project)
    wt="$p/.claude/worktrees/wt"
    git -C "$p" worktree add -q "$wt" -b wt
    run_check "$h" "$wt" "$(answers "${WORKED_EXAMPLE[@]}")"
    [ "$STATUS" -ne 0 ] || fail "exit 0, expected a stop. Output:
$(cat "$OUT")"
    expect_line "is in a linked worktree. Run --check on the main checkout, $p"
}

# A colleague running --init by hand sees the gaps too, once it has written.
case_init_prints_the_check_lines() {
    local h p
    h=$(installed_home)
    p=$(worked_example_project)
    run_init "$h" "$p" "$(answers "${WORKED_ANSWERS[@]}")"
    expect_status 0
    sed -n '/^== Record the project/,$p' "$OUT" | grep -qxF "  origin has no branch main: $ORIGIN_LOSES. Fix: git push origin main" \
        || fail "no check line after the record is written. Output:
$(cat "$OUT")"
}

# ---------------------------------------------------------------------------
# The machine check: ./install's last step names what this machine lacks.

# Every command in /bin and /usr/bin but the tools the check looks for, with
# this machine's git and bash, in farm/. Built once.
farm() {
    local f
    [ ! -d "$SCRATCH/farm" ] || return 0
    mkdir -p "$SCRATCH/farm"
    for f in /bin/* /usr/bin/*; do
        case ${f##*/} in osascript|defaults|pbcopy|gh|lsof|curl|claude|git|bash) continue ;; esac
        [ -e "$SCRATCH/farm/${f##*/}" ] || ln -s "$f" "$SCRATCH/farm/"
    done
    ln -s "$(command -v git)" "$SCRATCH/farm/git"
    ln -s "$BASH" "$SCRATCH/farm/bash"
}

# Tool $1 in this case's machine/, a shell script running $2.
stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$SCRATCH/$CASE/machine/$1"
    chmod +x "$SCRATCH/$CASE/machine/$1"
}

# A stub in machine/ of every tool the check runs, each answering as a
# machine on which its check passes: macOS with iTerm2 running and its
# Automation permission granted, a logged-in gh, a reachable GitHub, and a login shell that
# finds claude. Each tool named in $@ is left out. A case changes one by
# stubbing it again.
passing_machine() {
    local tool
    farm
    mkdir -p "$SCRATCH/$CASE/machine"
    stub osascript 'case "$2" in *"count windows") echo 1 ;; *"is running") echo true ;; *) echo com.googlecode.iterm2 ;; esac'
    stub defaults 'echo "\"Custom Command\" = No;"'
    stub pbcopy 'cat >/dev/null'
    stub gh 'exit 0'
    stub lsof 'exit 0'
    stub curl 'exit 0'
    stub claude 'echo "2.1.282 (Claude Code)"'
    stub login-shell 'echo /usr/local/bin/claude'
    for tool; do rm -f -- "$SCRATCH/$CASE/machine/$tool"; done
}

# Run ./install under HOME $1 on the machine passing_machine built.
run_machine() {
    PATH="$SCRATCH/$CASE/machine:$SCRATCH/farm" SHELL="$SCRATCH/$CASE/machine/login-shell" \
        run_install "$1"
}

# The lines of the machine check, without its heading.
check_lines() { sed -n '/^== Check this machine$/,/^$/p' "$OUT" | sed '1d;/^$/d'; }

# A skill-creator in HOME $1's skills, linked there as a skill manager does.
link_skill_creator() {
    mkdir -p "$SCRATCH/$CASE/agents/skill-creator" "$1/.claude/skills"
    printf -- '---\nname: skill-creator\n---\n' > "$SCRATCH/$CASE/agents/skill-creator/SKILL.md"
    ln -s "$SCRATCH/$CASE/agents/skill-creator" "$1/.claude/skills/skill-creator"
}

case_machine_check_passes_on_a_complete_machine() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    run_machine "$h"
    expect_status 0
    [ "$(check_lines)" = "  claude --version: 2.1.282 (Claude Code), with no minimum version checked
  no gaps in 13 checks: osascript and defaults, iTerm2, not inside tmux, pbcopy, gh, lsof, curl, mktemp and /tmp, skill-creator, claude in a new pane, the gh login, the network to GitHub, the Automation permission" ] \
        || fail "not the two lines of a machine with no gaps. Output:
$(cat "$OUT")"
}

case_machine_check_names_what_a_missing_gh_costs() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine gh
    run_machine "$h"
    expect_status 0
    [ "$(check_lines | grep -cw gh)" -eq 1 ] || fail "not exactly one line naming gh. Output:
$(cat "$OUT")"
    check_lines | grep -qxF "  gh is not installed, so its login is not checked: /flow-close-out, /flow-new-github-issue, /flow-ship-ticket and /flow-stakeholder-update error, and /flow-comments-review and /flow-pr-summary diff against the default branch, not the pull request's base. Fix: brew install gh" \
        || fail "no line naming gh, what it costs and its fix. Output:
$(cat "$OUT")"
    check_lines | grep -qxF "  1 gap in 12 checks:" || fail "the login was counted as run. Output:
$(cat "$OUT")"
}

case_machine_check_names_a_logged_out_gh() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    stub gh 'case "$1 $2" in "auth status") exit 1 ;; esac'
    run_machine "$h"
    expect_status 0
    check_lines | grep -qxF "  gh is not logged in to github.com: for a project there, /flow-new-github-issue stops, /flow-close-out, /flow-ship-ticket and /flow-stakeholder-update error, and /flow-comments-review and /flow-pr-summary diff against the default branch, not the pull request's base. Fix: gh auth login" \
        || fail "no line saying gh is not logged in. Output:
$(cat "$OUT")"
    refuse_line "gh is not installed"
}

case_machine_check_names_a_missing_lsof() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine lsof
    run_machine "$h"
    expect_status 0
    check_lines | grep -qE '^  lsof is not (installed|on PATH): /flow-run-app reads every port as free, ' \
        || fail "no line saying /flow-run-app reads every port as free. Output:
$(cat "$OUT")"
}

# Every check fails that can while its tool is there, and every other tool
# is missing. The lines come in the order the prerequisites are listed:
# machine, then Claude Code; every access check is ruled out here. Without
# iTerm2 no pane can open, so the login shell a pane runs is never started.
case_machine_check_names_every_gap_in_order() {
    local h
    h=$(new_home)
    passing_machine pbcopy gh lsof curl
    stub osascript 'echo "execution error: Can'"'"'t get application id \"com.googlecode.iterm2\". (-1728)" >&2; exit 1'
    stub login-shell "touch \"$SCRATCH/$CASE/login-shell-ran\""
    stub mktemp 'case "$1" in /tmp/*) exit 1 ;; *) exec /usr/bin/mktemp "$@" ;; esac'
    TMUX=/tmp/tmux-501/default,1,0 run_machine "$h"
    expect_status 0
    [ "$(check_lines | sed 1d | cut -d: -f1)" = "  8 gaps in 9 checks
  iTerm2 is not installed, so the Automation permission and claude in a new pane are not checked
  this shell is inside tmux
  pbcopy is not installed
  gh is not installed, so its login is not checked
  lsof is not $(if [ -x /usr/sbin/lsof ]; then echo on PATH; else echo installed; fi)
  curl is not installed, so the network to GitHub is not checked
  mktemp cannot make a file in /tmp
  skill-creator is not installed" ] \
        || fail "not every gap, in order. Output:
$(cat "$OUT")"
    [ "$(check_lines | grep /flow-conductor | cut -d: -f1)" = "  iTerm2 is not installed, so the Automation permission and claude in a new pane are not checked
  this shell is inside tmux" ] \
        || fail "a line naming /flow-conductor is not a dispatch probe's. Output:
$(cat "$OUT")"
    [ ! -e "$SCRATCH/$CASE/login-shell-ran" ] || fail "the login shell was run without iTerm2"
}

# With iTerm2 there, the other three dispatch probes fail, each in its own
# layer's place, and each names /flow-conductor and no other skill.
case_machine_check_dispatch_probes_name_only_the_conductor() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    stub osascript 'case "$2" in
    *"count windows") echo "execution error: Not authorized to send Apple events to iTerm2. (-1743)" >&2; exit 1 ;;
    *"is running") echo true ;;
    *) echo com.googlecode.iterm2 ;;
esac'
    stub login-shell 'exit 1'
    TMUX=/tmp/tmux-501/default,1,0 run_machine "$h"
    expect_status 0
    [ "$(check_lines | sed 1d)" = "  3 gaps in 13 checks:
  this shell is inside tmux: /flow-conductor stops at its dispatch probes there
  claude is not on PATH in the login shell a new iTerm2 pane runs: /flow-conductor stops at its dispatch probes
  this terminal has no Automation permission for iTerm2, execution error: Not authorized to send Apple events to iTerm2. (-1743): /flow-conductor stops at its dispatch probes. Fix: grant it in System Settings, Privacy & Security, Automation" ] \
        || fail "not the three dispatch lines. Output:
$(cat "$OUT")"
}

# What the check cannot probe without a side effect or an input is named,
# not counted: an iTerm2 that is not running, which probe 2 would launch, or
# one osascript cannot ask about; no SHELL to run; and no defaults to read
# the profile with. A gh from before accounts, which has no --active, is
# asked without it.
case_machine_check_names_what_it_cannot_probe() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    stub osascript "echo \"\$2\" >> \"$SCRATCH/$CASE/osascript-calls\"
case \"\$2\" in *\"is running\") echo false ;; *) echo com.googlecode.iterm2 ;; esac"
    stub gh 'case "$*" in *--active*) echo "unknown flag: --active" >&2; exit 1 ;; esac'
    PATH="$SCRATCH/$CASE/machine:$SCRATCH/farm" SHELL= run_install "$h"
    expect_status 0
    expect_line "  no gaps in 11 checks: "
    expect_line "  not checked: claude in a new pane, because SHELL is not set"
    expect_line "  not checked: the Automation permission, because iTerm2 is not running, and the check does not start it"
    ! grep -q "count windows" "$SCRATCH/$CASE/osascript-calls" || fail "iTerm2 was sent an event while it was not running"

    passing_machine defaults
    stub login-shell "touch \"$SCRATCH/$CASE/login-shell-ran\""
    stub osascript 'case "$2" in *"is running") echo "execution error: timed out (-1712)" >&2; exit 1 ;; *) echo com.googlecode.iterm2 ;; esac'
    run_machine "$h"
    expect_status 0
    check_lines | grep -qxF "  defaults is not installed, so claude in a new pane is not checked: /flow-conductor stops at its dispatch probes" \
        || fail "no defaults line naming the probe it rules out. Output:
$(cat "$OUT")"
    [ ! -e "$SCRATCH/$CASE/login-shell-ran" ] || fail "the login shell was run with no profile read"
    expect_line "  not checked: the Automation permission, because osascript cannot say whether iTerm2 is running, execution error: timed out (-1712)"
}

# Probe 4 reads the first profile's Custom Command, as the conductor does.
# Anything but No runs a command other than the login shell, which is then
# never run.
case_machine_check_skips_probe_4_for_a_custom_command() {
    local h value
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    stub login-shell "touch \"$SCRATCH/$CASE/login-shell-ran\""
    for value in Yes '"Custom Shell"'; do
        stub defaults "echo '\"Custom Command\" = $value;'"
        run_machine "$h"
        expect_status 0
        expect_line "  no gaps in 12 checks: "
        expect_line "  not checked: claude in a new pane, because the iTerm2 profile runs a custom command. ~/.flow-factory/dispatch-prerequisites.md says how to probe it"
        [ ! -e "$SCRATCH/$CASE/login-shell-ran" ] || fail "the login shell was run for Custom Command = $value"
    done

    stub defaults "printf '%s\n' '\"Custom Command\" = No;' '\"Custom Command\" = Yes;'"
    run_machine "$h"
    expect_status 0
    expect_line "  no gaps in 13 checks: "
    [ -e "$SCRATCH/$CASE/login-shell-ran" ] || fail "the login shell was not run for a first profile running it"
}

# Claude Code's record of the plugins installed, holding plugin $1 installed
# for scope $2 at $3, under HOME $4.
plugin_record() {
    mkdir -p "$4/.claude/plugins"
    cat > "$4/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "$1@claude-plugins-official": [
      {
        "scope": "$2",
        "projectPath": "/somewhere/else",
        "installPath": "$3",
        "version": "1.0.0"
      }
    ]
  }
}
EOF
}

# A skill-creator plugin counts only when it is installed for every
# project, and the catalog of plugins offered never counts.
case_machine_check_finds_skill_creator_only_where_it_is_installed() {
    local h plugin
    h=$(new_home)
    plugin="$h/.claude/plugins/cache/claude-plugins-official/skill-creator/1.0.0"
    mkdir -p "$plugin/skills/skill-creator" \
        "$h/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator"
    printf -- '---\nname: skill-creator\n---\n' | tee "$plugin/skills/skill-creator/SKILL.md" \
        > "$h/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator/SKILL.md"
    passing_machine

    plugin_record skill-creator project "$plugin" "$h"
    run_machine "$h"
    expect_status 0
    expect_line "  skill-creator is not installed: "

    plugin_record skill-creator user "$plugin" "$h"
    run_machine "$h"
    expect_status 0
    expect_line "  no gaps in 13 checks: "
}

# Calls that never answer give up after 10 seconds, together: the Automation
# probe, as a permission dialog nobody answers; a login shell whose startup
# file hangs and ignores TERM, which the hangup of its own terminal still
# ends; and curl, as a network that drops packets, after which gh is not
# asked. Then gh alone.
case_machine_check_gives_up_on_calls_that_hang() {
    local h start
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    stub osascript 'case "$2" in *"count windows") exec sleep 30 ;; *"is running") echo true ;; *) echo com.googlecode.iterm2 ;; esac'
    stub login-shell 'trap "" TERM; sleep 30'
    stub curl 'exec sleep 30'
    stub gh "touch \"$SCRATCH/$CASE/gh-ran\""
    start=$SECONDS
    run_machine "$h"
    expect_status 0
    [ $((SECONDS - start)) -lt 20 ] || fail "the check took $((SECONDS - start)) seconds"
    expect_line "  not checked: claude in a new pane, because the login shell gave no answer in 10 seconds"
    expect_line "  GitHub cannot be reached, no answer in 10 seconds, so the gh login is not checked: "
    expect_line "  this terminal has no Automation permission for iTerm2, no answer in 10 seconds: /flow-conductor stops at its dispatch probes. Fix: answer the macOS dialog if one is open, or grant it in System Settings, Privacy & Security, Automation"
    [ ! -e "$SCRATCH/$CASE/gh-ran" ] || fail "gh was asked about a login while GitHub could not be reached"

    passing_machine
    stub gh 'exec sleep 30'
    start=$SECONDS
    run_machine "$h"
    expect_status 0
    [ $((SECONDS - start)) -lt 18 ] || fail "the check took $((SECONDS - start)) seconds"
    expect_line "  no gaps in 12 checks: "
    expect_line "  not checked: the gh login, because gh auth status gave no answer in 10 seconds"
}

# This machine's curl, through a closed local proxy, which no_proxy must not
# route around.
case_machine_check_names_an_unreachable_github() {
    local h
    h=$(new_home)
    link_skill_creator "$h"
    passing_machine
    ln -sf /usr/bin/curl "$SCRATCH/$CASE/machine/curl"
    https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 all_proxy= ALL_PROXY= \
        no_proxy= NO_PROXY= run_machine "$h"
    expect_status 0
    expect_line "  GitHub cannot be reached, curl: "
    expect_line ", so the gh login is not checked: for a project there, /flow-close-out, /flow-comments-review, /flow-new-github-issue, /flow-pr-summary, /flow-ship-ticket, /flow-stakeholder-update, /flow-worktree-close and /flow-worktree-create error, /flow-status and /flow-reground stop"
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
