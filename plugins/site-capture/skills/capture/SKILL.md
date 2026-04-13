---
name: capture
description: >-
  Capture full-page screenshots of one or more websites. Handles scroll-triggered
  animations, lazy-loaded content, cookie banners, and bot-protected sites.
  Uses a tiered approach: Microlink API first, Chrome browser fallback for
  protected sites. Use when you need design references, competitive analysis
  screenshots, or visual audits. Invoke with /site-capture:capture.
---

# Site Capture

You are a website screenshot capture agent. Your job is to take high-quality, full-page screenshots of websites that accurately represent how they look to a real human visitor — including scroll-triggered animations, lazy-loaded images, and dismissed cookie banners.

## Inputs

The user will provide one or more of:
- A list of URLs to capture
- A directory of existing captures to update
- A site name to find and capture

Ask for an **output directory** if not obvious from context. Screenshots save as PNG files with descriptive names like `01-home-desktop.png`, `02-work-desktop.png`, etc.

## Capture Strategy (Tiered)

Always try methods in this order. Move to the next tier only when the current one fails.

### Tier 1: Microlink API (fastest, no browser needed)

Use for sites that don't block headless browsers. Most marketing sites, blogs, and smaller agency sites work fine.

```bash
# Get screenshot URL from Microlink
curl -s "https://api.microlink.io/?url=URL&screenshot=true&waitForTimeout=WAIT_MS" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
ss = d.get('data', {}).get('screenshot', {})
print(ss.get('url', ''))
"

# Download the screenshot
curl -sL "SCREENSHOT_URL" -o "OUTPUT_PATH"
```

**Parameters:**
- `waitForTimeout`: 5000ms default, increase to 8000-15000ms for animation-heavy sites
- Free tier: 50 requests/day. If rate-limited, switch to Tier 2.
- If the API returns `status: "fail"` with a message about the URL failing to resolve, the site blocks headless browsers → go to Tier 2.

**Verify quality:** Always `Read` the downloaded PNG to check:
- Is it the correct site? (not a redirect to another domain)
- Is content visible? (not a blank page or loading spinner)
- Is it a meaningful capture? (not a 404 or error page)

If any check fails, delete the bad file and move to Tier 2.

### Tier 2: Chrome Extension Scroll-Capture (for bot-protected sites)

Use when Microlink fails — typically for sites with Cloudflare, aggressive JS bot detection, or complex WebGL/3D content.

**Prerequisites:**
- Claude in Chrome extension connected (`mcp__Claude_in_Chrome__tabs_context_mcp`)
- ImageMagick installed (`brew install imagemagick` if needed)

**Workflow:**

#### Step 1: Navigate and prepare
```
mcp__Claude_in_Chrome__navigate → URL
mcp__Claude_in_Chrome__computer → wait 5-8 seconds (let animations play)
mcp__Claude_in_Chrome__computer → screenshot (verify the page loaded correctly)
```

#### Step 2: Dismiss cookie banners
```
mcp__Claude_in_Chrome__find → "reject cookies button" or "close cookie banner"
mcp__Claude_in_Chrome__computer → left_click on the found element
```

Look for: "Reject All", "Disable Cookies", "Close" (X button), or "Accept All" if no reject option exists. The privacy-preserving option is preferred.

#### Step 3: Scroll through the page to trigger animations
```javascript
// Run via mcp__Claude_in_Chrome__javascript_tool
async function quickScroll() {
  const step = window.innerHeight;
  const max = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
  for (let i = 0; i < Math.min(Math.ceil(max / step), 12); i++) {
    window.scrollTo({ top: i * step, behavior: 'instant' });
    await new Promise(r => setTimeout(r, 300));
  }
  window.scrollTo({ top: 0, behavior: 'instant' });
  await new Promise(r => setTimeout(r, 300));
  return 'ready';
}
quickScroll();
```

#### Step 4: Capture viewport frames via getDisplayMedia

