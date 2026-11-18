<!-- system-index-depends: BuildAndTesting.md, FileOperations.md -->

# Build Systems and Project Configuration — Targets, Build Phases, Signing, Configs, and CI

Practical guidance for structuring and maintaining a buildable project: targets and build phases, build settings and configurations, code signing and entitlements, dependency integration, and continuous integration. This asset governs **project configuration**; `BuildAndTesting.md` governs running builds and interpreting their results, and `DependencyAuditing.md` governs what the project depends on.

---

## 0. Scope and Purpose

A project that builds on one machine and fails on another is not a working project — it is a coincidence. Build configuration is the difference: targets, phases, settings, signing, and CI are the machinery that turns source code into a shippable product reproducibly. Configuration drift — a setting changed in the GUI and never recorded, a signing identity that exists only on one Mac, a build phase that depends on a file nobody remembers — is the most common reason a project stops building for a new team member or a new machine.

Use this asset when:

- Creating or restructuring targets, schemes, or build phases.
- Diagnosing a build that works locally but fails in CI, or vice versa.
- Setting up or fixing code signing, entitlements, or provisioning.
- Reviewing a configuration change.

Do not hand-edit generated project files casually. The project file is a database with its own consistency rules; a malformed edit can corrupt it in ways that surface much later. Prefer the project editor, a generator, or a script that validates its output — and verify the project still opens and builds afterwards.

---

## 1. The Core Rules

- **The build is reproducible from a clean checkout.** Clone, build, no manual steps. Anything that requires a human to have done something first is a defect in the configuration.
- **Configuration is code, and it is reviewed.** Build settings, phases, and scripts are part of the change. A configuration change without a review is a build break waiting for the next machine.
- **Debug and release differ deliberately.** The differences between configurations are named and minimal: optimisation level, assertions, signing identity, diagnostics. An accidental difference is a bug that only appears in one configuration.
- **Signing is explicit.** Identities, profiles, entitlements, and capabilities are declared in the project, not remembered by a developer. A build that signs only because the right certificate happens to be in a keychain is not configured — it is lucky.
- **CI builds what developers build.** The same targets, the same schemes, the same configuration. A CI that builds something different from the developer's build verifies something different from what ships.

---

## 2. Targets and Build Phases

### 2.1 Targets

- **One target, one product.** An app target, an extension target, a test target, a library target — each produces one thing. A target that produces two things is two targets sharing a name.
- **Targets depend on targets, not on files.** A target's dependencies are declared as target dependencies. Reaching into another target's source files directly couples the two targets and hides the dependency from the build system.
- **Shared code lives in a shared target.** Code used by the app and an extension belongs in a framework or library target both depend on — not copied into both, and not reached across target boundaries.
- **Test targets test one thing.** A unit test target per product target, with its own host where needed. A test target that imports the whole product to test one module is testing the wrong granularity.
- **Keep the target list small.** Each target is a build graph node, a signing identity, and a maintenance cost. A new target must justify itself: a distinct product, a distinct platform, or a distinct boundary.

### 2.2 Build phases

- **Order matters and is explicit.** Compile sources, link, copy resources, run scripts — in that order, and only the phases the target needs. A script phase that depends on a build product must run after that product is built; a resource phase that runs too early copies stale files.
- **Script phases are deterministic and fast.** A script that downloads, generates, or modifies files during the build must be idempotent, must declare its inputs and outputs (so the build system can skip it when nothing changed), and must fail loudly on error — a script that fails silently produces a build that looks green and is wrong.
- **No secrets in build phases.** Credentials, tokens, and signing material do not live in scripts, settings, or the project file. They come from the environment or a secure store at build time.
- **Generated code is generated, not committed — or committed deliberately.** Either the build generates it every time (and the generation is deterministic), or it is committed as source and regenerated explicitly. The worst option is generated code committed once and then edited by hand: nobody knows which is the source of truth.

---

## 3. Build Settings and Configurations

- **Settings live at the right level.** Project-level settings are defaults; target-level settings override for a reason. A setting overridden in ten targets with the same value belongs at the project level.
- **Use configuration files (`.xcconfig`) for anything non-trivial.** They are text, they are diffable, they are reviewable, and they can be shared across targets. Settings changed only in the GUI are invisible in review.
- **Name configurations for their purpose.** Debug, Release, and any custom configuration (e.g. a beta or an internal build) each have a defined meaning: optimisation, diagnostics, signing, feature flags. A configuration whose meaning nobody can state is a configuration that will be misused.
- **Search paths are explicit and minimal.** Header, framework, and library search paths that point at absolute locations on one developer's machine break every other machine. Use project-relative paths and the build system's variables.
- **Warnings are not noise.** A new warning is a finding. Treat warnings as errors in CI for the code you own, so they are fixed when introduced instead of accumulating into a list nobody reads.
- **Compiler flags are deliberate.** Optimisation level, sanitizers, strict concurrency checking, and language mode are choices with consequences. Changing them is a configuration change — reviewed, recorded, and verified by a build and a test run.

### Example: shared settings in one xcconfig

A notes app keeps its shared settings in one base configuration file, with one small file per configuration for the differences that are deliberate:

```xcconfig
SWIFT_VERSION = 5.0
SWIFT_STRICT_CONCURRENCY = complete
PRODUCT_BUNDLE_IDENTIFIER = com.example.notes
```

```xcconfig
#include "Shared.xcconfig"
SWIFT_OPTIMIZATION_LEVEL = -Onone
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
GCC_OPTIMIZATION_LEVEL = 0
ENABLE_TESTABILITY = YES
```

