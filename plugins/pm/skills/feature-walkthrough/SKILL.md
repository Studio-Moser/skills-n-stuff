---
name: feature-walkthrough
description: >-
  Use when a developer asks to see, demonstrate, record, or visually review a web
  feature through an existing browser-testing workflow.
allowed-tools: "Bash Read Write Edit AskUserQuestion"
---

# Feature Walkthrough

Produce visual proof only for a web feature with Playwright-backed coverage. This
supplements existing test, build, review, and verification proof; it never replaces
them. If Playwright, the feature test, authorized test data, or a safe recording path
is unavailable, stop and explain the missing prerequisite.

## 1. Establish the recording plan

1. Read repository instructions, Playwright configuration, the existing feature test,
   fixtures, authentication, and test cleanup behavior.
2. Confirm the run uses authorized QA accounts and synthetic data. Never expose
   passwords, tokens, payment credentials, customer data, production-only URLs, or
   unrelated browser content. Do not charge, order, message, or otherwise mutate an
   external production system without explicit authorization.
3. When the target is unspecified, ask exactly: **Desktop, mobile, or both?** Do not
   record until the user answers.
4. Run the existing feature test before recording. Stop on failure; it is the proof
   source for the demonstrated behavior.

Use the requested destination, or
`output/playwright/walkthroughs/<feature>/<device>.mp4`. Never silently overwrite an
artifact. Generated recordings stay untracked unless the user explicitly asks to
commit them.

## 2. Prepare presentation coverage

Reuse a project-owned walkthrough spec when present. Otherwise create run-specific,
presentation-only coverage from the existing feature test; do not alter normal E2E
defaults. Start from a recognizable state, show the action and result, retain enough
assertion to fail when the outcome is absent, and omit diagnostic assertions from the
video. Resolve the installed PM plugin root before using its overlay helper:

```bash
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
overlay="$pm/templates/playwright-walkthrough-overlay.ts"
[ -f "$overlay" ] || { echo "missing walkthrough overlay helper: $overlay" >&2; exit 1; }
```

Read "$overlay" before creating presentation coverage. Import it from that resolved
path or copy it into the run-specific presentation coverage; do not recreate an ad hoc
overlay. Use the helper for each spoken state: `STEP N`, one short present-tense
explanation, bottom center, and 180 ms fade-and-rise motion. Remove each overlay before
the next interaction.

For each requested device, record a deterministic flow with one worker, list reporter,
no automatically opened HTML report, about 350 ms action delay, and deliberate holds:

| Device | Browser viewport | Encoded video |
| --- | --- | --- |
| Desktop | 1920×1080 | 1920×1080 |
| Mobile | 360×800 | 360×800 |

A user-specified device or size overrides these defaults. For `both`, produce separate
desktop and mobile files. The encoded dimensions must exactly match the browser
viewport: no scaling or letterboxing.

## 3. Convert, verify, and clean up

When `ffmpeg` is available, convert the native Playwright video to H.264 MP4 with
`-pix_fmt yuv420p -movflags +faststart`. If it is unavailable, preserve the WebM and
report that limitation. Verify each final artifact with `ffprobe` (codec, dimensions,
and duration) and a full decode, for example:

```bash
ffprobe -v error -show_entries stream=codec_name,width,height -show_entries format=duration -of json "$artifact"
ffmpeg -v error -i "$artifact" -f null -
```

Report each artifact path, browser, viewport, encoded video dimensions, duration, test
result, and conversion limitation if applicable. Remove only run-specific temporary
configuration, specs, and intermediate files that this walkthrough created. Preserve
existing worktree changes and artifacts; finish by checking `git status` and report any
pre-existing changes separately.
