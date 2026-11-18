<!-- system-index-depends: SwiftUsage.md, NativeMacSwiftUIArchitecture.md -->
# AppKitInteroperability.md — AppKit Interoperability in SwiftUI

Authoritative guidance for embedding AppKit views and controls inside SwiftUI, bridging responders and first-responder state, and using AppKit-only APIs from a SwiftUI macOS app. Use AppKit where SwiftUI cannot express the behavior; keep the SwiftUI side as the owner of state and the AppKit side as a rendering detail.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** AppKit bridging code and generated views must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If a representable fails to render, loses first responder, or leaks, diagnose the lifecycle (make/update/dismantle, coordinator ownership), formulate an alternative, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions.
- **Minimal surface:** Bridge the smallest AppKit surface that solves the problem. A whole AppKit view hierarchy inside SwiftUI is a design smell, not a solution.

---

## 1. NSViewRepresentable Lifecycle

- **Three methods, three responsibilities:** `makeNSView` creates the view once; `updateNSView` applies current SwiftUI state; `dismantleNSView` releases resources. Never create the view in `updateNSView` and never apply state in `makeNSView` that `updateNSView` will overwrite.
- **Coordinator owns the delegate:** The `Coordinator` class is the `NSView` delegate/data source and the bridge for callbacks into SwiftUI. It is created by `makeCoordinator` and lives as long as the representable.
- **Coordinator callbacks go through the model:** The coordinator calls model methods or updates bindings; it never mutates SwiftUI view structs directly. Callbacks that touch the model must hop to `@MainActor`.
- **Identity stability:** SwiftUI may recreate the representable struct freely; the underlying `NSView` persists by identity. State that must survive struct recreation lives in the coordinator or the model, never in the struct's stored properties.
- **Dismantle is not optional for heavy views:** Text views with large documents, web views, and views holding file handles must release in `dismantleNSView`. A missing dismantle leaks the heaviest objects in the app.

```swift
struct TextEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
```

---

## 2. Embedding AppKit Controls

- **Prefer SwiftUI first, bridge on evidence:** Bridge when SwiftUI lacks the control (rich `NSTextView`, `NSOutlineView` with drag, `NSVisualEffectView` materials, `NSSplitView` with custom dividers) — not because AppKit is familiar.
- **`NSTextView` for rich text:** Text views with attributed strings, rulers, completions, and spell checking are AppKit territory. Keep the document model in SwiftUI state; the text view is a rendering surface that reports edits through the coordinator.
- **`NSOutlineView` / `NSTableView` for large data:** Thousands of rows with cell reuse, drag-and-drop, and column sorting perform better in AppKit. Drive them from a diffed data source owned by the model.
- **`NSVisualEffectView` for materials:** Sidebar and toolbar materials come from `NSVisualEffectView` with the matching `NSVisualEffectView.Material`. Do not fake materials with translucent SwiftUI fills.
- **Size negotiation:** AppKit views report `fittingSize` and `intrinsicContentSize`; SwiftUI respects them through `.frame` and layout priorities. A representable that ignores sizing produces clipped or expanding views — set explicit layout priorities in `makeNSView`.
- **One representable per control:** A representable wraps one control, not a whole panel. Composition happens in SwiftUI; each bridge stays small, testable, and replaceable.

---

## 3. Responder Chain and First Responder

- **First responder is window state, not view state:** `NSWindow.firstResponder` is the single source of truth. A view becomes first responder by being in the window's responder chain and receiving `becomeFirstResponder`.
- **SwiftUI focus and AppKit focus are different systems:** `@FocusState` manages SwiftUI focus; `NSWindow.makeFirstResponder(_:)` manages AppKit focus. A representable that needs keyboard input must explicitly claim first responder when it appears and release it when it disappears.
- **Request first responder in `updateNSView`, guarded:** Only call `makeFirstResponder` when a bound `isFocused` flag is true and the view is not already first responder. Unconditional calls fight the user and steal focus from other controls.
- **Key view loop:** AppKit's Tab order follows `nextKeyView`. Set it explicitly for bridged controls; SwiftUI's focus order does not propagate into AppKit views automatically.
- **Responder loss on rebuild:** SwiftUI may replace the underlying `NSView` when identity changes, dropping first responder. Fix by keeping the representable's identity stable (stable `id`, no conditional struct type changes) and re-asserting focus in `updateNSView` only when the model says the view should be focused.
- **Menu validation flows through the responder chain:** `validateUserInterfaceItem` and `validateMenuItem` are consulted on the first responder and its chain. A bridged editor must implement validation for its actions or the menu items stay enabled when they cannot run.

---

## 4. Bridging State

