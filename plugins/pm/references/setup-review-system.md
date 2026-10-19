# Review system setup

Loaded by `skills/setup/SKILL.md` Phase 7.5 for every issue-tracker backend. The issue tracker does not determine the code host: create the local review contract for every
configured repository, then offer GitHub infrastructure only for repositories with an
accessible GitHub remote.

## 1. Install the project review contract

For every repository in `pulse-config.yaml` (or the detected repository when there is
no list), resolve relative repository paths from the config file's directory, confirm
the resulting directory is the intended Git root, resolve the installed PM root, and
run its idempotent writer:

```bash
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
"$pm/scripts/stamp-review-contract.sh" "$repo_root"
```

The writer owns only `<!-- pm:review-baseline:* -->`. It adopts an existing
`REVIEW.md` without overwriting project text and refuses symlinks or incomplete
markers. Never reconstruct the managed baseline in this skill.

Tell the user which contracts were created, adopted, or refreshed. Ask them to fill
the project-owned failure modes, sensitive paths, required checks, and exclusions as
those facts become known.

## 2. Detect the code host

For each repository, inspect `git remote get-url origin`. Continue with this reference
only when the remote resolves to an accessible GitHub `{owner}/{repo}` and `gh auth
status` succeeds. Otherwise retain `REVIEW.md`, report GitHub enforcement as skipped,
and do not treat the selected PM issue backend as proof of code hosting.

Read existing `.github` files, repository rulesets, and branch protection before
proposing changes. Existing files and remote rules are user-owned state.

## 3. Interview for verification and ownership

Gather these decisions in one batch per repository:

1. **Verification environment and commands.** Inspect existing documented scripts and
   workflows and propose only a supported GitHub runner, preparation steps, and stable
   commands already used by the repository. For each command, name the expected
   positive signal. Let the user edit or decline the list. Never invent a command, add
   optional tooling, interpolate secrets, introduce an unapproved third-party action,
   or accept an always-successful placeholder.
2. **Pull-request enforcement.** Offer `workflow + active ruleset` (recommended when
   verified commands exist), `documentation only`, or `skip`.
3. **Human approvals.** Ask for the repository-wide minimum, default `0`; PM's risk
   gate may still require a human for an individual change. Explain that a static
   GitHub rule cannot express PM's full dynamic risk policy.
4. **Owners.** Ask for real CODEOWNERS mappings or skip the file. Never insert a placeholder owner. Ask separately whether matching paths require code-owner review.

If no command has a positive acceptance signal, disable the workflow/ruleset option
and report the missing testing seam. Do not install a green shell placeholder merely
to satisfy setup.

## 4. Prepare local GitHub files

Use the installed PM templates. Preserve existing files; offer a diff and merge rather
than replacing them.

### Pull request template

Create or merge `.github/pull_request_template.md` from
`templates/pull-request-template.md`. The result must contain What, Why, Testing,
Risk / Blast Radius, and How to revert.

### Verification workflow

Only when the user approved a runner and at least one verified command, create or merge
`.github/workflows/pm-verification.yml` from
`templates/github-verification-workflow.yml`.

Replace `PM_SETUP_RUNNER` with the approved runner. Replace
`# PM_SETUP_VERIFICATION_STEPS` with the approved preparation steps and one step per
approved command. Use a literal YAML `run` block, a descriptive step name, and the
exact approved command. Reuse only preparation actions the repository already trusts.
Preserve `pull_request` and `merge_group` triggers, least-privilege `contents: read`,
and the job name `PM verification`; that job name is the required status-check
context. Show the completed workflow and confirm that neither placeholder remains.

### CODEOWNERS

Create or merge `.github/CODEOWNERS` only from mappings the user supplied. Validate
that each owner starts with `@` and each path is repository-relative. Do not enable
required code-owner review when the file is empty, contains placeholders, or names an
owner that cannot fulfill the obligation.

## 5. Preview and apply GitHub enforcement

Remote enforcement is consequential. After the local file previews, show one combined preview containing:

- Repository and protected branch.
- Existing rule or protection that would change.
- Required check `PM verification` and strict status-check behavior.
- Required pull requests and conversation resolution.
- Chosen minimum human approvals and stale-approval dismissal state.
- Code-owner review state.
- Recovery: delete a newly created PM ruleset, or restore the captured prior ruleset.

Ask once for explicit approval of that exact preview. Declining remote enforcement
must not undo the local documentation.

After approval, use GitHub's repository rulesets API through `gh api` with the current
API version. Target only the configured base branch. Create or update one ruleset named
`PM merge requirements`; never edit an unrelated ruleset. Its branch rules are:

- `pull_request` with the selected approval count, conversation resolution, optional
  code-owner review, and stale-review dismissal when approvals are required.
- `required_status_checks` containing context `PM verification`, strict mode enabled,
  and no source integration restriction unless the user selected one already installed.

Before mutation, capture `gh api repos/{owner}/{repo}/rulesets` and the full matching
ruleset when present. After mutation, read the rule back and verify every approved
field. If rulesets are unavailable for the repository or plan, report enforcement as
unmet and offer a branch-protection fallback with the same approved requirements;
never silently weaken or approximate the rule.

Do not activate a required check unless the corresponding workflow was generated and
contains every approved command. Do not claim the check is operational until a pull
request run reports the `PM verification` job; setup can prove configuration, not a
future workflow run.

## 6. Summary evidence

Return these lines to the main setup summary for every repository:

```text
Review contract: {created | adopted | refreshed} at REVIEW.md
PR template: {created | merged | unchanged | skipped}
Verification workflow: {created with commands | merged | skipped — reason}
CODEOWNERS: {created | merged | skipped — reason}
Merge enforcement: {verified ruleset URL/id | declined | unmet — reason}
```
