<!-- system-index-depends: SwiftUsage.md, CodeReviewSystemAsset.md -->

# API Design and Compatibility — Versioning, Breaking Changes, Deprecation, and Evolution

Practical guidance for designing APIs that other code — including your own future code — can rely on: naming and surface design, versioning, detecting breaking changes, deprecating gracefully, and evolving an API without breaking its callers. This asset governs **public interface design and evolution**; `SwiftUsage.md` governs Swift-level implementation, and `CodeReviewSystemAsset.md` governs reviewing interface changes.

---

## 0. Scope and Purpose

An API is a promise. Every public type, function, parameter, and behaviour is a commitment that callers will build on, and breaking it costs every caller a migration. Good API design is therefore mostly restraint: a small surface, clear names, explicit contracts, and an evolution path that lets the promise change without breaking the people who believed it.

Use this asset when:

- Designing a new public interface (module API, framework API, service contract, file format).
- Changing an existing public interface.
- Reviewing a change that might break callers.
- Planning a deprecation or a major version.

Do not use this asset to justify freezing an API that is wrong. Compatibility is a constraint on how change happens, not a prohibition on change.

---

## 1. The Core Rules

- **Small surface, deep capability.** An API should expose few entry points that do a lot, not many entry points that each do a little. Every public declaration is a commitment; every commitment is a future constraint.
- **Names are the interface.** Callers read names, not implementations. A misleading name is a bug that ships in every call site.
- **Explicit over clever.** Default behaviour, implicit conversions, and magic overloads feel convenient and produce call sites nobody can reason about. Prefer explicit parameters and explicit results.
- **Behaviour is part of the contract.** Return values, error conditions, ordering guarantees, thread-safety, and performance characteristics are all API. Changing any of them can break a caller that relied on it.
- **Compatibility is judged from the caller's side.** A change is breaking if any correct caller can observe it — not if the author's own call sites still compile.

---

## 2. Designing a Good API

### 2.1 Naming and shape

- **Name things for what they do, not how they do it.** `fetchUserProfile` survives a change of transport; `fetchUserProfileOverHTTP` does not.
- **One concept, one name.** The same operation called `load` in one module, `fetch` in another, and `retrieve` in a third forces callers to re-learn the vocabulary at every boundary.
- **Parameters read like a sentence at the call site.** Swift's argument labels exist for this reason: `move(from:to:)` is self-documenting; `move(_:_:)` is not.
- **Prefer values over references at boundaries.** Value types make the contract obvious: the caller owns the data, the callee cannot mutate it behind their back, and concurrency hazards shrink. See `MemoryResourceLifecycle.md`.
- **Return rich results, not bare success.** A result that carries the value, the error, or the reason for absence lets callers handle reality instead of guessing from a boolean.

### 2.2 Contracts to state explicitly

Every public API should document, in its declaration or its documentation:

- **Preconditions.** What must be true when it is called (non-nil, non-empty, valid range, correct thread). A violated precondition is a caller bug — but only if the precondition was stated.
- **Postconditions.** What is guaranteed afterwards.
- **Failure modes.** Every error it can produce, and what each error means the caller should do. An error with no documented recovery is a dead end.
- **Threading and actor context.** May it be called from any thread? Does it hop to the main actor? Does it suspend? Concurrency behaviour is part of the contract; see `AdvancedSwiftConcurrency.md`.
- **Performance expectations.** Is it O(1) or O(n)? Does it hit the network or the disk? A caller that assumes cheap and gets expensive has a performance bug caused by the API, not by the caller.

### 2.3 What not to expose

- **Implementation types.** Internal storage, cache structures, parser intermediates — expose domain types, not machinery.
- **Mutable shared state.** A public mutable static is a global with a nicer name. Expose behaviour, not storage.
- **Overly broad protocols.** A protocol with ten requirements is hard to implement and hard to evolve. Split by responsibility so conformers implement only what they need.
- **Sentinel values.** Magic strings, magic numbers, and "pass nil to mean default" are contracts that cannot be checked by the compiler. Use optionals, enums, or explicit default parameters instead.

---

## 3. Versioning

- **Semantic versioning for anything with external consumers.** MAJOR for breaking changes, MINOR for backwards-compatible additions, PATCH for backwards-compatible fixes. A version number that does not follow this is a number, not a version.
- **Internal modules version by commit, not by number.** If only your own code consumes an API, the git history is the versioning. Do not invent release numbers for internal boundaries.
- **Version the contract, not just the code.** A file format, a network protocol, and a persisted schema all need version fields and migration paths, even when the code that reads them is versioned separately.
- **One major version supported at a time, unless there is a real reason.** Supporting two majors doubles the maintenance surface and halves the attention each gets.

---

## 4. Breaking-Change Detection

A change is breaking if it can break a correct caller. Check every interface change against this list:

