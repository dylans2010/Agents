<!-- system-index-depends: FileOperations.md, ProjectContext.md -->

# Repository Exploration — Mapping an Unfamiliar Codebase Fast

Practical guidance for getting oriented in a codebase you did not write: finding entry points, tracing dependency graphs, choosing a reading order, and building a mental model from evidence rather than guessing. This asset governs **how to explore before changing anything**; `ProjectContext.md` governs what project context to collect, and `FileOperations.md` governs how files are read and searched.

---

## 0. Scope and Purpose

Every unfamiliar codebase looks chaotic from the outside. The chaos is usually an illusion produced by not knowing where the seams are. Exploration has one job: find the seams quickly, with evidence, so that later work starts from a correct model instead of a plausible one.

Use this asset when:

- Starting work in a repository you have not touched before.
- Reviewing or auditing a project someone else built.
- Deciding where a new feature belongs.
- Diagnosing a bug in an area with no obvious owner.

Do not explore endlessly. Exploration is time-boxed: the goal is a working map, not a complete understanding. Depth comes from the task itself.

---

## 1. The Core Rules

- **Evidence first, inference second.** A claim about how the code works must be traceable to a file, a call site, or a test. "Probably the router handles this" is not evidence.
- **Follow the runtime, not the directory tree.** Directory layout reflects someone's past intentions; the call graph reflects what actually happens.
- **Start from the outside in.** Entry points first, then the paths they trigger, then the leaves. Reading leaf utilities before knowing who calls them wastes the budget.
- **Write the map down.** A short note — entry points, key modules, data flow, open questions — is worth more than a perfect mental model that evaporates.
- **Stop when the map answers the task.** If the next task is "add a setting", the map needs the settings flow, not the entire networking stack.

---

## 2. Methodology: The First Hour

### Step 1 — Orient (10 minutes)

- Read the top-level README, `AGENTS.md`, or equivalent project instructions if present. They state intent; the code states reality. Note where they disagree.
- List the top-level directories and the build manifest (project file, package manifest, workspace). The manifest is the authoritative module list — it shows targets, dependencies, and what is actually built.
- Check version control state: current branch, recent commits, uncommitted changes. Recent commits show where active work is happening; uncommitted changes show where someone else's work is in flight.

### Step 2 — Find the entry points (15 minutes)

- Locate the application entry point: `App` struct / `AppDelegate` / `main`, the root view, the command-line entry.
- Locate the secondary entry points: URL handlers, extensions, background tasks, CLI commands, test targets.
- For each entry point, note what it constructs first. The first objects created at launch are the skeleton of the architecture: the store, the coordinator, the service registry.

### Step 3 — Trace one real flow end to end (20 minutes)

Pick the product's most central user flow (open a project, run a command, load a list) and trace it:

1. Where does the user action originate (view, command, shortcut)?
2. What handles it (view model, controller, command handler)?
3. What service or store does the handler call?
4. What persistence, network, or platform API does that service reach?
5. Where does the result return, and what updates the UI?

One traced flow teaches more than ten skimmed directories. It reveals the layering, the naming conventions, and the real dependency direction.

### Step 4 — Map the modules (15 minutes)

- For each top-level module or target, write one sentence: what it owns, what it depends on.
- Identify the shared core: the module everything imports. Read its public interface — it defines the vocabulary of the whole codebase.
- Identify the seams: protocols, registries, plugin points, event buses. Seams are where behaviour can be changed without rewriting callers.

### Step 5 — Record and stop

Write the map: entry points, the traced flow, module sentences, seams, and open questions with file references. Then start the actual task. Return to exploration only when the task hits something the map does not explain.

---

## 3. Reading Order

When a task requires deeper reading, read in this order:

1. **Public interfaces first.** Type declarations, protocol definitions, public method signatures. They say what a component promises.
2. **Call sites second.** Who calls this, and with what arguments? Call sites reveal the real contract — including the parts the signature does not show.
3. **Implementation third.** Only now read the body, and only the paths relevant to the task.
4. **Tests last, or alongside.** Tests show intended behaviour and the boundaries the author considered worth pinning. A test that exists for an edge case is a warning: that edge case has bitten before.

Never read a file top-to-bottom as a first pass. Read the shape first (declarations, structure), then the paths that matter.

---

## 4. Dependency Graph Techniques

- **Import graph.** List what each module imports. The module imported by the most others is the core; the module importing the most others is the orchestrator. A cycle in the import graph is a finding, not a curiosity — record it.
- **Call graph for one flow.** Follow calls mechanically: function A calls B, B calls C. Note where the chain crosses a module boundary — that crossing is the seam to respect.
- **Data flow.** Trace one piece of data (a user setting, a downloaded model, a document) from creation to display. Data flow exposes hidden coupling: a value that is copied into five places, a cache that is written in one module and read in another.
- **Ownership graph.** Who creates, who retains, who destroys. In Swift this is visible in initialisers, stored properties, and `weak`/`unowned` annotations; see `MemoryResourceLifecycle.md`.

---

## 5. Failure Cases and Pitfalls

- **Reading everything.** The codebase is large; the budget is not. Reading without a question is browsing, not exploration.
- **Trusting names.** A file called `Manager` may manage nothing; a module called `Core` may be a dumping ground. Verify every name against its contents.
- **Trusting documentation over code.** READMEs and comments describe intent at the time they were written. The code describes current behaviour. When they conflict, the code wins and the conflict is a finding.
- **Assuming the happy path is the only path.** Error handling, migrations, and background work often live in separate files. A map that omits them will mislead the first bug fix.
- **Exploring in the wrong layer.** Tracing a UI bug through the persistence layer, or a data bug through the view hierarchy. Let the symptom choose the starting layer.
- **Not writing anything down.** An unwritten map is re-derived from scratch every session. The note is the deliverable of exploration.

## 6. Verification Steps

Before acting on an exploration:

1. The map names the entry points with file references, not guesses.
2. At least one real flow has been traced end to end through actual call sites.
3. Every module sentence in the map was checked against the module's public interface.
4. Open questions are listed explicitly, with the file or behaviour that would answer them.
5. The next task's starting file is identified — exploration that cannot name where work begins is incomplete.

## 7. Related Assets

- `ProjectContext.md` — what context to collect about a project before working in it.
- `AdvancedSoftwareArchitecture.md` — evaluating the structure the map reveals.
- `ComplexDebugging.md` — tracing a failure through an unfamiliar codebase.
- `GitHistoryForensics.md` — using history to explain why the code looks the way it does.
