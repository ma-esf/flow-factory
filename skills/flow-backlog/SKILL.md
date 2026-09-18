---
name: flow-backlog
description: List this project's local task backlog so the user can decide what to work on. Scans the tracker's issues and candidates, reads each file's Status line, and presents a scannable list grouped by how ready each item is to pick up. Read-only: it never edits a file, flips a Status, runs git, or starts a task. Use this whenever the user asks what they can work on, what's on the backlog / list / tracker, what's next, what issues are open, "what's up", or types /flow-backlog. This is about the TRACKER BACKLOG, not the session/git snapshot (that's /flow-status).
---

# flow-backlog - What's on the tracker

Read-only. When invoked, scan this project's tracker and present a scannable list of what there is to work on, grouped by how ready each item is to pick up. The point is a fast "what can I work on" answer.

Do NOT edit any file, change a `Status:`, run git, or start work. End with a single pointer line and stop.

Two sources, one shape. `~/.flow-factory/tracker-contract.md` gives both:

- **Issues** - `.flow/issues/<feature>/*.md`. Work items.
- **Candidates** - `.flow/candidates/*.md`. Captures: something seen, not yet decided to be work.

Every file in both carries a `Status:` line, so both are read the same way and sorted into the same buckets. What tells them apart in the report is the id, which keeps its `issues/` or `candidates/` prefix.

If `~/.flow-factory/tracker-contract.md` is not readable, the factory was never installed on this machine. Say so and stop. The buckets below repeat that contract's statuses, and a listing built from the repeat rather than the contract is a guess wearing the shape of a report.

## Step 1 - Collect

```bash
find .flow/issues .flow/candidates -name '*.md' ! -name 'PRD.md' -type f | LC_ALL=C sort | while read -r f; do
  st=$(grep -m1 -iE '^Status:' "$f" | sed -E 's/^[Ss]tatus:[[:space:]]*//;s/[[:space:]]*$//')
  title=$(grep -m1 -E '^#[[:space:]]' "$f" | sed -E 's/^#+[[:space:]]*//')
  rel=${f#.flow/}; rel=${rel%.md}
  printf '%s\t%s\t%s\n' "${st:-NO-STATUS}" "$rel" "${title:-(no heading)}"
done
```

Output is one line per item: `status <TAB> issues/feature/NN-slug | candidates/slug <TAB> title`.

`PRD.md` is excluded by name. A PRD is a spec, not work: the contract gives it no `Status:` line at all, so it would otherwise land in Uncategorized and push a file nobody can pick up into a view that promises pickable work. That is the one deliberate exclusion, and naming the file is the point: `/flow-conductor` filters on `[0-9]*` instead, which also drops an issue whose filename does not start with a digit. That trade suits a dispatcher choosing what to run. It does not suit this skill, which promises that every item reaches a bucket.

## Step 2 - Present the report

Sort each item into one bucket by its status (mapping below), then print the buckets in the order below. Skip a bucket that has no items.

**Render each bucket as one markdown table.** Sort the rows by the Item value so same-feature rows cluster together. Columns are `Item | What it is | Status`, in every bucket that has a table:

- **Item** = the full identifier, `issues/<feature>/<NN>-<slug>` or `candidates/<slug>` (e.g. `issues/search/07-stale-index-after-rename`), copyable into other flows.
- **What it is** = a short plain-English explanation, not the title. Read the file's opening sentence, or its `## What was observed` block, and compress it to one clear sentence, roughly 12-18 words, jargon-light. Do not just copy the `# Title`. Never include company names or figures.
- **Status** = the raw status string.

Print the bucket's `###` header, then its table. Never put an em dash in a cell you write.

Buckets and the statuses they hold, in order:

### Ready to pick up
`ready-for-agent`, and nothing else. Every other status is work nobody can hand to an agent today, so anything else in this bucket makes it worthless as an answer.

### Needs you, not an agent
`ready-for-human`. Just as ready, different picker.

### In flight
`in-triage`, `in-progress`, `in-review`

### Needs attention
`needs-triage`, `needs-info`. Every capture `/flow-park` writes arrives here, because `needs-triage` is the only status it sets.

### Parked on purpose
`backlog`. Not a queue item and not a rejection, so the open question is whether it is time to work this, which is `/flow-triage`'s call.

### Wontfix
`wontfix`. Include only if any exist.

### Done
`done`. Do not enumerate these. Print one line with the count, e.g. `Done: 2 (not listed)`.

### Uncategorized
Any item whose status is missing, or is not one of the ten values in `~/.flow-factory/tracker-contract.md`. Same `Item | What it is | Status` columns, so nothing is silently dropped. Omit the header if there are none.

The contract matches a status value exactly, so `Status: Ready-For-Agent` is not `ready-for-agent` and belongs here. That is the intended answer, not a bug to work around: a file landing in Uncategorized is how a misspelled status becomes visible.

Finish with a single pointer line, then stop. For example: "Name an item (e.g. `issues/search/07`) to start work, or open a file to read it." Do not open, edit, or act on anything.

## Format rules

- Pure read. No git, no fetch, no edits, no `Status:` changes.
- Report only what the files contain; never invent tasks or statuses.
- Keep it tight and scannable: `###` bucket headers, one markdown table per bucket, no emoji.
