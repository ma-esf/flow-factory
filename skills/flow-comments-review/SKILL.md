---
name: flow-comments-review
description: Review comments and docstrings added or left beside changed code in a branch or PR. Flag incorrect, stale, fragile, redundant, and verbose text, then suggest deletion or a minimum sufficient rewrite. Use for comment reviews on the current branch, a named branch, or a PR number. Read-only; use /code-review for code defects.
---

# /flow-comments-review

Read-only. Judge the comments this branch touched, present concise findings, stop.

Your output is a report. Reading, grepping, and opening cited files is the work: a
finding without the evidence in hand is a guess, and guesses are what make a
comment review worthless. Applying the rewrites, committing, and posting to the PR
are a separate job, and the user asks for that in a later turn.

## Input - resolve target and base

Accept, in order:

1. **A PR number** (`104`, `#104`). Its base is that PR's own `baseRefName`.
2. **A branch name.** If it has an open PR, use that PR's `baseRefName`, else this
   project's default branch.
3. **Nothing.** The current branch, resolved as in 2, including work not committed yet.

The default branch is the `git.default_branch` key in this project's settings, read
as `~/.flow-factory/settings-contract.md` says. Never write a branch name into this step:
in a repository whose default branch is `master`, a guessed remote ref does not
exist, and a base that quietly falls back computes the whole review against the
wrong diff.

If `~/.flow-factory/settings-contract.md` is not readable, the factory was never installed on this machine. Say so and stop. Do not derive the default branch from the repository instead: `git ls-remote` showing one branch is the repository answering, not the project, and a guess that happens to be right is the failure this rule exists to catch.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

```bash
git fetch origin --quiet
git branch --show-current
gh pr view "$TARGET" --json number,baseRefName,headRefName 2>/dev/null
```

Read `baseRefName` rather than assuming the default branch. A stacked branch has
another branch as its base, and a PR's base can be set wrong in the UI while its
diff still looks right. Name the base you used in the report so the reader can
check it.

Diff from the merge-base, so the report covers this branch's own work and not commits
the base gained meanwhile. Diffing straight against a moved base invents findings.

```bash
BASE_AT=$(git merge-base "origin/$BASE" HEAD || git merge-base "$BASE" HEAD)  # bare "$BASE" if origin/$BASE is absent
[ -n "$BASE_AT" ] || { echo "STOP: base \"$BASE\" resolves neither as origin/$BASE nor as $BASE"; exit 1; }
CURRENT=$(git branch --show-current)
HEAD_REF=$(gh pr view "$TARGET" --json headRefName -q .headRefName 2>/dev/null)
if [ -z "$TARGET" ] || [ "$TARGET" = "$CURRENT" ] || [ "$HEAD_REF" = "$CURRENT" ]; then
  RANGE="$BASE_AT"        # current branch, by name or by its PR number: reaches the working tree, so uncommitted comments count
else
  RANGE="$BASE_AT HEAD"   # a PR or another branch: their working tree is not yours to review
fi
git diff $RANGE --stat
git ls-files --others --exclude-standard   # untracked: no diff sees these, read them whole
```

The guard is not defensive noise. Without it an unresolved base leaves `BASE_AT`
empty, `git diff $RANGE --stat` collapses to a bare `git diff`, and the review covers
the uncommitted change alone and exits 0, which reads as clean.

On `STOP`, report the base you tried and end the review. Do not substitute another
base, and above all not the current branch: that comparison is empty and reads as a
clean report about work nobody reviewed.

When the diff and the untracked list are both empty, say so and stop.

## Step 1 - Collect the two sets

Every added line with its real file and line number:

```bash
git diff -U0 $RANGE | awk '
  /^\+\+\+ b\// { f = substr($0, 7); next }
  /^@@/ { match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
  /^\+/ && !/^\+\+\+/ { print f ":" n ": " substr($0, 2); n++ }
'
```

**Set A** is the comments in that output: comments this branch wrote. Group adjacent
line comments and each block comment or docstring into one review unit. Read the
surrounding code before judging it; verbosity is visible only at the block level.

**Set B** is comments the branch did *not* touch, sitting on code it did. Read the
full diff (`git diff $RANGE`, widen with `-U10` when a comment sits
just outside a hunk) and look through the context lines for a comment that survived
while the code under it changed. Set B holds the highest-value findings, because a
comment nobody edited is a comment nobody re-read.

Docstrings, block comments, trailing comments, and YAML or JSX comments all count.
So do SQL comments, Jinja comments in a dbt model, the `description:` fields in a dbt
`schema.yml`, a markdown cell in a notebook, and a comment inside a prompt template.
That list is examples of one class, prose beside code that a reader trusts, not the
set: anything of that class the diff touched is in scope.

