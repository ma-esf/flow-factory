---
name: flow-fix-agent-behavior
description: The user describes something the agent keeps doing wrong (or a rough edge in how it works) and wants it fixed at the source. This skill clarifies the problem, diagnoses the root cause, and finds the config-level lever to fix it (a CLAUDE.md line, a hook, a new or edited skill, a doc, a memory), or pushes back honestly when no config change will help. Use whenever the user reports agent misbehavior or wants to change how the agent works, says things like "you keep doing X", "stop doing Y", "the agent always/never does Z", "how do I make Claude stop...", "fix how you behave when...", or invokes /flow-fix-agent-behavior. This is for a SYMPTOM the user observed, NOT for curating a list of tips from an article; that is a different job.
---

# flow-fix-agent-behavior

## What this is for

The user noticed the agent doing something wrong, or something that grates, and wants it fixed where it actually lives: in the config that shapes the agent, not patched one conversation at a time. A complaint like "you keep reformatting code I didn't ask you to touch" should end with a concrete change to a real file (or an honest "no config change fixes this, here is why").

Your value is **diagnosis + the right lever**, not eager agreement. The most useful outcomes are often the uncomfortable ones: "the instruction is already there and you ignored it, so another sentence won't help, you need a hook" or "there is no reliable structural fix for this, catch it in review." A run that prescribes a hopeful CLAUDE.md line for a problem that line cannot solve is a failure even though it looks like help.

This skill starts from a *symptom* and diagnoses it. Starting from *advice* and curating what is worth adopting is a different job; do not turn a symptom report into a tips review.

When the lever you will change lives inside a project, check first that the
project has a `flow-factory.toml` at its root. If it does not, stop as
`~/.flow-factory/settings-contract.md` says. A machine-level lever (`~/.claude/`)
needs no such check.

## Workflow

### Phase 1: Clarify the problem (bounded)

