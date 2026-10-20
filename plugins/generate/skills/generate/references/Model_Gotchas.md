# Model Gotchas

Read the entry for a model before the first call to it. Verified against a live
six-model batch on 2026-08-12 with `@felores/kie-ai-mcp-server`; re-check an entry
when the server updates. These are defects in the defaults or the server, not in
your parameters, and each fails until worked around. All of them are rejected before
dispatch, so they cost nothing except the round-trip.

## Reference parameter names

One hosted URL feeds every model, but the parameter name changes:

| Model | Parameter | Shape |
|---|---|---|
| `gpt_image_2`, `flux2_image` | `input_urls` | array |
| `nano_banana_image` | `image_input` | array |
| `veo3_generate_video` | `imageUrls` | array (1 image, or 2 for start and end frame) |
| `bytedance_seedream_image` | `image_urls` | array |
| `flux_kontext_image` | `inputImage` | single string |
| `qwen_image` | `image_url` | single string |
| `midjourney_generate` | `fileUrls` | array |

## `flux_kontext_image`: pass `safetyTolerance` when editing

The tool defaults it to 6, but editing mode only accepts 0–2, so a call with
`inputImage` set fails until you pass `safetyTolerance: 2` explicitly. Text-to-image
is unaffected.

## `midjourney_generate`: reference modes do not work in this server build

Kie's API rejects omni-reference with "speed cannot be empty", and the server forwards
neither `speed` nor `processMode`, so no parameter combination works. Its own
`parameter_guidance` claims speed is "not required for omni tasks", which is wrong.
Pick another model and say why rather than spending attempts on it.

## `z_image`: no reference image

Text-to-image only, so it cannot do a likeness. Cheap and fast for backgrounds and
textures; unsuitable for anything that has to resemble a source.

## Likeness quality is not image quality

In that batch the most polished render had the weakest likeness, and one model read a
Death Star on a sweater as a Batman logo. Read the saved file: a beautiful image of
the wrong person is still a failure.
