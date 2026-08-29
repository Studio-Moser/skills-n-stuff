# Prompt Contract

Use this contract to turn a product request into a buildable Mac interface. It is
the transferable part of the Glaze approach: strong platform defaults, a bounded
component system, explicit states, and a verification harness. It is not a copy of
Glaze's private prompt, which was not available for inspection.

## 1. Ground the brief

Inspect the actual product before proposing UI. Identify:

- the user's recurring job, not the feature list;
- the objects they manipulate and the verbs they use;
- the most frequent command and the highest-consequence command;
- the information that must remain visible while they work;
- the existing brand, component, runtime, and persistence contracts;
- one concrete visual reference and the specific qualities it contributes.

If the reference is another app, borrow its hierarchy, density, interaction model,
or material discipline. Do not reproduce its branded assets or distinctive screen.

## 2. State the screen model before styling

Write these six lines:

```text
Primary job:
Window composition:
Persistent objects:
Primary command:
Secondary commands:
Required states:
```

Choose the simplest Mac composition that supports them:

- single content pane for one focused object;
- sidebar + content for persistent navigation;
- sidebar + content + inspector when selection properties must stay available;
- document windows when the user's files are the primary objects;
- menu-bar extra only when quick ambient access is the product's core job.

Do not begin with a dashboard grid. Start with the user's objects and commands.

## 3. Define the command surface

For every visible action, decide its canonical home:

- menu bar for the complete, stable command set;
- toolbar for frequent commands in the current window;
- context menu for selection-specific commands;
- inspector for editable properties that should stay visible;
- popover for brief, reversible choices;
- sheet/dialog only for a blocking decision;
- content surface for the primary product action.

Name standard shortcuts and define disabled states. Never make hover the only way
to discover or invoke a command.

## 4. Specify components by intent

Prompt for semantic components and behavior, not CSS decoration:

- “resizable navigation sidebar with compact selected rows”;
- “unified toolbar with a draggable empty region and trailing search”;
- “field group with persistent labels and native control density”;
- “selection-aware inspector that collapses before the content does”;
- “native-backed context menu with keyboard equivalents.”

Require reuse of the project's UI kit. A new visual primitive needs a new semantic
role, not merely a different color or radius.

## 5. Require the full state matrix

Every brief names the relevant combination of:

- populated, empty, loading, partial, offline, permission-denied, and error;
- default, hover, pressed, selected, focused, disabled, and destructive;
- key and inactive window;
- light and dark appearance;
- system accent changes;
- Reduce Motion, Reduce Transparency, and Increase Contrast;
- minimum, typical, and wide window sizes.

Use realistic fixture data. Empty lorem ipsum and repeated placeholder cards hide
hierarchy problems.

## 6. Set a measurable done bar

A design is done when the Mac App Done Rubric passes in both the browser fixture
and the native shell. Ask an independent critic to judge the artifact against the
brief, the rubric, and the named reference. Fix actionable failures and re-run the
changed checks; stop when there are no material failures or the agreed round cap is
reached.

## Compact reusable brief

```text
Design this as a macOS desktop product in the existing Tauri/Svelte/Rust stack.
First inspect the product, current components, and bridge. State the primary job,
window composition, persistent objects, command surface, visual reference, and
required state matrix. Use semantic Mac components and compact desktop metrics;
keep system behavior in the shell and product identity in the content. Implement
the same render tree with browser fixtures, then verify native-only seams in the
running Tauri app. Judge the result against the Mac App Done Rubric; do not accept
a browser-looking dashboard, mobile metrics, recreated traffic lights, or a static
happy-path mockup.
```
