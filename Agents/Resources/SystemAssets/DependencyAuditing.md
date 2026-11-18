<!-- system-index-depends: BuildAndTesting.md, Safeguards.md -->

# Dependency Auditing — Outdated, Unmaintained, Duplicated, and Risky Dependencies

Practical guidance for auditing what a project depends on: finding outdated, unmaintained, duplicated, and risky dependencies, judging licence and security exposure, and deciding what to update, replace, or remove. This asset governs **evaluating dependencies**; `BuildAndTesting.md` governs how dependencies are integrated and built, and `Safeguards.md` governs the security posture they must satisfy.

---

## 0. Scope and Purpose

Every dependency is a liability you have chosen to carry: someone else's code, running in your process, under their maintenance schedule, under their licence. Dependencies compound silently — a direct dependency brings transitive ones, a convenient utility brings a whole framework, a pinned old version freezes a known vulnerability in place. Auditing is the periodic reckoning: what do we depend on, is it still healthy, and is it still worth it?

Use this asset when:

- Reviewing a project's dependency list before a release.
- Investigating a security advisory that names a library you may use.
- Deciding whether to adopt a new dependency.
- Cleaning up after a period of fast growth.

Do not audit continuously. Audit on a cadence (per release, per quarter) and on trigger (a security advisory, a build break, a deprecation notice). An audit with no decision is a report; an audit must end in update, replace, remove, or explicitly accept.

---

## 1. The Core Rules

- **A dependency must justify itself every audit.** "We have always used it" is not a justification. The justification is: what it does, what it would cost to replace, and what risk it carries.
- **Direct dependencies are your responsibility; transitive ones are your exposure.** You chose the direct ones. The transitive ones arrived uninvited — audit them anyway, because they run in your process too.
- **Pin deliberately, update deliberately.** An unpinned dependency drifts; a pinned dependency rots. Either way the choice must be explicit, recorded, and revisited.
- **Small dependencies are not free.** A ten-line utility package carries the same supply-chain risk, review cost, and breakage surface as a large one, for a benefit you could have written yourself.
- **Removal is a valid outcome.** The best dependency is the one you no longer need.

---

## 2. Methodology: The Audit Pass

### Step 1 — Inventory

List every dependency, direct and transitive, with: name, version (and how it is pinned), source, licence, and what uses it. The package manifest and the resolved lockfile are the sources of truth — not memory, not documentation. If the inventory cannot be produced from the manifest and lockfile, the project's dependency management is itself a finding.

### Step 2 — Health check, per dependency

For each dependency, check:

- **Maintenance.** Last release date, commit activity, open issues and pull requests, maintainer responsiveness. A library with no release in two years and unanswered security issues is unmaintained, whatever its download count.
- **Currency.** How far behind the latest release is the pinned version? A small gap is normal; a multi-major gap means the upgrade will be a project, not a chore — and the longer it waits, the bigger it gets.
- **Duplication.** Two libraries doing the same job (two HTTP clients, two date libraries, three JSON helpers). Duplication usually accretes one adoption at a time; the audit is the moment to pick one.
- **Overlap with the platform.** A library that duplicates functionality the OS or standard library now provides natively. Platform APIs are maintained by the platform vendor, documented, and already on the device.
- **Size and surface.** What the dependency pulls in transitively. A small utility that drags in a large framework is not small.

### Step 3 — Risk check, per dependency

