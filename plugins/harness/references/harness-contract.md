# Harness Contract

Harness accepts one provider-neutral request and returns one evidence-bearing
result. Consumers describe the work and its semantic altitude; Harness owns
concrete routing and execution.

The top-level orchestrator owns the user conversation, scope, approvals,
delegation graph, and final acceptance decision. Each HarnessRequest describes
one delegated operation.

## HarnessRequest

Every request has these top-level fields:

```yaml
operation: execute | review | computer-use
route: bulk | quick | default | taste | batch | review | independent
outcome: bounded observable result
context:
  project: canonical project identifier when known
  mode: fresh | fork | hybrid
  state: concise current state
  files: relevant repository-relative paths
  memory:
    enabled: true | false
    recall: optional domain-owned lookup intents
    capture: optional durable facts to record only after acceptance
authority:
  working_directory: repository root or worktree
  allowed_paths: explicit write/read scope when narrower than the repository
  tools: required capabilities
  approvals: actions that still require the user
constraints:
  - explicit task constraints
delegation:
  max_children: positive integer
  max_depth: positive integer
  token_budget: positive bounded amount when the runtime supports it
verification:
  seam: highest stable observable check
  expected: expected result
  fixed_target: commit or immutable snapshot when reviewing
```

`outcome` says what must be observably true, not what activity to perform.
`authority` is a ceiling: an executor may not widen paths, tools, permissions,
or approvals. A review request fixes its target before dispatch.
`delegation` is optional because direct work has no child budget. When present,
the executor must enforce the child and depth caps and pass a supported token budget
to the delegated runtime. Unsupported budgets stay visible as a blocker rather than
silently becoming unlimited.

Workflow-specific data remains owned by the consumer. PM blockers and blast
radius, for example, and Product Pulse source requirements travel in `context`
or `constraints`; they do not extend this schema. Consumers do not select a
provider, resolve a model, interpret executor metadata, or redefine proof.

`context.memory` is optional. A consumer supplies only domain intent: whether
enrichment is enabled, what prior context would help, and what durable result is
worth recording after acceptance. It never names a provider tool or supplies a
provider project ID. Harness resolves canonical scope, performs any available
recall or capture, and leaves the request otherwise executable when enrichment
is unavailable.

## HarnessResult

Every result has these top-level fields:

```yaml
status: accepted | failed | blocked | abandoned
route:
  requested: semantic route
  model: resolved model
  effort: resolved effort
  provider: resolved provider
  executor: current agent, native child, or external CLI
  dispatch: direct | delegated
artifacts:
  files: changed or created paths
  report: optional report path
evidence:
  fixed_target: commit or immutable snapshot
  checks: commands or procedures with actual results
  outcome: proven | unproven
blockers: explicit unresolved items
```

The resolver may track attempted candidates and fallback reasons internally while
selecting an authorized route. Those loop details are not part of HarnessResult;
the result records only the requested route and terminal concrete dispatch.
Optional Shelby recall and capture remain provider-owned side effects and are not
HarnessResult fields.

Use the statuses consistently:

- `accepted`: the requested outcome was delivered and has current proof.
- `failed`: execution ended without the outcome after an actual attempt.
- `blocked`: an unmet capability, approval, dependency, or authority boundary
  prevents a safe attempt or continuation.
- `abandoned`: the requirement remains visible but will not be pursued, such as
  an impossible requirement the caller explicitly declines to revise.

An executor exit code and a worker-authored summary are claims, not acceptance.
The evidence gate and invalidation rules live in
[verification.md](verification.md).

## Payload boundary

Never put credentials, tokens, secret-bearing profiles, or other secrets in a
request or result. Record decisive, bounded check output; do not copy unbounded
logs into evidence. Artifacts identify outputs by path rather than embedding
their full contents.
