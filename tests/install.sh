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

CASE=""
RUNS=0

fail() { printf 'FAIL %s: %s\n' "$CASE" "$*" >&2; exit 1; }

# A scratch HOME holding only .claude/, as a machine with Claude Code has.
new_home() {
    local h="$SCRATCH/$CASE/${1:-home}"
    mkdir -p "$h/.claude"
    printf '%s' "$h"
}

# Run ./install from a factory checkout under HOME $1, with nothing on stdin
# and any further arguments passed on. Sets OUT to the file holding stdout and
# stderr, and STATUS to the exit code.
run_install() {
    local h=$1 factory=${2:-$FACTORY}
    shift; [ $# -eq 0 ] || shift
    RUNS=$((RUNS + 1))
    OUT="$SCRATCH/$CASE/out.$RUNS"
    STATUS=0
    HOME="$h" "$factory/install" "$@" </dev/null >"$OUT" 2>&1 || STATUS=$?
}

# Run ./install --init under HOME $1 on project root $2 with answers file $3.
run_init() {
    run_install "$1" "$FACTORY" --init "$2" "$3"
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
    for d in "$FACTORY"/skills/*/; do basename -- "$d"; done
}

# A committed copy of this checkout, for a case that must change a shipped file.
copy_factory() {
    local dest="$SCRATCH/$CASE/factory"
    mkdir -p "$dest"
    cp -R "$FACTORY/install" "$FACTORY/skills" "$FACTORY/machine" "$FACTORY/project" "$FACTORY/.gitignore" "$dest/"
    git -C "$dest" init -q
    git -C "$dest" add -A
    git -C "$dest" -c user.name=test -c user.email=test@example.invalid commit -qm copy
    printf '%s' "$dest"
}

# ---------------------------------------------------------------------------

case_fresh_install_places_every_file() {
    local h name
    h=$(new_home)
    run_install "$h"
    expect_status 0
    for name in $(shipped); do
        diff -r -x .DS_Store "$FACTORY/skills/$name" "$h/.claude/skills/$name" >/dev/null \
            || fail "skill $name differs from skills/$name"
    done
    diff -r -x .gitkeep -x .DS_Store -x install-record.txt "$FACTORY/machine" "$h/.flow-factory" >/dev/null \
        || fail "~/.flow-factory differs from machine/"
}

case_announces_both_paths_before_any_write() {
    local h first_write paths
    h=$(new_home)
    run_install "$h"
    expect_status 0
    # The first line that reports a write, including creating a directory.
    first_write=$(grep -nE '^ *(placed|unchanged|OVERWROTE|installed|replaced|created|recorded) ' "$OUT" \
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
    grep -q "^version $(git -C "$FACTORY" describe --tags --always)" "$rec" \
        || fail "no version line naming $(git -C "$FACTORY" describe --tags --always)"
    grep -qxF "checkout $FACTORY" "$rec" || fail "no line 'checkout $FACTORY'"
    grep -qx 'mode copy' "$rec" || fail "no line 'mode copy'"
    ! grep -q '^project ' "$rec" || fail "a project line, before any project was initialised"
    # A Finder .DS_Store is git-ignored and not the factory.
    expected=$(cd "$FACTORY" && find skills machine -type f ! -name .gitkeep ! -name .DS_Store \
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

case_rerun_keeps_record_lines_it_did_not_replace() {
    local h rec
    h=$(new_home)
    run_install "$h"
    expect_status 0
    rec="$h/.flow-factory/install-record.txt"
    # A skill a later factory withdrew, and a project an init recorded.
    mkdir -p "$h/.claude/skills/flow-withdrawn"
    printf 'old\n' > "$h/.claude/skills/flow-withdrawn/SKILL.md"
    printf 'file %s\nproject /work/app\n' "$h/.claude/skills/flow-withdrawn/SKILL.md" >> "$rec"
    run_install "$h"
    expect_status 0
    grep -qxF "file $h/.claude/skills/flow-withdrawn/SKILL.md" "$rec" \
        || fail "the rerun dropped the withdrawn skill from the record"
    grep -qx 'project /work/app' "$rec" || fail "the rerun dropped the project line"
    refuse_line "left alone flow-withdrawn"
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
    git -C "$factory" -c user.name=test -c user.email=test@example.invalid commit -qm ignore
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
        run_install "$h" "$FACTORY" "$arg"
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
    expect_line "Next: restart Claude Code first, then open Claude Code in your project and type /flow-init"
    expect_line "/fewer-permission-prompts"
}

case_existing_skills_dir_says_no_restart() {
    local h
    h=$(new_home)
    mkdir "$h/.claude/skills"
    run_install "$h"
    expect_status 0
    expect_line "Next: open Claude Code in your project and type /flow-init"
    refuse_line "restart"
    expect_line "/fewer-permission-prompts"
}

# ---------------------------------------------------------------------------
# Project mode: ./install --init <project root> <answers file>

GIT_ID=(-c user.name=test -c user.email=test@example.invalid)

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
    grep -qF "Flow Factory $(git -C "$FACTORY" describe --tags --always)" "$p/.cortex/README.md" \
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
    rm -rf -- "$h.before" "$p.before"
    cp -Rp "$h" "$h.before"
    cp -Rp "$p" "$p.before"
    run_init "$h" "$root" "$a"
    [ "$STATUS" -ne 0 ] || fail "exit 0, expected a stop. Output:
$(cat "$OUT")"
    diff -r "$h.before" "$h" >/dev/null || fail "HOME changed. Output:
$(cat "$OUT")"
    diff -r --no-dereference "$p.before" "$p" >/dev/null || fail "the project changed. Output:
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
