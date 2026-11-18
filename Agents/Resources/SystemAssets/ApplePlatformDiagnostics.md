<!-- system-index-depends: BuildAndTesting.md, ErrorHandling.md -->
# ApplePlatformDiagnostics.md — Apple Platform Diagnostics

Authoritative guidance for diagnosing macOS applications: unified logging, crash reports, Instruments, Console, and sysdiagnose. Diagnostics exist to turn "it crashed" and "it feels slow" into a reproducible cause with evidence. Never ship a fix for a symptom you cannot reproduce and measure.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Diagnostics work must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If a diagnostic capture fails or a report is unsymbolicated, diagnose the capture pipeline, formulate an alternative, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions. Never log secrets, tokens, credentials, or user content beyond what is needed to diagnose.
- **Evidence before fixes:** A fix without a reproducing capture is a guess. Capture first, then fix, then re-capture to prove the fix.

---

## 1. Unified Logging (os.Logger)

- **Use `os.Logger`, not print:** `Logger(subsystem:category:)` gives levels, privacy, persistence, and Console filtering. `print` output is unstructured and invisible in release builds.
- **Levels mean something:** `.debug` for development detail, `.info` for normal milestones, `.notice` for notable but expected events, `.error` for failures the user can recover from, `.fault` for bugs that corrupt state. A log full of `.fault` entries that are not faults trains everyone to ignore real faults.
- **Privacy by default:** Interpolated values are private unless marked `.public`. Never mark secrets, tokens, file contents, or user messages public. Log identifiers and counts; log content only when the user explicitly consents and the content is needed.
- **Subsystem and category discipline:** One subsystem per app or framework, one category per component (network, persistence, agent loop, UI). A single catch-all category makes Console filtering useless.
- **Signposts for performance:** `os_signpost` marks intervals (a request, a render, an index build). Signposts appear in Instruments as intervals with durations — the fastest way to find where time goes.
- **Log sparingly on hot paths:** Logging on every frame or every keystroke costs time and floods the log. Sample, aggregate, or log on state change only.

---

## 2. Crash Reports

- **Read the report, not the rumor:** A crash report names the crashing thread, the exception or signal, and the faulting frame. Start there; do not start from a user's paraphrase.
- **Exception vs signal:** An `EXC_BAD_ACCESS` is a memory error (dangling pointer, over-release, use-after-free). An `EXC_BREAKPOINT` in Swift is usually a failed precondition, a force unwrap, or a `fatalError`. A `SIGABRT` is often an uncaught exception or a failed assertion. The type narrows the search before any code is read.
- **Symbolicate before reading:** An unsymbolicated report shows addresses, not function names. Symbolication needs the matching dSYM for the exact build. Archive builds with dSYMs and keep them; a crash without its dSYM is nearly undiagnosable.
- **The crashing thread is the symptom; the cause may be another thread:** A main-thread crash can be caused by a background thread corrupting shared state. Read all threads, especially ones holding the same lock or touching the same object.
- **MetricKit for field crashes:** `MXCrashDiagnostic` delivers crash reports from the field with stack traces. Integrate it and treat its reports as the primary source for crashes users never report.
- **Reproduce before fixing:** A fix for a crash that was never reproduced is unverified. Write the reproducing steps (or a test that triggers the same path) before changing code.

---

## 3. Instruments

- **Time Profiler for slowness:** Sample the app under the slow workload. The heaviest stack is where the time goes; optimize that, not the function that looks slow in source.
- **Allocations for memory growth:** Track persistent allocations over time. A graph that climbs without falling is a leak or an unbounded cache. The responsible stack is in the allocation backtrace.
- **Leaks for retain cycles:** Run the Leaks instrument after a workflow (open, use, close a window). Leaked objects at the end are retain cycles or missing dismantles.
- **SwiftUI instrument for view churn:** Excessive `body` evaluations and view updates show up here. A view whose body runs on every keystroke in an unrelated field has a state-ownership problem (see `NativeMacSwiftUIArchitecture.md`).
- **File Activity for disk churn:** Unexpected reads/writes (repeated full-file rewrites, cache thrash) show up as file activity. Disk work on the main thread shows up as a hang.
- **Profile release builds:** Debug builds have different optimization and different performance characteristics. A Time Profiler run on a debug build measures the debug build, not the product.

