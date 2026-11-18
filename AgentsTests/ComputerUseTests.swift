import Foundation
import Testing
@testable import Agents

@Suite("Computer Use Status, Requests & Screenshots")
struct ComputerUseTests {

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/computer-use-\(UUID().uuidString.prefix(8).lowercased())")
        let dataDir = tempRoot.appendingPathComponent("d")
        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        return (client, tempRoot)
    }

    @Test("Status reports the switch off and the native executor compiled")
    func statusReportsSwitchOffAndNativeExecutorCompiled() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let status = try await client.computerUseStatus()
        #expect(status.enabled == false)
        #expect(status.nativeCompiled == true)
        #expect(status.savedEnabled == false)
        await client.close()
    }

    @Test("Request is refused while Computer Use is off")
    func requestRefusedWhileOff() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let threadID = try await client.newThread()
        do {
            _ = try await client.computerUseRequest(
                threadId: threadID.uuidString,
                request: .object([
                    "action": .string("call"),
                    "name": .string("list_apps"),
                    "arguments": .object([:]),
                ])
            )
            Issue.record("Expected Computer Use request to be refused while off")
        } catch {
            #expect(true)
        }
        await client.close()
    }

    @Test("Enable switch round-trips through status")
    func enableRoundTrips() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let turnedOn = try await client.computerUseSetEnabled(true)
        #expect(turnedOn.enabled == true)
        let turnedOff = try await client.computerUseSetEnabled(false)
        #expect(turnedOff.enabled == false)
        await client.close()
    }

    @Test("Screenshots list is empty for a fresh thread")
    func screenshotsEmptyForFreshThread() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let threadID = try await client.newThread()
        let screenshots = try await client.computerUseScreenshots(threadId: threadID.uuidString)
        #expect(screenshots.isEmpty)
        await client.close()
    }

    @Test("Screenshots for an unknown thread throw")
    func screenshotsUnknownThreadThrows() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            _ = try await client.computerUseScreenshots(threadId: UUID().uuidString)
            Issue.record("Expected screenshots for an unknown thread to throw")
        } catch {
            #expect(true)
        }
        await client.close()
    }

    @Test("Controller records a refused run while Computer Use is off")
    @MainActor
    func controllerRecordsRefusalWhileOff() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let threadID = try await client.newThread()
        let controller = ComputerUseController()
        controller.runtimeProvider = { client }
        await controller.runTool(tool: "list_apps", threadId: threadID.uuidString, arguments: [:])
        let history = controller.history
        #expect(history.count == 1)
        #expect(history.first?.tool == "list_apps")
        #expect(history.first?.error != nil)
        #expect(history.first?.timedOut == false)
        await client.close()
    }

    @Test("take_screenshot returns live desktop state through execute()")
    func takeScreenshotReturnsDesktopState() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let threadID = try await client.newThread()
        let turnedOn = try await client.computerUseSetEnabled(true)
        #expect(turnedOn.enabled == true)
        let state = try await SystemToolRegistry.execute(
            "take_screenshot",
            arguments: ["threadId": .string(threadID.uuidString), "include_screenshot": .bool(false)],
            toolset: .system, runtime: client
        )
        #expect(state["coordinateSpace"]?.stringValue == "screen_points")
        #expect(state["apps"]?.arrayValue != nil)
        #expect(state["windows"]?.arrayValue != nil)
        #expect(state["screenshot"] == .null)
        _ = try await client.computerUseSetEnabled(false)
        await client.close()
    }
}
