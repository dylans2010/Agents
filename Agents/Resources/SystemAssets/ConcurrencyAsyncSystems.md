<!-- system-index-depends: SwiftUsage.md, ErrorHandling.md -->

# Concurrency and Async Systems — Actors, Races, Deadlocks, Cancellation, and Structured Concurrency

Practical guidance for reasoning about concurrent and asynchronous systems: where races come from, how actors and structured concurrency prevent them, how deadlocks and cancellation failures happen, and how to design async work that is correct under real scheduling. This asset governs **concurrency design and diagnosis**; `AdvancedSwiftConcurrency.md` governs Swift-specific concurrency mechanics, and `SwiftUsage.md` governs the language patterns underneath.

---

## 0. Scope and Purpose

Concurrency bugs are the hardest class of defect in ordinary software: they depend on timing, they disappear under observation, they manifest far from their cause, and they are often unreproducible on demand. The defence is not cleverness — it is structure. Code whose concurrency is structured (bounded lifetimes, explicit ownership, single-owner state) has a small space of possible interleavings; code whose concurrency is ad hoc has an unbounded one.

Use this asset when:

- Designing work that runs on more than one thread, queue, or task.
- Diagnosing a race, a deadlock, a hang, or a result that arrives on the wrong thread.
- Reviewing async code for correctness.
- Deciding how cancellation and timeouts should behave.

Do not use this asset to justify making everything asynchronous. Synchronous code that runs on the right thread is simpler and often faster; concurrency is a tool for responsiveness and parallelism, not a default.

---

## 1. The Core Rules

- **Shared mutable state has exactly one owner.** State is owned by one actor, one serial queue, or one thread. Everyone else reaches it through that owner. Two writers with no owner is a race by definition.
- **Structure beats discipline.** Structured concurrency (a task tree with a defined lifetime) is verifiable; unstructured spawning (`Task.detached`, fire-and-forget, bare threads) is a promise that someone will remember to clean up. Prefer the structure.
- **Cancellation is a contract, not a suggestion.** Work that cannot be cancelled will run after its result is useless, hold resources after its owner is gone, and deliver results to a dead context. Every long-running unit of work must respond to cancellation.
- **Never block a thread waiting for async work.** Blocking a thread to wait for a task, a semaphore, or a lock that an async continuation must release is a deadlock waiting for the right schedule.
- **The main thread is for the interface.** It renders, handles input, and coordinates. It does not parse, decode, query, or wait on the network. Anything that can take more than a frame belongs elsewhere.

---

## 2. Races: Where They Come From and How to Prevent Them

A race is two accesses to the same mutable state, at least one a write, with no ordering between them. The result depends on scheduling, so it varies run to run — which is why races are flaky and why "it works on my machine" is meaningless for them.

### 2.1 Common race shapes

- **Check-then-act.** Checking a condition and then acting on it, with another writer in between: "if not cached, fetch and store" executed twice stores twice, or returns two different values.
- **Read-modify-write.** Reading a value, computing, writing it back — a counter, a flag, a collection append — with another writer interleaving. The interleaved write is lost.
- **Publication.** One thread writes a value, another reads it, with no synchronisation establishing that the write is visible. The reader sees a stale value, or a partially-constructed object.
- **Callback on the wrong executor.** A completion handler that mutates UI state from a background thread, or mutates shared state from whatever thread the framework happened to use.
- **Mutable capture.** A closure that captures a mutable variable and runs on two threads, or runs after the variable's owner has moved on.

### Example: the check-then-act race, as an interleaving

Two tasks ask a cache for the same note at the same time. Each checks, finds nothing, loads, and stores — and the second store overwrites the first:

```swift
actor NoteCache {
    private var cached: [String: Note] = [:]

    func note(for id: String) async -> Note {
        if let found = cached[id] {
            return found
        }
        let loaded = await loadFromDisk(id: id)
        cached[id] = loaded
        return loaded
    }
}
```

The actor serialises each individual access, but the sequence is not atomic: while the first task awaits the disk load, the second task enters the actor and runs the same check. The interleaving:

```text
Task A: checks cache, misses
Task B: checks cache, misses
Task A: awaits loadFromDisk, suspends
Task B: awaits loadFromDisk, suspends
Task A: resumes, stores its copy, returns
Task B: resumes, stores its copy, overwrites
```

