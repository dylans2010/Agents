import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Agent Memory Store, Tools & Clear Gate")
struct MemoryTests {

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/memory-\(UUID().uuidString.prefix(8).lowercased())")
        let dataDir = tempRoot.appendingPathComponent("d")
        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        return (client, tempRoot)
    }

    @Test("Memory tools register with their real backend actions")
    func memoryToolsRegister() {
        let tools = SystemToolRegistry.tools(for: .system)
        #expect(tools.count == 41)
        #expect(Set(tools.map(\.name)).count == tools.count)
        let expected: [(String, String)] = [
            ("mem_store", "memory.store"),
            ("mem_retrieve", "memory.retrieve"),
            ("view_memory", "memory.list"),
            ("mem_delete", "memory.delete"),
            ("mem_clear", "memory.clear"),
            ("mem_context_snapshot", "memory.snapshot"),
            ("context_persistence_store", "memory.context_store"),
        ]
        for (name, action) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == .desktop)
            #expect(definition.parameters.contains { $0.required })
        }
        #expect(SystemToolRegistry.definition(named: "mem_clear", for: .system)?.parameters.map(\.name) == ["scope", "confirm"])
        #expect(SystemToolRegistry.definition(named: "view_memory", for: .system)?.parameters.map(\.name).contains("query") == true)
        #expect(SystemToolRegistry.definition(named: "context_persistence_store", for: .system)?.parameters.map(\.name).contains("action") == true)
        for tool in SystemToolRegistry.systemTools {
            #expect(SystemToolRegistry.definition(named: tool.name, for: .provider) == nil)
        }
    }

    @Test("Memory tools refuse missing arguments before any runtime call")
    func memoryMissingArgumentRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cases: [(String, [String: JSONValue], String)] = [
            ("mem_store", ["key": .string("k")], "value"),
            ("mem_retrieve", [:], "key"),
            ("mem_delete", [:], "key"),
            ("mem_clear", [:], "scope"),
            ("mem_clear", ["scope": .string("global")], "confirm"),
            ("context_persistence_store", ["key": .string("k")], "action"),
        ]
        for (tool, arguments, missing) in cases {
            do {
                _ = try await SystemToolRegistry.execute(tool, arguments: arguments, toolset: .system, runtime: client)
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: missing))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        await client.close()
    }

    @Test("mem_clear with confirm=false is refused and deletes nothing")
    func clearGateRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        _ = try await SystemToolRegistry.execute(
            "mem_store", arguments: ["key": .string("keep"), "value": .string("me"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        do {
            _ = try await SystemToolRegistry.execute(
                "mem_clear", arguments: ["scope": .string("global"), "confirm": .bool(false)],
                toolset: .system, runtime: client
            )
            Issue.record("Expected mem_clear refusal")
        } catch let error as SystemToolError {
            guard case .executionFailed(let tool, _) = error else {
                Issue.record("Expected executionFailed, got \(error)")
                await client.close()
                return
            }
            #expect(tool == "mem_clear")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        let kept = try await SystemToolRegistry.execute(
            "mem_retrieve", arguments: ["key": .string("keep"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(kept["value"]?.stringValue == "me")
        await client.close()
    }

    @Test("Memory round trip: store, retrieve, list, snapshot, delete, scoped clear")
    func memoryRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let workspaceScope = "workspace:/tmp/demo-project"
        let stored = try await SystemToolRegistry.execute(
            "mem_store", arguments: ["key": .string("editor"), "value": .string("uses tabs"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(stored["overwritten"]?.boolValue == false)
        let overwritten = try await SystemToolRegistry.execute(
            "mem_store", arguments: ["key": .string("editor"), "value": .string("uses spaces"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(overwritten["overwritten"]?.boolValue == true)
        _ = try await SystemToolRegistry.execute(
            "mem_store", arguments: ["key": .string("editor"), "value": .string("workspace tabs"), "scope": .string(workspaceScope)],
            toolset: .system, runtime: client
        )
        let global = try await SystemToolRegistry.execute(
            "mem_retrieve", arguments: ["key": .string("editor"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(global["value"]?.stringValue == "uses spaces")
        let scoped = try await SystemToolRegistry.execute(
            "mem_retrieve", arguments: ["key": .string("editor"), "scope": .string(workspaceScope)],
            toolset: .system, runtime: client
        )
        #expect(scoped["value"]?.stringValue == "workspace tabs")
        do {
            _ = try await SystemToolRegistry.execute(
                "mem_retrieve", arguments: ["key": .string("missing"), "scope": .string("global")],
                toolset: .system, runtime: client
            )
            Issue.record("Expected missing-key failure")
        } catch {
        }
        let listed = try await SystemToolRegistry.execute(
            "view_memory", arguments: ["query": .string("spaces")],
            toolset: .system, runtime: client
        )
        #expect(listed.arrayValue?.count == 1)
        #expect(listed.arrayValue?.first?["scope"]?.stringValue == "global")
        let snapshot = try await SystemToolRegistry.execute(
            "mem_context_snapshot", arguments: ["scope": .string("global"), "query": .string("spaces")],
            toolset: .system, runtime: client
        )
        guard let snapshotKey = snapshot["key"]?.stringValue, snapshotKey.hasPrefix("snapshot:") else {
            Issue.record("Expected a snapshot:<uuid> key, got \(snapshot)")
            await client.close()
            return
        }
        #expect(snapshot["totalMatched"]?.intValue == 1)
        let snapshotEntry = try await SystemToolRegistry.execute(
            "mem_retrieve", arguments: ["key": .string(snapshotKey), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(snapshotEntry["value"]?.stringValue?.contains("snapshotId") == true)
        let deleted = try await SystemToolRegistry.execute(
            "mem_delete", arguments: ["key": .string("editor"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(deleted["deleted"]?.boolValue == true)
        let cleared = try await SystemToolRegistry.execute(
            "mem_clear", arguments: ["scope": .string(workspaceScope), "confirm": .bool(true)],
            toolset: .system, runtime: client
        )
        #expect(cleared["deleted"]?.intValue == 1)
        let survivors = try await SystemToolRegistry.execute(
            "view_memory", arguments: ["scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(survivors.arrayValue?.count == 1)
        #expect(survivors.arrayValue?.first?["key"]?.stringValue == snapshotKey)
        let dataDir = tempRoot.appendingPathComponent("d")
        await client.close()
        let reopened = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        let durable = try await SystemToolRegistry.execute(
            "mem_retrieve", arguments: ["key": .string(snapshotKey), "scope": .string("global")],
            toolset: .system, runtime: reopened
        )
        #expect(durable["value"]?.stringValue?.contains("snapshotId") == true)
        await reopened.close()
    }

    @Test("context_persistence_store get-missing succeeds with an empty value")
    func contextStoreSemantics() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let missing = try await SystemToolRegistry.execute(
            "context_persistence_store", arguments: ["key": .string("ghost"), "action": .string("get")],
            toolset: .system, runtime: client
        )
        #expect(missing["value"]?.stringValue == "")
        #expect(missing["found"]?.boolValue == false)
        _ = try await SystemToolRegistry.execute(
            "context_persistence_store", arguments: ["key": .string("ghost"), "action": .string("set"), "value": .string("boo")],
            toolset: .system, runtime: client
        )
        let found = try await SystemToolRegistry.execute(
            "context_persistence_store", arguments: ["key": .string("ghost"), "action": .string("get")],
            toolset: .system, runtime: client
        )
        #expect(found["value"]?.stringValue == "boo")
        #expect(found["found"]?.boolValue == true)
        let deleted = try await SystemToolRegistry.execute(
            "context_persistence_store", arguments: ["key": .string("ghost"), "action": .string("delete")],
            toolset: .system, runtime: client
        )
        #expect(deleted["deleted"]?.boolValue == true)
        let deletedAgain = try await SystemToolRegistry.execute(
            "context_persistence_store", arguments: ["key": .string("ghost"), "action": .string("delete")],
            toolset: .system, runtime: client
        )
        #expect(deletedAgain["deleted"]?.boolValue == false)
        await client.close()
    }
}
