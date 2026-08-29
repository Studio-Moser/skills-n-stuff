# Verification Contract

## Iterate on one render tree

Run the Svelte interface in a plain browser with deterministic fixtures while the
same development server feeds the Tauri WebView. Use browser tooling for fast DOM,
layout, state, accessibility, and screenshot checks. Do not maintain a separate
prototype that can drift from the app.

## Browser proof

Verify the applicable set below and record why any item does not exist for this
surface:

- minimum, typical, and wide viewport sizes;
- operational-state fixtures such as populated, empty, loading, error, or permission when the product can enter them, plus long-label and boundary-data fixtures;
- light and dark appearance;
- keyboard-only navigation, focus order, focus visibility, and accessible names/states;
- pane scrolling and pointer/keyboard resizing;
- Reduce Motion behavior and static fallbacks;
- component tests, type checks, production build, and browser end-to-end tests defined by the repository.

Use screenshots to judge hierarchy, density, alignment, clipping, overflow, and
whether the result looks like a webpage. Screenshots do not prove interaction.

## Native-shell proof

In the running Tauri app verify:

- native traffic lights, key/inactive appearance, resizing, full screen, and minimum size;
- draggable empty titlebar regions and non-draggable controls;
- menus, keyboard equivalents, disabled items, focus transfer, and focus restoration;
- native dialogs, context menus, permissions, notifications, clipboard, and drag/drop used by the product;
- WebView selection, scrolling, overscroll, and text-input behavior;
- system accent, Increase Contrast, Reduce Transparency, and Reduce Motion;
- applicable Rust commands, error presentation, and capability denials;
- typed event streaming, cancellation, and late-result handling only when the product implements long-running or streamed work.

When packaging, signing, entitlements, extensions, or bundled resources change,
repeat the relevant checks against the built `.app`, not only the dev runner.

## Independent design critique

For a high-value screen, give a fresh critic only:

1. the brief and concrete reference;
2. the rendered artifact at the required sizes and states;
3. the **Mac App Done Rubric** from `Mac Interface Contract.md`.

Require pass/fail per item and a specific fix for each failure. Reject vague advice.
Apply material fixes and re-run only the affected checks plus the full rubric at the
end. Stop at zero material failures or the agreed round cap.

## Evidence report

Report separately:

- browser checks completed and their results;
- native-shell checks completed and their results;
- checks not run and why;
- known platform seams that remain unproven.

Never summarize “looks native” as proof.
