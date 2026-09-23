---
name: flow-verify-delivery
description: Verify a just-built feature live on its worktree branch, anchored on the ticket's acceptance criteria. Runs the app in an isolated, safe state (never real/shared data), seeds data through the feature's real ingress, runs the deterministic checks itself, and hands the human the visual ones. Use after the build, when you want to confirm the feature actually works end-to-end in the running app before opening a PR, or when the user says "verify this", "smoke test it", or invokes /flow-verify-delivery.
---

# flow-verify-delivery

Confirm a feature works **live on its branch**, not just in unit tests. This is
distinct from the automated tests (which prove units) and `/code-review` (which
reads the diff) — here you drive the running app and check it against what the
ticket promised.

It is a **check, not a repair**: report the truth, hand off, and let the human
decide. Never change code here.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says. Then read
`app.services`. Unset, name `app.services` and stop: the project has no app to
run, so there is nothing to verify live. The ticket's `## How to verify` commands
are then the whole verification.

## Inputs

- **The anchor.** Take a ticket path as an argument, or infer the ticket this
  session has been implementing (same context-reading as `/flow-run-app`). Read
  its **acceptance criteria** — they are the spine of the verification. Match the
  heading `## Acceptance` and take the checkbox lines under it, as
  `~/.flow-factory/tracker-contract.md` pins them. If you find none, say so; do
  not verify a ticket against criteria you invented. With no ticket at all,
  confirm a one-line "done looks like" with the user in-session and anchor on
  that. **Persist it nowhere** — if a one-liner needs a durable home, that's the
  signal the work warranted a real ticket. Never anchor on a GitHub issue, even
  when one exists: the tracker ticket is the contract, and the GitHub issue is
  written from it.
- **The worktree.** Inferred from conversation context, exactly as
  `/flow-run-app` does. When ambiguous, ask.

## Steps

### 1. Read the acceptance criteria and classify each

For every acceptance criterion, decide:

- **Agent-automatable** — expressible as an unattended API / CLI / file
  assertion (status codes, response shapes, persisted values). You will run it.
- **Needs human eyes** — visual, layout, UX, "looks/feels right". You will hand
  it over with exact steps.
- **Not a live check** — needs a code change or the test suite rather than the
  running app. Every factory ticket carries one: the "Falsify it: break X on
  purpose" criterion the ticket template requires. Report it as such; do not run
  it here and do not drop it.

The criteria are the spine. Every criterion must end up in one bucket — none
dropped, none added.

### 2. Decide what "isolated, safe state" means for this feature

**Non-negotiable: never write to a real or shared store** (cloud storage,
shared DBs, external queues). Read the feature's code/config to find where it
persists and which env knobs force local, throwaway state (a filesystem backend,
a temp directory such as `/tmp/verify-<branch>-<port>`). Derive them from the
code, don't assume.

### 3. Launch the app in that state via `/flow-run-app`

Call `/flow-run-app` with the safe knobs as passthrough env, so the override is
present at launch (it can't be set across separate shell calls):

```
/flow-run-app --env <KNOB>=<value> --env <KNOB2>=<value>
```

`/flow-run-app` owns the worktree/port/readiness/teardown; you own *what safe
means*. Note the port of each service it reports.

### 4. Seed the minimum data through the feature's real ingress

Seed only what the criteria need, through the **same entry points the feature
uses** (its real endpoints/actions; prefer existing dev fixtures when the
project has them). Read the code to find the ingress.

**If a criterion's data can't be cheaply seeded** (needs a full pipeline run, an
external dependency, a real upload), **say so explicitly** and route that
criterion to the human, or note it's already covered by a named automated test.
Never fake data straight into the store past the ingress (that verifies a fake
path), and never silently skip a criterion.

Read any secrets (passwords, keys) from the env / `.env` — use them, never print
them.

### 5. Run the agent-automatable checks

Hit the running app (curl / CLI). For each criterion capture the evidence (the
request + the response/status). Cover the negative cases the criteria name
(auth walls, rejected input), not just the happy path.

### 6. Report

```
Verify: <feature> on <branch>  —  <verdict>

Verified by me:
  [✓/✗] <criterion> — <evidence, e.g. HTTP 422 / value persisted>
  ...

For you to verify (open http://localhost:<port>/...):
  1. <exact step> → expect <result>
  2. ...

Could not seed (routed): <criterion> — <why> (covered by <test> / needs you)

Not a live check: <criterion> — <the test or code change that settles it>
```

### 7. On a failed check

Report it red **with the evidence** as a finding. Do **not** auto-fix and do
**not** loop silently. Verify tells the truth; it doesn't patch, and it doesn't
decide what happens next. That belongs to the user.

### 8. Teardown

**Offer** `/flow-run-app -kill` (this worktree's servers only); default to
leaving the servers up so the human can keep clicking. Ask, don't auto-kill.

## Rules

- Anchor on the ticket's acceptance criteria if a ticket exists; else a one-line
  "done looks like" the user confirms in-session (persist nothing). Every
  criterion is verified or explicitly routed, never dropped.
- Never write to real/shared stores; force local throwaway state.
- Seed through the real ingress; surface anything you couldn't seed.
- This is a check, not a repair — never edit code.
- Secrets come from the env; use them, never print them.
