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

# Run ./install from a factory checkout under HOME $1, with nothing on stdin.
# Sets OUT to the file holding stdout and stderr, and STATUS to the exit code.
run_install() {
    local h=$1 factory=${2:-$FACTORY}
    RUNS=$((RUNS + 1))
    OUT="$SCRATCH/$CASE/out.$RUNS"
    STATUS=0
    HOME="$h" "$factory/install" </dev/null >"$OUT" 2>&1 || STATUS=$?
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
    cp -R "$FACTORY/install" "$FACTORY/skills" "$FACTORY/machine" "$FACTORY/.gitignore" "$dest/"
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
