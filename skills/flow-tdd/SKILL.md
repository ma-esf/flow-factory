---
name: flow-tdd
description: Test-driven development. Use when the user wants to build features or fix bugs test-first, says "build this test-first" or "write the failing test first", or mentions "red-green-refactor".
---

# Test-Driven Development

TDD is the red -> green loop. This skill is the reference that makes that loop produce tests worth keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop. Every section applies on every cycle, so consult them before and during the loop, not after.

Check first that this project has a `flow-factory.toml` at its root. If it does not, stop as `~/.flow-factory/settings-contract.md` says.

When exploring the codebase, read the file named by `docs.context` in this project's settings so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you're touching. Unset, the project has no such document: take the vocabulary from the code you are reading. `~/.flow-factory/settings-contract.md` holds the rule for reading the key.

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification ("user can checkout with valid cart" tells you exactly what capability exists) and survives refactors because it doesn't care about internal structure.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Seams: where tests go

A **seam** is the public boundary you test at: the interface where you observe behavior without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam. You can't test everything, and agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

Ask: "What's the public interface, and which seams should we test?"

When the shape of that interface is itself in question (how deep the module is, where the seam belongs, what the interface should expose), use the `/flow-codebase-design` skill for the vocabulary. It is the shared source of the module, interface, depth, seam, adapter, leverage and locality terms, and it is a reference to consult, not a session to run.

## Anti-patterns

- **Implementation-coupled**: mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but behavior hasn't changed.
- **Tautological**: the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction and can never disagree with the code. Expected values must come from an independent source of truth: a known-good literal, a worked example, the spec.
- **Horizontal slicing**: writing all tests first, then all implementation. Bulk tests verify _imagined_ behavior: you test the _shape_ of things rather than user-facing behavior, the tests go insensitive to real changes, and you commit to test structure before understanding the implementation. Work in **vertical slices** instead, one test -> one implementation -> repeat, each test a **tracer bullet** that responds to what the last cycle taught you.

## Rules of the loop

- **Run every test with `test.command`.** That key in this project's settings is how this project runs its tests, read as `~/.flow-factory/settings-contract.md` says. It has no default: when it is unset, name the key, say the loop cannot run, and stop. Never guess a command from the files in the repository. The guess costs more here than anywhere else, because a command that never ran and a test correctly going red look the same, so a test that was never executed reads as progress.
- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to the review stage (see the `code-review` skill), not the red -> green implementation cycle.

## Red and green in other stacks

Two kinds of behaviour change what red and green look like without changing the loop.

When the behaviour under test is a transformation over data, the seam is the output table for a given input table. The fixture is a small input table, the expected value is the rows that should come out, and red is a failing assertion over those rows, usually against a local engine standing in for the warehouse. A test that queries an intermediate table the model does not promise is the side-channel anti-pattern above, with SQL in place of a database call.

When the behaviour under test is non-deterministic, as a model call is, one exact string is not an expected value. Assert a property of the output, a threshold, or a score over a labelled set; run the case enough times to trust the rate; and fix the seed or the temperature wherever the interface allows it. Red is then a score below the threshold and green is clearing it, not matching one sample. Where the model sits behind a seam, test what the module does with the model's reply by replacing the model with a fake that returns a fixed one, and keep the real model for the scored set.

Everything else in this file holds unchanged: the seam is still agreed first, the expected value still comes from an independent source, and a threshold lowered until the test passes is the tautological test in a new coat. [tests.md](tests.md) shows both shapes.