- **Security.** Known vulnerabilities in the pinned version (advisory databases, the package manager's audit command). A known vulnerability in a pinned version is a decision, not an oversight — record it as accepted or fix it.
- **Licence.** Licence type, compatibility with the project's licence and distribution model, and any obligations (attribution, source disclosure, copyleft). A licence that conflicts with distribution is a blocker, not a footnote.
- **Supply chain.** Who publishes it, how releases are made, whether the package is a single-maintainer project with no succession plan. A dependency on one person's weekend project is a bus-factor risk.
- **Behavioural risk.** Does it swizzle, hook, or patch runtime behaviour? Does it phone home, collect telemetry, or execute code at load time? Dependencies that alter the runtime are audited more strictly than libraries that are called.

### Step 4 — Decide

Every dependency gets one verdict:

- **Update** — to the latest compatible version, or to the latest major with a planned migration.
- **Replace** — with a maintained alternative, a platform API, or in-house code. Record the reason so the next audit does not re-adopt it.
- **Remove** — nothing uses it, or its use is trivial. Removal is verified by the build and the test suite, not by grep alone (a dependency can be referenced by generated code or configuration).
- **Accept** — keep as-is, with the reason and the risk recorded, and a revisit date. An accepted risk with a date is a decision; an unexamined risk is negligence.

### Example: one audit verdict, worked

A notes app depends on a date-formatting library pinned at 2.1.0. The audit's findings and verdict, written down so the next audit does not repeat the work:

```text
Dependency: DateFormatKit 2.1.0, direct, MIT licence
Used by:    three call sites in the export feature
Health:     last release 14 months ago, 30 open issues,
            no maintainer reply in 6 months
Currency:   latest is 3.0.0, a major behind; migration renames two types
Overlap:    Foundation now provides the two formatters the app uses
Security:   no advisories for 2.1.0
Verdict:    REPLACE with Foundation formatters; delete the dependency
Evidence:   build and full test suite pass with the dependency removed
```

The decisive finding is the overlap, not the staleness: the library is unmaintained and a major behind, but what makes replacement cheap is that the platform already provides the two formatters the app actually uses. Had the app used the library's calendar arithmetic as well, the verdict would have been Update with a planned migration, not Replace.

---

## 3. Adoption Criteria for New Dependencies

Before adding a dependency, answer in writing:

1. What exact problem does it solve that the platform, the standard library, or existing dependencies do not?
2. What would it cost to write the needed piece in-house, and to maintain it?
3. Is it maintained, and by whom? What happens if maintenance stops?
4. What does it pull in transitively, and what is its licence?
5. What is the exit cost — how much code would need to change to remove it later?

If the answer to (1) is "convenience" and the answer to (2) is "an afternoon", do not adopt it. If the answer to (5) is "everything", the dependency is becoming architecture — that decision deserves the scrutiny in `AdvancedSoftwareArchitecture.md`, not a one-line addition to a manifest.

Prefer dependencies that are: narrow in scope, stable in API, maintained by more than one person, and replaceable behind a protocol or a thin wrapper you own.

---

## 4. Failure Cases and Pitfalls

- **The abandoned transitive dependency.** Your direct dependency is healthy; the library it depends on is dead and has a known vulnerability. You cannot fix it by updating your direct dependency — you must replace the chain or patch around it.
- **Version drift between targets.** The app pins one version, an extension or test target pins another. Two versions of the same library in one product produce duplicate symbols, inconsistent behaviour, or silent wrong-version loading.
- **The lockfile that is not locked.** A manifest without a committed lockfile means every clean build can resolve differently. Reproducibility requires the lockfile to be committed and the build to respect it.
- **Licence contamination discovered at release time.** A copyleft dependency pulled in transitively, found during a release review. Licence checks belong in the audit and in CI, not in a pre-release scramble.
- **Updating everything at once.** A bulk update that changes twenty dependencies in one commit. When the build breaks, the cause is unknown. Update one dependency (or one coherent group) at a time, with tests passing between each.
- **The "temporary" fork.** A forked dependency patched in place and never upstreamed. It drifts from upstream, accumulates private patches, and becomes unmaintainable. A fork needs an owner, an upstreaming plan, or a replacement date.

## 5. Verification Steps

Before claiming an audit is complete:

1. The inventory is complete and derived from the manifest and lockfile — every direct and transitive dependency listed.
2. Every dependency has a verdict (update, replace, remove, accept) with a reason.
3. Security advisories for the pinned versions have been checked; any accepted vulnerability is recorded with a revisit date.
4. Licences have been checked for compatibility with the project's distribution.
5. Removals and updates are verified by a clean build and a full test run, not by search alone.
6. The audit outcome is recorded where the next audit will find it.

## 6. Related Assets

- `BuildAndTesting.md` — how dependencies are resolved, built, and verified.
- `Safeguards.md` — the security requirements dependencies must satisfy.
- `AdvancedSoftwareArchitecture.md` — when a dependency becomes architecture.
- `PerformanceProfiling.md` — when a dependency is the performance problem.
