---
name: flow-research
description: Investigate a question against high-trust primary sources in a subagent, then file the cited findings in this project's tracker. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated.
---

Check first that this project has a `flow-factory.toml` at its root. If it does not, stop as `~/.flow-factory/settings-contract.md` says.

Hand the research to a **subagent** (the `task` tool in Copilot CLI, `runSubagent` in VS Code), so its reading stays out of this conversation. Where it can run in the background, keep working while it reads; otherwise wait for it to report, then continue. With no subagent tool, do the research yourself in this session, to the same rules. For web sources use `web_fetch` / `web_search` in Copilot CLI, or `#fetch` in VS Code.

Its job:

1. Investigate the question against **primary sources** (official docs, source code, specs, first-party APIs), not a secondary write-up of them. For a question about data the primary source is the data itself, a query against the warehouse; for a question about a model it is the model card, the provider's own documentation and a measured run against the model. Follow every claim back to the source that owns it.
2. Write the findings to a single Markdown file, citing each claim's source.
3. Save it at `.cortex/candidates/<question-slug>.md`, written from `~/.flow-factory/templates/capture.md`. If that template or `~/.flow-factory/tracker-contract.md` is not readable, the factory was never installed on this machine. Say so and write nothing.

The findings file is a capture, not a fourth kind of file. The tracker holds three shapes and this is one of them: the findings and their citations go under `## What was observed`, and what they mean for the decision that prompted the question goes under `## Why it matters`. Keep the template's `Status:` line. Every file in that directory is read for one, so a report without one reaches no bucket in `/flow-backlog`, and research nobody can find is research nobody did.
