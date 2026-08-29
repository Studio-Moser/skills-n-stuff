# mac-design

A Claude Code plugin for designing **native-feeling macOS apps** in Studio Moser's
Tauri 2 + SvelteKit 5 + Rust desktop stack.

The WebView is an implementation detail, not permission to ship a website in a
window. This plugin supplies the Mac product, interface-kit, shell/bridge, agent
harness, and verification contracts that keep generated apps compact,
keyboard-first, resizable, accessible, and credible beside native Mac software.

## What's inside

- **`mac-app-design`** skill — a prompt contract, semantic Mac UI kit, compact
  desktop metrics, Tauri/Svelte/Rust ownership model, narrow native capability
  bridge, Glaze-inspired project harness, and a packaged-app done rubric.

The skill is intentionally macOS-only and is not a SwiftUI UI guide. Other
operating systems should use separate platform design skills.

## Install

```
/plugin marketplace add Studio-Moser/skills-n-stuff
/plugin install mac-design@studio-moser
```

The skill triggers on requests for a Mac app, macOS desktop UI, Tauri/WebView Mac
surface, toolbar/sidebar/inspector design, or “make this feel native.” Invoke it
explicitly with `/mac-design:mac-app-design` when needed.

Its Glaze guidance is clean-room: it reproduces the observable harness and design
discipline of an installed Glaze app, not Glaze's unavailable private prompt or
proprietary source.
