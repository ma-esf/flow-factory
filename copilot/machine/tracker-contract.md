# Tracker contract

The file shapes, statuses and headings every Flow Factory skill reads and
writes. The installer places this file. A project does not change it, so a
skill only ever reads one shape.

## Where files live

`<tracker>` is `.cortex/` at the root of the project, with two children,
`tickets/` and `candidates/`. The installer creates it and adds `/.cortex` to
`info/exclude` in the common git directory, never to `.gitignore`, so git
leaves it out of commits and every worktree shares one copy. A project that
commits `.cortex/` on any branch is left as it is.

- `<tracker>/tickets/<feature>/<NN>-<slug>.md` is one work item. Numbering is
  per folder and has gaps, so the highest number is not the count.
- `<tracker>/tickets/<feature>/PRD.md` is that feature's spec.
- `<tracker>/candidates/<slug>.md` is a capture that is not yet a work item.

## Where decisions live

`docs/adr/` at the root of the project, outside `<tracker>`. One architecture
decision record per file, numbered next in sequence; in an empty directory the
first is `0001`. `/flow-grill-with-docs` is the skill that writes there.

It is outside `<tracker>` on purpose and is not a third child of `.cortex/`. A
tracker file is work in flight and stops being read once it is `done`. A
decision record outlives the work that produced it and is read by people who
never open the tracker, so it belongs with the project's documents. `docs/adr/`
is the name the wider convention already uses. A project that keeps decision
documents somewhere else as well lists those in `project.decision_docs`; this
pin is the one directory the factory writes to.

## Every file starts the same

```
# One plain sentence as the title

Status: ready-for-agent
Created: 2026-09-17
```

`Status:` is the only source of truth for state. Any list or board is a reading
view. Values are lowercase with hyphens and are matched exactly, so
`Status: Ready-For-Agent` is not a status.

Every file ends with `## Comments`, holding dated entries appended over time.
This includes a capture, because the delivery skill appends there and must
never meet a file without the section.

`PRD.md` is the one exception to the header: a spec is not work, so it carries
no `Status:` line, and skills that list work skip it by filename.

## Header lines

Every line a skill may write in the header, in the order they appear. A skill
that writes one of them points here instead of describing its own line's
position, so the positions cannot drift apart.

1. `Status:`. Required. Written at `needs-triage` by the capture writers
   `/flow-park` and `/flow-research`, and by the skills that claim, promote
   and close: `/flow-triage`, `/flow-to-tickets`, `/flow-ship-ticket` and
   `/flow-close-out`.
2. `Session: <id>`, directly after `Status:`. Transient. `/flow-triage` and
   `/flow-ship-ticket` write it when they claim, holding the session's claim
   marker, and remove it when the status leaves the value
   they claimed with, so a file at rest never carries it. `/flow-conductor` does
   not read it: it is for a person inspecting a stuck `in-progress` or
   `in-triage` file, who can then tell an abandoned run from a live one.
   The claim marker is made once per session, at the first claim, with
   `printf 'copilot-%s-%s\n' "$(date +%Y%m%d%H%M%S)" "$(openssl rand -hex 2)"`,
   and the same value is reused for every later claim in that session. Copilot
   gives a skill no session id of its own, so the marker stands in for one: its
   time tells a person how old the claim is.
3. `Jira: reported <YYYY-MM-DD>`, directly after `Status:`. Written by
   `/flow-jira-subtask` on a `done` file, so it never coexists with `Session:`.
4. `Created:`. Required.
5. `Slice <X.Y> of PRD.md`, directly after `Created:`. Only on a ticket cut
   from a spec, written by `/flow-to-tickets`. A qualifier may follow it on the
   same line, as the ticket template shows.
6. `<tracker.epic_field>: <value>`, after that. Only when the key is set,
   written by `/flow-park` and carried through a promote.

## The three shapes

**Capture.** Written by `/flow-park` and `/flow-research`, read by
`/flow-triage`. Sections:
`## What was observed`, `## Why it matters`, `## Comments`. No goal and no
acceptance: a capture records something seen, not something decided.

**Ticket.** Written by `/flow-to-tickets`, and by `/flow-triage` when it
promotes a capture into one, built by `/flow-ship-ticket`.
Sections, in order: `## Background`, `## Goal`, `## Scope`, `## Not in scope`,
`## Acceptance`, `## How to verify`, `## Depends on`, `## Comments`. A ticket
cut from a spec carries one provenance line under `Created:`, reading
`Slice <X.Y> of PRD.md`.

**Spec.** Written by `/flow-to-spec`. No `Status:` line. A paragraph saying what
the feature is, then, in order: `## Problem Statement`, `## Solution`,
`## Implementation Decisions`, `## Testing Decisions`, `## Out of Scope`,
`## Slices`, `## Comments`.

`## Slices` is the seam between defining the work and cutting it up.
`/flow-to-spec` leaves it empty; `/flow-to-tickets` fills it with numbered
slices. Each ticket's `Slice <X.Y> of PRD.md` line points at one of those
numbers, so a spec with no slice list leaves every ticket cut from it pointing
at nothing.

## Telling the shapes apart

A file with no `Status:` line is a spec. Otherwise, a file carrying
`## Acceptance` is a ticket and a file without it is a capture. Do not detect a
ticket by its provenance line: a ticket written straight into the tracker, not
cut from a spec, has none.

## Status values

| Status | Meaning |
|---|---|
| `needs-triage` | Needs evaluation. The triage queue. |
| `needs-info` | Waiting on an answer. The file names the question and who owes it. |
| `ready-for-agent` | Fully specified, ready for an unattended agent. |
| `ready-for-human` | Needs a judgment call, external access, or manual testing. |
| `blocked` | Fully specified, waiting on a ticket named under `## Depends on`. Not the triage queue: `/flow-triage` promotes it once those land. |
| `wontfix` | Will not be actioned. The file keeps the argued reason. |
| `backlog` | Deliberately not worked yet. Not a rejection, not in the queue. |
| `in-triage` | A session has claimed this to triage it. Transient. |
| `in-progress` | A session has claimed this to build it. |
| `in-review` | Open for review, waiting on review or merge. |
| `done` | Finished. See below. |

## When a dependency is satisfied

A ticket names what it waits on under `## Depends on`, one line per blocker,
each ending `at <in-review | merged to the default branch>`. A blocker at `done`
or `wontfix` always satisfies its line. A blocker at `in-review` satisfies it
only when the line asked for `in-review`: that ticket's branch is then the
branch base, which is stacking, and `/flow-ship-ticket` names it to
`/flow-worktree-create`. Once the blocker is `done` its branch is deleted, so a
`Branch base:` naming it means the default branch. Any other status leaves the
dependency outstanding.

This is the one statement of the rule. `/flow-triage` promotes a `blocked`
ticket by it, `/flow-conductor` lists one by it, and the ticket template points
at it. None of them restates it.

## One spelling per heading

`## Acceptance` is the only spelling. Never `## Acceptance criteria`, and never
criteria kept inside another section. A skill that needs the acceptance criteria
matches the heading. It does not search the file for them.

The same rule holds for every heading named above. A skill that cannot find a
required heading says so; it does not guess.

## What `done` means

The work landed and nothing is left dangling. Where the work produced a change
to merge, it is merged, and any branch or worktree it created is dealt with.
Work that produces no merge at all, such as an investigation writing a document,
still reaches `done` when its acceptance is met.
