<!-- system-index-depends: BuildAndTesting.md, SwiftUsage.md -->

# Performance Profiling — Measurement First, Hotspots, Memory, CPU, Rendering, and Regressions

Practical guidance for making software faster by measuring first: finding real hotspots, distinguishing CPU, memory, and rendering costs, optimising what matters, and preventing regressions. This asset governs **how performance work is done**; `BuildAndTesting.md` governs running builds and tests, and `MemoryResourceLifecycle.md` governs the memory problems profiling often uncovers.

---

## 0. Scope and Purpose

Performance work fails in exactly one predictable way: optimising something that was never the bottleneck. A developer's intuition about where time goes is usually wrong — the hotspot is in the code nobody suspected, the cost is in a framework call that looks free, the "slow" feature is waiting on something else entirely. Profiling replaces intuition with measurement, and measurement is the whole discipline.

Use this asset when:

- Something feels slow and nobody knows why.
- A feature must meet a responsiveness or resource budget.
- A regression is suspected — something got slower and the cause is unknown.
- Before claiming an optimisation helped.

Do not use this asset to justify premature optimisation. Code that is fast enough does not need to be faster; the budget for optimisation is spent where measurement says it matters.

---

## 1. The Core Rules

- **Measure before you optimise.** No measurement, no optimisation. A change made without a baseline cannot be shown to help.
- **Measure in release configuration.** Debug builds disable optimisations, add checks, and change timing. A profile taken in debug mode measures the debug build, not the product.
- **Measure on the real device and the real data.** Simulator timing, synthetic data, and empty states all lie in different ways. The profile must reflect what users actually experience.
- **Optimise the hotspot, not the code you happen to be reading.** The hotspot is where the time is, even if it is in a framework, a dependency, or a line that looks innocent.
- **A regression is a bug.** A measurable slowdown introduced by a change is treated like any other regression: found, attributed, and fixed or explicitly accepted.

---

## 2. Methodology: The Profiling Pass

### Step 1 — Define the symptom precisely

"Slow" is not a symptom. Define it:

- **What operation?** Launch, a specific interaction, a background sync, a render pass.
- **How slow, measured how?** Wall-clock time, frames per second, time to first paint, time to interactive. With numbers, from a real run.
- **Under what conditions?** Data size, device, OS version, network state, battery state. Performance is conditional; the conditions are part of the measurement.

### Step 2 — Profile, do not guess

Use the platform profiler (Instruments on Apple platforms: Time Profiler, Allocations, Leaks, Core Animation / Metal System Trace). The workflow:

1. **Record a representative session.** Perform the slow operation the way a user would, with real data.
2. **Read the call tree by weight.** Sort by self time and total time. The top entries are the investigation, not the whole list.
3. **Follow the heaviest path.** Expand the heaviest branch until the cost lands on identifiable code — your code, a framework call, or a dependency.
4. **Classify the cost.** CPU-bound (computation), memory-bound (allocation, copying, paging), I/O-bound (disk, network), or waiting (locks, serial queues, main-thread blocking). Each class has different fixes; a CPU fix applied to a waiting problem changes nothing.

### Step 3 — Form a hypothesis and test it

State what you believe the cost is and what change would remove it. Make the smallest change that tests the hypothesis, re-profile under identical conditions, and compare numbers. If the number did not move, the hypothesis was wrong — record that and move on.

### Step 4 — Record the result

The before number, the after number, the conditions, and the change. An optimisation without a recorded measurement will be re-questioned, re-done, or reverted by someone who cannot tell whether it mattered.

---

## 3. Common Hotspot Families

- **Work on the main thread.** Anything that blocks the main thread blocks the interface: parsing, image decoding, database queries, synchronous network calls, heavy layout. The fix is moving the work off the main thread — or, better, not doing the work at all. A blocked main thread shows up as dropped frames and an unresponsive interface long before it shows up as CPU time.
- **Repeated work.** The same computation per frame, per cell, per keystroke. Caching, memoisation, and doing work once at the right layer fix this — but only after measurement proves the repetition is the cost.
- **Excess allocation.** Short-lived objects allocated in a hot loop: strings built by concatenation, arrays copied on mutation, value types passed by copy through deep call chains. Allocations show up in the Allocations instrument as churn; the fix is usually reuse, in-place mutation, or a different data structure — not a different allocator.
- **Copying large values.** Swift value semantics copy. Copying a large struct or array on every call is a real cost that looks like nothing in the source. Profile first; then consider references, copy-on-write types, or passing by borrowing where the language supports it.
- **Layout and rendering.** Expensive view hierarchies, views that invalidate layout repeatedly, images decoded at display size instead of decoded once, shadows and blurs on scrolling content. The rendering instruments show this directly — do not guess at it from the view code.
- **Synchronous I/O in a hot path.** Reading a file, a database, or user defaults inside a loop or a scroll handler. I/O latency dominates everything else in the path; move it out, cache it, or make it asynchronous.
- **Chatty cross-boundary calls.** Hundreds of small calls across a process, thread, or IPC boundary, each cheap alone and expensive together. Batch them.

