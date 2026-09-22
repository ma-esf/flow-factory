# Settings contract

How a skill reads one project's settings. The rule is written here once. A
skill points at this file; no skill restates it.

## Where the file is

`flow-factory.toml`, at the root of the project the skill is working in. The
installer places it from `project/flow-factory.toml` in the factory repository.

This fixes the settings path only. Where a project's tracker files live is a
separate question, still written `<tracker>/` everywhere in the factory.

## How to read a key

The file is flat. Every key is one `key = value` line and there are no
`[section]` headers, so a full dotted key such as `git.default_branch` appears
literally in the file. Find that line and take its value.

Values are TOML: a string in double quotes, a list in square brackets, `true`
or `false` bare. A list is ordered, and a skill that depends on the order says
which position it means.

A key is **unset** when its value is empty (`""` or `[]`) or when its line is
absent. Every key in the template carries an `unset:` tag naming one of the
three behaviours below.

## What unset means

An empty value is a statement, not an omission. The project is saying it has no
such thing, and the three behaviours keep the two kinds of nothing apart.

- **default** - the key's comment in the template names a value. Use it and
  carry on. The project had no reason to differ.
- **does not apply** - drop the sentence the key feeds. Do not substitute a
  placeholder, do not point at a file that may not exist, and do not ask. A
  project with no glossary has no glossary. A skill that re-points that sentence
  at an invented path is worse than one that never wrote the sentence.
  When the dropped sentence is one of a counted set, the count goes with it: a
  rule that says "search three angles" becomes two. Do not keep the number and
  do not invent a replacement.
- **stop** - the skill cannot do the step and no guess is defensible. Name the
  unset key and stop. `test.command` is the case: a guessed test command reports
  a pass for a run that never happened.

## When to look

A skill that reads a settings key, or writes into the project, checks that
`flow-factory.toml` is at the project root before its first step. A skill that
only reads the tracker and writes nothing does not check, and says nothing about
settings.

Both halves are needed. Checking only in the skills that read a key lets a skill
that writes files read no key at all and create them in a project nobody asked.
Checking in every skill makes a listing skill refuse to read plain markdown,
which the pointer file the installer places promises stays readable without the
factory.

The check goes at the skill's opening gate, not at the step that happens to
touch a key. A key can be optional, so a skill that notices the missing file
only because it reached one notices nothing on the run where that key is not
needed.

## When the file is missing

Stop. Say the project has no `flow-factory.toml`, so the factory was never
installed here. Do not fall back to the defaults.

A missing file is not an empty value. An empty value is a project that
answered. A missing file is a project nobody asked, and every default is then a
guess about a repository nobody described. The factory must report a failure
rather than produce a plausible fallback, and assuming `main` in a repository
on `master` is that failure exactly.

## Four rows rewritten

Four lines from four skills, as the port map classified them, and the sentence
each becomes under this rule. Two are substitutions and two are conditionals,
because a rule that only substitutes passes on most keys and is still wrong.

**`flow-worktree-create:45`, `BASE` hardcoded to `origin/` plus one branch
name** -> Set `BASE` to `origin/`
followed by `git.default_branch`. The same key, used bare, serves the line that
says a branch is based on the latest default branch.

**`flow-close-out:30`, "this repo squash-merges, so ancestry checks lie"** ->
When `github.merge_strategy` is `squash`, `git merge-base --is-ancestor` reports
landed work as unmerged, so gate on an empty diff against the default branch
instead. Under `merge` the ancestry check is sound and the empty diff answers
nothing, the branch head being its own merge base. The row is a worked example of
the rule, not what shipped: neither question is right alone, so `/flow-close-out`
asks both in order and reads no key here.

**`flow-park:51`, `Epic: <roadmap epic id>`** -> When `tracker.epic_field` is
set, write one header line, that field name followed by the value the user
gives. Unset, the line is not written and the user is not asked for it.

**`flow-grill-with-docs:31`, "the settled term goes in one hardcoded root
document"** ->
Write the settled term into the first file in `docs.glossaries`. Check terms
against every file in the list. Unset, there is no glossary: keep challenging
the terms, write the outcome nowhere.
