<!-- system-index-depends: SwiftUsage.md, ProjectContext.md -->

# Advanced Software Architecture — Modular Boundaries, Layering, and Dependency Direction

Authoritative guidance for designing and evolving the architecture of a real software system: where modules begin and end, which direction dependencies may flow, how feature code stays separated from infrastructure, and when a module should be split, merged, or left alone. This asset governs **structural decisions that outlive any single feature**; `SwiftUsage.md` governs Swift-level implementation discipline and `ProjectContext.md` governs how project context is gathered before changing structure.

---

## 0. Scope and Purpose

Architecture is the set of decisions that are expensive to reverse: module boundaries, dependency direction, layering, and the split between what the product does and how it talks to the outside world. Everything else — a new screen, a new endpoint, a new algorithm — is comparatively cheap.

Use this asset when:

- Adding a feature that touches more than one existing module.
- Untangling a dependency cycle or a module that everything imports.
- Deciding whether new code belongs in an existing module or a new one.
- Reviewing a proposed structural change before it lands.

Do not use this asset to justify a rewrite. A rewrite is a last resort, not an architecture strategy; see `SafeLegacyRefactoring.md` for the incremental path.

---

## 1. The Core Rules

### 1.1 Dependencies point one way

A module may depend on modules below it, never on modules beside it or above it. If two modules need each other, one of the following is wrong: the boundary is in the wrong place, a shared concept has not been extracted, or one module is doing two jobs.

- **Acyclic dependency graph, always.** A cycle means neither module can be understood, tested, or built without the other — they are one module wearing two names.
- **Depend on abstractions, not concretions, at boundaries.** A feature module depends on a protocol for persistence, networking, or logging — never on the concrete store, client, or logger.
- **The dependency rule is checked, not hoped for.** If the build system can express it (target dependencies, package boundaries, import restrictions), express it there. A rule that lives only in a document will be violated silently.

### 1.2 Layers are about stability, not prestige

Layering orders code by how often it changes and how widely it is reused:

- **Domain / feature logic** — the product's rules. Changes when the product changes. Depends on almost nothing.
- **Application / coordination** — use cases, orchestration, state machines. Depends on the domain and on infrastructure abstractions.
- **Infrastructure** — persistence, networking, platform APIs, file I/O. Changes when the platform or a vendor changes. Depends on nothing in the product.
- **Presentation** — views, view models, navigation. Depends on application and domain; the domain never depends on presentation.

The most common architectural failure in Apple-platform apps is the reverse: domain logic embedded in a view, a network call inside a view model, a Core Data entity passed straight into SwiftUI. Every one of those makes the logic untestable without the UI and unreusable anywhere else.

### 1.3 Feature vs infrastructure split

Feature code answers "what does the product do". Infrastructure code answers "how does it reach the outside world". They must be separable:

- A feature module must compile and be testable with every infrastructure dependency replaced by a stub.
- Infrastructure code must not contain product rules. A network client that knows which endpoints are "premium" has absorbed feature logic; a persistence layer that filters by business status has done the same.
- Shared infrastructure (logging, analytics, keychain access, crash reporting) is a dependency injected into features, never a global that features reach for directly. Globals hide dependencies and make tests order-dependent.

---

## 2. Methodology: Designing a Boundary

Apply this sequence whenever a new boundary is proposed:

1. **Name the responsibility in one sentence.** If it takes a paragraph, the boundary is wrong. "Owns the user's saved servers and their credentials" is a responsibility. "Handles server stuff" is not.
2. **List what it needs from others.** Each need becomes an explicit dependency — a protocol, a value type, or a narrow interface. If the list is long, the module is too broad.
3. **List what others need from it.** That is its public interface. Everything else is internal. A module whose public surface is most of its code has no encapsulation.
4. **Draw the dependency direction.** Confirm it is acyclic and that it points from volatile toward stable. If a stable module would depend on a volatile one, invert the dependency with a protocol owned by the stable side.
5. **Write the seam test first.** Before moving code, write one test that exercises the new boundary through its public interface with stubs. If that test is awkward, the boundary is awkward.
6. **Move code in small, compiling steps.** Each step keeps the build green. A boundary change that requires a flag day is a boundary change that was not decomposed.

---

## 3. When to Split a Module

Split when any of these is true, and the split has a clean seam:

