---
name: flow-new-github-issue
description: Create a GitHub issue through a quick, approval-gated flow. Drafts the title and body in one shot, then creates only on the user's explicit go. Never creates the GitHub issue without explicit approval. Use when the user wants to open a GitHub issue safely.
---

# /flow-new-github-issue

Create a GitHub issue for this project. The user supplies the context (a bug, a task, a
paste of notes, a link). Turn it into a clean GitHub issue and create it with
`gh issue create`, but **only after explicit, final approval**.

Two visible gates: **Draft** (title + body together) and **Create** (explicit go). Keep
it tight; do not re-show the same content across multiple previews.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

## Hard rules

- **Never run `gh issue create` (or `--web`) until the user gives a clear go** ("create
  it", "go", "submit", "yes create"). A vague "ok", "sure", or silence is NOT approval.
  When unsure, ask again.
- **Default is: do not create.** If the user goes quiet or changes topic, stop and wait.
- **Redact when the project says to.** When `privacy.redact_client_data` is true in
  this project's settings, read as `~/.flow-factory/settings-contract.md` says,
  strip real company names and real figures from the title and body. Use
  synthetic values with the same shape. The key defaults to true and this text
  leaves the project, so the default is the safe one.
- **Tool attribution follows `~/.flow-factory/attribution-rule.md`**, which names
  the GitHub issue title and body as one of its three write points. That rule is
  not restated here.
- **The body must be readable from a fresh clone.** Write the reasoning out
  instead of pointing at a path under `.cortex/` or at a decision-record
  identifier: a project may commit its tracker or git-exclude it and the factory
  cannot know which, so a GitHub issue body must never depend on that path
  being reachable. The rule lives in this skill because this skill owns the
  GitHub issue body and can be invoked directly, not only through
  `/flow-ship-ticket`.
- **One GitHub issue per invocation.** Do not batch-create.

## Step 0 - Precheck (silent unless it fails)

```bash
gh auth status 2>&1
git remote -v 2>&1
```

- If not authenticated, stop and tell the user to run `gh auth login`. Do not continue.
- Read the `origin` remote for the `owner/repo`. This is the default target, confirmed
  at the Create gate, and it is why the factory needs no repository key.

Don't narrate this when it passes; just proceed to the draft.

## Step 1 - Draft gate (title + body in one message)

Show the **title and body together**, ready to submit. Don't split the problem statement
into its own round; fold it into the draft. Keep the body tight and scannable: relevant
context or repro, and what a good outcome looks like.

Before you show it, re-read the body once as the person who will fix this, and delete
every sentence that does not change what they do. Write in ASD-STE100 Simplified
Technical English: short sentences, one idea per sentence, plain words, active voice.

**Body shape.** Target 100 words, four parts, in this order. 150 is the ceiling,
not the goal: if the draft is over 100, cut before showing it.

1. Two short paragraphs on the problem. Open by glossing any domain term an outsider
   needs ("a run is one execution of the nightly import"), then say what breaks and
   why nobody notices it.
2. An `**Examples**` block: a concrete case of the behavior, one to three short lines,
   each shaped `input -> what happens now -> what is correct`. Always include one when
   the GitHub issue describes a behavior, a bug, or a concrete output; skip it only
   when there is genuinely no case to show. Prefer a case actually observed over an
   invented one, because a real instance proves the problem is real, not hypothetical.
   Keep the real shape and replace any client name or figure with a synthetic one of
   the same shape (see the redaction rule): a real bug never needs real client data to
   show it. When the behavior is non-deterministic, as a model output is, give the
   output observed and the property or range that is correct, and say how often the
   wrong one appeared, because one sample is not the behavior.
3. A `**Done looks like**` bullet list. One outcome per bullet, not a task. Fold a
   constraint into the bullet it belongs to instead of giving it its own.
4. `Prerequisite:` one line, only when something must land first.

Keep the technical level; simplify only the words around the technical terms. Cut any
sentence that repeats a point already made, even a good one.

Apply while drafting:
- **Separate the filing reason from the problem.** Why the GitHub issue is being
  opened ("need a GitHub issue to reference from a PR", "branch isn't tracked") is
  meta and does NOT belong in it. Capture the underlying problem or task. If the user's
  context is mostly a filing reason, ask what the real problem is before drafting.
- **Labels and assignees come from the project.** Use `github.labels` and
  `github.assignees` from this project's settings. Both empty means add none and
  do not ask; only add others if the user brings them up.
- If the GitHub issue stems from an existing branch or PR, you may reference it, and
  link it after creation (Step 3).

Ask the user to edit or approve. **Loop here** until the draft is settled.

## Step 2 - Create gate

Confirm the target repo and ask for an explicit go in one clean line, e.g.:

> Create this in `owner/repo`? Say "create it".

Do **not** paste the raw `gh` command with escaped body; it just repeats the draft. Keep
the command internal. The command that runs:

```bash
gh issue create --repo <owner/repo> --title "<title>" --body "<body>" [--label ... --assignee ...]
```

Pass `--label` and `--assignee` only for the values the settings gave, and omit
each flag entirely when its key is empty.

Offer `--web` as an alternative only if the user would rather submit it themselves:
append `--web` to open a pre-filled browser draft they click to create.

On a clear go, run it.

## Step 3 - After creation

Return the GitHub issue URL that `gh` prints.

**Link to related work.** If the GitHub issue relates to an in-flight branch or PR,
remind the user they can connect them by adding a closing keyword to the **PR body**:
`Closes #<n>` (or `Fixes #<n>` / `Resolves #<n>`), which auto-closes the GitHub issue
when the PR merges.
Under `pr.create_mode` set to `manual`, the user opens the pull request, so hand them
the line to paste and do not edit a pull request or run `gh pr` commands. Under `gh`
the line still comes from this skill; whoever opens the pull request puts it in the body.

If at any point the user says stop/cancel/never mind, abort and create nothing.
