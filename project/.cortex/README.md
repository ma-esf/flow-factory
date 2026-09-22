# This project's work items

`.cortex/` holds this project's work items. `issues/` holds work. `candidates/`
holds something someone saw and wrote down, which nobody has yet decided is
work.

Every file is markdown, and its `Status:` line is the only source of truth for
its state. Any list or board is a reading view built from these files.

The shapes these files follow are fixed by Flow Factory, not by this project.
They were installed on the machine that created these files:

- `~/.flow-factory/tracker-contract.md` gives the file shapes, the status
  values and the headings.
- `~/.flow-factory/settings-contract.md` gives how a skill reads
  `flow-factory.toml` at the root of this project.
- `~/.flow-factory/templates/` holds one template per file shape.

Without that install everything here is still readable, because it is plain
markdown. What you cannot do is run the skills that write it.

Flow Factory <factory version>, installed <YYYY-MM-DD>.
