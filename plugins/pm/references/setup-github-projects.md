# GitHub Projects v2 Setup for /pm:setup

This is the GitHub Projects v2 setup detail for `/pm:setup` (Phase 6P), split
out of the main `SKILL.md` for progressive disclosure — only load this when
the backend is `github` and the user wants the optional Projects
visualization layer.

## Phase 6P: GitHub Project (optional, skip if backend != github)

**Skip this phase unless `backend == github`.** Trello and local backends have their own visualization stories.

This phase is OPTIONAL. The plugin's label-based workflow works perfectly without it. The Project is a downstream visualization layer that mirrors `status/*` labels to a Projects v2 Status field — useful when you want a board/table UI with custom fields, but not required for any skill to function.

### 6P.1 Ask the user

Print:

```
Would you like a GitHub Project (Projects v2) to visualize this backlog
alongside labels? Labels remain the source of truth — the project just
makes the work browsable in a board/table UI with custom fields and
timelines.

  1. Create new project (recommended for first-time setup)
  2. Link an existing project I already created
  3. Skip — I'll add this later

Choice [1/2/3]:
```

If **3 (skip)**: do not write a `project_sync` section to `.pm/config.yml`. Print "Skipped — re-run /pm:setup any time to add a project." and continue to Phase 7.

If **1 or 2**: continue to 6P.2.

### 6P.2 Check MCP availability

Try to load the github MCP tool via ToolSearch:

```
ToolSearch query: "select:mcp__github__projects_write"
```

If the tool does NOT load successfully, print:

```
GitHub Projects integration requires the github MCP server. To enable it:

  1. Install the plugin:
       /plugin install github@claude-plugins-official
  2. Add a Personal Access Token to your ~/.claude/settings.json env
     section (scopes: repo, project, read:org):
       "env": {
         "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..."
       }
  3. Reload Claude Code.
  4. Re-run /pm:setup to configure the project.

Setup will continue now WITHOUT project sync — your label-based workflow
is fully functional.
```

Do not write a `project_sync` section. Continue to Phase 7.

If the tool loads: continue.

### 6P.3 Path A — Create new project (choice 1)

1. Ask: `"Project title? [default: {gh_owner} — Backlog]"`
2. Ask: `"Make it private? [Y/n]"` — default yes.
3. Call `mcp__github__projects_write` with method `create_project`, passing `owner` (from `github.owner` in config), `title`, and the privacy flag. The response includes the project's `number` and `node_id` — store both.
4. Add custom fields. Call `mcp__github__projects_write` with the appropriate "add field" method for each:
   - `Target date` — type `DATE`
   - `Epic` — type `TEXT`
   (Status is already a default field on every Projects v2 project — do not create a second one.)
5. Link target repos. For each repo in `github.target_repos` (plus `github.owner/github.repo` if not already in that list), call `projects_write` with the "link repository" method.
6. Bulk-add open issues. For each linked repo:
   ```bash
   gh issue list --repo "{owner}/{repo}" --state open \
     --json url,number,labels --limit 1000
   ```
   For each issue returned, call `mcp__github__projects_write` with the "add item" method, passing the issue's URL or node ID. Capture each item's project item ID for the Status assignment in step 8.
7. Configure the Status field options. Call `mcp__github__projects_list` with method `list_project_fields` (or equivalent) to find the existing Status field ID. Then call `projects_write` to set the Status field options, in order, to:
   1. `Needs Triage`
   2. `Ready`
   3. `In Progress`
   4. `In Review`
   5. `Blocked`
   6. `Done`

   Capture each option's ID (you need these for step 8).
8. Set initial Status per item. For each added item, inspect the issue's labels (from the `gh issue list` output) to find its current `status/*` label. Map to the Status option from the table:
   | Label | Status option |
   |-------|---------------|
   | `status/needs-triage` | Needs Triage |
   | `status/ready` | Ready |
   | `status/in-progress` | In Progress |
   | `status/in-review` | In Review |
   | `status/done` | Done |
   | (none / `blocker`) | (leave unset, or Blocked if `blocker` label present) |

   Call `mcp__github__projects_write` with the "update item field value" method to set Status. Batch when the MCP supports it.

9. Persist to `.pm/config.yml` under `github.project_sync`:
   ```yaml
   github:
     owner: {existing}
     repo: {existing}
     project_sync:
       enabled: true
       project_number: {number from step 3}
       project_owner: {gh_owner}
       project_owner_type: org  # or "user" — match the owner type
       project_node_id: "{node_id from step 3}"
       status_field_sync: true
       status_field_id: "{Status field ID from step 7}"
       status_map:
         status/needs-triage: "Needs Triage"
         status/ready:        "Ready"
         status/in-progress:  "In Progress"
         status/in-review:    "In Review"
         status/blocked:      "Blocked"
         status/done:         "Done"
   ```
10. Print the manual playbook reminder:
    ```
    Project created — https://github.com/{type-prefix}/{owner}/projects/{number}

    A few things the MCP can't fully automate. See the
    "GitHub Project integration" section of the plugin README for the
    one-time UI steps:

      - Built-in workflows (auto-add issues, auto-archive done)
      - Custom views (Board by Status, Table by sprint, P0 filter, etc.)

    These take about 5 minutes in the project's web UI.
    ```

### 6P.4 Path B — Link existing project (choice 2)

1. Ask: `"Project number? (e.g. for https://github.com/orgs/Foo/projects/2 enter 2)"`
2. Ask: `"Is this an org-owned or user-owned project? [org/user]"` (default org).
3. Call `mcp__github__projects_get` passing `owner` and `number`. If the call fails (not found, no permission), print the error and ask if the user wants to retry or skip. On skip, write no `project_sync` section and continue.
4. Call `mcp__github__projects_list` with method `list_project_fields` to read the Status field's current options. Compare against the canonical set: `Needs Triage`, `Ready`, `In Progress`, `In Review`, `Blocked`, `Done`.

   If they don't match, ask:
   ```
   The Status field on this project has options [{list}] which don't match
   pm's conventions [Needs Triage, Ready, In Progress, In Review, Blocked, Done].

   Update them? [Y/n]

     Y — pm will set the Status options to match. SAFE on a new project,
         CAREFUL on an existing one: items already assigned to obsolete
         options will be reset.
     n — leave the existing options. PM will skip status mirroring
         (status_field_sync will be set to false).
   ```

   If Y: call `projects_write` to set the options. Capture field ID and option IDs.
   If n: still capture field ID; set `status_field_sync: false`.

5. Persist to `.pm/config.yml` under `github.project_sync` with the values gathered. Use `status_field_sync: false` when the user chose `n` above.

### 6P.5 Closing summary contribution

Record for Phase 8's summary:
- Project: created / linked / skipped
- Project URL (if applicable)
- Status field sync: enabled / disabled
- Items added (if Path A): N