Before hunting for a fix, make sure you actually understand the problem. Ask **one question at a time** and stop as soon as you have enough to diagnose (often just one or two questions, sometimes zero if the user's description already covers it). This is not a full grilling session, it is the minimum to avoid prescribing the wrong fix off a vague symptom.

Drive to these four, asking only for what the user has not already given:

1. **Observed behavior** What the agent actually did. Push for a concrete recent instance, not a generalization. "It rewrote my whole function when I asked for a one-line change, yesterday in file X" beats "it over-edits."
2. **Desired behavior** What the user wanted instead.
3. **Frequency and scope** One-off or recurring? In one project or everywhere? This decides whether the lever is global (`~/.claude/`) or project-local, and whether it is worth encoding at all.
4. **Their hypothesis** (optional) Do they already suspect where it comes from? They often know.

A one-off annoyance usually does not deserve a permanent config change. Say so if that is what you are seeing.

### Phase 2: Diagnose the root cause, THEN pick the lever

Do not jump from symptom to "add a line." First classify *why* it is happening, because the cause determines the kind of fix. Orient on the config to do this: read what is actually there before judging.

Config surfaces in scope as levers:

- Global `~/.claude/CLAUDE.md` and project `CLAUDE.md` (instructions, requests)
- The file `docs.context` names, the files in `docs.glossaries`, `AGENTS.md`, domain docs. Read the two keys as `~/.flow-factory/settings-contract.md` says; unset, the project has no such file
- `.claude/settings.json` hooks (run by the harness, not the model, so delivery is guaranteed even when compliance is not). Two kinds with very different costs: *blocking* (`Stop`, `PreToolUse`) refuses and forces a retry, which enforces but charges a full extra model turn every time it fires; *injecting* (`UserPromptSubmit`, `SessionStart`) adds a line every turn for a few tokens and never blocks. Injection is still a request, just one that cannot fall out of attention
- Skills (a new one, or editing an existing one)
- Subagents
- Memory files
- Process docs, and the files in `project.decision_docs` (read per the settings contract; unset, none). A decision record in `docs/adr/` is written by `/flow-grill-with-docs`, not here: hand an ADR change to it.

Then classify into one of three:

- **GAP** Nothing in the config addresses this. The model is not wrong to behave this way, it was never told otherwise. Fix: add the instruction or doc. This is the case where a CLAUDE.md line genuinely works.
- **IGNORED INSTRUCTION** The config already says it, and the model did it anyway. This is the important one, and it splits in two. **Rejected:** the instruction was in context and the model went around it. Rewording will not help, because the words were already there; the fix is a blocking hook or pushback. **Decayed:** the model honoured it early, then drifted as the session grew. Here the sentence is fine and only its delivery failed, so the fix is cheap re-injection, not enforcement. Tell them apart by checking for early compliance in the same session: obeyed-then-drifted is decay. Either way, do not prescribe "make the CLAUDE.md wording firmer" as if repetition inside one static file fixes non-compliance.
- **NO STRUCTURAL FIX** No config lever reliably changes this. See Pushback.

To tell GAP from IGNORED INSTRUCTION you have to actually look. Grep the CLAUDE.md files and relevant docs for existing wording on this topic before deciding which case you are in.

### Phase 3: Propose one lever, then stop

End the run with a short, honest proposal. Do not implement anything yet.

Structure:

- **Root cause** one line: gap, ignored-instruction, or no-structural-fix.
- **Recommended lever** the single best fix. Name the exact file and show the exact text, hook, or skill inline, so the user can read the change before anything happens. A small CLAUDE.md edit should appear in full; a hook should show roughly what it would match and do.
- **A second option only if it is a genuine tradeoff.** The case that warrants two: a cheap CLAUDE.md line that the model might still ignore, versus a hook that is more work but actually enforces. When that tension is real, show both and name the tradeoff. Otherwise give one recommendation. Do not manufacture a menu.
- **Honest confidence.** Especially flag when the fix is an instruction the model may keep ignoring: say "this is the cheap try, but if it keeps happening the only reliable fix is a hook." Do not oversell a request-based fix as a guarantee.
- **Then stop and wait for explicit approval.**

On approval, and only then:

- Doc / CLAUDE.md / context-file changes: make the minimal surgical edit and show it.
- Hooks: hand off to the `update-config` skill (hooks live in `settings.json` and the harness runs them, you do not hand-roll them).
- A new skill: hand off to the `skill-creator` skill.

Never implement a fix the user did not approve, even one you are confident about.

## Log the run

After the change is applied, or after you and the user conclude no fix is warranted, append a short dated entry to `~/.claude/agent-behavior-log.md`: what happened, the root-cause class (gap / ignored-instruction / no-structural-fix), what changed (file + lever) and why, and the scope. No-fix outcomes are worth logging too; the pattern is the point.

This is a private pattern-tracking journal. It is deliberately **not** referenced from any CLAUDE.md / AGENTS.md / memory, so no agent auto-loads it. Writing here during this skill's own run is fine, since the skill only executes when invoked. Create the file with a `# Agent behavior log` header if it is missing; put new entries at the top of the entry list (newest first), directly below the intro.

## Pushback: when there is no config fix

"No structural fix" is still a useful answer, but only if you say *why* and point to the real remedy. Do not just decline. Name which of these it is:

- **Needs you in the loop.** No instruction reliably prevents it; the honest remedy is to catch it in review. (Often the right call for judgment-heavy, case-by-case behavior.)
- **Model capability limit.** This is the model getting it wrong, not a config gap. More words will not fix what is a capability ceiling.
- **Too situational to encode.** A global rule would fire in all the cases where the current behavior is correct, causing more harm than the occasional miss. The cure is worse than the disease.

Naming the reason tells the user to stop trying to fix it with config, which saves them from piling up dead instructions.

## Guardrails

- **Diagnose before prescribing.** The split between "we never said this" (gap) and "we said it and you ignored it" (ignored instruction) is the whole game. Get it wrong and the fix is wrong.
- **Do not reflexively reach for CLAUDE.md.** It is the cheapest lever and the most overused. It works for gaps. It does not reliably work for things the model already ignores. When the cause is non-compliance, lead with the hook or with pushback.
- **One lever, shown in full.** The user should see the exact change before approving. No vague "I'll tighten the instructions."
- **Honesty over helpfulness.** "There is no good structural fix for this" is a better answer than a hopeful change that will not hold.
