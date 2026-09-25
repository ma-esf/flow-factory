---
name: flow-conductor
description: Pick the next tickets to dispatch from one feature folder, list them for the user to choose from, then launch a named Claude session per pick as a vertical split, builds in one iTerm2 tab and triages in another. Checks status, dependencies and file collisions so several agents can run in parallel without conflicting. Use when the user names a feature folder to coordinate, types /flow-conductor, says "conduct", says an agent is free, or asks what to dispatch next. For a read-only backlog list across the whole project use /flow-backlog instead.
---

# flow-conductor - what to dispatch next from one feature folder

Invoked on a folder: `/flow-conductor .cortex/tickets/backend-testing`. Ask
which folder only if the conversation does not make it obvious. After that the user
types `conduct` (or "what's next", "update") to refresh. Every run does the same four
steps.

## What you do not do

- **You do not do the tickets.** You launch a terminal session per ticket and stop there.
  Never call the Agent tool: an in-process subagent has no tab the user can watch or
  interrupt, which is the whole point of dispatching.
- **You do not triage.** `needs-triage` means hand it to `/flow-triage`, not decide its scope.
- **You do not edit ticket files.** `Status:` belongs to the skills "Header
  lines" in `~/.flow-factory/tracker-contract.md` names as writing it.

## The two kinds

Every dispatch is one of two kinds. The kind decides the skill, the tab, and the
prefix on the session name. These three spellings are the only ones; everything
below says "the kind's prefix" rather than repeating them, because a prefix that
drifts between the name and the lookup makes every lookup miss.

| Kind | Skill it dispatches | Session-name prefix |
|---|---|---|
| ship | `/flow-ship-ticket` | `ship-` |
| tri | `/flow-triage` | `tri-` |

## Step 1 - read

One command. Run it every time, never answer from earlier in this conversation.

```bash
grep -m1 '^Status:' <folder>/[0-9]*.md
```

The `[0-9]*` glob keeps `PRD.md` and any other non-ticket file out of the count. This
skill and `/flow-backlog` filter differently on purpose: that one excludes `PRD.md` by
name because it promises every item reaches a bucket, and this one takes the glob
because a dispatcher wants only files it could hand to an agent, and a file whose name
does not start with a digit is not one.

That is the whole state read. No `git fetch`, no worktree or session scan. The
`Status:` line is canonical, as `~/.flow-factory/tracker-contract.md` says:
`/flow-ship-ticket` flips it to `in-progress` on pickup, `/flow-triage` flips it to
`in-triage`, and `/flow-close-out` flips it to `done` after the merge. So a triage in
flight is visible too, not only a build.

It has two failure modes, both stale state, both in the cautious direction. Work merged
and `/flow-close-out` never ran, so the ticket still reads `in-review` and you call the
work behind it blocked. Or a run was abandoned after it claimed its ticket, so the ticket
reads `in-progress` or `in-triage` with no session on it. If the user says something
merged, or that a session is gone, take it and move on.

Being wrong in the dangerous direction takes work started without `/flow-ship-ticket` or
`/flow-triage`. Both claim at pickup as their first write, so the window where a ticket
reads free while a session has it is seconds wide. Trust it: list the ticket, or do not.
Never list one hedged with "pick this only if that tab is gone". That hands the tracking
back to the user.

## Step 2 - decide

Read the **candidate files in full** - the ones at `ready-for-agent`, `needs-triage` or
`blocked`, and nothing else in the folder. Two gates:

1. **Depends on.** Every ticket it names must be satisfied, by the rule under "When a
   dependency is satisfied" in `~/.flow-factory/tracker-contract.md`. A ticket that
   names none has none.
2. **Collision.** Two candidates that write the same file cannot run at the same time.
   Judge on files, never on titles. A shared artefact that is not one file collides too:
   a table, a migration sequence, an eval set or a prompt that both tickets change. Files
   stay the default evidence. Pick which one goes first, say why in one clause, and name
   the shared file or artefact so the user can check the call.

