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

## Configured-status mode

When a consumer invokes this skill with `mode: status`, run a read-only configuration
check and return immediately; do not enter Ordered setup and do not mutate files,
links, repositories, or remote state.

1. Invoke `harness:sync` with `--dry-run`. Require its report to establish the personal
   agents repository, portable links, declared skills, MCP commands, and portability
   checks without a pending repair.
2. Discover the current runtime capabilities with the same read-only `command -v`
   inventory used by Ordered setup. Require `python3`, `yq`, and the resolver at
   `$harness/scripts/resolve-route.py`; missing `python3`, `yq`, or the resolver
   is a blocker, not permission to infer configured status.
3. Resolve the rubric through `scripts/rubric-path.sh --check`. When it is set,
   first require the Harness 0.7 completion markers: `routing.orchestrator`,
   `routing.default`, `routing.quick`, and `routing.review` are present and every
   completed model row's `efficiency` is an integer from 1 through 10. Then run
   the canonical validator against the current native provider and callable
   executors:

   ```bash
   harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
   "$harness/scripts/resolve-route.py" validate \
     --rubric "$RUBRIC_PATH" \
     --native-provider "$HARNESS_NATIVE_PROVIDER" \
     --executors "$HARNESS_EXECUTORS"
   ```

   Require exit 0 and `{"status":"valid"}`. The command never receives a
   health-state path and must not create or update provider-health state. It
   proves exact model rows, unique providers within chains, taste thresholds,
   and current provider/executor reachability without rewriting the rubric. A
   rubric that satisfies only the pre-0.7 execute/review checks is not configured.
4. Return the complete HarnessResult defined by the Harness contract. Use
   `status: accepted` with `evidence.outcome: proven` only when the Sync dry run and
   current rubric/capability validation all pass. Otherwise use `status: blocked` with
   `evidence.outcome: unproven` and name each missing or stale configuration element in
   `blockers`. Record the validated agents-repository commit or configuration snapshot
   as `evidence.fixed_target` and the decisive read-only checks in `evidence.checks`.

Installed skills alone never prove configured status. Optional Shelby absence remains
non-blocking, as in Ordered setup.

## Ordered setup

1. Invoke `harness:sync` in full mode. It owns discovering, cloning, or safely
   creating the personal agents repository from loose configuration, reconciling
   portable links, and running its portability checks. If the repository is
   absent, let Sync distinguish an existing private remote from loose local
   configuration and preserve every backup, confirmation, privacy, and conflict
   boundary it owns.
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

4. Invoke `harness:model-rubric`, passing the same native-provider and
   callable-executor inventory used by configured-status validation, together
   with the observed capabilities, as current setup context. That skill owns the
   rubric path, interview, creation, refresh, validation, and audit mechanics.
   Do not write or parse a second rubric here. It must reconcile the rubric's
   `capabilities` with the observed inventory, rederive affected routes instead
   of retaining a stale executor, and report a validated write only after its
   temporary draft passes `resolve-route.py validate` with that inventory.
5. Invoke `harness:sync` again if the rubric changed inside the agents repository,
   but only after Model Rubric reports a validated write, so the existing commit,
   pull, push, and conflict mechanics publish that version-controlled change. A
   blocked validation never authorizes Sync.
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
Record bounded JSON summaries from the actual calls rather than inventing
results:

- Sync: initial/final status and decisive checks, plus changed files;
- Model Rubric: status, whether the file was current, whether capabilities were
  reconciled, whether it changed, decisive checks, and changed files;
- callable runtime tool names as a JSON string array;
- Shelby: status, checks, and only identifiers returned by successful calls.

Then run the deterministic result seam. It validates that even a current rubric
was reconciled, requires final Sync when the rubric changed, and handles Shelby
present, absent, or failed without fabricating identifiers:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/setup-result.py" \
  --sync-result "$SYNC_RESULT" \
  --rubric-result "$RUBRIC_RESULT" \
  --tool-names "$TOOL_NAMES" \
  ${SHELBY_RESULT:+--shelby-result "$SHELBY_RESULT"} \
  --model "$HARNESS_MODEL" \
  --effort "$HARNESS_EFFORT" \
  --provider "$HARNESS_PROVIDER" \
  --executor "$HARNESS_EXECUTOR" \
  --fixed-target "$HARNESS_FIXED_TARGET" \
  --proof "$HARNESS_PROOF"
```

Return the exact `HarnessResult` from
[references/harness-contract.md](../../references/harness-contract.md). Use the
current runtime as the executor, record the agents-repository commit or config
snapshot in `evidence.fixed_target`, and include decisive setup checks. Only the
parent or accepting workflow may return `status: accepted`, after reproducing
those checks; it alone may pass `--proof proven`. A subordinate skill's success
report is a claim.

Populate every field: `status`, `route.requested`, `route.actual_model`,
`route.effort`, `route.provider`, `route.executor`, `artifacts.files`,
`artifacts.report`, `evidence.fixed_target`, `evidence.checks`,
`evidence.outcome`, `telemetry.attempts`, `telemetry.elapsed`,
`telemetry.verification_failures`, `telemetry.token_or_quota_usage`,
`shelby.project_id`, `shelby.run_id`, `shelby.checkpoint_ids`, and `blockers`.
For Setup, use `route.requested: default` and record the current session's model,
effort, provider, and runtime executor. Leave unavailable optional values empty
rather than omitting fields.
