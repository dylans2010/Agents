<!-- system-index-depends: SwiftUsage.md, UsingApp.md -->
# NativeMacSwiftUIArchitecture.md — Native macOS SwiftUI Architecture

Authoritative guidance for structuring native macOS applications in SwiftUI: app structure, state ownership, navigation, windows, and menus. Applies to every SwiftUI surface Assist reasons about or generates for macOS targets. The goal is an app that behaves like a Mac app — multi-window, menu-driven, keyboard-first — not an iOS layout stretched onto a desktop.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Generated architecture and SwiftUI modifications must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If generated SwiftUI code fails to compile or behaves incorrectly, diagnose the compiler diagnostics or the runtime behavior, formulate an alternative implementation, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions.
- **Platform Discipline:** macOS conventions win over iOS habits. When a SwiftUI API behaves differently on macOS, follow the macOS behavior and document the difference.

---

## 1. App Structure

- **`@main` App owns scenes, nothing else:** The `App` struct declares scenes (`WindowGroup`, `Window`, `Settings`, `MenuBarExtra`) and wires top-level dependencies. It holds no view state, no business logic, and no singletons that views reach for directly.
- **One model per concern, owned at the scene root:** A scene creates its model with `@State` and passes it down through the environment. A document app creates one model per document window; a single-window app creates one model for the main window and separate small models for auxiliary windows.
- **Scenes, not view controllers:** Prefer `WindowGroup`, `Window(id:)`, and `Settings` over `NSWindowController` subclasses. Reach for AppKit windows only when SwiftUI scenes cannot express the behavior (see `AppKitInteroperability.md`).
- **Settings scene is a real scene:** Preferences live in a `Settings` scene with tabbed panes, not in a modal sheet bolted onto the main window. Settings state is shared with the main window through the same model or a dedicated settings store, never duplicated.
- **MenuBarExtra for menu-bar presence:** A menu-bar utility is a `MenuBarExtra` scene with its own window content. It shares the model with the main window through a shared observable object created at the `App` level, not through a global.
- **Dependency injection at the root:** Services (network, persistence, providers) are constructed once in the `App` or scene initializer and injected via `.environment`. Views never construct services in `init` or `body`.

```swift
@main
struct AgentsApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
```

---

## 2. State Ownership

- **Single source of truth per fact:** Every piece of state has exactly one owner. Views read it; they never keep a second copy that can drift. If two views need the same value, both read the same model.
- **`@Observable` models, `@State` ownership:** Models are `@Observable` classes owned with `@State` at the scene root and read with `@Environment` below. Use `@Bindable` only at the point where a binding is actually needed.
- **`@State` is for view-local state only:** Selection within a single view, disclosure state, transient text-field content. Anything that must survive a view rebuild, cross a window, or be read by a command belongs in the model.
- **No state in `App` beyond the model:** The `App` struct holds model instances and service instances. It does not hold selection, navigation paths, or UI flags.
- **Derived state is computed, not stored:** Filtered lists, counts, and enabled states are computed properties on the model. Storing a derived copy creates a second source of truth that goes stale.
- **Concurrency boundaries:** Models that touch the network or disk are actors or `@MainActor`-isolated classes with async methods. Views never `await` inside `body`; they call model methods from `.task` or event handlers and read the resulting state.
- **Persistence is the model's job:** The model owns loading and saving (SwiftData, files, UserDefaults). Views never write to disk directly.

---

## 3. Navigation

- **`NavigationSplitView` is the Mac default:** Sidebar, content, detail. Three-column layouts use `NavigationSplitView` with a visibility binding so the user can collapse columns and the state persists.
- **Selection drives navigation, not pushes:** Navigation state is a selection binding on the model (`selectedItem: Item.ID?`), not a stack of pushed views. Deep links and restoration set the selection; the UI follows.
- **`NavigationStack` with a path for drill-down:** When a detail view drills deeper, use `NavigationStack(path:)` with a typed path stored on the model. The path is serializable state, restorable across launches.
- **Keep path and selection in sync:** A path that disagrees with the sidebar selection produces a detail view with no selected row. Update both together in one model method.
- **Toolbar placement follows the column:** Column-specific actions live in that column's toolbar. Global actions live in the window toolbar or the menu bar, never duplicated in both.
- **Keyboard navigation is navigation:** Arrow keys move selection in lists; Return opens; Escape closes. Do not require the mouse for any navigation path (see `AccessibilityKeyboardInteraction.md`).

---

## 4. Windows

