<!-- system-index-depends: BuildAndTesting.md, CodeReviewSystemAsset.md -->

# Testing Strategy — What to Test, Meaningful Tests, Flaky Tests, and Coverage Traps

Practical guidance for building a test suite that actually protects a product: what deserves a test, what makes a test meaningful, how flaky tests are handled, and why coverage numbers mislead. This asset governs **testing judgement**; `BuildAndTesting.md` governs running builds and tests, and `SafeLegacyRefactoring.md` governs characterisation tests written before a refactor.

---

## 0. Scope and Purpose

A test suite is not a number. It is a safety net with a specific job: to catch regressions before users do, and to let developers change code with confidence. A suite that is slow, flaky, or full of tests that assert nothing will be ignored — and a suite that is ignored protects nothing. Strategy is the difference between a suite that earns trust and a suite that is cargo-culted.

Use this asset when:

- Deciding what to test for a new feature or a fix.
- Reviewing a test that seems weak, brittle, or meaningless.
- Triaging a flaky test.
- Evaluating whether a coverage number means anything.

Do not use this asset to justify testing everything. Testing everything is unaffordable; testing the right things is the skill.

---

## 1. The Core Rules

- **Test behaviour, not implementation.** A test that asserts how the code works breaks when the code is refactored; a test that asserts what the code does survives. Test through public interfaces.
- **A test must be able to fail.** A test that passes regardless of what the code does is not a test — it is a ritual. Verify a new test by breaking the code it guards and watching it fail.
- **Tests are code.** They are read, maintained, and refactored like production code. A test that nobody understands will be deleted at the first inconvenience.
- **Fast tests run; slow tests are skipped.** A suite that takes an hour will be run rarely, and a suite run rarely catches regressions late. Keep the fast suite fast; move slow tests to a separate tier.
- **A red suite is an emergency.** A suite that is allowed to stay red trains everyone to ignore it. Fix it, quarantine the failing test, or revert — the same day.

---

## 2. What to Test

### 2.1 The priority order

1. **Regressions.** Every bug fix lands with a test that fails without the fix and passes with it. This is non-negotiable: the bug has already proven it can happen once, and the test is what stops it happening twice.
2. **Public contracts.** The promises an API makes: inputs, outputs, errors, edge cases. If a caller can depend on it, a test pins it. See `ApiDesignCompatibility.md`.
3. **Business rules and invariants.** The logic that, if wrong, produces wrong results silently: calculations, permissions, state transitions, data transformations. Silent wrongness is worse than a crash — it ships.
4. **Failure paths.** Errors, timeouts, malformed input, missing resources. The happy path is the least interesting path; the failure paths are where the product breaks in production.
5. **Concurrency and lifecycle.** Cancellation, races, teardown, resource release — the behaviours that are hardest to verify by reading. See `ConcurrencyAsyncSystems.md` and `MemoryResourceLifecycle.md`.

### 2.2 What not to test

- **Trivial code.** A getter that returns a stored property, a function that forwards to another function. The test adds maintenance cost and no information.
- **The framework.** Do not test that the platform's APIs work. Test that your code uses them correctly.
- **Implementation details.** Private methods, internal state, call counts to a mock. These tests break on every refactor and teach the team to dread refactoring.
- **Everything, uniformly.** Uniform coverage targets produce uniform mediocrity: trivial code tested to 100% and critical logic tested to 40%. Allocate testing effort by risk, not by file.

---

## 3. What Makes a Test Meaningful

A meaningful test has these properties:

- **Independent.** It does not depend on another test having run, on execution order, or on shared mutable state. It can run alone, in any order, in parallel.
- **Deterministic.** Same code, same result, every run. No sleeps as synchronisation, no dependence on wall-clock time, no dependence on network or filesystem state it does not control.
- **Fast.** Milliseconds, not seconds. A test that takes seconds is a test that will be avoided.
- **Clear about what it proves.** The test name states the behaviour: `testSavingAnEmptyDocumentProducesAnEmptyFile`, not `testSave2`. A failing test should tell the reader what broke without opening the test body.
- **Minimal.** It sets up only what the behaviour needs. A test with fifty lines of setup is testing the setup, and it will break when the setup changes.
- **Honest about its dependencies.** If it needs the network, the disk, or the clock, it says so — by being in the integration tier, not by secretly depending on them in the unit tier.

### 3.1 Test tiers

- **Unit tests.** Fast, isolated, no I/O. The bulk of the suite. Run on every change.
- **Integration tests.** Real collaborators: real database, real file system, real network stub. Slower, fewer, targeted at the seams where components meet.
- **End-to-end tests.** The whole product, through the real interface, for the critical flows. Few in number, high in value, slow — run them before release, not on every keystroke.
- **Manual checks.** What cannot be automated: visual quality, feel, accessibility, real-device behaviour. Recorded as a checklist, not as folklore.

