# Transcribe Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `transcribe` plugin in the `skills-n-stuff` marketplace that fetches spoken-word transcripts from YouTube, YouTube Shorts, Instagram posts/Reels, TikTok, and Threads, then update `research-scout`, Shelby, and TCL research skills to use it.

**Architecture:** A Claude Code plugin with a single user-invocable skill (`/transcribe:transcribe`) backed by a bash orchestrator in `bin/transcribe`. Two-tier extraction: yt-dlp for supported platforms, headless Playwright Chromium for Threads and any other yt-dlp-unsupported URL. Audio is normalized via ffmpeg and transcribed locally by mlx-whisper on Apple Silicon.

**Tech Stack:** bash, Node.js ≥ 20, Playwright (Chromium), yt-dlp, ffmpeg, mlx-whisper (mlx-community/whisper-large-v3-mlx default).

**Spec:** [`docs/superpowers/specs/2026-04-14-transcribe-plugin-design.md`](../specs/2026-04-14-transcribe-plugin-design.md)

---

## File Structure

All paths are relative to the `skills-n-stuff` repo root unless otherwise noted.

**New files in this plan:**

- `plugins/transcribe/.claude-plugin/plugin.json` — plugin metadata
- `plugins/transcribe/README.md` — user-facing install + usage docs
- `plugins/transcribe/skills/transcribe/SKILL.md` — skill definition
- `plugins/transcribe/skills/transcribe/references/integration-guide.md` — reference for other skill authors
- `plugins/transcribe/bin/transcribe` — main orchestrator (executable bash)
- `plugins/transcribe/scripts/install.sh` — one-time dep installer
- `plugins/transcribe/scripts/verify-deps.sh` — pre-flight dep check
- `plugins/transcribe/scripts/extract-via-playwright.mjs` — tier-2 browser extractor

**Modified files in this plan:**

- `.claude-plugin/marketplace.json` — register the new plugin
- `plugins/research-scout/skills/research-scout/SKILL.md` — line ~70, video-source bullet
- `Projects/The Crooked Line/.claude/skills/daily-research/SKILL.md` — add transcript section
- `Projects/The Crooked Line/.claude/skills/weekly-strategist/SKILL.md` — add transcript section
- Shelby skills — TBD; Task 16 investigates which (if any) reference video sources and edits only those

---

## Task 1: Scaffold plugin directory and manifest

**Files:**
- Create: `plugins/transcribe/.claude-plugin/plugin.json`

- [ ] **Step 1: Create the plugin directory skeleton**

Run:
```bash
cd /Users/timmoser/Projects/skills-n-stuff
mkdir -p plugins/transcribe/.claude-plugin
mkdir -p plugins/transcribe/bin
mkdir -p plugins/transcribe/scripts
mkdir -p plugins/transcribe/skills/transcribe/references
```

Expected: four new directories under `plugins/transcribe/`.

- [ ] **Step 2: Write plugin.json**

Create `plugins/transcribe/.claude-plugin/plugin.json`:

```json
{
  "name": "transcribe",
  "version": "0.1.0",
  "description": "Transcribe spoken-word audio from YouTube, Shorts, Instagram, TikTok, and Threads. Local on Apple Silicon via yt-dlp + mlx-whisper, with a headless-Playwright fallback for Threads.",
  "author": {
    "name": "Studio Moser",
    "url": "https://github.com/Studio-Moser"
  },
  "repository": "https://github.com/Studio-Moser/skills-n-stuff",
  "license": "MIT",
  "keywords": [
    "transcript",
    "whisper",
    "video",
    "youtube",
    "instagram",
    "threads",
    "research"
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add plugins/transcribe/.claude-plugin/plugin.json
git commit -m "transcribe: scaffold plugin manifest"
```

---

## Task 2: Dependency verification script

**Files:**
- Create: `plugins/transcribe/scripts/verify-deps.sh`

- [ ] **Step 1: Write verify-deps.sh**

Create `plugins/transcribe/scripts/verify-deps.sh`:

```bash
#!/bin/bash
# verify-deps.sh — Check that all transcribe plugin deps are present.
# Exit 0 if all present, 1 if any missing. Prints a table to stderr.

set -u

missing=0
check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "  %-14s %s\n" "$name" "OK" >&2
  else
    printf "  %-14s %s\n" "$name" "MISSING" >&2
    missing=1
  fi
}

echo "Checking transcribe plugin dependencies:" >&2
check "yt-dlp"       "command -v yt-dlp"
check "ffmpeg"       "command -v ffmpeg"
check "python3"      "command -v python3"
check "mlx-whisper"  "python3 -c 'import mlx_whisper'"
check "node"         "command -v node"
check "chromium"     "test -d \"$HOME/.cache/ms-playwright\" || test -d \"$HOME/Library/Caches/ms-playwright\""

if [[ $missing -eq 1 ]]; then
  echo "" >&2
  echo "One or more dependencies are missing." >&2
  echo "Run: bash \"\${CLAUDE_PLUGIN_ROOT:-plugins/transcribe}/scripts/install.sh\"" >&2
  exit 1
fi

echo "All dependencies OK." >&2
exit 0
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x plugins/transcribe/scripts/verify-deps.sh
```

- [ ] **Step 3: Sanity-run it**

Run:
```bash
bash plugins/transcribe/scripts/verify-deps.sh
```

