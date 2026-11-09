# Avoidable Repeated Work

Did the agent spend effort it should not have needed, because it repeated an action
that was already failing or rediscovered something its instructions should have told it?

Read the raw session JSONL and count each `tool_use.id` once; resumed sessions repeat
records, and condensed renders omit the stretches that decide this rubric.

## Labels

| Label | Meaning |
|---|---|
| `pass` | No avoidable repetition, or brief recovery that changed approach after the first failure. |
| `fail` | At least one avoidable loop or rediscovery below, cited by event. |
| `insufficient_evidence` | The decisive events are missing even from the raw transcript. |

## Fail when any of these appears

- The same failing call is retried two or more times without a change aimed at the
  error it returned. A change that does not address that error does not count, and
  retries inside one call (a loop in one script) count.
- The agent probes the environment (ports, paths, tool names, commands, config, auth)
  for a fact an installed skill, rule, or project doc should have supplied, or
  supplied wrongly.
- The agent runs a documented command that a stale doc turned into a no-op or a
  failure, and only finds out late.
- The agent does what an installed instruction said to skip, then retries around it.
- The same check is rerun on an unchanged target and inputs.
- The user has to repeat a correction the agent already received in this session.

## Do not fail

- Waiting by design with a bounded cadence, retries after a change aimed at the error,
  or exploring unfamiliar code that no instruction covers.
- One failed attempt followed by a different, successful approach.
- Deliberate parallel variants: they count as one attempt.

## Record

Label, then 1–3 sentences citing the events (a quote of 15 words or fewer, or the
call), and, for a fail, the missing or stale instruction when one is identifiable.
