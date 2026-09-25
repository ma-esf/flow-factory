---
name: flow-grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or says "grill me", "stress-test this plan", "poke holes in this", or "interview me about this design".
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled. Those are the questions you can ask _now_, without guessing at answers you haven't heard yet. Ask each round with the `AskUserQuestion` tool, never as typed questions in chat. One call is one round and holds at most four questions: when the frontier is larger, ask the four that unblock the most of the tree and leave the rest for the next round. The context a question needs goes in its text and its option descriptions. Every question gets your recommended answer as its first option, its label ending "(Recommended)". A question about the user's own situation is no exception: recommend your best guess from what you have heard. An open question still gets two to four likely answers; the tool adds "Other" for the rest.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, a row count or a distribution that lives in data, a model's output on one input that lives in a run, etc.), dispatch a sub-agent to find it, rather than asking the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report. Ask the rest of the frontier now. The _decisions_ are the user's, so put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms, through the same tool, that you have reached a shared understanding.