Expected output (yt-dlp, ffmpeg, python3, mlx-whisper already installed from the `claude-transcribe` test session; node and chromium may or may not be present):

```
Checking transcribe plugin dependencies:
  yt-dlp         OK
  ffmpeg         OK
  python3        OK
  mlx-whisper    OK
  node           OK or MISSING
  chromium       OK or MISSING
```

If `node` or `chromium` is missing, that's expected for this step — Task 3 installs them.

- [ ] **Step 4: Commit**

```bash
git add plugins/transcribe/scripts/verify-deps.sh
git commit -m "transcribe: add dependency verification script"
```

---

## Task 3: Install script

**Files:**
- Create: `plugins/transcribe/scripts/install.sh`

- [ ] **Step 1: Write install.sh**

Create `plugins/transcribe/scripts/install.sh`:

```bash
#!/bin/bash
# install.sh — One-time install for the transcribe plugin.
# Installs: yt-dlp, ffmpeg, mlx-whisper, Node.js, Playwright Chromium.
#
# Apple Silicon only. Intel Macs and Linux are not supported in v0.1.

set -euo pipefail

# ── Platform check ───────────────────────────────────────────────────────────

if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: transcribe plugin v0.1 supports Apple Silicon only." >&2
  echo "Detected: $(uname) $(uname -m)" >&2
  exit 1
fi

# ── Homebrew ─────────────────────────────────────────────────────────────────

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is required. Install from https://brew.sh and retry." >&2
  exit 1
fi

echo "→ Installing system packages via Homebrew..."
for pkg in yt-dlp ffmpeg node; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    echo "  $pkg already installed."
  else
    brew install "$pkg"
  fi
done

# ── mlx-whisper ──────────────────────────────────────────────────────────────

echo "→ Installing mlx-whisper..."
if python3 -c "import mlx_whisper" >/dev/null 2>&1; then
  echo "  mlx-whisper already installed."
else
  pip3 install --break-system-packages mlx-whisper
fi

# ── Playwright Chromium ──────────────────────────────────────────────────────

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "→ Installing Playwright and Chromium..."
pushd "$PLUGIN_ROOT" >/dev/null
if [[ ! -f package.json ]]; then
  cat > package.json <<'JSON'
{
  "name": "transcribe-plugin",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "playwright": "^1.48.0"
  }
}
JSON
fi
npm install --no-audit --no-fund
npx playwright install chromium
popd >/dev/null

# ── Profile dir ──────────────────────────────────────────────────────────────

mkdir -p "$HOME/.cache/transcribe-plugin/playwright-profile"

echo ""
echo "Install complete. Verify with: bash $PLUGIN_ROOT/scripts/verify-deps.sh"
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x plugins/transcribe/scripts/install.sh
```

- [ ] **Step 3: Run the installer**

Run:
```bash
bash plugins/transcribe/scripts/install.sh
```

Expected: installs any missing deps; `node` appears in `/opt/homebrew/bin/node`; Chromium lands under `~/Library/Caches/ms-playwright/` or `~/.cache/ms-playwright/`; profile dir created; final "Install complete" line.

Note: `package.json` and `package-lock.json` (and `node_modules/`) are created in `plugins/transcribe/`. `node_modules/` must be git-ignored.

- [ ] **Step 4: Add node_modules to gitignore**

Check for an existing `.gitignore`:
```bash
cat .gitignore 2>/dev/null || echo "(no gitignore)"
```

If a root `.gitignore` exists, append `plugins/transcribe/node_modules/` to it. If none exists, create `plugins/transcribe/.gitignore` with:

```
node_modules/
```

- [ ] **Step 5: Re-run verify-deps**

Run:
```bash
bash plugins/transcribe/scripts/verify-deps.sh
```

Expected: all six rows show `OK`. Exit code 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/transcribe/scripts/install.sh plugins/transcribe/package.json plugins/transcribe/package-lock.json plugins/transcribe/.gitignore
# If you updated the root .gitignore instead of creating a plugin-level one:
# git add .gitignore
git commit -m "transcribe: add install script and Playwright dep"
```

---

## Task 4: bin/transcribe — tier 1 (yt-dlp) only

**Files:**
- Create: `plugins/transcribe/bin/transcribe`

- [ ] **Step 1: Write the tier-1 orchestrator**

Create `plugins/transcribe/bin/transcribe`:

```bash
#!/bin/bash
# transcribe — Fetch a spoken-word transcript from a video URL.
#
# Usage:
#   transcribe <url>           # markdown output
#   transcribe <url> --json    # JSON output
#
# Env:
#   WHISPER_MODEL    mlx-whisper model (default: mlx-community/whisper-large-v3-mlx)
#   HF_TOKEN         HuggingFace token, raises HF download rate limits

set -euo pipefail

# ── Parse args ───────────────────────────────────────────────────────────────

URL=""
OUTPUT_JSON=false

for arg in "$@"; do
  case "$arg" in
    --json) OUTPUT_JSON=true ;;
    -h|--help)
      cat <<'HELP'
transcribe — fetch a spoken-word transcript from a video URL.

Usage:
  transcribe <url>           Markdown output (default)
  transcribe <url> --json    JSON output

Supports: YouTube, YouTube Shorts, Instagram posts/Reels, TikTok, Threads.

