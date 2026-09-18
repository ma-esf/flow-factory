# Flow Factory MVP 1 plan

**Status:** Settled

## 1. Problem

AI engineers and software engineers need a repeatable way to carry work from an
unclear idea to a verified, merged, and closed-out result. The current flow,
skills, tracker conventions, and project-control view were developed inside one
repository. They are not yet packaged as a project-agnostic product.

MVP 1 must prove that the process can be installed and used in a clean project
without relying on the source repository's domain, paths, client data, or local
project-control setup.

## 2. MVP 1 outcome

Flow Factory ships in numbered MVPs, each one useful to an engineer on its own.
`product-scope.md` holds that rule. MVP 1 is the first of them, and the sections below
define it.

A new user installs Flow Factory on a clean machine and completes one real flow
from Discover through Define, Decompose, and Deliver, using the factory's skills
and generated project structure, and borrowing nothing from the source
repository.

The completed flow must produce:

- a recorded discovery and decision trail;
- a defined, bounded piece of work with acceptance criteria;
- one or more executable work items with dependencies;
- an implementation in an isolated branch or worktree;
- verification evidence against the acceptance criteria;
- a reviewed and merged change; and
- a closed-out tracker item.

The same acceptance flow must work on macOS, with Claude Code.

## 3. Proposed MVP 1 scope

### 3.1 Skills

The set is settled: twenty-one skills, named and grouped by stage in
`mvp-1-skills.md`.

It is the transitive closure of the four stages' entry points, not the least
that completes one flow. We ship whole skills: when a kept skill invokes
another, that other one ships too, because editing the reference out of a
working skill costs more than shipping the file it points at.

Existing skills are source material, not ready components. Each one must remove
the source repository's paths, labels, domain vocabulary, and tool assumptions,
or declare those as project configuration.

### 3.2 Project structure

The installer must create or configure the minimum structure required by the
skills. The structure must define:

- where durable project context lives;
- where decisions and specifications live;
- where tracker issues and candidates live;
- how statuses and dependencies are represented; and
- how a fresh session resumes unfinished work.

MVP 1 supports both an existing project and a new one. The project step only
creates a folder for work items and a settings file, so it is the same step
either way.

### 3.3 Installer

An install leaves two sets of files, in two places.

On the machine, once:

- the skill files, in the folder Claude Code reads; and
- the tracker rules and ticket templates the skills write against.

Nothing else. No service, no database, no shared state between projects.

In each project, once per project:

- a folder for work items, holding issues and candidates;
- one settings file naming that project's own commands and rules, for example
  how to run its tests and how its branches are named; and
- a short pointer file saying where the rules live and which factory version
  created these files, so someone who never installed the factory can still
  read the project.

The rules and templates are fixed by the factory, not by the project, so a
skill only ever reads one shape.

The installer must:

- support macOS;
- detect Claude Code where possible;
- detect required terminal and version prerequisites;
- ask the user to confirm detected configuration;
- ask only for configuration that cannot be detected;
- install or link the skills in the supported agent environments; and
- report failures explicitly rather than leaving a partial successful-looking
  installation.

The installation method is not decided. It must be investigated before the
installer is implemented.

### 3.4 Tracker

MVP 1 needs a project-agnostic tracker contract for issues, specifications,
status, dependencies, acceptance, verification, and close-out.

Seeing the current flow and its work items is a skill that prints the tracker,
not a separate interface. The tracker files are markdown, so the agent can read
and list them directly.

## 4. Implementation decisions required

Three decisions are open. Each gets answered by building the first slice, not by
more planning.

1. What installer technology can install the factory without requiring users
   to understand its internals?
2. What is the minimum project configuration surface for project-specific
   commands, test commands, branch rules, and review rules?
3. Which versions of Claude Code and required terminal tools are supported?

Settled, and recorded with its reasons in
`mvp-1-skills.md`: which skills are in MVP 1, and which
are deferred.

## 5. Testing decisions

The first acceptance flow is a small feature in a repo that is not this one. A
feature rather than a bug fix, so the run exercises all four stages, including
Decompose. Because "it works" is less clear-cut for a feature, the issue's own
acceptance criteria decide it, not opinion on the day.

MVP 1 passes when a second engineer installs the factory on their own machine
and completes one real flow, with us watching. Two lists are the result: what
they had to ask us, and every point where the factory did not say what to do
next.

The run must include at least one intentionally invalid input or failed check,
to prove the factory reports failure instead of producing a successful
fallback.

## 6. Out of scope for MVP 1

Deferred to a later MVP, unless the decisions above change the boundary:

- a broad catalogue of skills;
- project-specific domain skills;
- starting the project's app, and live verification through a running app;
- Windows support;
- GitHub Copilot CLI support;
- VS Code Copilot support;
- git hosting other than GitHub, and what “merged” means there;
- Jira or other external tracker integrations beyond a documented manual path;
- automatic prioritisation of the backlog; and
- automatic migration of existing project trackers.

Not planned at all. The factory has ten users we can reach directly, so none of
this earns its cost:

- a user interface beyond a skill that prints the tracker;
- a hosted service or central database;
- organisation-wide dashboards and analytics; and
- multi-user permissions and enterprise administration.

## 7. Current gaps and risks

- Project-agnostic boundaries for the existing skills are not mapped. The size
  looks small: in the three largest skills, about 2% of lines name the source
  repository, its paths or its stack.
- The factory repository and generated project structure do not exist.
- macOS prerequisites have not been verified.
- There is no MVP 1 requirement-to-ticket decomposition yet.
- The source repository's development flow contains useful decisions but also
  project-specific assumptions that must not be copied blindly.

## 8. Proposed order of work

1. Define the observable end state of the first flow.
2. Investigate installation and agent integration on macOS.
3. Map existing skills into reusable core, project adapter, and deferred work.
4. Decide the tracker contract and the generated structure.
5. Create a Flow Factory PRD and implementation tickets.
6. Build the smallest vertical slice through installation and one complete flow.
7. Run the acceptance test with a second engineer.
8. Fix failures, document constraints, and decide whether MVP 1 is complete.
