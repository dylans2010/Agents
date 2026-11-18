<!-- system-index-depends: UsingApp.md, SwiftUsage.md -->
# MacDesignConventions.md — Native macOS Interaction and Design Conventions

Authoritative guidance for designing native macOS interfaces: Human Interface Guidelines, materials, menus, toolbars, sheets, and controls. A Mac app earns trust by behaving like a Mac app — consistent chrome, predictable menus, restrained effects, and respect for the user's window arrangement. Novelty that breaks a convention must pay for itself.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Design and interface work must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If an interface violates a convention or behaves inconsistently, diagnose the cause, formulate a fix, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions.
- **Convention first:** Follow the HIG by default. Deviate only with a concrete, stated reason, and document the deviation.

---

## 1. Human Interface Guidelines Fundamentals

- **Clarity, deference, depth:** Content is the focus; chrome recedes; layers communicate hierarchy. A UI that shouts its chrome at the user has the priorities backwards.
- **Consistency beats originality:** Users transfer knowledge from every other Mac app. A control that looks standard but behaves differently is worse than a control that looks different.
- **Direct manipulation:** Users drag, drop, select, and edit content in place. Prefer in-place editing over dialogs that describe the edit.
- **Forgiveness:** Every destructive action is undoable or confirmed; every state change is reversible where the platform supports it.
- **Feedback:** Every action produces immediate visible feedback — a selection, a spinner, a status change. A button that does nothing visible for two seconds feels broken.
- **Aesthetic integrity:** The app's appearance matches its purpose. A developer tool looks precise and dense; a writing app looks calm and spacious. Visual language follows function.

---

## 2. Windows, Layout, and Materials

- **Sidebar, content, detail:** The standard three-column structure. The sidebar navigates, the content lists, the detail shows. Do not invent a fourth primary column without a strong reason.
- **Toolbars carry primary actions:** The window toolbar holds the actions for the current context (new, search, share, view options). Secondary actions live in menus or contextual menus, not in a second toolbar row.
- **Inspectors are optional panes:** An inspector shows details for the current selection and can be hidden. It never holds the only copy of an action.
- **Materials, not translucency hacks:** Sidebar and toolbar backgrounds use system materials (`NSVisualEffectView` materials, SwiftUI `.background(.thinMaterial)` and friends). A hand-rolled translucent fill looks wrong in one of the two appearances.
- **Respect the user's window arrangement:** Do not resize, reposition, or reorder windows on the user's behalf. Windows open where the user left them.
- **Responsive, not fixed:** Layouts adapt to window size. Fixed dimensions that clip at small sizes or waste space at large sizes are defects. Content reflows; sidebars collapse; toolbars overflow into menus.
- **Density follows purpose:** A pro tool can be dense; a consumer surface should breathe. Density is a decision per surface, not a global style.

---

## 3. Menus

- **Standard menus stay standard:** Application, File, Edit, Format, View, Window, Help — in that order, with standard items in standard places. Users find commands by muscle memory.
- **Menu items name actions:** Verbs, present tense, sentence case: "New Thread", "Duplicate", "Export as Markdown". Not "Thread Creation" and not "EXPORT".
- **Ellipsis means a dialog follows:** A menu item ending in "…" opens a dialog or sheet before acting. An item that acts immediately must not carry an ellipsis.
- **Disabled means cannot run now:** Items are disabled when their action cannot succeed (no selection, operation in flight), not hidden. Hidden items make users doubt the feature exists.
- **Contextual menus are short:** A right-click menu holds the actions for the clicked item — five to eight items, not the whole application. The full set lives in the menu bar.
- **No emoji or custom glyphs in menus:** Menu items use text and standard shortcuts. Decorative symbols break the platform visual language.

---

## 4. Sheets, Alerts, and Popovers

- **Sheets are modal to one window:** A sheet blocks its window, not the app. Use a sheet when the task must complete before the window continues (save, confirm, configure).
- **Alerts are for decisions, not information:** An alert asks the user to choose. Information that needs no choice is a banner, a status line, or a notification — not an alert.
- **Alerts have one clear default:** The default button is the safe action (Save, not Delete). Destructive buttons are never the default and are never adjacent to it without separation.
- **Popovers are transient:** A popover shows a quick detail or a small editor and dismisses when the user clicks away. A popover that holds a multi-step workflow is a sheet.
- **Never stack modals:** A sheet over a sheet over an alert traps the user in a modal maze. Flatten the flow or move the second step inline.

