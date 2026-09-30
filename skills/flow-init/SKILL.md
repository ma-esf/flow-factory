---
name: flow-init
description: Fit this project to Flow Factory from one screen. Reads the repository, proposes every setting it can find with where each came from, asks only for a test command it cannot find, and on your approval writes the settings and the tracker through the factory's installer. Use when the user types /flow-init in a project with no flow-factory.toml.
disable-model-invocation: true
---

# /flow-init

Work out every setting the repository can answer, show them on one screen,
and hand the approved answers to `./install --init`. The installer does every
write and every check. The only file this skill writes itself is a temporary
answers file outside the project and `$HOME`.

It writes into a project that has no `flow-factory.toml`, so it does not stop
on a missing file as `~/.flow-factory/settings-contract.md` says the skills
that read settings do. It stops on one that is there.

## 1. Gates

1. Take the path on the `checkout` line of
   `~/.flow-factory/install-record.txt`. No such file or line: stop, say the
   factory is not installed on this machine, and that `./install`, run from a
   factory checkout, installs it. `<checkout>/install` is the script, and
   `<checkout>/project/flow-factory.toml` is the template: every key, its
   default and its `unset:` tag.
2. The project root is `git rev-parse --show-toplevel`. When that fails, stop:
   the directory is not in a git repository, and every skill that runs git
   needs one. The check in step 4 says what else is wrong with the root.
3. `flow-factory.toml` already at the root: stop, and say this skill does not
   fit a project over existing settings. A setting is changed by editing that
   file.

## 2. Read

Propose a key only from a file or ref that exists, with a tag and a source:

- *read*: a file or ref states the value.
- *guessed*: the value follows from a name or a stack's convention, such as a
  directory called `tests` or a lockfile beside a tool's config.

A key with no source is not proposed. Take a stated value as written. Look
only at files git tracks (`git ls-files`), so a worktree or build output
under the root is no source. Run only commands that write nothing: no
`git fetch`, no install, no test run.

**`git.default_branch`**, from `origin/HEAD`, never from the current branch,
which may be a feature branch:

```bash
git symbolic-ref --short refs/remotes/origin/HEAD    # origin/develop
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= GCM_INTERACTIVE=never \
GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-$(git config core.sshCommand || echo ssh)} -o BatchMode=yes -o ConnectTimeout=5 -o UpdateHostKeys=no" \
    git ls-remote --symref origin HEAD               # ref: refs/heads/develop  HEAD
```

A clone whose `origin/HEAD` was never set has no local answer, so ask the
remote with the second, which asks for no password, keeps the project's own
ssh command and gives up on an ssh connection after five seconds. Either is
*read*, and the value is the bare name, `develop`. With neither, there is no
source, and the template's `main` stays.

**`test.command`**, run from the project root:

- *read* from a file that states it. `scripts.test` in `package.json` runs as
  `pnpm test`, `yarn test` or `bun run test` beside `pnpm-lock.yaml`,
  `yarn.lock` or `bun.lock`/`bun.lockb`, and as `npm test` otherwise. The
  placeholder `npm init` writes, which echoes "no test specified" and exits 1,
  states no command. A `test` target in a `Makefile` or `justfile`, a test step
  in CI, or the usage lines of a README or a test script count too.
- *guessed* from a test tool the project's own files name. pytest, named in
  `pyproject.toml`, `pytest.ini`, `setup.cfg`, `tox.ini`, `conftest.py` or a
  requirements file, is `uv run pytest` beside `uv.lock`, `poetry run pytest`
  beside `poetry.lock`, and `pytest` otherwise. A built-in runner counts as
  named: `cargo test` for `Cargo.toml`, `go test ./...` for `go.mod`.
- A language alone names no tool. Python with no pytest anywhere is no source.
- With `source.backend_dir` found, it is the backend's command, run from that
  directory: `cd backend && uv run pytest`. `/flow-ship-ticket` applies its
  test-first gate only there, so a frontend command tests the part it skips.

**`source.backend_dir`**: *guessed* when two top-level directories each hold
their own stack files and one is named for a frontend (`frontend`, `web`,
`client`, `ui`). The other is the backend.

**`test.dir`**: *read* from a test config that names it, such as pytest's
`testpaths`. *Guessed* from an existing `tests`, `test`, `spec` or
`__tests__` directory, inside the backend directory when there is one. Write
it from the project root, as `backend/tests`.

**`test.guide_path`**: *guessed* from a file named for testing, such as
`TESTING.md` or `docs/testing.md`.

**`docs.context`**: *guessed* from `CONTEXT.md` at the root or in `docs/`.

**`docs.glossaries`**: *guessed* from each file named `glossary.md`, in any
case, outside dependency directories, the shallowest first: the first is
where a newly settled term is written.

**`project.decision_docs`**: *guessed* from a decisions directory or file
other than `docs/adr/`, such as `docs/decisions/` or `DECISIONS.md`. Never
`docs/adr/`: the factory already reads that one.

**`app.services`, `app.start_commands`, `app.ports`**: all three or none, and
only *read*. A file must state each service's start command and the port it
listens on, as `vite --port 5173` in `scripts.dev` does. Take the port as
written, with no `{NN}` added.

