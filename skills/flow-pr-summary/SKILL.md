---
name: flow-pr-summary
description: Generate a pull request summary for the current branch against its real base, written for an AI/software-engineer reviewer who does not want to read the diff line by line. Use when the user wants a PR description, PR summary, or to summarize a branch's changes for a technical reviewer.
---

# PR summary

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

`<default branch>` below is `git.default_branch` from this project's settings,
read the way `~/.flow-factory/settings-contract.md` says. Read it once, before
step 1.

## Process

### 1. Establish the scope

Run these in parallel:

```bash
git branch --show-current
git fetch origin
gh pr view --json baseRefName -q .baseRefName 2>/dev/null   # the real base, when a PR exists
```

**Resolve the base before you read anything.** When a pull request is already
open, its `baseRefName` is the base, and it is not always the default branch: the
GitHub UI can default a new pull request onto another in-flight branch while the
diff still looks right. With no pull request yet, use `origin/<default branch>`,
or the bare `<default branch>` when the remote-tracking ref does not exist. Then
run the scope commands against the base you resolved, and **name that base in the
summary** so a reader can see what the diff was taken against.

```bash
git log origin/<base>..HEAD --oneline
git diff origin/<base>...HEAD --stat
```

If the branch has zero commits ahead of the base, say so and stop.

### 2. Read the diff

Pull the full diff:

```bash
git diff origin/<base>...HEAD
```

If the diff is large, save it to a unique temp file (`mktemp /tmp/pr-diff.XXXXXX`) and Read it from there (a fixed filename can collide across parallel worktree sessions).

Skim it with three questions in mind:

- **What does this do, and why?** Name the actual mechanism (library, function, endpoint, schema field) so you have it exact; step 3 decides how much of it the reader needs by name. For a pure refactor or infra change, "why" often matters more than "what": what was wrong with the old way, what broke because of it, what specifically was checked to confirm the new way is equivalent.
- **How would I check it works?** A concrete command or smoke test the reviewer can run without extra setup.
- **What needs the reviewer's eyes specifically?** Removals, replaced behavior, schema or API changes, new or dropped dependencies, anything that would surprise them.

### 3. Write the summary

**Decide the reader, then the spine.** Name the reviewer who will actually read this PR. When the change has a product or behavior effect, that reader thinks in the product, not the code, so translate each internal symbol to what it does: a stage function becomes "the prompt-building stage", a dedup helper becomes "the later de-duplication step", a raw boolean guard becomes the rule stated in words. For a pure infra or refactor change, the reader is an engineer, and the mechanism should be named precisely instead.

**Make a worked example the spine of any behavior change.** One case with the real shape, shown before -> after as a fenced diff block or a two-line sketch. A reader believes a worked example and skims an abstract description, and the shape is what makes it believable, so an abstract example is not the substitute. When `privacy.redact_client_data` is true in this project's settings, read as `~/.flow-factory/settings-contract.md` says, keep that shape and replace any real company name or figure with a synthetic one of the same shape. Make it self-checking: show the operation the change turns on, do not hide it inside an arrow and leave the reader to reverse-engineer the numbers. Scale to the change: a typo, format-only, or generated-file PR needs neither, and forcing them in reads as padding.

**When the fix is a rule with branches, draw the case table.** If the change reads "prefer X, except when Y" or "do this here, not there", it has cases. Give each case its own row, and state the resulting behavior per row (the value shown, the path taken), never "unchanged", which is meaningless to a reader who never saw the old code. Prose lets you skip a branch you forgot to specify; a table row forces you to fill it.

The worked example, its before/after block, and the case table are the core, not prose, so the word caps below do not count them. Everything else stays inside the caps.

Word caps, counted. These are ceilings, not targets.

| Section | Cap | Include it when |
|---|---|---|
| What this changes | 140 | always |
| How to verify | 30 | a real command with an exact expected result helps |
| Needs your attention | 40 | something needs a conscious sign-off |
| Known limitations | 25 | a real gap would otherwise be filed as a bug |

Most PRs need one or two sections. Four is rare. Over a cap means delete a whole item or section, not trim every sentence.

Write plain paragraphs, not a slide deck: connected sentences the reviewer can read in one pass, not a wall of parallel bullets. Reserve bullets or numbered steps for things that are genuinely discrete or ordered (verification steps, a list of unrelated dependency bumps); when facts are related, join them into a sentence instead of stacking them as separate dashes. See "Avoiding AI-sounding output" below before writing.

Tool attribution in the body follows `~/.flow-factory/attribution-rule.md`, which
names the pull request body as one of its three write points. That rule is not
restated here.

