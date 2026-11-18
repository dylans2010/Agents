<!-- system-index-depends: SwiftUsage.md, ErrorHandling.md -->

# Memory and Resource Lifecycle — Retain Cycles, Ownership, Cleanup, Leaks, and Lifecycle Bugs

Practical guidance for managing memory and scarce resources correctly: ownership, retain cycles, cleanup, leaks, and the lifecycle bugs that appear when objects live too long, die too early, or are used after they are gone. This asset governs **lifetime discipline**; `SwiftUsage.md` governs Swift-level patterns, and `AdvancedSwiftConcurrency.md` governs lifetime across asynchronous boundaries.

---

## 0. Scope and Purpose

Most memory bugs are not about running out of memory. They are about lifetime: an object that should have died and did not (a leak, a cycle), an object that died too early (a dangling reference, a callback into a deallocated owner), or a resource that was never released (a file handle, a subscription, a task). The program's behaviour then depends on the history of allocations — which is why these bugs are intermittent, hard to reproduce, and easy to misdiagnose.

Use this asset when:

- Memory grows without bound during a session.
- An object receives messages after it should be gone, or never receives the ones it should.
- A view, controller, or service is created repeatedly and never released.
- A resource (file, socket, subscription, observation) leaks or is used after close.

Do not use this asset as a substitute for profiling. Suspect a leak; prove it with the Allocations and Leaks instruments before changing code.

---

## 1. The Core Rules

- **Every owner is explicit.** For every object and every resource, someone owns it, and the owner is named in the code — a stored property, a collection, a task, a subscription. Ownership by accident (a global, a static, a closure that happens to capture it) is a leak waiting to happen.
- **Ownership forms a tree, not a graph.** A parent owns its children; children do not own their parent. Back-references are `weak`. A cycle in the ownership graph is a leak by construction.
- **Acquisition and release are paired, in the same place.** The code that acquires a resource names how it is released, and the release happens on every path — including error paths and cancellation.
- **Objects are not used after their lifecycle ends.** A callback, a notification, or a task that fires after its owner is gone must be inert: it must check, or it must have been cancelled when the owner died.
- **Deallocation is observable.** If you cannot tell when an object dies, you cannot tell whether it leaks. Make deallocation visible during debugging (a log in `deinit`, a counter, an instrument) until the lifecycle is proven.

---

## 2. Ownership in Swift

- **Strong by default, weak by design.** A stored strong reference is ownership. A `weak` reference is a non-owning observation that becomes nil when the owner dies. An `unowned` reference is a promise that the referent outlives the referrer — a promise that, if broken, crashes. Prefer `weak` unless the lifetime guarantee is genuinely provable.
- **Delegates are weak.** A delegate that is held strongly creates a cycle in the most common pattern in Apple-platform code: the owner holds the worker, the worker holds the owner as its delegate. The delegate is always `weak`.
- **Closures capture strongly by default.** A closure stored on an object that captures that object creates a cycle. Capture lists (`[weak self]`, `[unowned self]`) exist for this reason — use them at every stored closure, every escaping closure that outlives its call, and every subscription handler.
- **Capture only what the closure needs.** Capturing `self` to reach one property captures the whole object graph. Capture the value, not the owner, when the value is all that is needed.
- **Collections own their elements.** An array, dictionary, or set that accumulates objects without removal is a leak with an API. Every collection that grows during a session needs a removal rule: when does an element leave?
- **Singletons are permanent owners.** Anything a singleton holds strongly lives for the life of the process. A singleton that caches view controllers, documents, or sessions is a leak that grows with use.

---

## 3. Retain Cycles: Finding and Breaking Them

### 3.1 The classic shapes

- **Object ↔ closure.** An object stores a closure (a completion handler, an observation, a timer callback) and the closure captures the object. Break it with a `weak` capture, or by invalidating the stored closure when the object is torn down.
- **Object ↔ delegate.** Owner holds worker strongly; worker holds owner as delegate strongly. Break it by making the delegate `weak`.
- **Object ↔ object.** Two objects hold each other strongly, each believing the other is the child. Break it by deciding which one is the parent — the other reference becomes `weak`.
- **Object ↔ timer / observation / subscription.** A repeating timer, a notification observer, or a Combine/AsyncSequence subscription retains its target or its closure. The owner must invalidate, cancel, or remove it at teardown — and the teardown must actually run. A subscription stored in a bag that is never cleared is a leak.
- **Object ↔ task.** A `Task` that captures its owner and runs indefinitely (or until a condition that never arrives) keeps the owner alive. The task must be cancelled when the owner dies, and must check for cancellation.

### Example: the object-and-closure cycle, broken

A sync object stores a completion closure, and the closure captures the object — a loop of two strong references, so neither is ever released:

```swift
final class NoteSyncer {
    var onSyncFinished: () -> Void = {}

    func start() {
        onSyncFinished = {
            self.markSyncComplete()
        }
    }

    func markSyncComplete() {
    }
}
```

The memory graph shows the loop directly: `NoteSyncer` holds `onSyncFinished` strongly, and `onSyncFinished` holds `NoteSyncer` strongly. Breaking it means weakening one edge — the capture, since the object must keep owning its handler:

```swift
final class NoteSyncer {
    var onSyncFinished: () -> Void = {}

    func start() {
        onSyncFinished = { [weak self] in
            self?.markSyncComplete()
        }
    }

    func markSyncComplete() {
    }
}
```