Every other key keeps its template default or stays unset.

## 3. Ask

Only for `test.command`, and only when nothing states or implies it. Ask once,
in plain text, which command runs this project's tests, and say that an empty
answer leaves it unset. An answer is tagged *given*. An empty one leaves the
key unset, and its row says `/flow-ship-ticket` and `/flow-tdd` stop until it
is set. Ask nothing else.

## 4. Check

Write the proposals to a temporary answers file made with `mktemp`, outside
the project, one `key = value` line each. Write the value in the kind the
template's value has: a string in double quotes, with `"` and `\` inside it
escaped as `\"` and `\\`; a list of such strings in square brackets; `true` or
`false` bare. Leave out every key without a proposal. Then run:

```bash
"<checkout>/install" --check "<root>" "<answers file>"
```

It prints the project's gaps one per line, or `no gaps`, and writes nothing.
When it exits non-zero, show its `FAILED:` line, or its last line when there
is none. On the first check, delete the answers file and stop, with no screen
and no choice: a screen would offer *Looks right* on a check that never
passed. Name the way on: fix what the line names, or fit the project by hand
with an answers file, as the checkout's `README.md`, "Fit a project", shows.
A check after an edit is handled under *Edit a value*.

## 5. Screen

Under 15 lines, in this shape:

```
Flow Factory init: billing
  git.default_branch  develop    read     origin/HEAD
  test.command        yarn test  read     package.json scripts.test
  test.dir            test       guessed  test/ exists
  Defaults kept: pr.create_mode manual, github.attribution none, 6 more
  Writes flow-factory.toml, .cortex/, .git/info/exclude, and this project's line in ~/.flow-factory/install-record.txt.
  Kept out of git: .cortex/, flow-factory.toml and .claude/worktrees/, through .git/info/exclude,
  which stays on this machine and is never committed or pushed.
  Gaps: you cannot push to origin, gh reports READ: /flow-ship-ticket errors, and /flow-worktree-close cannot delete the remote branch. Fix: ask a repository admin for write access
```

- The first line names the project root's directory.
- One row per proposed key: value, tag, source. The three `app.*` keys share
  one row. When the rows and gaps would take the screen to 15 lines, put the
  *guessed* rows on one line, `Guessed: test.dir test, ...`; *Show all* lists
  them in full.
- The defaults line covers the keys whose template value is kept because
  their `unset:` tag is a default: it names `pr.create_mode` and
  `github.attribution`, which set what the skills do outside this machine, and
  counts the others. With no source for the default branch,
  `git.default_branch main` leads it.
- The writes line names every path `--init` writes, one of them in `$HOME`.
  The exclude file is `info/exclude` under `git rev-parse --git-common-dir`,
  which is `.git/info/exclude` in a plain repository and elsewhere in a
  submodule.
- `--init` excludes no path that `git ls-files` lists. It also leaves
  `.cortex` and `flow-factory.toml` in git when any branch or tag holds them,
  since a checkout of that ref would overwrite them. Name such a path as
  staying in git, with the ref, instead of as kept out. This prints each ref
  holding `.cortex`; run it for `flow-factory.toml` too:

  ```bash
  git for-each-ref --format='%(refname):.cortex %(refname)' refs/heads refs/remotes refs/tags |
      git cat-file --batch-check='%(objecttype) %(rest)' | grep -v ' missing$'
  ```
- `Gaps:` holds each line `--check` printed, word for word, one screen line
  each, or `none`. The script's wording is the one its tests hold.

Offer three choices with it: *Looks right*, *Edit a value*, *Show all*.
Through `AskUserQuestion`, where it exists, the screen is the question's own
text, followed by `Write these settings?`. A screen printed above the call was
left out in both interactive runs of 2026-09-29, and a yes to values nobody
saw approves nothing. Without the tool, print the screen as the whole message,
end it with `[Looks right]  [Edit a value]  [Show all]`, and wait for the
reply.

- *Edit a value*: ask for a key and its value. The key must be in the
  template, and the three `app.*` keys are given together, since the check
  fails any one of them alone. An empty value drops the proposal. The value is
  tagged *given*.
  Rewrite the answers file and go back to step 4, so every screen shows the
  answers its check read. When that check fails, show its line, undo the
  edit, and offer the choices again on the last screen that passed.
- *Show all*: every key in the template with its value and source: read,
  guessed, given, the template's default, or unset. Then offer the choices
  again.

## 6. Write

Only after *Looks right*:

```bash
"<checkout>/install" --init "<root>" "<answers file>"
```

Show its output. When it exits non-zero, the project is not fitted: show its
`FAILED:` line as the reason, keep the answers file, and stop. Once the line's
cause is fixed, the same command finishes the rest, since each write is
skipped once done, and `/flow-init` would stop at gate 3 on a settings file
already written. Otherwise delete the answers file and name the everyday
chain as the next step: `/flow-park` captures a finding, `/flow-triage` makes
it a ticket, and `/flow-ship-ticket` builds it.