The fix is to make the check and the store one atomic unit inside the actor: keep the in-flight load in the actor's state before awaiting, so the second caller finds the in-flight load and awaits the same result instead of starting a second one. The actor did not fail — the code asked it to protect two separate accesses and expected it to protect the sequence between them.

### 2.2 Prevention

- **Give the state an owner.** An actor, a serial queue, a lock — one mechanism, applied consistently, for all access to that state. Mixed mechanisms (sometimes the actor, sometimes a direct access) are worse than none, because they create the illusion of safety.
- **Make state immutable where possible.** Immutable values cannot race. Prefer value types, `let` bindings, and data passed by copy across boundaries.
- **Copy at the boundary.** When data crosses a thread or actor boundary, pass a copy or an immutable snapshot. Sharing a mutable reference across the boundary reintroduces the race the boundary was supposed to prevent.
- **Use the compiler.** Swift's actor isolation and `Sendable` checking exist to catch races statically. Code that fights the compiler with unchecked conformances or force-unwrapped isolation is hiding the race, not fixing it. See `AdvancedSwiftConcurrency.md`.

---

## 3. Deadlocks

A deadlock is a cycle of waits: A waits for B, B waits for A, and nothing proceeds. The program hangs, silently, with no error.

### 3.1 Common deadlock shapes

- **Lock ordering.** Two locks acquired in different orders on different paths. Path one takes lock X then lock Y; path two takes Y then X. Under the wrong interleaving, each holds one and waits for the other.
- **Re-entrancy.** A lock that is not re-entrant, acquired twice on the same thread — a method that takes a lock and calls another method that takes the same lock.
- **Main-thread wait.** The main thread blocks waiting for work that must run on the main thread to complete. The classic form: a synchronous dispatch to the main queue from the main queue, or a semaphore waited on by the thread whose work would signal it.
- **Actor re-entrancy deadlock (logical).** An actor method awaits another actor, which awaits the first. No thread is blocked, but no progress is made — a deadlock in the task graph rather than in the threads.

### 3.2 Prevention

- **One lock per resource, acquired in a fixed global order.** If two locks are ever held together, their acquisition order is the same everywhere. Document the order.
- **Never hold a lock while calling out.** A lock held across a call to unknown code (a delegate, a closure, another module) can re-enter or block indefinitely. Copy what is needed, release the lock, then call.
- **Never block waiting for async work.** Use `await`, not a semaphore or a blocking wait, to join async work. Blocking a thread to wait for a task that needs that thread is the deadlock.
- **Keep critical sections short and non-blocking.** A critical section does the minimal work: read, compute, write. It does not do I/O, does not call out, does not await.

---

## 4. Cancellation

Cancellation is how a system stops work that is no longer wanted: a user navigated away, a newer request superseded an older one, the app is terminating. Work that ignores cancellation keeps running, keeps holding resources, and delivers stale results.

### 4.1 The contract

- **Every unit of async work is cancellable.** If a task, operation, or request cannot be cancelled, it must be short — short enough that running to completion after its result is useless is harmless.
- **Check cancellation at the right points.** Before starting an expensive step, after each `await`, and inside loops. A task that checks cancellation once at the start and then runs for ten seconds is not cancellable in any meaningful sense.
- **Cancellation propagates down.** Cancelling a parent cancels its children. A child that spawns unstructured work escapes the tree and escapes cancellation — which is why unstructured spawning is dangerous.
- **Cleanup runs on cancellation.** Files closed, partial results discarded, UI state restored. Cancellation is not an error path to skip; it is a normal outcome with its own cleanup.
- **Distinguish cancellation from failure.** A cancelled task is not a failed task. It should not log an error, show an alert, or retry. Treating cancellation as failure produces error noise and spurious retries.

### 4.2 Common cancellation failures

