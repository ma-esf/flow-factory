---
name: flow-ask
description: Ask which skill or flow fits your situation. A router over the Flow Factory's user-invoked skills.
disable-model-invocation: true
---

# flow-ask

You don't remember every skill, so ask.

A **flow** is a path through the skills. Most paths run along one **main flow**, and two **on-ramps** merge onto it. Everything else is standalone. The four stages the flow passes through are Discover, Define, Decompose and Deliver; `docs/4d-system.md` in the factory checkout says what each one answers.

## The main flow: idea → ship

The route most work travels. You have an idea and want it built.

1. **`/flow-grill-with-docs`** — sharpen the idea by interview. Start here when you **have a codebase**: it's stateful, writing settled terms into the project's first glossary (`docs.glossaries`) and decisions into `docs/adr/`. (No codebase? Use `/flow-grilling` — see Standalone.)
2. **Branch — can you settle every question in conversation?** If a question needs a runnable answer (state, business logic, a UI you have to see), detour through a throwaway prototype session (see Crossing sessions):
   - write the open question and what you already know into a file, then open a fresh session against that file,
   - answer the question there with throwaway prototype code,
   - write what you learned back into the file, and reference it from the original idea thread.
3. **Branch — is this a multi-session build?**
   - **Yes** → **`/flow-to-spec`** (turn the thread into a spec) → **`/flow-to-tickets`** (split the spec into independently buildable tickets) → **`/flow-conductor`** on that folder, which picks the dispatchable tickets and launches a session per pick. Because the tickets are independent, **each ticket gets its own session**, running the shared tail below.
   - **No** → **`/flow-park`** writes the capture, **`/flow-triage`** promotes it to a ticket, then the shared tail. That is ordinary day-to-day development: no grill, no spec, no slices, but still one ticket file and one decision gate.

### The shared ship tail

Every unit ships the same way, and it is one command:

**`/flow-ship-issue <path>`**

It conducts stages 0 to 8: re-ground and claim the ticket, create and enter the worktree, build, verify against the ticket's acceptance criteria, review and commit, prepare the pull request, push and hand the pull request over, close out after the merge, then end in a receipt where every row holds an observed value.

It auto-advances through stages that come back clean and stops only for a failure, a material decision, a delegated skill's own approval, `git push`, or worktree deletion. Say "stop after each" to add gates.

You never type the stages. `/flow-reground`, `/flow-worktree-create`, `/flow-tdd`, `/flow-comments-review`, `/code-review`, `/flow-new-issue`, `/flow-pr-summary`, `/flow-close-out` and `/flow-worktree-close` all sit inside it.

Who opens the pull request is `pr.create_mode` in the project's settings: under `manual` you open it in the GitHub UI from the URL the push prints; under `gh` the skill may run `gh pr create`.

It reads a `Status:` from a ticket file, which is why a single unplanned change still needs `/flow-park` and `/flow-triage` first. There is no file-less path.

**Want to see it run, not just pass its checks?** `/flow-verify-delivery` drives the running app against the ticket's acceptance criteria in a throwaway state, after the build and before the pull request. It is standalone, not a stage, and needs the project's app described in `app.services`; it starts the app through `/flow-run-app`.

### Context hygiene

Keep steps 1–3 in **one unbroken context window** — don't compact or clear until after `/flow-to-tickets` — so the grilling, spec, and tickets all build on the same thinking. Each `/flow-ship-issue` run then starts fresh, working from the ticket file.

The limit on this is the **[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)**: the window (~120k tokens on state-of-the-art models) within which the model still reasons sharply. If a session approaches it before `/flow-to-tickets`, don't push on degraded — write a handoff file and continue in a fresh thread.

## On-ramps

A starting situation that generates work, then merges onto the main flow.

- **Bugs and requests piling up** → **`/flow-backlog`** to see what is there, then **`/flow-triage`** on each item. Triage verifies the claim and promotes the item to a buildable ticket, asks for what is missing, or closes it with the reason kept. **`/flow-conductor`** dispatches both kinds: `/flow-triage` for an item at `needs-triage` and `/flow-ship-issue` for one at `ready-for-agent`.

  Triage does most of its work on items **you didn't plan** — bug reports, parked findings, anything that arrives raw. A ticket that `/flow-to-tickets` cut from a spec is already specified, so `/flow-triage` Step 0 only promotes it once its blockers are done. That promote re-grounds first and patches a stale mechanism, but anything substantive it proposes rather than applies.

- **A question before any work** → **`/flow-research`** investigates it against primary sources in a background agent and files the cited findings in the tracker, where `/flow-triage` picks them up.

## Crossing sessions

- **A handoff file** — when a thread is full or you need to branch off (e.g. into a prototype session), write the conversation's state into a markdown file: the question, what is settled, what is open, the paths involved. You don't continue in place — you **open a new session and reference that file** to carry the context across. Use it when you want a **fresh session** but need the **current conversation preserved**.
- **`/compact`** (built-in) — stay in the **same conversation**, letting the earlier turns be summarized. Use it at **intentional breaks between phases**, when you don't mind losing the verbatim history. Don't compact mid-phase — the agent can lose its way. A handoff file forks; `/compact` continues.

## Standalone

Off the main flow entirely.

- **`/flow-grilling`** — the same relentless interview as `/flow-grill-with-docs`, but for when you have **no codebase**. Stateless: it saves nothing locally. Reach for it to sharpen any plan or design that doesn't live in a repo.
- **`/flow-status`** — where this session stands: branch, commits made, uncommitted changes, delta against the default branch.
- **`/flow-reground`** — recheck an aged ticket, capture or spec against the latest default branch before picking it up.
- **`/flow-codebase-design`** — vocabulary for deep modules: where a seam belongs, what makes a module testable.
- **`/flow-run-app`** — start the project's app from the worktree you are in, one port per service, without touching anyone else's servers.
- **`/flow-jira-subtask`** — turn shipped tickets into paste-ready Jira sub-tasks, for a project with `jira.enabled`.
- **`/flow-stakeholder-update`** — the next "what shipped" report for stakeholders, continuing from the previous one.
- **`/flow-to-core`** — cut a skill, doc or CLAUDE.md down to what it actually does.
- **`/flow-fix-agent-behavior`** — something the agent keeps doing wrong, fixed at the config lever that owns it.

## Precondition

The flows assume the factory is installed: `flow-factory.toml` at the project root and the `.flow/` tracker beside it, both placed by the factory's installer. A skill that finds no `flow-factory.toml` stops and says so.
