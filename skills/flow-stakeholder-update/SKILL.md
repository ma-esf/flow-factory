---
name: flow-stakeholder-update
description: Write the next "what shipped" stakeholder report into the directory `reports.stakeholder_dir` names, continuing from the day the previous one ended.
disable-model-invocation: true
---

# flow-stakeholder-update

A report a stakeholder reads to learn what changed in the product since the last
one, and how to see each change for themselves. It covers everything that
shipped: user-visible fixes and features, plus CI, deployment, platform
controls, and architecture docs.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says. Then read
`reports.stakeholder_dir`. Unset, stop and name the key: the skill finds the
previous report there and writes the new one there, and no guessed directory
does either.

## Process

### 1. Fix the window and the exclusion list

List `reports.stakeholder_dir`. Filenames read
`stakeholder-update-<DDMM>-<DDMM>-<YY>.md`, start date first. Read the second
date out of each name and take the latest one: that is the new window's start,
and today is its end. Name order runs by day before month, so `0109` sorts ahead
of `0708` while covering the later window. An empty directory means this is the
first report: ask the user for the start date.

Then read that file end to end and write down every `#N` it already names. The
date boundary alone is not enough: a report written product-only leaves internal
items from its own window unreported, and those belong in this one.

Done when you hold a start date, an end date, and the set of numbers to skip.

### 2. Enumerate every shipped item

Enumerate by merged PR, then add closed issues. A PR can merge with no issue
behind it, and an issue can close in the window with its PR merged earlier.

```bash
gh pr list --state merged --search 'merged:>=START merged:<=END' --limit 100 \
  --json number,title,mergedAt,url,closingIssuesReferences
gh issue list --state closed --search 'closed:>=START closed:<=END' --limit 100 \
  --json number,title,closedAt,url
```

Union the two, then drop the numbers from step 1.

Done when every merged PR in the window is either on your list or carries a
written reason for being off it.

### 3. Read each item in its own words

```bash
gh pr view N --json body,title,closingIssuesReferences
gh issue view N --json body,title
```

The issue body states the problem in the user's language and the PR body states
the fix, so a linked pair gives you both halves. Some PRs land with an empty
body. For those, read `gh pr diff N --stat` and the commit titles, and say what
changed from the diff.

`.flow/issues/<feature>/` holds the close-out notes for items this project's
own agents shipped. They carry what was actually verified and what was left
unverified, which is often absent from the PR body and is what makes the Test
line honest.

Done when, for each item, you can state the before, the after, and one concrete
thing to do in the product to see it.

### 4. Confirm an input for each item

For each item, find one real input the stakeholder can use that triggers the
change: a document, a record, a request, a dataset, whatever the product takes.
Search the project's own inputs or fixtures for the shape the item needs.

Every item's Input line ends in one of three states:

| State | Write |
|---|---|
| An input on hand has the shape | how to reach it, plus `(confirmed: <what you saw in it>)` |
| The change does not depend on input shape | `any input works`, plus one you already have loaded |
| No input on hand has the shape | `not confirmed.` plus what you searched and what you found instead |

Done when every item's Input line reads confirmed, any-input, or not-confirmed,
and no line names an input you did not open.

### 5. Write the report

Open with the window in the title, then two or three lines saying what the report
covers and which previous report it continues.

Group items under headings named for the benefit to the user, reusing the
previous report's headings where items fit them and adding new ones where they do
not. Headings of that kind read like `Numbers you can trust` or `Platform, CI,
deployment, and controls`.

Each item:

```markdown
**Headline: the bug fixed or the capability gained, in the user's words** ([#N](url))
- What: the feature or check this touches, one sentence.
- Before: what went wrong.
- After: what happens now.
- Test: what to do in the product and what to look for, naming the screen or step.
- Input: the outcome from step 4.
```

Link the issue when one exists, the PR otherwise.

An item still open gets the same shape with the headline led by `In progress:`,
`Before` replaced by `Currently:`, a `Status:` line saying what is left, and
`Test: not testable yet` with `Input: n/a`.

Close with a rule off, then one line counting the items by group and naming any
that stayed open, with the reason.

### 6. Deliver

Write to `<reports.stakeholder_dir>/stakeholder-update-<DDMM>-<DDMM>-<YY>.md`.
Count the item headings in the finished file and check the closing line against
that count before you report.

Report the path and the count. Do not stage or commit the file: a report of this
kind names customers and their data, so it belongs in a git-excluded directory,
and if the one configured is tracked, say so.

## Voice

Write for a stakeholder who does not open the repo.

- Name what the user sees on screen. The Input line is the one place a path
  belongs.
- Say the effect, then the number. The mechanism goes in only where the effect
  makes no sense without it.
- Name a screen or step the way the product does.
- Gloss a domain term the first time it appears.
- Keep each item's five lines to one sentence each, two where the before or after
  has a second case.
