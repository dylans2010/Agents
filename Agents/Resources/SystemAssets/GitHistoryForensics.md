<!-- system-index-depends: DocumentationWithGitHub.md, FileOperations.md -->

# Git History Forensics — Bisect, Blame Limits, Archaeology, and Regression Hunting

Practical guidance for using version history as a diagnostic tool: finding the commit that introduced a failure, understanding why code looks the way it does, and knowing where history's answers stop being trustworthy. This asset governs **history as evidence**; `DocumentationWithGitHub.md` governs working with remotes and pull requests, and `ComplexDebugging.md` governs the debugging method that history supports.

---

## 0. Scope and Purpose

Code tells you what it does. History tells you why — or at least, it tells you when it started doing it, who changed it, and what else changed at the same time. Forensic use of history is how a regression is traced to a single commit, how a mysterious workaround is explained, and how a "this has always been broken" claim is tested against evidence.

Use this asset when:

- A regression appeared and the introducing commit is unknown.
- A piece of code looks wrong, redundant, or inexplicable and you need its context.
- A bug fix needs to know whether the behaviour was ever correct.
- Reviewing a change whose history matters more than its diff.

Do not treat history as a courtroom. Commit messages are written by humans under time pressure; they are evidence, not testimony. Corroborate them against the code and the tests.

---

## 1. The Core Rules

- **History is evidence, not authority.** A commit message says what the author believed at the time. The diff says what they actually changed. When they disagree, the diff wins.
- **One fact per query.** Ask history one question at a time: when did this line change, which commit introduced this failure, what did this file look like then. Broad questions get noisy answers.
- **Never rewrite shared history to answer a question.** Forensics is read-only. Bisecting, blaming, and inspecting do not modify history; if an investigation needs an experiment, it happens on a scratch branch or a worktree.
- **A commit is the unit of causation.** A regression was introduced by a commit, not by a release, a branch, or a person. Find the commit.
- **Record what you found.** A forensic finding that lives only in a chat message will be re-derived next time. Note the commit, the conclusion, and the evidence in the fix, the review, or the issue.

---

## 2. Methodology: Finding the Regression Commit (Bisect)

When something that worked now fails, and the failure appeared somewhere in a range of commits:

1. **Define the predicate.** A runnable yes/no test: a script, a test case, or a manual step that answers "does this commit fail?" Cleanly and quickly. The predicate is the whole method — a vague predicate produces a vague answer.
2. **Establish the bounds.** A known-good commit (the last state where the behaviour was correct) and a known-bad commit (usually the current tip). Verify both bounds with the predicate before starting; a wrong bound invalidates the whole search.
3. **Bisect.** Test the midpoint. The answer halves the range. Repeat until one commit remains. `git bisect` automates this; the discipline is the same by hand.
4. **Verify the boundary.** Confirm the commit before the result passes and the commit itself fails, with the same predicate. A bisect that lands on a commit whose parent was never tested is unverified.
5. **Read the commit, not just its title.** The diff of the introducing commit is the cause — or the trigger. Distinguish the two: a commit can expose a pre-existing defect without being its cause. If the defect predates the commit, the commit is the trigger and the real cause is older.

### 2.1 When bisect misleads

- **The failure is flaky.** A predicate that answers wrongly some of the time sends the search down the wrong half. Make the predicate deterministic first — or run it multiple times per step and require agreement.
- **The failure depends on state outside the commit.** A database, a server, a file left by an earlier run. Reset the environment at every step, or the bisect measures the environment, not the commit.
- **The range contains a merge.** A merge commit's parents may each be fine while the merge itself is broken (a bad conflict resolution). Bisect across merges carefully, and test merge commits explicitly.
- **The range is too large to bisect by hand.** Narrow it first with dates, with release tags, or with a coarser predicate, then bisect the smaller range.

---

## 3. Methodology: Understanding a Line or a File (Blame and Log)

### 3.1 Blame

`git blame` shows, for each line, the last commit that touched it. It answers "when did this line last change" — and that is all it answers.

- **Blame the line, then blame the history.** The last commit to touch a line is often a refactor, a rename, or a formatting pass. The commit that introduced the logic is usually earlier. Follow the history past cosmetic changes.
- **Ignore bulk changes.** Formatting, renames, and mechanical refactors obscure blame. Use blame options that ignore whitespace or follow the history through the bulk change to find the substantive commit.
- **A line with no blame history is a finding.** Code that arrived in the initial import, with no commit explaining it, has no recorded rationale. Treat its intent as unknown, not as obvious.

### 3.2 Log

- **Log a file or a path** to see its history: when it was created, what changed it, and what the changes were for. A file with a long, varied history is a file with many owners and many reasons — read it with that in mind.
- **Log with a search** to find when a string, a function name, or a concept appeared or disappeared. Searching history for a removed identifier often finds the commit that removed it — and the reason given.
- **Log a range** to see what changed between two states: two releases, two branches, before and after a fix. The range is the change; read it as a whole, not commit by commit.

