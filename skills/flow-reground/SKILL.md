---
name: flow-reground
description: Re-ground a tracker artifact (issue, candidate, or PRD) against the project's latest default branch, report what no longer holds, patch mechanical staleness on approval, flag substantive staleness for you to action. Use when picking up an aged issue, before implementing or triaging, or when the user says "re-ground this", "is this still valid?", "check this against the default branch", or invokes /flow-reground.
---

# /flow-reground

Re-ground a tracker artifact against the code that exists *today*. A brief written
weeks ago is a stale claim, not ground truth: its line numbers, paths, and "where"
refs rot, the behavior it describes may already be built, and a decision it leans
on may have been reversed. This re-validates the artifact against the project's
fresh default branch, so whoever picks it up next isn't working from dead
coordinates.

It is a **check, not a repair**. It never touches code, never flips `Status:`, and
never silently rewrites the artifact. It patches only *mechanical* staleness, and
only on your approval. Everything substantive it **reports and recommends**, and
you decide.

Works on any file under `.flow/`, issue, candidate, or PRD. It re-grounds whatever
the file actually contains; it does not branch on type.

Conventions (paths, `Status:`, `Created:`, the `## Comments` history section) follow
`~/.flow-factory/tracker-contract.md`.

## Input - resolve the target artifact

Accept, in order:

1. **An explicit path** under `.flow/` (issue, candidate, or PRD).
2. **A fuzzy local reference**, a feature name, slug fragment, or `<feature>/<NN>`.
   Resolve it by searching `.flow/`. Multiple matches: list them and ask.
3. **Infer from context**. Given nothing, re-ground the artifact this session has
   been discussing.

Guard: a bare `#N` is a **GitHub** reference, not a local tracker file. If handed
one, say so and ask which `.flow/` file is meant, don't guess from the number.

## Step 0 - Fetch and fix the baseline (must run first, and must SUCCEED)

Re-grounding against a stale baseline is worse than no check: it reads as
"all clear." So adopt `/flow-status`'s discipline, refresh the base ref first, and
stop if you can't.

`BASE` is `origin/` followed by `git.default_branch`, read as
`~/.flow-factory/settings-contract.md` says. If that contract is not readable, the
factory was never installed on this machine. Say so and stop. Never write a branch
name into this step: in a project whose default branch is spelled differently a
guessed ref does not exist, and a baseline that quietly falls back grounds the whole
check against nothing.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

```bash
# Refresh remote refs. Does not modify any local branch or working tree.
git fetch --all --prune && echo "FETCH_OK" || echo "FETCH_FAILED"

# Baseline SHA for the provenance note, and how far the checkout sits from the base.
git rev-parse --short "$BASE"
git rev-list --left-right --count "$BASE...HEAD"   # "<behind>  <ahead>"
```

If `FETCH_FAILED`, **STOP**. Report the error and do not run the check: a freshness
verdict you can't trust is the failure that looks like success. The usual causes are
authentication, the network and a proxy. Ask the user to resolve the fetch failure
and re-run.

Validate anchors against `$BASE`, not the working tree. If the checkout is behind,
note it; the implementer will branch off the fresh default branch, so that is the
truth that matters.

## Step 1 - Inventory what's checkable

Read the artifact and list every element that can be re-grounded. Don't assume
density: a `/flow-park` capture is anchor-rich, a PRD deliberately has almost none.
Check whatever is present:

- **Anchors** - `file:line`, paths, symbols, referenced commits / PRs / `#N`.
- **Decision refs** - the ADRs, and the documents in `project.decision_docs`, that
  the artifact leans on.
- **Claimed behavior** - what the artifact says should be built (for the
  already-built check).
- **Acceptance criteria** - under `## Acceptance`, the one spelling
  `~/.flow-factory/tracker-contract.md` allows. If the file has none, say so in the
  report rather than skipping in silence: a picker-upper who is told nothing assumes
  the criteria were checked.

## Step 1.5 - Orient: brief the picker-upper

Before checking freshness, say what the artifact *is*. Whoever just picked up a
colleague's week-old issue needs to know what they're about to ship, not only which
line numbers moved. Boil the artifact down to three one-line labels:

- **What:** what the issue asks you to build.
- **Approach:** the intended implementation, if the artifact states one.
- **Done when:** the acceptance criteria, in brief.

One line each; drop any label the artifact has nothing for (a bare `/flow-park`
capture may yield only **What:**).

What this brief is:

- **The issue as authored** - synthesised from the artifact alone, no code search
  here (that's Step 2's job).
- **Not yet re-grounded** - Step 2 is what tells you which of these claims have gone
  stale.
- **Shown, not written to the file** - re-grounding stays a check, not a repair.

Sample brief, shown above the staleness report:

> **What:** Let one project override the default rate limit.
> **Approach:** A nullable column plus a settings toggle; the limiter reads the override when set.
> **Done when:** the toggle persists; the limiter respects it; projects with no override are unaffected.

## Step 2 - Re-ground each element against the base

For each element, resolve it against `$BASE` and sort it into one of three buckets:

- **Mechanical staleness** - the coordinates moved but the intent holds: a line
  number shifted, a function renamed, a path relocated. *Patchable.*
- **Substantive staleness** - the *answer* changed, not just the address:
  - the behavior is **already built** (search by domain concept, not wording);
  - an **acceptance criterion is now invalid**;
  - **scope or premise has moved**;
  - an **ADR reversed** a decision the artifact depends on.
- **Never-true claim** - the reasoning was wrong when written, so nothing drifted and
  every check above passes. Test the claims the scope rests on, not just the
  addresses: a `## Not in scope` rejection reason and an acceptance criterion's
  stated rationale are both testable, and a cheap one is worth running. When the
  reason to keep something is a condition that has not happened yet ("so it can be
  filled in later"), simulate that condition. Measuring only today's state is how a
  latent defect reads as harmless.

The one-line test: **did the answer change, or just the coordinates?** Coordinates
mean mechanical, the answer means substantive. Then one more: **was the answer ever
right?** Report a never-true claim like substantive staleness, and say it was wrong
from the start rather than stale, because the fix is different.

## Step 3 - Report before writing

Show all three buckets to the user. For each substantive or never-true finding, give
a one-line recommended next step, and note that these are recommendations, not
actions:

- already built: consider `wontfix`, or close;
- criterion invalid, or scope moved: re-triage (`/flow-triage`);
- premise gone: consider dropping;
- never-true claim: say what you tested and what it returned, and whether the scope
  still holds once the claim is removed. A rejected option whose reason was false is
  an option again.

Do **not** flip `Status:` and do **not** invoke `/flow-triage`. Recommend, don't act.
It is model-invocable, so this is a rule now, not a limitation.

## Step 4 - Patch and record (on approval)

On the user's go, in one pass:

1. **Apply the mechanical patches** to the artifact (only the coordinate fixes).
2. **Append one dated provenance note** under `## Comments`, AI-disclaimed, carrying
   the baseline SHA, the per-anchor changelog, and the flagged-not-actioned items:

```
> *Re-grounded YYYY-MM-DD against <base ref> (a1b2c3d) by AI.*
> Patched: handlers.py:65 -> :71; UserTable.tsx -> components/UserTable.tsx.
> Flagged (not actioned): criterion 2 may be invalid, the rate limiter was removed in #57; consider re-triage.
```

The substantive flags are **recorded, not actioned**; writing the breadcrumb is the
point, and whoever (or `/flow-triage`) picks it up next acts on it. Nothing lands
without the user's approval.
