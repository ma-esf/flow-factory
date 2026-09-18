# MVP 1 skill set

The twenty-one skills MVP 1 ships, and the decisions that produced that
set.

**Scope:** which skills ship and why. Not which stage each one serves
(`skills-by-stage.md`), and not how any one of them is built.

## The set

The set is the transitive closure of the four stages' entry points, not a
hand-picked minimum. We ship whole skills: when a kept skill invokes another,
that other one ships too. Editing a reference out of a working skill costs more
than shipping the file it points at, and an MVP should already be useful
rather than only large enough to pass the acceptance run.

The one exception is a skill bound to a single project's stack. That is why
running the app is deferred below, and why dropping it is worth the edits it
forces on its callers.

- Discover: `research`, `park`
- Define: `mart-grill-with-docs`, `grilling`, `mart-triage`, `mart-reground`
- Decompose: `mart-to-spec`, `mart-to-tickets`, `mart-conductor`
- Deliver: `mart-ship-issue`, `wt-create`, `tdd`, `mart-comments-review`,
  `pr-summary`, `new-issue`, `mart-close-out`, `wt-close`
- Across stages: `mart-whatup`, the skill that prints the tracker

Three more ship although nothing invokes them, because each is named inside a
skill we keep and dropping it means editing that sentence: `sta`,
`codebase-design`, `jira-subtask`.

Twenty-one skills in total.

## Decisions behind the set

- **`research` replaces the `mart-research` fork.** The fork adds five lines to
  the upstream skill: a pinned tracker path, and a workaround for this repo
  symlinking that path into worktrees. Upstream plus the factory's own pinned
  path is the same skill without the local arrangement.
- **MVP 1 does not run the project's app.** `run-app` and `verify-delivery` are
  both deferred. Every project has a different stack, and some have no app to
  run at all, so there is no start command worth configuring up front. In MVP 2,
  ask how to start the app the first time someone needs it, then keep the answer
  in project settings.
- **Dropping those two is a contract change, not six reference edits.** An
  earlier count said six. The port map showed the real shape: a literal sentence
  travels from the ticket template through two writing skills into every ticket
  on disk, and the delivery pipeline matches that exact string to choose its
  path. The fix is the inverted default below, not a search and replace.
- **Ship-issue Stage 3 then carries the verification discipline itself.** Today
  it delegates. What has to survive the deletion: verify against the issue's own
  acceptance criteria and never invented ones, check each criterion with a
  command and keep its evidence, drop no criterion and name the ones that need
  human eyes, and report a failure with its evidence instead of repairing it.
- **Every skill is named `flow-*`.** All 21 take the prefix, including the ones
  taken from upstream unchanged. Bare names such as `triage` or `to-spec`
  collide with the upstream skills of exactly those names, which an engineer
  may already have installed; both sets sit side by side on the machine this
  one came from. 79 of the 300 mapped lines are name references. Four names are
  spelled out rather than just prefixed, because they are private
  abbreviations: `flow-status`, `flow-backlog`, `flow-worktree-create` and
  `flow-worktree-close`.
- **The tracker contract is settled** in `machine/tracker-contract.md`: three
  file shapes, ten lowercase status values, one spelling per heading, a comments
  section in every shape, and a definition of `done` that covers work producing
  no merge.
- **A ticket that says nothing gets no live verification.** Today the delivery
  pipeline calls the deferred verification skill whenever a ticket's
  `## How to verify` section is absent, and the ticket template writes a literal
  route sentence that the pipeline matches on. Invert it: silence means check
  the acceptance commands directly, and the route sentence is deleted from the
  template and from both skills that write it.
- **Two references are already dead.** `mart-grill-with-docs` points at retired
  `domain-modeling` and `mart-conductor` points at retired `triage`. Both are
  broken in the source skills today and must not ship that way.