---

## 4. Memory and CPU: What to Look At

- **CPU:** Time Profiler, sorted by self time. Look for the function that owns the time, not the function that happens to be on top of the stack when sampling catches it.
- **Memory footprint:** Allocations instrument, persistent bytes over time. A footprint that grows without bound during a session is a leak or an unbounded cache — see `MemoryResourceLifecycle.md`.
- **Memory churn:** Allocations and deallocations per second. High churn means the allocator and the ARC/autorelease machinery are doing constant work; it also pressures the memory system and the battery.
- **Rendering:** frame rate and frame time, hitch rate, offscreen rendering passes. A frame budget is 16.7 ms at 60 fps; work that exceeds it drops frames visibly.
- **Energy:** CPU wake-ups, network activity, and background work are energy costs. A feature that is fast but wakes the device constantly is a battery bug.

---

## 5. Optimisation Principles

- **Do less work.** The fastest code is code that does not run. Remove work before making work faster: skip invisible rendering, avoid redundant computation, lazy-load what is not needed yet.
- **Do work later or less often.** Defer, debounce, coalesce. A search that runs on every keystroke can run when typing pauses; a layout that runs per item can run once per batch.
- **Do work off the critical path.** Move it to a background queue, precompute it during idle time, or stream it so the user sees progress instead of waiting.
- **Choose the right structure.** An array scanned linearly, a dictionary keyed wrongly, a set rebuilt per lookup — data structure choice is the highest-leverage optimisation and the one most often missed.
- **Cache with a policy.** A cache without an eviction policy is a leak with a nicer name. Every cache needs a size bound, an invalidation rule, and a way to observe its hit rate.
- **Optimise for the common case, not the worst case.** The 99% path deserves the fast path; the 1% path can be slow, as long as it is correct.

---

## 6. Failure Cases and Pitfalls

- **Optimising the debug build.** Hours spent speeding up code that the optimiser would have handled in release. Always profile release.
- **Micro-benchmarks that lie.** A benchmark of a tiny function in isolation, with data that fits in cache and no real callers. It measures the benchmark, not the product.
- **The optimisation that changes behaviour.** A cache that returns stale data, a fast path that skips a validation, a parallelised loop that reorders results. Speed gained by changing semantics is a bug, not an optimisation.
- **Fixing the symptom metric.** Reducing CPU time by moving work to a background thread does not help if the user is still waiting for the result. The metric that matters is the user's experienced latency.
- **Regression by a thousand cuts.** No single change is measurably slower, but the product gets slower every release. This is why performance budgets and automated regression checks exist — see section 7.
- **Profiling once.** A profile is a snapshot of one build, one device, one dataset. Conclusions drawn from one snapshot rot as the code changes.

---

## 7. Preventing Regressions

- **Set a budget.** A number for the operations that matter: launch time, time to interactive, frame rate during scrolling, memory ceiling. A budget turns "feels slow" into a failing check.
- **Measure in CI where possible.** Automated performance tests that run the critical operations and compare against the budget. They are approximate and noisy — run them repeatedly and compare distributions, not single samples.
- **Profile before release.** A profiling pass on the release candidate, on a real device, with real data. Catches the regression that CI's synthetic workload missed.
- **Attribute regressions to commits.** When a regression is found, bisect it like any other bug (see `ComplexDebugging.md` and `GitHistoryForensics.md`). "Something got slower" is a bug report with a findable cause.

---

## 8. Verification Steps

Before claiming a performance improvement:

1. The symptom is defined with numbers, conditions, and a measurement method.
2. A baseline profile exists, taken in release configuration on a real device with real data.
3. The hotspot was identified from the profile, and the cost was classified (CPU, memory, I/O, waiting).
4. The change was re-profiled under identical conditions and the number improved by a margin larger than run-to-run noise.
5. The full test suite passes — the optimisation did not change behaviour.
6. The before/after numbers, conditions, and change are recorded.

## 9. Related Assets

- `MemoryResourceLifecycle.md` — leaks, cycles, and unbounded growth found by profiling.
- `ConcurrencyAsyncSystems.md` — main-thread blocking and background work.
- `ComplexDebugging.md` — bisecting a performance regression to its commit.
- `DependencyAuditing.md` — when the hotspot is inside a dependency.
