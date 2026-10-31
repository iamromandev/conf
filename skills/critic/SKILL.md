---
name: critic
description: Review the current change for bugs, security and design issues with the critic subagent, in a fresh context. Run it yourself as /critic, optionally followed by what to review (files, a commit range, a plan or an earlier review's findings).
argument-hint: files, commit range, plan or review findings
context: fork
agent: critic
background: false
disable-model-invocation: true
---

# Critic

Review the current change. What to review, if the user named anything (files, a commit range, a plan or an earlier review's findings), follows; otherwise find the change yourself.

$ARGUMENTS