- **Bindings cross the boundary, not structs:** The representable takes `@Binding` values and model references. The coordinator writes back through those bindings on the main actor.
- **Coalesce update storms:** `updateNSView` runs on every SwiftUI state change. Guard each assignment with an equality check (string, selection, scroll position) so the AppKit view is not reset on every keystroke.
- **Combine for AppKit publishers:** AppKit notifications (`NSText.didChangeNotification`, `NSWindow.didBecomeKeyNotification`) are observed with Combine in the coordinator or model, with cancellables stored on the coordinator and cancelled in `dismantleNSView`.
- **No shared mutable state across the boundary:** The AppKit view never holds a reference to a SwiftUI view struct. It holds the coordinator; the coordinator holds bindings and a weak model reference. Retain cycles here leak whole windows.
- **`@MainActor` everywhere on the bridge:** All coordinator callbacks, `updateNSView` mutations, and binding writes happen on the main actor. AppKit is not thread-safe; a background callback that touches a view is a crash.

---

## 5. AppKit-Only APIs

- **Panels:** `NSOpenPanel` and `NSSavePanel` are presented from the window, not from a SwiftUI view. Run them with `beginSheetModal(for:completionHandler:)` on the key window so they sheet correctly.
- **Pasteboard:** `NSPasteboard` reads and writes go through the model (copy/paste actions), not through view code. Pasteboard types are declared explicitly; never write a bare string and hope the receiver guesses the type.
- **Drag and drop:** `NSDraggingSource` / `NSDraggingDestination` live on the bridged view. The model supplies the dragged data and receives the drop; the view only reports gestures.
- **Services and sharing:** `NSSharingServicePicker` and the Services menu are AppKit APIs. Present them from the window's content view controller, not from SwiftUI.
- **Accessibility in bridged views:** AppKit views must expose `accessibilityLabel`, `accessibilityRole`, and `accessibilityValue`. SwiftUI accessibility modifiers do not propagate into the bridged subtree.

---

## 6. Methodology — Adding an AppKit Bridge

1. **Prove SwiftUI cannot do it:** Name the missing capability (rich text, outline drag, material, panel). If SwiftUI can do it, do not bridge.
2. **Define the smallest interface:** What state goes in (bindings, configuration) and what events come out (edits, selection, actions)? Write that contract before the representable.
3. **Write the coordinator first:** Delegates, notifications, and callbacks — with main-actor hops and weak references.
4. **Guard every update:** Equality checks before assignment in `updateNSView`; focus assertions only when the model requests focus.
5. **Handle dismantle:** Cancel subscriptions, remove observers, release heavy resources.
6. **Verify against sections 7 and 8 before finishing.**

---

## 7. Failure Cases and Pitfalls

- **Update churn resets the view:** `updateNSView` sets `textView.string` unconditionally, resetting cursor position and undo state on every keystroke. Fix: guard with an equality check.
- **Coordinator retain cycle:** The coordinator holds a strong model reference and the model holds the coordinator. Fix: weak model reference in the coordinator, or bindings only.
- **Focus theft:** `makeFirstResponder` called unconditionally in `updateNSView` steals focus from every other control. Fix: guard on a model-owned `isFocused` flag.
- **Lost first responder after rebuild:** The representable's identity changes and the new `NSView` is not first responder. Fix: stable identity and a guarded focus re-assertion.
- **Background-thread view mutation:** A coordinator callback from a notification fires off the main thread and mutates the view. Fix: hop to `@MainActor` in every callback.
- **Dangling observers:** Notifications registered in `makeNSView` are never removed. Fix: store tokens on the coordinator, cancel in `dismantleNSView`.
- **Sheet presented from the wrong window:** A panel opened with `runModal` instead of sheeting blocks the whole app. Fix: sheet from the key window.
- **Sizing fights:** The representable expands to fill the window because no layout priority was set. Fix: explicit `setContentHuggingPriority` / `setContentCompressionResistancePriority` in `makeNSView`.

---

## 8. Verification Steps

1. **Render:** The bridged control appears with correct size, material, and content on first appearance.
2. **Edit round-trip:** Typing in the bridged view updates the model; model changes update the view; undo works in both directions.
3. **Focus:** Tab order passes through the bridged control; clicking in claims first responder; clicking out releases it; no focus theft on unrelated state changes.
4. **Lifecycle:** Open and close the containing window repeatedly; no leaks (check Allocations), no dangling observers, no crashes on dismantle.
5. **Keyboard:** Shortcuts and menu validation work while the bridged view is first responder.
6. **Accessibility:** VoiceOver announces the bridged control with a correct label, role, and value.
7. **Thread safety:** No main-thread checker warnings; no AppKit access from background threads under the Thread Sanitizer.
8. **Panels and drag:** Open/save panels sheet from the correct window; drag-and-drop round-trips through the model.