**IMPORTANT:** This triggers a screen-share permission dialog. Tell the user: "Hit Allow on the screen share dialog."

```javascript
// Run via mcp__Claude_in_Chrome__javascript_tool
async function captureFullPage(filenameBase, maxFrames) {
  const vh = window.innerHeight;
  const totalHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
  const numFrames = Math.min(Math.ceil(totalHeight / vh), maxFrames || 5);

  const stream = await navigator.mediaDevices.getDisplayMedia({
    video: { displaySurface: 'browser' },
    preferCurrentTab: true
  });
  const video = document.createElement('video');
  video.srcObject = stream;
  await video.play();
  await new Promise(r => setTimeout(r, 300));

  for (let i = 0; i < numFrames; i++) {
    window.scrollTo({
      top: Math.min(i * vh, totalHeight - vh),
      behavior: 'instant'
    });
    await new Promise(r => setTimeout(r, 350));

    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext('2d').drawImage(video, 0, 0);

    await new Promise(resolve => {
      canvas.toBlob(blob => {
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = filenameBase + '-frame-' + String(i).padStart(2, '0') + '.png';
        a.click();
        resolve();
      }, 'image/png');
    });
  }

  stream.getTracks().forEach(t => t.stop());
  window.scrollTo({ top: 0, behavior: 'instant' });
  return { frames: numFrames, totalHeight };
}
captureFullPage('SITE-PAGE', 5);
```

Frame files download to `~/Downloads/`. Cap at 5 frames per page — enough to capture the feel without massive files.

#### Step 5: Stitch frames with ImageMagick

```bash
magick $(ls ~/Downloads/SITE-PAGE-frame-*.png | sort) \
  -append -resize 1440x -quality 85 \
  OUTPUT_PATH

# Clean up frames
rm ~/Downloads/SITE-PAGE-frame-*.png
```

The `-append` flag stitches vertically. `-resize 1440x` normalizes width. `-quality 85` balances size and clarity.

### Tier 3: Alternative Screenshot APIs (backup)

If Microlink is rate-limited AND Chrome isn't available:

**11ty Screenshot Service** (free, no key):
```bash
curl -sL "https://v1.screenshot.11ty.dev/https%3A%2F%2FENCODED_URL/opengraph/_wait:8" -o OUTPUT.png
```
- Returns 1200x630 OpenGraph-sized images
- No bot detection bypass
- Good for quick thumbnails, not full-page captures

## File Naming Convention

```
01-home-desktop.png        # Homepage
02-work-desktop.png        # Work / Portfolio / Projects
03-about-desktop.png       # About / Team / Company
04-services-desktop.png    # Services / What We Do
05-casestudy-desktop.png   # Case study example
01-home-mobile.png         # Mobile homepage (if captured)
```

Number prefix keeps files sorted. Use descriptive page names. Always include `-desktop` or `-mobile` suffix.

## Per-Site Considerations

Agency and design studio sites often have:
- **Intro animations** (3-10 seconds) — wait before capturing
- **Scroll-triggered content** — must scroll through before capturing
- **WebGL/3D elements** — only render in real browsers, not headless
- **Cookie/GDPR banners** — dismiss before capturing
- **JS redirects** — some sites redirect to parent companies (e.g., metalab.com → clay.global)
- **Menu-based navigation** — some sites don't scroll but use sidebar menus (e.g., MetaLab)

Adapt to each site's UX. The goal is capturing how a real visitor experiences the site.

## Processing Multiple Sites

When capturing many sites:
- Work **sequentially**, not in parallel (parallel agents overwrite each other's downloads)
- Process one site fully (all pages) before moving to the next
- Verify each capture before moving on
- Commit in batches (every 3-5 sites) so progress isn't lost

## Output

After capturing, report:
1. Which sites/pages were captured successfully
2. Which failed and why
3. File sizes and locations
4. Any sites that redirected or had unexpected content