- **One scene per window kind:** The main window is a `WindowGroup`; each auxiliary window (inspector, preview, about) is a `Window(id:)` with a stable identifier. Never create windows by constructing `NSWindow` in view code.
- **Open windows through the environment:** Use `@Environment(\.openWindow) var openWindow` and `openWindow(id:)` with a value. The model decides whether a window may open; the view only requests it.
- **Window identity is data:** `Window(id:)` receives a value (an item ID, a session ID). Two windows for two items are two values of the same scene, not two scene declarations.
- **Default size and position are deliberate:** Set `.defaultSize(width:height:)` and `.defaultPosition(.center)` or a saved frame. A window that opens at a random size on every launch is a defect.
- **Per-window state stays per-window:** Each window gets its own model instance or its own slice of a shared model keyed by window ID. Shared mutable state across windows without a key is a race.
- **Closing a window is not quitting:** Closing the last window of a `WindowGroup` does not terminate the app unless the app opts into that behavior. Termination policy is an app-level decision (see `WindowLifecycleManagement.md`).

---

## 5. Menus and Commands

- **Commands live in the scene, not the view:** `CommandMenu` and `CommandGroup` are declared in the `App` body alongside scenes. Menu actions call model methods; they never reach into a view hierarchy.
- **Keyboard shortcuts are declared once:** A shortcut is declared on its `Command` or `Button` with `.keyboardShortcut`. The same action must not have two different shortcuts in two places.
- **Menu state reflects model state:** Enable/disable menu items from model state (selection present, operation in flight). A menu item that is always enabled and fails at runtime is a defect.
- **`@FocusedValue` for context:** Commands that act on the focused view (copy, delete, rename) read `@FocusedValue` / `@FocusedObject`. Views publish focused values; commands consume them. This keeps commands decoupled from any specific view.
- **Standard menus stay standard:** Do not remove or reorder the standard Application, File, Edit, View, Window, and Help menus without a concrete reason. Users find commands by muscle memory.

---

## 6. Methodology — Designing a New Feature

1. **Name the model first:** What state does the feature own? What are its inputs, its derived values, its persistence? Write the model before any view.
2. **Decide the scene:** Main window column, detail view, auxiliary window, settings pane, or menu-bar extra? The scene choice determines the state lifetime.
3. **Decide navigation:** Selection binding, stack path, or modal presentation? Record the decision in the model, not in view-local state.
4. **Build the view as a pure function of the model:** The view reads model state and calls model methods. No view-local copies of model data.
5. **Wire commands and shortcuts:** Every primary action gets a menu command with a shortcut where the HIG expects one.
6. **Handle the empty state:** A feature with no data shows an intentional empty state with a next action, never a blank pane.
7. **Verify against sections 7 and 8 before finishing.**

---

## 7. Failure Cases and Pitfalls

- **Duplicated state:** A view keeps its own `@State var items` mirroring the model. Edits in one place never appear in the other. Fix: delete the copy; read the model.
- **`@StateObject` in a view that rebuilds:** The object is recreated when the view identity changes, losing state. Fix: own the model at the scene root with `@State`.
- **Navigation path desync:** The stack path holds an item the sidebar no longer selects. Fix: one model method updates selection and path together.
- **Global singletons as state:** A `shared` model reached from anywhere makes testing impossible and hides ownership. Fix: inject through the environment.
- **Blocking the main thread in `body`:** Synchronous disk or network access during view evaluation freezes the UI. Fix: async model methods, `.task` for loading.
- **iOS idioms on macOS:** Full-screen modal sheets for settings, tab bars for primary navigation, swipe gestures as the only action. Fix: use `Settings`, `NavigationSplitView`, toolbars, and menus.
- **Commands reaching into views:** A command that searches the view hierarchy for a control breaks on the next refactor. Fix: `@FocusedValue` and model methods.
- **Window-per-item without identity:** Opening the same item twice creates two windows with the same content and divergent edits. Fix: key windows by item ID and focus the existing window.

---

## 8. Verification Steps

1. **Build with strict concurrency:** No data-race warnings, no main-thread blocking diagnostics.
2. **Cold launch:** App opens to the correct window, size, and selection with no data.
3. **State survives rebuilds:** Rotate selection, resize, collapse the sidebar, reopen the window — state is consistent everywhere.
4. **Multi-window:** Open two windows for two items; editing in one never leaks into the other; closing one leaves the other intact.
5. **Keyboard-only pass:** Every primary action is reachable and visible via keyboard and menus alone.
6. **Menu audit:** Every command is enabled exactly when it can succeed; shortcuts match the HIG and do not collide.
7. **Empty and error states:** Each view renders a deliberate empty state and a deliberate error state.
8. **Persistence round-trip:** Relaunch; selection, window frames, and settings are restored.