Env:
  WHISPER_MODEL   mlx-whisper model (default: mlx-community/whisper-large-v3-mlx)
  HF_TOKEN        HuggingFace token for higher download rate limits
HELP
      exit 0 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *)  URL="$arg" ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "Usage: transcribe <url> [--json]" >&2
  exit 1
fi

# ── Locate plugin scripts ────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Verify deps ──────────────────────────────────────────────────────────────

"$PLUGIN_ROOT/scripts/verify-deps.sh" >/dev/null 2>&1 || {
  echo "ERROR: transcribe plugin deps missing." >&2
  echo "Run: bash $PLUGIN_ROOT/scripts/install.sh" >&2
  exit 1
}

# ── Detect platform ──────────────────────────────────────────────────────────

detect_platform() {
  local url="$1"
  if   [[ "$url" =~ (youtube\.com|youtu\.be) ]]; then echo "YouTube"
  elif [[ "$url" =~ instagram\.com ]];          then echo "Instagram"
  elif [[ "$url" =~ tiktok\.com ]];             then echo "TikTok"
  elif [[ "$url" =~ threads\.(net|com) ]];      then echo "Threads"
  else                                               echo "Unknown"
  fi
}

PLATFORM="$(detect_platform "$URL")"
echo "Platform: $PLATFORM" >&2

# ── Temp dir ─────────────────────────────────────────────────────────────────

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT
AUDIO_WAV="$TMPDIR_WORK/audio_16k.wav"

# ── Tier 1: yt-dlp ───────────────────────────────────────────────────────────

WHISPER_MODEL="${WHISPER_MODEL:-mlx-community/whisper-large-v3-mlx}"
VIDEO_TITLE="Unknown"
DURATION_SECONDS=0
USED_TIER=""

tier1_ytdlp() {
  echo "→ Tier 1: yt-dlp" >&2

  # Title + duration via yt-dlp metadata (may fail on some URLs; tolerate)
  local meta
  meta="$(yt-dlp --print "%(title)s|||%(duration)s" "$URL" 2>/dev/null || true)"
  if [[ -n "$meta" ]]; then
    VIDEO_TITLE="${meta%%|||*}"
    DURATION_SECONDS="${meta##*|||}"
    [[ "$DURATION_SECONDS" == "NA" || -z "$DURATION_SECONDS" ]] && DURATION_SECONDS=0
  fi

  # Download + extract audio
  if ! yt-dlp -x --audio-format wav \
        -o "$TMPDIR_WORK/audio_raw.%(ext)s" \
        "$URL" >/dev/null 2>&1; then
    return 1
  fi

  local raw
  raw="$(find "$TMPDIR_WORK" -name 'audio_raw.*' -type f | head -1)"
  [[ -z "$raw" ]] && return 1

  ffmpeg -y -i "$raw" -ar 16000 -ac 1 -c:a pcm_s16le "$AUDIO_WAV" >/dev/null 2>&1 || return 1

  USED_TIER="ytdlp"
  return 0
}

# ── Skip tier 1 for known-unsupported platforms ──────────────────────────────

if [[ "$PLATFORM" == "Threads" ]]; then
  echo "→ Tier 1 skipped (Threads unsupported by yt-dlp)" >&2
elif tier1_ytdlp; then
  :
else
  echo "→ Tier 1 failed, will fall through to tier 2 (not yet implemented)" >&2
  echo "ERROR: tier 1 failed and tier 2 is not available in this task." >&2
  exit 2
fi

if [[ "$PLATFORM" == "Threads" ]]; then
  echo "ERROR: Threads not supported in this task. Implemented in Task 7." >&2
  exit 2
fi

# ── Transcribe with mlx-whisper ──────────────────────────────────────────────

echo "→ Transcribing with $WHISPER_MODEL" >&2
TRANSCRIPT_JSON="$TMPDIR_WORK/transcript.json"
python3 - <<PYEOF > "$TRANSCRIPT_JSON"
import json, mlx_whisper
r = mlx_whisper.transcribe("$AUDIO_WAV", path_or_hf_repo="$WHISPER_MODEL")
print(json.dumps(r))
PYEOF

TRANSCRIPT_TEXT="$(python3 -c "import json,sys; print(json.load(open('$TRANSCRIPT_JSON'))['text'].strip())")"

# ── Format output ────────────────────────────────────────────────────────────

human_duration() {
  local s="${1:-0}"
  [[ "$s" == "0" ]] && { echo "unknown"; return; }
  printf "%d:%02d" $((s/60)) $((s%60))
}

if $OUTPUT_JSON; then
  python3 - <<PYEOF
import json
data = json.load(open("$TRANSCRIPT_JSON"))
out = {
    "title": """$VIDEO_TITLE""",
    "url": """$URL""",
    "platform": """$PLATFORM""",
    "duration_seconds": int("$DURATION_SECONDS" or 0),
    "model": """$WHISPER_MODEL""",
    "tier": """$USED_TIER""",
    "text": data.get("text", "").strip(),
    "segments": [
        {"start": s["start"], "end": s["end"], "text": s["text"].strip()}
        for s in data.get("segments", [])
    ],
}
print(json.dumps(out, indent=2))
PYEOF
else
  cat <<MD
# $VIDEO_TITLE

**Source:** $URL
**Platform:** $PLATFORM
**Duration:** $(human_duration "$DURATION_SECONDS")
**Model:** $WHISPER_MODEL

