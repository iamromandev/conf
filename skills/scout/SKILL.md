---
name: scout
description: Find something or answer a "where/how is X" question with the scout subagent, in a fresh context. Run it yourself as /scout followed by the question, optionally with how thoroughly to look (quick, medium or very thorough).
argument-hint: question, optionally quick, medium or very thorough
context: fork
agent: scout
background: false
disable-model-invocation: true
---

# Scout

Answer the user's question, which follows. Look as thoroughly as they asked (quick, medium or very thorough), or medium if they didn't say. If no question follows, reply that `/scout` needs one, such as `/scout where is the config loaded`, and stop.

$ARGUMENTS