```markdown
## What this changes

Max 140 words, in short paragraphs. Start with the problem in the reader's own words, not the code's, and make it concrete: one worked case with numbers beats describing the class of bug, under the same redaction rule as the example above. Then say what the branch does about it. Then, if the change decides something on its own, say when it does not act.

Keep technical and domain terms exact, and gloss a domain term on first use (spell out an abbreviation the first time it appears). Use plain words around them. Name a function or file only when the reader cannot find it otherwise, since the diff already holds those names.

## How to verify

Max 30 words. One or two steps, each a real command with its exact expected result. Say what new tests cover in product terms; a test file or class name is a bare pointer the reader cannot parse ("3 new cases for an expired session token", not "3 new `TestSessionTokenExpiry` cases"). Skip the section when the command is obvious. If you already verified something nontrivial, say what you ran and what you got instead of asking the reviewer to redo it.

## Needs your attention

Max 40 words. Only what needs a conscious sign-off: removed behavior, new or dropped dependencies, schema or API changes, anything destructive, behavior changes in shared code paths. State each as the product-visible change the reviewer approves, not the code that carries it ("a total now rounds the same way as the rows it sums", not "routed through one shared rounding helper"); a sentence built only from function, file, and variable names belongs in the diff. One sentence per item, written as a plain sentence, never a bullet with a bolded lead-in.

## Known limitations

Max 25 words. Only a real gap the branch leaves open that a reviewer would otherwise file as a bug. One sentence. Rare.
```

### 4. Cut to the caps

Count the words in each section. Read the draft once asking only "does this change what the reviewer does next?" and delete what does not: restatement, context they already have, anything visible in the diff. Deleting a whole section beats trimming every sentence. Keep exact numbers, commands, removed behavior, and anything needing sign-off.

Then re-check every product-level paraphrase against the diff. Translating code into plain language is where a wrong claim slips in, so confirm the before/after, the numbers, and the cases match what the code actually does.

### 5. Deliver

Print the summary directly to the user, wrapped in one fenced code block. Your output is rendered as markdown in the terminal, so an unfenced summary reaches the user's clipboard already rendered: the `##` headings and the backticks are gone, and the PR body arrives as flat paragraphs.

Then write it to `/tmp/pr-body-<name>.md`, where `<name>` is the branch with every `/` turned into `-`, because a prefix such as `feat/` would otherwise name a directory that does not exist. Use the Write tool (heredocs are blocked in worktree sessions). Never ask permission for that write, because the file is throwaway. Do not write the summary anywhere durable unless asked.

Close with a numbered choice the user can pick or type, never a yes/no question:

1. Copy the PR summary to the clipboard, ready to paste as the PR body
2. Edit the PR summary

Copying replaces what the user was holding, so it stays their call. On 1, run `pbcopy < /tmp/pr-body-<name>.md`, confirm with `pbpaste | wc -c`, and report the count. On 2, rewrite, print, and offer the same choice again.

Offer option 1 only when `command -v pbcopy` succeeds. `pbcopy` is macOS only, and it copies text the user already has: the summary is printed above and the file path is named. Where there is no clipboard, drop the option rather than running a command that is not there.

Who opens the pull request is `pr.create_mode` in this project's settings. Under
`manual` the user opens it and this skill never runs a command that creates one.
Under `gh` it may run `gh pr create` after an explicit approval. Either way the
summary is text for the pull request body, and this skill does not push.

## Style notes

- **Write for the reviewer who has not seen this code.** Keep the technical and domain terms exact, and use plain words around them. Precision belongs in the terms, not in the sentence structure.
- **No restating the diff.** If a sentence could be replaced by "see the diff", remove it.
- **Test plan is concrete.** "Verify the feature works" is useless; a real command or a specific click is useful.
- **Be honest about removed behavior.** It's the single most common thing reviewers miss. Always check for `-` lines in the diff that delete features, not just refactor.
- **No em dashes.** Use commas, parentheses, or separate sentences.

## Avoiding AI-sounding output

The most common way this reads as machine-written: a bullet list where every line leads with a **bolded term followed by a colon**, all phrased in identical parallel structure. It's scannable, but nobody's PR description actually reads like that. Write it like an engineer explaining the change to a teammate, not like a slide.

- Default to prose. A short paragraph that connects two related facts with "which," "so," or "since" reads as one coherent thought; the same two facts as separate dashes read as a report.
- Vary how paragraphs open. If every section starts with "This also..." or "This confirms...", rewrite at least one.
- Only reach for a bullet or numbered list when the items are genuinely a flat, unordered set (dependency bumps) or a real sequence (verification steps). A list of causally-related facts is not that.
- Cut hedging and meta-commentary ("it's worth noting that," "importantly,"). State the fact.
- Re-read the draft once as if you were the reviewer skimming it in Slack, not grading it against the template. If a sentence would make a real engineer wince, rewrite it.
- Write in ASD-STE100 Simplified Technical English: short sentences, one idea per sentence, plain words, active voice.
