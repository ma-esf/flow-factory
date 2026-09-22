# Flow glossary

Terms used across `4d-system.md`, `skills.md`, and `roadmap.md`.

**Scope:** what a word means, one entry each. No rules or instructions, and no
term used in only one file.

## The system

- **Flow** - one piece of work, idea to merged and closed-out slice.
- **4-D system** - the four stages: Discover, Define, Decompose, Deliver (`4d-system.md`).
- **Stage** - one of the four; ends when its question is answered.
- **Pipeline** - the numbered run inside `/flow-ship-issue`, nested in Deliver.
- **Gate** - a pipeline stop awaiting a human decision.

## Work items

- **Candidate** - untriaged work: a question, gap, finding, investigation (`<tracker>/candidates/`).
- **Issue / ticket** - a work item file under `<tracker>/issues/<feature>/`.
- **Spec** (`PRD.md`) - one per feature folder; not a work item, no status.
- **Slice** - one independently buildable piece cut from a spec.
- **Feature folder** - directory grouping a spec with its issues.
- **Tracker** - the `<tracker>/` files as a whole; conventions in `machine/tracker-contract.md`.

## Doing the work

- **Skill** - a named procedure, invoked as `/name`.
- **Session** - one agent conversation; a flow can span several.
- **Worktree** - the isolated checkout/branch an issue is built in.
- **Acceptance** - the criteria that decide an issue is done.
- **Evidence** - an observed result supporting a claim, not an assertion.
- **Verify** - check delivered behavior against acceptance.
- **Re-ground** - recheck an aged item against the latest `origin/<default branch>` before acting.
- **Close out** - after merge: flip the tracker item, clean up worktree/branch.

## Factory terms

- **Flow Factory** - the packaged product.
- **MVP** - one numbered release of the factory, useful to an engineer on its
  own. MVP 1 is the first.
- **Project agnostic** - carries no assumption about the project it runs in.
- **Agentic system** - the agent runtime, e.g. Claude Code or GitHub Copilot.
