# Transcribe Plugin — Design

**Date:** 2026-04-14
**Status:** Design approved, ready for implementation plan
**Repo:** skills-n-stuff
**Marketplace:** studio-moser

## Summary

A new Claude Code plugin (`transcribe`) that fetches spoken-word transcripts from video URLs on YouTube, YouTube Shorts, Instagram posts, Instagram Reels, TikTok, and Threads. The plugin runs entirely locally on Apple Silicon (yt-dlp + mlx-whisper), with a headless-Playwright fallback for platforms yt-dlp doesn't support (notably Threads).

Three downstream skills — `research-scout`, Shelby research skills, and The Crooked Line research skills — get a minimal additive edit pointing them at the new skill.

## Motivation

Existing landscape:

- `claude-transcribe` (normalspoon) works well for YouTube/Instagram/TikTok but relies on yt-dlp, which does not support Threads (upstream issue closed as "not planned").
- `research-scout`'s SKILL.md says "Pull the transcript" without specifying how, leaving execution up to Claude each time.
- No plugin in `skills-n-stuff` handles transcription today.

We want one composable skill that all our research-oriented skills can call, with Threads coverage baked in.

## Architecture

### Plugin structure

```
skills-n-stuff/plugins/transcribe/
├── .claude-plugin/
│   └── plugin.json
├── README.md
├── skills/
│   └── transcribe/
│       ├── SKILL.md
│       └── references/
│           └── integration-guide.md
├── bin/
│   └── transcribe                      # Auto-added to PATH by Claude Code
└── scripts/
    ├── install.sh
    ├── extract-via-playwright.mjs
    └── verify-deps.sh
```

