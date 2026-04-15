# transcribe

Local video transcription for Claude Code on Apple Silicon.

Handles YouTube, YouTube Shorts, Instagram posts/Reels, TikTok, and Threads. Uses yt-dlp + mlx-whisper for the first four; falls back to a headless-Playwright + Chromium pipeline for Threads (unsupported by yt-dlp upstream).

## Install

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh
```

Installs: yt-dlp, ffmpeg, Node.js, Playwright Chromium, mlx-whisper. Apple Silicon only.

## Usage

### As a slash command

```
/transcribe:transcribe <url>
```

### From the Bash tool (or terminal, after install)

```
transcribe <url>
transcribe <url> --json
```

### From another skill

```
Skill({ skill: "transcribe:transcribe", args: "<url>" })
```

## Configuration

| Env var         | Default                                   | Purpose                                |
|-----------------|-------------------------------------------|----------------------------------------|
| `WHISPER_MODEL` | `mlx-community/whisper-large-v3-mlx`      | mlx-whisper model HF repo              |
| `HF_TOKEN`      | —                                         | HuggingFace token (higher rate limits) |

## Output

**Markdown (default):**

```
# {title}

**Source:** {url}
**Platform:** YouTube
**Duration:** 0:19
**Model:** mlx-community/whisper-large-v3-mlx

{transcript}
```

**JSON (with `--json`):** includes timestamped segments.

## Scope and limitations

See the [design spec](../../docs/superpowers/specs/2026-04-14-transcribe-plugin-design.md) for what's in scope for v0.1.

## License

MIT
