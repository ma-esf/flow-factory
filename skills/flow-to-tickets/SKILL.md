---
name: flow-to-tickets
description: Split a plan, spec, or PRD into slice tickets on this project's local tracker, each declaring what blocks it, written to .flow/issues/<feature>/. Quizzes the user on granularity and blocking edges before writing anything. Use when the user wants a spec or PRD broken into tickets, says "turn this into tickets", "split this into slices", "cut this into issues", or types /flow-to-tickets. For capturing a single unplanned finding mid-session, use /flow-park instead.
---

# flow-to-tickets - split a spec into slice tickets

Break a plan, spec, or PRD into **slice tickets**: each a narrow complete path, each declaring the tickets that **block** it.

Tracker conventions (paths, `Status:` strings, the `## Comments` section) live in `~/.flow-factory/tracker-contract.md`. Read it before writing. If it is not readable, the factory was never installed on this machine. Say so and stop, rather than rebuilding the shape from this file: a ticket missing a heading is read as complete by every skill after this one.

Check first that this project has a `flow-factory.toml` at its root. If it does not, stop as `~/.flow-factory/settings-contract.md` says.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect the decision records in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path from where the request or the data enters to where a user or consumer observes the result (schema to API to UI to test; source to staging to mart to the report or downstream table; input to retrieval to generation to the eval that scores it) - vertical, NOT a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring should be done first

</vertical-slice-rules>

Give each ticket its **blocking edges** - the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change - rename a column, retype a shared symbol - whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand-contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket - green is promised only there.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct - does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

### 5. Publish the tickets

Write one file per ticket under `.flow/issues/<feature-slug>/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). One ticket per file, never a single combined file. Create the feature directory if it does not exist. Never renumber an existing ticket.

Set each ticket's `Status:` to one of the contract's values:

- Nothing blocks it -> `ready-for-agent`. The quiz in step 4 is the specification gate, so the ticket is agent-grabbable by construction.
- Something blocks it -> `blocked`, plus a qualifier on the provenance line naming what promotes it, for example "Promote to `ready-for-agent` once step 2 merges." A blocked ticket is fully specified and still not ready to start, which is why it is not `needs-triage`: nothing about it needs evaluating, and `/flow-triage` promotes it once its blockers land.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

### 6. Fill the spec's `## Slices`

When the tickets came from a spec, write the numbered slice list into that spec's `## Slices` section, which `/flow-to-spec` left empty. Each ticket's `Slice <X.Y> of PRD.md` line has to point at a number that exists there; a spec with an empty slice list leaves every ticket cut from it pointing at nothing.

This is the one edit you make to the spec. Do NOT otherwise close or modify it: parallel agents write that one file, and git will not warn about the conflict.

### 7. The ticket body

One shape, every ticket: `~/.flow-factory/templates/ticket.md`. Its headings, in its order, and the authoring guidance inside each section is the instruction for what to put there. Follow it; do not paraphrase it back into a bare heading, and do not keep a second copy of the shape here.

Section names and the `Status:` line are tool contracts, not style. `/flow-backlog` reads `^Status:` at column 0 and the `# Title` heading, and `/flow-ship-issue` appends PR URLs to `## Comments`. When `jira.enabled` is true in this project's settings, read as `~/.flow-factory/settings-contract.md` says, `/flow-jira-subtask` also inserts a marker in the header, at the position "Header lines" in `~/.flow-factory/tracker-contract.md` gives it. Do not rename, reorder, or bold these fields.

Two things the template does not decide for you:

- **The provenance line.** Write it exactly as the contract spells it, `Slice <X.Y> of PRD.md`, pointing at a number in the spec's `## Slices`. Omit the line entirely on a ticket written straight into the tracker rather than cut from a spec.
- **`## How to verify`.** Leave it empty when the acceptance criteria already carry their commands. An empty section is a statement, and it means check those criteria directly. Do not write a route sentence to fill it: a sentence there is matched by the delivery pipeline, so an invented one sends a ticket down a path nobody chose.

Name real paths and symbols, but never line numbers: an unrelated change shifts them within days and the stale reference still reads as correct. If a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note that it came from a prototype. Trim to the decision-rich parts, not a working demo.

Two shapes, two skills: this template is for slices cut from a spec. A single unplanned finding captured mid-session keeps `/flow-park`'s shape, which deliberately has no Goal and no Acceptance, because the decision has not been made yet.
