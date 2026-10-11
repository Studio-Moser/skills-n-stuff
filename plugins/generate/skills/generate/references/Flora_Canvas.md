# Flora Canvas

How `/generate:generate` runs a job on a [Flora](https://flora.ai) canvas instead of
through Kie. Read this only when the plan says canvas mode.

The point of the canvas is the record. Every prompt sits on the node that ran it,
where the user can read and edit it; every round stays on the board next to the one
it came from. A canvas that only holds the winners has thrown that away.

## Requires

The Flora MCP (`mcp__flora__flora_*` tools), installed once per machine at user
scope — the default local scope only loads in the directory it was added from:

```bash
claude mcp add --scope user --transport http flora https://agents.flora.ai/mcp
```

Auth is OAuth in a browser on the first tool call. If the tools are absent, give the
user that command and stop — do not quietly run the job through Kie instead, because
the user asked for a canvas and would get a folder.

**The tool schemas are the authority.** The tool and field names below were checked
against the live tool schemas on 2026-10-11, and the layout, run, poll, and save
steps and local reference upload were run end to end that day. `quote: true` and
techniques were not. Where a tool's own schema disagrees with this file, follow the
schema and fix this file.

## The hard rules still apply

Flora bills the workspace in USD the moment a run starts. `flora_run_canvas_nodes`
has no confirmation step and no dry run, so the guard is still this skill.

- **Price** from `estimated_cost_usd` on `flora_list_models`, or from `run_cost` on
  `flora_list_techniques` for a technique. For a firmer figure, call
  `flora_create_generations` with `quote: true` — it returns an estimate and starts
  nothing. Quote dollars to the user, never credits.
- **One budget.** A job that uses both Flora and Kie shares a single ceiling.
- **Log actuals.** `flora_run_canvas_nodes` returns `charged_cost` for each node as
  it starts, but the completed run is the figure to trust: a node with two
  references started at `$0` under a different `model_id` than the one configured,
  then completed at `$0.073` against a `$0.064` estimate. Pass the completed
  `charged_cost` to `--cost`, and correct the running total with it before the next
  sub-batch.
- **Save locally anyway.** Flora output URLs are long-lived, not permanent. Every
  result still goes through `save-generation.sh`, with `--model "flora:<model id>"`.

## Canvas layout

One Flora project per body of work. Reuse the project the user names; otherwise
find it with `flora_list_projects` before creating one with `flora_create_project`,
so a second session does not start a second board for the same work.

| On the canvas | Node | Holds |
|---|---|---|
| Brief | `notes`, top of the board | Goal, constraints (hex values, aspect ratio, what to avoid), budget, date |
| Round | `group`, labelled `R2 — glass panel` | Every generation in that round |
| Generation | `image` / `video` / `audio` | `prompt`, `model`, `params`; label `R2-C` |
| Reference | `static_image`, in a References group | A brand mark or source image the round builds on |
| Round verdict | `notes`, below the round | What the user kept, what they rejected, and why |

Notes cannot go inside a group, and one added without a `position` lands far to the
right of the rounds. Always pass `position` on a note: the brief above the first
round, a verdict below its round — the next round sits to the right, so a note
there collides with it. Read the round's `position` and `size` from
`flora_get_canvas`. A group's position is its top-left corner; a note's is its
top-centre, so a note flush with the round's left edge has `x` = round `x` + half
the note's width. Leave a 64px gap: `y` = round `y` + round height + 64 for a
verdict, round `y` − note height − 64 for the brief.

Label every generation with a short code (`R1-A`, `R1-B`, … `R2-A`). The user will
say "more like R1-C", and the code is how that maps back to a node.

## Workflow

### 1. Lay out the round before spending

Add the round's nodes in one `flora_add_to_canvas` call: the `group`, then one
generation node per variant with its `prompt`, `model`, `params`, `label`, and
`group`. Give the group a `ref` so the variants can name it in the same call.
Nothing runs yet. The call tiles a group's members and fits the frame around them,
so `flora_arrange_canvas` is only needed when the result reads badly; it takes
nodes that are all top-level or all in one group, not a mix.

Take node ids from `created` in the response, keyed by `ref` — its order is not the
order you sent.

A bad node rejects the whole call, not just itself: `group` on a `notes` node, a
`params` value the model does not accept, or a `video` node in a workspace without
the video entitlement. Take `model` ids and `params` from `flora_list_models`.
That list is truncated and not sorted by cost, so search it with `query` rather
than assuming the first page holds the model you want.

Then give the user the `canvas_url` alongside the price table. When hard rule 2
calls for confirmation, this is that review step moved onto the board: the user can
rewrite a prompt in Flora instead of dictating the change back in chat.

### 2. Read the canvas back, then run

Before running, call `flora_get_canvas` and run what is on the board, not
what you wrote. The canvas is the source of truth for prompts — an edit the user
made in Flora must not be overwritten by your earlier draft. If a model or count
changed, re-price before running.

Run with `flora_run_canvas_nodes` (up to 50 nodes a call), in sub-batches small
enough that reaching the budget can stop the rest. A node reported `skipped` did
not charge; say why it was skipped rather than re-running it blind.

Poll `flora_list_generations` with the returned `run_ids` until each is completed
or failed, waiting at least 15 seconds between polls of the same runs — faster
polling returns a cooldown error, not a result.

### 3. Iterate by adding, never by overwriting

A node that has run is a record. To vary it, add a new node in a new round group
and connect it from its parent (`connect`, `from` the parent, `to` the variant), so
the lineage is drawn on the board. Editing the prompt of a finished node erases the
prompt that produced the image sitting in it.

Use a parent's output as a reference by connecting it, or by passing it in
`reference_node_ids` — both take nodes from the same project only. A node fed by a
parent needs an image-to-image model (`i2i-…`), not the text-to-image one (`t2i-…`)
its parent used, and the two are priced differently: price the variant from its own
`model_id`. `flora_get_canvas` shows the same display name for both, so read
`model_id`, not `model`.

Rejected directions stay. `flora_remove_from_canvas` is immediate and cannot be
undone through the API; call it only when the user asks for specific nodes gone.

### 4. Record the verdict

When the user picks, write it down on the board: add a `notes` node below the round
with the kept codes, the rejected ones, and the reason in the user's words, and pass
`fit_text: true` so the whole note shows. Without it the canvas shows what was made
but not what was decided.

### 5. Save

Download each kept result — and, unless the user says otherwise, every result — with
`save-generation.sh`, passing the prompt as it ran (read from the node, since the
user may have edited it) and the `charged_cost`. A finished node carries its
`output_url` in `flora_get_canvas`, next to that prompt.

Flora has served JPEG bytes from a URL ending in `.png`, and the archiver names the
file from the URL. Read the saved file as usual; if the format matters downstream,
check it with `file` rather than trusting the extension.

## Local references

Bring a local file in with `flora_create_asset` (`source: "signed-url"`; send the
returned `form_fields` and then the file as a multipart `curl` POST) and
`flora_complete_asset`. Then place it in the round's `flora_add_to_canvas` call as a
`static_image` node with the asset's `url` as `content_url`, which lets it carry a
label, sit in a References group, and be connected to the variants in that same
call. `flora_attach_asset` also places it, but with no label, group, or ref.

A variant can take several references: connect each one to it, and name them in the
prompt by what they show ("the cartoon avatar", "the photograph"), not by order.

The upload goes to the user's own Flora workspace, so `host-reference.sh` and its
public temp host are not needed in canvas mode. It is still an upload to a third
party. Ask before the first one of a session, the same as section 3b of the skill.

## Sharing

A new project is not link-shared, though other members of the Flora workspace may
see it. `flora_share_project` makes a public link. Call it only when the
user asks for a link, with `access: "view"` unless they ask for `edit`, and say that
the link exposes the whole board, prompts included.

## Report

In addition to the usual close: the `canvas_url`, the round codes that were added,
and estimated against charged spend.
