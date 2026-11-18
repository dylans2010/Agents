<!-- system-index-depends: BuildAndTesting.md, ErrorHandling.md -->

# Complex Debugging — Root-Cause Analysis, Reproduction, and Flaky-Failure Triage

Practical guidance for diagnosing failures that are not obvious: reproducing them reliably, narrowing the cause by bisection and hypothesis testing, reading logs and traces as evidence, and triaging failures that only happen sometimes. This asset governs **how to find the real cause**; `BuildAndTesting.md` governs running builds and tests, and `ErrorHandling.md` governs how errors should be surfaced once found.

---

## 0. Scope and Purpose

Simple bugs announce themselves: a compiler error, a crash with a clear stack trace, a test naming the broken assertion. Complex bugs do not. They reproduce intermittently, depend on state built up over time, span process or thread boundaries, or manifest far from their cause. Debugging those requires method, not intuition — a sequence that converts a symptom into a verified root cause.

Use this asset when:

- A failure cannot be reproduced on demand.
- The symptom and the cause are in different modules, threads, or processes.
- A fix has been attempted and the failure returned.
- A test or a build fails only sometimes.

Never "fix" a complex bug by changing code until the symptom disappears. A fix without a reproduced cause is a guess that will regress.

---

## 1. The Core Rules

- **Reproduce before you repair.** No reproduction, no fix. If it cannot be reproduced, the investigation is not finished — the reproduction is the investigation.
- **One variable at a time.** Change one thing, observe, record. Changing three things and seeing improvement proves nothing about which change mattered.
- **Hypotheses are cheap; evidence is the currency.** State the hypothesis, state what evidence would confirm or refute it, then go get that evidence. A hypothesis without a discriminating test is a story.
- **The bug is in the code you have not read yet.** The code you have already verified is innocent until the evidence moves. Do not re-read the same file hoping for a different result.
- **Write the timeline down.** What happened, in what order, with what state. Most complex bugs become obvious once the sequence is written out.

---

## 2. Methodology: Reproduction

### 2.1 Make it deterministic

- **Capture the exact conditions.** Input, environment, configuration, prior state, sequence of preceding actions. A reproduction that omits prior state is not a reproduction.
- **Shrink the input.** Remove data, steps, and configuration until the failure disappears, then add back the last removed piece. The minimal reproduction is the smallest input that still fails — it usually points straight at the cause.
- **Remove time.** If the failure depends on timing, replace waits and races with controlled sequencing in a test harness. A race that can be forced deterministically is a race that can be fixed and verified.
- **Automate the reproduction.** A script or test that triggers the failure on demand is the single most valuable artefact of a debugging session. It becomes the regression test.

### 2.2 When it will not reproduce

- **Check for hidden state.** Caches, persisted settings, keychain entries, files left by earlier runs, server-side state. Reset them one at a time.
- **Check for environment differences.** OS version, build configuration (debug vs release optimisations change timing and expose different bugs), locale, timezone, network conditions.
- **Check for ordering.** Run the failing sequence twice in the same process. Run it after a different preceding sequence. Order-dependent failures point at shared mutable state.
- **Add observation, not changes.** Logging, tracing, and breakpoints that record state without altering behaviour. If adding observation makes the failure vanish, the failure is timing-sensitive — see section 5.

---

## 3. Methodology: Narrowing by Bisection

When the cause is somewhere in a large space — a range of commits, a range of inputs, a set of modules — bisect:

1. **Define the predicate.** A yes/no test: "does this commit fail", "does this input fail", "does this module's presence cause the failure". The predicate must be runnable quickly and give a clean answer.
2. **Find a known-good and a known-bad point.** A commit that passed and a commit that fails; an input that works and one that does not.
3. **Halve the space.** Test the midpoint. The answer tells you which half contains the cause. Repeat until one commit, one input element, or one module remains.
4. **Verify the boundary.** Confirm the good side passes and the bad side fails, then inspect the single remaining difference. The cause is in that difference — or in its interaction with something else, which is the next hypothesis.

Bisection works on commits (`git bisect`, see `GitHistoryForensics.md`), on inputs (delta debugging), and on code (disable half the suspects). The discipline is the same: a clean predicate and a halving step.

---

## 4. Hypothesis Testing

A debugging session is a sequence of hypotheses. Run them properly:

1. **State it precisely.** "The crash happens because the delegate is nil when the callback fires" — not "something with the delegate".
2. **State the discriminating evidence.** "If the hypothesis is true, the log will show the callback firing after deallocation. If false, the delegate will be non-nil at the crash."
3. **Get the evidence with the cheapest experiment.** A log line, a breakpoint condition, a targeted unit test — before a refactor, before a rewrite.
4. **Record the outcome.** Confirmed, refuted, or inconclusive. A refuted hypothesis is progress: it eliminates a branch. An unrecorded one gets re-tested an hour later.

