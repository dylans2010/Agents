import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant Change Ledger: pre-run snapshots, real post-run diffs, read-only and failure rules")
struct AssistantChangeLedgerTests {

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/ledger-\(UUID().uuidString.prefix(8).lowercased())")
        let dataDir = tempRoot.appendingPathComponent("d")
        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        return (client, tempRoot)
    }

    private struct LedgerFixtureError: Error {
        let message: String
    }

    private static func runGit(_ repo: URL, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repo.path] + args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LedgerFixtureError(message: "git \(args.joined(separator: " ")) failed with status \(process.terminationStatus)")
        }
    }

    private static func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/ledger-repo-\(UUID().uuidString.prefix(8).lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(root, ["init", "-q"])
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false"]
        try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(root, ["add", "--", "a.txt"])
        try runGit(root, identity + ["commit", "-qm", "first"])
        try "one\ntwo\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "bee\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try runGit(root, ["add", "--", "a.txt", "b.txt"])
        try runGit(root, identity + ["commit", "-qm", "second"])
        return root
    }

    private static func makePlainDirectory() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/ledger-plain-\(UUID().uuidString.prefix(8).lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func makeThread(in repo: URL, client: AgentsRuntimeClient) async throws -> UUID {
        let projectID = try await client.createProject(path: repo.path)
        return try await client.newThread(projectID: projectID)
    }

    private static func headSHA(client: AgentsRuntimeClient, thread: String) async throws -> String {
        let value = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(1)]
        )
        return value["commits"]?.arrayValue?[0]["sha"]?.stringValue ?? ""
    }

    private static func samplePatch() -> String {
        [
            "diff --git a/a.txt b/a.txt",
            "index 1111111..2222222 100644",
            "--- a/a.txt",
            "+++ b/a.txt",
            "@@ -1,2 +1,3 @@",
            " one",
            " two",
            "+three",
            "diff --git a/d.txt b/d.txt",
            "new file mode 100644",
            "index 0000000..3333333",
            "--- /dev/null",
            "+++ b/d.txt",
            "@@ -0,0 +1 @@",
            "+fresh",
        ].joined(separator: "\n")
    }

    private static func sampleNumstat() -> JSONValue {
        .array([
            .object(["path": .string("a.txt"), "additions": .int(1), "deletions": .int(0)]),
            .object(["path": .string("d.txt"), "additions": .int(1), "deletions": .int(0)]),
        ])
    }

    @Test("Pre-run snapshot records HEAD, worktree status, and a stable status hash")
    func snapshotRecordsPreState() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let expectedHead = try await Self.headSHA(client: client, thread: thread)
        #expect(!expectedHead.isEmpty)
        let ledger = AssistantChangeLedger(runtime: client)
        let snapshot = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        #expect(snapshot != nil)
        #expect(snapshot?.headSHA == expectedHead)
        #expect(snapshot?.isClean == true)
        #expect(snapshot?.entries.isEmpty == true)
        #expect(snapshot?.canonicalRoot != nil)
        let firstHash = snapshot?.statusHash ?? ""
        #expect(!firstHash.isEmpty)
        try "one\ntwo\nCHANGED\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let second = try await ledger.beginRun(
            runId: UUID().uuidString,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        #expect(second?.isClean == false)
        #expect(second?.entries.count == 1)
        #expect(second?.entries.first?.path == "a.txt")
        #expect(second?.entries.first?.status == " M")
        #expect(second?.statusHash != firstHash)
        #expect(second?.statusHash == AssistantChangeLedger.statusHash(entries: second?.entries ?? []))
        await client.close()
    }

    @Test("A second beginRun on the same unfinished run throws runAlreadyActive")
    func secondBeginRunThrowsRunAlreadyActive() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        do {
            _ = try await ledger.beginRun(
                runId: thread,
                assistantId: UUID().uuidString,
                permissionProfile: .workspaceModify
            )
            Issue.record("Expected a second beginRun on an unfinished run to throw")
        } catch let error as AssistantChangeLedgerError {
            if case .runAlreadyActive = error {
                #expect(true)
            } else {
                Issue.record("Expected runAlreadyActive, got \(error)")
            }
        }
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry != nil)
        #expect(entry?.outcome?.kind == .empty)
        await client.close()
    }

    @Test("Post-run diff attaches real file entries with per-file patches")
    func diffAttachedWithRealFileEntries() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        try "one\ntwo\nthree\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "fresh\n".write(to: repo.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .changed)
        let files = entry?.outcome?.changeSet?.files ?? []
        let paths = files.map(\.path)
        #expect(paths.contains("a.txt"))
        #expect(paths.contains("d.txt"))
        let changed = files.first { $0.path == "a.txt" }
        #expect(changed?.status == "modified")
        #expect(changed?.patch.contains("+three") == true)
        #expect(changed?.additions == 1)
        let added = files.first { $0.path == "d.txt" }
        #expect(added?.status == "added" || added?.status == "untracked")
        #expect(added?.patch.contains("+fresh") == true)
        #expect(await ledger.hasModifications(runId: thread) == true)
        #expect(await ledger.reviewChanges(runId: thread)?.kind == .changed)
        await client.close()
    }

    @Test("An unchanged run reports an explicit empty diff, never a hidden one")
    func emptyDiffReportedExplicitly() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .empty)
        #expect(entry?.outcome?.changeSet?.files.isEmpty == true)
        #expect(await ledger.hasModifications(runId: thread) == false)
        #expect(await ledger.reviewChanges(runId: thread)?.kind == .empty)
        await client.close()
    }

    @Test("Pre-existing untracked files make an empty post-run diff unavailable, not empty")
    func preExistingUntrackedFilesMakeEmptyDiffUnavailable() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try "scratch\n".write(to: repo.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        let snapshot = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        #expect(snapshot?.entries.contains(where: { $0.status == "??" && $0.path == "notes.txt" }) == true)
        try FileManager.default.removeItem(at: repo.appendingPathComponent("notes.txt"))
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .unavailable)
        #expect(!(entry?.outcome?.unavailableReason ?? "").isEmpty)
        await client.close()
    }

    @Test("More than 5,000 untracked files are reported unavailable, never empty")
    func overLimitUntrackedFilesAreNotReportedEmpty() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        for index in 0..<5_001 {
            try Data().write(to: repo.appendingPathComponent("bulk-\(index).txt"))
        }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .unavailable)
        #expect(!(entry?.outcome?.unavailableReason ?? "").isEmpty)
        await client.close()
    }

    @Test("A read-only run creates no snapshot and is reported as read-only")
    func readOnlyRunCreatesNoSnapshot() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        let snapshot = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .readOnly
        )
        #expect(snapshot == nil)
        #expect(await ledger.snapshot(runId: thread) == nil)
        #expect(await ledger.entry(runId: thread)?.snapshot == nil)
        try "one\ntwo\nthree\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .readOnly)
        #expect(entry?.snapshot == nil)
        #expect(await ledger.hasModifications(runId: thread) == false)
        await client.close()
    }

    @Test("A snapshot failure blocks the run and records no entry")
    func snapshotFailureBlocksRun() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let plain = try Self.makePlainDirectory()
        defer { try? FileManager.default.removeItem(at: plain) }
        let threadID = try await Self.makeThread(in: plain, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        do {
            _ = try await ledger.beginRun(
                runId: thread,
                assistantId: UUID().uuidString,
                permissionProfile: .workspaceModify
            )
            Issue.record("Expected beginRun outside a Git repository to throw")
        } catch let error as AssistantChangeLedgerError {
            if case .snapshotFailed = error {
                #expect(true)
            } else {
                Issue.record("Expected snapshotFailed, got \(error)")
            }
        }
        #expect(await ledger.entry(runId: thread) == nil)
        await client.close()
    }

    @Test("A post-run diff failure marks the record unavailable, never empty")
    func diffFailureMarksUnavailable() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        try FileManager.default.removeItem(at: repo)
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .unavailable)
        #expect(!(entry?.outcome?.unavailableReason ?? "").isEmpty)
        #expect(await ledger.hasModifications(runId: thread) == false)
        #expect(await ledger.reviewChanges(runId: thread)?.kind == .unavailable)
        await client.close()
    }

    @Test("A change committed during the run surfaces with its commit flag")
    func committedChangeSurfacesInDiff() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        try "one\ntwo\ncommitted\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false"]
        try Self.runGit(repo, ["add", "--", "a.txt"])
        try Self.runGit(repo, identity + ["commit", "-qm", "run commit"])
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .changed)
        let changeSet = entry?.outcome?.changeSet
        #expect(changeSet?.committedDuringRun == true)
        #expect(changeSet?.committedPaths.contains("a.txt") == true)
        #expect(changeSet?.files.map(\.path).contains("a.txt") == true)
        #expect(await ledger.hasModifications(runId: thread) == true)
        await client.close()
    }

    @Test("A binary file committed during the run surfaces with the engine's counts")
    func committedBinaryFileSurfacesWithEngineCounts() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        try Data([0x00, 0x01, 0x02, 0x03, 0x62, 0x69, 0x6e, 0x61, 0x72, 0x79]).write(to: repo.appendingPathComponent("bin.dat"))
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false"]
        try Self.runGit(repo, ["add", "--", "bin.dat"])
        try Self.runGit(repo, identity + ["commit", "-qm", "add binary"])
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .changed)
        let changeSet = entry?.outcome?.changeSet
        #expect(changeSet?.committedDuringRun == true)
        #expect(changeSet?.committedPaths.contains("bin.dat") == true)
        let binary = changeSet?.files.first { $0.path == "bin.dat" }
        #expect(binary != nil)
        #expect(binary?.isBinary == true)
        #expect(binary?.status == "added")
        #expect(binary?.additions == 0)
        #expect(binary?.deletions == 0)
        await client.close()
    }

    @Test("Pre-existing dirt stays listed and flagged, never hidden or attributed to the run")
    func preExistingDirtIsFlaggedNotHidden() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try "one\ntwo\nPRE-EXISTING\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let ledger = AssistantChangeLedger(runtime: client)
        _ = try await ledger.beginRun(
            runId: thread,
            assistantId: UUID().uuidString,
            permissionProfile: .workspaceModify
        )
        try "fresh\n".write(to: repo.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
        let entry = await ledger.finishRun(runId: thread)
        #expect(entry?.outcome?.kind == .changed)
        let changeSet = entry?.outcome?.changeSet
        #expect(changeSet?.files.map(\.path).contains("a.txt") == true)
        #expect(changeSet?.files.map(\.path).contains("d.txt") == true)
        #expect(changeSet?.preExistingPaths.contains("a.txt") == true)
        #expect(changeSet?.preExistingPaths.contains("d.txt") == false)
        await client.close()
    }

    @Test("Status hash is deterministic and moves with the entries")
    func statusHashIsDeterministic() {
        let entries = [
            AssistantStatusEntry(status: " M", path: "a.txt"),
            AssistantStatusEntry(status: "??", path: "b.txt"),
        ]
        let first = AssistantChangeLedger.statusHash(entries: entries)
        let reordered = AssistantChangeLedger.statusHash(entries: entries.reversed())
        #expect(first == reordered)
        #expect(!first.isEmpty)
        let changed = AssistantChangeLedger.statusHash(entries: [
            AssistantStatusEntry(status: " M", path: "a.txt"),
            AssistantStatusEntry(status: "??", path: "c.txt"),
        ])
        #expect(changed != first)
        #expect(AssistantChangeLedger.statusHash(entries: []) != first)
    }

    @Test("Diff building splits a real patch and overlays numstat counts")
    func buildDiffParsesRealPatch() {
        let diff = AssistantChangeLedger.buildDiff(
            patch: Self.samplePatch(),
            numstat: Self.sampleNumstat(),
            untracked: [],
            title: "Assistant changes"
        )
        #expect(diff.files.count == 2)
        let changed = diff.files.first { $0.path == "a.txt" }
        #expect(changed?.status == "modified")
        #expect(changed?.additions == 1)
        #expect(changed?.deletions == 0)
        #expect(changed?.patch.contains("+three") == true)
        let added = diff.files.first { $0.path == "d.txt" }
        #expect(added?.status == "added")
        #expect(added?.additions == 1)
        #expect(added?.patch.contains("+fresh") == true)
        #expect(diff.isTruncated == false)
    }

    @Test("Untracked files with no patch text are kept as untracked entries")
    func buildDiffKeepsUntrackedWithoutPatch() {
        let diff = AssistantChangeLedger.buildDiff(
            patch: Self.samplePatch(),
            numstat: Self.sampleNumstat(),
            untracked: ["notes.txt"],
            title: "Assistant changes"
        )
        #expect(diff.files.count == 3)
        let untracked = diff.files.first { $0.path == "notes.txt" }
        #expect(untracked?.status == "untracked")
        #expect(untracked?.patch.isEmpty == true)
    }

    @Test("Diff building overlays engine numstat counts onto a binary patch entry")
    func buildDiffOverlaysEngineCountsOntoBinaryPatchEntry() {
        let patch = [
            "diff --git a/bin.dat b/bin.dat",
            "index 5d27a55..64e424d 100644",
            "Binary files a/bin.dat and b/bin.dat differ",
        ].joined(separator: "\n")
        let diff = AssistantChangeLedger.buildDiff(
            patch: patch,
            numstat: .array([
                .object(["path": .string("bin.dat"), "additions": .int(3), "deletions": .int(2)]),
            ]),
            untracked: [],
            title: "Assistant changes"
        )
        #expect(diff.files.count == 1)
        let binary = diff.files.first
        #expect(binary?.path == "bin.dat")
        #expect(binary?.isBinary == true)
        #expect(binary?.additions == 3)
        #expect(binary?.deletions == 2)
        #expect(binary?.patch.isEmpty == true)
    }

    @Test("Status parsing keeps rename sources and drops malformed entries")
    func parseStatusEntriesKeepsRenames() {
        let value: JSONValue = .object([
            "branch": .string("main"),
            "entries": .array([
                .object(["status": .string("R "), "path": .string("new.txt"), "originalPath": .string("old.txt")]),
                .object(["status": .string(" M"), "path": .string("a.txt")]),
                .object(["status": .string(""), "path": .string("broken.txt")]),
                .object(["path": .string("missing-status.txt")]),
            ]),
        ])
        let entries = AssistantChangeLedger.parseStatusEntries(value)
        #expect(entries.count == 2)
        #expect(entries.first?.path == "new.txt")
        #expect(entries.first?.originalPath == "old.txt")
        #expect(entries.first?.status == "R ")
        #expect(entries.last?.path == "a.txt")
    }
}
