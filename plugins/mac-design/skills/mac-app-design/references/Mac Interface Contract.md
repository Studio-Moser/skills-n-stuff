# Mac Interface Contract

## Window composition

- Use the native Tauri window and real traffic lights. Never draw replacement dots in the packaged app.
- Treat the titlebar/toolbar, sidebar, inspectors, menus, popovers, and transient controls as chrome; treat the user's objects and work as content.
- Use one strong pane composition instead of a webpage header followed by a grid of cards.
- Let panes resize continuously. Hide or collapse secondary panes before compressing the primary content beyond usefulness.
- Keep each pane's scrolling independent. Allow content to pass under translucent chrome with a progressive edge effect rather than an opaque strip and heavy divider.
- Preserve minimum, typical, and wide layouts. Responsive Mac layout is continuous resizing, not a desktop/mobile breakpoint pair.

## Practical starting metrics

Follow existing product tokens first. When none exist, start here and tune by
looking at the running app:

| Role | Starting value |
| --- | ---: |
| Base UI text | 13 px/pt |
| Metadata | 10–11 px/pt |
| Unified-toolbar title | 13–15 px/pt, medium/semibold |
| Toolbar height | 52–54 px/pt |
| Compact controls | 18, 22, 28, and 34 px/pt |
| Toolbar icon button | about 36 × 26 px/pt |
| Sidebar | 225–400 px/pt, resizable |
| Inspector | 280–460 px/pt, resizable |
| Spacing rhythm | 4 px/pt base, usually grouped on 8 |

Use the system font stack (`-apple-system`, SF Pro) for routine UI. A rounded or
branded face may appear deliberately, but it must not make labels larger or softer
than Mac density permits. Use tabular numbers for changing or aligned values.

## Semantic tokens

Define roles rather than fixed light-mode colors:

- text: primary, secondary, tertiary, disabled, link, destructive;
- surfaces: window, sidebar, chrome, control, inset well, selected row, popover, dialog;
- lines: separator, field border, strong outline;
- elevation: panel, popover, dialog;
- geometry: field, control, panel, popover, pill;
- states: hover, pressed, selected, keyboard focus, inactive window.

Support light/dark appearance, system accent, key/inactive windows, Increase
Contrast, and Reduce Transparency. Dark appearance is a separately tuned palette,
not an inversion.

## Semantic components

- **Toolbar:** leading navigation/title, a few grouped actions, trailing search or one primary action. Keep empty regions draggable; controls are never drag regions.
- **Sidebar:** compact rows, restrained labels, native-feeling selection, arrow-key navigation, shallow disclosure, user resizing and hiding.
- **Split view:** pointer and keyboard resizing with exposed separator semantics and min/max values.
- **Inspector:** selection-aware properties or activity that stays visible while the user works; collapses before primary content.
- **List/table:** dense rows, explicit selection, keyboard range/toggle behavior, inline rename where appropriate, contextual commands, useful empty states.
- **Fields:** persistent labels, compact controls, visible keyboard focus, clear validation near the field.
- **Menu/select/context menu/tooltip:** prefer native-backed behavior when placement, dismissal, keyboard routing, or inactive-window behavior differs from macOS.
- **Popover:** brief, reversible choices anchored to their source.
- **Sheet/dialog:** only for a decision that genuinely blocks the current task.
- **Empty state:** one explanation and one next action, not a marketing landing page.

Selection is the strongest routine state. Hover is subtle. Keyboard focus is
unmistakable. Primary actions stay visible; hover may reveal only secondary detail.

## Command and interaction model

- Put stable app, window, and document commands in the application menu bar. Direct-manipulation and selection-specific actions may remain canonical in content, an inspector, a popover, or a context menu.
- Give conventional or frequent commands standard shortcuts: Command-S/F/W/Z/Shift-Z/A/C/V/X and Command-comma where their meanings apply.
- Define disabled command states instead of hiding stable menu items.
- Preserve Escape/Return, arrow navigation, Shift ranges, Command toggles, Delete, Space/Quick Look, undo/redo, drag/drop, and focus restoration where the object model calls for them.
- Prefer undo for fully reversible destructive actions. Use a native confirmation when recovery is unavailable or the action has broad scope; state the affected object and consequence. Do not recreate browser modals for system tasks.
- Use motion for spatial continuity or meaningful feedback; remove movement under Reduce Motion.

## Brand

Keep routine chrome restrained and system-aware. Put product identity in the
content: illustration, data visualization, meaningful color, icon language,
onboarding, empty states, voice, and a few deliberate microinteractions. Do not
brand every control, surface, or selection state.

## Mac App Done Rubric

Fail the surface if any applicable item is false:

1. It uses a real system window and does not recreate traffic lights.
2. Its pane structure follows the user's objects and tasks, not a dashboard template.
3. Toolbar, sidebar, inspector, scrolling, and drag regions behave correctly at minimum, typical, and wide sizes.
4. Type and controls use compact desktop metrics; nothing defaults to mobile-sized 44 px controls or universal 16 px body text.
5. Stable commands have appropriate menus and disabled states; frequent commands have shortcuts; contextual commands and keyboard focus behavior remain complete.
6. Semantic components and tokens cover hover, pressed, selected, focused, disabled, destructive, key/inactive window, light/dark, and accessibility appearances.
7. Primary actions are visible without hover; every applicable operational state is intentionally designed and omissions are justified.
8. Materials are restrained to chrome and transient surfaces; content hierarchy does not depend on glass cards or heavy shadows.
9. The renderer uses a narrow typed capability bridge and does not receive unrestricted system access.
10. Browser-fixture checks pass, and every native-only claim is verified in the running Tauri app or packaged `.app`.
