---
name: flow-to-core
description: Cut one prose artifact down to its core through a short interactive back-and-forth. Works on a skill, a doc, CLAUDE.md, a config, a prompt or a written process. Finds who consumes it, measures what it really costs, then tables every part against what that part buys. Use when the user wants something trimmed to its core, made leaner, or says it has grown bloated. For code use /simplify.
---

# flow-to-core — cut one artifact to what it actually does

Takes one prose artifact: a skill, a doc, `CLAUDE.md`, a config, a prompt, a written
process.

**Not code.** A prose method has no way to prove the meaning of code survived the cut, so
send a module or a function to `/simplify`. Prose *inside* code is in scope: a file's
comments and docstrings can be trimmed here.

Every unit ends as keep, cut, or report. **"Nothing should go" is a real outcome** — say
it plainly and stop.

When the artifact lives inside a project, check first that the project has a
`flow-factory.toml` at its root. If it does not, stop as
`~/.flow-factory/settings-contract.md` says. A machine-level artifact, such as a
skill under `~/.claude/skills/`, needs no such check.

## 1. Read it, then find both ends

Read the target in full. Then, before judging a single line, work out what it emits and who
takes it.

- **Downstream.** What does it write, define or print, and who reads that? Grep the repo
  and the sibling artifacts.
- **Its own name.** Grep for the artifact itself. This is what finds output it used to
  produce and no longer declares, which the downstream grep structurally cannot see.
- **Upstream.** Does a sibling document a contract this artifact depends on? A line
  elsewhere saying "X reads `^Status:` at column 0" tells you what must not be cut, and no
  downstream grep will surface it.

Two traps. A filename grep on a common name returns mostly false hits: mentions in docs, or
a different file of the same name. Confirm each hit is a real consumer. And an artifact
whose consumer is **a human reading the output in that turn** has no grep-able consumer at
all; that is not the same as having none, so never read it as a cut.

If the artifact is loaded into your own context to constrain you, say so. You are then the
consumer deciding which of your own constraints to drop, which is the one judgement you
cannot make alone. That cut list goes to the user, not into the table.

**Absence of a consumer is a finding; not having looked is not.**

## 2. Measure three costs, assume none

- **To load** — paid every time, whether or not the artifact is used. For a skill that is
  the frontmatter description, not the body.
- **To run** — paid per invocation: seconds, commands, the body loaded.
- **To obey** — the work the artifact *orders downstream*. Routinely the largest and the
  most missed: a 4 KB skill can instruct a read of 700 KB.

Run the deterministic parts for real and reason about the rest, saying which you did. If
nothing is runnable, count the read cost instead and say so.

A number on its own decides nothing. Get a baseline from sibling artifacts of the same kind
before calling anything large.

## 3. Table every unit against what it buys

One row per unit, one column for what that unit decides, then keep, cut or report with the
reason on the row. Go below section granularity wherever the cost sits in a single clause.

- **Guardrails die with the step they guard.** Do not weigh a rule on its own merit until
  you know its step survives. On a flat rule set with no steps, this does not apply.
- **Name the direction of each failure.** A cut that leaves the artifact too cautious is a
  different risk from one that leaves it acting on stale state. Fail-safe cuts you can
  recommend; dangerous ones belong to the user.
- **Judge redundancy across rows, not within one.** A rule stated four times is defensible
  on each row and still wasteful.
- **Report is the third verdict.** Anything wrong, missing, contradictory or broken that
  you hit while measuring gets reported, not fixed here. A shorter file that is still stale
  is a failed pass.

## 4. Ask, cut, verify

**One question at a time**, only where the answers produce materially different artifacts.
Lead with your recommendation. Use previews when the question is about output shape: two
shapes side by side settle it faster than prose. **Stop asking once the rest is craft** —
wording, or which of four guardrails survive, is yours to decide.

Then in this order:

1. **Capture the baseline.** Run the original on real input and keep its answer. After the
   rewrite the original is a backup file and the comparison is gone.
2. **Check the input shape** the artifact assumes against the inputs it will really get,
   before cutting anything. Mismatches are cheap to find now.
3. **Secure the original.** If it is git-tracked and the tree is clean, git is the backup.
   If not, copy it outside the artifact's own directory and say where.
4. **One bulk confirm** of the table.
5. **Rewrite.**
6. **Verify** by running the trimmed version on real input and comparing to the baseline.
   Never by rereading it.

On a read-only or unattended run, stop after the table and hand that back. If no real input
exists, say the result is unverified rather than letting it read as done.

## Rules

- **Cut function, not words.** Rewording a section that should not exist is wasted work.
- **Report what the trimmed version can no longer do.** Whether that is too much to lose is
  the user's call.
- **Leave a lean-keeping line** if size was the fix and the artifact has none already.