- **The fire-and-forget task.** Spawned, never stored, never cancelled. It outlives its owner and delivers results into a dead context.
- **The superseded request.** A new request starts before the old one is cancelled. Both complete; the older result arrives last and overwrites the newer one. Fix by cancelling the previous task before starting the next, and by ignoring results from a cancelled task.
- **The non-cooperative loop.** A loop that never awaits and never checks cancellation. It runs until it finishes, regardless of what the user or the system asked.
- **Cancellation that leaks.** A cancelled task that leaves a subscription, a file handle, or a network connection open. Cleanup belongs in `defer` or in the task's teardown, not in the success path.

---

## 5. Structured Concurrency

Structured concurrency means every task has a parent, a defined lifetime, and a defined place where its result or error is collected:

- **A task tree, not a task soup.** Child tasks are created by a parent (`TaskGroup`, `async let`), complete before the parent completes, and their errors propagate to the parent. There is no orphaned work.
- **Errors propagate, they do not vanish.** A child that throws reports to the parent. A fire-and-forget task that throws has nowhere to report — the error is lost, silently.
- **Scope defines lifetime.** When the scope exits, the work is done or cancelled. Work that must outlive a scope is a deliberate, documented exception — a background service with an explicit lifetime, not an accident.
- **Prefer `TaskGroup` and `async let` over `Task.detached`.** Detached tasks inherit nothing — no cancellation, no priority, no actor context — and are the most common source of orphaned work. Use them only for genuinely independent background computation.

---

## 6. Queues, Threads, and Executors

- **Serial queues serialize.** A serial queue is a simple, effective owner for shared state — but every access must go through it, and blocking it blocks all of its work.
- **Concurrent queues do not serialize.** A concurrent queue with a barrier for writes is a read-write lock by another name; a concurrent queue without a barrier is no protection at all.
- **The main actor is a serial executor.** Main-actor-isolated state is safe from races — and slow if abused, because every access serialises through the main thread. Keep main-actor work small and interface-related.
- **Do not assume a thread.** A task may resume on a different thread after an `await`. Code that assumes thread identity across an await is wrong. Actor isolation, not thread identity, is the guarantee.
- **Priority is a hint, not a guarantee.** Do not build correctness on the assumption that a high-priority task runs first. Build it on structure.

---

## 7. Failure Cases and Pitfalls

- **"It works in testing."** Races and deadlocks depend on scheduling; a test run that passes proves the schedule was favourable, not that the code is correct. Stress tests, thread sanitisers, and repeated runs are the evidence — see `TestingStrategy.md`.
- **The data race that the compiler cannot see.** Unsafe code, Objective-C interop, shared mutable globals, and `@unchecked Sendable` all bypass static checking. They need the same discipline as checked code, with more care, not less.
- **Locking around the wrong thing.** A lock that protects the container but not the elements, or that is taken for the read but not for the write. The protected unit is the invariant, not the variable.
- **The "temporary" global.** A global introduced for convenience, mutated from two threads. It will race. Give it an owner or make it immutable.
- **Async code that is secretly synchronous.** An `async` function that blocks a thread internally (a synchronous network call, a lock, a sleep). It occupies a thread from the cooperative pool and starves other tasks. Async functions must actually suspend.
- **Thread explosion.** Unbounded creation of threads or tasks under load. Each one costs memory and scheduling overhead; under pressure the system spends more time scheduling than working. Bound concurrency with a group, a semaphore, or a limited executor.

---

## 8. Verification Steps

Before claiming concurrent code is correct:

1. Every piece of shared mutable state has a named owner (actor, serial queue, or lock) and every access goes through it.
2. No unstructured task escapes the scope that created it; every `Task.detached` has a written justification.
3. Every long-running unit of work checks cancellation at each step and cleans up when cancelled.
4. No thread blocks waiting for async work; no lock is held across a call to unknown code.
5. The Thread Sanitizer (or equivalent) has been run over the affected flows, and the tests have been run repeatedly (at least 20 runs) without a flake.
6. The full test suite passes, including any new stress or concurrency test.

## 9. Related Assets

- `AdvancedSwiftConcurrency.md` — Swift actors, `Sendable`, `TaskGroup`, async sequences, MainActor discipline.
- `MemoryResourceLifecycle.md` — tasks and subscriptions that outlive their owners.
- `ComplexDebugging.md` — diagnosing a race or deadlock that only appears sometimes.
- `PerformanceProfiling.md` — main-thread blocking and thread explosion found by profiling.
