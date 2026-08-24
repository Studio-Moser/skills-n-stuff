# Memory integration (optional)

Memory is optional and Harness-owned. PM expresses domain intent only through a
Harness Request's `context.memory` field; it never discovers or calls a memory
provider.

## At Frame

- Add `recall` intents for prior blockers, conventions, failed runs, or in-flight
  work relevant to the approved slice.
- Set `enabled` from the project's memory configuration; `null` means false.
- Treat returned enrichment as bounded context, never authority to widen the slice.

## At Wrap

- Add a `capture` intent only for a durable decision, convention, gotcha, or outcome.
- Harness performs capture only after the accepting workflow reproduces proof.
- Do not save secrets, one-off details, provider state, or facts already in Git.

Harness resolves canonical project scope. If memory is unavailable, continue from
repository state and leave optional Harness memory identifiers empty.
