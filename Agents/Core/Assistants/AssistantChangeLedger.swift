import CoincideRemoteKit
import Foundation

public enum AssistantChangeLedgerError: Error, Sendable {
    case snapshotFailed(String)
    case runAlreadyActive(String)
}

public struct AssistantStatusEntry: Codable, Hashable, Sendable {
    public var status: String
    public var path: String
    public var originalPath: String?

    public init(status: String, path: String, originalPath: String? = nil) {
        self.status = status
        self.path = path
        self.originalPath = originalPath
    }
}

public struct AssistantRunSnapshot: Codable, Hashable, Sendable {
    public var headSHA: String?
    public var branch: String?
    public var entries: [AssistantStatusEntry]
    public var statusHash: String
    public var canonicalRoot: String?
    public var rootResolutionError: String?
    public var takenAt: Date

    public init(
        headSHA: String?,
        branch: String?,
        entries: [AssistantStatusEntry],
        statusHash: String,
        canonicalRoot: String?,
        rootResolutionError: String?,
        takenAt: Date
    ) {
        self.headSHA = headSHA
        self.branch = branch
        self.entries = entries
        self.statusHash = statusHash
        self.canonicalRoot = canonicalRoot
        self.rootResolutionError = rootResolutionError
        self.takenAt = takenAt
    }

    public var isClean: Bool { entries.isEmpty }

    public var paths: Set<String> {
        Set(entries.map(\.path))
    }
}

public struct AssistantRunChangeSet: Codable, Hashable, Sendable {
    public var files: [RemoteDiff.File]
    public var preExistingPaths: [String]
    public var committedDuringRun: Bool
    public var committedPaths: [String]
    public var isTruncated: Bool

    public init(
        files: [RemoteDiff.File],
        preExistingPaths: [String] = [],
        committedDuringRun: Bool = false,
        committedPaths: [String] = [],
        isTruncated: Bool = false
    ) {
        self.files = files
        self.preExistingPaths = preExistingPaths
        self.committedDuringRun = committedDuringRun
        self.committedPaths = committedPaths
        self.isTruncated = isTruncated
    }
}

public enum AssistantRunDiffKind: String, Codable, Hashable, Sendable {
    case empty
    case changed
    case unavailable
    case readOnly
}

public struct AssistantRunDiffOutcome: Codable, Hashable, Sendable {
    public var kind: AssistantRunDiffKind
    public var changeSet: AssistantRunChangeSet?
    public var unavailableReason: String?

    public init(kind: AssistantRunDiffKind, changeSet: AssistantRunChangeSet? = nil, unavailableReason: String? = nil) {
        self.kind = kind
        self.changeSet = changeSet
        self.unavailableReason = unavailableReason
    }

    public static var empty: AssistantRunDiffOutcome {
        AssistantRunDiffOutcome(kind: .empty, changeSet: AssistantRunChangeSet(files: []))
    }

    public static func changed(_ changeSet: AssistantRunChangeSet) -> AssistantRunDiffOutcome {
        AssistantRunDiffOutcome(kind: .changed, changeSet: changeSet)
    }

    public static func unavailable(reason: String) -> AssistantRunDiffOutcome {
        AssistantRunDiffOutcome(kind: .unavailable, unavailableReason: reason)
    }

    public static var readOnly: AssistantRunDiffOutcome {
        AssistantRunDiffOutcome(kind: .readOnly)
    }
}

public struct AssistantRunLedgerEntry: Codable, Hashable, Sendable {
    public var runId: String
    public var assistantId: String
    public var permissionProfile: RemoteAssistant.PermissionProfile
    public var snapshot: AssistantRunSnapshot?
    public var outcome: AssistantRunDiffOutcome?
    public var beganAt: Date
    public var finishedAt: Date?

    public init(
        runId: String,
        assistantId: String,
        permissionProfile: RemoteAssistant.PermissionProfile,
        snapshot: AssistantRunSnapshot? = nil,
        outcome: AssistantRunDiffOutcome? = nil,
        beganAt: Date,
        finishedAt: Date? = nil
    ) {
        self.runId = runId
        self.assistantId = assistantId
        self.permissionProfile = permissionProfile
        self.snapshot = snapshot
        self.outcome = outcome
        self.beganAt = beganAt
        self.finishedAt = finishedAt
    }