### 3.3 Show and diff

- **Show a commit** to see exactly what it changed, in full. Read the diff, not the message. A commit whose message says "fix" and whose diff changes five unrelated files is a commit that needs scrutiny.
- **Diff two states** to see the net change, ignoring the intermediate steps. Useful when the history is noisy and the question is "what is different now".

---

## 4. Archaeology: Why the Code Looks This Way

When code looks wrong but has survived, history usually explains it:

1. **Find the introducing commit.** When did this code arrive, and what did it replace?
2. **Read the message and the linked context.** The commit message, the pull request, the issue — what problem was being solved? What constraints existed then?
3. **Check what else changed at the same time.** A workaround introduced alongside a platform update, a dependency bump, or a deadline is a workaround for that moment, not a design decision.
4. **Check whether the constraint still exists.** The platform bug it worked around may be fixed; the dependency it accommodated may be gone; the deadline it served is past. A workaround whose reason has expired is removable — but only after verifying the behaviour it protected still holds.
5. **Check for the revert.** Sometimes the same code was added, removed, and added again. A re-addition after a revert means someone already tried removing it and something broke. Find out what.

Archaeology has a failure mode: **rationalising.** Finding a plausible reason for bad code and then defending the code because the reason sounds good. The question is not "was there a reason" — there almost always was — but "does the reason still hold, and does the code still serve it?"

---

## 5. Blame Limits: Where History Stops Being Trustworthy

- **Squashed and rebased history.** A squashed commit collapses many changes into one; a rebase rewrites authorship and dates. The history shows the final shape, not the process. Do not infer intent from the sequence of squashed commits.
- **Imported history.** Code imported from another repository, a snapshot, or a generated source has no meaningful history in this repository. Its real history lives elsewhere — or nowhere.
- **Co-authored and pair-programmed commits.** The author field names one person; the work may have been another's. Do not attribute decisions to the author field alone.
- **Messages written after the fact.** A commit message written during a rebase, a squash, or a history cleanup describes the change as the author remembers it, not as it happened.
- **The absence of a commit.** History shows what was committed, not what was considered and rejected, not what was tried and discarded, not what was never written down. Absence of evidence is not evidence of absence.
- **History as a performance record.** Using blame to assign fault for a defect is a misuse. History is a diagnostic tool; turning it into an accountability tool makes people avoid committing, squash aggressively, and write vague messages — which destroys the diagnostic value.

---

## 6. Regression Hunting Beyond Bisect

Not every regression has a clean bisectable range. Other approaches:

- **Date and release narrowing.** The regression appeared between two releases. Diff the releases, then bisect the diff's commits.
- **Feature-flag narrowing.** If the regression coincides with a feature being enabled, disable it and see whether the regression follows the flag.
- **Dependency narrowing.** If the regression coincides with a dependency update, pin the old version and see whether it follows the dependency. See `DependencyAuditing.md`.
- **Configuration narrowing.** If the regression appears in one configuration but not another, diff the configurations.
- **The suspicious commit.** A commit whose diff touches the failing area, whose message mentions the failing behaviour, or whose timing matches the first report. Test it directly — check out its parent, run the predicate, then the commit itself. One direct test beats ten inferences.

---

## 7. Failure Cases and Pitfalls

- **Bisecting with a broken predicate.** The most common failure. If the predicate is flaky, environment-dependent, or slow, fix the predicate before bisecting.
- **Blaming the last toucher.** The person who last formatted the line did not write the logic. Follow the history past cosmetic changes.
- **Reading the message instead of the diff.** Messages lie, or are vague, or describe intent rather than effect. The diff is the change.
- **Assuming the introducing commit is the cause.** A commit can trigger a latent defect. The fix belongs at the defect, not at the trigger — unless the trigger itself is wrong.
- **Forensics on a dirty tree.** Uncommitted changes, stashes, and mixed states contaminate every result. Start from a clean tree, or a dedicated worktree, and record the state you investigated.
- **Rewriting history during an investigation.** An investigation that rebases, amends, or force-pushes destroys the evidence it is studying. Forensics is read-only.

---

## 8. Verification Steps

Before claiming a forensic finding:

1. The predicate is defined, runnable, and verified at both bounds.
2. The introducing commit is identified and its boundary verified (parent passes, commit fails).
3. The commit's diff has been read — the cause or trigger is named in the diff, not just in the message.
4. Cosmetic changes have been followed past to the substantive commit where blame was used.
5. The finding is recorded with the commit hash, the predicate, and the conclusion.
6. The fix addresses the defect the commit introduced or exposed, and the regression test fails without the fix.

## 9. Related Assets

- `ComplexDebugging.md` — the debugging method that bisect serves.
- `SafeLegacyRefactoring.md` — understanding legacy code before changing it.
- `DocumentationWithGitHub.md` — remotes, pull requests, and the review context around commits.
- `TestingStrategy.md` — turning a found regression into a test that stays green.
