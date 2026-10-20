# Generate

Governed image, video, and audio generation over the [Kie.ai](https://kie.ai) MCP.

## Why

The Kie.ai MCP already exposes ~30 generative models as typed tools — that part is
solved. What it does not give you is the discipline around them:

- **No budget guard.** Ask for a hundred images and you get a hundred images.
- **No archive.** Results come back as URLs, which expire. Close the session and
  the work is gone.
- **No provenance.** Nothing records which prompt produced which file, so a good
  result is hard to reproduce and impossible to iterate on.

This plugin adds exactly those three things and nothing else. It is a policy layer,
not a wrapper — the MCP still does the generating.

## Installation

```bash
/plugin install generate@studio-moser
```

Requires the Kie.ai MCP configured with an API key:

```json
{
  "mcpServers": {
    "kie-ai": {
      "command": "npx",
      "args": ["-y", "@felores/kie-ai-mcp-server"],
      "env": { "KIE_AI_API_KEY": "your-key" }
    }
  }
}
```

## Skill

### `/generate:generate`

```
# Simple
/generate:generate three hero images for a green apple energy shot, flat editorial, #1F7A3D

# With a budget and a model comparison
/generate:generate 3 ad variants each from gpt_image_2 and nano_banana_image,
budget $3, output design/_generated

# Image to video — the local file is auto-hosted so Kie can fetch it
/generate:generate animate design/_generated/003-hero.png with kling, slow push in

# Explore on a Flora canvas — prompts and rounds stay on the board
/generate:generate six illustration directions for the landing page hero,
on a Flora canvas, budget $4
```

Every run: prices the batch and waits for confirmation before spending, generates
sequentially so the budget can actually halt it, downloads each result locally, and
appends the prompt to `Generations.jsonl` beside the files.

## Flora canvas

For exploration — rounds of illustrations or visual directions you pick from and
iterate on — the skill can run the job on a [Flora](https://flora.ai) canvas instead.
Each round is a labelled group, each generation a node carrying its own prompt, and
each variant is connected to the node it came from. You can rewrite a prompt on the
board before it runs; the skill reads the board back and runs what is there.

Needs the Flora MCP, which bills your Flora workspace separately from Kie:

```bash
claude mcp add --scope user --transport http flora https://agents.flora.ai/mcp
```

The budget check, the confirmation step, and the local archive all still apply.
The workflow lives in `skills/generate/references/Flora_Canvas.md`.

## Output

```
Generations/2026-08-12/
├── 001-hero-green-apple.png
├── 002-hero-green-apple.png
├── 003-can-closeup.png
└── Generations.jsonl
```

Each JSONL line: `file`, `model`, `prompt`, `source_url`, `est_cost_usd`, `at`.

## Known constraints

- **Local references get uploaded to a public temp host.** The Kie MCP's
  `image_input` / `input_urls` / `imageUrls` parameters accept URLs only — no local
  paths, no base64, and the server ships no upload tool. `scripts/host-reference.sh`
  bridges the gap via [litterbox](https://litterbox.catbox.moe) with a 1h expiry.
  The skill asks before the first upload of a session: the file is publicly fetchable
  by URL until it expires, which suits brand assets and generated output but not
  client-confidential material.
- **Costs are estimates.** `skills/generate/references/Model_Costs.md` is a local
  table you edit, seeded with conservative placeholders plus observed
  `creditsConsumed` figures. The credits-to-dollars rate is unknown, so the guard is
  the confirmation step, not the arithmetic.
- **Some models are broken or limited.** `flux_kontext_image` fails every edit unless
  `safetyTolerance` is passed explicitly, `midjourney_generate` reference modes do
  not work in the current server build, and `z_image` accepts no reference image at
  all. See `skills/generate/references/Model_Gotchas.md`.
- **No automatic fallback.** When Kie is down the skill stops; it does not move the
  job to fal.ai, WaveSpeed, or Flora. Flora is used only when you choose the canvas,
  so no account gets billed that you were not expecting.
- **Flora tool names can drift.** The names in `Flora_Canvas.md` were checked against
  the live tool schemas on 2026-10-11. The skill is told to trust the tools' own
  schemas over that file.

## Development

Self-check the scripts after editing either one (both run offline):

```bash
scripts/save-generation.sh --self-check
scripts/host-reference.sh --self-check
```

## License

MIT
