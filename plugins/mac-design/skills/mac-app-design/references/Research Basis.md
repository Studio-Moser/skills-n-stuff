# Research Basis

This skill combines two evidence sources. It uses transferable architecture and
interface patterns, not proprietary implementation material.

## Glaze observation

Static inspection of an installed Glaze app showed a hybrid native architecture:

- a small signed arm64 Swift/AppKit launcher;
- a shared Glaze runtime using AppKit/SwiftUI and the system WebKit/WKWebView;
- a local React renderer with semantic component and IPC layers;
- a Node runtime for application logic;
- native-backed menus, selects, tooltips, focus state, accessibility preferences,
  window behavior, and system scrollbar handling;
- a managed build/verify/package harness and dynamically synchronized agent guidance.

The installed files did not expose the original Glaze system prompt or the prompt
that generated the inspected app. This skill therefore does not claim to reproduce
or copy those prompts. It reconstructs the observable quality system: strong shell
defaults, semantic components, narrow capability boundaries, explicit state
contracts, and verification in the real desktop host.

## Shelby implementation direction

The Shelby App repository at commit `d070e3a6dae039a2ea9f99a241eb46670ab25ecc`
establishes Studio Moser's desktop boundary:

- Tauri 2 system shell and packaging;
- SvelteKit 5 renderer shared by browser fixtures and the native WebView;
- Rust commands, durable runtime events, cancellation, local services, and data;
- narrow Swift shims for Foundation Models and App Intents, with no SwiftUI UI;
- a native-overlay titlebar, resizable sidebar and inspector, compact Mac control
  metrics, semantic tokens, keyboard-resizable splitters, dark appearance, and
  Reduce Motion handling;
- a full gate spanning component tests, type checks, Rust tests, production build,
  and browser end-to-end tests.

This skill makes that boundary the default for future Studio Moser macOS apps while
keeping product-specific brand and domain decisions outside the shared prompt.
