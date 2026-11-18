<!-- system-index-depends: SwiftUsage.md, ConcurrencyAsyncSystems.md -->

# Advanced Swift Concurrency — Actors, Sendable, TaskGroups, Async Sequences, and MainActor Discipline

Advanced guidance for Swift's concurrency model: how actors isolate state, what `Sendable` actually guarantees, how `TaskGroup` and async sequences structure parallel and streaming work, and how MainActor discipline keeps the interface responsive without scattering main-thread hops through the codebase. This asset governs **Swift concurrency mechanics**; `ConcurrencyAsyncSystems.md` governs concurrency design in general, and `SwiftUsage.md` governs Swift patterns underneath.

---

## 0. Scope and Purpose

Swift's concurrency model is a contract: the compiler will catch a large class of data races for you — if you write code it can check. Every escape hatch (`@unchecked Sendable`, nonisolated access, unstructured tasks, `Task.detached`) is a place where you have told the compiler to stop checking, and where a race can now hide. Advanced use of the model is therefore mostly about knowing which guarantees you have, which you have given up, and where the remaining risks live.

Use this asset when:

- Designing an actor, a task hierarchy, or a streaming pipeline in Swift.
- Deciding whether a type is `Sendable` and what that requires.
- Debugging a race, a hang, or a main-thread violation in Swift code.
- Reviewing concurrent Swift code for correctness.

Do not use this asset to justify turning every type into an actor or every function into `async`. Concurrency is a tool for specific problems; applying it everywhere creates new problems (actor hops, suspension points, and complexity) without removing the old ones.

---

## 1. Actors: Isolation and Its Limits

An actor is a reference type whose mutable state is isolated to the actor: only the actor's own code touches its state directly, and all other access goes through an asynchronous hop that serialises it.

### 1.1 What actors guarantee

- **No two pieces of code mutate the actor's state at the same time.** The actor serialises access. A race on actor-isolated state is impossible by construction.
- **State is accessed only through the actor.** External code must `await` the actor, which is a visible suspension point — the caller can see that the access may take time and may interleave with other work.

### 1.2 What actors do not guarantee

- **They do not prevent logical races.** Two tasks can each read a value, compute, and write it back through the actor — serialised, but still interleaved. The actor guarantees the individual accesses are atomic; it does not guarantee the read-compute-write sequence is atomic. A sequence that must be atomic belongs inside a single actor method.
- **They do not prevent re-entrancy interleaving.** While an actor method awaits, another task can enter the actor and observe or change state. A method that checks a condition, awaits, and then acts on the condition may find the condition changed. Re-check after every `await`, or restructure so the check and the act happen without an intervening suspension.
- **They do not make the code fast.** Every cross-actor call is a hop with scheduling cost. An actor called in a tight loop, or an actor that does heavy computation, serialises work that could have run in parallel. Keep actor methods short and non-blocking.
- **They do not isolate what escapes.** A mutable reference handed out of an actor (a class instance, a mutable collection passed by reference) can be mutated from outside the actor. Isolation ends at the boundary; what crosses it must be a value, an immutable snapshot, or a `Sendable` type.

### 1.2 Example: the re-entrancy interleaving

Two tasks ask a loader for the same note at the same time. Each checks, finds the note not yet loaded, and starts a fetch — and the note is published twice:

```swift
actor NoteLoader {
    private var loaded: Set<String> = []

    func loadIfNeeded(id: String) async {
        guard loaded.contains(id) == false else {
            return
        }
        let note = await fetchFromDisk(id: id)
        loaded.insert(id)
        publish(note)
    }
}
```

The interleaving, step by step:

```text
Task A: checks loaded, id is absent
Task B: checks loaded, id is absent
Task A: awaits fetchFromDisk, suspends
Task B: awaits fetchFromDisk, suspends
Task A: resumes, inserts id, publishes the note
Task B: resumes, inserts id again, publishes the note a second time
```

The actor serialised every individual access — nothing here is a data race — and the bug still happened, because the check and the act are separated by a suspension point. The fix is to re-check after the `await`, so the second task finds the note already loaded and returns without publishing:

```swift
actor NoteLoader {
    private var loaded: Set<String> = []

    func loadIfNeeded(id: String) async {
        guard loaded.contains(id) == false else {
            return
        }
        let note = await fetchFromDisk(id: id)
        guard loaded.contains(id) == false else {
            return
        }
        loaded.insert(id)
        publish(note)
    }
}
```

The re-check prevents the double publish. If the duplicate fetch itself is the problem rather than the double publish, track the in-flight load in the actor's state so the second caller awaits the first caller's result — see `ConcurrencyAsyncSystems.md`.

### 1.3 Actor design

- **One actor, one responsibility.** An actor that owns unrelated state serialises unrelated work against each other and becomes a bottleneck.
- **Prefer small, focused actors** over one large actor that owns everything. Split by the state that changes together.
- **Keep actor methods non-blocking.** An actor method that awaits a long operation holds the actor's serial queue hostage: every other caller waits. Do the long work outside, then hop in to update state.
- **Use nonisolated methods for pure computation.** A method that touches no isolated state can be `nonisolated` — callable synchronously, without a hop. Mark it deliberately, and verify it truly touches no state.
- **The MainActor is an actor.** It is the serial executor for the interface. MainActor-isolated state is safe from races and slow if abused: every access serialises through the main thread. Keep MainActor work small and interface-related — see section 5.

