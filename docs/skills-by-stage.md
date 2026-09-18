# Skills by 4-D stage

Which skill owns which stage of `4d-system.md`. A skill listed once, at the stage
where it produces its main output; several skills touch more than one stage in
practice.

**Scope:** one line per skill, naming the stage it serves. Not how a skill
works or why it exists.

## Discover

- `/mart-research` - research a question, write cited findings to the tracker
- `/diagnosing-bugs` - reproduce and isolate the root cause of a bug
- `/find-skills` - locate an existing skill for a capability
- `/park` - capture a raw observation and its evidence into the tracker, at any point

## Define

- `/mart-grill-with-docs` - sharpen an idea against repo docs, settle terms and decisions
- `/grilling` - stress-test a plan or decision through structured questioning
- `/codebase-design` - decide where a seam or abstraction belongs
- `/adopt-agent-advice` - decide which external agent-practice tips to adopt here
- `/mart-triage` - decide an issue's status: promote it to a ticket, ask for missing info, or close it
- `/mart-to-spec` - turn a settled idea into a spec (multi-session work only)
- `/mart-reground` - recheck an aged issue, candidate, or spec against latest `origin/main`
- `/improve-codebase-architecture` - find deepening opportunities and settle which one to pursue

## Decompose

- `/mart-to-tickets` - cut a spec into independently buildable slices
- `/mart-conductor` - print one dispatchable command per ready issue

## Deliver

- `/mart-ship-issue` - build and ship one issue end to end
- `/tdd` - build through failing tests, implementation, refactor
- `/feedback-to-fix` - take reported feedback through to a verified fix
- `/run-app` - start the app locally on paired ports to test an in-progress branch
- `/verify-delivery` - verify a built feature against acceptance criteria
- `/mart-comments-review` - review comments and docstrings beside changed code
- `/compact-scan` - find and verify code-compaction candidates, write a ranked report
- `/pr-summary` - summarize the branch diff for a reviewer
- `/mart-close-out` - close the tracker item once the PR has merged
- `/wt-close` - clean up the worktree and branch after merge
- `/jira-subtask` - turn shipped work into Jira sub-tasks
- `/resolving-merge-conflicts` - resolve an in-progress merge conflict
- `/update-architecture` - sync `ARCHITECTURE.md` after a change lands

## Retired (superseded by mart-*)

These upstream skills are switched off in this repo; their `mart-*` equivalent
covers the same ground with repo-specific behavior.

- `/domain-modeling` - absorbed into `/mart-grill-with-docs`; writes ADRs to the wrong path here
- `/grill-with-docs` - replaced by `/mart-grill-with-docs`
- `/research` - replaced by `/mart-research` (names no path on its own)
- `/to-spec` - replaced by `/mart-to-spec`
- `/to-tickets` - replaced by `/mart-to-tickets`
- `/triage` - replaced by `/mart-triage`
- `/wayfinder` - retired; claims a ticket by assigning it to a person, which a markdown tracker cannot do
- `/decision-mapping` - retired; wants its map git-tracked, but the questions it would map live in the git-excluded tracker
- `/mart-implement` - self-retired; `/mart-ship-issue` conducts the whole pipeline instead

## Not stage-specific

- `/ask-mart` - route a raw idea, bug, or "which skill?" question to the right skill
- `/sta` - session and git status snapshot
- `/handoff` - compact the conversation into a handoff doc for another session
- `/mart-status` - refresh the personal on-track cockpit (epic/milestone RAG)
- `/mart-whatup` - read-only repo backlog list, grouped by readiness
- `/stakeholder-update` - write the next "what shipped" report for stakeholders
- `/wait-what` - stop and re-pitch a message that didn't land
- `/wt-create` - create a new worktree/branch and mirror agent context into it
- `/eng` - rephrase a sentence in engineer-speak
- `/to-core` - cut a document down to its essentials
- `/writing-for-agents` - write or edit a skill or agent instructions file
- `/wizard` - interactive wizard for human-only setup steps
- `/git-guardrails-claude-code` - block destructive git commands
- `/fix-agent-behavior` - fix a recurring agent misbehavior at its source
- `/new-issue` - create a GitHub issue after explicit approval
