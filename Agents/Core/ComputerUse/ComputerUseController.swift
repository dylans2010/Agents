import AppKit
import Foundation
import Observation

public nonisolated struct ComputerUseStatus: Codable, Sendable {
    public var enabled: Bool
    public var nativeCompiled: Bool
    public var savedEnabled: Bool
    public var accessibility: String
    public var screenCapture: String
    public var desktopOwner: String?
    public var stopped: Bool
    public var grantedThreads: [String]
    public var activeThreads: [String]
    public var error: String?

    public var accessibilityGranted: Bool {
        accessibility.lowercased() == "granted"
    }

    public var screenCaptureGranted: Bool {
        screenCapture.lowercased() == "granted"
    }
}

public struct ComputerUseScreenshot: Codable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var modifiedMs: Int64

    public var id: String { path }

    public var modifiedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(modifiedMs) / 1000)
    }
}

public struct ComputerUseActionRecord: Sendable, Identifiable {
    public var id: UUID
    public var tool: String
    public var threadId: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var result: JSONValue?
    public var error: String?
    public var timedOut: Bool

    public init(
        id: UUID = UUID(),
        tool: String,
        threadId: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        result: JSONValue? = nil,
        error: String? = nil,
        timedOut: Bool = false
    ) {
        self.id = id
        self.tool = tool
        self.threadId = threadId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.result = result
        self.error = error
        self.timedOut = timedOut
    }
}

@Observable
@MainActor
public final class ComputerUseController {
    public private(set) var status: ComputerUseStatus?
    public private(set) var history: [ComputerUseActionRecord] = []
    public private(set) var isBusy: Bool = false
    public var lastError: String?

    @ObservationIgnored public var runtimeProvider: (() -> AgentsRuntimeClient?)?

    public init() {}

    public func refreshStatus() async {
        guard let runtime = runtimeProvider?() else {
            lastError = "Runtime is not connected."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await runtime.computerUseStatus()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        guard let runtime = runtimeProvider?() else {
            lastError = "Runtime is not connected."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await runtime.computerUseSetEnabled(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func requestPermission(kind: String? = nil) async {
        guard let runtime = runtimeProvider?() else {
            lastError = "Runtime is not connected."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await runtime.computerUseRequestPermission(kind: kind)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refreshPermissions() async {
        guard let runtime = runtimeProvider?() else {
            lastError = "Runtime is not connected."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await runtime.computerUseRefresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func runTool(tool: String, threadId: String, arguments: [String: JSONValue]) async {
        guard let runtime = runtimeProvider?() else {
            lastError = "Runtime is not connected."
            return
        }
        let startedAt = Date()
        isBusy = true
        defer { isBusy = false }
        var record = ComputerUseActionRecord(tool: tool, threadId: threadId, startedAt: startedAt)
        do {
            let request = JSONValue.object([
                "action": .string("call"),
                "name": .string(tool),
                "arguments": .object(arguments),
            ])
            let started = try await runtime.computerUseRequest(threadId: threadId, request: request)
            guard let operationId = started["operationId"]?.stringValue else {
                throw AgentsRuntimeError.desktopFailure("Computer Use request did not return an operationId.")
            }
            var finished = false
            for _ in 0..<40 {
                let polled = try await runtime.computerUseResult(threadId: threadId, operationId: operationId)
                if polled["ready"]?.boolValue == true {
                    record.result = polled["result"]
                    record.error = polled["error"]?.stringValue
                    finished = true
                    break
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            if !finished {
                record.timedOut = true
                record.error = "Computer Use operation did not finish in time."
            }
            record.finishedAt = Date()
        } catch {
            record.error = error.localizedDescription
            record.finishedAt = Date()
            lastError = error.localizedDescription
        }
        history.insert(record, at: 0)
        if history.count > 100 {
            history.removeLast(history.count - 100)
        }
    }

    public func listScreenshots(threadId: String) async -> [ComputerUseScreenshot] {
        guard let runtime = runtimeProvider?() else {
            lastError = "Runtime is not connected."
            return []
        }
        do {
            lastError = nil
            return try await runtime.computerUseScreenshots(threadId: threadId)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    public func loadScreenshot(_ screenshot: ComputerUseScreenshot) -> NSImage? {
        NSImage(contentsOf: URL(fileURLWithPath: screenshot.path))
    }

    public static func prettyJSON(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}
