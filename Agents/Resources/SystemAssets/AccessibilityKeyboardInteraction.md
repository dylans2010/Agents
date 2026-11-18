<!-- system-index-depends: MacDesignConventions.md, UsingApp.md -->
# AccessibilityKeyboardInteraction.md — Accessibility and Keyboard Interaction

Authoritative guidance for building macOS interfaces that work with VoiceOver, Full Keyboard Access, and keyboard-only operation. Accessibility is not a feature flag: every control must be labeled, every action must be reachable without a pointer, and every state change must be announced. A feature that cannot be used from the keyboard is unfinished.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Accessibility work must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If an accessibility audit finds unlabeled controls, focus traps, or unreachable actions, diagnose the cause, formulate a fix, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions.
- **No pointer-only paths:** Every action reachable with a mouse must be reachable with the keyboard. Every state visible on screen must be perceivable through VoiceOver.

---

## 1. VoiceOver

- **Every control has a label:** `.accessibilityLabel` on every button, field, toggle, and image that conveys meaning. An icon-only button with no label is invisible to VoiceOver — the most common accessibility defect in Mac apps.
- **Labels name the action, not the appearance:** "Delete thread", not "Trash icon". "Send message", not "Blue button".
- **Hints explain consequences:** `.accessibilityHint` states what happens ("Deletes the thread permanently") when the action is not obvious from the label.
- **Values report state:** `.accessibilityValue` reports the current state of toggles, sliders, progress, and steppers ("On", "75 percent", "3 of 12"). A control whose state is only visible is a control whose state is unknown to VoiceOver users.
- **Traits describe behavior:** `.accessibilityAddTraits` marks buttons, links, selected states, and headers. A row that acts as a button must carry the button trait or VoiceOver users cannot discover the action.
- **Headings structure the screen:** `.accessibilityHeading(.h1)` and levels below let VoiceOver users navigate by heading. Every pane has a heading; every section has a subheading.
- **Groups reduce noise:** `.accessibilityElement(children: .combine)` merges a row's icon, title, and subtitle into one announced element. Un-grouped rows force VoiceOver to announce five elements for one logical item.
- **Announce state changes:** When an async operation completes (a build finishes, a thread errors), post an announcement with `AccessibilityNotification.Announcement` so the change is perceivable without looking.
- **Rotor and custom actions:** Expose frequent actions as `.accessibilityAction` custom actions on rows (delete, rename, duplicate) so VoiceOver users reach them without navigating into a detail view.

---

## 2. Keyboard Navigation

- **Tab order follows the visual order:** Top to bottom, left to right, sidebar before content before detail. A Tab order that jumps across the window is a defect, even if every control is eventually reachable.
- **`@FocusState` owns focus:** Focus is model-adjacent state, owned by the view or model with `@FocusState` and an enum of focusable fields. Never move focus by searching the view hierarchy.
- **Default focus on appearance:** When a sheet, dialog, or new pane opens, focus lands on the primary control (the first field, the default button). A dialog that opens with no focus forces the user to Tab from the top of the window.
- **Focus is visible:** The focus ring must be visible on every focused control in both light and dark mode. Custom controls must draw a focus ring; a control that hides its focus ring is unreachable in practice.
- **Escape closes, Return confirms:** Sheets and dialogs close on Escape and confirm on Return (or Command-Return for multi-line fields). Do not invent different dismissal keys per dialog.
- **Arrow keys move selection:** Lists, outlines, and grids respond to Up/Down (and Left/Right for disclosure). Selection moves without opening; Return opens.
- **No focus traps:** Focus must always be able to leave any pane, sheet, or popover with Tab/Shift-Tab or Escape. A trap that requires a mouse click to escape is a blocking defect.
- **Full Keyboard Access:** Test with Full Keyboard Access enabled (System Settings → Accessibility → Keyboard). Every control, including toolbar items and segmented controls, must be reachable.

---

## 3. Keyboard Shortcuts