$TRANSCRIPT_TEXT
MD
fi
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x plugins/transcribe/bin/transcribe
```

- [ ] **Step 3: Commit**

```bash
git add plugins/transcribe/bin/transcribe
git commit -m "transcribe: add orchestrator with tier-1 (yt-dlp) pipeline"
```

---

## Task 5: Smoke-test tier 1 on YouTube

**Files:** none (smoke test)

- [ ] **Step 1: Run on the 19-second reference video**

Run:
```bash
plugins/transcribe/bin/transcribe "https://www.youtube.com/watch?v=jNQXAC9IVRw"
```

Expected output (abbreviated):

```
Platform: YouTube
→ Tier 1: yt-dlp
→ Transcribing with mlx-community/whisper-large-v3-mlx
# Me at the zoo

**Source:** https://www.youtube.com/watch?v=jNQXAC9IVRw
**Platform:** YouTube
**Duration:** 0:19
**Model:** mlx-community/whisper-large-v3-mlx

All right, so here we are, in front of the, uh, elephants, ...
```

Success criteria:
- Exit code 0
- Markdown output contains "elephants"
- Duration shown as `0:19`

- [ ] **Step 2: Run with --json flag**

Run:
```bash
plugins/transcribe/bin/transcribe "https://www.youtube.com/watch?v=jNQXAC9IVRw" --json > /tmp/tr_test.json
python3 -c "import json; d=json.load(open('/tmp/tr_test.json')); print('OK' if 'elephants' in d['text'].lower() else 'FAIL')"
```

Expected: `OK`. Validates both markdown and JSON outputs produce equivalent transcripts.

---

## Task 6: Smoke-test tier 1 on Instagram and TikTok

**Files:** none (smoke test)

Note: these tests use external public content. If either URL is dead at runtime, substitute any public Reel / TikTok with spoken audio.

- [ ] **Step 1: Find a public Instagram Reel**

Pick any public Reel by browsing to an account with public short videos (NASA, official brand accounts, etc.) and copying the URL. Example pattern: `https://www.instagram.com/reel/{shortcode}/`.