## Step 2 - Judge Set A

Apply Tier 1 to every comment.

1. **Necessary:** Delete it mentally. If the code, names, types, test name, fixture,
   and assertions still communicate the same thing, flag it for deletion.
   Useful exceptions include units, domain mappings, invariants, safety constraints,
   workarounds, and navigation that the code cannot express.
2. **Minimum sufficient:** Keep only the smallest statement that preserves the
   necessary information. Default to one sentence or two short lines. Longer text
   must carry distinct facts the reader needs at that location.
3. **Rationale over narration:** Prefer the reason, constraint, or consequence.
   Remove walkthroughs of visible control flow, setup values, arithmetic, assertions,
   and log messages. A useful `what` comment such as `# columns C..V` still passes
   when the code cannot express that mapping.
4. **Durable:** State the current invariant, not the history of the change. Treat
   *now*, *previously*, *old*, and *no longer* as warning signs. Regression tests may
   name the prevented failure when that is their contract.
5. **Scoped:** Place the fact at the narrowest location it governs. A function
   docstring explains its contract; an inline comment explains one surprising choice.
   Do not repeat the same rationale at the module, function, and test levels.
6. **Complete and precise:** The text reaches its conclusion, names ambiguous
   referents, and avoids claims broader than the code supports. Scrutinize *both*,
   *only*, *always*, *every*, and *never*.
7. **Executable where possible:** If a name, type, assertion, helper, or test can
   express the fact clearly, recommend that instead of prose. Do not request code
   changes merely to remove a useful comment.

Apply Tier 2 only when relevant; each check earns one grep or file open.

8. **Pointer:** Can a fresh clone resolve every reference? Prefer a stable file and
   symbol over a bare issue number, line number, or commit SHA.
9. **Source:** Does the cited source establish the exact claim? Open it and verify.
10. **Synchronization:** If the comment says two places agree or instructs a manual
    update, identify both places and confirm the instruction remains correct.

### Minimum sufficient rewrites

For each flagged comment, choose the first adequate outcome:

1. **Delete** when no information is lost.
2. **Encode** in a name, type, assertion, or test when that is clearly better.
3. **Rewrite** as the shortest complete statement of the missing information.

Preserve causal content. Prefer `X because Y` or `Do X so Y` over a paragraph that
reconstructs the implementation. Do not retain examples, counts, or history unless
they are required to apply the constraint correctly.

For tests, assume the test name, fixture, and assertions form the primary narrative.
A test comment earns its place only by explaining a surprising fixture choice,
domain rule, tolerance, or regression that those elements cannot make clear.

For docstrings, describe the caller-facing contract, invariant, side effect, or
failure mode. Remove internal walkthroughs that duplicate the body.

## Step 3 - Judge Set B

One question per surviving comment: **does the code under it still do what it says?**
Open both sides of the diff. Report what the new code contradicts. A comment merely
sitting near an edit is not a finding.

## Avoid mechanical style rules

- Do not enforce a hard word or line limit. Apply minimum sufficient instead.
- Do not apply "why, not what" literally. Units, domain mappings, and navigation
  can be useful `what` comments.
- Do not flag a long comment solely for length. Identify the duplicated or
  unnecessary information and provide a shorter complete rewrite.
- Do not require TODO ownership unless the repository has that policy.

Two defect classes sit outside this review: a comment that was true when written and
drifted later (Set B reaches only what this diff touched), and a fact measured from a
binary or an external service, which needs a test to own it. Name either when you see
it, and leave it as a flag rather than implying the question set settles it.

## Step 4 - Present

Open with the base you diffed against, the size of each set, and how many you are
flagging.

Group findings by severity, most severe first:

- **Wrong** - the code, or a source it cites, contradicts it.
- **Fragile** - true today, dies on a likely edit elsewhere.
- **Verbose** - carries useful information in more words or locations than needed.
- **Noise** - adds nothing, or is unfinished.

Each finding carries `file:line`, the comment verbatim, the question number it fails,
one sentence of evidence, and one copy-pasteable outcome: **Delete**, **Encode**, or
**Rewrite**. Rewrites must themselves satisfy the minimum sufficient standard.

Close with the count that passed, so coverage is visible. Every comment in Set A and
Set B is either a finding or inside that count.

Then stop. Say that you can apply the rewrites, post them as PR comments, or both,
and wait to be asked.

## Style

- Lead with the finding, then the evidence.
- Keep each finding to the shortest complete explanation.
- No em dashes. Use commas, parentheses, or separate sentences.
- Quote the comment as it is, including its typos. The user is judging their own text.