---

## 5. Controls

- **Buttons say what they do:** "Save", "Delete Thread", "Run Tests". A button labeled "OK" on a destructive action hides the consequence.
- **Segmented controls switch views or modes:** Use them for view switching (list/grid) or mutually exclusive modes. Do not use them as a row of unrelated buttons.
- **Pickers and pop-up buttons for choices:** A small set of options is a pop-up button; a large set is a combo box or a searchable list. A free-text field for a value chosen from a fixed set invites invalid input.
- **Sliders for continuous values with visible feedback:** A slider always shows its current value nearby. A slider with no value label is a guessing game.
- **Toggles are immediate:** Flipping a toggle applies the change at once. A toggle that requires a separate Save button is a checkbox pretending to be a toggle.
- **Text fields commit explicitly:** Return or focus loss commits; Escape reverts. A field that commits on every keystroke fights undo and validation.

---

## 6. Icons, Symbols, and Color

- **SF Symbols for interface icons:** Use SF Symbols at the right weight and size for the context. Custom-drawn icons must match the SF Symbols visual weight or they look foreign.
- **One accent color:** The app has a single accent color used sparingly for selection and primary actions. Multiple accent colors compete and confuse.
- **Color encodes, it does not decorate:** Red is destructive or error; green is success or active; orange is warning. Do not use these colors for decoration.
- **App icon follows the platform:** A macOS app icon is a rounded square with the platform's perspective and shadow conventions, not a scaled-down iOS icon.
- **Dark mode is not a theme:** Both appearances must be correct. Hardcoded light colors that break in dark mode are defects, not style choices.

---

## 7. Methodology — Design Review Checklist

1. **Name the surface:** Window, pane, sheet, dialog, popover, or menu? The kind determines the chrome and the interaction rules.
2. **Check the HIG for the kind:** What does the platform expect for this surface? Follow it first.
3. **Audit the chrome:** Sidebar, toolbar, inspector, menus — each holds what the platform expects and nothing else.
4. **Audit the controls:** Every control is the platform control for its job; every label names its action; every destructive action is confirmed or undoable.
5. **Audit the states:** Empty, loading, error, and success states are all deliberate and consistent.
6. **Keyboard and accessibility pass:** See `AccessibilityKeyboardInteraction.md`. A beautiful surface that cannot be used from the keyboard is unfinished.
7. **Verify against sections 8 and 9 before finishing.**

---

## 8. Failure Cases and Pitfalls

- **iOS patterns on macOS:** Tab bars for primary navigation, full-screen modals for settings, swipe as the only action. Fix: `NavigationSplitView`, `Settings` scene, toolbars, menus.
- **Custom chrome overreach:** A hand-drawn window frame that breaks traffic-light buttons, drag regions, and full-screen behavior. Fix: use the standard window and customize within it.
- **Fixed-size layouts:** A pane that clips at small window sizes and wastes space at large ones. Fix: flexible layout, collapsing sidebar, reflowing content.
- **Menu items that lie:** An ellipsis on an item that acts immediately; a disabled item that should be hidden or vice versa. Fix: ellipsis and enabled state follow the action.
- **Stacked modals:** A sheet that opens a sheet that opens an alert. Fix: flatten the flow.
- **Destructive default:** Delete as the default button in a confirmation alert. Fix: the safe action is the default.
- **Hover-only actions:** Actions visible only on hover are invisible to keyboard and VoiceOver users. Fix: menu and keyboard paths for every action.
- **Color-only state:** Status shown only by color. Fix: pair color with an icon or label.
- **Too many accents:** Three accent colors fighting for attention. Fix: one accent, used sparingly.

---

## 9. Verification Steps

1. **HIG comparison:** Each surface is compared against the HIG section for its kind; deviations are named and justified.
2. **Menu audit:** Standard menus are present and ordered; items name actions; ellipsis and enabled states are correct.
3. **Control audit:** Every control is the platform control for its job; labels name actions; destructive actions are confirmed or undoable.
4. **State audit:** Empty, loading, error, and success states render deliberately in every pane.
5. **Appearance audit:** Light and dark mode both render correctly; materials are system materials.
6. **Window behavior:** Resize, collapse, full-screen, and multi-window all behave as the platform expects.
7. **Keyboard and accessibility pass:** See `AccessibilityKeyboardInteraction.md`; zero blocking findings.