- **Source-breaking:** renamed or removed declarations, changed parameter types or labels, changed return types, added a required protocol requirement, changed a default value that callers relied on.
- **Binary-breaking:** changed the layout of a public type, removed a symbol, changed an enum's cases in a way that exhausts switches (for non-frozen enums, callers must handle the unknown case — document that).
- **Behaviour-breaking:** changed the result for the same input, changed the error for the same failure, changed ordering, changed threading, changed performance by an order of magnitude. These compile fine and break callers anyway — they are the most dangerous kind.
- **Semantic-breaking:** changed what a name means while keeping its shape. Renaming `isReady` to still be called `isReady` but now meaning something else is worse than renaming it.

**Detection method:** before landing an interface change, search for all call sites (including tests, extensions, and sample code), and review each one against the list above. For widely-used APIs, a source-compatibility check — compiling representative callers against the new interface — is the verification, not a manual review.

---

## 5. Deprecation and Evolution

### 5.1 Deprecating

- **Deprecate with a replacement, not just a warning.** Every deprecation names the replacement and, where possible, the version in which the old API will be removed. A deprecation without a migration path is a dead end.
- **Deprecate in a minor version; remove in a major.** Callers need a release cycle to migrate. Removing in the same release that deprecates gives them no time.
- **Keep deprecated APIs working.** A deprecated API that is broken is not deprecated — it is removed, with a misleading label. Deprecated means "still works, plan to move".
- **Do not deprecate by silence.** If the documentation no longer mentions an API but the symbol still exists, callers cannot tell whether it is supported. Deprecation is an explicit, visible act.

### 5.2 Evolving without breaking

- **Add, do not change.** New functionality arrives as new declarations. Existing declarations change only in a major version.
- **Defaulted parameters absorb growth.** A new parameter with a default value is backwards-compatible at the source level. A new required parameter is not.
- **Extend enums carefully.** Adding a case breaks exhaustive switches. If an enum may grow, document that callers must handle unknown cases, or use a struct with static members instead.
- **Widen, do not narrow.** A function that accepted a narrow type can be widened to accept a broader one; the reverse breaks callers. The same applies to thrown errors and to preconditions.
- **Versioned payloads.** For persisted data and network messages, include a version field from day one and write the migration before the new version ships. A format without a version field cannot evolve.

### 5.3 Example: evolving a save API without breaking callers

A document store starts with one save method. A later release needs an option to skip the backup step, and an old quick-save method needs to go away — both without breaking existing callers:

```swift
struct DocumentStore {
    func save(document: Document, options: SaveOptions = SaveOptions()) throws
}

struct SaveOptions {
    var createBackup: Bool = true
    var flushImmediately: Bool = false
}

extension DocumentStore {
    @available(*, deprecated, renamed: "save(document:options:)")
    func quickSave(document: Document) throws {
        var options = SaveOptions()
        options.createBackup = false
        try save(document: document, options: options)
    }
}
```

The new parameter has a default, and the default preserves the old behaviour, so every existing `save(document:)` call site still compiles and behaves identically. The deprecated `quickSave` still works — it forwards to the new method — and names its replacement, with removal planned for the next major version. The change that was rejected in review: adding a required parameter to `save`, which would have broken every caller in a minor release.

---

## 6. Failure Cases and Pitfalls

- **The "internal" API that became public.** A module-internal helper that another module started using, then another, until removing it breaks the product. If it is used across a boundary, it is public — treat it as such or close the boundary.
- **Overload ambiguity as evolution.** Adding an overload that makes existing call sites ambiguous. The compiler will report it, but only when those call sites are compiled — check them.
- **Silent behaviour change in a patch release.** A "bug fix" that changes results for inputs callers depended on. If callers could have depended on it, it is a breaking change regardless of whether it was a bug.
- **Deprecation without a deadline.** Deprecated APIs that live forever accumulate: every new caller must learn which of the two ways is current, and the old path still has to be maintained and tested.
- **The boolean parameter trap.** `save(quick: true)` at the call site; a second boolean later makes every call site unreadable. Prefer an options enum or a configuration value.
- **Leaking the platform.** An API whose parameter types are platform types (a view, a managed object, a network response) rather than domain types. The API is now coupled to the platform's evolution as well as its own.

## 7. Verification Steps

Before claiming an API change is complete:

1. All call sites — including tests, extensions, and samples — have been found and reviewed against the breaking-change list.
2. No source, binary, behaviour, or semantic break exists outside a major version bump, or the break is explicitly listed in the release notes with a migration path.
3. Every deprecation names its replacement and its planned removal version.
4. New public API documents its preconditions, failure modes, threading behaviour, and performance expectations.
5. The full build and test suite pass, including a source-compatibility check of representative callers where the API is widely used.
6. Persisted or network formats carry a version field and a tested migration path.

## 8. Related Assets

- `SwiftUsage.md` — Swift-specific API design (argument labels, value types, protocols).
- `AdvancedSwiftConcurrency.md` — concurrency behaviour as part of the API contract.
- `SafeLegacyRefactoring.md` — evolving an implementation behind a stable interface.
- `CodeReviewSystemAsset.md` — reviewing interface changes.
