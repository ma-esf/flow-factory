---
name: flow-to-spec
description: Turn the current conversation into a PRD for a multi-session feature and write it to this project's tracker. No interview, just synthesis of what has already been discussed. Use when the user says "write the spec", "turn this into a PRD", "spec this out", or types /flow-to-spec. For cutting a written PRD into buildable tickets use /flow-to-tickets.
---

# flow-to-spec - the conversation becomes a PRD

Synthesis, not an interview. Everything the spec says has already been said in
this conversation; your job is to shape it, not to gather it.

Multi-session work only. A single change has no spec and no slices: it is parked
and triaged instead, `/flow-park` then `/flow-triage`.

## Where it lands

`.flow/issues/<feature-slug>/PRD.md`, and the filename is exactly `PRD.md`.
Every ticket cut from this spec carries a `Slice <X.Y> of PRD.md` line that
resolves by folder, so another filename breaks that trail for every ticket at
once.

**Write no `Status:` line.** A PRD is not a work item. `/flow-conductor` filters
the folder to `[0-9]*` and `/flow-backlog` skips `PRD.md` by name, so nothing
lists it as work. A PRD that carries `Status: ready-for-agent` anyway sits in the
ready queue as work nobody can pick up.

The rest of the tracker's conventions are in `~/.flow-factory/tracker-contract.md`.
If that file is not readable, the factory was never installed on this machine.
Say so and stop. Do not rebuild the shape from what this file describes: a spec
missing a heading is read as complete by every skill after this one.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

## Process

1. Sketch the seams you will test the feature at. Prefer existing seams and the
   highest one available. Fewer is better, one is ideal. Check them with the user
   before writing anything.
2. Write the file, then stop. Cutting it into tickets is `/flow-to-tickets`,
   which the user runs next.

## What you write

`~/.flow-factory/templates/spec.md` is the file: its headings, in its order,
ending with `## Comments`. The authoring guidance inside each of its sections is
the instruction for what to put there. Follow it; do not paraphrase it back into
a bare heading.

**Leave `## Slices` empty.** It is the seam between defining the work and cutting
it up, and `/flow-to-tickets` fills it. Slices written here are numbers nothing
points at, because the provenance line on each ticket cites the numbering that
skill assigns.

## Do not add

- **User Stories** and **Further Notes**, which many PRD templates carry.
  `## Acceptance` on each ticket pins the behaviour instead, at the point where
  an agent will actually be held to it.
- **Build order.** `## Depends on` on each ticket carries the edges, and
  `/flow-conductor` reads them to decide what can start.