Each tier has a different job. A unit test cannot catch a broken integration; an end-to-end test cannot diagnose which component failed. Do not ask one tier to do another's job.

---

## 4. Flaky Tests

A flaky test fails sometimes with no code change. It is a defect in the test, in the code, or in the environment — and it must be treated as a defect, not as weather.

### 4.1 Triage

1. **Reproduce the flake.** Run the test repeatedly (100 times for a suspected race, 20 for anything else). If it cannot be reproduced, quarantine it — do not leave it in the suite.
2. **Classify the cause.** Order dependence (shared state), timing dependence (a sleep, a race), resource dependence (a leak, a quota), time dependence (a date, a TTL), environment dependence (a machine, a configuration). See `ComplexDebugging.md` for the full triage order.
3. **Fix the cause.** Remove the dependence. Never fix a flake by increasing a timeout, adding a retry, or running the test in isolation — those hide the cause and let it return in production.
4. **Quarantine while fixing.** A flaky test is skipped with a tracked issue that names the reproduction and the suspected cause. The quarantine has a deadline; a test quarantined forever is a deleted test with extra steps.

### 4.2 The flaky-test rules

- **Never delete a flaky test silently.** Deletion destroys the information that something is wrong. Quarantine with a record.
- **Never let a flaky test stay in the suite.** Every run that fails spuriously teaches the team that red is normal. A suite that is sometimes red is a suite that is ignored.
- **A flake in a test can mean a bug in the code.** A race that a test catches intermittently is a race that production will hit eventually. Investigate the code, not just the test.

---

## 5. Coverage Traps

Coverage — the fraction of lines executed by tests — is a useful diagnostic and a terrible target:

- **100% coverage proves nothing about correctness.** It proves the lines ran, not that they were checked. A test that calls a function and asserts nothing contributes coverage and zero safety.
- **Coverage rewards testing the easy code.** Trivial getters and straight-line code are cheap to cover; branching logic, error paths, and concurrency are expensive. A suite optimised for coverage tests the wrong things.
- **Coverage targets distort effort.** A team chasing 90% will write tests for the code that is easy to test, and skip the code that is hard — which is usually the code that matters.
- **Coverage is blind to missing code.** It cannot show the branch that was never written, the validation that was never added, the error that was never handled. The most dangerous gaps have zero lines to cover.

Use coverage as a map: look at what is **not** covered, and ask whether the uncovered code matters. Uncovered critical logic is a finding; uncovered trivial code is not. Never set a coverage target as a release gate without also requiring that the tests assert behaviour — a gate on a number alone will be gamed.

---

## 6. Failure Cases and Pitfalls

- **The mock that proves nothing.** A test that mocks every collaborator and asserts that the code called the mock. It tests the test's own assumptions, not the code. Mock at the boundary, and assert on behaviour and outcomes.
- **The test that tests the test.** Setup so elaborate that the test's own logic can be wrong. If the test needs a test for itself, simplify the code under test.
- **Snapshot tests as a crutch.** A snapshot that is regenerated whenever it fails is not a test — it is a record of whatever the code happened to do. Snapshots are useful for detecting unintended change; they are useless if the update is automatic and unreviewed.
- **Tests that depend on the network or the clock.** They fail when the network is slow, when the clock changes, when a service is down. Control time and I/O in tests with fakes, or move the test to the integration tier.
- **The suite that nobody runs.** Too slow, too flaky, too hard to run. The fix is not exhortation — it is making the suite fast, deterministic, and runnable with one command.
- **Testing after the fact as a checkbox.** Tests written to satisfy a process, after the code is done, without ever being seen to fail. A test that has never failed has never proven it can catch anything.

---

## 7. Verification Steps

Before claiming testing is adequate for a change:

1. Every bug fix has a regression test that fails without the fix.
2. Every new public behaviour has a test through the public interface.
3. Every new test has been seen to fail (by breaking the code it guards) and then to pass.
4. Tests are independent, deterministic, and fast enough that the suite runs on every change.
5. No flaky test remains in the suite unquarantined, and every quarantine has a tracked issue and a deadline.
6. Coverage was used as a map (uncovered critical logic identified), not as a target.
7. The full suite passes, in the configuration that ships.

## 8. Related Assets

- `BuildAndTesting.md` — running the suite and interpreting results.
- `SafeLegacyRefactoring.md` — characterisation tests as the safety net for restructuring.
- `ComplexDebugging.md` — turning a reproduction into a regression test.
- `ApiDesignCompatibility.md` — contracts that tests should pin.