Conforms to the current Claude Code plugin spec (https://code.claude.com/docs/en/plugins-reference):

- `.claude-plugin/plugin.json` provides plugin metadata (auto-discovered if omitted, but we include it for marketplace registration).
- `skills/transcribe/SKILL.md` is the user-invocable skill. Since `user-invocable` defaults to `true`, it is reachable as `/transcribe:transcribe` without a separate `commands/` file.
- `bin/transcribe` is auto-added to PATH by Claude Code, so downstream skills can call `transcribe <url>` from the Bash tool with no path gymnastics.
- `scripts/` holds utility scripts (install, helpers) referenced via `${CLAUDE_PLUGIN_ROOT}`.

### Marketplace entry

Added to `skills-n-stuff/.claude-plugin/marketplace.json`:

```json
{
  "name": "transcribe",
  "source": "./plugins/transcribe",
  "description": "Transcribe spoken-word audio from YouTube, Shorts, Instagram, TikTok, and Threads. Local on Apple Silicon via yt-dlp + mlx-whisper, with a headless-Playwright fallback for Threads.",
  "version": "0.1.0",
  "author": { "name": "Studio Moser" },
  "license": "MIT",
  "keywords": ["transcript", "whisper", "video", "youtube", "instagram", "threads", "research"],
  "category": "productivity",
  "tags": ["research", "transcript", "video"]
}
```

### SKILL.md frontmatter

```yaml
---
name: transcribe
description: >-
  Fetch a spoken-word transcript from a video URL. Supports YouTube, YouTube
  Shorts, Instagram posts/Reels, TikTok, and Threads. Use whenever you need
  the words said in a video — for research, summarization, or analysis.
  Invoke with /transcribe:transcribe <url> or from Bash as `transcribe <url>`.
argument-hint: <video-url> [--json]
allowed-tools: Bash
---
```

`allowed-tools: Bash` lets downstream skills call `transcribe <url>` without a permission prompt when the user has enabled the skill.

## Data flow

```
URL
  │
  ▼
detect_platform (threads → skip tier 1)
  │
  ├─► Tier 1: yt-dlp -x --audio-format wav
  │     │
  │     ├─ success → 16kHz mono WAV
  │     └─ "Unsupported URL" → fall through
  │
  └─► Tier 2: Playwright Chromium (scripts/extract-via-playwright.mjs)
        │
        ├─ navigate to URL
        ├─ wait for <video> element to render
        ├─ capture .mp4 URL from network traffic
        ├─ replay the request with session headers → local file
        └─ ffmpeg → 16kHz mono WAV
  │
  ▼
mlx-whisper (default: mlx-community/whisper-large-v3-mlx, overridable via WHISPER_MODEL)
  │
  ▼
format_markdown (or --json)
  │
  ▼
stdout
```

**Playwright profile:** persists at `~/.cache/transcribe-plugin/playwright-profile/` so a one-time manual sign-in can unlock login-gated content. Default behavior targets public posts only.

### Output format

Default (Markdown):

```markdown
# {title}

**Source:** {url}
**Platform:** {YouTube|Instagram|TikTok|Threads}
**Duration:** {mm:ss}
**Model:** mlx-community/whisper-large-v3-mlx

{transcript}
```

With `--json`:

```json
{
  "title": "…",
  "url": "…",
  "platform": "Threads",
  "duration_seconds": 83,
  "model": "mlx-community/whisper-large-v3-mlx",
  "text": "…",
  "segments": [{ "start": 0.0, "end": 3.2, "text": "…" }]
}
```

## Dependencies

Installed by `scripts/install.sh`:

- `yt-dlp` (Homebrew or `pip3 install yt-dlp`)
- `ffmpeg` (Homebrew)
- `mlx-whisper` (`pip3 install --break-system-packages mlx-whisper`)
- `node` ≥ 20 (Homebrew; required by Playwright)
- `playwright` + Chromium (`npm install playwright && npx playwright install chromium`)

Install footprint: ~500 MB (Chromium ~300 MB, whisper-large-v3 ~3 GB model downloaded on first use).

**Platform:** Apple Silicon only for mlx-whisper. On Intel Macs or Linux, `install.sh` should error with a clear message and a pointer to `faster-whisper` as a future alternative. Out of scope for v0.1.

## Error handling

| Condition | Behavior |
|---|---|
| Missing dependency | `verify-deps.sh` runs first; if a dep is missing, prompt to run `install.sh`, exit 1. |
| URL unsupported by both tiers | Exit 1 with: "Platform not supported. Tried yt-dlp and Playwright. URL: …" |
| Video has no audio track | Exit 1 with: "No audio track found." Avoid Whisper hallucination on silent videos. |
| Whisper hallucination on silent/music content | Detect via repeated-segment check; warn in stderr but still return transcript. |
| Playwright can't find a `<video>` element | Retry once after 5s, then fail with clear message and the page HTML size for debugging. |
| Login-gated post | Return "Access denied — try signing into the Playwright profile once: npx playwright open --load-profile …" |
| mlx-whisper model download fails | Surface HF rate-limit message; suggest setting `HF_TOKEN`. |

## Downstream skill updates

Each gets a small additive section titled "Fetching video transcripts" that points to the new skill. No existing behavior is removed.

### 1. research-scout

**File:** `skills-n-stuff/plugins/research-scout/skills/research-scout/SKILL.md`

Current line ~70:
> - **YouTube videos**: Pull the transcript and analyze the full content…

Change to:
> - **YouTube / Shorts / Instagram / TikTok / Threads videos**: Use the `transcribe:transcribe` skill (or run `transcribe <url>` from Bash) to fetch a full transcript. Then analyze the full content — key concepts, tools mentioned, architectural patterns, specific recommendations, code examples discussed.

### 2. Shelby research skills

**Files to update** (to be confirmed during implementation):

- `Projects/Shelby/Shelby-MCP/skills/shelby-forage/SKILL.md` — only if it references video sources
- `Projects/Shelby/Shelby-MCP/skills/shelby-onboard/SKILL.md` — only if it references video sources
- Any Shelby-specific research skill not yet found

If none of these reference videos, we skip Shelby for this pass and note it in the plan. The scheduled `shelby-daily-research` task lives in `~/.claude/scheduled-tasks/` and may need its own update — investigate during implementation.

### 3. The Crooked Line research skills

**Files to update:**

- `Projects/The Crooked Line/.claude/skills/daily-research/SKILL.md`
- `Projects/The Crooked Line/.claude/skills/weekly-strategist/SKILL.md`

Add a short "Fetching video transcripts" section in each, pointing at the new skill. Same treatment as research-scout.

## Integration guide (shipped with plugin)

`skills/transcribe/references/integration-guide.md` explains for other skill authors:

- How to invoke from an LLM skill (use the Skill tool with `skill: "transcribe:transcribe", args: "<url>"`)
- How to invoke from Bash (`transcribe <url>` or `transcribe <url> --json`)
- What the output looks like
- Common gotchas (silent videos, login-gated posts, model download latency)

## Testing

Manual smoke tests against each platform on a short public clip:

| Platform | Test URL | Success criteria |
|---|---|---|
| YouTube | Me at the zoo (19s) | Transcript contains "elephants" |
| YouTube Short | Short clip with spoken word | Transcript non-empty, non-hallucinated |
| Instagram Reel | Public Reel from a known account | .mp4 extracted via yt-dlp, transcript non-empty |
| TikTok | Public TikTok | Transcript non-empty |
| Threads | Public video post with speech | Tier-2 fires, .mp4 captured via Playwright, transcript non-empty |
| Silent YouTube | Big Buck Bunny (silent) | Error or warning, not a hallucinated transcript |

No automated tests in v0.1 — external services make them flaky. Manual regression check before each version bump.

## Scope boundaries

**In scope (v0.1):**

- YouTube, Shorts, Instagram, TikTok, Threads
- Local transcription on Apple Silicon
- Markdown + JSON output
- Three downstream skill updates
- Manual install via `scripts/install.sh`

**Out of scope (v0.1):**

- Intel Mac / Linux support (noted as future `faster-whisper` path)
- Batch transcription of multiple URLs (workaround: shell loop)
- Translation (Whisper can do it; add a flag later if needed)
- Notion/Telegram integrations (explicitly dropped from claude-transcribe)
- Automated test suite
- Authentication flows for private content (manual Playwright profile sign-in only)

## Open questions

- Exact list of Shelby skills to update — resolve by grepping during implementation.
- Whether to commit the `playwright-profile/` cache directory path in install.sh, or leave it implicit.