---

## 4. Console, Sample, and Sysdiagnose

- **Console.app is the log reader:** Filter by subsystem and category; search by identifier; watch live while reproducing. Console shows the unified log for the whole system, so filter aggressively or the app's entries drown.
- **`sample` for hangs:** When the app beachballs, `sample <pid>` captures what every thread is doing. A hang is a thread waiting — on a lock, on disk, on the network — and the sample names what it waits for.
- **`spindump` for system-wide hangs:** When the whole system stalls, `spindump` captures all processes. Use it when the app's hang involves another process (a helper, a daemon, the window server).
- **`sysdiagnose` for the full picture:** `sysdiagnose` collects logs, crash reports, spindumps, and system state into one bundle. Request it when the problem spans processes or when the reproduction is intermittent and the next occurrence must be captured in full.
- **Reproduce under capture:** Start the capture, reproduce the problem, stop the capture. A log that starts after the problem is a log of nothing.

---

## 5. Methodology — Diagnosing a Report

1. **Classify:** Crash, hang, slowness, wrong behavior, or resource growth? The class determines the tool.
2. **Reproduce:** Find the minimal steps. If it cannot be reproduced, capture the next occurrence with logging and signposts already in place.
3. **Capture:** Crash report, sample, Time Profiler trace, or Console log — whichever matches the class. Capture the exact build.
4. **Narrow:** From the capture, name the failing component, the failing input, and the failing state. A diagnosis that cannot name all three is incomplete.
5. **Fix at the root cause:** Not at the symptom. A crash in a force unwrap is fixed by removing the impossible state, not by adding a nil check that hides it.
6. **Verify with the same capture:** Re-run the same reproduction under the same tool. The fault must be gone, not moved.

---

## 6. Failure Cases and Pitfalls

- **Logging secrets:** A token or file content marked public in a log ships to every diagnostic bundle. Fix: default-private interpolation, review every public value.
- **Missing dSYMs:** A crash arrives and the dSYM for that build was never archived. Fix: archive dSYMs with every release build, automated.
- **Reading an unsymbolicated report as fact:** Addresses that look like function names mislead. Fix: symbolicate first, read second.
- **Profiling a debug build:** Optimizations off, assertions on — the trace measures a different program. Fix: profile release builds.
- **Fixing the crashing thread, ignoring the corrupting thread:** The main thread crashed because a background thread corrupted shared state. Fix: read all threads, fix the corruption.
- **Log flooding:** Debug logging on a hot path costs more time than the code being measured. Fix: sample or aggregate.
- **One-off reproduction:** A fix verified once, by hand, on a different build. Fix: a repeatable reproduction and a regression test on the same build.
- **Ignoring field crashes:** Only crashes users report get fixed. Fix: MetricKit integration and a regular review of field diagnostics.

---

## 7. Verification Steps

1. **Logging audit:** Every subsystem/category is declared; no secrets in logs; levels are used correctly.
2. **Crash readiness:** dSYMs are archived for the current build; MetricKit is integrated; a test crash symbolicates correctly.
3. **Reproduction:** The reported problem reproduces on demand with written steps.
4. **Instrumented run:** Time Profiler (for slowness), Allocations/Leaks (for memory), SwiftUI instrument (for view churn) — run on a release build, under the reproducing workload.
5. **Fix verification:** The same reproduction under the same instrument shows the fault gone.
6. **Regression test:** A test covers the failing path so the fault cannot return silently.
7. **Field check:** After release, field diagnostics show the crash or hang signature absent.
