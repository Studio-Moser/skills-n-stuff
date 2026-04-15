#!/usr/bin/env node
// extract-via-playwright.mjs — Extract video+metadata from a JS-rendered page
// (primarily Threads, but works as a generic fallback).
//
// Stdin:   none
// Argv:    <url> <output-path>
// Stdout:  JSON: { "title": "...", "duration_seconds": 0, "video_path": "/abs/path.mp4" }
// Exit:    0 on success, non-zero on failure (with message on stderr)
//
// Strategy: Pages like Threads render the target post alongside related/
// suggested videos, so naive ".mp4 URL capture" can pick a neighbor's clip.
// We anchor on the first <video> element's currentSrc (that is the target
// post's stream), then:
//   1. Try the currentSrc directly. If ffprobe finds an audio stream, use it.
//   2. Otherwise, Threads is using DASH-style split streams. Match captured
//      .mp4 URLs by shared "asset id" prefix with currentSrc, and pick the
//      smallest one that ffprobe confirms carries audio.
//   3. As a last resort, try the smallest captured .mp4 regardless of prefix.

import { chromium } from 'playwright';
import { createWriteStream, unlinkSync, statSync, renameSync } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { spawnSync } from 'node:child_process';
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
      '-v', 'error',
      '-select_streams', 'a',
      '-show_entries', 'stream=codec_type',
      '-of', 'csv=p=0',
      filePath,
    ],
    { encoding: 'utf8' }
  );
  return r.stdout.trim() === 'audio';
}

async function downloadTo(url, headers, dest) {
  const resp = await fetch(url, { headers });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
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

// Extract an "asset id" fingerprint from a CDN URL so we can group segments
// that belong to the same video. Threads/Instagram URLs look like:
//   https://scontent-<dc>.cdninstagram.com/o1/v/t2/f2/m86/AQM...?<query>
// The first 20 chars of the filename segment are a reliable grouping key.
function assetIdOf(url) {
  try {
    const u = new URL(url);
    const last = u.pathname.split('/').pop() || '';
    return last.slice(0, 20);
  } catch {
    return '';
  }
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

// Coax the target player into loading audio segments. Muted autoplay gets
// past the browser gesture policy; unmuting afterwards persuades the player
// to actually fetch the audio track on DASH streams.
try {
  await page.evaluate(async () => {
    const v = document.querySelector('video');
    if (!v) return;
    v.scrollIntoView({ block: 'center' });
    v.muted = true;
    try { await v.play(); } catch {}
    v.muted = false;
    try { await v.play(); } catch {}
  });
} catch {}

await page.waitForTimeout(8_000);

// currentSrc identifies the target post's stream.
let currentSrc = null;
try {
  currentSrc = await page.$eval('video', (v) => v.currentSrc || v.src);
} catch {}

const title = await page.title().catch(() => 'Unknown');
await ctx.close();

if (!currentSrc && candidates.length === 0) {
  console.error('ERROR: no video URL found on page.');
  process.exit(4);
}

const outPath = path.join(OUT_DIR, 'video.mp4');
const tryPath = path.join(OUT_DIR, '_candidate.mp4');
let success = false;

// Step 1: try currentSrc directly.
async function tryCandidate(url, headers) {
  try {
    await downloadTo(url, stripPseudoHeaders(headers), tryPath);
    if (hasAudio(tryPath)) {
      try { unlinkSync(outPath); } catch {}
      renameSync(tryPath, outPath);
      return true;
    }
  } catch {}
  try { unlinkSync(tryPath); } catch {}
  return false;
}

if (currentSrc && /\.mp4(\?|$)/.test(currentSrc)) {
  const match = candidates.find((c) => c.url === currentSrc);
  const headers = match ? match.headers : {};
  success = await tryCandidate(currentSrc, headers);
}

// Step 2: candidates matching currentSrc's asset id, smallest first.
if (!success && currentSrc) {
  const targetId = assetIdOf(currentSrc);
  if (targetId) {
    const matching = candidates
      .filter((c) => assetIdOf(c.url) === targetId && c.url !== currentSrc)
      .sort((a, b) => a.size - b.size);
    for (const cand of matching) {
      success = await tryCandidate(cand.url, cand.headers);
      if (success) break;
    }
  }
}

// Step 3: last resort — any captured mp4 with audio, smallest first.
if (!success) {
  const fallback = [...candidates].sort((a, b) => a.size - b.size);
  for (const cand of fallback) {
    success = await tryCandidate(cand.url, cand.headers);
    if (success) break;
  }
}

if (!success) {
  console.error(
    `ERROR: none of the ${candidates.length} .mp4 candidates contained an audio stream for the target post.`
  );
  process.exit(5);
}

let bytes = 0;
try { bytes = statSync(outPath).size; } catch {}

process.stdout.write(
  JSON.stringify({
    title,
    duration_seconds: 0,
    video_path: outPath,
    bytes,
  }) + '\n'
);
