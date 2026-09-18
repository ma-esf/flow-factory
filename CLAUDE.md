# Project Instructions

Global behavioral rules live in `~/.claude/CLAUDE.md`. This file is
project-specific only.

## Local-only, for now

This repository has no git remote and must not get one, and nothing may be
pushed, until the owner explicitly allows it. Commit locally as normal. If a
step needs a remote, stop and ask.

The git identity is set on this repository alone, using the GitHub noreply
form. Do not change it, and do not set a global identity on this machine.

## Other sessions may be working here

Several agent sessions build this repository at once, sharing one working tree
with no isolation. Never run `git add -A`, `git add .`, `git add <directory>`
or `git commit -a`. Run `git status` first and stage by explicit filename. If
you see changes you did not make, leave them alone and say so.

`git commit --amend` needs its own guard. Another session can commit between
your commit and your amend, and the amend then rewrites their commit, not
yours. Check `git log -1` immediately before amending and stop if the tip is
not the commit you made. This has already happened once; the recovery was
`git reset --soft` back to their commit, with the fix committed on top.

## The tracker is not here

The issues that build this repository live in another checkout on this machine,
which the owner can point you at. Nothing here tracks the work.

## `docs/` is a copy that will drift

The specification in `docs/` was copied from that same checkout. When the two
disagree, this copy is what a reader of this repository gets, so fix it here.

## No client content

The skills this factory ships were written inside a corporate repository. Never
carry a client company name, a real figure, or a path from that repository into
this one.
