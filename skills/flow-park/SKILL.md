---
name: flow-park
description: Quickly capture a tangent or side-issue discovered mid-session into the project's tracker, with the context already learned in this conversation, then hand the user straight back to what they were doing. Use whenever the user wants to note something for later without breaking focus on the current task, says things like "park this", "capture this for later", "let's not lose this", "note this tangent", "capture this but keep going", "we'll deal with this later", "/flow-park", or otherwise flags a worthwhile side-thread they do NOT want to act on right now. Do not start implementing the parked thing, and do not turn this into a planning or triage session; the whole point is a fast capture that preserves focus.
---

# flow-park

## What this is for

You're deep in one task (call it A). Mid-flow you hit something else worth keeping (call it B): a bug you noticed, a risk, an open question. Stopping to *do* B would wreck your focus on A. But B is also worth more than a one-line "TODO", because right now, in this conversation, you already know the expensive part: which files are involved, why it matters here, the caveats. That knowledge evaporates if you just jot a stub and move on.

So `flow-park` does one thing well: snapshot B into the tracker **with the context already earned in this session**, then get the user back to A. It is deliberately fast. It does not grill, quiz, explore the codebase, or plan. The context it needs is already in the conversation; harvest it, don't re-derive it.

The single most valuable thing this skill captures is the **specifics that are cheap now and expensive later**: real file paths, the mechanism, the honest caveat. A capture that a future session (or AFK agent) can pick up cold is the goal.

## How it fits the tracker

- **Nothing installed, nothing written.** If `~/.flow-factory/tracker-contract.md` and `~/.flow-factory/templates/capture.md` are not readable, the factory was never installed on this machine. Say so and stop. Do not rebuild the shape from what this file describes: a capture missing a section is worse than no capture, because every skill after this one reads it as complete. Check first that this project has a `flow-factory.toml` at its root. If it does not, stop as `~/.flow-factory/settings-contract.md` says.
- **Container**: one capture file, `.flow/candidates/<slug>.md`. `~/.flow-factory/tracker-contract.md` gives the shape and `~/.flow-factory/templates/capture.md` is what you write.
- **A capture is not a work item.** It records something seen, not something decided. Promoting it into a ticket under `.flow/issues/<feature>/` is a separate, later decision, and `/flow-triage` makes it.
- **Resume side is already covered**: don't build a "what's parked" view here. `/flow-backlog` lists these and `/flow-triage` works them. `flow-park` just creates.

## Workflow

### 1. Identify what's being parked

It's usually the thing just discussed. If it's genuinely ambiguous (the conversation touched several side-threads), ask **one** short question to pin it down, then proceed. Don't interview.

### 2. Always park as `needs-triage`

Set `Status: needs-triage` every time, no exceptions. A capture was written fast and mid-focus, without verification, so it must be looked at before anyone acts on it. Capturing and being-ready-to-work are different states: promotion to `ready-for-agent` is a separate, deliberate decision made later, when the user actually picks the item up, never at capture time.

A capture holds no plan. If a concrete approach surfaced in the conversation, it does not go in the file: the capture shape has no section for it, because a suggestion made mid-focus is not a vetted plan and triage is where the approach gets decided. Write down what you *saw* instead, in enough detail that the approach is re-derivable.

### 3. Place the file

- `.flow/candidates/<slug>.md`. No feature directory and no number: both belong to a work item, and a capture is not one yet.
- Slug: short, reader-facing, describes the problem (not the file you'd edit).

### 4. Write the file, harvesting session context

Write `~/.flow-factory/templates/capture.md`: three sections, in its order, ending with `## Comments`. The authoring guidance inside each of its sections is the instruction for what to put there. Follow it; do not paraphrase it back into a bare heading.

Two things the template does not carry:

- **The epic line.** When `tracker.epic_field` is set in this project's settings, write one header line, that field name followed by the value the user gives, at the position "Header lines" in `~/.flow-factory/tracker-contract.md` gives it. Unset, the line is not written and the user is not asked for it. `~/.flow-factory/settings-contract.md` holds the rule for reading the key; if the user has not already named the value, fold the request into step 1's one question.
- **What you were working on.** Open `## What was observed` by naming the task this interrupted, in one clause, then give the observation. A reader who picks this up cold needs to know it was seen in passing, not sought.

Pull every concrete detail from the conversation: file paths, the mechanism, the caveat you already voiced. That harvesting is the whole value, a capture with no specifics is just a stub with extra steps.

### 5. Confirm in one line, then hand back to A

Report the title, the path, and the status in a single line, then explicitly return the user to what they were doing. For example:

> Parked (`needs-triage`): `.flow/candidates/<slug>.md`. Back to A: <the next thing in A>.

Do not keep talking about B. Do not start working on B. The success condition is that the user loses zero momentum on A.

## Guardrails

- **Speed and focus beat completeness.** This is a capture, not a planning session. No grilling, no codebase spelunking, no quizzing. If you find yourself exploring to *answer* B, stop, that's the future session's job, and note the open question instead.
- **Don't implement B.** Even if the fix is a one-liner and tempting. Parking means deferring on purpose.
- **Harvest, don't re-derive.** The context is in this conversation already. Reading the chat to pull file paths is fine; opening ten files to investigate is not.
- **Respect the tracker contract.** The status string, the file location and the section list come from `~/.flow-factory/tracker-contract.md`. Don't invent a parallel system.
- **End pointing at A.** The last thing you say should put the user back on their original task.
