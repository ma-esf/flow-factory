# Attribution rule

Whether text the factory writes into a hosted repository may credit the agent
that wrote it. The rule is written here once. A skill points at this file; no
skill restates it.

## The three write points

These are every place the factory writes text a hosted repository keeps:

- the commit message, `flow-ship-ticket` Stage 4 step 6
- the pull request body, `flow-pr-summary`
- the GitHub issue title and body, `flow-new-github-issue`

A skill writing at one of them reads `github.attribution` and applies the
matching rule below. `settings-contract.md`, beside this file, says how to read
the key, what its unset default is, and what to do when the settings file is
missing. Those are not repeated here.

## What counts as attribution

Attribution is any text that credits the agent, the company that makes it, the
model it runs as, or the tool it runs in. Match it by what it is, not by one
spelling.

Two forms are in use today and neither contains the other:

- a commit trailer: a `Co-Authored-By` header naming the model, with an address
  at the vendor's domain
- a line in a pull request body: an emoji, the words `Generated with`, and a
  markdown link to the tool's site

The model name inside the trailer changes between sessions, one form is a plain
header and the other is markdown, and a third point writes neither. A rule
matching one exact string misses the other cases. Match the class instead: a
trailer, a line, a footer, a badge or a link that credits the agent or its
maker, in any wording or markup.

What this does not govern: a human co-author line, and a line linking the work
to a GitHub issue or a ticket. Those stay under both values.

## Under `none`

Write no attribution at any of the three points. This is the unset default, and
it holds whatever the agent harness instructs.

That last clause is the reason this file exists. The harness instructs a session
to append attribution to a commit message and to a pull request body. A project
whose own instruction file overrides that instruction is safe for a reason that
does not travel: a project the factory was just installed in has no such file,
so the harness default wins and attribution lands in a repository whose owner
never asked for it. This rule is the override, held on the machine rather than
in a project.

## Under `tool`

Keep the attribution the harness gives, at the point the harness names, and add
nothing else. `tool` preserves a default; it does not ask a skill to invent a
credit of its own. At the three points that means:

- the commit message keeps the trailer, after the subject line
- the pull request body keeps its generated-with line
- the GitHub issue gets nothing, because the harness adds attribution to a
  commit and to a pull request body and not to a GitHub issue.
  `flow-new-github-issue` therefore writes the same text under both values.
