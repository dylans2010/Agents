<!-- system-index-depends: NativeMacSwiftUIArchitecture.md, UsingApp.md -->
# WindowLifecycleManagement.md — Window Management and Application Lifecycle

Authoritative guidance for macOS window management and application lifecycle: scenes, window creation and restoration, scene phase, termination, and multi-window coordination. A Mac app is a set of windows with a shared lifecycle; treat windows as first-class state, not as side effects of views appearing.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Window and lifecycle code must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If windows fail to open, restore, or close cleanly, diagnose the scene configuration and lifecycle handlers, formulate an alternative, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions.
- **User data first:** Lifecycle handling exists to protect user work. Never discard unsaved state to make a lifecycle transition look clean.

---

## 1. Scenes

- **Scene kinds and their jobs:** `WindowGroup` is the main document or primary window set. `Window(id:)` is a single auxiliary window keyed by an identifier. `DocumentGroup` is for document-based apps with file-backed models. `Settings` is preferences. `MenuBarExtra` is menu-bar presence. Each kind has distinct lifecycle semantics — do not use one to fake another.
- **One declaration per window kind:** The `App` body declares each scene once. Multiple windows of the same kind are values of the same scene, opened with different identifiers or values.
- **Scene state is model state:** Which windows are open, what each shows, and how they are arranged is recorded in the model where it is restorable. Views never track window existence in `@State`.
- **Settings and menu-bar scenes have their own lifecycles:** A `Settings` scene does not participate in window restoration the way a `WindowGroup` does. Do not store main-window state in a settings model.

---

## 2. Opening and Closing Windows

- **Open through the environment:** `@Environment(\.openWindow) var openWindow`, then `openWindow(id:)` or `openWindow(value:)`. The model decides whether the window may open; the view requests it.
- **Focus an existing window instead of duplicating:** Before opening a window for an item, check whether a window for that item already exists and bring it forward. Two windows editing the same item diverge.
- **Close through the environment:** `@Environment(\.dismiss) var dismiss` closes the current window's presentation. Programmatic close of a specific window goes through the model and the window's identity.
- **Closing is not destroying:** A closed window's model may persist (for restoration) or be released (for transient inspectors). The choice is explicit in the model, not an accident of view lifetime.
- **Sheets vs windows:** A sheet is modal to one window and blocks that window only. An auxiliary window is independent. Use a sheet for a task that must complete before the window continues; use a window for parallel work.

---

## 3. Restoration

- **Window frames restore by default in AppKit-backed apps:** SwiftUI scenes restore size and position when the scene is declared with a stable identity and the app has not opted out. Verify restoration on every scene you add; do not assume it.
- **State restoration is the model's job:** Selection, navigation path, scroll position, and open documents are saved by the model (on scene-phase change to background, on termination) and restored at launch. Views read restored state; they do not restore themselves.
- **Restorable state must be serializable:** Store identifiers, not object references. A selection stored as an object address is garbage after relaunch; stored as an ID it restores cleanly.
- **Version restoration data:** When the state schema changes, migrate or discard old restoration data explicitly. Silently reading a stale schema produces a window in an impossible state.
- **Do not restore errors:** A window that was showing an error at quit should restore to its underlying content, not to the error banner.

---

## 4. Scene Phase and Lifecycle Events

- **`scenePhase` is coarse:** `.active`, `.inactive`, `.background`. It tells you the app's foreground state, not a window's. Use it for app-level transitions (save, pause, resume), not for per-window logic.
- **Per-window events belong to the window:** `onAppear` / `onDisappear` on the window's root view mark window visibility. Window key/main status comes from AppKit notifications (`NSWindow.didBecomeKeyNotification`) bridged through the model.
- **Save on background, not on terminate:** Persist state when the scene phase moves to `.background` and periodically during use. Termination handlers are a last resort — the system may kill the app before they run.
- **Background work must be finite:** Work started when the scene goes to background must complete or be cancelled promptly. The system does not guarantee background runtime for a Mac app the way it does for iOS.
- **Do not fight the lifecycle:** A view that re-opens a window on `onDisappear`, or a model that re-activates the app on backgrounding, creates a lifecycle loop the user cannot escape.

---

## 5. Termination