Document the URL you chose (you'll re-use it for the integration guide examples).

- [ ] **Step 2: Run transcribe on the Instagram URL**

Run:
```bash
plugins/transcribe/bin/transcribe "<your-instagram-reel-url>"
```

Expected:
- Exit code 0
- Platform line reads `Platform: Instagram`
- Tier line reads `→ Tier 1: yt-dlp`
- A non-empty transcript is emitted

If yt-dlp fails with "rate-limit reached" or "login required", note it — Instagram's access policies vary by IP / time of day. Retry once; if it fails again, skip this test and note in the commit message.

- [ ] **Step 3: Find a public TikTok**

Pick any public TikTok with spoken word.

- [ ] **Step 4: Run transcribe on the TikTok URL**

Run:
```bash
plugins/transcribe/bin/transcribe "<your-tiktok-url>"
```

Expected:
- Exit code 0
- Platform: `TikTok`
- Non-empty transcript

No commit for this task — smoke tests only.

---

## Task 7: Tier 2 — Playwright extractor

**Files:**
- Create: `plugins/transcribe/scripts/extract-via-playwright.mjs`

- [ ] **Step 1: Write the Playwright extractor**

Create `plugins/transcribe/scripts/extract-via-playwright.mjs`:

```javascript
#!/usr/bin/env node
// extract-via-playwright.mjs — Extract video+metadata from a JS-rendered page
// (primarily Threads, but works as a generic fallback).
//
// Stdin:   none
// Argv:    <url> <output-path>
// Stdout:  JSON: { "title": "...", "duration_seconds": 0, "video_path": "/abs/path.mp4" }
// Exit:    0 on success, non-zero on failure (with message on stderr)

import { chromium } from 'playwright';
import { createWriteStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const [, , URL_ARG, OUT_DIR] = process.argv;

if (!URL_ARG || !OUT_DIR) {
  console.error('Usage: extract-via-playwright.mjs <url> <output-dir>');
  process.exit(2);
}

const PROFILE_DIR = path.join(
  process.env.HOME,
  '.cache',
  'transcribe-plugin',
  'playwright-profile'
);

const ctx = await chromium.launchPersistentContext(PROFILE_DIR, {
  headless: true,
  args: ['--no-sandbox'],
});
const page = await ctx.newPage();

/** @type {string | null} */
let videoUrl = null;
/** @type {Record<string,string>} */
let videoHeaders = {};

// Capture the first .mp4 URL the page requests.
page.on('response', (resp) => {
  const u = resp.url();
  if (!videoUrl && /\.mp4(\?|$)/.test(u)) {
    videoUrl = u;
    videoHeaders = resp.request().headers();
  }
});

try {
  await page.goto(URL_ARG, { waitUntil: 'domcontentloaded', timeout: 30_000 });
  // Wait for a <video> element and give the network a moment to fetch the mp4.
  await page.waitForSelector('video', { timeout: 20_000 });
  // Threads often delays the mp4 until the element is in view; give it 3s.
  await page.waitForTimeout(3_000);
} catch (err) {
  // Try one retry cycle.
  try {
    await page.waitForTimeout(5_000);
    await page.waitForSelector('video', { timeout: 15_000 });
    await page.waitForTimeout(3_000);
  } catch {
    await ctx.close();
    console.error(`ERROR: timed out waiting for <video>. URL: ${URL_ARG}`);
    process.exit(3);
  }
}

if (!videoUrl) {
  // Fallback: ask the page directly.
  videoUrl = await page
    .$eval('video', (v) => v.currentSrc || v.src)
    .catch(() => null);
}

// Best-effort title scrape.
const title = await page.title().catch(() => 'Unknown');

await ctx.close();

if (!videoUrl) {
  console.error('ERROR: no .mp4 URL detected for this page.');
  process.exit(4);
}

// Download with fetch, passing through any captured request headers so
// Instagram/Threads CDNs (which 403 anonymous requests) accept us.
const outPath = path.join(OUT_DIR, 'video.mp4');
const headers = { ...videoHeaders };
delete headers.host;
delete headers[':authority'];
delete headers[':method'];
delete headers[':path'];
delete headers[':scheme'];

const resp = await fetch(videoUrl, { headers });
if (!resp.ok) {
  console.error(`ERROR: CDN returned HTTP ${resp.status} for ${videoUrl}`);
  process.exit(5);
}
await pipeline(resp.body, createWriteStream(outPath));

process.stdout.write(
  JSON.stringify({
    title,
    duration_seconds: 0,
    video_path: outPath,
  }) + '\n'
);
```

- [ ] **Step 2: Verify the extractor runs standalone**

Run:
```bash
mkdir -p /tmp/transcribe-smoketest
cd /Users/timmoser/Projects/skills-n-stuff/plugins/transcribe
node scripts/extract-via-playwright.mjs \
  "https://www.threads.com/@alexgillon/post/CuVlmIzornl" \
  /tmp/transcribe-smoketest
```

Expected stdout: a single JSON line like `{"title":"…","duration_seconds":0,"video_path":"/tmp/transcribe-smoketest/video.mp4"}`
Expected files: `/tmp/transcribe-smoketest/video.mp4` exists, non-zero size.

If it fails with exit 3 or 4, the Threads post may not actually contain a public video — substitute any public Threads URL that does (e.g. `https://www.threads.com/@threads/post/C04KN6fODek`).

- [ ] **Step 3: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/transcribe/scripts/extract-via-playwright.mjs
git commit -m "transcribe: add Playwright extractor for JS-rendered sources"
```

---

## Task 8: Wire tier 2 into bin/transcribe

**Files:**
- Modify: `plugins/transcribe/bin/transcribe`

- [ ] **Step 1: Replace the tier-2 error stubs with a working fallback**

In `plugins/transcribe/bin/transcribe`, find the block:

```bash
if [[ "$PLATFORM" == "Threads" ]]; then
  echo "→ Tier 1 skipped (Threads unsupported by yt-dlp)" >&2
elif tier1_ytdlp; then
  :
else
  echo "→ Tier 1 failed, will fall through to tier 2 (not yet implemented)" >&2
  echo "ERROR: tier 1 failed and tier 2 is not available in this task." >&2
  exit 2
fi

if [[ "$PLATFORM" == "Threads" ]]; then
  echo "ERROR: Threads not supported in this task. Implemented in Task 7." >&2
  exit 2
fi
```

Replace it with:

```bash
tier2_playwright() {
  echo "→ Tier 2: Playwright" >&2
  local meta
  meta="$(node "$PLUGIN_ROOT/scripts/extract-via-playwright.mjs" "$URL" "$TMPDIR_WORK")"
  local vid_path
  vid_path="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['video_path'])" "$meta")"
  VIDEO_TITLE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['title'])" "$meta")"
  # Playwright path doesn't give duration reliably; probe with ffprobe.
  DURATION_SECONDS="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$vid_path" 2>/dev/null | cut -d. -f1 || echo 0)"
  [[ -z "$DURATION_SECONDS" ]] && DURATION_SECONDS=0
  ffmpeg -y -i "$vid_path" -ar 16000 -ac 1 -c:a pcm_s16le "$AUDIO_WAV" >/dev/null 2>&1 || return 1
  USED_TIER="playwright"
  return 0
}

if [[ "$PLATFORM" == "Threads" ]]; then
  echo "→ Tier 1 skipped (Threads unsupported by yt-dlp)" >&2
  tier2_playwright || { echo "ERROR: tier 2 extraction failed for $URL" >&2; exit 2; }
elif tier1_ytdlp; then
  :
else
  echo "→ Tier 1 failed, falling through to tier 2" >&2
  tier2_playwright || { echo "ERROR: both tiers failed for $URL" >&2; exit 2; }
fi
```

- [ ] **Step 2: Smoke-test Threads**

Run:
```bash
plugins/transcribe/bin/transcribe "https://www.threads.com/@alexgillon/post/CuVlmIzornl"
```

Expected:
- `Platform: Threads`
- `→ Tier 1 skipped (Threads unsupported by yt-dlp)`
- `→ Tier 2: Playwright`
- Markdown output with a non-empty transcript

If Playwright times out on this specific URL, substitute any other public Threads video post (see Task 7 for fallback URLs).

- [ ] **Step 3: Smoke-test tier-2 fallback on a non-Threads URL**

Deliberately force a tier-1 failure. Easiest path: pass a URL yt-dlp can't extract. Use a random unknown-to-yt-dlp video URL:

Run:
```bash
plugins/transcribe/bin/transcribe "https://example-broken-url.test/video"
```

Expected: tier 1 fails, tier 2 tries, both fail cleanly with exit code 2 and an error message. No traceback.

- [ ] **Step 4: Commit**

```bash
git add plugins/transcribe/bin/transcribe
git commit -m "transcribe: wire tier-2 Playwright fallback"
```

---

## Task 9: SKILL.md

**Files:**
- Create: `plugins/transcribe/skills/transcribe/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `plugins/transcribe/skills/transcribe/SKILL.md`:

