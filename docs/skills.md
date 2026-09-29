# Skills

The 27 skills Flow Factory installs, grouped by the stage of `4d-system.md`
where each one does its main work. Type the slash command to invoke one.

Several skills are useful in more than one stage. Each is listed once.

## Discover

- `/flow-backlog` - list what is on the tracker, grouped by how ready each
  item is to pick up
- `/flow-research` - research a question against primary sources, then file
  the cited findings in the tracker
- `/flow-park` - capture a tangent into the tracker mid-session, without
  losing focus on what you were doing

## Define

- `/flow-grill-with-docs` - sharpen a plan through a relentless interview,
  writing the vocabulary and decisions down as they land
- `/flow-grilling` - stress-test a plan or decision through relentless
  questioning, writing nothing down
- `/flow-codebase-design` - shared vocabulary for deep modules: where a seam
  belongs, and what makes a module easy to test and navigate
- `/flow-triage` - verify a tracker item's claim, then promote it to a
  ticket, ask for what is missing, or close it with the reason kept
- `/flow-reground` - recheck an aged ticket, candidate or spec against the
  project's latest default branch

## Decompose

- `/flow-to-spec` - turn what the conversation has settled into a spec, for
  work that spans several sessions
- `/flow-to-tickets` - cut a spec into independently buildable slices, each
  naming what blocks it
- `/flow-conductor` - pick the next tickets to dispatch from one feature folder
  and launch a session per pick, without letting them collide

## Deliver

- `/flow-ship-ticket` - ship a ready ticket end to end: implement, verify,
  review, prepare the pull request, close out. Its review stage depends on
  `/code-review`, Claude Code's built-in review skill, which the factory does
  not ship
- `/flow-worktree-create` - create the worktree and branch for a piece of
  work, and mirror your agent context into it
- `/flow-tdd` - build through a failing test and the smallest implementation
  that passes it; refactoring waits for review
- `/flow-comments-review` - review the comments and docstrings beside changed
  code, and cut the ones that do not earn their place
- `/flow-pr-summary` - summarize the branch diff for a reviewer who will not
  read it line by line
- `/flow-new-github-issue` - open a GitHub issue, drafted first and created
  only on your explicit go
- `/flow-close-out` - confirm the merge landed, flip the tracker item to done,
  and remove the worktree
- `/flow-worktree-close` - remove the worktree and delete the branch once the
  merge is verified
- `/flow-jira-subtask` - turn shipped tickets into paste-ready Jira sub-tasks
- `/flow-status` - report where this session stands: branch, commits made,
  uncommitted changes, the delta against the default branch, and a line when
  the factory checkout is behind its origin
- `/flow-to-core` - cut one prose artifact (a skill, a doc, a CLAUDE.md, a
  prompt) down to what it actually does, part by part
- `/flow-fix-agent-behavior` - take something the agent keeps doing wrong to
  its root cause, then fix it at the config lever that owns it
- `/flow-stakeholder-update` - write the next "what shipped" report for
  stakeholders, continuing from where the previous one ended
- `/flow-run-app` - start the project's app from the worktree you are working
  in, each service on its own port, without touching anyone else's servers
- `/flow-verify-delivery` - drive the running app against the ticket's
  acceptance criteria in a throwaway state, and hand you the visual checks
- `/flow-ask` - ask which skill or flow fits your situation, a router over
  all of the above
