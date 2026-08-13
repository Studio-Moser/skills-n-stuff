# Model Costs

Unit costs used by the budget guard in `/generate:generate`. **Edit this file** —
it is a local estimate table, not a live price feed.

## Observed credit consumption

Every `get_task_status` response carries `creditsConsumed`, which is the only
first-party cost signal available. Measured on a live batch, 2026-08-12, one image
each:

| Tool | Call | Credits |
|---|---|---|
| `nano_banana_image` | nano-banana-2, 2K, image-to-image | 12 |
| `gpt_image_2` | 2K, image-to-image | 10 |
| `bytedance_seedream_image` | 5-pro, 2K, edit | 7 |
| `qwen_image` | edit, square_hd | 7 |
| `flux2_image` | pro, 2K, image-to-image | 7 |
| `flux_kontext_image` | pro, edit | not reported — different response shape |

**The credits-to-dollars rate is unknown**, so these cannot be converted into the
table below. They are still useful as *relative* cost: Nano Banana 2 at 2K costs
roughly 1.7× a Seedream or Flux 2 call. If you learn the rate, price the whole table
from this column and delete the placeholders.

Failed calls consumed nothing — parameter rejections happen before dispatch.

## Provenance, honestly

Only the GPT Image 2 row below is a specific claimed figure, and it comes from a
third-party video comparison (Rob Nuggets, "This 1 Claude Skill fully replaces your
Higgsfield Subscription", Aug 2026), not from Kie's API. Everything else is a
deliberately **conservative placeholder** — set high so the guard errs toward asking
the user rather than quietly spending.

Verify against <https://kie.ai> pricing when a number starts to matter, and update
the row. A wrong-but-high estimate is a working guard; a wrong-but-low one is not.

## Images

| Tool | Unit | Est. cost (USD) | Source |
|---|---|---|---|
| `gpt_image_2` | 1K image | 0.03 | claimed, unverified |
| `gpt_image_2` | 2K image | 0.05 | claimed, unverified |
| `gpt_image_2` | 4K image | 0.08 | claimed, unverified |
| `nano_banana_image` | image | 0.05 | placeholder |
| `flux2_image` | image | 0.05 | placeholder |
| `bytedance_seedream_image` | image | 0.05 | placeholder |
| `qwen_image` | image | 0.05 | placeholder |
| `z_image` | image | 0.004 | stated in the tool's own description |
| `midjourney_generate` | image | 0.10 | placeholder — reference modes currently broken |
| `topaz_upscale_image` | image | 0.10 | placeholder |
| `recraft_remove_background` | image | 0.02 | placeholder |

## Video

| Tool | Unit | Est. cost (USD) | Source |
|---|---|---|---|
| `veo3_generate_video` (`veo3_fast`) | 8s clip | 0.40 | placeholder |
| `veo3_generate_video` (`veo3`) | 8s clip | 1.50 | placeholder |
| `kling_video`, `wan_video` | short clip | 0.50 | placeholder |
| `bytedance_seedance_video` | short clip | 0.50 | placeholder |
| `hailuo_video`, `grok_imagine` | short clip | 0.50 | placeholder |
| `runway_aleph_video` | short clip | 1.00 | placeholder |
| avatar / lip-sync (`omnihuman_video`, `kling_avatar`, `infinitalk_lip_sync`) | short clip | 1.00 | placeholder |

## Audio

| Tool | Unit | Est. cost (USD) | Source |
|---|---|---|---|
| `suno_generate_music` | track | 0.10 | placeholder |
| `elevenlabs_tts`, `elevenlabs_ttsfx` | clip | 0.05 | placeholder |

## Anything not listed

Assume **$0.15 per image** and **$1.00 per video clip**, and tell the user the
estimate is a ceiling for an unpriced model.
