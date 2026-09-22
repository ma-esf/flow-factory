# <reader-facing title, no NN prefix>

Status: <ready-for-agent; blocked when a ticket under ## Depends on has not landed; needs-triage when something else is unresolved>
Created: <YYYY-MM-DD>
Slice <X.Y> of PRD.md. <Qualifier when one applies: "Docs only, no code." / "Promote to ready-for-agent once step 2 merges." / "May end up near-empty; that is an acceptable outcome."> <Omit this line entirely on a ticket written straight into the tracker.>

<One plain sentence saying what this ticket is. Plain language, no project jargon. Readers and tools use it as the summary.>

## Background

What a reader who was not in the conversation needs before the goal makes sense. Two parts:

- The facts the problem rests on, in plain sentences. Only what a fresh reader cannot get from the repository in a few tool calls.
- One worked example with real numbers, stepping through what happens today and ending on the wrong output. For a ticket that builds something new, the same walkthrough with today's behaviour and the behaviour after.

## Goal

What is true after this lands. Engineer-facing, not user-facing.

## Scope

Concrete. Name the real paths, and the real symbols an agent will touch (functions, fixtures, config keys). Paths tell an agent where to look; the symbol list tells it what it is looking at. No line numbers, they rot within days.

## Not in scope

Each exclusion names its owner: another slice, another feature, or a decision id.

## Acceptance

- [ ] <criterion>
      <Indented lines carry the reasoning, the wrong reading the criterion blocks, and any `Unverified:` assumption the criterion rests on. Do not compress this away: a bare one-line criterion is usually the version that passes on broken code.>
- [ ] Falsify it: break <X> on purpose, confirm this fails, and confirm <Y> still passes. Required on every ticket.

## How to verify

<The exact commands, and the output that means each one passed. Leave this section empty when the acceptance criteria already carry their commands: an empty section means check those directly.>

## Depends on

<Ticket>, at <in-review | merged to the default branch>. <Why the dependency is real. Ask for in-review only when this ticket stacks on that one's branch; "When a dependency is satisfied" in tracker-contract.md says when each form is met, and is not restated here.>
Branch base: <off the default branch | off ticket N's branch>.
Check before starting: <one command, and the output that means you are on the right base>.

Or: None, can start immediately.

## Comments