Common hypothesis families, in the order they should be eliminated:

- **Wrong input.** The caller passed bad data; the callee is innocent. Check the call site first.
- **Wrong state.** The object was in a state its methods did not expect (not initialised, already torn down, mid-migration). Check lifecycle.
- **Wrong assumptions about the platform.** An API that behaves differently on this OS version, in this configuration, or under these permissions. Check the platform documentation against the actual call.
- **Concurrency.** A race, a deadlock, a callback on the wrong executor. Check thread and actor context at the failure point.
- **Resource exhaustion.** Memory, file descriptors, disk, network. Check the resource, not the code that happened to run out of it.

---

## 5. Log and Trace Analysis

Logs and traces are evidence, not narrative. Read them as a timeline:

- **Anchor on the failure.** Find the exact failure line (crash, assertion, error) and read backwards. The cause precedes the symptom; the lines after it are consequences.
- **Look for the first anomaly, not the loudest.** The first unexpected value, the first out-of-order event, the first retry. Later noise is usually fallout.
- **Correlate across sources.** A client log, a server log, and a system trace each tell part of the story. Align them by timestamp before drawing conclusions. Clock skew between machines is a real source of false conclusions — verify synchronisation.
- **Absence is evidence.** An expected log line that never appears means the code path never ran. An expected callback that never fired means the registration, the trigger, or the delivery failed.
- **Do not trust a single run.** One trace shows what happened once. Compare a failing trace against a passing trace of the same flow; the difference between them is the investigation.

---

## 6. Flaky-Failure Triage

A flaky test or flaky behaviour fails sometimes and passes sometimes with no code change. Triage in this order:

1. **Is it order-dependent?** Run it alone; run it in a different position in the suite; run the suite twice. Order dependence means shared mutable state — a singleton, a global, a file, a database.
2. **Is it timing-dependent?** Run it under load; run it on a slower machine; run it a hundred times. Timing dependence means a race, a sleep used as synchronisation, or an assumption about scheduling.
3. **Is it resource-dependent?** Run it with other tests in parallel; run it with a full disk or a slow network. Resource dependence means a leak, a quota, or contention.
4. **Is it time-dependent?** Run it at a different hour, date, or timezone. Time dependence means a date, a timeout, a token expiry, or a cache TTL.
5. **Is it environment-dependent?** Run it on a different machine, OS version, or configuration. Environment dependence means an undeclared assumption about the world.

For each candidate, the fix is to remove the dependence, not to increase a timeout or add a retry. A retry that masks a race is a race that will return in production, where there is no retry.

**Flaky-test policy:** a flaky test is quarantined (skipped with a tracked issue and a reproduction) — never deleted silently, never left failing in the suite where it trains everyone to ignore failures. See `TestingStrategy.md`.

---

## 7. Failure Cases and Pitfalls

- **Fixing the symptom.** The crash goes away because a nil is now guarded, but the object is still deallocated too early. The next symptom will be different and harder to find.
- **The coincidental fix.** A change that makes the failure disappear without explaining it. Treat it as unproven: the reproduction test must fail before the fix and pass after, or the fix is not verified.
- **Debugging by printf in production code.** Temporary logging committed by accident, or left in because "it might help". Observation code is removed before the fix lands.
- **Chasing the last error.** In a cascade, the first error causes the rest. Fix the first; re-run; see what remains.
- **Assuming the new code is guilty.** A failure that appears after a change may be caused by the change exposing a pre-existing defect — or by the change itself. Bisect to find out; do not assume.
- **The Heisenbug trap.** The failure disappears under observation. That is information: the cause involves timing, optimisation, or uninitialised memory. Change the observation method (sampling profiler, post-mortem log, sanitiser) rather than declaring the bug gone.

---

## 8. Verification Steps

Before claiming a complex bug is fixed:

1. The reproduction (script or test) fails on the unfixed code and passes on the fixed code.
2. The root cause is stated in one or two sentences, naming the file, the state, and the sequence.
3. The fix addresses the cause, not the symptom — a reviewer can see why the failure cannot recur.
4. The full test suite passes, including the new regression test.
5. No observation or debugging code remains in the change.
6. If the bug was flaky, the reproduction has been run repeatedly (at least 20 runs, or 100 for a race) without failure.

## 9. Related Assets

- `GitHistoryForensics.md` — bisecting history to find the commit that introduced a failure.
- `ConcurrencyAsyncSystems.md` — diagnosing races, deadlocks, and cancellation bugs.
- `MemoryResourceLifecycle.md` — diagnosing leaks, cycles, and premature deallocation.
- `TestingStrategy.md` — turning a reproduction into a regression test that stays green.