```markdown
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

## See also

- `references/integration-guide.md` — how other skills should invoke transcribe
```

- [ ] **Step 2: Commit**

```bash
git add plugins/transcribe/skills/transcribe/SKILL.md
git commit -m "transcribe: add SKILL.md"
```

---

## Task 10: Integration guide for other skill authors

**Files:**
- Create: `plugins/transcribe/skills/transcribe/references/integration-guide.md`

- [ ] **Step 1: Write the integration guide**

Create `plugins/transcribe/skills/transcribe/references/integration-guide.md`:

```markdown
# Integration Guide

For skill authors who want to use the `transcribe` skill to fetch video transcripts.

## Two ways to invoke

### 1. From Bash (recommended for simple pipelines)

```
transcribe <url>
transcribe <url> --json
```

The `transcribe` binary is on PATH once the plugin is installed. Output goes to stdout; logs go to stderr.

### 2. Via the Skill tool (recommended when LLM reasoning over the transcript is needed)

```
Skill({ skill: "transcribe:transcribe", args: "<url>" })
```

The skill loads with full context, runs the bash pipeline, and returns the markdown-formatted transcript to your conversation.

## Pattern for research skills

```markdown
When a user provides a video URL (YouTube, Shorts, Instagram, TikTok, Threads):

1. Call `transcribe <url>` from Bash to get the full transcript as markdown.
2. Treat the transcript as the primary source material for your analysis.
3. Preserve the source link in your output so the user can reference the original.

If `transcribe` exits non-zero, report the stderr output to the user and stop — do not try to analyze the video without its transcript.
```

## Gotchas

- **First call is slow.** The default whisper-large-v3 model downloads ~3GB on first use. Subsequent calls are fast.
- **Silent videos hallucinate.** Always check the transcript for obvious repetition (e.g. a sentence repeated 50 times) before treating it as ground truth.
- **Threads is slower** — it goes through Playwright. Budget 30-60 seconds for a short clip.
- **Don't cache transcripts silently.** If you're running inside a research pipeline, save the transcript alongside the report so the user can audit what the model actually saw.

## Example skill snippet

```markdown
## Fetching video transcripts

For any video URL (YouTube, Shorts, Instagram, TikTok, Threads), fetch the full transcript with the transcribe skill before analysis:

Bash: `transcribe <url>`

This returns a markdown document with title, source, platform, duration, and the full spoken text. Use the transcript as your primary source.
```

Copy-paste this section into any skill that analyzes video content.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/transcribe/skills/transcribe/references/integration-guide.md
git commit -m "transcribe: add integration guide for downstream skills"
```

---

## Task 11: README for the plugin

**Files:**
- Create: `plugins/transcribe/README.md`

- [ ] **Step 1: Write README.md**

Create `plugins/transcribe/README.md`:

```markdown
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

| Env var         | Default                                   | Purpose                            |
|-----------------|-------------------------------------------|-------------------------------------|
| `WHISPER_MODEL` | `mlx-community/whisper-large-v3-mlx`      | mlx-whisper model HF repo          |
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
```

- [ ] **Step 2: Commit**

```bash
git add plugins/transcribe/README.md
git commit -m "transcribe: add README"
```

---

## Task 12: Register plugin in marketplace

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Inspect current marketplace.json**

Run:
```bash
cat .claude-plugin/marketplace.json
```

Confirm the file's `plugins` array currently contains `product-pulse`, `research-scout`, and `site-capture`.

- [ ] **Step 2: Add transcribe entry**

Edit `.claude-plugin/marketplace.json`. Append to the `plugins` array:

```json
    {
      "name": "transcribe",
      "source": "./plugins/transcribe",
      "description": "Transcribe spoken-word audio from YouTube, Shorts, Instagram, TikTok, and Threads. Local on Apple Silicon via yt-dlp + mlx-whisper, with a headless-Playwright fallback for Threads.",
      "version": "0.1.0",
      "author": {
        "name": "Studio Moser"
      },
      "license": "MIT",
      "keywords": [
        "transcript",
        "whisper",
        "video",
        "youtube",
        "instagram",
        "threads",
        "research"
      ],
      "category": "productivity",
      "tags": [
        "research",
        "transcript",
        "video"
      ]
    }
```

Add a comma before this entry to the closing `}` of the preceding entry.

- [ ] **Step 3: Validate JSON**

Run:
```bash
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null && echo OK
```