---

## 2. Sendable: What It Guarantees and What It Costs

`Sendable` is a compile-time claim that a value can be safely passed across concurrency domains (between tasks, actors, and threads).

### 2.1 What is Sendable

- **Value types whose stored properties are all Sendable.** Structs and enums composed of Sendable values are Sendable. This is why value types are the default safe choice at concurrency boundaries.
- **Final classes with only immutable Sendable state** (all `let` properties that are Sendable). A class with no mutable state cannot race.
- **Actors.** An actor reference is Sendable because access to its state is serialised by the actor itself.
- **Types explicitly marked `@unchecked Sendable`.** The compiler is told to trust the author. This is an assertion, not a proof — and a wrong assertion is a race the compiler will never catch.

### 2.2 The discipline

- **Prefer types the compiler can verify.** If a type is not Sendable, the first question is whether it should be: can it be a value type, can its mutable state be removed or isolated, can the crossing be a copy instead of a shared reference?
- **`@unchecked Sendable` needs a written justification.** What invariant makes it safe? Who maintains that invariant? What test would catch a violation? An unchecked conformance without a justification is a race with a comment.
- **Mutable shared state behind `@unchecked Sendable` must have its own synchronisation.** A lock, an actor, a serial queue — something, owned by the type, that serialises access. "It is only written during setup" is a claim that must be enforced, not assumed.
- **Closures crossing boundaries must be `@Sendable`.** A closure passed to a task or stored for later execution must only capture Sendable values. A closure that captures a mutable variable or a non-Sendable class is a race waiting for a schedule.
- **Global and static mutable state is not Sendable by default.** Swift 6 makes this a compile-time error in strict mode for good reason: a global mutated from two tasks is a race. Give it an owner (an actor, a lock) or make it immutable.

---

## 3. TaskGroup and Structured Parallelism

`TaskGroup` (and `ThrowingTaskGroup`) is the structured way to run parallel work: child tasks are created by the group, complete before the group returns, and their results and errors are collected in one place.

### 3.1 The rules

- **Children are bounded by the group.** When the group scope exits, all children have finished or been cancelled. There is no orphaned work.
- **Errors propagate.** A throwing child reports to the group; the group reports to the caller. An error in a child is not lost.
- **Cancellation propagates.** Cancelling the group cancels the children. A child that ignores cancellation keeps running — so children must check for cancellation (see `ConcurrencyAsyncSystems.md`).
- **Results are collected, not raced.** `group.next()` yields results as children complete; the caller decides the order it processes them. Do not assume completion order.
- **`async let` is a group of one.** For a fixed, small number of parallel values, `async let` is clearer than a group. For a dynamic number, or for work discovered at runtime, use a group.

### 3.2 Common mistakes

- **A group that grows without bound.** Adding a child per item in a large collection creates thousands of concurrent tasks. Bound the parallelism: a fixed number of workers, a semaphore, or a chunked group.
- **Shared mutable state inside the group.** Children that mutate a shared variable (an accumulator, a dictionary, a counter) race — the group structures the tasks, not the data. Collect results through the group and combine them in the parent, or give the shared state an actor.
- **A child that awaits the parent.** A child that depends on the parent's result, or on another child's result through the parent, deadlocks the group: the parent waits for the group, the group waits for the child, the child waits for the parent.
- **Using a group where sequential work would do.** Parallelism has overhead: task creation, scheduling, result collection. For small work, sequential is faster and simpler. Parallelise when measurement says the work is big enough to matter.

---

## 4. Async Sequences: Streaming Work

An async sequence (`AsyncSequence`, `AsyncStream`, `AsyncThrowingStream`) is a stream of values delivered over time: network events, file lines, notifications, sensor readings.

### 4.1 The rules

- **A sequence has one consumer.** An async sequence is typically a single-pass stream: one `for await` loop consumes it. Two consumers racing over the same stream get an arbitrary split of the values. If two consumers need the values, broadcast them (a shared stream, an actor, a notification) — do not share the sequence.
- **Backpressure is real.** A fast producer and a slow consumer need a policy: buffer (bounded, with a defined overflow behaviour), drop, or suspend the producer. An unbounded buffer is a leak; a dropped value is a lost event. Choose deliberately.
- **Cancellation ends the stream.** When the consuming task is cancelled, iteration ends. The producer must observe the end of consumption and release its resources — a stream that keeps producing after its consumer is gone leaks.
- **Errors end the stream.** A throwing sequence terminates on its first error. The consumer must handle the error at the loop, not inside it, and must decide whether to restart the stream or stop.
- **Do not block inside the loop.** The loop body should process the value and move on. Blocking work inside the loop stalls the stream and delays every subsequent value.

### 4.2 `AsyncStream` and continuations