```xcconfig
#include "Shared.xcconfig"
SWIFT_OPTIMIZATION_LEVEL = -O
SWIFT_COMPILATION_MODE = wholemodule
GCC_OPTIMIZATION_LEVEL = s
ENABLE_TESTABILITY = NO
```

The three files are the whole story: the base holds what every configuration shares, and the Debug and Release files differ only in optimisation, compilation mode, testability, and the DEBUG condition. A setting changed in the project editor instead of here is invisible in review and will drift — which is why the review for a configuration change starts by asking which file it landed in.

---

## 4. Signing, Entitlements, and Capabilities

- **One signing identity per configuration, declared in the project.** Automatic signing is convenient for development; manual signing is explicit and reproducible for release. Whichever is chosen, it is chosen deliberately and documented.
- **Entitlements are the contract with the platform.** Each entitlement is a capability the app claims: App Sandbox, network access, file access, keychain groups, app groups. An entitlement that is claimed but unused is a review risk; a capability that is used but not entitled fails at runtime.
- **Capabilities match the entitlements file, which matches the provisioning profile, which matches the App ID.** A mismatch anywhere in that chain produces a signing or runtime failure whose error message points at the wrong link. When signing fails, check the whole chain, not just the last link.
- **App groups, keychain groups, and bundle identifiers are coordinated.** Extensions, the main app, and any helper tools share identifiers and groups by design. A typo in one identifier silently breaks sharing between them.
- **Never commit signing material.** Certificates, private keys, and provisioning profiles do not belong in version control. They belong in a keychain, a secure store, or a CI secret — and the build must fail clearly when they are absent, not silently produce an unsigned product.

---

## 5. Dependency Integration

- **Dependencies are declared in one place.** The package manifest, the project file, or the workspace — not two of them, and not partly in a script. Two sources of truth for dependencies will diverge.
- **Lockfiles are committed.** The resolved versions are part of the build's reproducibility. A build without a lockfile can resolve differently on every machine.
- **Dependencies build in the same configuration as the product.** A dependency built in debug while the product builds in release (or vice versa) produces subtle mismatches: different optimisation, different assertions, different concurrency checking.
- **Prebuilt binaries are verified.** A binary dependency is code you did not compile. Verify its source, its checksum, and its signature where the tooling supports it — and record the verification.

---

## 6. Continuous Integration

CI is the build that nobody can skip and nobody can fudge. Its job is to prove, on every change, that the project builds, tests pass, and the product is what the source says it is.

- **CI runs the same commands a developer runs.** The same scheme, the same configuration, the same test plan. A CI script that builds differently from the developer's workflow verifies a different product.
- **CI is fast enough to be useful.** A pipeline that takes an hour will be worked around. Split it: a fast gate (build + unit tests) on every change, and slower tiers (integration, end-to-end, profiling) on a schedule or before release.
- **CI fails loudly and specifically.** A failure names the step, the command, and the output. A pipeline that fails with a generic error will be re-run hopefully instead of investigated.
- **CI environments are disposable and reproducible.** A runner that accumulates state (caches, installed tools, leftover files) will eventually produce a build that cannot be reproduced anywhere else. Prefer clean runners, pinned tool versions, and explicit caches with invalidation.
- **Secrets in CI are secrets.** Injected by the CI system, scoped to the job, never printed in logs, never committed. A secret that appears in a build log is a compromised secret.
- **CI does not deploy on a green build alone.** Deployment needs the release configuration, the signing material, the version bump, and the checklist — a green test suite is necessary, not sufficient.

---

## 7. Failure Cases and Pitfalls

- **"It builds on my machine."** A setting, a file, or a tool that exists only locally. The fix is a clean-checkout build, regularly, by CI — which is exactly what CI is for.
- **The project file merge conflict.** Two developers editing the project file in the GUI produce a conflict that is hard to resolve by hand. Resolve it by understanding the structure (targets, phases, file references), not by accepting one side wholesale — and verify the project opens and builds afterwards.
- **A build phase that depends on order nobody recorded.** It works until someone reorders phases, adds a target, or the build system parallelises differently. Declare the dependency explicitly.
- **Signing that works until the certificate expires.** Certificates and profiles expire. Renewal is a scheduled task, not a surprise. Track expiry dates where the team will see them.
- **Configuration drift between app and extension.** The extension builds with one set of settings, the app with another, and a shared framework behaves differently in each. Shared settings belong in a shared configuration file.
- **The script phase that modifies source.** A build step that rewrites a source file makes the build non-reproducible and the source untrustworthy. Build steps write to derived data, not to the source tree.

---

## 8. Verification Steps

Before claiming a configuration change is complete:

1. A clean checkout builds with no manual steps, in both Debug and Release.
2. CI builds the same targets, schemes, and configuration — and passes.
3. The signing chain (entitlements, capabilities, profile, identity) is consistent and the product signs and launches.
4. All targets build; no target depends on another target's source files directly.
5. The full test suite passes in the configuration that ships.
6. The change is reviewable as a diff — settings in configuration files where possible, and the project file verified openable and buildable after the change.

## 9. Related Assets

- `BuildAndTesting.md` — running builds, reading diagnostics, running tests.
- `DependencyAuditing.md` — auditing what the build pulls in.
- `SafeLegacyRefactoring.md` — restructuring a project without breaking the build.
- `RepositoryExploration.md` — mapping a project's targets and structure.
