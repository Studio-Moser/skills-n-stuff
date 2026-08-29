# Shelby Stack Contract

This is the default architecture for Studio Moser Mac apps. Adapt names to the
product, but keep the ownership boundaries unless the repository proves a better
existing pattern.

## Ownership

| Layer | Owns | Does not own |
| --- | --- | --- |
| Tauri shell | system window, lifecycle, WebView, capabilities, IPC registration, packaging | product state or decorative fake chrome |
| SvelteKit renderer | layout, local interaction, semantic components, and presentation state | unrestricted filesystem/process access or durable truth |
| Rust runtime | durable product state, validated commands, privileged work, and local services | Svelte presentation or platform-specific view code |
| Swift shim | Foundation Models, App Intents, or another Apple-only API unavailable through a clean Rust/Tauri path | the primary UI, general business logic, or a parallel app architecture |

Use Tauri 2, SvelteKit 5, and Rust as the starting point. Keep Swift in a narrow
Apple integration folder; do not introduce SwiftUI for the product interface.

## Window and renderer seam

- Use a real Tauri system window with native traffic lights and resizable/full-screen behavior.
- Overlay content into the titlebar only when the composition needs it. Mark only empty chrome as draggable and exclude every control.
- Reserve traffic-light space through one shell token or layout rule, never per screen.
- Keep sidebar, content, and inspector as independently scrollable/resizable panes.
- Centralize the distinction between the macOS native shell and browser fixture instead of scattering environment checks through components.
- Treat browser mode as an explicit fixture runtime, not a degraded accidental fallback.

## Capability bridge

Expose typed, task-level commands such as `choose_export_folder`, `save_document`,
or `show_item_in_finder`. Avoid generic filesystem, shell, SQL, or arbitrary invoke
escape hatches.

For every command:

- validate inputs in Rust at the trust boundary;
- return an explicit serializable result or user-safe error;
- keep secrets and credentials outside the renderer;
- emit typed events when the product has streaming or durable background work;
- make cancellation and late-result handling explicit when the operation can outlive its initiating view;
- grant only the Tauri capabilities required by the named window.

When Rust owns durable truth, the renderer projects it into presentation state. It
does not invent a second durable state machine that can disagree with the backend.

## Browser fixture contract

The plain-browser build must render the same Svelte components and exercise the
same presentation-state transitions and data contracts as the Tauri app. Supply
deterministic fixtures for:

- app metadata and platform capabilities;
- representative applicable operational states, with deliberate omissions recorded;
- long labels, large collections, and boundary-size content.

If the product has streaming, tool calls, background work, or cancellation, add
fixtures for those lifecycles and late-result behavior. Otherwise omit them.

Browser fixtures make visual and interaction testing fast. They do not prove
native window chrome, drag regions, Tauri permissions, Rust commands, platform
materials, App Intents, or Apple-only integrations.

## Native-backed seams

Prefer Tauri or macOS implementations for file panels, notifications, application
menus, global shortcuts, context menus, clipboard, drag/drop, permissions, and
system appearance when browser behavior is observably wrong. Keep the adapter
narrow and expose semantic operations back to Svelte.

## Packaging contract

Use the repository's Mac build command rather than bare framework defaults when it
assembles extensions or native artifacts. Test the final `.app` when signing,
capabilities, entitlements, extensions, or bundled resources change.