- **Declare shortcuts once, on the command:** `.keyboardShortcut` on the `Command` or `Button` that performs the action. The same action must not carry two different shortcuts.
- **Follow the HIG shortcut map:** Command-N new, Command-O open, Command-S save, Command-W close window, Command-Q quit, Command-, settings, Command-F find, Command-Z undo, Command-Shift-Z redo. Reassigning a standard shortcut to a different action breaks muscle memory across every Mac app.
- **Single-key shortcuts need a modifier in text contexts:** A bare key (J, K) that works in a list must not fire while the user types in a text field. Guard single-key shortcuts by focus context or require a modifier.
- **Discoverability:** Every shortcut appears in its menu item. An action with a shortcut but no menu item is undiscoverable; an action in a menu without its shortcut is unlearnable.
- **No collisions:** Audit the full shortcut set for duplicates. Two commands sharing a shortcut means one of them never runs.
- **Custom shortcuts are a setting, not a default:** If the app supports remapping, defaults stay standard and remapping is explicit in Settings.

---

## 4. Visual and Motor Accessibility

- **Dynamic Type:** Text scales with the user's preferred size. Layouts must adapt — no fixed heights that clip enlarged text, no truncation that hides the action.
- **Reduced Motion:** Honor `AccessibilityReduceMotion`. Replace sliding and scaling transitions with fades or instant changes when the setting is on.
- **Differentiate Without Color:** Never encode state by color alone. Errors, selections, and statuses pair color with an icon, label, or shape.
- **Contrast:** Text meets the HIG contrast ratios in both light and dark mode. Secondary text that fails contrast is unreadable text.
- **Minimum target size:** Clickable controls are at least the HIG minimum (roughly 20–24 pt for toolbar items, larger for primary actions). A 12 pt icon button is a motor-accessibility defect.
- **Hover is not information:** State or actions revealed only on hover are invisible to keyboard and VoiceOver users. Every hover-revealed action has a keyboard and menu path.

---

## 5. Methodology — Accessibility Audit Pass

1. **VoiceOver walkthrough:** Enable VoiceOver and navigate the feature start to finish with the screen off. Every control announces a label, a role, and a value where applicable.
2. **Keyboard-only walkthrough:** Unplug the mouse. Complete the feature's primary task using Tab, arrows, Return, Escape, and shortcuts.
3. **Full Keyboard Access:** Repeat with Full Keyboard Access on; verify toolbar and segmented controls are reachable.
4. **Dynamic Type extremes:** Set the largest text size; verify no clipping, no hidden actions, no broken layouts.
5. **Reduced Motion and contrast:** Verify transitions respect the setting and text remains readable.
6. **Fix in order:** Labels first, then focus order, then shortcuts, then visual issues. A labeled control with imperfect focus is usable; an unlabeled control is not.

---

## 6. Failure Cases and Pitfalls

- **Unlabeled icon buttons:** The most common defect. Every icon button gets an explicit `.accessibilityLabel`.
- **Focus trap in a sheet:** Tab cycles inside a sheet and never reaches the close button. Fix: include all controls in the focus order and verify Escape dismisses.
- **Focus stolen on update:** A state change moves focus to the top of the window. Fix: never change `@FocusState` in response to data updates; only in response to user navigation.
- **Shortcut collision:** Two commands share Command-Shift-D; one never fires. Fix: audit the full set and keep a single registry.
- **Single-key shortcut firing in text fields:** Pressing J in a text field triggers a list action. Fix: guard by focus context.
- **Color-only status:** A red dot means "error" to sighted users and nothing to anyone else. Fix: pair with a label or icon.
- **Hover-only actions:** A delete button appears only on hover; keyboard users cannot delete. Fix: menu and keyboard paths for every hover action.
- **Announcements on every keystroke:** Announcing each character change floods VoiceOver. Fix: announce completions and state changes, not intermediate input.
- **Bridged AppKit views without accessibility:** A representable whose AppKit subtree exposes no labels. Fix: set accessibility properties on the AppKit view itself (see `AppKitInteroperability.md`).

---

## 7. Verification Steps

1. **VoiceOver pass:** Complete the feature with VoiceOver on and the display off; every control announces correctly.
2. **Keyboard-only pass:** Complete the feature with no pointer; every action is reachable and every dialog dismissible.
3. **Full Keyboard Access pass:** Toolbar, segmented controls, and popovers are reachable.
4. **Focus visibility:** The focus ring is visible on every focused control in light and dark mode.
5. **Shortcut audit:** Every shortcut is in its menu item; no collisions; standard shortcuts keep standard meanings.
6. **Dynamic Type:** Largest text size renders without clipping or hidden actions.
7. **Reduced Motion:** Transitions respect the setting.
8. **Accessibility Inspector:** Run the Accessibility Inspector audit; zero errors, zero unlabeled controls.