    public var isReadOnly: Bool { permissionProfile == .readOnly }

    public var isFinished: Bool { finishedAt != nil }
}

public actor AssistantChangeLedger {
    private let runtime: AgentsRuntimeClient
    private var entries: [String: AssistantRunLedgerEntry] = [:]

    public init(runtime: AgentsRuntimeClient) {
        self.runtime = runtime
    }

    public func beginRun(
        runId: String,
        assistantId: String,
        permissionProfile: RemoteAssistant.PermissionProfile
    ) async throws -> AssistantRunSnapshot? {
        if let existing = entries[runId], !existing.isFinished {
            throw AssistantChangeLedgerError.runAlreadyActive(runId)
        }
        let beganAt = Date()
        if permissionProfile == .readOnly {
            entries[runId] = AssistantRunLedgerEntry(
                runId: runId,
                assistantId: assistantId,
                permissionProfile: permissionProfile,
                beganAt: beganAt
            )
            return nil
        }
        let snapshot = try await takeSnapshot(threadId: runId)
        entries[runId] = AssistantRunLedgerEntry(
            runId: runId,
            assistantId: assistantId,
            permissionProfile: permissionProfile,
            snapshot: snapshot,
            beganAt: beganAt
        )
        return snapshot
    }

    public func finishRun(runId: String) async -> AssistantRunLedgerEntry? {
        guard var entry = entries[runId] else { return nil }
        entry.finishedAt = Date()
        if entry.isReadOnly {
            entry.outcome = .readOnly
        } else if let snapshot = entry.snapshot {
            entry.outcome = await computeDiff(threadId: runId, snapshot: snapshot)
        } else {
            entry.outcome = .unavailable(reason: "No pre-run snapshot was recorded for this run.")
        }
        entries[runId] = entry
        return entry
    }

    public func reviewChanges(runId: String) -> AssistantRunDiffOutcome? {
        entries[runId]?.outcome
    }

    public func hasModifications(runId: String) -> Bool {
        guard let outcome = entries[runId]?.outcome, outcome.kind == .changed else { return false }
        return !(outcome.changeSet?.files.isEmpty ?? true)
    }

    public func entry(runId: String) -> AssistantRunLedgerEntry? {
        entries[runId]
    }

    public func snapshot(runId: String) -> AssistantRunSnapshot? {
        entries[runId]?.snapshot
    }

    public func discard(runId: String) {
        entries.removeValue(forKey: runId)
    }

    public static func statusHash(entries: [AssistantStatusEntry]) -> String {
        let lines = entries
            .map { entry in
                var line = "\(entry.status) \(entry.path)"
                if let original = entry.originalPath {
                    line += " -> \(original)"
                }
                return line
            }
            .sorted()
        var hash: UInt64 = 0xcbf29ce484222325
        for line in lines {
            for byte in line.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
            hash ^= 0x0a
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    public static func parseStatusEntries(_ value: JSONValue) -> [AssistantStatusEntry] {
        (value["entries"]?.arrayValue ?? []).compactMap { item in
            guard let status = item["status"]?.stringValue,
                  let path = item["path"]?.stringValue,
                  !status.isEmpty, !path.isEmpty
            else { return nil }
            return AssistantStatusEntry(
                status: status,
                path: path,
                originalPath: item["originalPath"]?.stringValue
            )
        }
    }

    public static func parseHeadSHA(_ value: JSONValue) -> String? {
        value["commits"]?.arrayValue?.first?["sha"]?.stringValue
    }

    public static func numstat(fromRangeFiles value: JSONValue?) -> JSONValue {
        .array(
            value?.arrayValue?.compactMap { item in
                guard let path = item["path"]?.stringValue, !path.isEmpty else { return nil }
                var fields: [String: JSONValue] = [
                    "path": .string(path),
                    "additions": .int(item["additions"]?.intValue ?? 0),
                    "deletions": .int(item["deletions"]?.intValue ?? 0),
                ]
                if let oldPath = item["oldPath"]?.stringValue, !oldPath.isEmpty {
                    fields["oldPath"] = .string(oldPath)
                }
                return .object(fields)
            } ?? []
        )
    }

    public static func buildDiff(
        patch: String,
        numstat: JSONValue,
        untracked: [String],
        title: String
    ) -> RemoteDiff {
        let split = RemoteDiffParsing.split(patch, title: title)
        var files = split.files
        var indexByPath: [String: Int] = [:]
        for (index, file) in files.enumerated() {
            indexByPath[file.path] = index
        }
        for stat in numstat.arrayValue ?? [] {
            guard let path = stat["path"]?.stringValue, !path.isEmpty else { continue }
            let additions = stat["additions"]?.intValue ?? 0
            let deletions = stat["deletions"]?.intValue ?? 0
            if let index = indexByPath[path] {
                files[index].additions = additions
                files[index].deletions = deletions
                if let oldPath = stat["oldPath"]?.stringValue, !oldPath.isEmpty {
                    files[index].oldPath = oldPath
                }
            } else {
                files.append(
                    RemoteDiff.File(
                        path: path,
                        oldPath: stat["oldPath"]?.stringValue,
                        status: "modified",
                        additions: additions,
                        deletions: deletions
                    )
                )
                indexByPath[path] = files.count - 1
            }
        }
        for path in untracked where indexByPath[path] == nil {
            files.append(RemoteDiff.File(path: path, status: "untracked"))
            indexByPath[path] = files.count - 1
        }
        return RemoteDiff(title: title, files: files, isTruncated: split.isTruncated)
    }

    private func takeSnapshot(threadId: String) async throws -> AssistantRunSnapshot {
        let logValue: JSONValue
        do {
            logValue = try await runtime.runWorkspaceOperation(
                method: "git.log",
                params: ["threadId": .string(threadId), "limit": .int(1)]
            )
        } catch {
            throw AssistantChangeLedgerError.snapshotFailed("Could not read HEAD: \(error.localizedDescription)")
        }
        do {
            try requireNoError(logValue, operation: "git.log")
        } catch {
            throw AssistantChangeLedgerError.snapshotFailed(error.localizedDescription)
        }
        let statusValue: JSONValue
        do {
            statusValue = try await runtime.runWorkspaceOperation(
                method: "git.status",
                params: ["threadId": .string(threadId)]
            )
        } catch {
            throw AssistantChangeLedgerError.snapshotFailed("Could not read worktree status: \(error.localizedDescription)")
        }
        do {
            try requireNoError(statusValue, operation: "git.status")
        } catch {
            throw AssistantChangeLedgerError.snapshotFailed(error.localizedDescription)
        }
        let entries = Self.parseStatusEntries(statusValue)
        let root = await resolveCanonicalRoot(threadId: threadId)
        return AssistantRunSnapshot(
            headSHA: Self.parseHeadSHA(logValue),
            branch: statusValue["branch"]?.stringValue,
            entries: entries,
            statusHash: Self.statusHash(entries: entries),
            canonicalRoot: root.value,
            rootResolutionError: root.error,
            takenAt: Date()
        )
    }

    private func computeDiff(threadId: String, snapshot: AssistantRunSnapshot) async -> AssistantRunDiffOutcome {
        do {
            return try await computeDiffThrowing(threadId: threadId, snapshot: snapshot)
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    private func computeDiffThrowing(threadId: String, snapshot: AssistantRunSnapshot) async throws -> AssistantRunDiffOutcome {
        let postLog = try await runtime.runWorkspaceOperation(
            method: "git.log",
            params: ["threadId": .string(threadId), "limit": .int(1)]
        )
        try requireNoError(postLog, operation: "git.log")
        let postHead = Self.parseHeadSHA(postLog)
        var merged: [String: RemoteDiff.File] = [:]
        var committedPaths: [String] = []
        var truncated = false
        if let preHead = snapshot.headSHA, let post = postHead, preHead != post {
            let range = try await runtime.runWorkspaceOperation(
                method: "git.diff.range",
                params: ["threadId": .string(threadId), "from": .string(preHead), "to": .string(post)]
            )
            try requireNoError(range, operation: "git.diff.range")
            let rangePatch = range["diff"]?.stringValue ?? ""
            let rangeDiff = Self.buildDiff(
                patch: rangePatch,
                numstat: Self.numstat(fromRangeFiles: range["files"]),
                untracked: [],
                title: "Assistant changes"
            )
            truncated = truncated || (range["truncated"]?.boolValue ?? false)
            for file in rangeDiff.files {
                merged[file.path] = file
                committedPaths.append(file.path)
            }
            for item in range["files"]?.arrayValue ?? [] {
                guard let path = item["path"]?.stringValue, !path.isEmpty else { continue }
                let status = item["status"]?.stringValue ?? "modified"
                let oldPath = item["oldPath"]?.stringValue
                if var existing = merged[path] {
                    existing.status = status
                    if let oldPath = oldPath, !oldPath.isEmpty {
                        existing.oldPath = oldPath
                    }
                    merged[path] = existing
                } else {
                    merged[path] = RemoteDiff.File(
                        path: path,
                        oldPath: oldPath,
                        status: status,
                        additions: item["additions"]?.intValue ?? 0,
                        deletions: item["deletions"]?.intValue ?? 0
                    )
                }
                if !committedPaths.contains(path) {
                    committedPaths.append(path)
                }
            }
        }
        let root: String
        if let cached = snapshot.canonicalRoot {
            root = cached
        } else if let resolved = await resolveCanonicalRoot(threadId: threadId).value {
            root = resolved
        } else {
            return .unavailable(
                reason: snapshot.rootResolutionError ?? "Could not resolve the thread working directory for the post-run diff."
            )
        }
        let review = try await runWorkspaceApiOperation(
            method: "git.review.diff",
            params: [
                "threadId": .string(threadId),
                "expectedRoot": .string(root),
                "scope": .string("uncommitted"),
                "ignoreWhitespace": .bool(false),
            ],
            timeoutSeconds: 120
        )
        if review["notRepository"]?.boolValue == true {
            return .unavailable(reason: "The thread folder is not a Git repository.")
        }
        let reviewPatch = review["patch"]?.stringValue ?? ""
        let reviewDiff = Self.buildDiff(
            patch: reviewPatch,
            numstat: review["numstat"] ?? .array([]),
            untracked: review["untracked"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            title: "Assistant changes"
        )
        truncated = truncated || reviewDiff.isTruncated || (review["truncated"]?.boolValue ?? false)
        for file in reviewDiff.files {
            merged[file.path] = file
        }
        let files = merged.values.sorted { $0.path < $1.path }
        if files.isEmpty {
            if truncated {
                return .unavailable(reason: "The change listing was truncated, so an empty result cannot be trusted.")
            }
            if snapshot.entries.contains(where: { $0.status == "??" }) {
                return .unavailable(reason: "Untracked files were present before the run and the post-run diff came back empty, so an empty result cannot be trusted.")
            }
            return .empty
        }
        let preExisting = files
            .filter { snapshot.paths.contains($0.path) }
            .map(\.path)
            .sorted()
        return .changed(
            AssistantRunChangeSet(
                files: files,
                preExistingPaths: preExisting,
                committedDuringRun: !committedPaths.isEmpty,
                committedPaths: committedPaths.sorted(),
                isTruncated: truncated
            )
        )
    }

    private func resolveCanonicalRoot(threadId: String) async -> (value: String?, error: String?) {
        do {
            let threadDoc = try await runtime.engineRPC(
                method: "threads.read",
                params: ["threadId": .string(threadId), "itemLimit": .int(0)]
            )
            guard let worktree = threadDoc["worktreePath"]?.stringValue, !worktree.isEmpty else {
                return (nil, "The thread has no worktree path.")
            }
            let expanded = ExternalEditorService.expandedPath(worktree)
            return (URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path, nil)
        } catch {
            return (nil, "Could not read the thread worktree path: \(error.localizedDescription)")
        }
    }

    private func runWorkspaceApiOperation(
        method: String,
        params: [String: JSONValue],
        timeoutSeconds: Int = 30
    ) async throws -> JSONValue {
        guard let threadID = params["threadId"]?.stringValue else {
            throw AgentsRuntimeError.desktopFailure("Workspace API operation requires a threadId.")
        }
        let started = try await runtime.engineRPC(method: method, params: params)
        guard let operationId = started["operationId"]?.stringValue else {
            return started
        }
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let polled = try await runtime.engineRPC(
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

    private func requireNoError(_ value: JSONValue, operation: String) throws {
        if let errorText = value["error"]?.stringValue, !errorText.isEmpty {
            throw AgentsRuntimeError.desktopFailure("\(operation) failed: \(errorText)")
        }
    }
}
