# Reconcile — Local Backend Detail

Backend-specific procedure blocks for `/pm:reconcile`, split out of `reconcile/SKILL.md` so GitHub/Trello users don't have to read past them. Only relevant when `backend == local`; skip this whole file otherwise. Variables (`$items_dir`, `$stale_threshold`, `$default_branch`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

Epic rollup, orphan-epic sweep, and epic normalization (Phase 1.3 / 1.3b / 1.3c) are GitHub-only entirely — sub-issues are a GitHub feature. Local only has the minimal Phase 1.3 rollup check below; there is no local equivalent of 1.3b/1.3c.

## Phase 0.2: Load Backend Config — Local

```bash
items_dir="$primary_repo_root/$(yq '.local.items_dir // ".pm/items"' "$pm_config")"
```

## Phase 1.2: Completion Tracking — Local

```bash
for num in "${unique_refs[@]}"; do
  item_file=$(ls "$items_dir"/${num}-*.yml 2>/dev/null | head -1)
  [ -z "$item_file" ] && continue

  state=$(yq '.closed_at // "null"' "$item_file")
  [ "$state" != "null" ] && continue

  title=$(yq '.title' "$item_file")
  echo "Issue #${num} (${title}) — referenced on ${default_branch}, appears complete."
done
```

On user confirmation for local backend:

```bash
yq -i '.labels -= ["status/ready","status/in-progress","status/in-review","owner/ai","owner/human","owner/operator"] | .labels += ["status/done"] | .closed_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$item_file"
```

## Phase 1.3: Epic Rollup — Local

Scan items where `parent_epic` matches the epic number. If all are closed, flag the epic.

## Phase 2.1: Stale Detection — Local

```bash
cutoff=$(date -u -v-${stale_threshold}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "${stale_threshold} days ago" +%Y-%m-%dT%H:%M:%SZ)

for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  closed=$(yq '.closed_at // "null"' "$item_file")
  [ "$closed" != "null" ] && continue

  updated=$(yq '.updated_at // .created_at' "$item_file")
  # Compare $updated against $cutoff
done
```

## Phase 2.2: Stale Item Actions — Local

**retriage (local):**
```bash
yq -i '.labels -= ["status/ready","status/in-progress","status/in-review","owner/ai","owner/human","owner/operator"] | .labels += ["status/needs-triage"]' "$item_file"
```

**close (local):**
```bash
yq -i '.labels += ["stale-closed"] | .closed_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$item_file"
```

**demote (local):**
```bash
yq -i '.priority = "P'"${next}"'"' "$item_file"
```

## Phase 3.1: Pull Spawned Items — Local

```bash
spawned=()
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  labels="$(yq '.labels[]' "$item_file" 2>/dev/null)"
  echo "$labels" | grep -q "spawned-during-sprint" && spawned+=("$item_file")
done
```

## Phase 3.2: Classify Spawned Items — Local

**Blocking items (local):**
```bash
yq -i '.labels += ["blocker"] | .parent_epic = '"$parent_num"'' "$item_file"
```

**Independent items (local):**
```bash
yq -i '.labels -= ["spawned-during-sprint"] | .labels += ["status/needs-triage"]' "$item_file"
```