- **The continuation is the producer's handle.** `AsyncStream` is built by giving a closure a continuation; the producer yields values through it. The continuation must be finished (`finish()`) when production ends, or the consumer waits forever.
- **Yield from the right place.** Yielding from a callback that fires on an arbitrary thread is fine — the stream serialises delivery — but the values yielded must be `Sendable`.
- **Do not retain the continuation forever.** A continuation stored and never finished is a leak and a hang: the consumer never completes, and the producer's resources are never released.

---

## 5. MainActor Discipline

The MainActor is the serial executor for interface work. Discipline around it is what keeps an app responsive.

### 5.1 The rules

- **Interface state is MainActor-isolated.** Views, view models that drive views, and the state they display live on the MainActor. This is the guarantee that the interface is never updated from a background thread.
- **Non-interface work is not MainActor-isolated.** A type marked `@MainActor` because it touches the interface once drags all of its work onto the main thread. Isolate the interface state, not the whole type: keep the model off the MainActor and hop in only to publish results.
- **Hop explicitly, at the boundary.** When background work produces a result for the interface, hop to the MainActor once, with the complete result — not once per value, not per intermediate step. Each hop is a scheduling cost and a potential interleaving point.
- **Never block the MainActor.** No synchronous I/O, no locks that a background thread might hold, no `await` on work that needs the MainActor to complete (a deadlock: the MainActor waits for work that waits for the MainActor).
- **`@MainActor` on a whole type is a design decision, not a default.** It is correct for a view model whose entire job is driving a view. It is wrong for a service, a store, or a coordinator that does background work and occasionally updates the interface.

### 5.2 Common failures

- **Main-thread blocking disguised as async.** An `async` function on the MainActor that calls a synchronous blocking API. It suspends nothing; it blocks the interface.
- **The scattered hop.** `await MainActor.run` sprinkled through business logic, each one a place where state can change between hops. Collect the result, hop once, apply it.
- **The assumption of MainActor.** Code that updates interface state without being MainActor-isolated, relying on "it is always called from the main thread". That is an assumption, not a guarantee — and it breaks the first time a new caller arrives from a background task. Make the isolation explicit.

---

## 6. Structured vs Unstructured Tasks

- **Structured tasks have a parent.** `TaskGroup`, `async let`, and child tasks created with `Task { }` inside an async context inherit cancellation, priority, and actor context from their parent. When the parent is cancelled, they are cancelled. When the parent completes, they have completed.
- **`Task.detached` has no parent.** It inherits nothing: no cancellation, no priority, no actor isolation. It is the right tool only for genuinely independent background work — work that must continue even if its creator is cancelled. Every detached task needs a written reason for being detached.
- **Fire-and-forget is a bug shape.** A task created and never awaited, never stored, never cancelled. Its errors are lost, its lifetime is unbounded, its results go nowhere. If the work matters, await it; if it does not matter, do not start it.
- **Task-local values are for context, not for state.** Values propagated through the task tree (a request ID, a trace context) are fine as task-locals. Mutable state passed through task-locals is a race with a nicer name.

---

## 7. Failure Cases and Pitfalls

- **The race the compiler cannot see.** `@unchecked Sendable`, Objective-C interop, shared mutable globals, unsafe pointers. These bypass checking; they need the same discipline as checked code, with more care.
- **Actor re-entrancy.** Checking a condition, awaiting, then acting on the stale condition. Re-check after every `await`.
- **The logical race through an actor.** Read-compute-write split across two actor calls. Make it one actor method.
- **Priority inversion through the MainActor.** Background work that awaits MainActor-isolated state, while the MainActor waits for the background work. Neither progresses.
- **Task explosion.** Unbounded `TaskGroup` children or unbounded detached tasks under load. Bound the concurrency.
- **The non-cancellable loop.** A loop that never awaits and never checks cancellation. It runs until it finishes, regardless of what was asked.
- **Testing concurrency by running it once.** A race that does not appear in one run is not absent. Stress tests, repeated runs, and the Thread Sanitizer are the evidence.

---

## 8. Verification Steps

Before claiming Swift concurrent code is correct:

1. Every type crossing a concurrency boundary is `Sendable` by construction, or its `@unchecked Sendable` has a written justification and a synchronisation mechanism.
2. Every actor's methods are short and non-blocking; every read-compute-write that must be atomic is a single actor method; every condition is re-checked after an `await`.
3. Parallel work uses `TaskGroup` or `async let` with bounded concurrency; no unstructured task escapes its creating scope without a written reason.
4. Every long-running unit of work checks cancellation and cleans up when cancelled.
5. MainActor isolation covers interface state only; background work hops to the MainActor once, with the complete result.
6. The Thread Sanitizer has been run over the affected flows, and the tests have been run repeatedly (at least 20 runs) without a flake.
7. The full test suite passes, including any new concurrency or stress test.

## 9. Related Assets

- `ConcurrencyAsyncSystems.md` — races, deadlocks, cancellation, and structured concurrency in general.
- `SwiftUsage.md` — Swift patterns, value types, and protocol design.
- `MemoryResourceLifecycle.md` — tasks and subscriptions that outlive their owners.
- `PerformanceProfiling.md` — actor-hop overhead and main-thread blocking found by profiling.
