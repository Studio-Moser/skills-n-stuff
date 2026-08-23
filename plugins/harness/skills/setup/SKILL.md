---
name: setup
description: >-
  Use when Harness has been installed but this developer still needs a personal
  agents-repo relationship, portable links, runtime capability discovery, a model
  rubric, or optional Shelby enrichment configured.
---

# Harness Setup

Configure the personal Harness by composing its existing setup skills. Do not
copy their shell procedures into this skill.

Read [references/harness-contract.md](../../references/harness-contract.md) for
the result shape and [references/shelby-integration.md](../../references/shelby-integration.md)
only if Shelby tool names are available.

## Ordered setup

1. Invoke `harness:sync` in full mode. It owns discovering or cloning the
   personal agents repository, reconciling portable links, and running its
   portability checks. If the repository is absent, let Sync request the private
   repository URL and preserve every confirmation or conflict boundary it owns.
2. Finish the Sync link and portability reconciliation before capability
   discovery. An unresolved destructive choice, authentication failure, or
   divergence is a blocker; Setup does not decide it for the user.
3. Now discover runtime capabilities with `command -v`; do not install a runtime or
   infer one from a config file. Check only executors and tools relevant to the
   current rubric, plus the known supported agent runtimes:

   ```bash
   for capability in claude codex gemini pi hermes; do
     if command -v "$capability" >/dev/null 2>&1; then
       printf '%s\tpresent\n' "$capability"
     else
       printf '%s\tabsent\n' "$capability"
     fi
   done
   ```

4. Invoke `harness:model-rubric`, passing the observed capability inventory as
   current setup context. That skill owns the rubric path, interview, creation,
   refresh, validation, and audit mechanics. Do not write or parse a second
   rubric here. It must reconcile the rubric's `capabilities` with the observed
   inventory and rederive affected routes instead of retaining a stale executor.
5. Invoke `harness:sync` again if the rubric changed inside the agents repository,
   so the existing commit, pull, push, and conflict mechanics publish that
   version-controlled change.
6. Inspect the runtime's callable tool names for Shelby only after the portable
   setup is usable. When Shelby tool names are present, continue setup and return
   only identifiers from successful Shelby calls. Resolve canonical project
   scope, log this multi-phase setup run, and save only useful recovery
   checkpoints before returning those identifiers. When Shelby tool names are
   absent, continue setup and leave all optional `shelby` identifiers empty.
   Shelby failure never changes route or authority and blocks only enrichment,
   not correct setup.
7. Print the storage boundary:

   - **version-controlled:** portable instructions, skill declarations,
     manifests, shared settings, and the rubric when the agents repository owns
     its config directory;
   - **local-only:** credentials, secret-bearing profiles, resolved command
     paths, capability availability, symlinks, approvals, temporary evidence,
     and Shelby state.

## Completion

Re-run the checks owned by Sync and Model Rubric that establish the setup state.
Return the exact `HarnessResult` from
[references/harness-contract.md](../../references/harness-contract.md). Use the
current runtime as the executor, record the agents-repository commit or config
snapshot in `evidence.fixed_target`, and include decisive setup checks. Only the
parent or accepting workflow may return `status: accepted`, after those checks
prove the setup outcome. A subordinate skill's success report is a claim.

Populate every field: `status`, `route.requested`, `route.actual_model`,
`route.effort`, `route.provider`, `route.executor`, `artifacts.files`,
`artifacts.report`, `evidence.fixed_target`, `evidence.checks`,
`evidence.outcome`, `telemetry.attempts`, `telemetry.elapsed`,
`telemetry.verification_failures`, `telemetry.token_or_quota_usage`,
`shelby.project_id`, `shelby.run_id`, `shelby.checkpoint_ids`, and `blockers`.
For Setup, use `route.requested: default` and record the current session's model,
effort, provider, and runtime executor. Leave unavailable optional values empty
rather than omitting fields.