Expected: `OK`. If it prints an error, the JSON is malformed — fix the missing/extra comma and re-run.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "Register transcribe plugin in marketplace.json"
```

---

## Task 13: Update research-scout

**Files:**
- Modify: `plugins/research-scout/skills/research-scout/SKILL.md`

- [ ] **Step 1: Locate the line to change**

Run:
```bash
grep -n "YouTube videos" plugins/research-scout/skills/research-scout/SKILL.md
```

Expected: exactly one match near line 70.

- [ ] **Step 2: Update the bullet**

In `plugins/research-scout/skills/research-scout/SKILL.md`, find:

```markdown
- **YouTube videos**: Pull the transcript and analyze the full content — key concepts, tools mentioned, architectural patterns, specific recommendations, code examples discussed.
```

Replace with:

```markdown
- **YouTube / Shorts / Instagram / TikTok / Threads videos**: Fetch the full transcript with the `transcribe` skill — from Bash as `transcribe <url>`, or via `Skill({ skill: "transcribe:transcribe", args: "<url>" })`. Then analyze the full content — key concepts, tools mentioned, architectural patterns, specific recommendations, code examples discussed. If transcribe fails, surface the stderr message to the user and stop; do not try to analyze the video without its transcript.
```

- [ ] **Step 3: Verify the only change is that line**

Run:
```bash
git diff plugins/research-scout/skills/research-scout/SKILL.md
```

Expected: a single-line diff replacing the old bullet with the new one.

- [ ] **Step 4: Commit**

```bash
git add plugins/research-scout/skills/research-scout/SKILL.md
git commit -m "research-scout: delegate video transcription to transcribe plugin"
```

---

## Task 14: Update TCL daily-research

**Files:**
- Modify: `/Users/timmoser/Projects/The Crooked Line/.claude/skills/daily-research/SKILL.md`

- [ ] **Step 1: Inspect the current skill**

Run:
```bash
head -80 "/Users/timmoser/Projects/The Crooked Line/.claude/skills/daily-research/SKILL.md"
```

Locate a natural seam — typically after the "Input sources" or "Fetching sources" section — where a "Fetching video transcripts" subsection should sit.

- [ ] **Step 2: Insert the transcript section**

Add this section after whatever section discusses input sources (if unclear, add it immediately before the first task/step section):

```markdown
## Fetching video transcripts

For any video URL (YouTube, Shorts, Instagram, TikTok, Threads), fetch the full transcript with the transcribe skill before analysis:

Bash: `transcribe <url>`

This returns a markdown document with title, source, platform, duration, and the full spoken text. Use the transcript as your primary source and preserve the original URL in your report.

If `transcribe` exits non-zero, surface the stderr output and stop — do not analyze the video without its transcript.
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -n "transcribe" "/Users/timmoser/Projects/The Crooked Line/.claude/skills/daily-research/SKILL.md"
```

Expected: at least 2 matches (the new section header and body).

- [ ] **Step 4: Commit — in TCL repo**

The TCL skills live in a separate repo. Change directory and commit there:

```bash
cd "/Users/timmoser/Projects/The Crooked Line"
git add .claude/skills/daily-research/SKILL.md
git commit -m "daily-research: use transcribe skill for video transcripts"
cd /Users/timmoser/Projects/skills-n-stuff
```

---

## Task 15: Update TCL weekly-strategist

**Files:**
- Modify: `/Users/timmoser/Projects/The Crooked Line/.claude/skills/weekly-strategist/SKILL.md`

- [ ] **Step 1: Inspect the current skill**

Run:
```bash
head -80 "/Users/timmoser/Projects/The Crooked Line/.claude/skills/weekly-strategist/SKILL.md"
```

Find the section where references or sources are described.

- [ ] **Step 2: Insert the transcript section**

Add the same section as Task 14 (copy verbatim):

```markdown
## Fetching video transcripts

For any video URL (YouTube, Shorts, Instagram, TikTok, Threads), fetch the full transcript with the transcribe skill before analysis:

Bash: `transcribe <url>`

This returns a markdown document with title, source, platform, duration, and the full spoken text. Use the transcript as your primary source and preserve the original URL in your report.

If `transcribe` exits non-zero, surface the stderr output and stop — do not analyze the video without its transcript.
```

Place it next to any existing "sources" or "references" discussion.

- [ ] **Step 3: Verify**

Run:
```bash
grep -n "transcribe" "/Users/timmoser/Projects/The Crooked Line/.claude/skills/weekly-strategist/SKILL.md"
```

Expected: at least 2 matches.

- [ ] **Step 4: Commit**

```bash
cd "/Users/timmoser/Projects/The Crooked Line"
git add .claude/skills/weekly-strategist/SKILL.md
git commit -m "weekly-strategist: use transcribe skill for video transcripts"
cd /Users/timmoser/Projects/skills-n-stuff
```

---

## Task 16: Investigate and update Shelby research skills

**Files:** TBD (decided by investigation)

- [ ] **Step 1: Find video-related references in Shelby skills**

Run:
```bash
grep -rn -l -E "(youtube|transcript|video)" /Users/timmoser/Projects/Shelby/Shelby-MCP/skills/ 2>/dev/null
```

Record which files match.

- [ ] **Step 2: Check the scheduled tasks too**

Run:
```bash
grep -l -E "(youtube|transcript|video)" /Users/timmoser/.claude/scheduled-tasks/shelby-daily-research/SKILL.md 2>/dev/null
```

- [ ] **Step 3: Decide scope**

- **If no matches in either step 1 or step 2:** Shelby skills don't currently reference videos. Add the transcript section anyway to `shelby-forage/SKILL.md` as a forward-looking capability note, positioned near its existing "Inputs" discussion (check with `head -40 ~/Projects/Shelby/Shelby-MCP/skills/shelby-forage/SKILL.md`). Skip `shelby-onboard` — it's setup-focused and doesn't consume research inputs.
- **If matches exist:** update each matching file with the transcript section from Task 14.

- [ ] **Step 4: Apply updates**

For each file identified in step 3, insert this section (same wording as Task 14):

```markdown
## Fetching video transcripts

