#!/usr/bin/env node
// extract-via-playwright.mjs — Extract video+metadata from a JS-rendered page
// (primarily Threads, but works as a generic fallback).
//
// Stdin:   none
// Argv:    <url> <output-path>
// Stdout:  JSON: { "title": "...", "duration_seconds": 0, "video_path": "/abs/path.mp4" }
// Exit:    0 on success, non-zero on failure (with message on stderr)
//
// Strategy: Threads and Instagram serve DASH-style split streams — separate
// audio-only and video-only .mp4 URLs alongside (sometimes) a muxed URL. We
// capture every .mp4 the page requests, then use ffprobe to find the one
// that contains an audio stream, downloading candidates in ascending size
// (audio-only streams are typically the smallest). We write the first file
// that ffprobe confirms has audio to `video.mp4` in the output directory.

import { chromium } from 'playwright';
import { createWriteStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { spawnSync } from 'node:child_process';
import { unlinkSync, statSync } from 'node:fs';
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

function hasAudio(filePath) {
  const r = spawnSync(
    'ffprobe',
    [
      '-v',
      'error',
      '-select_streams',
      'a',
      '-show_entries',
      'stream=codec_type',
      '-of',
      'csv=p=0',
      filePath,
    ],
    { encoding: 'utf8' }
  );
  return r.stdout.trim() === 'audio';
}

async function downloadTo(url, headers, dest) {
  const resp = await fetch(url, { headers });
  if (!resp.ok) {
    throw new Error(`HTTP ${resp.status}`);
  }
  await pipeline(resp.body, createWriteStream(dest));
}

function stripPseudoHeaders(h) {
  const out = { ...h };
  delete out.host;
  delete out[':authority'];
  delete out[':method'];
  delete out[':path'];
  delete out[':scheme'];
  return out;
}

const ctx = await chromium.launchPersistentContext(PROFILE_DIR, {
  headless: true,
  args: ['--no-sandbox'],
});
const page = await ctx.newPage();

/** @type {Array<{url: string, headers: Record<string,string>, size: number}>} */
const candidates = [];
const seenUrls = new Set();

page.on('response', (resp) => {
  const u = resp.url();
  if (!/\.mp4(\?|$)/.test(u)) return;
  if (seenUrls.has(u)) return;
  seenUrls.add(u);
  const lenHeader = resp.headers()['content-length'];
  const size = lenHeader ? parseInt(lenHeader, 10) : 0;
  candidates.push({
    url: u,
    headers: resp.request().headers(),
    size: Number.isFinite(size) ? size : 0,
  });
});

try {
  await page.goto(URL_ARG, { waitUntil: 'domcontentloaded', timeout: 30_000 });
  await page.waitForSelector('video', { timeout: 20_000 });
} catch {
  try {
    await page.waitForTimeout(5_000);
    await page.waitForSelector('video', { timeout: 15_000 });
  } catch {
    await ctx.close();
    console.error(`ERROR: timed out waiting for <video>. URL: ${URL_ARG}`);
    process.exit(3);
  }
}

// Force the player to start loading all segments (including audio on DASH streams).
// We mute first so muted autoplay policies don't reject the play() call, then
// let the video run long enough to trigger audio segment requests.
try {
  await page.evaluate(async () => {
    const v = document.querySelector('video');
    if (!v) return;
    v.muted = true;
    try {
      await v.play();
    } catch {
      // Ignore — we just want the play attempt to trigger buffering.
    }
  });
} catch {
  // Ignore; we still continue and check what we got.
}

// Give the page time to request audio segments.
await page.waitForTimeout(6_000);

const title = await page.title().catch(() => 'Unknown');
await ctx.close();

if (candidates.length === 0) {
  console.error('ERROR: no .mp4 URLs captured from this page.');
  process.exit(4);
}

// Sort candidates by size ascending — audio-only streams are typically the smallest.
candidates.sort((a, b) => a.size - b.size);

const tryPath = path.join(OUT_DIR, '_candidate.mp4');
const outPath = path.join(OUT_DIR, 'video.mp4');
let success = false;

for (const cand of candidates) {
  try {
    await downloadTo(cand.url, stripPseudoHeaders(cand.headers), tryPath);
    if (hasAudio(tryPath)) {
      // Move candidate to final output path.
      const renameSync = (await import('node:fs')).renameSync;
      try {
        unlinkSync(outPath);
      } catch {}
      renameSync(tryPath, outPath);
      success = true;
      break;
    }
  } catch (err) {
    // Try the next candidate.
    try {
      unlinkSync(tryPath);
    } catch {}
    continue;
  }
  try {
    unlinkSync(tryPath);
  } catch {}
}

if (!success) {
  console.error(
    `ERROR: none of the ${candidates.length} .mp4 candidates contained an audio stream.`
  );
  process.exit(5);
}

let bytes = 0;
try {
  bytes = statSync(outPath).size;
} catch {}

process.stdout.write(
  JSON.stringify({
    title,
    duration_seconds: 0,
    video_path: outPath,
    bytes,
  }) + '\n'
);