After the fix, opening and closing the sync screen twenty times leaves the persistent count for `NoteSyncer` flat at zero between cycles. The `weak` capture is not a guess applied at random: it is the specific edge in the loop the memory graph identified, and the verification names that loop.

### 3.2 Diagnosis

- **Allocations instrument, persistent count.** An object type whose persistent count grows across repeated open/close cycles is leaking. The count is the evidence; the graph is the diagnosis.
- **Memory graph debugger.** Capture the graph, find the leaked object, and read its incoming strong references. The cycle is visible as a loop of strong edges. Follow the edges until the loop closes — that is the cycle to break.
- **Deinit logging.** A temporary log in `deinit` during debugging. If it never fires for an object that should have died, something still owns it. Remove the logging before the fix lands.

---

## 4. Resource Lifecycle

Memory is one resource; the same discipline applies to all of them:

- **Files and file descriptors.** Opened and closed in pairs, on every path. A descriptor leak eventually exhausts the process limit and produces failures in unrelated code — the symptom appears far from the cause.
- **Network connections and sessions.** Created, used, invalidated. A session that is never invalidated keeps its caches, its delegates, and its tasks alive.
- **Observers and subscriptions.** Registered and removed in pairs. An observer that outlives its owner receives events for a dead object — or keeps the owner alive to receive them.
- **Tasks and background work.** Started and cancelled in pairs. A task that survives its owner's teardown continues to consume CPU, hold memory, and deliver results to nobody.
- **Caches.** Bounded, with eviction. An unbounded cache is a leak that calls itself an optimisation. Every cache needs a size limit and an invalidation rule.
- **Platform resources.** Camera, microphone, location, Bluetooth, screen recording — acquired with user permission and released when no longer needed. Holding them is a privacy and battery issue as well as a resource one.

The pattern is always the same: **acquire, use, release — and the release must happen even when the use fails.** Swift's `defer` exists for this: put the release immediately after the acquisition, in the same scope, so no early return or thrown error can skip it.

---

## 5. Lifecycle Bugs

The most common lifecycle failures, and what they look like:

- **Use after teardown.** A callback fires after the view or controller was dismissed. The object is gone, but the closure, timer, or task still holds a strong reference — or worse, an `unowned` reference that now crashes. Fix by cancelling at teardown and by using `weak` captures that become nil instead of crashing.
- **Teardown that never runs.** A cleanup method that is only called from one path (a button, a specific dismissal) but not from the others (a swipe, a system termination, an error). Fix by putting cleanup in the one place that always runs — `deinit`, or the lifecycle event that is guaranteed.
- **Double teardown.** Cleanup that runs twice, releasing a resource twice or removing an observer twice. Fix by making cleanup idempotent, or by guarding it with a flag.
- **Resurrection.** An object that is deallocated, then brought back by a stale reference or a cache that re-registers it. Fix by removing the object from every registry at teardown.
- **Stale state after reuse.** A cell, a view, or a worker that is reused without resetting its state — it shows the previous item's data, or fires the previous item's callbacks. Fix by resetting all mutable state at the reuse point, not at creation.
- **The zombie delegate.** A delegate that is deallocated but the worker was never told. The worker calls into a dangling pointer (in unsafe code) or a nil weak reference (silently doing nothing). Either way the behaviour is wrong; the fix is to clear the delegate at teardown.

---

## 6. Failure Cases and Pitfalls

- **Fixing a leak by adding a `weak` somewhere at random.** The cycle is a specific loop of strong references. Adding `weak` to a reference that is not in the loop changes nothing; adding it to a reference that must be strong breaks ownership. Diagnose the loop first.
- **The leak that is actually a cache.** Memory grows because a cache grows. The fix is a bound and an eviction policy, not a `weak` reference.
- **Testing with too little repetition.** A leak of one object per session is invisible in a single run. Repeat the open/close cycle twenty times and watch the persistent count.
- **Relying on `deinit` for essential cleanup.** `deinit` runs when the last strong reference drops — which, in a cycle, is never. Essential cleanup (cancelling tasks, invalidating timers, closing resources) must happen at an explicit teardown point, with `deinit` as a backstop, not the plan.
- **Strong references in test fixtures.** A test that leaks its subject hides the leak and pollutes later tests. Tests should release their subjects and, where the lifecycle matters, assert deallocation.

---

## 7. Verification Steps

Before claiming a lifecycle problem is fixed:

1. The leak or cycle was proven with the Allocations instrument or the memory graph — persistent count growing, or a visible strong-reference loop.
2. The fix breaks the specific loop, and the reasoning names the edges involved.
3. Repeating the lifecycle (open/close, start/stop) twenty times leaves the persistent count flat.
4. Teardown paths are exercised: normal dismissal, error paths, and cancellation all release their resources.
5. No `deinit` logging or diagnostic code remains in the change.
6. The full test suite passes, including any new test that asserts deallocation or resource release.

## 8. Related Assets

- `AdvancedSwiftConcurrency.md` — lifetime of tasks and actors, cancellation.
- `ConcurrencyAsyncSystems.md` — tasks that outlive their owners.
- `PerformanceProfiling.md` — finding leaks and churn with instruments.
- `SwiftUsage.md` — capture lists, value types, and ownership idioms.
