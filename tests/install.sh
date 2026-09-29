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
    # A Finder .DS_Store is git-ignored and not the factory.
    expected=$(cd "$CHECKOUT" && find skills machine -type f ! -name .gitkeep ! -name .DS_Store \
        | wc -l | tr -d ' ')
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

case_linked_machine_file_is_left_alone() {
    local h target
    h=$(new_home)
    target="$SCRATCH/$CASE/checkout-copy.md"
    printf 'mine\n' > "$target"
    mkdir -p "$h/.flow-factory"
    ln -s "$target" "$h/.flow-factory/tracker-contract.md"
    run_install "$h"
    expect_status 0
    expect_line "left alone tracker-contract.md"
    [ "$(cat "$target")" = mine ] || fail "the install wrote through the link"
    [ -L "$h/.flow-factory/tracker-contract.md" ] || fail "the link was replaced"
}

case_linked_machine_directory_is_left_alone() {
    local h target
    h=$(new_home)
    target="$SCRATCH/$CASE/checkout-templates"
    mkdir -p "$h/.flow-factory"
    cp -R "$FACTORY/machine/templates" "$target"
    printf 'mine\n' > "$target/ticket.md"
    ln -s "$target" "$h/.flow-factory/templates"
    run_install "$h"
    expect_status 0
    expect_line "left alone templates/ticket.md"
    [ "$(cat "$target/ticket.md")" = mine ] || fail "the install wrote through the linked directory"
    ! grep -q "^file $h/.flow-factory/templates/" "$h/.flow-factory/install-record.txt" \
        || fail "the record claims files behind a link"
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

# Run the install and expect a stop that leaves HOME $1 exactly as it was.
expect_stop_writing_nothing() {
    local h=$1
    cp -Rp "$h" "$h.before"
    run_install "$h"
    [ "$STATUS" -ne 0 ] || fail "exit 0, expected a stop"
    diff -r "$h.before" "$h" >/dev/null || fail "HOME changed. Output:
$(cat "$OUT")"
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
    expect_line "Install complete, by the pulled installer."
    [ "$(grep -c '^== Update the checkout' "$OUT")" -eq 1 ] || fail "the run pulled more than once. Output:
$(cat "$OUT")"
}

# A pull can land and still exit non-zero, in a hook. The tree is new, so the
# new installer must place it.
case_update_hands_over_after_a_pull_that_lands_and_fails() {
    local h factory bin
    h=$(new_home)
    factory=$(copy_factory)
    run_install "$h" "$factory"
    expect_status 0
    change_origin_installer
    bin="$SCRATCH/$CASE/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\n"%s" "$@" || exit\ncase " $* " in *" pull "*) exit 1 ;; esac\n' "$(command -v git)" > "$bin/git"
    chmod +x "$bin/git"
    PATH="$bin:$PATH" run_install "$h" "$factory"
    expect_status 0
    expect_line "Install complete, by the pulled installer."
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
    bad_port app_lengths_differ no_commit not_a_repository missing_default_branch)

case_init_every_stop_has_a_case() {
    local s
    [ "${#INIT_STOPS[@]}" -eq 10 ] || fail "${#INIT_STOPS[@]} stops listed, expected 10"
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
