<!-- system-index-depends: CodeReviewSystemAsset.md, BuildAndTesting.md -->

# Safe Legacy Refactoring — Changing Structure Without Changing Behaviour

Practical guidance for refactoring code you did not write, in a system you cannot fully hold in your head, without changing what it does: characterisation tests, seams, strangler patterns, and explicit rollback criteria. This asset governs **how to restructure safely**; `AdvancedSoftwareArchitecture.md` governs what the target structure should be, and `TestingStrategy.md` governs the tests that guard the change.

---

## 0. Scope and Purpose

Legacy code is code that works and that nobody fully understands. It earns its keep every day, and it resists change because every change risks breaking something invisible. Refactoring it is not a matter of courage — it is a matter of method: pin the behaviour down first, then move in steps so small that each one is either provably safe or trivially reversible.

Use this asset when:

- Restructuring a module, extracting a component, or renaming across a large surface.
- Removing duplication that has diverged over time.
- Preparing code for a new feature that its current shape cannot support.
- Paying down structural debt without a rewrite.

Do not use this asset to justify rewriting a working system. A rewrite discards the behaviour the legacy code has accumulated — including the bug fixes nobody remembers. Refactor incrementally or do not refactor.

---

## 1. The Core Rules

- **Behaviour first, structure second.** No structural change lands until the current behaviour is pinned by tests. The tests are the contract; the refactor is an implementation detail.
- **One behaviour-preserving step at a time.** Each commit changes structure only, or behaviour only — never both. A commit that does both cannot be reviewed for safety.
- **The build stays green at every step.** If a step breaks the build, the step was too big. Split it.
- **Every step is reversible.** If a step cannot be reverted cleanly, it is too big or too entangled. Revert is the safety net; a refactor without a revert path is a gamble.
- **Stop when the goal is met.** Refactoring has a defined end state. "While I'm here" scope creep is how safe refactors become dangerous rewrites.

---

## 2. Methodology: Characterisation Tests

Characterisation tests describe what the code **actually does**, not what it should do. They are written before any refactoring, by observing the code:

1. **Pick the seam.** Find the narrowest public interface around the code to be refactored — a function, a type, a module boundary. Tests go through the seam, not through internals.
2. **Exercise the real paths.** Drive the code with representative inputs, including the odd ones: empty collections, boundary values, malformed data, the inputs the production system actually sees.
3. **Record the actual outputs.** Whatever the code returns — even if it looks wrong — is the characterised behaviour. If it looks wrong, note it as a suspected defect and file it separately; do not "fix" it inside the refactor.
4. **Cover the edges the code visibly handles.** Every branch, every early return, every special case in the implementation gets at least one test. The branches are where behaviour hides.
5. **Run the tests against the unchanged code.** They must pass. A characterisation test that fails on the original code is a misunderstanding, not a test — fix the test.

Characterisation tests are scaffolding: they exist to be run during the refactor. Some may be deleted or replaced by proper specification tests afterwards; the safety they provided is not deleted with them.

---

## 3. Methodology: Seams

A seam is a place where behaviour can be changed without editing the code that uses it. Refactoring proceeds seam by seam:

- **Find existing seams.** Protocols, dependency injection points, function parameters, configuration values, file boundaries. Legacy code usually has more seams than it appears to — a function parameter is a seam, a global that can be set in a test is a seam.
- **Create a seam where none exists.** The smallest seam is a function extraction: move the code to be replaced into its own function, call it from the old place, verify the tests still pass. Now the old and new implementations can be swapped behind the same call.
- **Refactor behind the seam.** Change the implementation while the callers and the tests see no difference.
- **Move the seam outward.** Once the internals are clean, the seam itself can move to a better boundary — a protocol, a module edge — in a separate, small step.

The classic mistake is refactoring callers and implementation in the same step. The seam exists precisely so you do not have to.

---

## 4. Methodology: The Strangler Pattern

When a component is too large or too entangled to refactor in place, strangle it:

1. **Build the new component alongside the old.** It lives in the same codebase, behind the same seam, but does not serve traffic yet.
2. **Route one path through the new component.** The narrowest, best-understood path first — one call site, one feature, one input type.
3. **Verify with production-equivalent evidence.** The characterisation tests pass through the new path; behaviour matches the old path exactly.
4. **Route the next path.** One at a time, in order of increasing risk. Each routed path is a small, reviewable, reversible step.
5. **Delete the old component only when nothing routes to it.** The compiler confirms this: no callers, no references. Deletion is the last step, not the first.

The strangler pattern is how large systems are replaced without downtime and without a flag day. It is slower than a rewrite and it works, which the rewrite usually does not.

---

## 5. Rollback Criteria

Define these **before** starting, in writing, where the change will be reviewed:

- **Revert triggers.** The conditions under which the refactor is rolled back rather than fixed forward: test failures that cannot be explained within the session, a behaviour difference found by characterisation tests, a performance regression beyond an agreed threshold, a build break that survives one focused repair attempt.
- **Revert granularity.** Each step is its own commit, so any single step can be reverted without losing the rest. If the steps were squashed, there is no granularity — do not squash during a refactor.
- **Checkpoint commits.** After each verified step, commit. A refactor with three hours of uncommitted work has no rollback point and no reviewable history.
- **The stop rule.** If two consecutive steps each reveal a new, uncharacterised behaviour, stop refactoring and go back to characterisation. The code is telling you it is not understood well enough yet.

Rollback is not failure. Rolling back a refactor that exposed unknown behaviour is the system working correctly.

---

## 6. Failure Cases and Pitfalls

- **Refactoring and fixing in one change.** A behaviour change hidden inside a "cleanup" commit. Reviewers cannot tell whether the behaviour change was intended, and the characterisation tests cannot catch it because they were written after.
- **Deleting tests that "no longer apply".** A test that fails after a behaviour-preserving refactor is evidence of a behaviour change, not a stale test. Investigate before deleting.
- **Renaming as a refactor step.** Renames touch many files and obscure the real change in review. Do renames as their own commit, before or after the structural work — never mixed in.
- **Duplicated code that has diverged.** Two copies that look identical but handle one edge case differently. Merging them without characterising both copies first silently picks one behaviour and breaks the other's callers.
- **The "obvious" simplification.** Removing a condition that looks dead, a branch that looks unreachable, a check that looks redundant. In legacy code, that condition is usually load-bearing in a case you have not seen. Characterise it first; if no test can reach it, prove it unreachable from the call graph before removing it.
- **Refactoring without a goal.** Restructuring code because it "feels messy", with no feature or defect driving it. The risk is real and the benefit is aesthetic. Refactor toward a concrete need.

## 7. Verification Steps

Before claiming a refactor is complete:

1. All characterisation tests written before the refactor still pass, unchanged.
2. The change consists of behaviour-preserving steps only; any behaviour change is a separate, explicitly labelled commit.
3. The full build and test suite pass (see `BuildAndTesting.md`).
4. No callers of the old component remain, if the old component was removed — verified by the compiler and by search, not by memory.
5. The rollback criteria were never triggered, or the rollback was performed and recorded.
6. A reviewer can follow the commit sequence and verify each step preserves behaviour.

## 8. Related Assets

- `AdvancedSoftwareArchitecture.md` — what the target structure should look like.
- `TestingStrategy.md` — what makes a characterisation test trustworthy.
- `ComplexDebugging.md` — what to do when a refactor exposes a real defect.
- `GitHistoryForensics.md` — using history to understand why the legacy code is shaped the way it is.
