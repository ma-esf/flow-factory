---
name: flow-run-app
description: Starts this project's app locally from the worktree the conversation has been working on, one process per service named in `app.services`, on the ports `app.ports` gives with the two-digit suffix NN filled in. Picks the smallest free NN >= 20 unless the user passes one (e.g. `/flow-run-app 27`). Never kills a server outside the chosen ports, and asks before killing anything on them. The point is to test an in-progress branch before pushing, so the skill must run code from the *correct* worktree, not the main checkout. Use when the user says "run the app", "start the app", or invokes /flow-run-app.
---

# flow-run-app

Two things vary per invocation: the **worktree path** (which checkout's code we run) and the **port suffix `NN`** (so multiple worktrees can run side by side).

Check first that this project has a `flow-factory.toml` at its root. If it does not, stop as `~/.flow-factory/settings-contract.md` says. Then read `app.services`, `app.start_commands` and `app.ports`. The three lists are index-matched: the first service starts with the first command and listens on the first port. All three empty, stop and name `app.services`: the project has no app configured, and no command is guessed. Some empty or lengths differing is a broken settings file: name the three lengths and stop.

Port convention: every entry in `app.ports` may carry `{NN}`, a two-digit suffix that is the same across all services of one run. An entry without `{NN}` is a fixed port, and a project whose ports are all fixed runs one instance at a time. A suffix is picked whenever `{NN}` appears in any port or any start command.

## Args

Parse the invocation args left to right:

- `-check` — **inspect only**, do not launch or kill. See the "Check mode" section below.
- `-kill` — **kill this worktree's servers**, then stop. See the "Kill mode" section below.
- A bare 2-digit number (e.g. `27`) — use as the port suffix `NN`. Mutually exclusive with auto-pick.
- `--env KEY=VAL` — extra environment variable passed to **every** launched service (repeatable). Launch mode only; ignored by `-check` / `-kill`. The runner stays generic — it does not interpret the keys. Callers (e.g. `/flow-verify-delivery`) use this to force isolated state. Set ahead of the command, so these win over anything the app loads from a dotenv file.

`-check` and `-kill` are mutually exclusive modes. If both are passed, refuse and ask which one.

Examples: `/flow-run-app` (auto-pick + launch), `/flow-run-app 27` (pin NN to 27 + launch), `/flow-run-app -check` (inspect), `/flow-run-app -kill` (shut down this worktree's servers), `/flow-run-app --env KEY=VAL` (launch with extra env).

## Port patterns

Build one listener pattern per entry in `app.ports` by replacing `{NN}` with two digits, and use the union everywhere below that says "the app's ports". For `["80{NN}", "30{NN}"]` that is:

```bash
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -E ':(80[0-9][0-9]|30[0-9][0-9]) \(LISTEN\)'
```

## Check mode (`-check`)

Read-only. The user wants to know whether the current session's worktree already has servers running locally.

1. Run **step A** (identify the worktree from conversation context). Confirmation block is **not** needed — nothing will be launched or killed.
2. Find every listener on the app's ports whose process cwd is under the resolved worktree. For each matching PID, resolve its cwd: `lsof -a -p <PID> -d cwd`. Keep only processes whose cwd equals `<WORKTREE>` or starts with `<WORKTREE>/` (lsof prints the cwd without a trailing slash, and a service started from the worktree root has cwd exactly `<WORKTREE>`).
3. Report exactly:
   ```
   Worktree: <absolute path>
   Branch:   <branch>

   <one line per service, or:>
     <service>  http://localhost:<port>  (PID <pid>, from <cwd>)
     (none — nothing running for this worktree)
   ```
   List every service separately so a half-running state (one service up, another dead) is visible.
4. Stop. Do not run any further steps.

## Kill mode (`-kill`)

The user wants to shut down the local servers for the worktree this session has been working on. Only kill processes whose cwd is inside that worktree — never anything else.

1. Run **step A** (identify the worktree from conversation context).
2. Find every listener on the app's ports whose process cwd equals `<WORKTREE>` or starts with `<WORKTREE>/`, resolving cwd with `lsof -a -p <PID> -d cwd`.
3. **Surface the kill list to the user first** — print each `PORT PID COMMAND` line that will be terminated. If the list is empty, say "nothing running for this worktree" and stop.
4. Kill them:
   ```bash
   kill <pid1> <pid2> ...   # SIGTERM
   sleep 1
   # Re-check; SIGKILL anything still listening on the same ports
   ```
   Prefer SIGTERM first so the servers shut down cleanly; SIGKILL only the stragglers.
5. Re-survey to confirm the ports are free. Report:
   ```
   Stopped:
     <service>  http://localhost:<port>  (PID <pid>)
   ```
   List only what was actually stopped. Do not run any further steps.

## Steps (launch mode — default, no `-check` / `-kill`)

### A. Identify the target worktree from conversation context

The user invokes `/flow-run-app` to test code on a specific feature branch. Do **not** trust the current shell cwd — it can have drifted. Instead infer the worktree from the conversation: which worktree's files have been read/edited, which branch has been discussed, which feature is being tested, what `/flow-status` last reported.

1. Look back through the session for the worktree path most consistent with the recent work. Strong signals: the files you recently edited or read, the branch named in `/flow-status` output, the bug being fixed.
2. Run `git worktree list` (from any path inside the repo) to enumerate available worktrees, then resolve the inferred path against that list.
3. **If the target worktree is unclear or multiple plausible candidates exist, STOP and ask the user**, presenting the candidates: `worktree path — branch — last commit subject`.
4. If cwd is outside any git checkout, ask.
5. If cwd is the main checkout but the conversation has been about a worktree, prefer the worktree.

### B. Confirm with the user before launching

Print, verbatim, a short confirmation block and wait for approval:

```
About to run:
  worktree: <absolute path>
  branch:   <branch>
  feature under test (inferred): <one line>
  services: <service names from app.services>
```

If a start command names a directory (`cd <dir> && ...`) that is missing under `<WORKTREE>`, stop and report which one — don't bury it in the confirmation.

### C. Survey existing servers on the app's ports — do NOT touch them

Run the listener pattern from "Port patterns"; print `(no listeners)` when it matches nothing.

Parse and surface the findings to the user as a table (`PORT  PID  COMMAND` + cwd if available via `lsof -a -p <PID> -d cwd`). The user must see what is already running before any kill or start. Other listeners belong to other sessions or worktrees — leave them alone.

### D. Resolve the port suffix `NN`

- If the user passed a 2-digit suffix (e.g. `/flow-run-app 27`): use `NN = 27`.
- Otherwise: pick the **smallest `NN` from 20 upward** where **every** port in `app.ports` with `{NN}` filled in is free per the survey. If all 20–99 are taken, stop and tell the user.
- If neither `app.ports` nor `app.start_commands` carries `{NN}`, there is nothing to pick: a passed suffix is an error to report, and the ports are the fixed ones.

### E. If the chosen ports have something on them → STOP

Name the occupying process(es) and ask explicitly whether to kill them. Do not proceed until the user answers. (Auto-picked `{NN}` ports are free by construction, so this branch fires only when the user named a suffix or any entry in `app.ports` is fixed.)

### F. Free the chosen ports only if approved (skip if already free)

```bash
lsof -ti :<port> | xargs kill -9 2>/dev/null   # once per port in app.ports
```

Substitute the actual ports — never run the literal string.

Any `--env KEY=VAL` pairs become `export KEY=VAL KEY2=VAL2 && ` placed at the front of **every** launch command (shown as `<ENV>` below). With none passed, `<ENV>` is empty. `export`, not a bare `KEY=VAL` prefix: a prefix binds to the first simple command only, so with a command that starts `cd api && ...` the variable would reach `cd` and never the server.

### G. Start each service from the chosen worktree (background)

For each index i in `app.services`, in list order, run the i-th entry of `app.start_commands` from the worktree root, with every `{NN}` replaced by the suffix, detached from this session, its output going to a log file:

```bash
nohup sh -c 'cd <WORKTREE> && <ENV><start command i, {NN} filled in>' \
  > "${TMPDIR:-/tmp}/run-app-<NN>-<service i>.log" 2>&1 < /dev/null &
echo "PID $!"
```

`nohup` and `< /dev/null` keep the server alive after the shell command returns and stop it waiting on input. The command goes inside single quotes, so a `'` in it is written `'\''`. Record each printed PID and log path: the PID is the wrapper shell's, so readiness below still reads the listener's own PID from `lsof`. Without `{NN}`, drop `<NN>-` from the log name.

A start command that needs a sibling service's port (a frontend that proxies to a backend) writes that port into its own command in the settings file, with `{NN}`, so the substitution lines both up.

### H. Wait, then verify readiness and report

A service is ready when its own port is listening: poll `lsof -nP -iTCP:<port> -sTCP:LISTEN` per chosen port every couple of seconds for up to 60 seconds (a first run that builds a virtualenv or installs packages can take that long). Before reporting, apply the same cwd filter as `-check` to the listening PID and check it once more: a listener whose cwd is not this worktree is reported as "port <port> taken by PID <pid>, not this worktree's", and a PID that is gone on the second look is a service that bound and crashed. Read each service's log file as well (`tail -n 40 <log>`); a service that exited prints why there. Then report:

```
Running:
  <service>  http://localhost:<port>  (PID <pid>)
```

A service that never listened is reported as such with the tail of its log, and the run is not "Running".

## Rules

- **Worktree comes from conversation context, not cwd.** When in doubt, ask.
- **Never kill a process outside the chosen ports.**
- **Always survey first**, even when the user passed an explicit suffix.
- **Commands come from the settings file, never from this skill.** A missing or wrong command is reported against `app.start_commands`, not patched here.
- **State worktree + branch in plain text in the confirmation block** (step B) — that's the moment ambiguity costs the most. After approval the running block stays terse.
