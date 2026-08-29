---
name: mac-app-design
description: >-
  Use when designing, building, or reviewing the interface of a native-feeling
  macOS desktop app implemented with Tauri, Svelte, HTML/CSS, Rust, or a WebView;
  especially when it resembles a website, dashboard, enlarged mobile app, or
  imitation Mac window. Not for Windows, Linux, iOS, Android, or SwiftUI-first UI.
---

# Mac App Design

Design a Mac product, not a webpage inside a desktop frame. Use the system for
Mac behavior, a local web renderer for the product interface, Rust for durable
application logic, and narrow native shims only for capabilities the shell cannot
provide cleanly.

## Establish the design contract

Before drawing or editing, inspect the product, existing components, tokens, and
runtime boundary. Write a short contract that names:

1. the user's primary job and the one action that should dominate;
2. the window composition: toolbar, sidebar, content, inspector, and transient UI;
3. the command model: menus, shortcuts, selection, undo, drag/drop, and dialogs;
4. the visual direction and concrete reference, including what to borrow and avoid;
5. the applicable states and any justified omissions: operational states, control
   states, key/inactive window, appearance, and accessibility preferences.

Do not proceed from adjectives such as “clean” or “native.” Resolve them into
observable structure, behavior, metrics, and states. Read
[Prompt Contract](references/Prompt%20Contract.md) when shaping a new screen or
brief.

## Use the Studio Moser desktop boundary

Default to Tauri 2 + SvelteKit 5 + Rust. The WebView owns presentation; Rust owns
durable state, privileged work, and capability validation; Tauri owns the window
and IPC; Swift is limited to narrow Apple-only shims. Keep the same Svelte render
tree runnable in a plain browser with fixtures for fast iteration.

Read [Shelby Stack Contract](references/Shelby%20Stack%20Contract.md) before
changing shell, bridge, runtime, or native integration.

## Build a semantic Mac interface kit

Compose screens from roles—window chrome, toolbar, sidebar, split view, inspector,
list, field, menu, popover, dialog, empty state—not one-off styled elements.
Component context determines density and treatment. Keep product identity in the
content; keep routine chrome calm, compact, and system-aware.

Read [Mac Interface Contract](references/Mac%20Interface%20Contract.md) before
authoring or critiquing a surface. Apply its **Mac App Done Rubric** to every
meaningful screen.

## Prove both surfaces

Use the browser fixture for DOM inspection, responsive states, accessibility, and
fast visual iteration. Use the running Tauri app for traffic lights, drag regions,
window resizing, native menus and shortcuts, focus transfer, dialogs, permissions,
materials, and inactive-window behavior. A browser screenshot cannot prove a Mac
app.

Read [Verification Contract](references/Verification%20Contract.md) for the build
and critique loop. Read [Glaze Harness Contract](references/Glaze%20Harness%20Contract.md)
when creating or repairing a project's agent/build harness. Read
[Research Basis](references/Research%20Basis.md) only when provenance or the Glaze
comparison matters.
