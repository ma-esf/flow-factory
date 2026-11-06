# Flow Factory

Flow Factory is an agentic software factory: a set of skills, a markdown ticket
tracker and an installer that carry one piece of work from an unclear idea to a
merged, closed-out change.

It is for an engineer who builds with a coding agent and wants every piece of
work to take the same route: captured, triaged, built, verified, shipped,
closed out. It is project agnostic. An AI engineer on a retrieval system and a
software engineer on a dashboard install the same factory and use the same four
stages.

## Before you install

- **macOS.** The installer and the skills use macOS tools.
- **Claude Code.** The skills are installed into `~/.claude/skills/`, and the
  installer stops when `~/.claude` is absent.
- **git.** Both this checkout and the project you install into have to be git
  repositories, and the project needs at least one commit.

The skills that ship work need three more. `./install` reports the first in
its last step, `./install --check` the second, and nothing checks the third:

- **`gh`, installed and authenticated.** `/flow-close-out` reads it as the
  proof that a pull request merged, and `/flow-new-github-issue` cannot run
  without it.
- **A remote named `origin` carrying the default branch.** Every skill that
  compares a branch with the default branch compares with `origin`'s copy.
- **`/code-review`**, Claude Code's built-in review skill, which the factory
  does not ship. `/flow-ship-ticket` reviews with it.

One skill needs more than that. `/flow-conductor` launches a session per ticket
by driving iTerm2, so it needs iTerm2 installed and macOS Automation permission
granted to the terminal the agent runs in. `./install` checks both, the
permission only while iTerm2 is running.
`machine/dispatch-prerequisites.md` holds the probes and what each failure
looks like.

## Install

Clone this repository. Then run the installer from the checkout:

```bash
./install
```

A first install asks nothing. Before it writes outside the checkout, it names
the only two places it writes there:

- `~/.claude/skills/flow-*`, one directory per skill.
- `~/.flow-factory/`, the tracker and settings contracts, the file templates
  the skills write against, and `install-record.txt`, the list of every file
  it placed.

A `flow-*` skill directory it did not place is left alone and named. A link
where it would place a copy stops it before it writes outside the checkout:
`./install --link`, for the machine that builds the factory, places links into
the checkout instead.

Run it again to update. It lists the incoming commits and asks before it
pulls, fast-forward only, then runs the installer that pull brought and
removes every file it placed that the factory no longer ships. A declined or
failed pull leaves the checkout as it stands, and that is what it installs.
Without a terminal it does not pull unless `FLOW_FACTORY_UPDATE=yes` is set.

Nothing else is installed. No service, no database, no state shared between
projects.

The skills read their rules from `~/.flow-factory/`, outside any project, so
Claude Code asks before each read. To allow them once, add this to the `allow`
list in `~/.claude/settings.json`:

```json
{ "permissions": { "allow": ["Read(~/.flow-factory/**)"] } }
```

## Install for GitHub Copilot

The same skills, ported for GitHub Copilot: Copilot CLI and VS Code agent
mode (with `chat.useAgentSkills` on). Run the Copilot installer from the
checkout:

```bash
./install-copilot
```

It needs macOS and git, as `./install` does, but not Claude Code. It writes
only two places:

- `~/.copilot/skills/flow-*`, one directory per skill. Set `COPILOT_HOME`
  to place them under `$COPILOT_HOME/skills/` instead.
- `~/.flow-factory-copilot/`, the contracts, the templates and this
  install's own `install-record.txt`.

Each skill is built from `skills/`. Where a file needs a Copilot rewrite,
the version in `copilot/` takes its place. In the rewritten skills:

- questions go through `ask_user` (CLI) or `askQuestions` (VS Code);
- subagents run through `task` (CLI) or `runSubagent` (VS Code);
- review goes through `/review`;
- the claim marker is generated once per session;
- worktrees are worked on by path rather than entered.

The installer stops, writing nothing, if a file it would place still names
a Claude-only tool. It warns when a source has changed since its rewrite
was made: `copilot/PORTED` records the source each rewrite came from.

Updating, withdrawn skills, and skills it did not place work as they do for
`./install`. Fit a project with `/flow-init`, or by hand with
`./install-copilot --init <project root> <answers file>` (`--check` first
prints its gaps and writes nothing). It writes the same `flow-factory.toml`
and `.cortex/`, so a project fitted once works under both agents.

Both installs can live on one machine without touching each other's files.
VS Code also reads `~/.claude/skills`, so with both installed it may list
each skill twice.

What still differs under Copilot:

- `/flow-conductor` still drives iTerm2, now launching
  `copilot --name <name> -i "<command>"`. Whether iTerm2 shows that name
  as the pane title has not been verified.
- `/flow-worktree-create` no longer shares Claude Code's project memory
  with the worktree.

## Fit a project

Once per project, from the factory checkout. Write the settings you know into
an answers file, then run `--init` on the project's root:

```bash
cat > /tmp/answers.txt <<'EOF'
git.default_branch = "main"
test.command = "npm test"
EOF
./install --init ~/code/my-app /tmp/answers.txt
```

It writes `flow-factory.toml` at the project's root, creates the tracker in
`.cortex/`, and keeps both out of git through `.git/info/exclude`. A key the
answers file leaves out keeps its value from `project/flow-factory.toml`,
which lists every key and what it does.

Run it once. To change a setting afterwards, edit the project's
`flow-factory.toml`: a second `--init` rebuilds the file from the template and
the answers file, and a value edited by hand since is lost.

## Where to start

The everyday chain is `/flow-park` to capture something worth doing,
`/flow-triage` to turn a capture into a buildable ticket, and
`/flow-ship-ticket` to build, verify and ship it. `/flow-backlog` answers what
there is to work on.

- `docs/4d-system.md` - the four stages work moves through.
- `docs/skills.md` - every skill and what it is for.
- `docs/glossary.md` - the vocabulary the skills use.
- `docs/roadmap.md` - what is coming next.

## What is in this repository

| Directory | Holds | Installed |
|---|---|---|
| `skills/` | the skill sources | on the machine, once |
| `machine/` | the tracker rules and the file templates skills write against | on the machine, once |
| `project/` | the settings file and the pointer file | in each project, once |
| `copilot/` | the Copilot rewrites of the skill and machine files that need one, and `PORTED` | on the machine, by `./install-copilot` |
| `install` | the installer | not installed; it does the placing |
| `install-copilot` | the installer for GitHub Copilot | not installed; it does the placing |
| `tests/` | the installers' regression tests | not installed |
| `docs/` | the reference docs | not installed; read them here |
| `LICENSE` | the license Flow Factory is released under | not installed |
| `THIRD_PARTY_NOTICES` | the license of the text taken from other projects | not installed |

## License

Flow Factory is released under the MIT License; see `LICENSE`. Text taken
from mattpocock/skills keeps its own MIT notice, listed in
`THIRD_PARTY_NOTICES`.
