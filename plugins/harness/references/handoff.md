# Handoff

A handoff is a bounded, typed packet between a workflow, parent, worker, or
reviewer. It carries enough state to act without transferring ownership of
routing, verification, or the consumer's domain policy.

## HandoffPacket

```yaml
outcome: bounded observable result
current_state: concise facts already established
relevant_files:
  - repository-relative path
constraints:
  - task or domain constraint
unresolved_blockers:
  - explicit unresolved item
verification_seam: highest stable observable check
current_proof:
  fixed_target: commit or immutable snapshot when applicable
  checks: decisive current results
  outcome: proven | unproven
authority:
  working_directory: repository root or worktree
  allowed_paths: explicit write/read scope when narrower than the repository
  tools: required capabilities
  approvals: actions that still require the user
expected_return_shape: HarnessResult
```

The packet states facts, constraints, and open questions; it does not paste the
parent conversation. The chosen context mode determines what accompanies the
packet as defined in [context.md](context.md). Durable project instructions
remain authoritative, while `authority` remains an execution ceiling.

Use repository-relative paths in `relevant_files` and an explicit absolute or
runtime-resolved working directory in `authority`. Summarize current proof and
point to artifacts where possible. Secrets and unbounded logs are forbidden;
include only the decisive output needed to reproduce or assess a claim.

The recipient returns the exact `HarnessResult` from
[harness-contract.md](harness-contract.md). Consumer-specific findings may be
artifacts or constraints, but they do not add universal result fields.
