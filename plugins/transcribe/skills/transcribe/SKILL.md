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

# transcribe

Fetch a spoken-word transcript from a video URL. The plugin runs entirely locally on Apple Silicon using yt-dlp + mlx-whisper, with a headless-Playwright fallback for Threads and any other yt-dlp-unsupported platform.

## When to invoke

- The user gives you a YouTube, Shorts, Instagram, TikTok, or Threads URL and asks for a transcript, summary, analysis, or quote
- Another skill needs the spoken content of a video to do its job (e.g. research-scout analyzing a reference video)

## How to invoke

From the Bash tool:

```
transcribe <url>
transcribe <url> --json
```

The `transcribe` executable is on PATH once the plugin is installed.

From another skill, use the Skill tool:

```
Skill({ skill: "transcribe:transcribe", args: "<url>" })
```

## Output

**Default (markdown):**

```
# {title}

**Source:** {url}
**Platform:** {YouTube|Instagram|TikTok|Threads}
**Duration:** {mm:ss or "unknown"}
**Model:** mlx-community/whisper-large-v3-mlx

{transcript}
```

**With `--json`:** structured object with `title`, `url`, `platform`, `duration_seconds`, `model`, `tier` (`ytdlp` or `playwright`), `text`, and `segments[]` with timestamps.

## Dependencies

Install with:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh
```

Apple Silicon only in v0.1. Install deps: yt-dlp, ffmpeg, Node.js ≥ 20, Playwright Chromium, mlx-whisper.

## Model

Default model: `mlx-community/whisper-large-v3-mlx` (~3GB, downloaded on first use). Override per-call with the `WHISPER_MODEL` environment variable, for example:

```
WHISPER_MODEL=mlx-community/whisper-base-mlx transcribe <url>
```

Smaller models trade accuracy for speed. Use `whisper-base-mlx` (~140MB) for quick checks.

## Known limitations

- **Apple Silicon only.** Intel Macs and Linux error out with a clear message.
- **Silent videos hallucinate.** Whisper will invent text on silent or music-only audio. The plugin returns the transcript regardless but adds a stderr warning when repeated segments are detected.
- **Login-gated posts.** Public content only unless the user has signed into the persistent Playwright profile at `~/.cache/transcribe-plugin/playwright-profile/`.
- **No batching.** One URL per call. Use a shell loop for multiple.
- **Threads is flaky.** Threads post pages also render a feed of suggested videos, and Playwright's network capture can land on a neighbor instead of the target post. The extractor anchors to the `<video>` element's `currentSrc` and filters to segments sharing its CDN asset id, but expect occasional failures or mismatches. Retry or fall back to manual download for critical Threads transcripts.

## See also

- `references/integration-guide.md` — how other skills should invoke transcribe
