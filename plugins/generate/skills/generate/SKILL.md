---
name: generate
description: >-
  Generate images, video, music, or speech through the Kie.ai MCP with a budget
  guard, local archiving, and a prompt log. Prices the batch and stops for
  confirmation before spending, downloads every result to a dated folder, and
  records the prompt that produced each file. Use for ad creative, brand imagery,
  illustrations, b-roll, image-to-video, upscales, or any batch of generated
  media. Invoke with /generate:generate.
---

# Generate

You generate media through the Kie.ai MCP. The models are not the hard part — the
MCP already exposes them as typed tools. Your job is the governance around them:
**price the work before spending, keep every result, and record how it was made.**

Left ungoverned, a request like "make some ad variants" turns into forty API calls
and a folder of URLs that expire. That is the failure this skill exists to prevent.

## Requires

The Kie.ai MCP (`mcp__kie-ai__*` tools). Confirm at least one generation tool is
available before planning any work. If the tools are absent, say so and stop —
do not fall back to describing images in SVG or suggesting another provider.

## Hard rules

These are not suggestions. Each one exists because skipping it costs the user money
or work.

1. **Price before you generate.** Never call a generation tool before stating
   `count × model × unit cost = estimate` and comparing it to the budget.
2. **Confirm before a batch.** More than 4 assets, or more than half the budget in
   one go, means stop and ask. Waiting costs a round-trip; not waiting costs money.
3. **Stop at the budget.** Track a running estimate. On reaching it, stop — even
   mid-batch — report what was spent and what remains undone, and ask.
4. **Save and log every result before reporting done.** Kie returns URLs, and they
   do not live forever. An asset that only exists as a URL in your transcript is
   an asset the user has already lost.
5. **Never silently retry.** A retry is another charge. State what the failed
   attempt already cost before asking to re-run it.

## Workflow

### 1. Scope

Establish, asking only for what you cannot infer:

- **What** — how many assets, of what kind, at what aspect ratio and resolution.
- **Where** — the output directory. Default `./Generations/<YYYY-MM-DD>/`, or the
  plugin's configured `output_dir` if set.
- **Budget** — the ceiling in dollars. Default **$2.00** per invocation unless the
  user names another, or `default_budget_usd` is configured.

If the user asks to "try a few models and compare", that is a deliberate fan-out —
price it as one batch, not as separate approvals.

### 2. Price

Look up unit costs in `references/Model_Costs.md`. Present the plan as a table
before any tool call:

```
4 × gpt_image_2 @ 2K     $0.05  = $0.20
2 × veo3_fast (8s)       $0.40  = $0.80
                    estimated total $1.00  (budget $2.00)
```

Unknown model? Use the conservative placeholder from the reference file and label
the estimate as a ceiling. Erring high means the user gets asked; erring low means
they get billed.

### 3. Prompt

Craft the prompts yourself — this is the part worth Claude's attention.

- Pull brand constraints into the prompt explicitly: exact hex values, flat vs.
  photographic, typography treatment, negative space for copy.
- Vary deliberately across a batch. Three near-identical images waste the budget;
  three distinct directions tell the user which way to go.
- Show the prompts before firing when the batch is large or the style is unsettled.
  Re-prompting is free; re-generating is not.

**Reference images must be URLs.** The `image_input` (nano banana), `input_urls`
(GPT Image 2), and `imageUrls` (Veo3) parameters take URLs only — this MCP server
has no upload tool and accepts neither local paths nor base64. Never pass a local
path and hope; host it first (next section).

### 3b. Host local references

To use a local file as a reference — a brand asset, a previous generation you want
to edit or animate — upload it to a temporary public host and pass the returned URL:

```bash
gen="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/generate/*/ 2>/dev/null | sort -V | tail -1)}"; gen="${gen%/}"
"$gen/scripts/host-reference.sh" path/to/brand-mark.png
# → https://litterbox.catbox.moe/abc123.png
```

Default TTL is **1h**, which outlives any single batch. Use `--ttl 12h|24h|72h` only
when the user will keep iterating on the same references over a longer session. The
script rejects a non-URL response rather than returning it, because passing an error
string as a reference URL spends a generation on a request that cannot succeed.

Chaining works the same way: to animate an image you just generated, host the saved
local file and pass that URL to `kling_video` or `veo3_generate_video`.

**Ask before the first upload of a session.** This puts the file on a public host
where anyone with the URL can fetch it until it expires. That is fine for the user's
own brand assets and generated output — it is not automatically fine for client-
confidential material, unreleased work, or anything containing a real person who has
not agreed to it. Say plainly what is being uploaded and where, get a yes, then
proceed; one confirmation covers the rest of the session's references unless the
sensitivity of the material changes.

### 4. Generate

Call the generation tool, then `mcp__kie-ai__wait_for_task` with the returned
`task_id` rather than polling `get_task_status` in a loop. Raise
`timeout_seconds` for video — the 180s default is short for a Veo3 job.

