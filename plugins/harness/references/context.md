# Context

Every Harness request chooses one context mode. The mode controls how much prior
session state reaches an executor; it does not widen authority.

## Modes

- `fresh`: start an isolated session with the handoff packet and durable project
  instructions only. This is the default for delegated implementation, bulk
  research, and independent review.
- `fork`: inherit full parent context when correctness depends on the complete
  conversation and the runtime supports faithful inheritance.
- `hybrid`: provide a stable project/session brief, a bounded handoff packet, and
  targeted live lookup for changing facts. This is the default for a
  continuation that depends on prior decisions.

Do not use `fork` merely for convenience. An independent review uses `fresh` so
the review is not primed by the implementer's reasoning. Its separate approval
rule is owned by [routing.md](routing.md).

## Durable and transient context

Durable context includes repository instructions, committed project artifacts,
stable configuration, and a project-scoped memory brief when available.
Transient context includes current task state, uncommitted diff state, command
results, temporary artifacts, and unresolved blockers. Put only the bounded
transient facts needed for the task into the handoff.

Changing facts are looked up at execution time rather than frozen into a durable
brief. If faithful inheritance is unavailable, do not label a reconstructed
summary as `fork`; use `hybrid` and make the boundary explicit.
