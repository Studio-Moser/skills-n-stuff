# mac-design

A Claude Code plugin for designing **native-feeling macOS app UI** in the Liquid
Glass era (macOS 26 "Tahoe").

AI design tools don't have enough context on what a *real* Mac app looks like, so
their output drifts toward web dashboards and iOS ports. This plugin supplies that
missing context as a skill that auto-triggers when you're designing a Mac window,
desktop app, SwiftUI/AppKit screen, or an HTML/CSS Mac-app mockup.

## What's inside

- **`mac-native-liquid-glass`** skill — the two-layer glass model, window /
  toolbar / sidebar / menu-bar conventions, Mac metrics and color, a SwiftUI API
  map, and a 10-point anti-slop checklist. Works for SwiftUI/AppKit *and* HTML/CSS
  mockups. It layers a project's own brand (`DESIGN.md`) onto the content layer
  while keeping the chrome system-native.

## Install

```
/plugin marketplace add Studio-Moser/skills-n-stuff
/plugin install mac-design@studio-moser
```

The skill triggers on phrases like "mac app", "Liquid Glass", "toolbar",
"sidebar", "make this feel native" — or invoke it explicitly.

Full illustrated guide, reference screenshots, and inspiration library live at
`Shelby-Docs/design/mac-ui-best-practices/` in the Studio Moser workspace.
