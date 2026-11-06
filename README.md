# Flow Factory

**From an idea to a verified, merged change.**

Flow Factory connects 28 agent skills into a software delivery workflow for Claude Code and GitHub Copilot. Clarify the problem, define the work, split it into buildable tickets, and ship each ticket through implementation, tests, review, and post-merge cleanup.

The skills share project settings and a local Markdown tracker. Decisions, dependencies, acceptance criteria, and handoffs live in files rather than only in a conversation. There is no hosted service or central database.

## Quick start

### Prerequisites

- macOS for the full workflow.
- Bash, Git, and an existing project repository with a GitHub `origin`.
- GitHub CLI (`gh`), authenticated for the project, even when you open pull requests manually.
- Claude Code or GitHub Copilot, with the corresponding review capability available.
- Your project's dependencies and a working test command.

Optional: parallel dispatch through `/flow-conductor` needs iTerm2, macOS Automation permission, and the `claude` or `copilot` CLI available in new terminal panes. Run it outside tmux.

### Install

```bash
git clone https://github.com/ma-esf/flow-factory.git
cd flow-factory
```

Run the installer for your agent:

```bash
# Claude Code
./install

# GitHub Copilot
./install-copilot
```

These are machine-wide installs; you do not copy the factory into each project.

| Target | Skills | Shared rules and templates |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `~/.flow-factory/` |
| GitHub Copilot | `~/.copilot/skills/` | `~/.flow-factory-copilot/` |

The Copilot installer respects `COPILOT_HOME` when set. In VS Code, turn on `chat.useAgentSkills`. Both installs can coexist.

Rerun your chosen installer from the factory checkout to update. It attempts a fast-forward pull before refreshing the installed files.

### Fit a project

Open an agent session in the project you want to work on, then run:

```text
/flow-init
```

Review the proposed settings and approve them. This creates `flow-factory.toml` and the `.cortex/` tracker, keeping untracked local settings and tracker files out of commits through Git's local exclude file.

To fit a project by hand, run your installer with `--init <project root> <answers file>` from the factory checkout. The answers file holds `key = value` lines from the [settings template](project/flow-factory.toml).

Then describe what you want to do, or ask for the right entry point:

```text
/flow-ask
```

## Idea-to-merge workflow

Work follows four stages: **Discover, Define, Decompose, Deliver**. See the [4-D system](docs/4d-system.md) for what each stage answers.

### A feature spanning several sessions

```text
/flow-grill-with-docs
        |
/flow-to-spec
        |
/flow-to-tickets
        |
/flow-conductor .cortex/tickets/<feature>
        |
/flow-ship-ticket <ticket-path>    [one fresh session per ticket]
```

1. **Clarify:** interview the idea, record settled vocabulary and decisions.
2. **Specify:** turn the agreed conversation into a spec.
3. **Decompose:** approve independently verifiable slices and their dependencies.
4. **Dispatch:** choose tickets that can run without dependency or file collisions.
5. **Deliver:** implement and verify each ticket, review the changes, and prepare its pull request.

Specs and tickets live together under `.cortex/tickets/<feature>/`. The conductor reads their state and launches sessions; it does not implement tickets itself.

### A small change or bug fix

Skip the spec and decomposition:

```text
/flow-park
    -> /flow-triage <capture-path>
    -> /flow-ship-ticket <ticket-path>
```

A capture records the finding. Triage checks it and, when ready, turns it into a ticket with acceptance criteria. Even a small change has a ticket before delivery starts.

### What shipping includes

`/flow-ship-ticket` coordinates ticket claiming, rechecking against the latest default branch, worktree isolation, test-driven implementation, acceptance verification, code and comment review, commit approval, and pull request preparation.

Clean stages advance automatically. Failures, material decisions, required approvals, and pushing stop for your input. Say **"stop after each"** for additional gates.

**Opening a pull request is not completion.** After you merge it, resume the shipping session or invoke `/flow-close-out`. It verifies the merge, marks the ticket done, and removes the worktree and branch when safe.

## Skills

Start with `/flow-ask` when you do not know which skill fits. The [full catalog](docs/skills.md) lists all 28 skills by stage.

| Need | Skill |
|---|---|
| Investigate a question before planning | `/flow-research` |
| See queued work and readiness | `/flow-backlog` |
| Stress-test an idea without writing project documents | `/flow-grilling` |
| Explore module boundaries and test seams | `/flow-codebase-design` |
| Recheck an older spec or ticket | `/flow-reground` |
| Inspect the current session's Git state | `/flow-status` |
| Start the app in a worktree | `/flow-run-app` |
| Check the running app against ticket acceptance criteria | `/flow-verify-delivery` |

Skills hand work off through shared [tracker contracts](machine/tracker-contract.md), [templates](machine/templates/), and [settings rules](machine/settings-contract.md). Ticket statuses and headings are interfaces between skills, not formatting preferences.

## Configuration and safeguards

Edit your project's `flow-factory.toml` to change its test command, default branch, documentation paths, app services, and GitHub behavior. The [settings template](project/flow-factory.toml) documents every key and its unset behavior.

- `test.command` must be set before ticket delivery can build and verify work.
- `pr.create_mode` defaults to `"manual"`; `"gh"` permits pull request creation through GitHub CLI after approval.
- `github.create_issue` defaults to `false`; local tickets do not require matching GitHub issues.
- `app.*` is optional; set it to enable app startup and live verification.
- `jira.enabled` defaults to `false`; when on, Jira integration produces text for a person to paste, not direct Jira API updates.

You approve planning decisions, commit messages, and pushes. The workflow hands over the pull request for review and merge. These instructions are not a security sandbox: keep your agent's permission controls enabled and keep secrets and customer data out of public artifacts.

## Limitations and troubleshooting

- **Missing project settings:** run `/flow-init`. If settings already exist, edit them directly; initialization will not overwrite them.
- **Delivery stops at review:** Claude Code needs `/code-review`; Copilot needs CLI `/review` or a VS Code review subagent. The factory does not install these review capabilities.
- **Parallel sessions do not launch:** check the [Claude Code](machine/dispatch-prerequisites.md) or [Copilot](copilot/machine/dispatch-prerequisites.md) dispatch prerequisites.
- **A merged ticket still blocks other work:** run `/flow-close-out`; the conductor uses tracker status, not a background merge watcher.

The full workflow is macOS- and GitHub-oriented. Copilot dispatch launches CLI sessions even when planning from VS Code. Worktrees isolate edits, but they do not remove the need to check shared files and artifacts before parallel work.

## Contributing

Open an [issue](https://github.com/ma-esf/flow-factory/issues) to discuss a change, or submit a focused pull request.

Keep related skills consistent with the shared contracts. When changing a skill with a Copilot rewrite, update the corresponding files under [copilot/](copilot/) and its source hash in [PORTED](copilot/PORTED).

For installer changes, add regression coverage and run:

```bash
bash tests/install.sh
bash tests/install-copilot.sh
```

For workflow changes, exercise the affected path in a disposable project and describe the result in your pull request. Never include credentials or private project data in examples or reports.

## License and acknowledgments

Flow Factory is released under the [MIT License](LICENSE). Third-party skill material from [Matt Pocock's skills](https://github.com/mattpocock/skills) keeps its own MIT notice; see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for attribution and terms.
