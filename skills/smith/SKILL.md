---
name: smith
description: Carry out a plan or a critic report's findings with the smith subagent, in a fresh context. Run it yourself as /smith followed by the plan or findings, or a path to a file that holds them.
argument-hint: plan or review findings, or a file that holds them
context: fork
agent: smith
background: false
disable-model-invocation: true
---

# Smith

Carry out the plan, or fix the review findings, that follow. If they point to a file, read it first. If nothing follows, reply that `/smith` needs a plan or review findings, such as `/smith docs/conf/tasks/<slug>/plan.md`, and stop.

$ARGUMENTS