- **Two reasons to change.** The module changes for unrelated product reasons (e.g. billing logic and sync logic in one target). Each change risks the other.
- **Two audiences.** One part is imported by the app, another by an extension, a CLI, or tests — and the second audience drags in dependencies it does not need.
- **A cycle is forming.** Splitting out the shared concept that both sides need breaks the cycle honestly instead of hiding it.
- **Build time concentrates.** One module dominates incremental build time because everything funnels through it; a split lets unrelated work compile independently.
- **Ownership diverges.** Different people or teams own different parts and keep stepping on each other's changes.

Split by extracting the **stable, depended-upon part first** — the types, protocols, and pure logic with no platform dependencies. The volatile remainder stays behind and depends on the extraction.

## 4. When to Merge Modules

Merge when any of these is true:

- **The boundary is crossed in both directions.** Callers constantly reach into both modules together; the split buys nothing and costs a dependency hop everywhere.
- **The seam has no second implementation.** A protocol with exactly one implementation, one caller, and no test double is ceremony, not abstraction. Inline it until a second use appears.
- **The split was speculative.** It was created for a future reuse that never arrived. Premature modularisation is the same failure as premature optimisation: cost paid now for a benefit that may never come.
- **Refactoring across the boundary is constant.** If every feature change edits both modules in lockstep, they change together and should live together.

Merging is not a failure of the earlier split. Codebases breathe: boundaries that were right at one size are wrong at another. The failure is keeping a boundary out of pride after the evidence says it costs more than it saves.

## 5. Dependency Direction Patterns

- **Ports and adapters (hexagonal).** The domain defines ports (protocols); infrastructure provides adapters. The domain never imports infrastructure. This is the default pattern for anything with persistence, networking, or platform services.
- **Feature modules depend on a shared core, never on each other.** Cross-feature communication goes through the core (events, a coordinator, a shared store) or through explicit, narrow interfaces — never through direct imports between features.
- **Platform code at the edges.** AppKit, UIKit, SwiftUI, Core Data, and third-party SDKs live in infrastructure or presentation modules. Pure logic modules import Foundation only. If a logic module imports a UI framework, the boundary has leaked.
- **No upward references in tests either.** A test target for a low-level module must not import a high-level module to build fixtures. Fixtures live at or below the module under test.

## 6. Failure Cases and Pitfalls

- **The god module.** One target that everything imports because "it's convenient". Symptoms: build times grow superlinearly, unrelated changes conflict, tests cannot run in isolation. Fix by extracting the stable core first, then the next most-depended-upon piece.
- **The dependency pretzel.** A depends on B, B on C, C on A. Usually caused by a shared type living in the wrong module. Fix by moving the shared type to a lower module both sides can depend on.
- **Leaky abstractions.** A repository protocol whose methods mention SQL, HTTP status codes, or Core Data types. The abstraction has failed; callers are coupled to the implementation anyway. Redesign the protocol in domain terms.
- **Interface explosion.** Twenty protocols where three would do, each with one method. The seam is too fine-grained to be useful. Consolidate around real responsibilities.
- **Hidden coupling through shared mutable state.** Singletons, global stores, and notification-center broadcasts that let modules coordinate without declaring a dependency. The dependency graph looks clean and the runtime behaviour is coupled. Replace with explicit injection or an explicit event bus owned by the core.
- **Big-bang restructure.** Moving hundreds of files in one commit with no green build in between. If it breaks, there is no bisectable step and no safe rollback. Always restructure incrementally.

## 7. Verification Steps

Before claiming an architectural change is complete:

1. The dependency graph is acyclic — verify from the build system or package manifest, not from memory.
2. Every new module has a one-sentence responsibility and a public interface small enough to list.
3. Feature logic compiles and tests pass with infrastructure replaced by stubs.
4. No domain or logic module imports a UI framework, a persistence framework, or a networking SDK.
5. The full build and test suite pass (see `BuildAndTesting.md`).
6. A feature change touching the restructured area requires editing one module, not three — spot-check with a real upcoming task.

## 8. Related Assets

- `SwiftUsage.md` — Swift-level patterns that keep modules clean (value types, protocols, actor isolation).
- `SafeLegacyRefactoring.md` — moving code to a new boundary without changing behaviour.
- `DependencyAuditing.md` — auditing what the modules themselves depend on externally.
- `RepositoryExploration.md` — mapping the existing structure before changing it.
