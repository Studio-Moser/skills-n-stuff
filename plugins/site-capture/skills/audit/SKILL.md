---
name: audit
description: >-
  Audit existing screenshot captures for quality issues. Checks every PNG file
  in a directory for wrong-company content, blank sections, cookie banners,
  error pages, and other problems. Reports what needs recapturing. Use when
  screenshots look wrong or after a batch capture to verify quality. Invoke
  with /site-capture:audit.
---

# Screenshot Audit

You are a screenshot quality auditor. Your job is to visually inspect every screenshot in a directory and flag issues.

## Process

### Step 1: Discover screenshots

Find all PNG/JPEG files in the target directory:

```bash
find TARGET_DIR -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" | sort
```

### Step 2: Inspect each file

Use the `Read` tool to visually inspect each image file. For every screenshot, check:

1. **Correct company?** — Does the screenshot show the site it's supposed to show? Check logos, domain names, branding. This is the most common issue when parallel capture agents overwrite each other's files.

2. **Content visible?** — Is there actual page content, or are there large blank/white areas where scroll-triggered animations didn't fire?

3. **Cookie banner?** — Is a cookie consent banner covering significant content?

4. **Error page?** — Is this a 404, 500, or other error page?

5. **Loading state?** — Is the page still loading (spinners, skeleton screens, placeholder content)?

6. **Redirect content?** — Did the site redirect to a different domain? (Common with acquired agencies — e.g., metalab.com → clay.global, hugeinc.com → clay.global)

### Step 3: Report findings

Output a table with one row per file:

```
| File | Status | Issue |
|------|--------|-------|
| artefact/01-home-desktop.png | OK | Correct Artefact homepage |
| artefact/02-work-desktop.png | WRONG_COMPANY | Shows Clay Global, not Artefact |
| clay/01-home-desktop.png | BLANK_SECTIONS | Nav visible but content area is white |
| ideo/03-about-desktop.png | COOKIE_BANNER | Banner covers bottom 20% of page |
```

Status codes:
- **OK** — Screenshot looks good
- **WRONG_COMPANY** — Shows a different company's site
- **BLANK_SECTIONS** — Large empty areas where content should be
- **COOKIE_BANNER** — Cookie notice covering content
- **ERROR_PAGE** — 404 or error page
- **LOADING** — Page caught in loading state
- **REDIRECT** — Site redirected to different domain
- **LOW_QUALITY** — Image is too small, blurry, or cropped wrong

### Step 4: Recommend actions

After the audit, provide:
1. Total files audited and pass rate
2. List of files that need recapturing, grouped by site
3. Recommended capture method per site (Microlink vs Chrome)
4. Any sites that may have been acquired/merged (redirect patterns)

## Tips

- File sizes can hint at issues: very small PNGs (< 10KB) are often error pages or blank captures
- Multiple files with identical sizes in different directories suggests they were captured from the same page (wrong-company issue from parallel capture)
- Check the directory name against the content — `metalab.com/screenshots/01-home-desktop.png` should show MetaLab, not Clay
- Some sites legitimately redirect (metalab.com IS now clay.global) — note this as context, not necessarily an error
