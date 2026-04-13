# Site Capture

Capture full-page screenshots of websites with scroll-triggered animation support. Built for competitive design analysis, visual audits, and design reference collection.

## Why

Most websites today use scroll-triggered animations, lazy loading, and bot detection — which means naive screenshot tools produce blank pages. This plugin handles the complexity:

- **Scroll-triggered content** — scrolls through the page to fire all animations before capturing
- **Bot-protected sites** — falls back from API to real Chrome browser when sites block headless browsers
- **Cookie banners** — finds and dismisses consent dialogs before capturing
- **Full-page stitching** — captures each viewport and stitches into a single tall image via ImageMagick
- **WebGL/3D content** — captures via real browser rendering, not DOM serialization

## Installation

```bash
/plugin install site-capture@studio-moser
```

Requires:
- ImageMagick (`brew install imagemagick`) — for frame stitching
- Claude in Chrome extension — for bot-protected sites (optional, falls back gracefully)

## Skills

### `/site-capture:capture`

Capture screenshots of one or more websites.

```
# Capture a single site
/site-capture:capture https://clay.global

# Capture multiple sites to a directory
/site-capture:capture clay.global instrument.com work.co --output design/_refs

# Recapture a specific page
/site-capture:capture https://www.instrument.com/work --output design/_refs/instrument.com/screenshots/03-work-desktop.png
```

Uses a tiered approach:
1. **Microlink API** (fast, 50 free/day) — works for most sites
2. **Chrome + getDisplayMedia** (slower, needs user Allow) — for bot-protected sites
3. **11ty Screenshot Service** (fallback) — for quick thumbnails

### `/site-capture:audit`

Audit existing screenshots for quality issues.

```
# Audit all screenshots in a directory
/site-capture:audit design/_refs

# Audit a specific site's screenshots
/site-capture:audit design/_refs/clay.global/screenshots
```

Checks every image for:
- Wrong company content (from parallel capture collisions)
- Blank sections (unfired scroll animations)
- Cookie banners covering content
- Error/404 pages
- Loading states

## File Naming

```
01-home-desktop.png
02-work-desktop.png
03-about-desktop.png
04-services-desktop.png
05-casestudy-desktop.png
01-home-mobile.png
```

## Tips

- **Sequential, not parallel** — capture one site at a time to avoid file collisions
- **Verify as you go** — check each capture before moving to the next site
- **Agency sites are weird** — some use sidebar menus instead of scrolling, some have 10-second intro animations, some redirect to parent companies. Adapt to each site.
- **5 frames max per page** — enough to capture the feel without 50MB files

## License

MIT