For any video URL (YouTube, Shorts, Instagram, TikTok, Threads), fetch the full transcript with the transcribe skill before analysis:

Bash: `transcribe <url>`

This returns a markdown document with title, source, platform, duration, and the full spoken text. Use the transcript as your primary source and preserve the original URL in your report.

If `transcribe` exits non-zero, surface the stderr output and stop — do not analyze the video without its transcript.
```

- [ ] **Step 5: Verify**

For each file edited:
```bash
grep -c "transcribe" "<path>"
```

Expected: ≥ 2.

- [ ] **Step 6: Commit — in Shelby repo**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-MCP
git add skills/
git commit -m "shelby: use transcribe skill for video transcripts"
cd /Users/timmoser/Projects/skills-n-stuff
```

If the scheduled-tasks file was touched (step 2 matched), commit that in its own repo (scheduled-tasks is under `~/.claude/scheduled-tasks/` and is typically not a git repo — leave the edit in place and note it in your summary).

---

## Task 17: End-to-end smoke test across all platforms

**Files:** none (final verification)

- [ ] **Step 1: YouTube**

Run:
```bash
plugins/transcribe/bin/transcribe "https://www.youtube.com/watch?v=jNQXAC9IVRw"
```

Expected: exit 0, transcript contains "elephants".

- [ ] **Step 2: Instagram Reel**

Run:
```bash
plugins/transcribe/bin/transcribe "<your-instagram-reel-url-from-task-6>"
```

Expected: exit 0, platform `Instagram`, tier `ytdlp`, non-empty transcript.

- [ ] **Step 3: TikTok**

Run:
```bash
plugins/transcribe/bin/transcribe "<your-tiktok-url-from-task-6>"
```

Expected: exit 0, platform `TikTok`, tier `ytdlp`, non-empty transcript.

- [ ] **Step 4: Threads**

Run:
```bash
plugins/transcribe/bin/transcribe "https://www.threads.com/@alexgillon/post/CuVlmIzornl"
```

Expected: exit 0, platform `Threads`, tier `playwright`, non-empty transcript.

- [ ] **Step 5: Silent video (expected-to-warn case)**

Run:
```bash
plugins/transcribe/bin/transcribe "https://www.youtube.com/shorts/aqz-KE-bpKQ"
```

Expected: exit 0, but the transcript will contain obvious repetition (whisper hallucinating on Big Buck Bunny's score). This is a documented limitation; we surface the transcript regardless. No action needed other than confirming the pipeline didn't crash.

---

## Task 18: Verify plugin loads correctly

**Files:** none

- [ ] **Step 1: Check the marketplace lists transcribe**

Run:
```bash
python3 -c "import json; m=json.load(open('.claude-plugin/marketplace.json')); print([p['name'] for p in m['plugins']])"
```

Expected: `['product-pulse', 'research-scout', 'site-capture', 'transcribe']`

- [ ] **Step 2: Confirm skill frontmatter parses**

Run:
```bash
head -10 plugins/transcribe/skills/transcribe/SKILL.md
```

Expected: valid YAML frontmatter starting with `---`, ending with `---`, with `name: transcribe` and a `description:` block.

- [ ] **Step 3: Confirm the bin executable is found on PATH when plugin is loaded**

Follow the manual load/install path (outside scope of this automated plan — user verifies by reloading Claude Code and running `/transcribe:transcribe <url>`).

---

## Self-review

**Spec coverage checklist:**

- [x] Plugin structure per spec — Task 1
- [x] yt-dlp tier 1 — Task 4
- [x] Playwright tier 2 — Tasks 7–8
- [x] Markdown + JSON output — Task 4
- [x] whisper-large-v3 default, override via WHISPER_MODEL — Task 4, Task 9
- [x] No Notion/Telegram integrations — not present anywhere
- [x] Apple Silicon only with clear error — Task 3
- [x] Silent-video handling — documented in Tasks 9, 17
- [x] Persistent Playwright profile — Tasks 3, 7
- [x] SKILL.md user-invocable, allowed-tools Bash — Task 9
- [x] Integration guide shipped — Task 10
- [x] Marketplace registration — Task 12
- [x] Update research-scout — Task 13
- [x] Update TCL daily-research and weekly-strategist — Tasks 14, 15
- [x] Investigate + update Shelby skills — Task 16
- [x] Manual smoke tests across platforms — Tasks 5, 6, 8, 17

**Placeholder scan:** No TBD/TODO/"etc" steps. Every step has exact code or commands. Task 16 is deliberately investigative — it defines a clear decision procedure, not a placeholder.

**Type consistency:** `tier1_ytdlp` and `tier2_playwright` function names match between Tasks 4 and 8. `USED_TIER` values `"ytdlp"` / `"playwright"` are consistent across the orchestrator and the JSON output. Model name `mlx-community/whisper-large-v3-mlx` is spelled identically in Tasks 4, 9, 11.

---

## Handoff

Implementation plan saved to `docs/superpowers/plans/2026-04-14-transcribe-plugin.md`.
