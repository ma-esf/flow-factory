# The install, step by step

What the first install did by hand, so the installer has something to automate.
Every step is marked **detectable**, meaning the installer can work it out on
its own, or **must-ask**, meaning it has to put the question to the user.

Run on macOS against Claude Code, with the three Discover-loop skills
(`flow-park`, `flow-backlog`, `flow-comments-review`) and a scratch project on
`master` with a real bare origin.

## The machine half, once per machine

| # | Step | Mark |
|---|---|---|
| 1 | Find the agent's skills directory. Claude Code reads `~/.claude/skills/`, one directory per skill. | detectable |
| 2 | Create `~/.flow-factory/`. | detectable |
| 3 | Place every file under `machine/` into it, keeping its relative path. | detectable |
| 4 | Copy each skill directory into the skills directory. | detectable |

**Step 3 must compare and overwrite, never skip because the file exists.** This
machine already held a `~/.flow-factory/` from an earlier hand-placement. Three
of its files matched the factory byte for byte and one, `worktree-share.txt`,
did not: the machine copy still said a project appends its own paths to it,
while the factory says the opposite, that a project does not edit the file and
puts its own paths in `flow-worktree-share.txt` at its root. An installer that
skips an existing file leaves that contradiction in place, and a user reading
the machine copy is reading an instruction the factory withdrew.

**Step 4 copies, it does not symlink.** A symlinked skill directory is invisible
to `find` and to `grep -r`, which take the link as an argument and do not
descend into it. Any later check over the skills directory, including the
clean-machine check that every skill reference resolves, then reads nothing and
reports a pass. If an install ever links instead of copying, every such check
has to use `find -L` and that requirement has to travel with the install.

**No restart is needed.** The three skills appeared in the running agent's skill
list as soon as the directories were copied. "Restart the agent" does not belong
in the installer's output.

## The project half, once per project

| # | Step | Mark |
|---|---|---|
| 5 | Find the project root. | detectable |
| 6 | Create the work-items folder with `issues/` and `candidates/`. | detectable |
| 7 | Place `flow-factory.toml` at the project root. | detectable |
| 8 | Answer `git.default_branch`. | must-ask |
| 9 | Answer `test.command`. | must-ask |
| 10 | Answer the document, tracker and Jira keys. | must-ask |
| 11 | Answer `github.merge_strategy` and `github.attribution`. | must-ask |
| 12 | Confirm the keys whose defaults stand. | must-ask |
| 13 | Place the pointer file in the work-items folder. | detectable |

**Step 8 is the one that looks detectable and is not.** The installer can read
the repository's branch, but `flow-comments-review` forbids exactly that
substitution: a repository showing one branch is the repository answering, not
the project, and a guess that happens to be right still hides the case where it
is wrong. Detect the value, then ask the user to confirm it. That is the
difference between detecting configuration and asking for it.

**Step 10 cannot be skipped just because empty is a common answer.** Under the
settings contract an empty value means the project has no such thing, which is a
statement. A key nobody answered is a different state with the same spelling,
and the installer is the only place the two can be told apart. This covers
`docs.context`, `docs.glossaries`, `project.decision_docs`, `test.dir`,
`test.guide_path`, `source.backend_dir`, `tracker.epic_field` and
`jira.enabled`.

**Step 13's version stamp is only honest if the factory tree is clean.** The
pointer file ends by naming the factory version that created the project's
files. This install ran from a working tree with four uncommitted files, so the
stamp reads the commit plus the number of files that differ from it. An
installer that prints a bare commit while installing from a dirty tree records
something that was never installed. Either refuse to install from a dirty tree
or stamp what was actually placed.

## The deliberately wrong input

`git.default_branch` was set to `main` in the scratch project, whose branch is
`master`, and `flow-comments-review` was run. Under the settings contract `main`
is a set value, so the skill has no licence to stop and ask.

The git layer failed loudly for both documented paths: `origin/main` and bare
`main` each returned `fatal: Not a valid object name`. The skill has no written
instruction for the case where both fail, so an agent reaching that point
invents one, and the nearest invention is the branch it is standing on.

The failure that matters is quieter. The skill's own code reads
`BASE_AT=$(git merge-base "origin/$BASE" HEAD)` and then `RANGE="$BASE_AT"`.
Command substitution of a failing command yields an empty string, so
`git diff $RANGE --stat` collapses to a bare `git diff`, exits 0, and prints a
plausible diff.

Measured rather than assumed. The first comparison agreed, which proves nothing,
so a file was committed without being pushed and both ranges were run again:

| Range | Files reported |
|---|---|
| `merge-base origin/master HEAD`, correct | `src/example.py`, `src/helper.py` |
| empty `BASE_AT`, collapsed to `git diff` | `src/example.py` only |

A wrong branch name therefore produces a review that omits a committed file and
reports success. This is the same shape as the `flow-status` collapse fixed in
`25cd0ad`, found in a second skill, and it is filed against the ticket that
ported this skill rather than repaired here.

## The falsification: no settings file

`flow-factory.toml` was deleted and all three skills were run again.

- `flow-park` reached the step that reads `tracker.epic_field`, found no
  settings file, named it and wrote nothing.
- `flow-comments-review` reached the step that reads `git.default_branch`, found
  no settings file, named it and stopped.
- `flow-backlog` listed the tracker correctly and never looked at the settings
  file.

`flow-backlog` names no settings key at all. Measured over the installed file:
zero hits across all seventeen key names, with the same call returning three
hits for a string the file certainly contains, so the zero is a measurement and
not a broken search. It has nothing to name and it does not guess, and the
pointer file already promises that the work items stay readable without an
install.

The machine gate was falsified the same way, because a gate seen only passing is
not a gate. With `tracker-contract.md` moved aside, `flow-park` and
`flow-backlog` both stop, and `flow-comments-review` is unaffected, since it
names `settings-contract.md` instead and writes no tracker file.

The result underneath both passes is that **no skill gates on the settings file
itself**. Each gates on the machine artifacts, then meets the missing settings
file only if it happens to read a key. `flow-park` stops solely because it reads
one optional key, `tracker.epic_field`, whose existence was an open decision
that could have gone the other way. Had that key been dropped, `flow-park` would
write a capture into a project the factory was never installed in.

## What the install could not verify

Two of the machine files, `settings-contract.md` and `templates/`, were already
on this machine before this run. They are byte-identical to the factory, so the
end state is right, but this run did not place them and therefore did not
observe a clean-machine order for them. The first install on a machine that has
never held `~/.flow-factory/` is still unobserved.