`wait_for_task` can time out on the client side while the job itself is fine — it
has been seen returning "Request timed out" at 300s on a task that completed in 113s.
Treat that error as "unknown", never as "failed": poll `get_task_status` once before
concluding anything, because re-firing a task that actually succeeded is a second
charge for one asset.

Generate sequentially unless the user asked for a comparison fan-out. Sequential
work lets rule 3 actually stop the spend partway. A model comparison **is** the
fan-out case — fire those together.

Read the per-model gotchas below before the first call to any of them. Each one
listed there fails every single time until the workaround is applied.

### 5. Save

Every returned URL goes through the archiver, which downloads the asset and appends
its provenance line to `Generations.jsonl` in the same folder:

```bash
gen="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/generate/*/ 2>/dev/null | sort -V | tail -1)}"; gen="${gen%/}"
"$gen/scripts/save-generation.sh" \
  --url "RESULT_URL" \
  --dir "OUTPUT_DIR" \
  --model "gpt_image_2" \
  --prompt "THE FULL PROMPT YOU SENT" \
  --cost 0.05 \
  --slug "ketone-green-apple-hero"
```

It prints the path it wrote. Pass the prompt verbatim — the script handles quoting
and newlines, so do not pre-escape it.

Verify what came back by reading the saved file, not by trusting the URL resolved.
A 200 response can still be a watermarked placeholder or the wrong aspect ratio.

### 6. Report

Close with:

- Where the files are, by path.
- Estimated spend against budget.
- What each model produced, so the user can judge which to keep using.
- Anything that failed, and what it cost.

## Model quick reference

The MCP tool descriptions carry the real detail. This is only for picking fast:

| Need | Tool |
|---|---|
| Best editing, text rendering in-image | `gpt_image_2` |
| Cheap, fast, many references (up to 14) | `nano_banana_image` |
| Photographic stills | `flux2_image`, `bytedance_seedream_image` |
| Cinematic video, native audio | `veo3_generate_video` |
| Image-to-video motion | `kling_video`, `wan_video` |
| Music | `suno_generate_music` |
| Voice | `elevenlabs_tts` |
| Upscale a keeper | `topaz_upscale_image` |
| Cut out a subject | `recraft_remove_background` |

## Model gotchas

Verified against a live six-model batch on 2026-08-12. These are defects in the
defaults or the server, not in your parameters — each fails 100% of the time until
worked around. All of them are rejected before dispatch, so they cost nothing except
the round-trip.

**`flux_kontext_image` — always pass `safetyTolerance` when editing.** The tool
defaults it to 6, but editing mode only accepts 0–2, so *every* call with
`inputImage` set fails until you pass `safetyTolerance: 2` explicitly. Text-to-image
is unaffected.

**`midjourney_generate` — reference modes are broken in this server build.** Kie's
API rejects omni-reference with "speed cannot be empty", and the server forwards
neither `speed` nor `processMode`, so there is no parameter combination that works.
Its own `parameter_guidance` claims speed is "not required for omni tasks", which is
wrong. Do not spend attempts on it — pick another model and say why. Re-test after
`@felores/kie-ai-mcp-server` updates.

**`z_image` takes no reference image.** Text-to-image only, so it cannot do a
likeness. Cheap and fast for backgrounds and textures, useless for anything that has
to resemble a source.

**Reference parameter names differ per model.** One hosted URL feeds them all, but
the key changes: `input_urls` (GPT Image 2, Flux 2), `image_input` (nano banana),
`inputImage` (Flux Kontext, singular string), `image_urls` (Seedream), `image_url`
(Qwen, singular string), `fileUrls` (Midjourney).

**Likeness quality is not the same as image quality.** In that batch the most
polished render had the weakest likeness, and one model read a Death Star on a
sweater as a Batman logo. Always read the saved file — a beautiful image of the
wrong person is still a failure.

## When Kie is unavailable

Kie is the cheapest aggregator and the least reliable one; outages happen. Report
the failure and stop. This skill deliberately has **no fal.ai or WaveSpeed
fallback** — a second provider means a second API key, a second price table, and a
silent path where the user gets billed somewhere they were not expecting. Add one
only if Kie's downtime actually becomes a recurring problem.

## Housekeeping

`Generations.jsonl` is append-only and grep-able. To find how something was made:

```bash
python3 -c "
import json
for line in open('Generations.jsonl'):
    r = json.loads(line)
    print(r['file'], '|', r['model'], '|', r['prompt'][:80])
"
```

Self-check the scripts after editing either one (both run offline):

```bash
gen="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/generate/*/ 2>/dev/null | sort -V | tail -1)}"; gen="${gen%/}"
"$gen/scripts/save-generation.sh" --self-check
"$gen/scripts/host-reference.sh" --self-check
```