**Read for the fact, not for a section name.** The contract fixes the headings, but it
does not make a ticket say what it touches: some name no path at all, and you have to
work out what they touch from what they describe. Grepping `## Scope` for a file list
silently misses those, so read the file.

There is no third gate. Do not ask how many agents the user has: dispatch opens a new
session per ticket, so the batch is however many candidates pass both gates.

## Step 3 - print

A count line, a numbered pick list, then one line for the rest.

~~~
27 tickets: 16 done, 2 in review, 1 in progress, 4 ready, 1 needs triage, 3 wontfix.

  1  ship  20  the importer keeps a stale cache between runs
  2  ship  22  amounts render without their declared unit
  3  tri   26  the report skips its final comparison step

Held: 11 collides with 20 (both write the same parser module) · 13 waits on 11

Pick numbers, or all.
~~~

Rules for that output:

- **The count line names every status present**, `blocked` like any other, so it sums
  to the number of ticket files in the folder. Leaving `in-review` and `in-progress`
  out of it hides work in flight. It is also the whole state report: nothing goes
  between it and the first row, no diff against the last run and no note on what
  freed a ticket. The user watched those tabs.
- **One row per dispatch:** pick number, the kind, ticket number, then a short
  plain gloss of what it is. The gloss is what the user chooses from, so it earns its
  place. Do not print the commands. The user no longer pastes them, so they are clutter;
  print one only when a launch fails and it has to be pasted by hand.
- **A `needs-triage` ticket gets a `tri` row** and `/flow-triage <path>` in place of
  `/flow-ship-ticket <path>`. Triage runs in parallel like anything else. List it even
  when the ticket looks fully specified: `/flow-triage` tells a ticket waiting
  only on its blockers from one needing a real evaluation, and promotes the first
  without re-opening its scope.
- **A `blocked` ticket whose blockers are all satisfied gets a `tri` row too**, because
  `/flow-triage` is what promotes it. One still waiting goes on the `Held:` line with
  the blocker it waits on.
- **The `-n` name is the point.** It titles the pane so the user can tell them apart, and
  it is also how you address a pane later. Build it from the kind's prefix, then the
  ticket filename cut short: `ship-20-stale-cache`, not the full slug.
- **Always a new session.** Never reuse an idle pane and never address a prompt to an
  existing one. A reused session carries stale beliefs about the default branch and about
  what has merged. The dispatched skill re-grounds from the ticket file anyway, so a cold
  start costs nothing.
- **List every ticket that passes both gates.** Parallel work on independent tickets is the
  normal case. The user picks; never pre-select, never shorten the list to what you would
  have chosen, and never rank it.
- **No note in the prompt** unless it changes what the agent does. The dispatched skill
  reads the whole ticket file, so copying its scope or open questions in just creates a
  second copy that drifts. If the ticket file is missing something, fix the ticket file.
- **Nothing dispatchable is a real answer.** Say the folder is idle and name the
  bottleneck in one clause, usually unmerged work or a dependency. Do not invent work.

## Step 4 - dispatch

The user answers with numbers or `all`. That answer is the confirmation: launch, do not
ask a second time.

**Check the prerequisites first, once per session.** Run all four probes in
`~/.flow-factory/dispatch-prerequisites.md` before the first dispatch of this
conversation. On any failure, name the prerequisite that failed and stop; do not
dispatch the picks that would have worked. Three of the four fail silently, so
skipping the check buys nothing and costs a report of sessions that never came up.
If that file is not readable, the factory was never installed on this machine. Say so
and stop rather than probing from memory.

**One tab per kind, and a pick splits beside an existing pane of its own kind.** Never
mix the kinds in one tab, and never open a second tab of a kind that already has one.

