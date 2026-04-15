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
