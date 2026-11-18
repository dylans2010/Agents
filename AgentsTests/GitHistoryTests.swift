import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Git History: log, show, range and branch diffs over the FFI")
struct GitHistoryTests {

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/git-history-\(UUID().uuidString.prefix(8).lowercased())")
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

    private static func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/git-history-repo-\(UUID().uuidString.prefix(8).lowercased())")
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

    private static func makeThread(in repo: URL, client: AgentsRuntimeClient) async throws -> UUID {
        let projectID = try await client.createProject(path: repo.path)
        return try await client.newThread(projectID: projectID)
    }

    @Test("git.log lists real commits through the engine")
    func logListsCommits() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let value = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(10)]
        )
        let commits = value["commits"]?.arrayValue ?? []
        #expect(commits.count == 2)
        #expect(commits[0]["subject"]?.stringValue == "second")
        #expect(commits[1]["subject"]?.stringValue == "first")
        #expect(commits[0]["authorName"]?.stringValue == "Fixture")
        #expect(commits[0]["authorEmail"]?.stringValue == "fixture@example.invalid")
        #expect((commits[0]["authorDate"]?.doubleValue ?? 0) > 0)
        #expect(commits[0]["parents"]?.arrayValue?.count == 1)
        #expect(commits[1]["parents"]?.arrayValue?.count == 0)
        let paged = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(1), "skip": .int(1)]
        )
        #expect(paged["commits"]?.arrayValue?.count == 1)
        #expect(paged["commits"]?.arrayValue?[0]["subject"]?.stringValue == "first")
        await client.close()
    }

    @Test("git.show returns the commit, its files, and its diff")
    func showReturnsCommitFilesAndDiff() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let value = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(10)]
        )
        let sha = value["commits"]?.arrayValue?[0]["sha"]?.stringValue ?? ""
        #expect(!sha.isEmpty)
        let shown = try await client.runWorkspaceOperation(
            method: "git.show",
            params: ["threadId": .string(thread), "sha": .string(sha)]
        )
        #expect(shown["commit"]?["subject"]?.stringValue == "second")
        #expect((shown["files"]?.arrayValue ?? []).count == 2)
        #expect(shown["diff"]?.stringValue?.contains("+two") == true)
        #expect(shown["diff"]?.stringValue?.contains("b.txt") == true)
        do {
            _ = try await client.runWorkspaceOperation(
                method: "git.show",
                params: ["threadId": .string(thread), "sha": .string(String(repeating: "0", count: 40))]
            )
            Issue.record("Expected git.show of an unknown SHA to throw")
        } catch {
            #expect(true)
        }
        await client.close()
    }

    @Test("git.diff.range and git.diff.branch read real comparisons")
    func rangeAndBranchDiffs() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let threadID = try await Self.makeThread(in: repo, client: client)
        let thread = threadID.uuidString.lowercased()
        let value = try await client.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(thread), "limit": .int(10)]
        )
        let commits = value["commits"]?.arrayValue ?? []
        let head = commits[0]["sha"]?.stringValue ?? ""
        let first = commits[1]["sha"]?.stringValue ?? ""
        let range = try await client.runWorkspaceOperation(
            method: "git.diff.range",
            params: ["threadId": .string(thread), "from": .string(first), "to": .string(head)]
        )
        #expect(range["from"]?.stringValue == first)
        #expect(range["to"]?.stringValue == head)
        #expect((range["files"]?.arrayValue ?? []).count == 2)
        #expect(range["diff"]?.stringValue?.contains("+two") == true)
        let branch = try await client.runWorkspaceOperation(
            method: "git.diff.branch",
            params: ["threadId": .string(thread)]
        )
        #expect(branch["patch"]?.stringValue == "")
        await client.close()
    }

    @Test("DiffScope branch and compare cases round-trip through Codable")
    func diffScopeRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let scopes: [DiffScope] = [.uncommitted, .branch, .compare(from: "main", to: "feature/x")]
        for scope in scopes {
            let data = try encoder.encode(scope)
            #expect(try decoder.decode(DiffScope.self, from: data) == scope)
        }
    }
}