One command does it. Put the kind's prefix in place of `<prefix>`. It returns
`no <prefix> pane found` when that kind is not running yet, which is the signal
to give it a tab. Always send the `cd`, even though a new pane usually inherits its
parent's directory: that inheritance is a profile setting, not a guarantee. Pass the slash
command as `claude`'s initial prompt rather than typing it in afterwards, because there is
no way to know when a session is ready for a second line.

```bash
osascript -e 'tell application id "com.googlecode.iterm2"
repeat with w in windows
repeat with t in tabs of w
repeat with s in sessions of t
set nm to name of s
considering case
set o to offset of " " in nm
set hit to nm starts with "<prefix>"
if not hit and o > 0 and o < (length of nm) then set hit to (text (o + 1) thru -1 of nm) starts with "<prefix>"
end considering
if hit then
tell s
set n to split vertically with default profile
end tell
tell n to write text "cd <project root> && claude -n <name> \"<slash command> <path>\""
return "split beside " & nm
end if
end repeat
end repeat
end repeat
return "no <prefix> pane found"
end tell'
```

On `no <prefix> pane found`, that kind needs its tab. Put it in the window the other kind
already uses:

```bash
osascript -e 'tell application id "com.googlecode.iterm2" to tell window id <id>
tell current session of (create tab with default profile) to write text "cd <project root> && claude -n <name> \"<slash command> <path>\""
end tell'
```

Only when neither kind is running anywhere do you create a window, which arrives with its
one session already:

```bash
osascript -e 'tell application id "com.googlecode.iterm2"
set w to (create window with default profile)
tell current session of current tab of w to write text "cd <project root> && claude -n <name> \"<slash command> <path>\""
return "" & (id of w)
end tell'
```

All three blocks address iTerm2 by bundle id and use iTerm2-only vocabulary, which is
why the first prerequisite is a hard requirement with no fallback.

The user naming a window overrides the search. Every split makes the panes narrower, so
past four or so a pane stops being readable. Say so before splitting past that, and split
anyway if the pick stands: a third tab is not yours to choose as the fix.

**Other sessions may be running here.** Only ever split beside, or write into, a pane
whose name starts with one of this skill's own two prefixes. A pane you did not launch may
belong to someone else's work, and `write text` into it types into their session.

**Tab titles cannot be set from here.** A tab's `title` is read-only, `set` fails with
`-10000`, and a window's `name` fails with `-10006`. An OSC escape sequence written into a
pane does not survive either, because Claude Code rewrites its own pane title every few
seconds. The two routes that would work are the iTerm2 Python API
(`tab.async_set_title`, which needs the API switched on in Preferences) and the user
setting a fixed title by hand. Do not promise tab names. The `-n` prefix is what separates
the two tabs.

Four traps, all measured:

- Match the prefix at the start of the name, or after Claude Code's status glyph, with
  case on. A bare `contains` ignores case, so on 2026-09-24 `ship-` matched the pane of
  another session titled `✳ Ship-ticket title listing (claude)` and split beside it.
- Address a session by its `-n` name in one pass, as above. Never by tab or window index,
  and never by a window id held from earlier in the conversation: indices shift while the
  user rearranges panes, and a window id dies the moment a tab is dragged out of it.
- `session id "X"` does not resolve at application level. Walk windows and tabs.
- Do not return `index of` a tab. It cannot be coerced to text, so the call reports an
  error after the write has already landed and it reads like a failure.

**Confirm, then stop.** Re-list and say which sessions came up. Do not read pane contents
to follow their progress: the user is watching those tabs, and a launched session reports
its own result. If a launch did not appear, print that one command for hand-pasting.

## Learned rules

If a run surfaces a rule the remaining tickets need, say it and offer to put it in a doc or
a memory. Do not store it in this skill or in the feature folder.

## Editing this skill

Keep it lean; its speed is the point. The whole file loads on every `conduct`, so prefer
replacing a line to adding one, and keep the state read to the one `grep`: no `git`, no
session scan.