- **Termination is a negotiation:** `applicationShouldTerminate` (via `NSApplicationDelegate` or the SwiftUI equivalent) asks each document and window whether it is safe to quit. Unsaved changes must block termination with a save/discard/cancel dialog.
- **Sudden termination:** The system may terminate the app without asking when no unsaved state exists. Design so that sudden termination is always safe: state is saved continuously, not only at quit.
- **Never lose user work to a fast quit:** If a save is in flight when termination is requested, delay termination until the save completes or fails with an error the user can act on.
- **Termination reply is explicit:** Reply `.terminateNow`, `.terminateLater`, or `.terminateCancel` exactly once per request. A missing reply hangs quit; a double reply is undefined behavior.
- **Cleanup is cheap and synchronous:** Termination cleanup releases resources and closes files. It does not start network requests or long migrations.

---

## 6. Multi-Window Coordination

- **Shared model, per-window slices:** Windows share the app model but each reads its own slice (its item, its selection, its navigation path). A window never mutates another window's slice directly.
- **Cross-window updates go through the model:** When a change in one window affects another (an item renamed, a thread completed), the model publishes the change and all windows re-render from the new state.
- **Window-specific commands use focus:** Commands that act on "the current window" read `@FocusedValue` from the key window. A command that acts on the wrong window because it read a global is a defect.
- **Window ordering is user state:** Which window is key, which is frontmost, and the z-order are the user's arrangement. The app does not reorder windows on its own initiative.
- **Resource limits per window:** Each window's heavy resources (previews, logs, subscriptions) are created when the window opens and released when it closes. A closed window must not keep subscriptions alive.

---

## 7. Methodology — Adding a New Window

1. **Name the window kind:** Main, auxiliary, inspector, preview, settings, or menu-bar? The kind determines the scene declaration.
2. **Define its identity:** What value keys it (item ID, session ID, none)? Identity determines duplication and restoration behavior.
3. **Define its model slice:** What state does it own, what does it share, what does it restore?
4. **Declare the scene:** `Window(id:)` with a stable identifier and a default size.
5. **Wire open/focus/close:** Through the environment, with duplicate-focus behavior.
6. **Wire save/restore:** Persist its slice on backgrounding; restore at launch.
7. **Verify against sections 8 and 9 before finishing.**

---

## 8. Failure Cases and Pitfalls

- **Duplicate windows for one item:** Opening the same item twice creates divergent edits. Fix: focus the existing window by identity.
- **State stored in the view:** Selection and navigation live in `@State` inside the window's root view and vanish when the window closes. Fix: move to the model.
- **Restoration of object references:** A stored object address restores to nothing. Fix: store IDs, resolve on launch.
- **Save only at termination:** The app is killed before the termination handler runs and work is lost. Fix: save on backgrounding and continuously.
- **Termination hang:** A missing or double termination reply hangs or crashes quit. Fix: exactly one reply per request, with a timeout path.
- **Lifecycle loops:** A view that reopens its window on disappear, or a model that reactivates on background. Fix: lifecycle handlers observe; they never initiate window creation.
- **Leaked per-window subscriptions:** A closed window keeps a log stream or file watcher alive, consuming resources and delivering updates to a dead view. Fix: tie subscriptions to window lifetime and cancel on close.
- **Sheet used as a window:** A long-running parallel task trapped in a modal sheet blocks its window. Fix: use an auxiliary window.

---

## 9. Verification Steps

1. **Cold launch:** Correct windows open, at the right size and position, with restored selection and content.
2. **Open/close cycle:** Open each window kind, close it, reopen it; no duplicates, no stale content, no leaks.
3. **Duplicate open:** Request the same item's window twice; the existing window comes forward, no second window appears.
4. **Background save:** Move the app to background; state is persisted; kill the app from Activity Monitor; relaunch restores.
5. **Termination with unsaved work:** Quit with dirty state; the save dialog appears; save, discard, and cancel all behave correctly.
6. **Multi-window edit:** Edit in one window; the other window reflects the change through the model without a manual refresh.
7. **Key window commands:** With two windows open, commands act on the key window's focused content, never the other window.
8. **Resource release:** Close a window with a heavy subscription; Allocations shows the subscription released.
