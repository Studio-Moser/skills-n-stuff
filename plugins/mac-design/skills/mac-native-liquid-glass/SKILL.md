---
name: mac-native-liquid-glass
description: >-
  Use when designing, building, or reviewing native macOS app UI — a Mac window,
  desktop app, SwiftUI/AppKit screen, or an HTML/CSS mockup of a Mac app. Triggers:
  "mac app", "macOS app", "native Mac", "Mac window", "Liquid Glass", "desktop app
  UI", "macOS toolbar/sidebar", "menu bar app", "make this feel native". Covers the
  two-layer glass model (macOS 26 "Tahoe"), window/toolbar/sidebar/menu-bar
  conventions, Mac metrics and color, a SwiftUI API map, and an anti-slop checklist.
  Use especially when generated "Mac" UI looks like a web dashboard or an iOS port —
  this skill closes that gap. NOT for iOS/iPadOS/watchOS/visionOS or web-only design.
---

# Mac-native design — the Liquid Glass era

AI design tools don't have enough context on what a *real* Mac app looks like, so
their output drifts toward web dashboards and iOS ports. This skill is that missing
context. Sourced from Apple's HIG (macOS 26 "Tahoe"), Apple's "Adopting Liquid
Glass" guide, and community Mac-native references (see `references/`).

## 1. The core mental model — two layers

Liquid Glass splits every interface into exactly two layers:

1. **Content layer** — documents, lists, media, canvases. Opaque or standard
   materials. What the app is *about*.
2. **Floating glass layer** — controls and navigation (toolbars, sidebars, tab
   bars, menus, popovers) that float above content on the Liquid Glass material.

Rules that follow:
- **Never put glass in the content layer.** Glass-on-glass destroys hierarchy.
  (Exception: a knob/toggle takes on glass *during* interaction.)
- **Use glass sparingly even in chrome** — standard components get it free; custom
  glass is reserved for the few most important functional elements.
- **Two variants:** `regular` (blurs + preserves legibility; the default, required
  wherever text sits) and `clear` (highly translucent, **only** over rich media;
  add ~35% dark dimming if the media is bright).
- **Scroll-edge effects replace hard dividers** — content fades under toolbars;
  don't paint custom opaque toolbar/sidebar backgrounds.
- Multiple custom glass elements share a `GlassEffectContainer`.

## 2. What makes it feel like a *Mac* app

- **The menu bar is the complete command surface** — every action appears in a
  menu; toolbars/buttons are shortcuts into that set. Every toolbar item has a
  menu-bar equivalent.
- **Keyboard-first** — standard shortcuts (⌘S/F/W/,) behave as expected; every
  primary action has one.
- **Windows are the user's** — freely resizable/movable/multi-window/full-screen;
  the system remembers placement; **never custom window chrome**.
- **Window states are visually distinct** — the *key* window has colored traffic
  lights; inactive windows show gray ones and lose vibrancy. (AI UI always misses
  this.)
- **Respect the user's settings** — system accent color, sidebar icon size, Reduce
  Transparency / Increase Contrast / Reduce Motion.
- **High density, calm presentation** — more content, fewer nested levels than iOS,
  grouped with whitespace not crammed.

## 3. Chrome conventions (the parts AI gets wrong)

- **Toolbar:** three fixed zones — *leading* (back, sidebar toggle, title),
  *center* (customizable common actions, collapse to system overflow), *trailing*
  (essentials + search + one `.prominent` primary action, tinted). Bare SF Symbols,
  **no bezels, no custom backgrounds, no tinted item colors**, ~3 groups.
- **Sidebar:** floats in the glass layer; extend content beneath it
  (`backgroundExtensionEffect()`). Max two hierarchy levels (deeper → three-pane
  `NavigationSplitView`). Icons tinted with the user's accent. ~225–275pt min,
  ~350–400pt max, user-resizable, hideable (never hidden by default).
