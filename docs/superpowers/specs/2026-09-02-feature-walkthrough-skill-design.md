# Feature Walkthrough Skill Design

## Goal

Add a reusable `pm:feature-walkthrough` skill that turns existing browser coverage into a human-readable feature demonstration when a developer asks to see completed work.

## Invocation

The skill applies to requests such as “show me the feature,” “record a walkthrough,” “let me see it working,” or “give me a demo video.” It remains available directly and through `pm:dev-task`.

`pm:dev-task` invokes it only after an explicit request for visual proof. A walkthrough supplements the approved Testing Seam; it never replaces test, build, review, or verification gates.

## Device Choice

If the request does not specify a target, ask one concise question: **Desktop, mobile, or both?**

- Desktop uses a real 1920×1080 viewport and 1920×1080 video.
- Mobile uses an exact 360×800 viewport and 360×800 video.
- A user-specified device or size overrides these defaults.
- “Both” produces separate desktop and mobile files. Each file’s encoded dimensions match its browser viewport exactly, with no scaling or letterboxing.

## Recording Workflow

1. Inspect the repository instructions, Playwright configuration, existing feature spec, fixtures, authentication, and cleanup behavior.
2. Confirm that the selected environment and data cannot create an unauthorized charge, order, message, or other external side effect.
3. Run the existing feature test before recording. Stop if it fails.
4. Reuse a project-owned walkthrough spec when one exists. Otherwise create temporary recording-only configuration and presentation steps without changing the normal test defaults.
5. Record one deterministic flow per requested device with one worker, a list reporter, no automatically opened HTML report, approximately 350 ms action delay, and deliberate holds on important states.
6. Convert Playwright’s native video to H.264 MP4 (`yuv420p`, fast-start) when `ffmpeg` is available. Preserve WebM and report the limitation when conversion is unavailable.
7. Decode-check every final file, report its path, browser, viewport, video dimensions, duration, and test result, then remove only temporary files created for the recording. Preserve pre-existing worktree changes and artifacts.

## Presentation Contract

The plugin owns a Playwright overlay helper so recordings use one visual language rather than ad hoc CSS.

- Content: `STEP N` eyebrow plus one short present-tense explanation.
- Position: horizontally centered, 48 px above the bottom edge, with a 40 px viewport gutter.
- Surface: charcoal `rgba(24, 27, 29, 0.94)`, white text, one-pixel translucent white border, 10 px radius, and a soft shadow.
- Type: system sans-serif, 600 weight, responsive 16–22 px message text; the eyebrow is smaller and uppercase.
- Motion: 180 ms fade-and-rise entrance and exit.
- Timing: two-second default hold; longer only when the screen requires reading.
- Behavior: maximum z-index and `pointer-events: none`; remove the overlay before the next interaction so it never changes application behavior.

The presentation spec starts from a recognizable state, shows the action and resulting state, and ends on the feature outcome. It omits diagnostic assertions that make the demonstration confusing while retaining enough assertions to fail when the demonstrated outcome is absent.

## Privacy and Safety

- Use authorized QA accounts and synthetic data only.
- Never expose passwords, tokens, payment credentials, customer data, production-only URLs, or unrelated browser content.
- Do not perform a charge, place an order, send a message, or mutate external production state without explicit authorization.
- Stop before recording when those guarantees cannot be established.

## Artifacts

Use the destination requested by the user. Otherwise save under:

`output/playwright/walkthroughs/<feature>/<device>.mp4`

Generated recordings remain untracked unless the user explicitly asks to commit them. The skill never overwrites an existing artifact silently.

## Repository Changes

- Add `plugins/pm/skills/feature-walkthrough/SKILL.md` for discovery and execution guidance.
- Add `plugins/pm/templates/playwright-walkthrough-overlay.ts` as the canonical overlay helper.
- Update `plugins/pm/skills/dev-task/SKILL.md` to route explicit demonstration requests.
- Extend PM contract tests to protect device prompting, dimensions, presentation behavior, safety, and the `dev-task` route.
- Update the PM README skill inventory and marketplace/plugin patch versions.

## Non-Goals

- Replacing fast E2E tests with presentation tests.
- Automatically recording every completed task.
- Adding narration, post-production editing, or a new video dependency.
- Committing generated videos by default.
