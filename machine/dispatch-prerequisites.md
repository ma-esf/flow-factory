# Dispatch prerequisites

`/flow-conductor` launches one Claude session per issue by driving iTerm2. Four
things must hold before the first dispatch. Three of them fail in ways the
conductor cannot see: it reports a session as launched and nothing is running.

The installer checks this same list. It is written here once so the installer
and the skill cannot drift apart.

Each entry gives the probe, the output that means pass, and what the failure
looks like to someone who did not check.

## 1. iTerm2 is installed

```bash
osascript -e 'id of application id "com.googlecode.iterm2"'
```

Pass: prints `com.googlecode.iterm2`. Absent: `Can't get application id
"com.googlecode.iterm2". (-1728)`, and the probe exits non-zero.

All three dispatch blocks address iTerm2 by that bundle id and use iTerm2-only
vocabulary (`split vertically`, `create tab`, `sessions of t`). Terminal.app
does not do a worse job of it; it does none of it. There is no fallback, so this
is a hard requirement rather than a preference.

This is the one failure that is loud on its own.

## 2. macOS Automation permission is granted

```bash
osascript -e 'tell application id "com.googlecode.iterm2" to count windows'
```

Pass: prints a number. Denied, or the dialog never answered: `Not authorized to
send Apple events to iTerm2. (-1743)`.

The permission belongs to the application that sends the events, which is the
terminal the agent is running in, not iTerm2 itself. Granting it to one terminal
says nothing about another.

Run the probe rather than reading the setting. The permission is per sending
application and there is no supported way to read the grant table.

## 3. The session is not inside tmux

```bash
[ -z "$TMUX" ]
```

Pass: `$TMUX` is empty or unset.

Under tmux, iTerm2 sees a single session whose name tmux owns, so the pane
lookup in the dispatch step never matches a session name carrying the kind
prefix. The conductor does not error. It reads "no pane found" every time and
opens a fresh tab per dispatch, which is the failure the kind prefixes exist to
prevent.

## 4. `claude` resolves in the shell a new pane runs

A new pane runs whatever the iTerm2 default profile launches, so the probe has
to match that profile. The agent's own shell cannot answer this question: it
read its startup files before the agent existed, so `command -v claude` there
passes whatever the profile does.

Read the profile first:

```bash
defaults read com.googlecode.iterm2 "New Bookmarks" | grep -m1 '"Custom Command"'
```

`No` means the profile runs the user's login shell, which iTerm2 starts
interactive. Probe it with no inherited environment, so nothing leaks in from
the shell the agent is already sitting in:

```bash
env -i HOME="$HOME" TERM=xterm "$SHELL" -lic 'command -v claude'
```

`Yes` means the profile runs a named command, and the startup files that command
reads are the ones that matter. Probe with that command's own flags.

Pass: prints a path. Failure: prints nothing and exits non-zero. Then the pane
opens, `claude: command not found` scrolls past, and the conductor has already
reported the dispatch as done.

Measured 2026-09-17 on the machine the factory was written on, with
`Custom Command = No`: `-lic` found `claude`, `-lc` did not, and a bare `-c` did
not. It was on `PATH` through an interactive startup file alone. A probe fixed
at non-login and non-interactive would have failed on a machine where every real
dispatch worked, which is the wrong direction to be wrong in: it blocks work
that would have run.

## How a skill uses this list

Run all four before the first dispatch of a session, not before every dispatch.
On any failure, name the prerequisite that failed and stop. Do not dispatch the
picks that would have worked: a partial batch leaves the user tracking which
ones came up, which is the thing dispatching is for.
