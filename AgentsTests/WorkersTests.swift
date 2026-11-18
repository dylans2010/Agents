import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Workers: Spawn, Status, Result, Cancel & Plans")
struct WorkersTests {

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/workers-\(UUID().uuidString.prefix(8).lowercased())")
        let dataDir = tempRoot.appendingPathComponent("d")
        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        return (client, tempRoot)
    }

    private static func workerArguments(_ workers: [[String: JSONValue]]) -> [String: JSONValue] {
        [
            "parentThreadId": .string(UUID().uuidString),
            "workers": .array(workers.map { .object($0) }),
        ]
    }

    @Test("Worker tools register with their real backend actions")
    func workerToolsRegister() {
        let tools = SystemToolRegistry.tools(for: .system)
        #expect(tools.count == 65)
        #expect(Set(tools.map(\.name)).count == tools.count)
        let expected: [(String, String)] = [
            ("use_workers", "workers.spawn"),
            ("list_workers", "workers.list"),
            ("worker_status", "workers.status"),
            ("worker_result", "workers.result"),
            ("cancel_worker", "workers.cancel"),
            ("intel_plan_task", "workers.plan"),
            ("intel_breakdown_task", "workers.breakdown"),
            ("execution_plan", "workers.execution_plan"),
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
        #expect(SystemToolRegistry.definition(named: "use_workers", for: .system)?.parameters.map(\.name) == ["parentThreadId", "workers"])
        #expect(SystemToolRegistry.definition(named: "intel_breakdown_task", for: .system)?.parameters.map(\.name) == ["planId", "parentThreadId"])
        #expect(SystemToolRegistry.definition(named: "execution_plan", for: .system)?.parameters.map(\.name) == ["parentThreadId", "objective", "mode"])
        for tool in SystemToolRegistry.systemTools {
            #expect(SystemToolRegistry.definition(named: tool.name, for: .provider) == nil)
        }
    }

    @Test("Worker tools refuse missing arguments before any runtime call")
    func workerMissingArgumentRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cases: [(String, [String: JSONValue], String)] = [
            ("use_workers", [:], "parentThreadId"),
            ("use_workers", ["parentThreadId": .string("p")], "workers"),
            ("worker_status", [:], "workerId"),
            ("worker_result", [:], "workerId"),
            ("cancel_worker", [:], "workerId"),
            ("intel_plan_task", ["parentThreadId": .string("p")], "task"),
            ("intel_breakdown_task", [:], "planId"),
            ("execution_plan", ["parentThreadId": .string("p"), "objective": .string("Fix it.")], "mode"),
            ("execution_plan", ["parentThreadId": .string("p")], "objective"),
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

    @Test("Worker list starts empty and unknown workers fail")
    func workerListStartsEmpty() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let listed = try await SystemToolRegistry.execute(
            "list_workers", arguments: [:], toolset: .system, runtime: client
        )
        #expect(listed.arrayValue?.isEmpty == true)
        for tool in ["worker_status", "worker_result", "cancel_worker"] {
            do {
                _ = try await SystemToolRegistry.execute(
                    tool, arguments: ["workerId": .string("no-such-worker")],
                    toolset: .system, runtime: client
                )
                Issue.record("Expected failure for unknown worker in \(tool)")
            } catch {
            }
        }
        await client.close()
    }

    @Test("Spawning on a missing parent fails and records nothing")
    func spawnOnMissingParentFails() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            _ = try await SystemToolRegistry.execute(
                "use_workers",
                arguments: Self.workerArguments([["name": .string("alpha"), "task": .string("Do the thing."), "targetFiles": .array([])]]),
                toolset: .system, runtime: client
            )
            Issue.record("Expected spawn failure for missing parent")
        } catch {
        }
        let listed = try await SystemToolRegistry.execute(
            "list_workers", arguments: [:], toolset: .system, runtime: client
        )
        #expect(listed.arrayValue?.isEmpty == true)
        await client.close()
    }

    @Test("Spawning a task over 500 characters fails before any provider launch")
    func spawnLongTaskFails() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let parent = try await client.newThread()
        do {
            _ = try await SystemToolRegistry.execute(
                "use_workers",
                arguments: [
                    "parentThreadId": .string(parent.uuidString),
                    "workers": .array([.object([
                        "name": .string("alpha"),
                        "task": .string(String(repeating: "x", count: 501)),
                        "targetFiles": .array([]),
                    ])]),
                ],
                toolset: .system, runtime: client
            )
            Issue.record("Expected spawn failure for a 501-character task")
        } catch {
        }
        let listed = try await client.listWorkers(parentThreadId: parent.uuidString)
        #expect(listed.isEmpty)
        await client.close()
    }

    @Test("Plan round trip: draft, expand, and the plan survives a reopen")
    func planRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let parent = try await client.newThread()
        let parentId = parent.uuidString
        let planned = try await SystemToolRegistry.execute(
            "intel_plan_task",
            arguments: ["parentThreadId": .string(parentId), "task": .string("Fix the leak. Add a regression test. Update the docs.")],
            toolset: .system, runtime: client
        )
        guard let planId = planned["planId"]?.stringValue else {
            Issue.record("Expected a planId, got \(planned)")
            await client.close()
            return
        }
        #expect(planned["steps"]?.arrayValue?.count == 3)
        #expect(planned["steps"]?.arrayValue?.first?["name"]?.stringValue == "Step 1")
        #expect(planned["steps"]?.arrayValue?.first?["task"]?.stringValue == "Fix the leak.")
        let expanded = try await SystemToolRegistry.execute(
            "intel_breakdown_task",
            arguments: ["planId": .string(planId), "parentThreadId": .string(parentId)],
            toolset: .system, runtime: client
        )
        #expect(expanded["planId"]?.stringValue == planId)
        #expect(expanded["steps"]?.arrayValue?.count == 3)
        let dataDir = tempRoot.appendingPathComponent("d")
        await client.close()
        let reopened = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        let again = try await SystemToolRegistry.execute(
            "intel_breakdown_task",
            arguments: ["planId": .string(planId)],
            toolset: .system, runtime: reopened
        )
        #expect(again["planId"]?.stringValue == planId)
        await reopened.close()
    }

    @Test("Execution plan needs a parent working directory")
    func executionPlanNeedsWorkingDirectory() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let parent = try await client.newThread()
        do {
            _ = try await SystemToolRegistry.execute(
                "execution_plan",
                arguments: [
                    "parentThreadId": .string(parent.uuidString),
                    "objective": .string("Fix the leak."),
                    "mode": .string("build"),
                ],
                toolset: .system, runtime: client
            )
            Issue.record("Expected execution_plan failure without a working directory")
        } catch {
        }
        await client.close()
    }

    @Test("Session thread wins over a model-supplied parent thread")
    func sessionThreadWinsOverModelParent() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let session = try await client.newThread()
        let other = try await client.newThread()
        let missing = UUID().uuidString
        do {
            _ = try await SystemToolRegistry.execute(
                "intel_plan_task",
                arguments: ["parentThreadId": .string(missing), "task": .string("Fix the leak. Add a regression test.")],
                toolset: .system, runtime: client
            )
            Issue.record("Expected intel_plan_task failure for a missing parent thread")
        } catch {
        }
        let pinned = try await SystemToolRegistry.execute(
            "intel_plan_task",
            arguments: ["parentThreadId": .string(missing), "task": .string("Fix the leak. Add a regression test.")],
            toolset: .system, runtime: client, sessionThreadId: session.uuidString
        )
        guard let planId = pinned["planId"]?.stringValue else {
            Issue.record("Expected a planId, got \(pinned)")
            await client.close()
            return
        }
        let owned = try await client.breakdownTask(planId: planId, parentThreadId: session.uuidString)
        #expect(owned.parentThreadId == session.uuidString)
        do {
            _ = try await client.breakdownTask(planId: planId, parentThreadId: other.uuidString)
            Issue.record("Expected breakdown failure for a plan owned by another thread")
        } catch {
        }
        await client.close()
    }

    @Test("Session thread wins for breakdown and same-thread use is unchanged")
    func sessionThreadWinsForBreakdown() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let session = try await client.newThread()
        let other = try await client.newThread()
        let plan = try await client.planTask(parentThreadId: session.uuidString, task: "Fix the leak. Add a regression test. Update the docs.")
        do {
            _ = try await SystemToolRegistry.execute(
                "intel_breakdown_task",
                arguments: ["planId": .string(plan.planId), "parentThreadId": .string(other.uuidString)],
                toolset: .system, runtime: client
            )
            Issue.record("Expected breakdown failure for a plan owned by another thread")
        } catch {
        }
        _ = try await SystemToolRegistry.execute(
            "intel_breakdown_task",
            arguments: ["planId": .string(plan.planId), "parentThreadId": .string(other.uuidString)],
            toolset: .system, runtime: client, sessionThreadId: session.uuidString
        )
        _ = try await SystemToolRegistry.execute(
            "intel_breakdown_task",
            arguments: ["planId": .string(plan.planId), "parentThreadId": .string(session.uuidString)],
            toolset: .system, runtime: client
        )
        await client.close()
    }

    @Test("Session thread wins through the use_mcp recursion")
    func sessionThreadWinsThroughUseMcp() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let session = try await client.newThread()
        let other = try await client.newThread()
        let plan = try await client.planTask(parentThreadId: session.uuidString, task: "Fix the leak. Add a regression test. Update the docs.")
        _ = try await SystemToolRegistry.execute(
            "use_mcp",
            arguments: [
                "serverName": .string("coincide"),
                "toolName": .string("intel_breakdown_task"),
                "arguments": .string("{\"planId\": \"\(plan.planId)\", \"parentThreadId\": \"\(other.uuidString)\"}"),
            ],
            toolset: .system, runtime: client, sessionThreadId: session.uuidString
        )
        await client.close()
    }

    @Test("Session thread wins over a model-supplied threadId")
    func sessionThreadWinsOverModelThreadId() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let session = try await client.newThread()
        let missing = UUID().uuidString
        do {
            _ = try await SystemToolRegistry.execute(
                "plan-AskUser",
                arguments: ["threadId": .string(missing)],
                toolset: .system, runtime: client
            )
            Issue.record("Expected plan-AskUser failure for a missing thread")
        } catch {
        }
        let pinned = try await SystemToolRegistry.execute(
            "plan-AskUser",
            arguments: ["threadId": .string(missing)],
            toolset: .system, runtime: client, sessionThreadId: session.uuidString
        )
        #expect(pinned["threadId"]?.stringValue == session.uuidString)
        let same = try await SystemToolRegistry.execute(
            "plan-AskUser",
            arguments: ["threadId": .string(session.uuidString)],
            toolset: .system, runtime: client
        )
        #expect(same["threadId"]?.stringValue == session.uuidString)
        await client.close()
    }

    @Test("Bulk selection separates running workers from finished ones")
    func bulkSelectionSeparatesRunningFromTerminal() {
        let records = [
            Self.makeRecord(id: "w-running", status: "running"),
            Self.makeRecord(id: "w-done", status: "completed"),
            Self.makeRecord(id: "w-failed", status: "failed"),
            Self.makeRecord(id: "w-cancelled", status: "cancelled"),
            Self.makeRecord(id: "w-unknown", status: "unknown"),
        ]
        let running = WorkerRecord.runningWorkers(from: records)
        #expect(running.count == 1)
        #expect(running.map(\.id) == ["w-running"])
        let terminal = WorkerRecord.terminalWorkers(from: records)
        #expect(terminal.count == 3)
        #expect(terminal.map(\.id) == ["w-done", "w-failed", "w-cancelled"])
        #expect(!terminal.contains(where: \.isRunning))
        #expect(!running.contains(where: \.isTerminal))
        #expect(Set(running.map(\.id)).isDisjoint(with: Set(terminal.map(\.id))))
    }

    @Test("Clear finished never selects a running worker")
    func clearFinishedNeverSelectsRunning() {
        let records = [
            Self.makeRecord(id: "w1", status: "running"),
            Self.makeRecord(id: "w2", status: "running"),
            Self.makeRecord(id: "w3", status: "completed"),
        ]
        let terminal = WorkerRecord.terminalWorkers(from: records)
        #expect(terminal.map(\.id) == ["w3"])
        #expect(WorkerRecord.terminalWorkers(from: []).isEmpty)
        #expect(WorkerRecord.runningWorkers(from: []).isEmpty)
    }

    @Test("Bulk failure message names every failed worker and stays silent on success")
    func bulkFailureMessage() {
        #expect(WorkerRecord.bulkFailureMessage(action: "cancel", attempted: 3, failures: []) == nil)
        let single = WorkerRecord.bulkFailureMessage(action: "cancel", attempted: 2, failures: ["alpha: boom"])
        #expect(single == "Failed to cancel 1 of 2 workers: alpha: boom")
        let multiple = WorkerRecord.bulkFailureMessage(action: "delete", attempted: 3, failures: ["alpha: boom", "beta: gone"])
        #expect(multiple == "Failed to delete 2 of 3 workers: alpha: boom; beta: gone")
    }

    private static func makeRecord(id: String, status: String) -> WorkerRecord {
        WorkerRecord(
            id: id, name: id, parentThreadId: "p1", threadId: "t1",
            task: "Do the thing.", provider: "codex", targetFiles: [],
            status: status, cancelRequested: false, transcriptStart: 0,
            transcriptItems: 0, elapsedSeconds: 0, createdAt: 100, startedAt: 100,
            completedAt: nil, error: nil, result: nil, progress: nil
        )
    }

    @Test("Worker record and plan survive a Codable round trip")
    func workerRecordRoundTrips() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let record = WorkerRecord(
            id: "w1", name: "alpha", parentThreadId: "p1", threadId: "t1",
            task: "Do the thing.", provider: "codex", targetFiles: ["a.swift"],
            status: "running", cancelRequested: false, transcriptStart: 0,
            transcriptItems: 3, elapsedSeconds: 12.5, createdAt: 100, startedAt: 100,
            completedAt: nil, error: nil, result: nil,
            progress: WorkerProgress(stage: "running", transcriptItems: 3, elapsedSeconds: 12.5)
        )
        let data = try encoder.encode(record)
        let decoded = try decoder.decode(WorkerRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.isRunning)
        #expect(!decoded.isTerminal)
        let json = "{\"planId\":\"pl\",\"parentThreadId\":\"p1\",\"task\":\"Fix it.\",\"steps\":[{\"name\":\"Step 1\",\"task\":\"Fix it.\",\"targetFiles\":[]}],\"createdAt\":100}"
        let plan = try decoder.decode(WorkerPlan.self, from: Data(json.utf8))
        #expect(plan.planId == "pl")
        #expect(plan.steps.count == 1)
        #expect(plan.objective == nil)
    }
}