- **Menu bar:** canonical order  ▸ App ▸ File ▸ Edit ▸ Format ▸ View ▸ *app* ▸
  Window ▸ Help. Menus are stable — **disable** unavailable items, never hide.
  Menu-bar *extras* show a menu (not a popover) and use a template symbol; never
  rely on the extra's presence.
- **Window:** rounder Tahoe corners; nested controls adopt **concentric** radii.
  Titles concise (<15 chars, describe content not app name). Avoid bottom bars.

## 4. Metrics & color

- **Type:** SF Pro; **13pt body** default (11pt min). Title-Style Capitalization
  for section headers, not ALL CAPS.
- **Grid:** 8pt spacing; compact **22–28pt** control heights in toolbars.
- **Layout:** edge-to-edge content; chrome floats above (no reserved opaque strip);
  windows resize continuously — hide inspectors first, collapse last.
- **Color:** chrome stays nearly monochrome; color lives in content. Use semantic
  system colors (they adapt to light/dark/vibrancy/contrast). Dark mode is
  elevation + saturation adjustment, **not inversion**.

## 5. Anti-slop checklist — run against every generated Mac surface

1. Glass everywhere (glass cards / content panels / glass-on-glass).
2. Custom window chrome (recreated traffic lights, custom title bars).
3. Web-style toolbars (bordered buttons, icon+text mix, colored fills, opaque strip
   + bottom border).
4. iOS metrics (17pt body, 44pt full-width buttons, tab bar where a sidebar belongs).
5. Web metrics (16px body, heavy drop shadows vs materials + hairlines, big rounded
   CTAs).
6. No menu bar / no shortcuts (pointer-only isn't a Mac app).
7. Missing window-state design (no key/inactive differentiation, fixed-size /
   single-window assumptions).
8. Legibility failures on glass (clear glass over bright content undimmed; tinted
   items over colorful content; ALL-CAPS headers).
9. Ignoring user settings (hardcoded accent, fixed sidebar size, breaks under Reduce
   Transparency).
10. Over-modality (a sheet/dialog for what an inspector/popover/window handles inline).

## 6. SwiftUI quick map (the "how")

| Concern | API |
|---|---|
| Glass on a custom view | `.glassEffect(.regular / .clear, in: shape)` |
| Multiple glass elements morphing | `GlassEffectContainer` |
| Toolbar chrome | `.toolbar { ToolbarItemGroup … }`, `.prominent`, fixed spacers |
| Content under chrome | `scrollEdgeEffectStyle(_:for:)` |
| Content under sidebar | `.backgroundExtensionEffect()` |
| Sidebar / three-pane | `NavigationSplitView` (AppKit `NSSplitViewController`) |
| Concentric corners | container-relative rounded shapes |
| Materials in content | `Material` (`.regular`/`.thick`…), AppKit `NSVisualEffectView` |

Build with the latest SDK and *look* — standard components adopt the new design
automatically; most "adoption" is deleting custom backgrounds that fight it.

## 7. Applying to a brand

The rule that keeps brand and native feel from fighting: **brand lives in the
content layer** (color fields, hero imagery, illustration, data viz); **chrome
stays system** (traffic lights, sidebar behavior, settings anatomy, menu-bar
menus). The apps that feel both branded *and* native — CleanMyMac, Setapp,
Pixelmator — all obey this. If a project has its own brand contract / `DESIGN.md`,
layer its palette and type onto the content layer and let this skill govern the
chrome. See `references/` for the full illustrated guide and sourcing.

## 8. Verify with the gauntlet (high-value surfaces)

Don't ship a Mac surface on your own say-so — you're the worst judge of what you
just drew. For a hero screen, a template, or anything reused, run the
`design-critic-loop` skill (install `design-critic-loop@studio-moser`) and pass
**§5 (the anti-slop checklist) + §1 (the two-layer glass rules)** as the *system*
rubric and §3–4 conventions as the *craft* bar. Independent critics catch the
web-dashboard / iOS-port drift that self-review rationalizes away. Skip it for
routine tweaks — the loop is token-expensive.
