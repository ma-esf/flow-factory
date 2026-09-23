---
name: flow-grill-with-docs
description: "A relentless interview to sharpen a plan or design before building, which writes the vocabulary and decisions down as they land: settled terms into the project's glossary, decisions into docs/adr/. Invoked by the user as /flow-grill-with-docs; no spoken phrase triggers it. For an interview that writes nothing, use /flow-grilling."
disable-model-invocation: true
---

# flow-grill-with-docs

Run a `/flow-grilling` session, and write down what it settles.

## While grilling

Two habits, on top of the questions `/flow-grilling` already asks:

- **Challenge the words.** When a term is vague, overloaded, or conflicts with what
  this project's glossaries already define, say so and make the user pick. "You said
  account. Do you mean the Customer or the User?"
- **Check the claim against the code.** When the user says how something works,
  look. When the claim is about data ("that column is never null"), look in the
  data, with a query. When it is about model behaviour ("it always returns
  JSON"), run it, more than once. Surface a contradiction at once.

## What to write, and where

Write it the moment it settles, never batched at the end.

- **A settled term** goes in the first file in `docs.glossaries`. Check terms
  against every file in the list. Unset, there is no glossary: keep challenging the
  terms, write the outcome nowhere. `~/.flow-factory/settings-contract.md` says how
  to read the key.
- **A decision** goes in `docs/adr/`, numbered next in sequence, where
  `~/.flow-factory/tracker-contract.md` pins it. Only when all three hold: hard to
  reverse, surprising to a future reader, and the result of a real trade-off between
  named alternatives. Two of three is not an ADR.

If `~/.flow-factory/settings-contract.md` is not readable, the factory was never
installed on this machine. Say so and stop. Do not pick a glossary file yourself:
this skill's whole output is text written into a project's own documents, and a
guessed path puts settled vocabulary where nobody looks for it.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

Where a target already holds examples, match what is there rather than inventing a
format.
