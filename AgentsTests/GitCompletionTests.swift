import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Git Completion: stash, blame, bisect, cherry-pick, rollback, snapshots over the FFI")
struct GitCompletionTests {

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/git-completion-\(UUID().uuidString.prefix(8).lowercased())")
        let dataDir = tempRoot.appendingPathComponent("d")
        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        return (client, tempRoot)
    }

    private struct GitFixtureError: Error {
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
            throw GitFixtureError(message: "git \(args.joined(separator: " ")) failed with status \(process.terminationStatus)")
        }
    }

    private static func gitOutput(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitFixtureError(message: "git \(args.joined(separator: " ")) failed with status \(process.terminationStatus)")
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/git-completion-repo-\(UUID().uuidString.prefix(8).lowercased())")
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
        try "see\n".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try runGit(root, ["add", "--", "c.txt"])
        try runGit(root, identity + ["commit", "-qm", "third"])
        return root
    }

    private static func makeThread(in repo: URL, client: AgentsRuntimeClient) async throws -> UUID {
        let projectID = try await client.createProject(path: repo.path)
        return try await client.newThread(projectID: projectID)
    }

    private static func runWorkspaceApiOperation(
        client: AgentsRuntimeClient,
        method: String,
        params: [String: JSONValue],
        timeoutSeconds: Int = 30
    ) async throws -> JSONValue {
        guard let threadID = params["threadId"]?.stringValue else {
            throw AgentsRuntimeError.desktopFailure("Workspace API operation requires a threadId.")
        }
        let started = try await client.engineRPC(method: method, params: params)
        guard let operationId = started["operationId"]?.stringValue else {
            return started
        }
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let polled = try await client.engineRPC(
                method: "git.workspace.result",
                params: [
                    "threadId": .string(threadID),
                    "operationId": .string(operationId),
                ]
            )
            if polled["ready"]?.boolValue == true {
                let result = polled["result"] ?? .object([:])
                if let errorText = result["error"]?.stringValue, !errorText.isEmpty {
                    throw AgentsRuntimeError.desktopFailure(errorText)
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AgentsRuntimeError.desktopFailure("Workspace API operation timed out.")
    }

    private static func canonicalRoot(_ repo: URL) -> String {
        URL(fileURLWithPath: repo.path).resolvingSymlinksInPath().path
    }

    private static func headSubject(
        repo: URL,
        client: AgentsRuntimeClient,
        thread: String
    ) async throws -> String {
        let value = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(1)]
        )
        return value["commits"]?.arrayValue?[0]["subject"]?.stringValue ?? ""
    }

    private static func logShas(
        client: AgentsRuntimeClient,
        thread: String
    ) async throws -> [String] {
        let value = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(10)]
        )
        return (value["commits"]?.arrayValue ?? []).compactMap { $0["sha"]?.stringValue }
    }

    private static func execute(
        _ tool: String,
        arguments: [String: JSONValue],
        client: AgentsRuntimeClient
    ) async throws -> JSONValue {
        try await SystemToolRegistry.execute(tool, arguments: arguments, toolset: .system, runtime: client)
    }

    @Test("git.stash push, list, show, and pop round-trip through the engine")
    func stashRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        try "one\ntwo\nthree\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let pushed = try await client.runWorkspaceOperation(
            method: "git.stash",
            params: ["threadId": .string(thread), "action": .string("push"), "message": .string("wip")]
        )
        #expect(pushed["pushed"]?.boolValue == true)
        #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "one\ntwo\n")
        let listed = try await client.runWorkspaceOperation(
            method: "git.stash",
            params: ["threadId": .string(thread), "action": .string("list")]
        )
        let entries = listed["stashes"]?.arrayValue ?? []
        #expect(entries.count == 1)
        #expect(entries[0]["subject"]?.stringValue?.contains("wip") == true)
        let reference = entries[0]["reference"]?.stringValue ?? ""
        let shown = try await client.runWorkspaceOperation(
            method: "git.stash",
            params: ["threadId": .string(thread), "action": .string("show"), "reference": .string(reference)]
        )
        #expect(shown["diff"]?.stringValue?.contains("+three") == true)
        do {
            _ = try await client.runWorkspaceOperation(
                method: "git.stash",
                params: ["threadId": .string(thread), "action": .string("pop"), "reference": .string(reference)]
            )
            Issue.record("Expected stash pop without confirm to throw")
        } catch {
            #expect(true)
        }
        let popped = try await client.runWorkspaceOperation(
            method: "git.stash",
            params: ["threadId": .string(thread), "action": .string("pop"), "reference": .string(reference), "confirm": .bool(true)]
        )
        #expect(popped["popped"]?.boolValue == true)
        #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "one\ntwo\nthree\n")
        let empty = try await client.runWorkspaceOperation(
            method: "git.stash",
            params: ["threadId": .string(thread), "action": .string("list")]
        )
        #expect((empty["stashes"]?.arrayValue ?? []).isEmpty)
        await client.close()
    }

    @Test("git.blame reads real authors and line numbers")
    func blameReadsAuthors() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let shas = try await Self.logShas(client: client, thread: thread)
        #expect(shas.count == 3)
        let value = try await client.runWorkspaceOperation(
            method: "git.blame",
            params: ["threadId": .string(thread), "path": .string("a.txt")]
        )
        let lines = value["lines"]?.arrayValue ?? []
        #expect(lines.count == 2)
        #expect(lines[0]["line"]?.intValue == 1)
        #expect(lines[0]["author"]?.stringValue == "Fixture")
        #expect(lines[0]["sha"]?.stringValue == shas[2])
        #expect(lines[1]["line"]?.intValue == 2)
        #expect(lines[1]["sha"]?.stringValue == shas[1])
        #expect(lines[1]["content"]?.stringValue == "two")
        let ranged = try await client.runWorkspaceOperation(
            method: "git.blame",
            params: ["threadId": .string(thread), "path": .string("a.txt"), "start": .int(2), "end": .int(2)]
        )
        #expect((ranged["lines"]?.arrayValue ?? []).count == 1)
        #expect(ranged["lines"]?.arrayValue?[0]["line"]?.intValue == 2)
        await client.close()
    }

    @Test("git.bisect finds the first bad commit")
    func bisectFindsFirstBad() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let shas = try await Self.logShas(client: client, thread: thread)
        let first = shas[2]
        let second = shas[1]
        let third = shas[0]
        let started = try await client.runWorkspaceOperation(
            method: "git.bisect",
            params: ["threadId": .string(thread), "action": .string("start"), "good": .string(first), "bad": .string(third)]
        )
        #expect(started["started"]?.boolValue == true)
        #expect(started["head"]?.stringValue == second)
        let marked = try await client.runWorkspaceOperation(
            method: "git.bisect",
            params: ["threadId": .string(thread), "action": .string("good"), "reference": .string(second)]
        )
        #expect(marked["head"]?.stringValue == third)
        #expect(marked["output"]?.stringValue?.contains("first bad commit") == true)
        let log = try await client.runWorkspaceOperation(
            method: "git.bisect",
            params: ["threadId": .string(thread), "action": .string("log")]
        )
        #expect(log["log"]?.stringValue?.contains("# good:") == true)
        let reset = try await client.runWorkspaceOperation(
            method: "git.bisect",
            params: ["threadId": .string(thread), "action": .string("reset")]
        )
        #expect(reset["reset"]?.boolValue == true)
        #expect(try await Self.headSubject(repo: repo, client: client, thread: thread) == "third")
        await client.close()
    }

    @Test("git.cherry_pick applies a clean commit and reports conflicts without aborting")
    func cherryPickAppliesAndReportsConflicts() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false"]
        try runGit(repo, ["checkout", "-qb", "pickable"])
        try "dee\n".write(to: repo.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
        try runGit(repo, ["add", "--", "d.txt"])
        try runGit(repo, identity + ["commit", "-qm", "pick me"])
        let pickableSha = try await Self.logShas(client: client, thread: thread)[0]
        try runGit(repo, ["checkout", "-q", "-"])
        try runGit(repo, ["checkout", "-qb", "feature"])
        try "feature-one\ntwo\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(repo, ["add", "--", "a.txt"])
        try runGit(repo, identity + ["commit", "-qm", "feature change"])
        let featureSha = try await Self.logShas(client: client, thread: thread)[0]
        try runGit(repo, ["checkout", "-q", "-"])
        try "main-one\ntwo\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(repo, ["add", "--", "a.txt"])
        try runGit(repo, identity + ["commit", "-qm", "main change"])
        let applied = try await client.runWorkspaceOperation(
            method: "git.cherry_pick",
            params: ["threadId": .string(thread), "sha": .string(pickableSha), "confirm": .bool(true)]
        )
        #expect(applied["applied"]?.boolValue == true)
        #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("d.txt").path))
        let conflicted = try await client.runWorkspaceOperation(
            method: "git.cherry_pick",
            params: ["threadId": .string(thread), "sha": .string(featureSha), "confirm": .bool(true)]
        )
        #expect(conflicted["applied"]?.boolValue == false)
        #expect((conflicted["conflicts"]?.arrayValue ?? []).compactMap { $0.stringValue }.contains("a.txt"))
        try runGit(repo, ["cherry-pick", "--abort"])
        await client.close()
    }

    @Test("git.rollback requires confirm and only accepts the allow-list")
    func rollbackGateAndAllowList() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        do {
            _ = try await client.runWorkspaceOperation(
                method: "git.rollback",
                params: ["threadId": .string(thread), "ref": .string("HEAD~1")]
            )
            Issue.record("Expected rollback without confirm to throw")
        } catch {
            #expect(true)
        }
        do {
            _ = try await client.runWorkspaceOperation(
                method: "git.rollback",
                params: ["threadId": .string(thread), "ref": .string("main"), "confirm": .bool(true)]
            )
            Issue.record("Expected rollback of a branch name to throw")
        } catch {
            #expect(true)
        }
        let rolled = try await client.runWorkspaceOperation(
            method: "git.rollback",
            params: ["threadId": .string(thread), "ref": .string("HEAD~1"), "confirm": .bool(true)]
        )
        #expect(rolled["rolledBack"]?.boolValue == true)
        #expect(try await Self.headSubject(repo: repo, client: client, thread: thread) == "second")
        await client.close()
    }

    @Test("Checkpoints create, list, and restore through the workspace API")
    func checkpointCreateListRestore() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let root = Self.canonicalRoot(repo)
        let head = try await Self.logShas(client: client, thread: thread)[0]
        let created = try await Self.runWorkspaceApiOperation(
            client: client,
            method: "git.checkpoints.create",
            params: ["threadId": .string(thread), "expectedRoot": .string(root), "expectedHead": .string(head), "label": .string("before edit")]
        )
        let checkpointId = created["id"]?.stringValue ?? ""
        #expect(!checkpointId.isEmpty)
        let listed = try await Self.runWorkspaceApiOperation(
            client: client,
            method: "git.checkpoints.list",
            params: ["threadId": .string(thread), "expectedRoot": .string(root)]
        )
        let checkpoints = listed["checkpoints"]?.arrayValue ?? []
        #expect(checkpoints.count == 1)
        #expect(checkpoints[0]["id"]?.stringValue == checkpointId)
        try "one\ntwo\nCHANGED\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "untracked\n".write(to: repo.appendingPathComponent("u.txt"), atomically: true, encoding: .utf8)
        do {
            _ = try await Self.runWorkspaceApiOperation(
                client: client,
                method: "git.checkpoints.restore",
                params: ["threadId": .string(thread), "expectedRoot": .string(root), "checkpointId": .string(checkpointId)]
            )
            Issue.record("Expected checkpoint restore without confirm to throw")
        } catch {
            #expect(true)
        }
        let restored = try await Self.runWorkspaceApiOperation(
            client: client,
            method: "git.checkpoints.restore",
            params: ["threadId": .string(thread), "expectedRoot": .string(root), "checkpointId": .string(checkpointId), "confirm": .bool(true)]
        )
        #expect(restored["restored"]?.boolValue == true)
        #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "one\ntwo\n")
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("u.txt").path))
        await client.close()
    }

    @Test("project_snapshot, project_changelog, project_restore, and safe_undo compose over checkpoints")
    func snapshotChangelogRestoreSafeUndo() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let first = try await Self.execute(
            "project_snapshot",
            arguments: ["threadId": .string(thread), "label": .string("at third")],
            client: client
        )
        #expect(!(first["id"]?.stringValue ?? "").isEmpty)
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false"]
        try "four\n".write(to: repo.appendingPathComponent("e.txt"), atomically: true, encoding: .utf8)
        try runGit(repo, ["add", "--", "e.txt"])
        try runGit(repo, identity + ["commit", "-qm", "fourth"])
        let second = try await Self.execute(
            "project_snapshot",
            arguments: ["threadId": .string(thread), "label": .string("at fourth")],
            client: client
        )
        #expect(!(second["id"]?.stringValue ?? "").isEmpty)
        let changelog = try await Self.execute(
            "project_changelog",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        let checkpoints = changelog["checkpoints"]?.arrayValue ?? []
        #expect(checkpoints.count == 2)
        try "one\ntwo\nDIRTY\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let undone = try await Self.execute(
            "safe_undo",
            arguments: ["threadId": .string(thread), "confirm": .bool(true)],
            client: client
        )
        #expect(undone["restoredId"]?.stringValue == first["id"]?.stringValue)
        #expect(try await Self.headSubject(repo: repo, client: client, thread: thread) == "third")
        #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "one\ntwo\n")
        await client.close()
    }

    @Test("git_branch_manager deletes a branch through the engine")
    func branchManagerDelete() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        try runGit(repo, ["branch", "spare"])
        let listed = try await client.runGitActionsOperation(
            method: "git.branches.list",
            params: ["threadId": .string(thread)]
        )
        let names = (listed["branches"]?["branches"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        #expect(names.contains("spare"))
        do {
            _ = try await Self.execute(
                "git_branch_manager",
                arguments: ["threadId": .string(thread), "action": .string("delete"), "name": .string("spare")],
                client: client
            )
            Issue.record("Expected branch delete without confirm to throw")
        } catch {
            #expect(true)
        }
        let deleted = try await Self.execute(
            "git_branch_manager",
            arguments: ["threadId": .string(thread), "action": .string("delete"), "name": .string("spare"), "confirm": .bool(true)],
            client: client
        )
        #expect(deleted["deleted"]?.boolValue == true)
        let relisted = try await client.runGitActionsOperation(
            method: "git.branches.list",
            params: ["threadId": .string(thread)]
        )
        let remaining = (relisted["branches"]?["branches"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        #expect(!remaining.contains("spare"))
        await client.close()
    }

    @Test("git_pr_summary composes log and diff into markdown")
    func prSummaryMarkdown() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let shas = try await Self.logShas(client: client, thread: thread)
        let summary = try await Self.execute(
            "git_pr_summary",
            arguments: ["threadId": .string(thread), "from": .string(shas[2]), "to": .string(shas[0]), "limit": .int(10)],
            client: client
        )
        let markdown = summary["markdown"]?.stringValue ?? ""
        #expect(markdown.contains("# PR Summary"))
        #expect(markdown.contains("second"))
        #expect(markdown.contains("third"))
        #expect(markdown.contains("b.txt"))
        #expect(markdown.contains("c.txt"))
        #expect(summary["commits"]?.intValue == 3)
        await client.close()
    }

    @Test("git_conflict_resolver detects markers and resolves them")
    func conflictResolverDetectAndResolve() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let conflicted = "top\n<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> feature\nbottom\n"
        try conflicted.write(to: repo.appendingPathComponent("conf.txt"), atomically: true, encoding: .utf8)
        let detected = try await Self.execute(
            "git_conflict_resolver",
            arguments: ["cwd": .string(repo.path), "action": .string("detect")],
            client: client
        )
        #expect((detected["conflictedFiles"]?.arrayValue ?? []).compactMap { $0.stringValue }.contains("conf.txt"))
        let resolved = try await Self.execute(
            "git_conflict_resolver",
            arguments: ["cwd": .string(repo.path), "path": .string("conf.txt"), "action": .string("resolve"), "strategy": .string("ours")],
            client: client
        )
        #expect(resolved["resolved"]?.boolValue == true)
        #expect(resolved["hunks"]?.intValue == 1)
        let text = try String(contentsOf: repo.appendingPathComponent("conf.txt"), encoding: .utf8)
        #expect(text == "top\nours line\nbottom\n")
        await client.close()
    }

    @Test("safe_validate_changes finds markers and missing trailing newlines")
    func validateChangesFindsIssues() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try "top\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> feature\n".write(to: repo.appendingPathComponent("bad.txt"), atomically: true, encoding: .utf8)
        try "clean".write(to: repo.appendingPathComponent("nonl.txt"), atomically: true, encoding: .utf8)
        try "clean\n".write(to: repo.appendingPathComponent("good.txt"), atomically: true, encoding: .utf8)
        let bad = try await Self.execute(
            "safe_validate_changes",
            arguments: ["cwd": .string(repo.path), "path": .string("bad.txt")],
            client: client
        )
        #expect((bad["count"]?.intValue ?? 0) >= 3)
        let noNewline = try await Self.execute(
            "safe_validate_changes",
            arguments: ["cwd": .string(repo.path), "path": .string("nonl.txt")],
            client: client
        )
        #expect(noNewline["count"]?.intValue == 1)
        #expect(noNewline["issues"]?.arrayValue?[0]["issue"]?.stringValue?.contains("trailing newline") == true)
        let good = try await Self.execute(
            "safe_validate_changes",
            arguments: ["cwd": .string(repo.path), "path": .string("good.txt")],
            client: client
        )
        #expect(good["count"]?.intValue == 0)
        await client.close()
    }

    @Test("file_create refuses an existing file and code_insert plus tree_view compose over real files")
    func fileCreateGuardCodeInsertTreeView() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        _ = try await Self.execute(
            "file_create",
            arguments: ["cwd": .string(repo.path), "path": .string("new.txt"), "content": .string("hello\n")],
            client: client
        )
        do {
            _ = try await Self.execute(
                "file_create",
                arguments: ["cwd": .string(repo.path), "path": .string("new.txt"), "content": .string("again\n")],
                client: client
            )
            Issue.record("Expected a second file_create to throw")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "file_create", message: "A file already exists at that path; use write_file to overwrite it."))
        } catch {
            Issue.record("Unexpected error for second file_create: \(error)")
        }
        try "alpha\nbeta\n".write(to: repo.appendingPathComponent("insert.txt"), atomically: true, encoding: .utf8)
        _ = try await Self.execute(
            "code_insert",
            arguments: ["cwd": .string(repo.path), "path": .string("insert.txt"), "code": .string("zero"), "mode": .string("line"), "line": .int(1)],
            client: client
        )
        #expect(try String(contentsOf: repo.appendingPathComponent("insert.txt"), encoding: .utf8) == "zero\nalpha\nbeta\n")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "nested\n".write(to: repo.appendingPathComponent("sub/nested.txt"), atomically: true, encoding: .utf8)
        let shallow = try await Self.execute(
            "tree_view",
            arguments: ["cwd": .string(repo.path), "maxDepth": .int(1)],
            client: client
        )
        let shallowPaths = (shallow.arrayValue ?? []).compactMap { $0["path"]?.stringValue }
        #expect(!shallowPaths.isEmpty)
        #expect(shallowPaths.allSatisfy { !$0.contains("/") })
        let deep = try await Self.execute(
            "tree_view",
            arguments: ["cwd": .string(repo.path), "maxDepth": .int(2)],
            client: client
        )
        let deepPaths = (deep.arrayValue ?? []).compactMap { $0["path"]?.stringValue }
        #expect(deepPaths.contains("sub/nested.txt"))
        await client.close()
    }

    @Test("use_mcp lists the coincide server and executes a system tool through it")
    func useMcpListsAndExecutes() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let servers = try await Self.execute(
            "use_mcp",
            arguments: ["serverName": .string("list")],
            client: client
        )
        let names = (servers.arrayValue ?? []).compactMap { $0["serverName"]?.stringValue }
        #expect(names.contains("coincide"))
        let tools = try await Self.execute(
            "use_mcp",
            arguments: ["serverName": .string("coincide"), "toolName": .string("list_tools")],
            client: client
        )
        let toolNames = (tools.arrayValue ?? []).compactMap { $0.stringValue }
        #expect(toolNames.contains("read_file"))
        #expect(toolNames.contains("git_stash_operator"))
        let read = try await Self.execute(
            "use_mcp",
            arguments: [
                "serverName": .string("coincide"),
                "toolName": .string("read_file"),
                "arguments": .string("{\"cwd\": \"\(repo.path)\", \"path\": \"a.txt\"}"),
            ],
            client: client
        )
        #expect(read["content"]?.stringValue?.contains("one") == true)
        await client.close()
    }

    @Test("list_files lists the fixture files through execute()")
    func listFilesListsFixtureFiles() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let listed = try await Self.execute(
            "list_files",
            arguments: ["cwd": .string(repo.path)],
            client: client
        )
        let paths = (listed.arrayValue ?? []).compactMap { $0["path"]?.stringValue }
        #expect(paths.contains("a.txt"))
        #expect(paths.contains("b.txt"))
        #expect(paths.contains("c.txt"))
        await client.close()
    }

    @Test("git_status reports the branch and dirty entries through execute()")
    func gitStatusReportsBranchAndDirtyEntries() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        try "one\ntwo\nthree\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let status = try await Self.execute(
            "git_status",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        #expect(!(status["branch"]?.stringValue ?? "").isEmpty)
        let entries = status["entries"]?.arrayValue ?? []
        let dirty = entries.first { $0["path"]?.stringValue == "a.txt" }
        #expect(dirty != nil)
        #expect(dirty?["status"]?.stringValue?.contains("M") == true)
        await client.close()
    }

    @Test("git_diff returns the unstaged diff through execute()")
    func gitDiffReturnsUnstagedDiff() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        try "one\ntwo\nthree\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let diff = try await Self.execute(
            "git_diff",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        #expect(diff["staged"]?.boolValue == false)
        #expect(diff["diff"]?.stringValue?.contains("a.txt") == true)
        #expect(diff["diff"]?.stringValue?.contains("+three") == true)
        await client.close()
    }

    @Test("git_log returns the fixture commits through execute()")
    func gitLogReturnsFixtureCommits() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let log = try await Self.execute(
            "git_log",
            arguments: ["threadId": .string(thread), "limit": .int(10)],
            client: client
        )
        let commits = log["commits"]?.arrayValue ?? []
        #expect(commits.count == 3)
        #expect(commits.map { $0["subject"]?.stringValue ?? "" } == ["third", "second", "first"])
        #expect(commits[0]["authorName"]?.stringValue == "Fixture")
        await client.close()
    }

    @Test("git_push publishes the branch to a local bare remote through execute()")
    func gitPushPublishesToLocalBareRemote() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let bare = tempRoot.appendingPathComponent("bare.git")
        _ = try Self.gitOutput(["init", "--bare", "-q", bare.path])
        try runGit(repo, ["remote", "add", "origin", bare.path])
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let branch = try Self.gitOutput(["-C", repo.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let pushed = try await Self.execute(
            "git_push",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        #expect(pushed["result"]?["push"]?["outcome"]?.stringValue == "pushed")
        #expect(pushed["result"]?["push"]?["upstream"]?.stringValue == "origin/\(branch)")
        let head = try Self.gitOutput(["-C", repo.path, "rev-parse", "HEAD"])
        let remoteHead = try Self.gitOutput(["--git-dir", bare.path, "rev-parse", "refs/heads/\(branch)"])
        #expect(remoteHead == head)
        await client.close()
    }

    @Test("git_pull fetches a commit from a local bare remote through execute()")
    func gitPullFetchesFromLocalBareRemote() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let bare = tempRoot.appendingPathComponent("bare.git")
        _ = try Self.gitOutput(["init", "--bare", "-q", bare.path])
        try runGit(repo, ["remote", "add", "origin", bare.path])
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let branch = try Self.gitOutput(["-C", repo.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let pushed = try await Self.execute(
            "git_push",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        #expect(pushed["result"]?["push"]?["outcome"]?.stringValue == "pushed")
        _ = try Self.gitOutput(["--git-dir", bare.path, "symbolic-ref", "HEAD", "refs/heads/\(branch)"])
        let clone = tempRoot.appendingPathComponent("clone")
        _ = try Self.gitOutput(["clone", "-q", bare.path, clone.path])
        try runGit(clone, ["checkout", "-q", branch])
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false"]
        try "from the remote\n".write(to: clone.appendingPathComponent("remote.txt"), atomically: true, encoding: .utf8)
        try runGit(clone, ["add", "--", "remote.txt"])
        try runGit(clone, identity + ["commit", "-qm", "from remote"])
        try runGit(clone, ["push", "-q", "origin", branch])
        let pulled = try await Self.execute(
            "git_pull",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        #expect(pulled["pulled"]?.boolValue == true)
        #expect(try String(contentsOf: repo.appendingPathComponent("remote.txt"), encoding: .utf8) == "from the remote\n")
        await client.close()
    }

    @Test("git_branch_list lists local branches through execute()")
    func gitBranchListListsLocalBranches() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        try runGit(repo, ["branch", "spare"])
        let listed = try await Self.execute(
            "git_branch_list",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        let branches = listed["branches"]?["branches"]?.arrayValue ?? []
        let names = branches.compactMap { $0["name"]?.stringValue }
        #expect(names.contains("spare"))
        let current = listed["branches"]?["currentBranch"]?.stringValue ?? ""
        #expect(!current.isEmpty)
        #expect(branches.first { $0["isCurrent"]?.boolValue == true }?["name"]?.stringValue == current)
        await client.close()
    }

    @Test("git_branch_checkout switches branches through execute()")
    func gitBranchCheckoutSwitchesBranches() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        try runGit(repo, ["branch", "spare"])
        let switched = try await Self.execute(
            "git_branch_checkout",
            arguments: ["threadId": .string(thread), "name": .string("spare")],
            client: client
        )
        #expect(switched["branch"]?.stringValue == "spare")
        let status = try await Self.execute(
            "git_status",
            arguments: ["threadId": .string(thread)],
            client: client
        )
        #expect(status["branch"]?.stringValue == "spare")
        await client.close()
    }
}
