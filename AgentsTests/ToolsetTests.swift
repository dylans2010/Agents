import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("System Toolset Selection, Storage & Registration Isolation")
struct ToolsetTests {

    private static func ephemeralDefaults() -> (UserDefaults, String) {
        let suiteName = "com.apoorvdarshan.coincide.toolset-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private static func makeClient() throws -> (AgentsRuntimeClient, URL) {
        let tempRoot = URL(fileURLWithPath: "/tmp/toolset-\(UUID().uuidString.prefix(8).lowercased())")
        let dataDir = tempRoot.appendingPathComponent("d")
        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        return (client, tempRoot)
    }

    private static func assetsDirectory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Agents/Resources/SystemAssets")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/nonexistent-system-assets")
    }

    private static func summary(toolset: String?) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Test",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default"),
            toolset: toolset
        )
    }

    @Test("Default toolset is System Tools")
    func defaultIsSystemTools() {
        #expect(AgentToolset(storedValue: nil) == .system)
        #expect(AgentToolset(storedValue: "bogus") == .system)
        #expect(AgentToolset(storedValue: "system") == .system)
        #expect(AgentToolset(storedValue: "provider") == .provider)
        let (defaults, suiteName) = Self.ephemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(AgentToolset.load(from: defaults) == .system)
    }

    @Test("Toolset selection persists across loads")
    func selectionPersists() {
        let (defaults, suiteName) = Self.ephemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AgentToolset.save(.provider, to: defaults)
        #expect(AgentToolset.load(from: defaults) == .provider)
        AgentToolset.save(.system, to: defaults)
        #expect(AgentToolset.load(from: defaults) == .system)
        #expect(defaults.string(forKey: AgentToolset.userDefaultsKey) == "system")
    }

    @Test("System Tools registry holds only verified core actions")
    func systemRegistryHoldsVerifiedActions() {
        let tools = SystemToolRegistry.tools(for: .system)
        #expect(tools.count == 333)
        #expect(Set(tools.map(\.name)).count == tools.count)
        let actions = Set(tools.map(\.action))
        #expect(actions == [
            "workspace.read_file", "workspace.write_file", "workspace.files", "workspace.search",
            "workspace.delete_file", "workspace.delete_directory", "workspace.move_file",
            "workspace.copy_file", "workspace.create_dir", "workspace.read_dir",
            "workspace.edit_file", "workspace.search_regex",
            "terminal.create", "terminal.write", "terminal.read", "git.status", "git.diff",
            "git.log", "git.show", "git.diff.range", "git.diff.branch",
            "git.actions.run", "git.actions.pull", "git.branches.list", "git.branches.create",
            "git.branches.checkout",
            "memory.store", "memory.retrieve", "memory.list", "memory.delete",
            "memory.clear", "memory.snapshot", "memory.context_store",
            "workers.spawn", "workers.list", "workers.status", "workers.result",
            "workers.cancel", "workers.delete", "workers.plan", "workers.breakdown", "workers.execution_plan",
            "computer_use.request",
            "system.open_in_finder", "system.reveal_in_finder",
            "mcp.tools", "git.stash", "git.blame", "git.bisect", "git.cherry_pick",
            "git.rollback", "git.checkpoints.create", "git.checkpoints.list",
            "git.checkpoints.restore", "git.review.diff",
            "system.lookup", "system.skills", "system.info", "system.env",
            "system.clipboard", "system.notify", "agent.pending", "web.fetch", "github.repo",
        ])
        #expect(tools.allSatisfy { !$0.parameters.isEmpty })
        let allOptionalTools: Set<String> = [
            "create_terminal", "view_memory", "mem_context_snapshot", "list_workers",
            "env_capture_logs", "env_info", "derived_data_locate",
        ]
        #expect(tools.allSatisfy {
            allOptionalTools.contains($0.name) || $0.parameters.contains { $0.required }
        })
        for tool in tools {
            #expect(SystemToolRegistry.definition(named: tool.name, for: .system) == tool)
        }
    }

    @Test("Slice 1 tools register with their real backend actions")
    func sliceOneToolsRegister() {
        let expected: [(String, String)] = [
            ("delete_file", "workspace.delete_file"),
            ("delete_directory", "workspace.delete_directory"),
            ("move_file", "workspace.move_file"),
            ("copy_file", "workspace.copy_file"),
            ("create_directory", "workspace.create_dir"),
            ("read_directory", "workspace.read_dir"),
            ("edit_file", "workspace.edit_file"),
            ("multi_edit_file", "workspace.edit_file"),
            ("search_regex", "workspace.search_regex"),
            ("run_build", "terminal.create"),
            ("run_tests", "terminal.create"),
            ("git_commit", "git.actions.run"),
            ("git_push", "git.actions.run"),
            ("git_pull", "git.actions.pull"),
            ("git_branch_list", "git.branches.list"),
            ("git_branch_create", "git.branches.create"),
            ("git_branch_checkout", "git.branches.checkout"),
        ]
        for (name, action) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.parameters.contains { $0.required })
        }
        #expect(SystemToolRegistry.definition(named: "edit_file", for: .system)?.parameters.map(\.name).contains("mode") == true)
        #expect(SystemToolRegistry.definition(named: "read_directory", for: .system)?.parameters.map(\.name).contains("recursive") == true)
        #expect(SystemToolRegistry.definition(named: "git_commit", for: .system)?.parameters.map(\.name).contains("message") == true)
    }

    @Test("Slice 6 tools register with their real backend actions")
    func sliceSixToolsRegister() {
        let expected: [(String, String)] = [
            ("git_log", "git.log"),
            ("git_show", "git.show"),
            ("git_diff_range", "git.diff.range"),
            ("git_diff_branch", "git.diff.branch"),
        ]
        for (name, action) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == .engine)
            #expect(definition.parameters.contains { $0.required })
        }
        #expect(SystemToolRegistry.definition(named: "git_log", for: .system)?.parameters.map(\.name) == ["threadId", "limit", "skip"])
        #expect(SystemToolRegistry.definition(named: "git_show", for: .system)?.parameters.map(\.name) == ["threadId", "sha"])
        #expect(SystemToolRegistry.definition(named: "git_diff_range", for: .system)?.parameters.map(\.name) == ["threadId", "from", "to"])
        #expect(SystemToolRegistry.definition(named: "git_diff_branch", for: .system)?.parameters.map(\.name) == ["threadId"])
    }

    @Test("Slice 10 tools register with their real backend actions")
    func sliceTenToolsRegister() {
        let expected: [(String, String, SystemToolChannel)] = [
            ("file_read", "workspace.read_file", .desktop),
            ("view_file", "workspace.read_file", .desktop),
            ("file_write", "workspace.write_file", .desktop),
            ("create_file", "workspace.write_file", .desktop),
            ("file_create", "workspace.write_file", .desktop),
            ("file_append", "workspace.write_file", .desktop),
            ("file_delete", "workspace.delete_file", .desktop),
            ("dir_delete", "workspace.delete_directory", .desktop),
            ("file_move", "workspace.move_file", .desktop),
            ("file_rename", "workspace.move_file", .desktop),
            ("file_copy", "workspace.copy_file", .desktop),
            ("dir_create", "workspace.create_dir", .desktop),
            ("dir_read", "workspace.read_dir", .desktop),
            ("list_directory", "workspace.read_dir", .desktop),
            ("tree_view", "workspace.read_dir", .desktop),
            ("search_directory", "workspace.files", .desktop),
            ("search_text", "workspace.search", .desktop),
            ("code_replace", "workspace.edit_file", .desktop),
            ("code_insert", "workspace.write_file", .desktop),
            ("code_multi_edit", "workspace.edit_file", .desktop),
            ("use_terminal", "terminal.create", .engine),
            ("run_command", "terminal.create", .engine),
            ("git_log_viewer", "git.log", .engine),
            ("git_branch_compare", "git.diff.range", .engine),
            ("project_diff", "git.diff", .engine),
            ("git_branch_manager", "git.branches.list", .engine),
            ("save_to_memory", "memory.store", .desktop),
            ("use_mcp", "mcp.tools", .desktop),
            ("take_screenshot", "computer_use.request", .engine),
            ("start_subagent", "workers.spawn", .desktop),
            ("git_stash_operator", "git.stash", .engine),
            ("git_blame_inspector", "git.blame", .engine),
            ("git_bisect", "git.bisect", .engine),
            ("git_cherry_pick", "git.cherry_pick", .engine),
            ("version_control_operator", "git.rollback", .engine),
            ("git_pr_summary", "git.log", .engine),
            ("git_conflict_resolver", "workspace.search_regex", .desktop),
            ("project_snapshot", "git.checkpoints.create", .engine),
            ("project_changelog", "git.checkpoints.list", .engine),
            ("project_restore", "git.checkpoints.restore", .engine),
            ("safe_undo", "git.checkpoints.restore", .engine),
            ("safe_validate_changes", "workspace.search_regex", .desktop),
        ]
        #expect(expected.count == 42)
        for (name, action, channel) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == channel)
            #expect(definition.parameters.contains { $0.required })
        }
        #expect(SystemToolRegistry.definition(named: "file_rename", for: .system)?.parameters.map(\.name) == ["cwd", "path", "newName"])
        #expect(SystemToolRegistry.definition(named: "git_stash_operator", for: .system)?.parameters.map(\.name).contains("action") == true)
        #expect(SystemToolRegistry.definition(named: "use_mcp", for: .system)?.parameters.map(\.name) == ["serverName", "toolName", "arguments"])
        #expect(SystemToolRegistry.definition(named: "project_restore", for: .system)?.parameters.map(\.name).contains("confirm") == true)
        #expect(SystemToolRegistry.definition(named: "code_insert", for: .system)?.parameters.map(\.name).contains("mode") == true)
        #expect(SystemToolRegistry.definition(named: "edit_file", for: .system) != nil)
    }

    @Test("Slice 10 destructive tools refuse without confirm before any runtime call")
    func sliceTenConfirmationRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let missingConfirm: [(String, [String: JSONValue])] = [
            ("git_cherry_pick", ["threadId": .string("t"), "sha": .string("0123456789abcdef0123456789abcdef01234567")]),
            ("git_branch_manager", ["threadId": .string("t"), "action": .string("delete"), "name": .string("spare")]),
            ("version_control_operator", ["threadId": .string("t"), "action": .string("rollback")]),
            ("project_restore", ["threadId": .string("t"), "checkpointId": .string("abc")]),
            ("safe_undo", ["threadId": .string("t")]),
            ("git_stash_operator", ["threadId": .string("t"), "action": .string("pop")]),
            ("git_stash_operator", ["threadId": .string("t"), "action": .string("drop")]),
        ]
        for (tool, arguments) in missingConfirm {
            do {
                _ = try await SystemToolRegistry.execute(
                    tool, arguments: arguments, toolset: .system, runtime: client
                )
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: "confirm"))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        do {
            _ = try await SystemToolRegistry.execute(
                "git_cherry_pick",
                arguments: [
                    "threadId": .string("t"),
                    "sha": .string("0123456789abcdef0123456789abcdef01234567"),
                    "confirm": .bool(false),
                ],
                toolset: .system, runtime: client
            )
            Issue.record("Expected executionFailed error for cherry-pick with confirm=false")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "git_cherry_pick", message: "Cherry-pick changes the working tree; pass confirm=true."))
        } catch {
            Issue.record("Unexpected error for cherry-pick with confirm=false: \(error)")
        }
        do {
            _ = try await SystemToolRegistry.execute(
                "file_rename",
                arguments: [
                    "cwd": .string("/tmp"),
                    "path": .string("a.txt"),
                    "newName": .string("sub/b.txt"),
                ],
                toolset: .system, runtime: client
            )
            Issue.record("Expected executionFailed error for file_rename with a path newName")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "file_rename", message: "newName must be a single file name, not a path."))
        } catch {
            Issue.record("Unexpected error for file_rename: \(error)")
        }
        await client.close()
    }

    @Test("Provider Tools mode registers no system tools")
    func providerModeRegistersNothing() {
        #expect(SystemToolRegistry.tools(for: .provider).isEmpty)
        for tool in SystemToolRegistry.systemTools {
            #expect(SystemToolRegistry.definition(named: tool.name, for: .provider) == nil)
        }
        #expect(SystemToolRegistry.definition(named: "read_file", for: .provider) == nil)
        #expect(SystemToolRegistry.definition(named: "no_such_tool", for: .system) == nil)
    }

    @Test("Executing a system tool under Provider Tools fails before any runtime call")
    func providerModeExecutionRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            try await SystemToolRegistry.execute(
                "read_file", arguments: ["cwd": .string("/tmp"), "path": .string("x.txt")],
                toolset: .provider, runtime: client
            )
            Issue.record("Expected toolNotActive error")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "read_file", toolset: .provider))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        do {
            try await SystemToolRegistry.execute(
                "no_such_tool", arguments: [:], toolset: .system, runtime: client
            )
            Issue.record("Expected unknownTool error")
        } catch let error as SystemToolError {
            #expect(error == .unknownTool("no_such_tool"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        await client.close()
    }

    @Test("execute() enforces allowedTools, including through use_mcp")
    func executeEnforcesAllowedTools() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        #expect(SystemToolRegistry.definition(named: "mem_store", for: .system, allowedTools: ["mem_store"]) != nil)
        #expect(SystemToolRegistry.definition(named: "mem_store", for: .system, allowedTools: ["mem_retrieve"]) == nil)
        #expect(SystemToolRegistry.definition(named: "mem_store", for: .system, allowedTools: ["mem_store", "not_a_tool"]) != nil)
        #expect(SystemToolRegistry.definition(named: "mem_store", for: .system, allowedTools: nil) != nil)
        #expect(SystemToolRegistry.definition(named: "mem_store", for: .system, allowedTools: []) != nil)
        #expect(SystemToolRegistry.definition(named: "no_such_tool", for: .system, allowedTools: ["no_such_tool"]) == nil)
        let stored = try await SystemToolRegistry.execute(
            "mem_store",
            arguments: ["key": .string("allowed"), "value": .string("yes"), "scope": .string("global")],
            toolset: .system, runtime: client, allowedTools: ["mem_store"]
        )
        #expect(stored["overwritten"]?.boolValue == false)
        let unlisted = try await SystemToolRegistry.execute(
            "mem_store",
            arguments: ["key": .string("unlisted"), "value": .string("yes"), "scope": .string("global")],
            toolset: .system, runtime: client, allowedTools: nil
        )
        #expect(unlisted["overwritten"]?.boolValue == false)
        do {
            _ = try await SystemToolRegistry.execute(
                "mem_store",
                arguments: ["key": .string("blocked"), "value": .string("no"), "scope": .string("global")],
                toolset: .system, runtime: client, allowedTools: ["mem_retrieve"]
            )
            Issue.record("Expected toolNotActive error for disallowed mem_store")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "mem_store", toolset: .system))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        do {
            _ = try await SystemToolRegistry.execute(
                "use_mcp",
                arguments: [
                    "serverName": .string("coincide"),
                    "toolName": .string("mem_store"),
                    "arguments": .string("{\"key\": \"via_mcp\", \"value\": \"no\", \"scope\": \"global\"}"),
                ],
                toolset: .system, runtime: client, allowedTools: ["use_mcp"]
            )
            Issue.record("Expected toolNotActive error for mem_store reached through use_mcp")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "mem_store", toolset: .system))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        let viaMcp = try await SystemToolRegistry.execute(
            "use_mcp",
            arguments: [
                "serverName": .string("coincide"),
                "toolName": .string("mem_store"),
                "arguments": .string("{\"key\": \"via_mcp\", \"value\": \"yes\", \"scope\": \"global\"}"),
            ],
            toolset: .system, runtime: client, allowedTools: ["use_mcp", "mem_store"]
        )
        #expect(viaMcp["overwritten"]?.boolValue == false)
        await client.close()
    }

    @Test("execute() gates use_app inner actions against allowedTools")
    func executeGatesUseAppInnerActions() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let threadID = try await client.newThread()
        let turnedOn = try await client.computerUseSetEnabled(true)
        #expect(turnedOn.enabled == true)
        let listed = try await SystemToolRegistry.execute(
            "use_app",
            arguments: ["threadId": .string(threadID.uuidString), "action": .string("list_applications")],
            toolset: .system, runtime: client, allowedTools: ["use_app", "list_apps"]
        )
        #expect(listed["action"]?.stringValue == "list_applications")
        #expect(listed["tool"]?.stringValue == "list_apps")
        do {
            _ = try await SystemToolRegistry.execute(
                "use_app",
                arguments: ["threadId": .string(threadID.uuidString), "action": .string("click")],
                toolset: .system, runtime: client, allowedTools: ["use_app"]
            )
            Issue.record("Expected toolNotActive error for click reached through use_app")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "click", toolset: .system))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        do {
            _ = try await SystemToolRegistry.execute(
                "use_app",
                arguments: ["threadId": .string(threadID.uuidString), "action": .string("click")],
                toolset: .system, runtime: client, allowedTools: ["click"]
            )
            Issue.record("Expected toolNotActive error for disallowed use_app")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "use_app", toolset: .system))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "use_app", message: "use_app action no_such_action is not a known action.")) {
            try await SystemToolRegistry.execute(
                "use_app",
                arguments: ["threadId": .string(threadID.uuidString), "action": .string("no_such_action")],
                toolset: .system, runtime: client, allowedTools: ["use_app"]
            )
        }
        _ = try await client.computerUseSetEnabled(false)
        await client.close()
    }

    @Test("Executing a system tool without required arguments fails before any runtime call")
    func missingArgumentRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            try await SystemToolRegistry.execute(
                "read_file", arguments: ["cwd": .string("/tmp")],
                toolset: .system, runtime: client
            )
            Issue.record("Expected missingArgument error")
        } catch let error as SystemToolError {
            #expect(error == .missingArgument(tool: "read_file", argument: "path"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        await client.close()
    }

    @Test("Slice 1 tools refuse missing arguments before any runtime call")
    func sliceOneMissingArgumentRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cases: [(String, [String: JSONValue], String)] = [
            ("delete_file", ["cwd": .string("/tmp")], "path"),
            ("move_file", ["cwd": .string("/tmp"), "path": .string("a.txt")], "destination"),
            ("edit_file", ["cwd": .string("/tmp"), "path": .string("a.txt"), "oldText": .string("x")], "newText"),
            ("multi_edit_file", ["cwd": .string("/tmp"), "path": .string("a.txt")], "edits"),
            ("search_regex", ["cwd": .string("/tmp")], "pattern"),
            ("run_build", ["threadId": .string("t")], "command"),
            ("git_commit", ["threadId": .string("t")], "message"),
            ("git_branch_create", ["threadId": .string("t")], "name"),
        ]
        for (tool, arguments, missing) in cases {
            do {
                _ = try await SystemToolRegistry.execute(
                    tool, arguments: arguments, toolset: .system, runtime: client
                )
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: missing))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        await client.close()
    }

    @Test("Stored toolset on a thread wins over the global selection")
    func storedToolsetWins() {
        let (defaults, suiteName) = Self.ephemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AgentToolset.save(.provider, to: defaults)
        #expect(AgentToolset.effective(stored: Self.summary(toolset: "system").toolset) == .system)
        AgentToolset.save(.system, to: defaults)
        #expect(AgentToolset.effective(stored: Self.summary(toolset: "provider").toolset) == .provider)
        #expect(AgentToolset.effective(stored: Self.summary(toolset: nil).toolset) == .provider)
        #expect(AgentToolset.effective(stored: "bogus") == .provider)
    }

    @Test("Thread summary toolset survives a Codable round trip")
    func summaryToolsetRoundTrips() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let stored = Self.summary(toolset: "system")
        let data = try encoder.encode(stored)
        #expect(try decoder.decode(RemoteThreadSummary.self, from: data).toolset == "system")
        let legacy = Self.summary(toolset: nil)
        let legacyData = try encoder.encode(legacy)
        #expect(!String(data: legacyData, encoding: .utf8)!.contains("toolset"))
        #expect(try decoder.decode(RemoteThreadSummary.self, from: legacyData).toolset == nil)
    }

    @Test("New-thread request carries the system prompt and toolset")
    func newThreadRequestCarriesPromptAndToolset() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let projectID = UUID()
        let message = RemoteClientMessage(
            request: .newThread(projectID: projectID, systemPrompt: "Behave.", toolset: "system", allowedTools: ["read_file"])
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(RemoteClientMessage.self, from: data)
        guard case .newThread(let decodedProject, let prompt, let toolset, let allowedTools, let assistantId, _) = decoded.request else {
            Issue.record("Expected newThread request")
            return
        }
        #expect(decodedProject == projectID)
        #expect(prompt == "Behave.")
        #expect(toolset == "system")
        #expect(allowedTools == ["read_file"])
    }

    @Test("New-thread request without allowed tools encodes an absent list")
    func newThreadRequestWithoutAllowedTools() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let message = RemoteClientMessage(
            request: .newThread(projectID: nil, systemPrompt: nil, toolset: nil, allowedTools: nil)
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(RemoteClientMessage.self, from: data)
        guard case .newThread(_, _, _, let allowedTools, _, _) = decoded.request else {
            Issue.record("Expected newThread request")
            return
        }
        #expect(allowedTools == nil)
    }

    @Test("New-thread creation rejects an unknown tool name at the bridge")
    func newThreadRejectsUnknownToolName() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF2Tools")
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.newThread(projectID: projectID, allowedTools: ["not_a_real_tool"])
        }
        let created = try await client.newThread(projectID: projectID, allowedTools: ["read_file"])
        let workspace = try await client.fetchWorkspace()
        let summary = workspace.threads.first { $0.id == created }
        #expect(summary?.allowedTools == ["read_file"])
        await client.close()
    }

    @Test("New-thread creation applies a full selection override")
    func newThreadAppliesFullSelection() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF6bSelection")
        let created = try await client.newThread(
            projectID: projectID,
            selection: RemoteSelectionOverride(provider: "claude", modelID: "claude-sonnet-4"))
        let workspace = try await client.fetchWorkspace()
        let summary = workspace.threads.first { $0.id == created }
        #expect(summary?.selection.provider == "claude")
        #expect(summary?.selection.modelID == "claude-sonnet-4")
        await client.close()
    }

    @Test("New-thread creation with a provider-only selection uses the provider default model")
    func newThreadProviderOnlySelection() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF6bSelection")
        let created = try await client.newThread(
            projectID: projectID,
            selection: RemoteSelectionOverride(provider: "grok"))
        let workspace = try await client.fetchWorkspace()
        let summary = workspace.threads.first { $0.id == created }
        #expect(summary?.selection.provider == "grok")
        #expect(summary?.selection.modelID == "default")
        await client.close()
    }

    @Test("New-thread creation with a model-only selection keeps the default provider")
    func newThreadModelOnlySelection() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF6bSelection")
        let created = try await client.newThread(
            projectID: projectID,
            selection: RemoteSelectionOverride(modelID: "gpt-5"))
        let workspace = try await client.fetchWorkspace()
        let summary = workspace.threads.first { $0.id == created }
        #expect(summary?.selection.provider == "codex")
        #expect(summary?.selection.modelID == "gpt-5")
        await client.close()
    }

    @Test("New-thread creation without a selection keeps today's defaults")
    func newThreadWithoutSelectionKeepsDefaults() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF6bSelection")
        _ = try await client.saveProjectDefaults(RemoteProjectDefaults(
            projectID: projectID, usesGlobalDefaults: false, provider: "codex", modelID: "default"))
        let created = try await client.newThread(projectID: projectID)
        let workspace = try await client.fetchWorkspace()
        let summary = workspace.threads.first { $0.id == created }
        #expect(summary?.selection.provider == "codex")
        #expect(summary?.selection.modelID == "default")
        await client.close()
    }

    @Test("New-thread creation rejects an unknown provider before creating anything")
    func newThreadRejectsUnknownProvider() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF6bSelection")
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.newThread(
                projectID: projectID,
                selection: RemoteSelectionOverride(provider: "not-a-provider"))
        }
        let workspace = try await client.fetchWorkspace()
        #expect(workspace.threads.filter { $0.projectID == projectID }.isEmpty)
        await client.close()
    }

    @Test("New-thread creation rejects an overlong model before creating anything")
    func newThreadRejectsOverlongModel() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF6bSelection")
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.newThread(
                projectID: projectID,
                selection: RemoteSelectionOverride(modelID: String(repeating: "m", count: 513)))
        }
        let workspace = try await client.fetchWorkspace()
        #expect(workspace.threads.filter { $0.projectID == projectID }.isEmpty)
        await client.close()
    }

    @Test("Old new-thread messages without prompt fields decode to nils")
    func oldNewThreadDecodes() throws {
        let json = """
        {"v":1,"id":"old","type":"newThread","body":{"projectID":"\(UUID().uuidString)"}}
        """
        let decoded = try RemoteProtocol.makeDecoder().decode(
            RemoteClientMessage.self, from: Data(json.utf8)
        )
        guard case .newThread(let project, let prompt, let toolset, let allowedTools, _, _) = decoded.request else {
            Issue.record("Expected newThread request")
            return
        }
        #expect(project != nil)
        #expect(prompt == nil)
        #expect(toolset == nil)
        #expect(allowedTools == nil)
    }

    @Test("Send request carries the system prompt and old sends decode without it")
    func sendRequestCarriesPrompt() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let request = RemoteSendRequest(
            threadID: UUID(), text: "Hi", systemPrompt: "Behave."
        )
        #expect(request.systemPrompt == "Behave.")
        let data = try encoder.encode(request)
        #expect(try decoder.decode(RemoteSendRequest.self, from: data).systemPrompt == "Behave.")
        let old = try decoder.decode(
            RemoteSendRequest.self,
            from: Data("{\"threadID\":\"\(UUID().uuidString)\",\"text\":\"Hi\",\"images\":[],\"delivery\":\"automatic\"}".utf8)
        )
        #expect(old.systemPrompt == nil)
        #expect(old.allowedTools == nil)
    }

    @Test("Send request carries allowed tools and old sends decode without them")
    func sendRequestCarriesAllowedTools() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let request = RemoteSendRequest(
            threadID: UUID(), text: "Hi", systemPrompt: "Behave.", allowedTools: ["read_file"]
        )
        #expect(request.allowedTools == ["read_file"])
        let data = try encoder.encode(request)
        #expect(try decoder.decode(RemoteSendRequest.self, from: data).allowedTools == ["read_file"])
    }

    @Test("Update-stored-prompt request carries the prompt and tools")
    func updateStoredPromptRequestCarriesPromptAndTools() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let threadID = UUID()
        let message = RemoteClientMessage(
            request: .updateStoredPrompt(threadID: threadID, systemPrompt: "Behave.", allowedTools: ["read_file"])
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(RemoteClientMessage.self, from: data)
        guard case .updateStoredPrompt(let decodedThread, let prompt, let allowedTools) = decoded.request else {
            Issue.record("Expected updateStoredPrompt request")
            return
        }
        #expect(decodedThread == threadID)
        #expect(prompt == "Behave.")
        #expect(allowedTools == ["read_file"])
    }

    @Test("Update-stored-prompt request without allowed tools encodes an absent list")
    func updateStoredPromptRequestWithoutAllowedTools() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let message = RemoteClientMessage(
            request: .updateStoredPrompt(threadID: UUID(), systemPrompt: "Behave.", allowedTools: nil)
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(RemoteClientMessage.self, from: data)
        guard case .updateStoredPrompt(_, let prompt, let allowedTools) = decoded.request else {
            Issue.record("Expected updateStoredPrompt request")
            return
        }
        #expect(prompt == "Behave.")
        #expect(allowedTools == nil)
    }

    @Test("Update-stored-prompt request requires its prompt field")
    func updateStoredPromptRequestRequiresPrompt() throws {
        let json = """
        {"v":1,"id":"old","type":"updateStoredPrompt","body":{"threadID":"\(UUID().uuidString)"}}
        """
        #expect(throws: RemoteProtocolError.self) {
            try RemoteProtocol.makeDecoder().decode(RemoteClientMessage.self, from: Data(json.utf8))
        }
    }

    @Test("Stored-prompt update rejects invalid prompts and provider-toolset threads, and accepts a valid one")
    func updateStoredPromptRejectsInvalidUpdates() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "SliceF4StoredPrompt")
        let systemThread = try await client.newThread(projectID: projectID, toolset: .system)
        let oversize = String(repeating: "x", count: 65 * 1024 + 1)
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.updateStoredPrompt(threadID: systemThread, prompt: oversize)
        }
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.updateStoredPrompt(threadID: systemThread, prompt: "   ")
        }
        try await client.updateStoredPrompt(threadID: systemThread, prompt: "Behave.", allowedTools: ["read_file"])
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.updateStoredPrompt(threadID: systemThread, prompt: "Behave.", allowedTools: ["not_a_real_tool"])
        }
        let providerThread = try await client.newThread(projectID: projectID, toolset: .provider)
        await #expect(throws: AgentsRuntimeError.self) {
            try await client.updateStoredPrompt(threadID: providerThread, prompt: "Behave.")
        }
        await client.close()
    }

    @Test("Computer Use tools register with the real engine action")
    func computerUseToolsRegister() {
        let expected: [String] = [
            "list_apps", "list_windows", "get_window_state", "get_desktop_state",
            "verify_state", "zoom", "click", "double_click", "right_click", "set_value",
            "type_text", "press_key", "hotkey", "scroll", "drag", "move_cursor",
            "click_point", "invoke_menu", "launch_app", "set_window_frame",
            "take_screenshot",
        ]
        for name in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == "computer_use.request")
            #expect(definition.channel == .engine)
            #expect(definition.parameters.first { $0.name == "threadId" }?.required == true)
            #expect(definition.parameters.first { $0.name == "threadId" }?.type == "string")
            #expect(definition.parameters.contains { $0.required })
        }
        #expect(SystemToolRegistry.definition(named: "click", for: .system)?.parameters.map(\.name).contains("element_token") == true)
        #expect(SystemToolRegistry.definition(named: "click", for: .system)?.parameters.first { $0.name == "element_token" }?.required == true)
        #expect(SystemToolRegistry.definition(named: "get_window_state", for: .system)?.parameters.first { $0.name == "pid" }?.required == true)
        #expect(SystemToolRegistry.definition(named: "get_window_state", for: .system)?.parameters.first { $0.name == "window_id" }?.required == true)
        #expect(SystemToolRegistry.definition(named: "launch_app", for: .system)?.parameters.first { $0.name == "bundle_id" }?.required == true)
        #expect(SystemToolRegistry.definition(named: "take_screenrecord", for: .system) == nil)
        #expect(SystemToolRegistry.definition(named: "use_app", for: .system)?.name == "use_app")
    }

    @Test("Computer Use tools refuse missing arguments before any runtime call")
    func computerUseMissingArgumentRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cases: [(String, [String: JSONValue], String)] = [
            ("click", ["threadId": .string("t")], "element_token"),
            ("get_window_state", ["threadId": .string("t"), "window_id": .int(1)], "pid"),
            ("get_window_state", ["threadId": .string("t"), "pid": .int(1)], "window_id"),
            ("launch_app", ["threadId": .string("t")], "bundle_id"),
            ("scroll", ["threadId": .string("t")], "direction"),
            ("invoke_menu", ["threadId": .string("t"), "pid": .int(1)], "path"),
        ]
        for (tool, arguments, missing) in cases {
            do {
                _ = try await SystemToolRegistry.execute(
                    tool, arguments: arguments, toolset: .system, runtime: client
                )
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: missing))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        do {
            _ = try await SystemToolRegistry.execute(
                "click", arguments: ["threadId": .string("t"), "element_token": .string("x")],
                toolset: .provider, runtime: client
            )
            Issue.record("Expected toolNotActive error")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "click", toolset: .provider))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        await client.close()
    }

    @Test("System prompt built for a thread fits the 64 KiB instruction cap")
    func systemPromptFitsInstructionCap() {
        let manager = SystemAssetManager(directory: Self.assetsDirectory())
        #expect(manager.isReady)
        let prompt = manager.systemPrompt(for: "Run the build and fix the failing tests", provider: "codex", model: "default")
        #expect(!prompt.text.isEmpty)
        #expect(prompt.text.utf8.count <= 64 * 1024)
        #expect(prompt.includedDocumentIDs.contains("AvailableTools"))
        #expect(prompt.includedDocumentIDs.contains("ToolRoutingPolicy"))
    }

    private static func run(
        _ tool: String,
        arguments: [String: JSONValue],
        client: AgentsRuntimeClient
    ) async throws -> JSONValue {
        try await SystemToolRegistry.execute(tool, arguments: arguments, toolset: .system, runtime: client)
    }

    private static func writeText(_ text: String, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func readText(_ relativePath: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func writeData(_ data: Data, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    @Test("Slice 11 tools register with their real backend actions")
    func sliceElevenToolsRegister() {
        let expected: [(String, String, SystemToolChannel)] = [
            ("create_artifact", "workspace.write_file", .desktop),
            ("list_artifacts", "workspace.read_dir", .desktop),
            ("read_artifact", "workspace.read_file", .desktop),
            ("delete_artifact", "workspace.delete_file", .desktop),
            ("format_json_file", "workspace.write_file", .desktop),
            ("csv_to_json", "workspace.write_file", .desktop),
            ("json_to_csv", "workspace.write_file", .desktop),
            ("plist_to_json", "workspace.write_file", .desktop),
            ("json_to_plist", "workspace.write_file", .desktop),
            ("json_validate", "workspace.write_file", .desktop),
            ("json_validator_tool", "workspace.read_file", .desktop),
            ("yaml_validate", "workspace.write_file", .desktop),
            ("yaml_parser_tool", "workspace.read_file", .desktop),
            ("plist_edit", "workspace.write_file", .desktop),
            ("plist_editor", "workspace.write_file", .desktop),
            ("binary_plist_converter", "workspace.write_file", .desktop),
            ("file_metadata", "workspace.read_dir", .desktop),
            ("file_hash_verify", "workspace.read_file", .desktop),
            ("generate_file_checksum", "workspace.read_file", .desktop),
            ("file_checksum_verifier", "workspace.read_file", .desktop),
            ("file_compare_diff", "workspace.read_file", .desktop),
            ("file_head_preview", "workspace.read_file", .desktop),
            ("code_generate", "workspace.write_file", .desktop),
            ("code_format", "workspace.write_file", .desktop),
            ("swift_format_lint", "terminal.create", .engine),
            ("code_mutation_engine", "workspace.write_file", .desktop),
            ("patch_application_engine", "workspace.write_file", .desktop),
            ("automated_repair_engine", "workspace.write_file", .desktop),
            ("regex_replace_in_files", "workspace.write_file", .desktop),
            ("symbol_rename_project", "workspace.write_file", .desktop),
            ("symbol_move_file", "workspace.write_file", .desktop),
            ("import_cleanup", "workspace.write_file", .desktop),
            ("batch_rename_files", "workspace.move_file", .desktop),
            ("file_backup", "workspace.copy_file", .desktop),
            ("session_export", "workspace.write_file", .desktop),
            ("markdown_toc_generate", "workspace.write_file", .desktop),
            ("readme_generate", "workspace.write_file", .desktop),
            ("docs_generate", "workspace.write_file", .desktop),
            ("test_data_factory", "workspace.write_file", .desktop),
            ("ui_test_scaffold", "workspace.write_file", .desktop),
            ("test_snapshot_manage", "workspace.read_dir", .desktop),
            ("open_in_finder", "system.open_in_finder", .desktop),
            ("reveal_in_finder", "system.reveal_in_finder", .desktop),
            ("image_encode_base64", "workspace.read_file", .desktop),
            ("image_decode_base64", "workspace.write_file", .desktop),
            ("image_get_dimensions", "terminal.create", .engine),
            ("image_convert_format", "terminal.create", .engine),
            ("image_generate_thumbnail", "terminal.create", .engine),
            ("image_extract_metadata", "terminal.create", .engine),
            ("zip_file", "terminal.create", .engine),
            ("unzip_file", "terminal.create", .engine),
            ("tar_archive_create", "terminal.create", .engine),
            ("tar_archive_extract", "terminal.create", .engine),
            ("gzip_compress_file", "terminal.create", .engine),
            ("gzip_decompress_file", "terminal.create", .engine),
            ("count_file_lines", "workspace.read_file", .desktop),
            ("extract_code_symbols", "workspace.read_file", .desktop),
            ("find_duplicate_files", "workspace.read_file", .desktop),
            ("env_capture_logs", "memory.snapshot", .desktop),
        ]
        #expect(expected.count == 59)
        for (name, action, channel) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == channel)
            if name != "env_capture_logs" {
                #expect(definition.parameters.contains { $0.required })
            }
        }
        #expect(SystemToolRegistry.definition(named: "file_append", for: .system)?.action == "workspace.write_file")
        #expect(SystemToolRegistry.definition(named: "delete_artifact", for: .system)?.parameters.map(\.name).contains("confirm") == true)
        #expect(SystemToolRegistry.definition(named: "plist_editor", for: .system)?.parameters.map(\.name).contains("action") == true)
    }

    @Test("Slice 11 artifacts round-trip through the real workspace")
    func sliceElevenArtifactsRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        let created = try await Self.run("create_artifact", arguments: ["cwd": .string(cwd), "name": .string("notes"), "content": .string("# Hello\n")], client: client)
        #expect(created["path"]?.stringValue == ".assist_temp/artifacts/notes.md")
        #expect(created["kind"]?.stringValue == "artifact")
        #expect(created["appended"]?.boolValue == false)
        let appended = try await Self.run("create_artifact", arguments: ["cwd": .string(cwd), "name": .string("notes"), "content": .string("More\n"), "append": .bool(true)], client: client)
        #expect(appended["appended"]?.boolValue == true)
        let read = try await Self.run("read_artifact", arguments: ["cwd": .string(cwd), "name": .string("notes")], client: client)
        #expect(read["content"]?.stringValue == "# Hello\nMore\n")
        #expect(read["truncated"]?.boolValue == false)
        let listed = try await Self.run("list_artifacts", arguments: ["cwd": .string(cwd)], client: client)
        let names = listed.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names == ["notes.md"])
        do {
            _ = try await Self.run("create_artifact", arguments: ["cwd": .string(cwd), "name": .string("../escape"), "content": .string("x")], client: client)
            Issue.record("Expected executionFailed for an escaping artifact name")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "create_artifact", message: "Artifact name must be a plain file name without any path separator."))
        } catch {
            Issue.record("Unexpected error for escaping artifact name: \(error)")
        }
        do {
            _ = try await Self.run("create_artifact", arguments: ["cwd": .string(cwd), "name": .string("notes"), "content": .string("x"), "kind": .string("bogus")], client: client)
            Issue.record("Expected executionFailed for a bogus artifact kind")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "create_artifact", message: "Artifact kind must be artifact or execution_plan."))
        } catch {
            Issue.record("Unexpected error for bogus artifact kind: \(error)")
        }
        do {
            _ = try await Self.run("delete_artifact", arguments: ["cwd": .string(cwd), "name": .string("notes")], client: client)
            Issue.record("Expected missingArgument for delete_artifact without confirm")
        } catch let error as SystemToolError {
            #expect(error == .missingArgument(tool: "delete_artifact", argument: "confirm"))
        } catch {
            Issue.record("Unexpected error for delete_artifact without confirm: \(error)")
        }
        _ = try await Self.run("create_artifact", arguments: ["cwd": .string(cwd), "name": .string("agent_notes.md"), "content": .string("protected\n")], client: client)
        do {
            _ = try await Self.run("delete_artifact", arguments: ["cwd": .string(cwd), "name": .string("agent_notes.md"), "confirm": .bool(true)], client: client)
            Issue.record("Expected executionFailed for deleting agent_notes.md")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "delete_artifact", message: "agent_notes.md is protected and cannot be deleted."))
        } catch {
            Issue.record("Unexpected error for deleting agent_notes.md: \(error)")
        }
        do {
            _ = try await Self.run("delete_artifact", arguments: ["cwd": .string(cwd), "name": .string("agent_notes"), "confirm": .bool(true)], client: client)
            Issue.record("Expected executionFailed for deleting agent_notes without the .md suffix")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "delete_artifact", message: "agent_notes.md is protected and cannot be deleted."))
        } catch {
            Issue.record("Unexpected error for deleting agent_notes without the .md suffix: \(error)")
        }
        let deleted = try await Self.run("delete_artifact", arguments: ["cwd": .string(cwd), "name": .string("notes"), "confirm": .bool(true)], client: client)
        #expect(deleted["deleted"]?.boolValue == true)
        let afterDelete = try await Self.run("list_artifacts", arguments: ["cwd": .string(cwd)], client: client)
        #expect(afterDelete.arrayValue?.count == 1)
        await client.close()
    }

    @Test("Slice 11 structured data round-trips through the real workspace")
    func sliceElevenStructuredDataRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("{\"b\": 2, \"a\": 1}", to: "data.json", in: tempRoot)
        let formatted = try await Self.run("format_json_file", arguments: ["cwd": .string(cwd), "path": .string("data.json")], client: client)
        #expect(formatted["valid"]?.boolValue == true)
        let formattedText = try Self.readText("data.json", in: tempRoot)
        #expect(formattedText.contains("\"a\": 1"))
        if let aIndex = formattedText.range(of: "\"a\""), let bIndex = formattedText.range(of: "\"b\"") {
            #expect(aIndex.lowerBound < bIndex.lowerBound)
        } else {
            Issue.record("Expected formatted JSON to contain both keys")
        }
        try Self.writeText("name,age\nAda,36\nGrace,28\n", to: "messy.csv", in: tempRoot)
        let csvResult = try await Self.run("csv_to_json", arguments: ["cwd": .string(cwd), "path": .string("messy.csv")], client: client)
        #expect(csvResult["rows"]?.intValue == 2)
        #expect(csvResult["output"]?.stringValue == "messy.json")
        let csvJson = try Self.readText("messy.json", in: tempRoot)
        #expect(csvJson.contains("\"name\": \"Ada\""))
        #expect(csvJson.contains("\"age\": \"36\""))
        try Self.writeText("[{\"name\":\"Ada\",\"age\":36},{\"name\":\"Grace\",\"age\":28}]", to: "records.json", in: tempRoot)
        let jsonCsv = try await Self.run("json_to_csv", arguments: ["cwd": .string(cwd), "path": .string("records.json")], client: client)
        #expect(jsonCsv["rows"]?.intValue == 2)
        #expect(try Self.readText("records.csv", in: tempRoot) == "age,name\n36,Ada\n28,Grace\n")
        try Self.writeText("{\"a\": }", to: "broken.json", in: tempRoot)
        let invalid = try await Self.run("json_validate", arguments: ["cwd": .string(cwd), "path": .string("broken.json")], client: client)
        #expect(invalid["valid"]?.boolValue == false)
        #expect(invalid["error"]?.stringValue != nil)
        let validator = try await Self.run("json_validator_tool", arguments: ["cwd": .string(cwd), "path": .string("data.json")], client: client)
        #expect(validator["valid"]?.boolValue == true)
        #expect(validator["formatted"]?.stringValue?.contains("\"a\": 1") == true)
        try Self.writeText("name: demo\nport: 8080\n", to: "config.yaml", in: tempRoot)
        let yamlValid = try await Self.run("yaml_validate", arguments: ["cwd": .string(cwd), "path": .string("config.yaml"), "write": .bool(true)], client: client)
        #expect(yamlValid["valid"]?.boolValue == true)
        #expect(yamlValid["wrote"]?.boolValue == true)
        let parsed = try await Self.run("yaml_parser_tool", arguments: ["cwd": .string(cwd), "path": .string("config.yaml")], client: client)
        #expect(parsed["valid"]?.boolValue == true)
        #expect(parsed["value"]?["name"]?.stringValue == "demo")
        #expect(parsed["value"]?["port"]?.intValue == 8080)
        try Self.writeText("server:\n  host: localhost\n  port: 8080\n", to: "nested.yaml", in: tempRoot)
        let nested = try await Self.run("yaml_parser_tool", arguments: ["cwd": .string(cwd), "path": .string("nested.yaml")], client: client)
        #expect(nested["value"]?["server"]?["host"]?.stringValue == "localhost")
        #expect(nested["value"]?["server"]?["port"]?.intValue == 8080)
        try Self.writeText("name: demo\n\tbad: tab\n", to: "bad.yaml", in: tempRoot)
        let yamlBad = try await Self.run("yaml_validate", arguments: ["cwd": .string(cwd), "path": .string("bad.yaml")], client: client)
        #expect(yamlBad["valid"]?.boolValue == false)
        #expect(yamlBad["issues"]?.arrayValue?.count == 1)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleName</key>
        \t<string>Demo</string>
        \t<key>Version</key>
        \t<integer>3</integer>
        </dict>
        </plist>
        """
        try Self.writeText(plist, to: "Info.plist", in: tempRoot)
        let plistJson = try await Self.run("plist_to_json", arguments: ["cwd": .string(cwd), "path": .string("Info.plist")], client: client)
        #expect(plistJson["output"]?.stringValue == "Info.json")
        #expect(try Self.readText("Info.json", in: tempRoot).contains("CFBundleName"))
        let toBinary = try await Self.run("json_to_plist", arguments: ["cwd": .string(cwd), "path": .string("Info.json"), "output": .string("InfoBinary.plist"), "format": .string("binary")], client: client)
        #expect(toBinary["format"]?.stringValue == "binary")
        let backToXml = try await Self.run("binary_plist_converter", arguments: ["cwd": .string(cwd), "path": .string("InfoBinary.plist"), "format": .string("xml"), "output": .string("InfoXml.plist")], client: client)
        #expect(backToXml["converted"]?.boolValue == true)
        let getName = try await Self.run("plist_edit", arguments: ["cwd": .string(cwd), "path": .string("InfoXml.plist"), "action": .string("get"), "key": .string("CFBundleName")], client: client)
        #expect(getName["found"]?.boolValue == true)
        #expect(getName["value"]?.stringValue == "Demo")
        let setVersion = try await Self.run("plist_edit", arguments: ["cwd": .string(cwd), "path": .string("InfoXml.plist"), "action": .string("set"), "key": .string("Version"), "value": .string("4")], client: client)
        #expect(setVersion["value"]?.stringValue == "4")
        let editorRead = try await Self.run("plist_editor", arguments: ["cwd": .string(cwd), "path": .string("InfoXml.plist")], client: client)
        #expect(editorRead["value"]?["CFBundleName"]?.stringValue == "Demo")
        #expect(editorRead["value"]?["Version"]?.stringValue == "4")
        let editorDelete = try await Self.run("plist_editor", arguments: ["cwd": .string(cwd), "path": .string("InfoXml.plist"), "action": .string("delete"), "key": .string("Version")], client: client)
        #expect(editorDelete["deleted"]?.boolValue == true)
        let getDeleted = try await Self.run("plist_editor", arguments: ["cwd": .string(cwd), "path": .string("InfoXml.plist"), "action": .string("get"), "key": .string("Version")], client: client)
        #expect(getDeleted["found"]?.boolValue == false)
        await client.close()
    }

    @Test("Slice 11 file operations round-trip through the real workspace")
    func sliceElevenFileOpsRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("hello world\n", to: "hello.txt", in: tempRoot)
        let metadata = try await Self.run("file_metadata", arguments: ["cwd": .string(cwd), "path": .string("hello.txt")], client: client)
        #expect(metadata["name"]?.stringValue == "hello.txt")
        #expect(metadata["isDirectory"]?.boolValue == false)
        #expect(metadata["sizeBytes"]?.intValue == 12)
        #expect((metadata["modifiedAt"]?.doubleValue ?? 0) > 0)
        #expect(metadata["isSymlink"]?.boolValue == false)
        #expect(metadata["isExecutable"]?.boolValue == false)
        let checksums = try await Self.run("generate_file_checksum", arguments: ["cwd": .string(cwd), "path": .string("hello.txt")], client: client)
        let sha256 = checksums["sha256"]?.stringValue ?? ""
        #expect(sha256.count == 64)
        #expect(checksums["sha512"]?.stringValue?.count == 128)
        #expect(checksums["sha1"]?.stringValue?.count == 40)
        #expect(checksums["md5"]?.stringValue?.count == 32)
        let verify = try await Self.run("file_hash_verify", arguments: ["cwd": .string(cwd), "path": .string("hello.txt"), "expectedHash": .string(sha256)], client: client)
        #expect(verify["match"]?.boolValue == true)
        #expect(verify["hash"]?.stringValue == sha256)
        let mismatch = try await Self.run("file_hash_verify", arguments: ["cwd": .string(cwd), "path": .string("hello.txt"), "expectedHash": .string(String(repeating: "0", count: 64))], client: client)
        #expect(mismatch["match"]?.boolValue == false)
        let verifier = try await Self.run("file_checksum_verifier", arguments: ["cwd": .string(cwd), "path": .string("hello.txt"), "expectedHash": .string(sha256)], client: client)
        #expect(verifier["verified"]?.boolValue == true)
        #expect(verifier["sha256"]?.stringValue == sha256)
        try Self.writeText("one\ntwo\nthree\n", to: "a.txt", in: tempRoot)
        try Self.writeText("one\ntwo\nthree\n", to: "b.txt", in: tempRoot)
        let identical = try await Self.run("file_compare_diff", arguments: ["cwd": .string(cwd), "path": .string("a.txt"), "otherPath": .string("b.txt")], client: client)
        #expect(identical["identical"]?.boolValue == true)
        #expect(identical["added"]?.intValue == 0)
        #expect(identical["removed"]?.intValue == 0)
        try Self.writeText("one\nTWO\nthree\nfour\n", to: "c.txt", in: tempRoot)
        let changed = try await Self.run("file_compare_diff", arguments: ["cwd": .string(cwd), "path": .string("a.txt"), "otherPath": .string("c.txt")], client: client)
        #expect(changed["identical"]?.boolValue == false)
        #expect(changed["added"]?.intValue == 2)
        #expect(changed["removed"]?.intValue == 1)
        #expect(changed["diff"]?.stringValue?.contains("TWO") == true)
        let previewLines = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try Self.writeText(previewLines, to: "long.txt", in: tempRoot)
        let preview = try await Self.run("file_head_preview", arguments: ["cwd": .string(cwd), "path": .string("long.txt"), "lines": .int(5)], client: client)
        #expect(preview["totalLines"]?.intValue == 30)
        #expect(preview["truncated"]?.boolValue == true)
        #expect(preview["content"]?.stringValue?.split(separator: "\n").count == 5)
        let backup = try await Self.run("file_backup", arguments: ["cwd": .string(cwd), "path": .string("hello.txt")], client: client)
        #expect(backup["byteLen"]?.intValue == 12)
        let backupPath = backup["backupPath"]?.stringValue ?? ""
        #expect(backupPath.hasPrefix(".assist_temp/backups/hello."))
        #expect(backupPath.hasSuffix(".bak"))
        #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(backupPath).path))
        try Self.writeText("// comment\nlet x = 1\n\nlet y = 2\n", to: "code.swift", in: tempRoot)
        let counts = try await Self.run("count_file_lines", arguments: ["cwd": .string(cwd), "path": .string("code.swift")], client: client)
        #expect(counts["files"]?.intValue == 1)
        #expect(counts["total"]?.intValue == 4)
        #expect(counts["code"]?.intValue == 2)
        #expect(counts["comment"]?.intValue == 1)
        #expect(counts["blank"]?.intValue == 1)
        try Self.writeText("public struct Widget {\n    public func render() {}\n}\n", to: "Widget.swift", in: tempRoot)
        let symbols = try await Self.run("extract_code_symbols", arguments: ["cwd": .string(cwd), "path": .string("Widget.swift")], client: client)
        #expect(symbols["count"]?.intValue == 2)
        let symbolNames = symbols["symbols"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(symbolNames.contains("Widget"))
        #expect(symbolNames.contains("render"))
        try Self.writeText("same\n", to: "dups/dup1.txt", in: tempRoot)
        try Self.writeText("same\n", to: "dups/dup2.txt", in: tempRoot)
        try Self.writeText("different\n", to: "dups/unique.txt", in: tempRoot)
        let duplicates = try await Self.run("find_duplicate_files", arguments: ["cwd": .string(cwd), "path": .string("dups")], client: client)
        #expect(duplicates["count"]?.intValue == 1)
        let groupFiles = duplicates["groups"]?.arrayValue?.first?["files"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        #expect(groupFiles.contains("dups/dup1.txt"))
        #expect(groupFiles.contains("dups/dup2.txt"))
        #expect(duplicates["groups"]?.arrayValue?.first?["byteLen"]?.intValue == 5)
        await client.close()
    }

    @Test("Slice 11 code transforms round-trip through the real workspace")
    func sliceElevenCodeTransformsRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        let generated = try await Self.run("code_generate", arguments: ["cwd": .string(cwd), "path": .string("Gadget.swift"), "template": .string("swift_struct")], client: client)
        #expect(generated["template"]?.stringValue == "swift_struct")
        #expect(try Self.readText("Gadget.swift", in: tempRoot).contains("public struct Gadget"))
        do {
            _ = try await Self.run("code_generate", arguments: ["cwd": .string(cwd), "path": .string("Gadget.swift"), "template": .string("swift_struct")], client: client)
            Issue.record("Expected executionFailed for code_generate over an existing file")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "code_generate", message: "A file already exists at that path; use write_file to overwrite it."))
        } catch {
            Issue.record("Unexpected error for code_generate over an existing file: \(error)")
        }
        let scaffold = try await Self.run("code_generate", arguments: ["cwd": .string(cwd), "path": .string("GadgetTests.swift"), "template": .string("test")], client: client)
        #expect(scaffold["template"]?.stringValue == "test")
        #expect(try Self.readText("GadgetTests.swift", in: tempRoot).contains("#expect(Bool(false)"))
        try Self.writeText("let x\t= 1   \n\n\n\nlet y = 2\n", to: "messy.swift", in: tempRoot)
        let formatted = try await Self.run("code_format", arguments: ["cwd": .string(cwd), "path": .string("messy.swift")], client: client)
        #expect(formatted["formatted"]?.intValue == 1)
        #expect(try Self.readText("messy.swift", in: tempRoot) == "let x    = 1\n\n\nlet y = 2\n")
        try Self.writeText("alpha\nbeta\ngamma\n", to: "notes.txt", in: tempRoot)
        let mutated = try await Self.run("code_mutation_engine", arguments: ["cwd": .string(cwd), "path": .string("notes.txt"), "target": .string("beta"), "replacement": .string("BETA")], client: client)
        #expect(mutated["mutated"]?.boolValue == true)
        #expect(try Self.readText("notes.txt", in: tempRoot) == "alpha\nBETA\ngamma\n")
        try Self.writeText("struct Shape {\n    var side: Int\n}\n", to: "Shape.swift", in: tempRoot)
        let shapeMutated = try await Self.run("code_mutation_engine", arguments: ["cwd": .string(cwd), "path": .string("Shape.swift"), "symbol": .string("Shape"), "replacement": .string("    var side: Double\n    var area: Double")], client: client)
        #expect(shapeMutated["mutated"]?.boolValue == true)
        let shapeText = try Self.readText("Shape.swift", in: tempRoot)
        #expect(shapeText.contains("var side: Double"))
        #expect(!shapeText.contains("var side: Int"))
        try Self.writeText("one\ntwo\none\n", to: "patch.txt", in: tempRoot)
        let patched = try await Self.run("patch_application_engine", arguments: ["cwd": .string(cwd), "path": .string("patch.txt"), "original": .string("one"), "updated": .string("1")], client: client)
        #expect(patched["occurrences"]?.intValue == 2)
        #expect(try Self.readText("patch.txt", in: tempRoot) == "1\ntwo\n1\n")
        try Self.writeText("let a = 1\nlet b = 2\n", to: "fix.swift", in: tempRoot)
        let repaired = try await Self.run("automated_repair_engine", arguments: ["cwd": .string(cwd), "path": .string("fix.swift"), "errors": .array([.int(2)])], client: client)
        #expect(repaired["annotated"]?.intValue == 1)
        #expect(try Self.readText("fix.swift", in: tempRoot) == "let a = 1\n// AssistAutoRepair: review required\nlet b = 2\n")
        try Self.writeText("hello hello\n", to: "greet.txt", in: tempRoot)
        let replaced = try await Self.run("regex_replace_in_files", arguments: ["cwd": .string(cwd), "pattern": .string("hello"), "replacement": .string("hi")], client: client)
        #expect(replaced["changed"]?.intValue == 1)
        #expect(replaced["replacements"]?.intValue == 2)
        #expect(try Self.readText("greet.txt", in: tempRoot) == "hi hi\n")
        try Self.writeText("struct Old {\n    func useOld() { let o = Old() }\n}\n", to: "Old.swift", in: tempRoot)
        let renamed = try await Self.run("symbol_rename_project", arguments: ["cwd": .string(cwd), "oldName": .string("Old"), "newName": .string("New")], client: client)
        #expect(renamed["changed"]?.intValue == 1)
        #expect(renamed["replacements"]?.intValue == 2)
        let renamedText = try Self.readText("Old.swift", in: tempRoot)
        #expect(renamedText.contains("struct New"))
        #expect(renamedText.contains("let o = New()"))
        try Self.writeText("struct Keeper {\n    var a: Int\n}\n\nstruct Mover {\n    var b: Int\n}\n", to: "Source.swift", in: tempRoot)
        try Self.writeText("struct Existing {\n}\n", to: "Dest.swift", in: tempRoot)
        let moved = try await Self.run("symbol_move_file", arguments: ["cwd": .string(cwd), "sourcePath": .string("Source.swift"), "destinationPath": .string("Dest.swift"), "symbol": .string("Mover")], client: client)
        #expect(moved["moved"]?.boolValue == true)
        #expect(moved["lines"]?.intValue == 3)
        #expect(!try Self.readText("Source.swift", in: tempRoot).contains("struct Mover"))
        #expect(try Self.readText("Dest.swift", in: tempRoot).contains("struct Mover"))
        try Self.writeText("import Foundation\nimport MissingKit\n\nlet x = 1\n", to: "Cleanup.swift", in: tempRoot)
        let cleaned = try await Self.run("import_cleanup", arguments: ["cwd": .string(cwd), "path": .string("Cleanup.swift")], client: client)
        #expect(cleaned["count"]?.intValue == 1)
        #expect(cleaned["removed"]?.arrayValue?.compactMap { $0.stringValue } == ["MissingKit"])
        #expect(!try Self.readText("Cleanup.swift", in: tempRoot).contains("import MissingKit"))
        try Self.writeText("x", to: "old-a.txt", in: tempRoot)
        try Self.writeText("x", to: "old-b.txt", in: tempRoot)
        try Self.writeText("x", to: "keep.txt", in: tempRoot)
        let dryRun = try await Self.run("batch_rename_files", arguments: ["cwd": .string(cwd), "pattern": .string("old-"), "replacement": .string("new-"), "dryRun": .bool(true)], client: client)
        #expect(dryRun["dryRun"]?.boolValue == true)
        #expect(dryRun["count"]?.intValue == 2)
        #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("old-a.txt").path))
        let renamedFiles = try await Self.run("batch_rename_files", arguments: ["cwd": .string(cwd), "pattern": .string("old-"), "replacement": .string("new-")], client: client)
        #expect(renamedFiles["count"]?.intValue == 2)
        #expect(!FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("old-a.txt").path))
        #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("new-a.txt").path))
        #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("new-b.txt").path))
        await client.close()
    }

    @Test("Slice 11 docs, fixtures, snapshots, session export, and base64 round-trip")
    func sliceElevenDocsAndMiscRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("# Title\n\n## Section One\n\nText\n\n### Sub Part\n", to: "doc.md", in: tempRoot)
        let toc = try await Self.run("markdown_toc_generate", arguments: ["cwd": .string(cwd), "path": .string("doc.md")], client: client)
        #expect(toc["entries"]?.intValue == 3)
        let docText = try Self.readText("doc.md", in: tempRoot)
        #expect(docText.contains("- [Title](#title)"))
        #expect(docText.contains("    - [Sub Part](#sub-part)"))
        try Self.writeText("one", to: "first.txt", in: tempRoot)
        try Self.writeText("two", to: "second.txt", in: tempRoot)
        let readme = try await Self.run("readme_generate", arguments: ["cwd": .string(cwd)], client: client)
        #expect(readme["entries"]?.intValue == 3)
        let readmeText = try Self.readText("README.md", in: tempRoot)
        #expect(readmeText.hasPrefix("# toolset-"))
        #expect(readmeText.contains("- doc.md"))
        try Self.writeText("public struct Api {\n    public func call() {}\n}\n", to: "Api.swift", in: tempRoot)
        let docs = try await Self.run("docs_generate", arguments: ["cwd": .string(cwd)], client: client)
        #expect(docs["files"]?.intValue == 1)
        #expect(docs["symbols"]?.intValue == 2)
        let docsText = try Self.readText("API.md", in: tempRoot)
        #expect(docsText.contains("- `struct Api` (line 1)"))
        #expect(docsText.contains("- `func call` (line 2)"))
        let factoryJson = try await Self.run("test_data_factory", arguments: ["cwd": .string(cwd), "path": .string("fixture.json"), "format": .string("json"), "fields": .string("name:String,age:Int")], client: client)
        #expect(factoryJson["fields"]?.intValue == 2)
        let fixtureJson = try Self.readText("fixture.json", in: tempRoot)
        #expect(fixtureJson.contains("\"name\": \"Example\""))
        #expect(fixtureJson.contains("\"age\": 1"))
        let factorySwift = try await Self.run("test_data_factory", arguments: ["cwd": .string(cwd), "path": .string("Fixture.swift"), "format": .string("swift"), "fields": .string("name:String,age:Int")], client: client)
        #expect(factorySwift["format"]?.stringValue == "swift")
        let fixtureSwift = try Self.readText("Fixture.swift", in: tempRoot)
        #expect(fixtureSwift.contains("public struct Fixture"))
        #expect(fixtureSwift.contains("public static let sample = Fixture()"))
        let scaffold = try await Self.run("ui_test_scaffold", arguments: ["cwd": .string(cwd), "path": .string("UITests.swift"), "appName": .string("Demo App")], client: client)
        #expect(scaffold["appName"]?.stringValue == "Demo App")
        #expect(try Self.readText("UITests.swift", in: tempRoot).contains("final class DemoAppUITests: XCTestCase"))
        try Self.writeText("snapshot one", to: "__Snapshots__/First.txt", in: tempRoot)
        try Self.writeText("snapshot two", to: "__Snapshots__/Second.txt", in: tempRoot)
        let snapshots = try await Self.run("test_snapshot_manage", arguments: ["cwd": .string(cwd)], client: client)
        #expect(snapshots["count"]?.intValue == 2)
        let refs = snapshots["refs"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        #expect(refs.contains("__Snapshots__/First.txt"))
        #expect(refs.contains("__Snapshots__/Second.txt"))
        do {
            _ = try await Self.run("test_snapshot_manage", arguments: ["cwd": .string(cwd), "action": .string("clean")], client: client)
            Issue.record("Expected missingArgument for test_snapshot_manage clean without confirm")
        } catch let error as SystemToolError {
            #expect(error == .missingArgument(tool: "test_snapshot_manage", argument: "confirm"))
        } catch {
            Issue.record("Unexpected error for test_snapshot_manage clean without confirm: \(error)")
        }
        try Self.writeText("struct Ref {\n    let value = First()\n}\n", to: "Ref.swift", in: tempRoot)
        let cleaned = try await Self.run("test_snapshot_manage", arguments: ["cwd": .string(cwd), "action": .string("clean"), "confirm": .bool(true)], client: client)
        #expect(cleaned["count"]?.intValue == 1)
        #expect(cleaned["kept"]?.intValue == 1)
        #expect(cleaned["deleted"]?.arrayValue?.compactMap { $0.stringValue } == ["__Snapshots__/Second.txt"])
        #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("__Snapshots__/First.txt").path))
        #expect(!FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("__Snapshots__/Second.txt").path))
        let exported = try await Self.run("session_export", arguments: ["cwd": .string(cwd), "title": .string("Test Session"), "sessionId": .string("s1")], client: client)
        #expect(exported["path"]?.stringValue == ".assist_temp/session-export-s1.md")
        #expect(exported["sessionId"]?.stringValue == "s1")
        #expect(try Self.readText(".assist_temp/session-export-s1.md", in: tempRoot).contains("# Test Session"))
        try Self.writeData(Data([0, 1, 2, 255]), to: "pic.bin", in: tempRoot)
        let encoded = try await Self.run("image_encode_base64", arguments: ["cwd": .string(cwd), "path": .string("pic.bin")], client: client)
        #expect(encoded["base64"]?.stringValue == "AAEC/w==")
        #expect(encoded["byteLen"]?.intValue == 4)
        let decoded = try await Self.run("image_decode_base64", arguments: ["cwd": .string(cwd), "path": .string("copy.bin"), "base64": .string("AAEC/w==")], client: client)
        #expect(decoded["byteLen"]?.intValue == 4)
        #expect(try Data(contentsOf: tempRoot.appendingPathComponent("copy.bin")) == Data([0, 1, 2, 255]))
        let logs = try await Self.run("env_capture_logs", arguments: [:], client: client)
        if case .object = logs {
        } else {
            Issue.record("Expected env_capture_logs to return a snapshot object")
        }
        await client.close()
    }

    @Test("Slice 11 terminal and Finder tools refuse missing arguments before any runtime call")
    func sliceElevenTerminalToolsRefuseMissingArguments() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cases: [(String, [String: JSONValue], String)] = [
            ("swift_format_lint", [:], "threadId"),
            ("image_get_dimensions", [:], "threadId"),
            ("image_convert_format", [:], "threadId"),
            ("image_generate_thumbnail", [:], "threadId"),
            ("image_extract_metadata", [:], "threadId"),
            ("zip_file", [:], "threadId"),
            ("unzip_file", [:], "threadId"),
            ("tar_archive_create", [:], "threadId"),
            ("tar_archive_extract", [:], "threadId"),
            ("gzip_compress_file", [:], "threadId"),
            ("gzip_decompress_file", [:], "threadId"),
            ("open_in_finder", [:], "cwd"),
            ("reveal_in_finder", [:], "cwd"),
        ]
        for (tool, arguments, missing) in cases {
            do {
                _ = try await Self.run(tool, arguments: arguments, client: client)
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: missing))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        do {
            _ = try await Self.run("image_convert_format", arguments: ["threadId": .string("t"), "cwd": .string("/tmp"), "path": .string("a.png"), "format": .string("webp")], client: client)
            Issue.record("Expected executionFailed for an unsupported image format")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "image_convert_format", message: "Image format must be png, jpg, tiff, bmp, or gif."))
        } catch {
            Issue.record("Unexpected error for image_convert_format: \(error)")
        }
        do {
            _ = try await Self.run("swift_format_lint", arguments: ["threadId": .string("t"), "cwd": .string("/tmp"), "path": .string("a.swift"), "mode": .string("bogus")], client: client)
            Issue.record("Expected executionFailed for a bogus swift_format_lint mode")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "swift_format_lint", message: "swift_format_lint mode must be lint or format."))
        } catch {
            Issue.record("Unexpected error for swift_format_lint: \(error)")
        }
        await client.close()
    }
    @Test("Slice 12 tools register with their real backend actions")
    func sliceTwelveToolsRegister() {
        let expected: [(String, String, SystemToolChannel)] = [
            ("project_build", "terminal.create", .engine),
            ("project_test", "terminal.create", .engine),
            ("compiler_diagnostics_engine", "terminal.create", .engine),
            ("dependency_resolution_engine", "terminal.create", .engine),
            ("generate_xcodeproj", "terminal.create", .engine),
            ("project_scheme_list", "terminal.create", .engine),
            ("project_target_list", "terminal.create", .engine),
            ("project_build_settings", "terminal.create", .engine),
            ("project_clean", "terminal.create", .engine),
            ("project_archive", "terminal.create", .engine),
            ("test_run_single", "terminal.create", .engine),
            ("test_coverage_report", "terminal.create", .engine),
            ("test_coverage_reporter", "terminal.create", .engine),
            ("performance_benchmark", "terminal.create", .engine),
            ("docc_build", "terminal.create", .engine),
            ("xcode_scheme_manager", "terminal.create", .engine),
            ("xcode_build_settings_inspector", "terminal.create", .engine),
            ("xcode_device_destination_finder", "terminal.create", .engine),
            ("simulator_list", "terminal.create", .engine),
            ("simulator_boot", "terminal.create", .engine),
            ("simulator_controller", "terminal.create", .engine),
            ("device_list", "terminal.create", .engine),
            ("provisioning_check", "terminal.create", .engine),
            ("swift_package_manager", "terminal.create", .engine),
            ("package_dependency_update", "terminal.create", .engine),
            ("code_signing_diagnose", "terminal.create", .engine),
            ("xcode_toolchain_info", "terminal.create", .engine),
            ("xcresult_parser", "terminal.create", .engine),
            ("mach_o_binary_analyzer", "terminal.create", .engine),
            ("signing_certificate_inspector", "terminal.create", .engine),
            ("provisioning_profile_reader", "terminal.create", .engine),
            ("swift_ast_inspector", "terminal.create", .engine),
            ("binary_size_report", "terminal.create", .engine),
            ("git_review_diff", "git.review.diff", .engine),
        ]
        #expect(expected.count == 34)
        for (name, action, channel) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == channel)
            #expect(definition.parameters.contains { $0.required })
            #expect(definition.parameters.first?.name == "threadId")
        }
        #expect(SystemToolRegistry.definition(named: "project_archive", for: .system)?.parameters.map(\.name) == ["threadId", "scheme", "archivePath", "configuration", "destination", "timeoutSeconds"])
        #expect(SystemToolRegistry.definition(named: "performance_benchmark", for: .system)?.parameters.map(\.name) == ["threadId", "benchmark", "scheme", "timeoutSeconds"])
        #expect(SystemToolRegistry.definition(named: "git_review_diff", for: .system)?.parameters.map(\.name) == ["threadId", "scope", "ignoreWhitespace"])
        #expect(SystemToolRegistry.definition(named: "project_build_settings", for: .system)?.parameters.map(\.name).contains("target") == true)
        #expect(SystemToolRegistry.definition(named: "project_clean", for: .system)?.parameters.map(\.name).contains("confirm") == true)
        #expect(SystemToolRegistry.definition(named: "binary_size_report", for: .system)?.parameters.map(\.name).contains("top") == true)
    }

    @Test("Slice 12 parsers read real CLI output shapes")
    func sliceTwelveParsersParseRealCLIOutput() throws {
        let diagnostics = SystemToolRegistry.parseG3Diagnostics("/Users/dylan/Projects/MyApp/Sources/App.swift:12:7: error: cannot find 'missing' in scope\n/Users/dylan/Projects/MyApp/Sources/App.swift:20:3: warning: variable 'x' was never used\n/Users/dylan/Projects/MyApp/Sources/App.swift:33:1: note: did you mean 'other'?\nerror: unable to load standard library for target 'arm64-apple-macosx14.0'\n** BUILD FAILED **\n")
        #expect(diagnostics.count == 4)
        #expect(diagnostics[0]["path"]?.stringValue == "/Users/dylan/Projects/MyApp/Sources/App.swift")
        #expect(diagnostics[0]["line"]?.intValue == 12)
        #expect(diagnostics[0]["column"]?.intValue == 7)
        #expect(diagnostics[0]["severity"]?.stringValue == "error")
        #expect(diagnostics[0]["message"]?.stringValue == "cannot find 'missing' in scope")
        #expect(diagnostics[1]["severity"]?.stringValue == "warning")
        #expect(diagnostics[1]["line"]?.intValue == 20)
        #expect(diagnostics[2]["severity"]?.stringValue == "note")
        #expect(diagnostics[3]["path"]?.stringValue == "")
        #expect(diagnostics[3]["message"]?.stringValue == "unable to load standard library for target 'arm64-apple-macosx14.0'")

        let summary = SystemToolRegistry.parseG3TestSummary("Test Suite 'MyAppTests' started at 2026-11-18 00:00:00.000\nTest Suite 'MyAppTests' passed at 2026-11-18 00:00:01.234.\n\t Executed 42 tests, with 0 failures (0 unexpected) in 1.234 (1.567) seconds\nTest Suite 'OtherTests' failed at 2026-11-18 00:00:02.000.\n\t Executed 3 tests, with 2 failures (1 unexpected) in 0.500 (0.600) seconds\n")
        #expect(summary.executed == 45)
        #expect(summary.failed == 2)
        #expect(summary.suitesPassed == 1)
        #expect(summary.suitesFailed == 1)

        let settings = SystemToolRegistry.parseG3BuildSettings("Build settings for action build and target \"MyApp\":\n    PRODUCT_NAME = MyApp\n    SWIFT_VERSION = 5.0\n    OTHER_LDFLAGS = (\n        \"-framework\",\n        \"Foundation\",\n    )\nBuild settings for action build and target \"MyAppTests\":\n    PRODUCT_NAME = MyAppTests\n")
        #expect(settings.count == 2)
        #expect(settings[0]["target"]?.stringValue == "MyApp")
        #expect(settings[0]["settings"]?.objectValue?["PRODUCT_NAME"]?.stringValue == "MyApp")
        #expect(settings[0]["settings"]?.objectValue?["SWIFT_VERSION"]?.stringValue == "5.0")
        #expect(settings[0]["settings"]?.objectValue?["OTHER_LDFLAGS"]?.stringValue?.contains("-framework") == true)
        #expect(settings[1]["target"]?.stringValue == "MyAppTests")

        let listJSON = try JSONDecoder().decode(JSONValue.self, from: Data("{\"project\" : {\"configurations\" : [\"Debug\", \"Release\"], \"name\" : \"MyApp\", \"schemes\" : [\"MyApp\"], \"targets\" : [\"MyApp\", \"MyAppTests\"]}}".utf8))
        let (schemes, targets, configurations, projectName) = SystemToolRegistry.parseG3XcodebuildList(listJSON)
        #expect(projectName == "MyApp")
        #expect(schemes == ["MyApp"])
        #expect(targets == ["MyApp", "MyAppTests"])
        #expect(configurations == ["Debug", "Release"])
        let emptyList = SystemToolRegistry.parseG3XcodebuildList(.object([:]))
        #expect(emptyList.schemes.isEmpty)
        #expect(emptyList.name.isEmpty)

        let simctlJSON = try JSONDecoder().decode(JSONValue.self, from: Data("{\"devices\" : {\"com.apple.CoreSimulator.SimRuntime.iOS-18-0\" : [{\"udid\" : \"A1B2C3D4-1111-2222-3333-444455556666\", \"name\" : \"iPhone 16\", \"state\" : \"Shutdown\", \"isAvailable\" : true, \"deviceTypeIdentifier\" : \"com.apple.CoreSimulator.SimDeviceType.iPhone-16\"}], \"com.apple.CoreSimulator.SimRuntime.iOS-17-5\" : []}}".utf8))
        let devices = SystemToolRegistry.parseG3SimctlDevices(simctlJSON)
        #expect(devices.count == 1)
        #expect(devices[0]["udid"]?.stringValue == "A1B2C3D4-1111-2222-3333-444455556666")
        #expect(devices[0]["name"]?.stringValue == "iPhone 16")
        #expect(devices[0]["state"]?.stringValue == "Shutdown")
        #expect(devices[0]["runtime"]?.stringValue == "com.apple.CoreSimulator.SimRuntime.iOS-18-0")
        #expect(devices[0]["isAvailable"]?.boolValue == true)

        let destinations = SystemToolRegistry.parseG3Destinations("{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:00008110-001234567890, name:My Mac }\n{ platform:iOS Simulator, id:A1B2C3D4-1111-2222-3333-444455556666, name:iPhone 16, OS:18.0 }\n")
        #expect(destinations.count == 2)
        #expect(destinations[0]["platform"]?.stringValue == "macOS")
        #expect(destinations[0]["variant"]?.stringValue == "Designed for [iPad,iPhone]")
        #expect(destinations[0]["name"]?.stringValue == "My Mac")
        #expect(destinations[1]["OS"]?.stringValue == "18.0")

        let codesign = SystemToolRegistry.parseG3Codesign("Identifier=com.example.app\nFormat=app bundle with Mach-O thin (arm64)\nCodeDirectory v=20400 size=12345 flags=0x0(none) hashes=10+7 location=embedded\nSignature size=1234\nAuthority=Apple Development: Jane Appleseed (ABCDE12345)\nAuthority=Apple Worldwide Developer Relations Certification Authority\nAuthority=Apple Root CA\nTeamIdentifier=ABCDE12345\n")
        #expect(codesign["Identifier"]?.stringValue == "com.example.app")
        #expect(codesign["TeamIdentifier"]?.stringValue == "ABCDE12345")
        #expect(codesign["Authority"]?.arrayValue?.count == 3)
        #expect(codesign["Authority"]?.arrayValue?.first?.stringValue == "Apple Development: Jane Appleseed (ABCDE12345)")

        let identities = SystemToolRegistry.parseG3Identities("  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 \"Apple Development: Jane Appleseed (ABCDE12345)\"\n  2) 1234567890ABCDEF1234567890ABCDEF12345678 \"Apple Distribution: Example Inc (FGHIJ67890)\"\n     2 valid identities found\n")
        #expect(identities.count == 2)
        #expect(identities[0]["index"]?.intValue == 1)
        #expect(identities[0]["hash"]?.stringValue == "ABCDEF1234567890ABCDEF1234567890ABCDEF12")
        #expect(identities[0]["name"]?.stringValue == "Apple Development: Jane Appleseed (ABCDE12345)")

        let libraries = SystemToolRegistry.parseG3OtoolLibraries("/path/to/MyApp:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1351.0.0)\n\t/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 2500.0.0)\n")
        #expect(libraries == ["/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"])

        let headers = SystemToolRegistry.parseG3MachHeader("Mach header\n      magic cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags\n 0xfeedfacf 16777228          2 0x00           2    24       2288 0x00200085\n")
        #expect(headers.count == 1)
        #expect(headers[0]["magic"]?.stringValue == "0xfeedfacf")
        #expect(headers[0]["cputype"]?.stringValue == "16777228")
        #expect(headers[0]["filetype"]?.stringValue == "2")

        let (version, build) = SystemToolRegistry.parseG3XcodeVersion("Xcode 16.2\nBuild version 16C5032a\n")
        #expect(version == "16.2")
        #expect(build == "16C5032a")

        let counts = SystemToolRegistry.parseG3ASTDeclCounts("(source_file \"Sources/App.swift\"\n  (func_decl range=[Sources/App.swift:1:1 - line:1:1] \"run()\" type='() -> ()')\n  (struct_decl range=[Sources/App.swift:5:1 - line:5:1] \"Widget\")\n  (var_decl range=[Sources/App.swift:9:3 - line:9:3] \"count\")\n  (import_decl range=[Sources/App.swift:0:1 - line:0:1]))\n")
        #expect(counts["func_decl"] == 1)
        #expect(counts["struct_decl"] == 1)
        #expect(counts["var_decl"] == 1)
        #expect(counts["import_decl"] == 1)
        #expect(counts["total"] == 4)

        let sizes = SystemToolRegistry.parseG3DuSizes("16\tbuild/MyApp.app/Contents/MacOS/MyApp\n8\tbuild/MyApp.app/Contents/Info.plist\n4\tbuild\n")
        #expect(sizes.count == 3)
        #expect(sizes[0].path == "build/MyApp.app/Contents/MacOS/MyApp")
        #expect(sizes[0].kilobytes == 16)
        #expect(sizes[2].kilobytes == 4)

        let coverageJSON = try JSONDecoder().decode(JSONValue.self, from: Data("{\"lineCoverage\" : 0.85, \"targets\" : [{\"name\" : \"MyApp.app\", \"lineCoverage\" : 0.9, \"coveredLines\" : 90, \"executableLines\" : 100}, {\"name\" : \"MyAppTests.xctest\"}]}".utf8))
        let coverage = SystemToolRegistry.parseG3Coverage(coverageJSON)
        #expect(coverage.count == 2)
        #expect(coverage[0]["name"]?.stringValue == "MyApp.app")
        #expect(coverage[0]["lineCoverage"]?.doubleValue == 0.9)
        #expect(coverage[0]["coveredLines"]?.intValue == 90)
        #expect(coverage[0]["executableLines"]?.intValue == 100)
        #expect(coverage[1]["name"]?.stringValue == "MyAppTests.xctest")
        #expect(coverage[1]["lineCoverage"] == nil)
        #expect(coverageJSON["lineCoverage"]?.doubleValue == 0.85)
    }

    @Test("Slice 12 tools refuse missing arguments and invalid values before any runtime call")
    func sliceTwelveValidationRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let missingThreadId: [String] = [
            "project_build", "project_test", "compiler_diagnostics_engine",
            "dependency_resolution_engine", "generate_xcodeproj", "project_scheme_list",
            "project_target_list", "project_build_settings", "project_archive",
            "test_run_single", "test_coverage_report", "test_coverage_reporter",
            "performance_benchmark", "docc_build", "xcode_scheme_manager",
            "xcode_build_settings_inspector", "xcode_device_destination_finder",
            "simulator_list", "simulator_boot", "simulator_controller", "device_list",
            "provisioning_check", "swift_package_manager", "package_dependency_update",
            "code_signing_diagnose", "xcode_toolchain_info", "xcresult_parser",
            "mach_o_binary_analyzer", "signing_certificate_inspector",
            "provisioning_profile_reader", "swift_ast_inspector", "binary_size_report",
            "git_review_diff",
        ]
        for tool in missingThreadId {
            do {
                _ = try await Self.run(tool, arguments: [:], client: client)
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: "threadId"))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        let invalid: [(String, [String: JSONValue], SystemToolError)] = [
            ("performance_benchmark", ["threadId": .string("t"), "benchmark": .string("rm -rf /")], .executionFailed(tool: "performance_benchmark", message: "performance_benchmark benchmark must be xcodebuild-build, xcodebuild-test, swift-build, swift-test, or xcodebuild-clean-build.")),
            ("compiler_diagnostics_engine", ["threadId": .string("t"), "kind": .string("bogus")], .executionFailed(tool: "compiler_diagnostics_engine", message: "compiler_diagnostics_engine kind must be xcodebuild or swiftpm.")),
            ("dependency_resolution_engine", ["threadId": .string("t"), "kind": .string("bogus")], .executionFailed(tool: "dependency_resolution_engine", message: "dependency_resolution_engine kind must be swiftpm or xcode.")),
            ("swift_package_manager", ["threadId": .string("t"), "action": .string("bogus")], .executionFailed(tool: "swift_package_manager", message: "swift_package_manager action must be describe, resolve, clean, or reset.")),
            ("xcode_scheme_manager", ["threadId": .string("t"), "action": .string("bogus")], .executionFailed(tool: "xcode_scheme_manager", message: "xcode_scheme_manager action must be list or validate.")),
            ("simulator_controller", ["threadId": .string("t"), "action": .string("bogus"), "device": .string("iPhone 16")], .executionFailed(tool: "simulator_controller", message: "simulator_controller action must be boot, shutdown, erase, openurl, or status.")),
            ("test_coverage_reporter", ["threadId": .string("t"), "xcresultPath": .string("a.xcresult"), "format": .string("bogus")], .executionFailed(tool: "test_coverage_reporter", message: "test_coverage_reporter format must be json or text.")),
            ("git_review_diff", ["threadId": .string("t"), "scope": .string("bogus")], .executionFailed(tool: "git_review_diff", message: "git_review_diff scope must be uncommitted or branch.")),
            ("test_run_single", ["threadId": .string("t"), "testIdentifier": .string("Target//test")], .executionFailed(tool: "test_run_single", message: "testIdentifier must be a slash-separated test path using letters, digits, underscore, dot, dash, or slash.")),
            ("project_archive", ["threadId": .string("t"), "scheme": .string("MyApp"), "archivePath": .string("/tmp/abs.xcarchive")], .executionFailed(tool: "project_archive", message: "Path must be relative to the working directory.")),
        ]
        for (tool, arguments, expected) in invalid {
            do {
                _ = try await Self.run(tool, arguments: arguments, client: client)
                Issue.record("Expected validation error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == expected)
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        do {
            _ = try await Self.run("project_clean", arguments: ["threadId": .string("t")], client: client)
            Issue.record("Expected missingArgument error for project_clean without confirm")
        } catch let error as SystemToolError {
            #expect(error == .missingArgument(tool: "project_clean", argument: "confirm"))
        } catch {
            Issue.record("Unexpected error for project_clean: \(error)")
        }
        do {
            _ = try await Self.run("project_clean", arguments: ["threadId": .string("t"), "confirm": .bool(false)], client: client)
            Issue.record("Expected executionFailed error for project_clean with confirm=false")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "project_clean", message: "project_clean removes build products; pass confirm=true."))
        } catch {
            Issue.record("Unexpected error for project_clean: \(error)")
        }
        await client.close()
    }

    @Test("RemoteCheckoutAction useExistingWorktree round-trips through Codable")
    func useExistingWorktreeActionRoundTrips() throws {
        let action = RemoteCheckoutAction.useExistingWorktree(path: "/tmp/worktrees/app-feature", branch: "feature")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RemoteCheckoutAction.self, from: data)
        #expect(decoded == action)
        let previous = try JSONDecoder().decode(RemoteCheckoutAction.self, from: Data("{\"type\":\"usePreviousWorktree\"}".utf8))
        #expect(previous == .usePreviousWorktree)
        let local = try JSONDecoder().decode(RemoteCheckoutAction.self, from: Data("{\"type\":\"useExistingWorktree\",\"path\":\"/tmp/wt\",\"branch\":null}".utf8))
        #expect(local == .useExistingWorktree(path: "/tmp/wt", branch: nil))
    }


    @Test("Slice 13 tools register with their real backend actions")
    func sliceThirteenToolsRegister() {
        let expected: [(String, String, SystemToolChannel)] = [
            ("search_symbol", "workspace.search_regex", .desktop),
            ("dependency_graph", "workspace.search_regex", .desktop),
            ("source_graph_builder", "workspace.search_regex", .desktop),
            ("semantic_query_engine", "workspace.search", .desktop),
            ("code_summary", "workspace.read_file", .desktop),
            ("code_lint", "workspace.read_file", .desktop),
            ("complexity_analysis", "workspace.read_file", .desktop),
            ("autonomous_review_engine", "workspace.search_regex", .desktop),
            ("runtime_diagnostics_engine", "workspace.read_file", .desktop),
            ("code_metrics_analyzer", "workspace.read_file", .desktop),
            ("memory_leak_detector", "workspace.search_regex", .desktop),
            ("dead_code_eliminator", "workspace.read_file", .desktop),
            ("dead_code_scan", "workspace.read_file", .desktop),
            ("duplicate_code_scan", "workspace.read_file", .desktop),
            ("todo_scan", "workspace.search_regex", .desktop),
            ("todo_fixme_scanner", "workspace.search_regex", .desktop),
            ("license_header_check", "workspace.read_file", .desktop),
            ("api_surface_extract", "workspace.search_regex", .desktop),
            ("access_level_audit", "workspace.search_regex", .desktop),
            ("concurrency_audit", "workspace.search_regex", .desktop),
            ("swift_concurrency_analyzer", "workspace.search_regex", .desktop),
            ("swift_migration_advisor", "workspace.search_regex", .desktop),
            ("security_audit_scanner", "workspace.search_regex", .desktop),
            ("secrets_scan", "workspace.search_regex", .desktop),
            ("network_security_auditor", "workspace.search_regex", .desktop),
            ("permissions_audit", "workspace.search_regex", .desktop),
            ("accessibility_audit", "workspace.search_regex", .desktop),
            ("accessibility_audit_scanner", "workspace.search_regex", .desktop),
            ("interface_simulator", "workspace.search_regex", .desktop),
            ("docstring_generator", "workspace.read_file", .desktop),
            ("code_snippet_manager", "workspace.write_file", .desktop),
            ("unused_imports_detector", "workspace.read_file", .desktop),
            ("force_unwrap_scan", "workspace.search_regex", .desktop),
            ("string_literal_audit", "workspace.search_regex", .desktop),
            ("comment_density_report", "workspace.read_file", .desktop),
            ("function_size_report", "workspace.read_file", .desktop),
            ("call_hierarchy", "workspace.search_regex", .desktop),
            ("type_hierarchy", "workspace.search_regex", .desktop),
            ("protocol_conformance_list", "workspace.search_regex", .desktop),
            ("import_graph", "workspace.search_regex", .desktop),
            ("change_impact_estimate", "workspace.search_regex", .desktop),
            ("conflict_marker_scan", "workspace.search_regex", .desktop),
            ("build_log_analyze", "workspace.read_file", .desktop),
            ("crash_log_parse", "workspace.read_file", .desktop),
            ("deprecation_usage_scan", "workspace.search_regex", .desktop),
            ("info_plist_audit", "workspace.read_file", .desktop),
            ("api_endpoint_audit", "workspace.search_regex", .desktop),
            ("color_usage_audit", "workspace.search_regex", .desktop),
            ("strings_file_validate", "workspace.read_file", .desktop),
            ("entitlements_diff", "workspace.read_file", .desktop),
            ("pbxproj_lint", "workspace.read_file", .desktop),
            ("xctest_discovery", "workspace.search_regex", .desktop),
            ("build_settings_diff", "workspace.read_file", .desktop),
            ("build_phase_scripts_list", "workspace.read_file", .desktop),
            ("build_configuration_list", "workspace.read_file", .desktop),
            ("target_dependencies_list", "workspace.read_file", .desktop),
            ("target_source_list", "workspace.read_file", .desktop),
            ("workspace_settings_read", "workspace.read_file", .desktop),
            ("scheme_test_plan_list", "workspace.read_file", .desktop),
            ("test_log_parse", "workspace.read_file", .desktop),
            ("test_flaky_detect", "workspace.read_file", .desktop),
            ("code_comment_extract", "workspace.search_regex", .desktop),
            ("api_docs_coverage", "workspace.read_file", .desktop),
            ("markdown_link_check", "workspace.read_file", .desktop),
            ("docs_index_build", "workspace.files", .desktop),
        ]
        #expect(expected.count == 65)
        for (name, action, channel) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Missing system tool \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == channel)
            #expect(definition.parameters.contains { $0.required })
            #expect(definition.parameters.first?.name == "cwd")
            #expect(definition.parameters.first?.required == true)
        }
        #expect(SystemToolRegistry.definition(named: "search_symbol", for: .system)?.parameters.map(\.name) == ["cwd", "symbol", "path", "limit"])
        #expect(SystemToolRegistry.definition(named: "entitlements_diff", for: .system)?.parameters.map(\.name) == ["cwd", "path", "otherPath"])
        #expect(SystemToolRegistry.definition(named: "code_snippet_manager", for: .system)?.parameters.map(\.name) == ["cwd", "template", "path"])
        #expect(SystemToolRegistry.definition(named: "runtime_diagnostics_engine", for: .system)?.parameters.map(\.name) == ["cwd", "logPath"])
        #expect(SystemToolRegistry.definition(named: "dead_code_eliminator", for: .system)?.description.contains("Report-only") == true)
        #expect(SystemToolRegistry.definition(named: "pbxproj_lint", for: .system)?.description.contains("Never writes") == true)
    }

    @Test("Slice 13 regex scans round-trip through the real workspace")
    func sliceThirteenScansRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        let store = """
        import Foundation
        import SwiftUI
        import FakeyKit

        // TODO: migrate this store
        public struct Store {
            public var title: String
            public func load() {
                let value = optionalValue!.description
                let forced = try! loadData()
                let casted = value as! String
                let color = Color(red: 1, green: 0, blue: 0)
                let url = "https://api.example.com/v1/items"
                Task {
                    DispatchQueue.main.sync {
                        print("sync")
                    }
                }
            }
            private func helper() {
            }
            func unusedHelper() {
            }
            @available(*, deprecated, message: "Use something else.")
            func bigFunction() {
                if true {
                    if true {
                        print("nested")
                    }
                }
                print("a")
                print("b")
                print("c")
                print("d")
                print("e")
                print("f")
                print("g")
            }
        }
        """
        try Self.writeText(store, to: "Sources/Store.swift", in: tempRoot)
        try Self.writeText("let apiKey = \"AKIAIOSFODNN7EXAMPLE\"\n", to: "Sources/Secrets.swift", in: tempRoot)
        try Self.writeText("<<<<<<< HEAD\nlet conflicted = 1\n", to: "Sources/Conflict.swift", in: tempRoot)
        let duplicateBlock = """
        func duplicated() {
            print("alpha")
            print("beta")
            print("gamma")
            print("delta")
            print("epsilon")
            print("zeta")
        }
        """
        try Self.writeText("import Foundation\n" + duplicateBlock, to: "Sources/DupA.swift", in: tempRoot)
        try Self.writeText(duplicateBlock, to: "Sources/DupB.swift", in: tempRoot)
        try Self.writeText("import XCTest\nclass StoreTests: XCTestCase {\n    func testExample() {\n    }\n}\n", to: "Tests/StoreTests.swift", in: tempRoot)

        let todo = try await Self.run("todo_scan", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(todo["matchCount"]?.intValue == 1)
        #expect(todo["groups"]?.arrayValue?.first?["matches"]?.arrayValue?.first?["path"]?.stringValue == "Sources/Store.swift")
        let todoFixme = try await Self.run("todo_fixme_scanner", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(todoFixme["matchCount"]?.intValue == 1)
        let unwraps = try await Self.run("force_unwrap_scan", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(unwraps["matchCount"]?.intValue == 5)
        #expect(unwraps["groups"]?.arrayValue?.first?["count"]?.intValue == 3)
        let conflicts = try await Self.run("conflict_marker_scan", arguments: ["cwd": .string(cwd), "path": .string("Sources/Conflict.swift")], client: client)
        #expect(conflicts["matchCount"]?.intValue == 1)
        let secrets = try await Self.run("secrets_scan", arguments: ["cwd": .string(cwd), "path": .string("Sources/Secrets.swift")], client: client)
        #expect(secrets["matchCount"]?.intValue == 1)
        #expect(secrets["groups"]?.arrayValue?.first?["matches"]?.arrayValue?.first?["lineText"] == nil)
        #expect(secrets["groups"]?.arrayValue?.first?["label"]?.stringValue == "awsKey")
        let symbol = try await Self.run("search_symbol", arguments: ["cwd": .string(cwd), "symbol": .string("Store")], client: client)
        #expect(symbol["matchCount"]?.intValue == 1)
        #expect(symbol["groups"]?.arrayValue?.map { $0["label"]?.stringValue ?? "" } == ["function", "type", "variable", "typealias"])
        let hierarchy = try await Self.run("call_hierarchy", arguments: ["cwd": .string(cwd), "function": .string("load")], client: client)
        #expect(hierarchy["groups"]?.arrayValue?.first?["count"]?.intValue == 1)
        #expect(hierarchy["groups"]?.arrayValue?.last?["count"]?.intValue == 1)
        let impact = try await Self.run("change_impact_estimate", arguments: ["cwd": .string(cwd), "symbol": .string("Store")], client: client)
        #expect(impact["matchCount"]?.intValue == 1)
        let semantic = try await Self.run("semantic_query_engine", arguments: ["cwd": .string(cwd), "query": .string("migrate")], client: client)
        #expect(semantic["matchCount"]?.intValue == 1)
        let graph = try await Self.run("dependency_graph", arguments: ["cwd": .string(cwd), "path": .string("Sources")], client: client)
        #expect(graph["groups"]?.arrayValue?.first?["files"]?.arrayValue?.count == 2)
        let imports = try await Self.run("import_graph", arguments: ["cwd": .string(cwd), "module": .string("SwiftUI")], client: client)
        #expect(imports["groups"]?.arrayValue?.first?["files"]?.arrayValue?.count == 1)
        let types = try await Self.run("type_hierarchy", arguments: ["cwd": .string(cwd)], client: client)
        #expect(types["groups"]?.arrayValue?.first?["values"]?.arrayValue?.compactMap { $0.stringValue }.sorted() == ["Store", "StoreTests"])
        let tests = try await Self.run("xctest_discovery", arguments: ["cwd": .string(cwd)], client: client)
        #expect(tests["groups"]?.arrayValue?.first?["count"]?.intValue == 1)
        #expect(tests["groups"]?.arrayValue?.last?["count"]?.intValue == 1)
        let surface = try await Self.run("api_surface_extract", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(surface["groups"]?.arrayValue?.first?["files"]?.arrayValue?.first?["count"]?.intValue == 3)
        let access = try await Self.run("access_level_audit", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(access["groups"]?.arrayValue?.first?["count"]?.intValue == 3)
        #expect(access["groups"]?.arrayValue?[3]["count"]?.intValue == 1)
        let deprecated = try await Self.run("deprecation_usage_scan", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(deprecated["matchCount"]?.intValue == 1)
        let colors = try await Self.run("color_usage_audit", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(colors["matchCount"]?.intValue == 1)
        let endpoints = try await Self.run("api_endpoint_audit", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(endpoints["groups"]?.arrayValue?.first?["hosts"]?.arrayValue?.first?["label"]?.stringValue == "api.example.com")
        let strings = try await Self.run("string_literal_audit", arguments: ["cwd": .string(cwd), "path": .string("Sources")], client: client)
        #expect(strings["matchCount"]?.intValue == 3)
        let comments = try await Self.run("code_comment_extract", arguments: ["cwd": .string(cwd)], client: client)
        #expect(comments["matchCount"]?.intValue == 0)
        await client.close()
    }

    @Test("Slice 13 file parses round-trip through the real workspace")
    func sliceThirteenFileParsesRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        let store = """
        // Copyright 2026 Demo
        import Foundation
        import FakeyKit

        public struct Store {
            public var title: String
            public func load() {
                if true {
                    print("one")
                }
            }
            private func helper() {
            }
            func unusedHelper() {
            }
            func bigFunction() {
                if true {
                    if true {
                        print("nested")
                    }
                }
                print("a")
                print("b")
                print("c")
                print("d")
                print("e")
                print("f")
                print("g")
            }
        }
        """
        try Self.writeText(store, to: "Sources/Store.swift", in: tempRoot)
        let duplicateBlock = """
        func duplicated() {
            print("alpha")
            print("beta")
            print("gamma")
            print("delta")
            print("epsilon")
            print("zeta")
        }
        """
        try Self.writeText("import Foundation\n" + duplicateBlock, to: "Sources/DupA.swift", in: tempRoot)
        try Self.writeText(duplicateBlock, to: "Sources/DupB.swift", in: tempRoot)
        try Self.writeText("import XCTest\nclass StoreTests: XCTestCase {\n    func testExample() {\n    }\n}\n", to: "Tests/StoreTests.swift", in: tempRoot)

        let summary = try await Self.run("code_summary", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(summary["commentLines"]?.intValue == 1)
        #expect((summary["codeLines"]?.intValue ?? 0) + (summary["commentLines"]?.intValue ?? 0) + (summary["blankLines"]?.intValue ?? 0) == summary["lines"]?.intValue)
        let complexity = try await Self.run("complexity_analysis", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(complexity["complexityEstimate"]?.intValue == 4)
        let lint = try await Self.run("code_lint", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(lint["issueCount"]?.intValue == 0)
        let metrics = try await Self.run("code_metrics_analyzer", arguments: ["cwd": .string(cwd)], client: client)
        #expect(metrics["filesChecked"]?.intValue == 4)
        #expect(metrics["totals"]?["functions"]?.intValue == 7)
        #expect(metrics["totals"]?["types"]?.intValue == 2)
        let density = try await Self.run("comment_density_report", arguments: ["cwd": .string(cwd)], client: client)
        #expect(density["files"]?.arrayValue?.count == 4)
        #expect(density["files"]?.arrayValue?.first?["commentRatio"]?.doubleValue == 0)
        let sizes = try await Self.run("function_size_report", arguments: ["cwd": .string(cwd)], client: client)
        #expect(sizes["functions"]?.arrayValue?.first?["name"]?.stringValue == "bigFunction")
        #expect(sizes["functions"]?.arrayValue?.first?["lines"]?.intValue == 14)
        let dead = try await Self.run("dead_code_scan", arguments: ["cwd": .string(cwd)], client: client)
        #expect(dead["candidateCount"]?.intValue == 8)
        #expect(dead["candidates"]?.arrayValue?.compactMap { $0["name"]?.stringValue }.contains("unusedHelper") == true)
        let eliminator = try await Self.run("dead_code_eliminator", arguments: ["cwd": .string(cwd)], client: client)
        #expect(eliminator["candidateCount"]?.intValue == 1)
        #expect(eliminator["candidates"]?.arrayValue?.first?["name"]?.stringValue == "helper")
        #expect(eliminator["reportOnly"]?.boolValue == true)
        let duplicates = try await Self.run("duplicate_code_scan", arguments: ["cwd": .string(cwd)], client: client)
        #expect(duplicates["blockCount"]?.intValue == 1)
        #expect(duplicates["blocks"]?.arrayValue?.first?["occurrences"]?.arrayValue?.count == 2)
        let unused = try await Self.run("unused_imports_detector", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift")], client: client)
        #expect(unused["unused"]?.arrayValue?.compactMap { $0["module"]?.stringValue } == ["FakeyKit"])
        let license = try await Self.run("license_header_check", arguments: ["cwd": .string(cwd)], client: client)
        #expect(license["missingCount"]?.intValue == 3)
        let coverage = try await Self.run("api_docs_coverage", arguments: ["cwd": .string(cwd)], client: client)
        #expect(coverage["declarations"]?.intValue == 3)
        #expect(coverage["documented"]?.intValue == 0)
        #expect(coverage["coverage"]?.doubleValue == 0)
        let docs = try await Self.run("docstring_generator", arguments: ["cwd": .string(cwd), "path": .string("Sources/Store.swift"), "symbol": .string("load")], client: client)
        #expect(docs["declarations"]?.arrayValue?.count == 1)
        #expect(docs["declarations"]?.arrayValue?.first?["docBlock"]?.stringValue == "/// load")
        let snippet = try await Self.run("code_snippet_manager", arguments: ["cwd": .string(cwd), "template": .string("actor"), "path": .string("Snippets/Counter.swift")], client: client)
        #expect(snippet["written"]?.boolValue == true)
        #expect(try Self.readText("Snippets/Counter.swift", in: tempRoot).contains("actor Counter"))

        try Self.writeText("Compiling App.swift\nApp.swift:10:5: error: cannot find 'x' in scope\nApp.swift:12:1: warning: unused variable\n** BUILD FAILED **\n", to: "build.log", in: tempRoot)
        let buildLog = try await Self.run("build_log_analyze", arguments: ["cwd": .string(cwd), "path": .string("build.log")], client: client)
        #expect(buildLog["result"]?.stringValue == "failed")
        #expect(buildLog["errorCount"]?.intValue == 1)
        #expect(buildLog["warningCount"]?.intValue == 1)
        try Self.writeText("Exception Type: EXC_BAD_ACCESS (SIGSEGV)\nTermination Reason: Namespace SIGNAL, Code 11 Segmentation fault\nTriggered by Thread: 0\nThread 0 Crashed:\n0   DemoApp  0x100000000 main + 0\n1   DemoApp  0x100000100 start + 0\nThread 1:\n0   libsystem  0x100000200 work + 0\n", to: "crash.log", in: tempRoot)
        let crash = try await Self.run("crash_log_parse", arguments: ["cwd": .string(cwd), "path": .string("crash.log")], client: client)
        #expect(crash["exceptionType"]?.stringValue == "EXC_BAD_ACCESS (SIGSEGV)")
        #expect(crash["faultingThread"]?.intValue == 0)
        #expect(crash["blamedFrames"]?.arrayValue?.count == 2)
        let diagnostics = try await Self.run("runtime_diagnostics_engine", arguments: ["cwd": .string(cwd), "logPath": .string("crash.log")], client: client)
        #expect(diagnostics["findings"]?.arrayValue?.count == 3)
        #expect(diagnostics["leads"]?.arrayValue?.count == 3)
        try Self.writeText("Test Suite 'DemoTests' started\nTest Case '-[DemoTests testExample]' passed (0.001 seconds)\nTest Case '-[DemoTests testBroken]' failed (0.002 seconds)\nTest Suite 'DemoTests' finished\nTests/StoreTests.swift:10: error: DemoTests.testBroken : failed\n", to: "test.log", in: tempRoot)
        let testLog = try await Self.run("test_log_parse", arguments: ["cwd": .string(cwd), "path": .string("test.log")], client: client)
        #expect(testLog["passed"]?.intValue == 1)
        #expect(testLog["failed"]?.intValue == 1)
        #expect(testLog["failedTests"]?.arrayValue?.first?["stringValue"] == "DemoTests testBroken")
        #expect(testLog["suites"]?.arrayValue?.first?["passed"]?.intValue == 1)
        #expect(testLog["errorLines"]?.arrayValue?.count == 1)
        try Self.writeText("Test Case '-[DemoTests testExample]' passed (0.001 seconds)\nTest Case '-[DemoTests testExample]' failed (0.002 seconds)\n", to: "flaky.log", in: tempRoot)
        let flaky = try await Self.run("test_flaky_detect", arguments: ["cwd": .string(cwd), "path": .string("flaky.log")], client: client)
        #expect(flaky["flakyCount"]?.intValue == 1)
        #expect(flaky["flaky"]?.arrayValue?.first?["name"]?.stringValue == "DemoTests testExample")
        try Self.writeText("\"hello\" = \"Hello\";\n\"hello\" = \"Hello again\";\n\"empty\" = \"\";\nbad line here\n", to: "Localizable.strings", in: tempRoot)
        let strings = try await Self.run("strings_file_validate", arguments: ["cwd": .string(cwd)], client: client)
        #expect(strings["issueCount"]?.intValue == 3)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \t<key>CFBundleIdentifier</key>
        \t<string>com.example.Demo</string>
        \t<key>CFBundleShortVersionString</key>
        \t<string>1.0</string>
        \t<key>CFBundleVersion</key>
        \t<string>1</string>
        \t<key>CFBundleName</key>
        \t<string>Demo</string>
        </dict>
        </plist>
        """
        try Self.writeText(plist, to: "Info.plist", in: tempRoot)
        let plistAudit = try await Self.run("info_plist_audit", arguments: ["cwd": .string(cwd)], client: client)
        #expect(plistAudit["filesChecked"]?.intValue == 1)
        #expect(plistAudit["plists"]?.arrayValue?.first?["issues"]?.arrayValue?.count == 0)
        try Self.writeText("{\"testTargets\": [{\"target\": {\"name\": \"DemoTests\"}}]}", to: "Demo.xctestplan", in: tempRoot)
        let plans = try await Self.run("scheme_test_plan_list", arguments: ["cwd": .string(cwd)], client: client)
        #expect(plans["plans"]?.arrayValue?.first?["testTargets"]?.arrayValue?.first?["stringValue"] == "DemoTests")
        let settingsPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \t<key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>
        \t<true/>
        </dict>
        </plist>
        """
        try Self.writeText(settingsPlist, to: "Demo.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings", in: tempRoot)
        let settings = try await Self.run("workspace_settings_read", arguments: ["cwd": .string(cwd)], client: client)
        #expect(settings["found"]?.boolValue == true)
        #expect(settings["settings"]?["IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded"]?.stringValue == "true")
        try Self.writeText("# Demo\n\n[Guide](Guide.md)\n[Missing](Nope.md)\n", to: "README.md", in: tempRoot)
        try Self.writeText("# Guide\n", to: "Guide.md", in: tempRoot)
        let index = try await Self.run("docs_index_build", arguments: ["cwd": .string(cwd)], client: client)
        #expect(index["files"]?.arrayValue?.count == 2)
        #expect(index["files"]?.arrayValue?.compactMap { $0["title"]?.stringValue }.sorted() == ["Demo", "Guide"])
        let links = try await Self.run("markdown_link_check", arguments: ["cwd": .string(cwd)], client: client)
        #expect(links["links"]?.intValue == 2)
        #expect(links["brokenCount"]?.intValue == 1)
        #expect(links["broken"]?.arrayValue?.first?["target"]?.stringValue == "Nope.md")
        let entitlementsA = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \t<key>application-identifier</key>
        \t<string>TeamID.com.example.Demo</string>
        \t<key>get-task-allow</key>
        \t<true/>
        \t<key>aps-environment</key>
        \t<string>development</string>
        </dict>
        </plist>
        """
        let entitlementsB = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \t<key>application-identifier</key>
        \t<string>TeamID.com.example.Demo</string>
        \t<key>get-task-allow</key>
        \t<false/>
        \t<key>com.apple.security.application-groups</key>
        \t<array>
        \t\t<string>group.com.example.Demo</string>
        \t</array>
        </dict>
        </plist>
        """
        try Self.writeText(entitlementsA, to: "A.entitlements", in: tempRoot)
        try Self.writeText(entitlementsB, to: "B.entitlements", in: tempRoot)
        let entitlements = try await Self.run("entitlements_diff", arguments: ["cwd": .string(cwd), "path": .string("A.entitlements"), "otherPath": .string("B.entitlements")], client: client)
        #expect(entitlements["added"]?.arrayValue?.compactMap { $0.stringValue } == ["com.apple.security.application-groups"])
        #expect(entitlements["removed"]?.arrayValue?.compactMap { $0.stringValue } == ["aps-environment"])
        #expect(entitlements["changed"]?.arrayValue?.first?["key"]?.stringValue == "get-task-allow")
        try Self.writeText("PRODUCT_NAME = Demo\nSWIFT_VERSION = 5.0\n", to: "Debug.xcconfig", in: tempRoot)
        try Self.writeText("PRODUCT_NAME = Demo\nSWIFT_VERSION = 6.0\nOPTIMIZATION = -O\n", to: "Release.xcconfig", in: tempRoot)
        let xcconfig = try await Self.run("build_settings_diff", arguments: ["cwd": .string(cwd), "path": .string("Debug.xcconfig"), "otherPath": .string("Release.xcconfig")], client: client)
        #expect(xcconfig["added"]?.arrayValue?.compactMap { $0.stringValue } == ["OPTIMIZATION"])
        #expect(xcconfig["changed"]?.arrayValue?.first?["key"]?.stringValue == "SWIFT_VERSION")
        await client.close()
    }


    @Test("Slice 13 pbxproj tools round-trip through the real workspace")
    func sliceThirteenPbxprojRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("import Foundation\n", to: "App.swift", in: tempRoot)
        let pbxproj = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 56;
        \tobjects = {

        /* Begin PBXBuildFile section */
        \t\tAAAABBBBCCCCDDDDEEEE0001 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAABBBBCCCCDDDDEEEE0011; };
        \t\tAAAABBBBCCCCDDDDEEEE0002 /* Missing.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAABBBBCCCCDDDDEEEE0012; };
        \t\tAAAABBBBCCCCDDDDEEEE0003 /* App.swift in Resources */ = {isa = PBXBuildFile; fileRef = AAAABBBBCCCCDDDDEEEE0011; };
        \t\tAAAABBBBCCCCDDDDEEEE0004 /* Orphan.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAABBBBCCCCDDDDEEEE00FF; };
        /* End PBXBuildFile section */

        /* Begin PBXFileReference section */
        \t\tAAAABBBBCCCCDDDDEEEE0011 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
        \t\tAAAABBBBCCCCDDDDEEEE0012 /* Missing.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Missing.swift; sourceTree = "<group>"; };
        \t\tAAAABBBBCCCCDDDDEEEE0013 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
        /* End PBXFileReference section */

        /* Begin PBXNativeTarget section */
        \t\tAAAABBBBCCCCDDDDEEEE0021 /* DemoApp */ = {isa = PBXNativeTarget; buildConfigurationList = AAAABBBBCCCCDDDDEEEE0041; buildPhases = (
        \t\t\tAAAABBBBCCCCDDDDEEEE0031 /* Sources */,
        \t\t\tAAAABBBBCCCCDDDDEEEE0032 /* Run Script */,
        \t\t); buildRules = (
        \t\t); dependencies = (
        \t\t\tAAAABBBBCCCCDDDDEEEE0029 /* PBXTargetDependency */,
        \t\t); name = DemoApp; productName = DemoApp; productType = "com.apple.product-type.application"; };
        \t\tAAAABBBBCCCCDDDDEEEE0022 /* DemoLib */ = {isa = PBXNativeTarget; buildConfigurationList = AAAABBBBCCCCDDDDEEEE0041; buildPhases = (
        \t\t); buildRules = (
        \t\t); dependencies = (
        \t\t); name = DemoLib; productName = DemoLib; productType = "com.apple.product-type.library.static"; };
        /* End PBXNativeTarget section */

        /* Begin PBXShellScriptBuildPhase section */
        \t\tAAAABBBBCCCCDDDDEEEE0032 /* Run Script */ = {isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (
        \t\t); inputPaths = (
        \t\t); name = "Run Script"; outputPaths = (
        \t\t); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = "echo hello\\n"; };
        /* End PBXShellScriptBuildPhase section */

        /* Begin PBXSourcesBuildPhase section */
        \t\tAAAABBBBCCCCDDDDEEEE0031 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (
        \t\t\tAAAABBBBCCCCDDDDEEEE0001 /* App.swift in Sources */,
        \t\t\tAAAABBBBCCCCDDDDEEEE0002 /* Missing.swift in Sources */,
        \t\t\tAAAABBBBCCCCDDDDEEEE0004 /* Orphan.swift in Sources */,
        \t\t); runOnlyForDeploymentPostprocessing = 0; };
        /* End PBXSourcesBuildPhase section */

        /* Begin PBXTargetDependency section */
        \t\tAAAABBBBCCCCDDDDEEEE0029 /* PBXTargetDependency */ = {isa = PBXTargetDependency; target = AAAABBBBCCCCDDDDEEEE0022 /* DemoLib */; targetProxy = AAAABBBBCCCCDDDDEEEE0028 /* PBXContainerItemProxy */; };
        /* End PBXTargetDependency section */

        /* Begin XCBuildConfiguration section */
        \t\tAAAABBBBCCCCDDDDEEEE0051 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {
        \t\t\tPRODUCT_NAME = DemoApp;
        \t\t}; name = Debug; };
        \t\tAAAABBBBCCCCDDDDEEEE0052 /* Release */ = {isa = XCBuildConfiguration; buildSettings = {
        \t\t\tPRODUCT_NAME = DemoApp;
        \t\t}; name = Release; };
        /* End XCBuildConfiguration section */

        \t};
        \trootObject = AAAABBBBCCCCDDDDEEEE0099 /* Project object */;
        }
        """
        try Self.writeText(pbxproj, to: "Demo.xcodeproj/project.pbxproj", in: tempRoot)
        let lint = try await Self.run("pbxproj_lint", arguments: ["cwd": .string(cwd)], client: client)
        #expect(lint["fileReferences"]?.intValue == 3)
        #expect(lint["missingFiles"]?.arrayValue?.compactMap { $0["path"]?.stringValue } == ["Missing.swift"])
        #expect(lint["duplicatePaths"]?.arrayValue?.compactMap { $0.stringValue } == ["App.swift"])
        #expect(lint["danglingBuildFiles"]?.arrayValue?.compactMap { $0.stringValue } == ["AAAABBBBCCCCDDDDEEEE0004"])
        #expect(lint["issueCount"]?.intValue == 3)
        let scripts = try await Self.run("build_phase_scripts_list", arguments: ["cwd": .string(cwd)], client: client)
        #expect(scripts["phases"]?.arrayValue?.count == 1)
        #expect(scripts["phases"]?.arrayValue?.first?["name"]?.stringValue == "Run Script")
        #expect(scripts["phases"]?.arrayValue?.first?["shellPath"]?.stringValue == "/bin/sh")
        #expect(scripts["phases"]?.arrayValue?.first?["script"]?.stringValue?.contains("echo hello") == true)
        let configs = try await Self.run("build_configuration_list", arguments: ["cwd": .string(cwd)], client: client)
        #expect(configs["configurations"]?.arrayValue?.compactMap { $0.stringValue }.sorted() == ["Debug", "Release"])
        let deps = try await Self.run("target_dependencies_list", arguments: ["cwd": .string(cwd)], client: client)
        #expect(deps["targets"]?.arrayValue?.first { $0["name"]?.stringValue == "DemoApp" }?["dependencies"]?.arrayValue?.compactMap { $0.stringValue } == ["DemoLib"])
        #expect(deps["targets"]?.arrayValue?.first { $0["name"]?.stringValue == "DemoLib" }?["dependencies"]?.arrayValue?.count == 0)
        let sources = try await Self.run("target_source_list", arguments: ["cwd": .string(cwd)], client: client)
        #expect(sources["targets"]?.arrayValue?.first?["name"]?.stringValue == "DemoApp")
        #expect(sources["targets"]?.arrayValue?.first?["sources"]?.arrayValue?.compactMap { $0.stringValue } == ["App.swift", "Missing.swift"])
        await client.close()
    }

    @Test("Slice 13 parsers read real scan text shapes")
    func sliceThirteenParsersParseRealText() {
        let summary = SystemToolRegistry.parseG5FileSummary(tool: "code_summary", path: "A.swift", content: "import Foundation\n\n// note\nlet x = 1\n")
        #expect(summary["lines"]?.intValue == 5)
        #expect(summary["codeLines"]?.intValue == 2)
        #expect(summary["commentLines"]?.intValue == 1)
        #expect(summary["blankLines"]?.intValue == 2)
        let complexity = SystemToolRegistry.parseG5Complexity(tool: "complexity_analysis", path: "A.swift", content: "func f() {\n    if a && b {\n        for i in list {\n        }\n    }\n}\n")
        #expect(complexity["complexityEstimate"]?.intValue == 4)
        let diagnostics = SystemToolRegistry.parseG5DiagnosticsLog(tool: "runtime_diagnostics_engine", logPath: "crash.log", content: "fatal error: nil\nEXC_BAD_ACCESS\nThread 0 crashed\n")
        #expect(diagnostics["findings"]?.arrayValue?.count == 4)
        let buildLog = SystemToolRegistry.parseG5BuildLog(tool: "build_log_analyze", path: "build.log", content: "ok\n** BUILD SUCCEEDED **\n")
        #expect(buildLog["result"]?.stringValue == "succeeded")
        #expect(buildLog["errorCount"]?.intValue == 0)
        let crash = SystemToolRegistry.parseG5CrashLog(tool: "crash_log_parse", path: "crash.log", content: "Exception Type: EXC_CRASH (SIGABRT)\nTermination Reason: Namespace SIGNAL\nTriggered by Thread: 2\nThread 2 Crashed:\n0   App  0x1 main + 0\n")
        #expect(crash["exceptionType"]?.stringValue == "EXC_CRASH (SIGABRT)")
        #expect(crash["faultingThread"]?.intValue == 2)
        #expect(crash["blamedFrames"]?.arrayValue?.count == 1)
        let testLog = SystemToolRegistry.parseG5TestLog(tool: "test_log_parse", path: "test.log", content: "Test Suite 'S' started\nTest Case '-[S a]' passed (0.1 seconds)\nTest Case '-[S b]' failed (0.1 seconds)\nTest Suite 'S' finished\n")
        #expect(testLog["passed"]?.intValue == 1)
        #expect(testLog["failed"]?.intValue == 1)
        #expect(testLog["suites"]?.arrayValue?.first?["failed"]?.intValue == 1)
        let flaky = SystemToolRegistry.parseG5FlakyTests(tool: "test_flaky_detect", path: "test.log", content: "Test Case '-[S a]' passed (0.1 seconds)\nTest Case '-[S a]' failed (0.1 seconds)\nTest Case '-[S b]' passed (0.1 seconds)\n")
        #expect(flaky["flakyCount"]?.intValue == 1)
        #expect(flaky["flaky"]?.arrayValue?.first?["name"]?.stringValue == "S a")
        let plistValues = SystemToolRegistry.parseG5PlistKeyValues("<key>CFBundleIdentifier</key>\n<string>com.example.App</string>\n<key>Flag</key>\n<true/>\n<key>Count</key>\n<integer>3</integer>\n")
        #expect(plistValues["CFBundleIdentifier"] == "com.example.App")
        #expect(plistValues["Flag"] == "true")
        #expect(plistValues["Count"] == "3")
        let xcconfigValues = SystemToolRegistry.parseG5XcconfigKeyValues("// comment\nPRODUCT_NAME = Demo\nSWIFT_VERSION = 6.0\n")
        #expect(xcconfigValues["PRODUCT_NAME"] == "Demo")
        #expect(xcconfigValues["SWIFT_VERSION"] == "6.0")
        let diff = SystemToolRegistry.parseG5KeyValueDiff(tool: "build_settings_diff", path: "A.xcconfig", otherPath: "B.xcconfig", first: ["A": "1", "B": "2"], second: ["B": "3", "C": "4"])
        #expect(diff["added"]?.arrayValue?.compactMap { $0.stringValue } == ["C"])
        #expect(diff["removed"]?.arrayValue?.compactMap { $0.stringValue } == ["A"])
        #expect(diff["changed"]?.arrayValue?.first?["key"]?.stringValue == "B")
        let dead = SystemToolRegistry.parseG5DeadCode(tool: "dead_code_scan", files: [("A.swift", "func used() {\n}\nfunc unused() {\n}\nused()\n")], privateOnly: false, limit: 200)
        #expect(dead["candidateCount"]?.intValue == 1)
        #expect(dead["candidates"]?.arrayValue?.first?["name"]?.stringValue == "unused")
        let duplicates = SystemToolRegistry.parseG5DuplicateBlocks(tool: "duplicate_code_scan", files: [("A.swift", "print(\"a\")\nprint(\"b\")\nprint(\"c\")\nprint(\"d\")\nprint(\"e\")\nprint(\"f\")\nprint(\"g\")\n"), ("B.swift", "print(\"a\")\nprint(\"b\")\nprint(\"c\")\nprint(\"d\")\nprint(\"e\")\nprint(\"f\")\nprint(\"h\")\n")], limit: 200)
        #expect(duplicates["blockCount"]?.intValue == 1)
        let sizes = SystemToolRegistry.parseG5FunctionSizes(tool: "function_size_report", files: [("A.swift", "func small() {\n}\nfunc big() {\n    print(1)\n    print(2)\n    print(3)\n}\n")], limit: 200)
        #expect(sizes["functions"]?.arrayValue?.first?["name"]?.stringValue == "big")
        #expect(sizes["functions"]?.arrayValue?.first?["lines"]?.intValue == 5)
        let coverage = SystemToolRegistry.parseG5DocCoverage(tool: "api_docs_coverage", files: [("A.swift", "/// Documented.\npublic func a() {\n}\npublic func b() {\n}\n")])
        #expect(coverage["declarations"]?.intValue == 2)
        #expect(coverage["documented"]?.intValue == 1)
        #expect(coverage["coverage"]?.doubleValue == 0.5)
        let docstring = SystemToolRegistry.parseG5Docstring(tool: "docstring_generator", path: "A.swift", content: "public func greet(name: String, count: Int) -> String {\n    return name\n}\n", symbol: nil)
        #expect(docstring["declarations"]?.arrayValue?.first?["docBlock"]?.stringValue?.contains("///   - name: ") == true)
        #expect(docstring["declarations"]?.arrayValue?.first?["docBlock"]?.stringValue?.contains("///   - count: ") == true)
        #expect(docstring["declarations"]?.arrayValue?.first?["docBlock"]?.stringValue?.contains("/// - Returns: ") == true)
        let density = SystemToolRegistry.parseG5CommentDensity(tool: "comment_density_report", files: [("A.swift", "// c\nlet x = 1\n"), ("B.swift", "let y = 2\n")], limit: 200)
        #expect(density["files"]?.arrayValue?.first?["path"]?.stringValue == "B.swift")
        let metrics = SystemToolRegistry.parseG5Metrics(tool: "code_metrics_analyzer", files: [("A.swift", "struct S {\n    func f() {\n    }\n}\n")])
        #expect(metrics["totals"]?["functions"]?.intValue == 1)
        #expect(metrics["totals"]?["types"]?.intValue == 1)
        let unused = SystemToolRegistry.parseG5UnusedImports(tool: "unused_imports_detector", files: [("A.swift", "import Foundation\nimport FakeyKit\nlet x = 1\n")], limit: 200)
        #expect(unused["unused"]?.arrayValue?.compactMap { $0["module"]?.stringValue } == ["FakeyKit"])
        let license = SystemToolRegistry.parseG5LicenseCheck(tool: "license_header_check", files: [("A.swift", "// Copyright 2026\nlet x = 1\n"), ("B.swift", "let y = 2\n")], requiredText: "Copyright")
        #expect(license["missing"]?.arrayValue?.compactMap { $0.stringValue } == ["B.swift"])
        #expect(SystemToolRegistry.g5SnippetTemplate("actor")?.contains("actor Counter") == true)
        #expect(SystemToolRegistry.g5SnippetTemplate("bogus") == nil)
    }

    @Test("Slice 13 tools refuse missing arguments before any runtime call")
    func sliceThirteenToolsRefuseMissingArguments() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cases: [(String, [String: JSONValue], String)] = [
            ("search_symbol", ["cwd": .string(tempRoot.path)], "symbol"),
            ("call_hierarchy", ["cwd": .string(tempRoot.path)], "function"),
            ("protocol_conformance_list", ["cwd": .string(tempRoot.path)], "protocol"),
            ("change_impact_estimate", ["cwd": .string(tempRoot.path)], "symbol"),
            ("semantic_query_engine", ["cwd": .string(tempRoot.path)], "query"),
            ("code_summary", ["cwd": .string(tempRoot.path)], "path"),
            ("complexity_analysis", ["cwd": .string(tempRoot.path)], "path"),
            ("runtime_diagnostics_engine", ["cwd": .string(tempRoot.path)], "logPath"),
            ("build_log_analyze", ["cwd": .string(tempRoot.path)], "path"),
            ("entitlements_diff", ["cwd": .string(tempRoot.path), "path": .string("A.entitlements")], "otherPath"),
        ]
        for (tool, arguments, missing) in cases {
            do {
                _ = try await Self.run(tool, arguments: arguments, client: client)
                Issue.record("Expected missingArgument error for \(tool)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: tool, argument: missing))
            } catch {
                Issue.record("Unexpected error for \(tool): \(error)")
            }
        }
        do {
            _ = try await Self.run("code_snippet_manager", arguments: ["cwd": .string(tempRoot.path), "template": .string("bogus")], client: client)
            Issue.record("Expected executionFailed error for a bogus snippet template")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "code_snippet_manager", message: "Unknown template. Use observable, asyncstream, actor, or glasscard."))
        } catch {
            Issue.record("Unexpected error for code_snippet_manager: \(error)")
        }
        await client.close()
    }



    @Test("Slice 14: G5 part 2 tools register with expected actions and channels")
    func sliceFourteenToolsRegister() {
        let tools = SystemToolRegistry.tools(for: .system)
        let expected: [(name: String, action: String, channel: SystemToolChannel)] = [
            ("framework_linker_auditor", "workspace.read_file", .desktop),
            ("string_catalog_migrator", "workspace.write_file", .desktop),
            ("symbol_reference_graph", "workspace.search_regex", .desktop),
            ("podfile_inspector", "workspace.read_file", .desktop),
            ("carthage_cartfile_inspector", "workspace.read_file", .desktop),
            ("spm_dependency_tree", "terminal.create", .engine),
            ("package_manifest_read", "workspace.read_file", .desktop),
            ("package_manifest_validate", "terminal.create", .engine),
            ("package_dependency_audit", "terminal.create", .engine),
            ("package_dependency_add", "workspace.write_file", .desktop),
            ("asset_catalog_list", "workspace.files", .desktop),
            ("asset_image_add", "workspace.write_file", .desktop),
            ("strings_localization", "workspace.write_file", .desktop),
            ("localization_audit", "workspace.read_file", .desktop),
            ("localize_app", "workspace.write_file", .desktop),
            ("asset_catalog_manager", "workspace.write_file", .desktop),
            ("localization_manager", "workspace.write_file", .desktop),
            ("entitlements_manager", "workspace.write_file", .desktop),
            ("colorset_builder", "workspace.write_file", .desktop),
            ("icon_generator_tool", "terminal.create", .engine),
            ("project_entitlements", "workspace.read_file", .desktop),
            ("project_info_plist", "workspace.write_file", .desktop),
            ("project_capabilities", "workspace.write_file", .desktop),
            ("project_signing", "terminal.create", .engine),
            ("entry_points_discover", "workspace.search_regex", .desktop),
            ("repo_overview", "workspace.files", .desktop),
            ("project_structure_map", "workspace.read_dir", .desktop),
            ("recent_changes", "workspace.read_dir", .desktop),
            ("readme_locate", "workspace.read_file", .desktop),
            ("dependency_licenses", "workspace.read_file", .desktop),
            ("stale_files_report", "workspace.read_dir", .desktop),
            ("file_type_breakdown", "workspace.files", .desktop),
            ("empty_dirs_find", "workspace.read_dir", .desktop),
            ("symlink_audit", "workspace.read_dir", .desktop),
            ("executable_files_scan", "workspace.read_dir", .desktop),
            ("dir_size_report", "workspace.read_dir", .desktop),
            ("image_asset_size_report", "workspace.read_dir", .desktop),
            ("bundle_resource_auditor", "workspace.read_file", .desktop),
            ("core_data_model_inspector", "workspace.read_file", .desktop),
            ("swift_data_schema_auditor", "workspace.read_file", .desktop),
            ("privacy_manifest_auditor", "workspace.read_file", .desktop),
            ("env_info", "system.info", .desktop),
            ("process_monitor_tool", "terminal.create", .engine),
            ("disk_space_analyzer", "terminal.create", .engine),
            ("environment_variable_manager", "system.env", .desktop),
            ("clipboard_manager_tool", "system.clipboard", .desktop),
            ("system_notification_tool", "system.notify", .desktop),
            ("use_system", "terminal.create", .engine),
            ("search_skills", "system.skills", .desktop),
            ("plan-AskUser", "agent.pending", .engine),
            ("tool_capability_lookup", "system.lookup", .desktop),
            ("preflight_checks", "terminal.create", .engine),
            ("session_progress_report", "workspace.read_file", .desktop),
            ("manage_memory", "memory.store", .desktop),
            ("fetch_documentation", "web.fetch", .desktop),
            ("external_resource_gateway", "web.fetch", .desktop),
            ("read_url_content", "web.fetch", .desktop),
            ("github_repo", "github.repo", .engine),
            ("use_app", "computer_use.request", .engine),
            ("derived_data_locate", "system.info", .desktop),
            ("build_system_detect", "workspace.files", .desktop),
        ]
        #expect(expected.count == 61)
        for row in expected {
            guard let definition = SystemToolRegistry.definition(named: row.name, for: .system) else {
                Issue.record("Slice 14 tool missing from registry: \(row.name)")
                continue
            }
            #expect(definition.action == row.action)
            #expect(definition.channel == row.channel)
            #expect(!definition.parameters.isEmpty)
        }
        let cwdParams = ["framework_linker_auditor", "repo_overview", "build_system_detect"]
        for name in cwdParams {
            let params = SystemToolRegistry.definition(named: name, for: .system)?.parameters ?? []
            #expect(params.contains { $0.name == "cwd" && $0.required && $0.type == "string" })
        }
    }

    @Test("Slice 14: G6 parsers read real text shapes")
    func sliceFourteenParsersReadRealTextShapes() throws {
        let manifestText = """
        // swift-tools-version: 5.10
        import PackageDescription

        let package = Package(
            name: "MyApp",
            platforms: [.macOS(.v14), .iOS(.v17)],
            products: [
                .library(name: "MyApp", targets: ["MyApp"]),
            ],
            dependencies: [
                .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
            ],
            targets: [
                .target(name: "MyApp"),
                .testTarget(name: "MyAppTests"),
            ]
        )
        """
        let manifest = SystemToolRegistry.g6ParseManifest(manifestText)
        #expect(manifest.name == "MyApp")
        #expect(manifest.platforms == ["macOS 14", "iOS 17"])
        #expect(manifest.products == ["MyApp"])
        #expect(manifest.targets == ["MyApp", "MyAppTests"])
        #expect(manifest.dependencies.count == 1)
        #expect(manifest.dependencies[0]["url"] == "https://github.com/apple/swift-argument-parser")
        #expect(manifest.dependencies[0]["from"] == "1.3.0")

        let resolvedJSON = """
        {
          "pins": [
            { "identity": "swift-argument-parser", "location": "https://github.com/apple/swift-argument-parser", "state": { "branch": null, "revision": "aabbcc", "version": "1.3.0" } },
            { "identity": "swift-collections", "location": "https://github.com/apple/swift-collections", "state": { "branch": null, "revision": "ddeeff", "version": "1.1.0" } }
          ],
          "version": 2
        }
        """
        let pins = SystemToolRegistry.g6ParseResolved(resolvedJSON)
        #expect(pins.count == 2)
        #expect(pins[0]["identity"] == "swift-argument-parser")
        #expect(pins[0]["version"] == "1.3.0")
        #expect(pins[1]["identity"] == "swift-collections")
        #expect(pins[1]["version"] == "1.1.0")

        let audit = SystemToolRegistry.g6DependencyAudit(
            tool: "package_dependency_audit",
            manifest: manifest,
            resolvedPins: pins,
            shown: ["swift-argument-parser"],
            exitCode: 0,
            output: ""
        )
        #expect(audit["missingResolved"]?.arrayValue?.isEmpty == true)
        #expect(audit["nonExactRequirements"]?.arrayValue?.count == 1)
        #expect(audit["resolvedMissingFromManifest"]?.arrayValue?.compactMap { $0.stringValue } == ["swift-collections"])

        let shownJSON = """
        {
          "name": "MyApp",
          "dependencies": [
            { "identity": "swift-argument-parser", "dependencies": [{ "identity": "swift-nio" }] }
          ]
        }
        """
        let shownValue = try JSONDecoder().decode(JSONValue.self, from: Data(shownJSON.utf8))
        #expect(SystemToolRegistry.g6ShowDependenciesNames(shownValue) == ["swift-argument-parser", "swift-nio"])

        let stringsText = "\"hello\" = \"Hello\";\n\"bye\" = \"Bye\";\n// a comment\n"
        let pairs = SystemToolRegistry.g6StringsPairs(stringsText)
        #expect(pairs.count == 2)
        #expect(pairs[0].key == "hello" && pairs[0].value == "Hello")
        #expect(pairs[1].key == "bye" && pairs[1].value == "Bye")
        let serialized = SystemToolRegistry.g6SerializeStrings(pairs.map { (key: $0.key, value: $0.value) })
        #expect(serialized == "\"hello\" = \"Hello\";\n\"bye\" = \"Bye\";\n")
        #expect(SystemToolRegistry.g6StringsUnescape("a\\n\\t\\\"b") == "a\n\t\"b")
        #expect(SystemToolRegistry.g6StringsEscape("a\nb") == "a\\nb")

        let xcstringsJSON = """
        {"sourceLanguage":"en","strings":{"hello":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"Hello"}}}}},"version":"1.0"}
        """
        let xcstrings = try JSONDecoder().decode(JSONValue.self, from: Data(xcstringsJSON.utf8))
        let xcstringsDict = xcstrings.objectValue ?? [:]
        let keys = SystemToolRegistry.g6XcstringsKeys(xcstringsDict)
        #expect(keys["hello"]?["en"] == "Hello")
        let updated = SystemToolRegistry.g6XcstringsSet(xcstringsDict, key: "bye", locale: "fr", value: "Au revoir", state: "new")
        let updatedKeys = SystemToolRegistry.g6XcstringsKeys(updated)
        #expect(updatedKeys["bye"]?["fr"] == "Au revoir")
        #expect(updatedKeys["hello"]?["en"] == "Hello")

        let pbxproj = """
        /* Begin PBXBuildFile section */
            111111111111111111111111 = {isa = PBXBuildFile; fileRef = 222222222222222222222222; /* Foundation.framework */ settings = {ATTRIBUTES = (Weak, ); }; };
            555555555555555555555555 = {isa = PBXBuildFile; fileRef = 666666666666666666666666; };
        /* End PBXBuildFile section */
        /* Begin PBXFileReference section */
            222222222222222222222222 /* Foundation.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Foundation.framework; path = System/Library/Frameworks/Foundation.framework; sourceTree = SDKROOT; };
            666666666666666666666666 /* Logo.png */ = {isa = PBXFileReference; lastKnownFileType = image.png; name = Logo.png; path = Logo.png; sourceTree = "<group>"; };
        /* End PBXFileReference section */
        /* Begin PBXResourcesBuildPhase section */
            777777777777777777777777 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (
                555555555555555555555555 /* Logo.png in Resources */,
            ); runOnlyForDeploymentPostprocessing = 0; };
        /* End PBXResourcesBuildPhase section */
        /* Begin PBXNativeTarget section */
            333333333333333333333333 /* MyApp */ = {isa = PBXNativeTarget; name = MyApp; };
        /* End PBXNativeTarget section */
        /* Begin XCBuildConfiguration section */
            444444444444444444444444 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = { CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ABCDE12345; PRODUCT_BUNDLE_IDENTIFIER = com.example.myapp; CODE_SIGN_IDENTITY = "Apple Development"; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; }; name = Debug; };
        /* End XCBuildConfiguration section */
        """
        let frameworkAudit = SystemToolRegistry.g6FrameworkAudit(tool: "framework_linker_auditor", path: "MyApp.xcodeproj/project.pbxproj", content: pbxproj)
        #expect(frameworkAudit["linkedCount"]?.intValue == 1)
        #expect(frameworkAudit["linkedFrameworks"]?.arrayValue?.first?["name"]?.stringValue == "Foundation.framework")
        #expect(frameworkAudit["linkedFrameworks"]?.arrayValue?.first?["weak"]?.boolValue == true)
        #expect(frameworkAudit["sdkroots"]?.arrayValue?.compactMap { $0.stringValue }.contains("macosx") == true)
        #expect(frameworkAudit["deploymentTargets"]?.arrayValue?.compactMap { $0.stringValue }.contains("MACOSX_DEPLOYMENT_TARGET 14.0") == true)
        let signing = SystemToolRegistry.g6SigningFromPbxproj(tool: "project_signing", path: "MyApp.xcodeproj/project.pbxproj", content: pbxproj)
        #expect(signing["codeSignStyle"]?.stringValue == "Automatic")
        #expect(signing["developmentTeam"]?.stringValue == "ABCDE12345")
        #expect(signing["bundleIdentifier"]?.stringValue == "com.example.myapp")
        #expect(signing["codeSignIdentity"]?.stringValue == "Apple Development")
        #expect(SystemToolRegistry.g6PbxprojTargets(pbxproj) == ["MyApp"])

        let settings = SystemToolRegistry.g6BuildSettingsJSON("PRODUCT_NAME = MyApp\nSWIFT_VERSION = 5.0\n")
        #expect(settings["PRODUCT_NAME"]?.stringValue == "MyApp")
        #expect(settings["SWIFT_VERSION"]?.stringValue == "5.0")

        let ps = SystemToolRegistry.g6ParsePs("  123  1.5  2.0 /usr/bin/foo\n  456  0.0  0.1 /bin/bar\n", filter: nil, limit: 200)
        #expect(ps.count == 2)
        #expect(ps[0]["pid"]?.intValue == 123)
        #expect(ps[0]["cpuPercent"]?.doubleValue == 1.5)
        #expect(ps[0]["command"]?.stringValue == "/usr/bin/foo")
        let filtered = SystemToolRegistry.g6ParsePs("  123  1.5  2.0 /usr/bin/foo\n  456  0.0  0.1 /bin/bar\n", filter: "bar", limit: 200)
        #expect(filtered.count == 1)
        #expect(filtered[0]["pid"]?.intValue == 456)

        let df = "Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk1 1000000 400000 600000 40% 100 200 1% /\n"
        let disk = SystemToolRegistry.g6DiskSpace(tool: "disk_space_analyzer", path: ".", dfOutput: df, duOutput: "1234\t.")
        #expect(disk["totalKilobytes"]?.intValue == 1000000)
        #expect(disk["usedKilobytes"]?.intValue == 400000)
        #expect(disk["availableKilobytes"]?.intValue == 600000)
        #expect(disk["capacityPercent"]?.intValue == 40)
        #expect(disk["mountPoint"]?.stringValue == "/")
        #expect(disk["pathKilobytes"]?.intValue == 1234)

        let bundleEntries = [
            WorkspaceFileEntry(path: "Sources/Logo.png", sizeBytes: 2048),
            WorkspaceFileEntry(path: "Sources/App.swift", sizeBytes: 100),
        ]
        let bundle = SystemToolRegistry.g6BundleResources(tool: "bundle_resource_auditor", path: "MyApp.xcodeproj/project.pbxproj", content: pbxproj, entries: bundleEntries)
        #expect(bundle["resources"]?.arrayValue?.first?["path"]?.stringValue == "Logo.png")
        #expect(bundle["resources"]?.arrayValue?.first?["found"]?.boolValue == true)
        #expect(bundle["missing"]?.arrayValue?.isEmpty == true)
        #expect(bundle["duplicates"]?.arrayValue?.isEmpty == true)

        let modelContents = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0">
          <entity name="Item" representedClassName="Item">
            <attribute name="name" attributeType="String"/>
            <attribute name="createdAt" attributeType="Date"/>
            <relationship name="owner" destinationEntity="Owner" maxCount="1"/>
          </entity>
          <entity name="Owner" representedClassName="Owner">
            <attribute name="email" attributeType="String"/>
          </entity>
        </model>
        """
        let coreData = SystemToolRegistry.g6CoreDataModel(tool: "core_data_model_inspector", path: "Model.xcdatamodeld/Model.xcdatamodel/contents", content: modelContents)
        #expect(coreData["entityCount"]?.intValue == 2)
        #expect(coreData["entities"]?.arrayValue?.first?["name"]?.stringValue == "Item")
        #expect(coreData["entities"]?.arrayValue?.first?["attributes"]?.arrayValue?.count == 2)
        #expect(coreData["entities"]?.arrayValue?.first?["relationships"]?.arrayValue?.first?["destination"]?.stringValue == "Owner")

        let goodPlist: [String: Any] = [
            "NSPrivacyTracking": false,
            "NSPrivacyCollectedDataTypes": [["NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeLinked": false, "NSPrivacyCollectedDataTypeTracking": false, "NSPrivacyCollectedDataTypePurposes": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]]],
            "NSPrivacyAccessedAPITypes": [["NSPrivacyAccessedAPICategory": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]]],
        ]
        let goodAudit = SystemToolRegistry.g6PrivacyAudit(tool: "privacy_manifest_auditor", path: "PrivacyInfo.xcprivacy", plist: goodPlist)
        #expect(goodAudit["issueCount"]?.intValue == 0)
        #expect(goodAudit["collectedDataTypes"]?.intValue == 1)
        #expect(goodAudit["accessedApiTypes"]?.intValue == 1)
        let badAudit = SystemToolRegistry.g6PrivacyAudit(tool: "privacy_manifest_auditor", path: "PrivacyInfo.xcprivacy", plist: ["NSPrivacyTracking": true])
        #expect(badAudit["issueCount"]?.intValue == 1)
        #expect(badAudit["issues"]?.arrayValue?.first?["message"]?.stringValue?.contains("NSPrivacyTrackingDomains") == true)

        let colorset = SystemToolRegistry.g6ColorsetContents(lightHex: "#FF8800", darkHex: "#112233")
        let colors = colorset["colors"] as? [[String: Any]]
        #expect(colors?.count == 2)
        let lightComponents = (colors?[0]["color"] as? [String: Any])?["components"] as? [String: String]
        #expect(lightComponents?["red"] == "1.000")
        #expect(lightComponents?["green"] == "0.533")
        #expect(lightComponents?["blue"] == "0.000")
        let darkComponents = (colors?[1]["color"] as? [String: Any])?["components"] as? [String: String]
        #expect(darkComponents?["red"] == "0.067")

        #expect(SystemToolRegistry.g6PlistScalar("true") as? Bool == true)
        #expect(SystemToolRegistry.g6PlistScalar("42") as? Int == 42)
        #expect(SystemToolRegistry.g6PlistScalar("hello") as? String == "hello")

        #expect(SystemToolRegistry.g6LanguageForExtension("swift") == "Swift")
        #expect(SystemToolRegistry.g6LanguageForExtension("py") == "Python")
        #expect(SystemToolRegistry.g6LanguageForExtension("xyz") == ".xyz")
        #expect(SystemToolRegistry.g6LanguageForExtension("") == "No extension")
        #expect(SystemToolRegistry.g6LocaleForStringsPath("en.lproj/Localizable.strings") == "en")
        #expect(SystemToolRegistry.g6LocaleForStringsPath("Base.lproj/Main.strings") == "Base")
        #expect(SystemToolRegistry.g6LocaleForStringsPath("Localizable.strings") == "base")

        let iosSizes = SystemToolRegistry.g6IconSizes(platform: "ios")
        #expect(iosSizes.count == 12)
        #expect(iosSizes[0].pixels == 40)
        #expect(SystemToolRegistry.g6IconSizes(platform: "macos").count == 10)
        #expect(SystemToolRegistry.g6IconSizes(platform: "watchos").count == 11)
    }

    @Test("Slice 14: G5 part 2 tools round-trip against a real temp workspace")
    func sliceFourteenInventoryRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try Self.writeText("""
        // swift-tools-version: 5.10
        import PackageDescription

        let package = Package(
            name: "MyApp",
            platforms: [.macOS(.v14), .iOS(.v17)],
            products: [
                .library(name: "MyApp", targets: ["MyApp"]),
            ],
            dependencies: [
                .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
            ],
            targets: [
                .target(
                    name: "MyApp",
                    dependencies: []
                ),
                .testTarget(name: "MyAppTests"),
            ]
        )
        """, to: "Package.swift", in: tempRoot)
        try Self.writeText("""
        {
          "pins": [
            { "identity": "swift-argument-parser", "location": "https://github.com/apple/swift-argument-parser", "state": { "branch": null, "revision": "aabbcc", "version": "1.3.0" } },
            { "identity": "swift-collections", "location": "https://github.com/apple/swift-collections", "state": { "branch": null, "revision": "ddeeff", "version": "1.1.0" } }
          ],
          "version": 2
        }
        """, to: "Package.resolved", in: tempRoot)
        try Self.writeText("""
        platform :ios, '17.0'
        target 'MyApp' do
          pod 'Alamofire', '5.9.0'
          pod 'SnapKit'
        end
        """, to: "Podfile", in: tempRoot)
        try Self.writeText("""
        PODS:
          - Alamofire (5.9.0)
          - SnapKit (5.7.1)

        DEPENDENCIES:
          - Alamofire
          - SnapKit
        """, to: "Podfile.lock", in: tempRoot)
        try Self.writeText("""
        github "Alamofire/Alamofire" "5.9.0"
        github "realm/realm-swift"
        """, to: "Cartfile", in: tempRoot)
        try Self.writeText("""
        github "Alamofire/Alamofire" "5.9.1"
        github "realm/realm-swift" "10.54.0"
        """, to: "Cartfile.resolved", in: tempRoot)
        try Self.writeText("""
        import Foundation
        @main
        struct MyApp: App {
            var body: some Scene { WindowGroup { ContentView() } }
        }
        final class Foo {
            func greet() -> String { NSLocalizedString("welcome", comment: "") }
        }
        let foo = Foo()
        struct ContentView {
            let label = String(localized: "settings")
        }
        """, to: "Sources/App.swift", in: tempRoot)
        try Self.writeText("""
        import SwiftData
        @Model
        final class Item {
            @Attribute(.unique) var identifier: String
            @Relationship(deleteRule: .cascade) var owner: Owner?
            var name: String
        }
        """, to: "Sources/Models/Item.swift", in: tempRoot)
        try Self.writeText("""
        import SwiftData
        @Model
        final class Owner {
            var email: String
        }
        """, to: "Sources/Models/Owner.swift", in: tempRoot)
        try Self.writeText("print(\"hello\")\n", to: "Sources/main.swift", in: tempRoot)
        try Self.writeText("fake-png-bytes", to: "Sources/hero.png", in: tempRoot)
        try Self.writeText("#!/bin/sh\necho hi\n", to: "Sources/run.sh", in: tempRoot)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: (tempRoot as NSString).appendingPathComponent("Sources/run.sh"))
        try FileManager.default.createSymbolicLink(atPath: (tempRoot as NSString).appendingPathComponent("Sources/LinkToApp"), withDestinationPath: "App.swift")
        try FileManager.default.createSymbolicLink(atPath: (tempRoot as NSString).appendingPathComponent("Sources/BrokenLink"), withDestinationPath: "Nope.swift")
        try Self.writeText("""
        /* Begin PBXBuildFile section */
            111111111111111111111111 = {isa = PBXBuildFile; fileRef = 222222222222222222222222; /* Foundation.framework */ settings = {ATTRIBUTES = (Weak, ); }; };
            555555555555555555555555 = {isa = PBXBuildFile; fileRef = 666666666666666666666666; };
        /* End PBXBuildFile section */
        /* Begin PBXFileReference section */
            222222222222222222222222 /* Foundation.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Foundation.framework; path = System/Library/Frameworks/Foundation.framework; sourceTree = SDKROOT; };
            666666666666666666666666 /* Logo.png */ = {isa = PBXFileReference; lastKnownFileType = image.png; name = Logo.png; path = Logo.png; sourceTree = "<group>"; };
            888888888888888888888888 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = App.swift; path = App.swift; sourceTree = "<group>"; };
        /* End PBXFileReference section */
        /* Begin PBXResourcesBuildPhase section */
            777777777777777777777777 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (
                555555555555555555555555 /* Logo.png in Resources */,
            ); runOnlyForDeploymentPostprocessing = 0; };
        /* End PBXResourcesBuildPhase section */
        /* Begin PBXNativeTarget section */
            333333333333333333333333 /* MyApp */ = {isa = PBXNativeTarget; name = MyApp; };
        /* End PBXNativeTarget section */
        /* Begin XCBuildConfiguration section */
            444444444444444444444444 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = { CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ABCDE12345; PRODUCT_BUNDLE_IDENTIFIER = com.example.myapp; CODE_SIGN_IDENTITY = "Apple Development"; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; }; name = Debug; };
        /* End XCBuildConfiguration section */
        """, to: "MyApp.xcodeproj/project.pbxproj", in: tempRoot)
        try Self.writeText("{\"images\":[],\"info\":{\"author\":\"xcode\",\"version\":1}}", to: "Assets.xcassets/AppIcon.appiconset/Contents.json", in: tempRoot)
        try Self.writeText("{\"images\":[{\"filename\":\"Logo.png\",\"idiom\":\"universal\",\"scale\":\"1x\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}", to: "Assets.xcassets/Logo.imageset/Contents.json", in: tempRoot)
        try Self.writeText(String(repeating: "x", count: 2048), to: "Assets.xcassets/Logo.imageset/Logo.png", in: tempRoot)
        try Self.writeText("\"welcome\" = \"Welcome\";\n\"goodbye\" = \"Goodbye\";\n", to: "en.lproj/Localizable.strings", in: tempRoot)
        try Self.writeText("\"welcome\" = \"Bienvenue\";\n", to: "fr.lproj/Localizable.strings", in: tempRoot)
        try Self.writeText("{\"sourceLanguage\":\"en\",\"strings\":{\"hello\":{\"localizations\":{\"en\":{\"stringUnit\":{\"state\":\"translated\",\"value\":\"Hello\"}}}}},\"version\":\"1.0\"}", to: "Localizable.xcstrings", in: tempRoot)
        try Self.writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.app-sandbox</key>
            <true/>
            <key>com.apple.security.network.client</key>
            <false/>
            <key>com.apple.application-identifier</key>
            <string>TEAM.com.example.myapp</string>
        </dict>
        </plist>
        """, to: "App.entitlements", in: tempRoot)
        try Self.writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>Demo</string>
        </dict>
        </plist>
        """, to: "Info.plist", in: tempRoot)
        try Self.writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSPrivacyTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypes</key>
            <array>
                <dict>
                    <key>NSPrivacyCollectedDataType</key>
                    <string>NSPrivacyCollectedDataTypeEmailAddress</string>
                    <key>NSPrivacyCollectedDataTypeLinked</key>
                    <false/>
                    <key>NSPrivacyCollectedDataTypeTracking</key>
                    <false/>
                    <key>NSPrivacyCollectedDataTypePurposes</key>
                    <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
                </dict>
            </array>
            <key>NSPrivacyAccessedAPITypes</key>
            <array>
                <dict>
                    <key>NSPrivacyAccessedAPICategory</key>
                    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
                    <key>NSPrivacyAccessedAPITypeReasons</key>
                    <array><string>C617.1</string></array>
                </dict>
                <dict>
                    <key>NSPrivacyAccessedAPICategory</key>
                    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
                    <key>NSPrivacyAccessedAPITypeReasons</key>
                    <array><string>CA92.1</string></array>
                </dict>
            </array>
        </dict>
        </plist>
        """, to: "PrivacyInfo.xcprivacy", in: tempRoot)
        try Self.writeText("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0">
          <entity name="Item" representedClassName="Item">
            <attribute name="name" attributeType="String"/>
            <attribute name="createdAt" attributeType="Date"/>
            <relationship name="owner" destinationEntity="Owner" maxCount="1"/>
          </entity>
          <entity name="Owner" representedClassName="Owner">
            <attribute name="email" attributeType="String"/>
          </entity>
        </model>
        """, to: "Model.xcdatamodeld/Model.xcdatamodel/contents", in: tempRoot)
        try Self.writeText("# Demo App\n", to: "README.md", in: tempRoot)
        try Self.writeText("MIT License\n", to: "LICENSE", in: tempRoot)
        try Self.writeText("name: MyApp\n", to: "project.yml", in: tempRoot)
        try Self.writeText("# Agent Notes\n## Setup\nInstalled dependencies.\n## Build\nBuild failed on first try.\n", to: ".assist_temp/artifacts/agent_notes.md", in: tempRoot)
        try FileManager.default.createDirectory(atPath: (tempRoot as NSString).appendingPathComponent("EmptyDir"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: (tempRoot as NSString).appendingPathComponent("EmptyDD"), withIntermediateDirectories: true)

        let cwd = tempRoot.path
        let stringsOf: (JSONValue?, String) -> [String] = { value, key in
            value?[key]?.arrayValue?.compactMap { $0.stringValue } ?? []
        }

        let manifest = try await Self.run("package_manifest_read", arguments: ["cwd": .string(cwd)], client: client)
        #expect(manifest["name"]?.stringValue == "MyApp")
        #expect(stringsOf(manifest, "platforms") == ["macOS 14", "iOS 17"])
        #expect(stringsOf(manifest, "products") == ["MyApp"])
        #expect(stringsOf(manifest, "targets") == ["MyApp", "MyAppTests"])
        #expect(manifest["dependencies"]?.arrayValue?.first?["url"]?.stringValue == "https://github.com/apple/swift-argument-parser")
        #expect(manifest["dependencies"]?.arrayValue?.first?["from"]?.stringValue == "1.3.0")

        let added = try await Self.run("package_dependency_add", arguments: [
            "cwd": .string(cwd),
            "url": .string("https://github.com/apple/swift-collections"),
            "version": .string("1.1.0"),
            "product": .string("Collections"),
            "target": .string("MyApp"),
        ], client: client)
        #expect(added["added"]?.boolValue == true)
        #expect(added["wired"]?.boolValue == true)
        #expect(try Self.readText("Package.swift", in: tempRoot).contains("https://github.com/apple/swift-collections"))
        #expect(try Self.readText("Package.swift", in: tempRoot).contains(".product(name: \"Collections\", package: \"swift-collections\")"))

        let framework = try await Self.run("framework_linker_auditor", arguments: ["cwd": .string(cwd)], client: client)
        #expect(framework["linkedCount"]?.intValue == 1)
        #expect(framework["linkedFrameworks"]?.arrayValue?.first?["name"]?.stringValue == "Foundation.framework")
        #expect(framework["linkedFrameworks"]?.arrayValue?.first?["weak"]?.boolValue == true)
        #expect(stringsOf(framework, "sdkroots").contains("macosx"))
        #expect(stringsOf(framework, "deploymentTargets").contains("MACOSX_DEPLOYMENT_TARGET 14.0"))

        let signing = try await Self.run("project_signing", arguments: ["cwd": .string(cwd), "threadId": .string("test-thread")], client: client)
        #expect(signing["codeSignStyle"]?.stringValue == "Automatic")
        #expect(signing["developmentTeam"]?.stringValue == "ABCDE12345")
        #expect(signing["bundleIdentifier"]?.stringValue == "com.example.myapp")
        #expect(signing["codeSignIdentity"]?.stringValue == "Apple Development")

        let bundle = try await Self.run("bundle_resource_auditor", arguments: ["cwd": .string(cwd)], client: client)
        #expect(bundle["resources"]?.arrayValue?.count == 1)
        #expect(bundle["resources"]?.arrayValue?.first?["path"]?.stringValue == "Logo.png")
        #expect(bundle["resources"]?.arrayValue?.first?["found"]?.boolValue == true)
        #expect(bundle["missing"]?.arrayValue?.isEmpty == true)
        #expect(bundle["duplicates"]?.arrayValue?.isEmpty == true)

        let podfile = try await Self.run("podfile_inspector", arguments: ["cwd": .string(cwd)], client: client)
        #expect(podfile["platform"]?.stringValue == "ios 17.0")
        #expect(stringsOf(podfile, "targets") == ["MyApp"])
        #expect(podfile["podCount"]?.intValue == 2)
        #expect(podfile["pods"]?.arrayValue?.first?["name"]?.stringValue == "Alamofire")
        #expect(podfile["pods"]?.arrayValue?.first?["requirement"]?.stringValue == "5.9.0")
        #expect(podfile["locked"]?.arrayValue?.count == 2)
        #expect(podfile["lockPresent"]?.boolValue == true)

        let carthage = try await Self.run("carthage_cartfile_inspector", arguments: ["cwd": .string(cwd)], client: client)
        #expect(carthage["dependencyCount"]?.intValue == 2)
        #expect(carthage["dependencies"]?.arrayValue?.first?["name"]?.stringValue == "Alamofire/Alamofire")
        #expect(carthage["dependencies"]?.arrayValue?.first?["requirement"]?.stringValue == "5.9.0")
        #expect(carthage["resolved"]?.arrayValue?.count == 2)
        #expect(carthage["resolvedPresent"]?.boolValue == true)

        let graph = try await Self.run("symbol_reference_graph", arguments: ["cwd": .string(cwd), "symbol": .string("Foo"), "path": .string("Sources")], client: client)
        #expect(graph["definitionCount"]?.intValue == 1)
        #expect(graph["referenceCount"]?.intValue == 1)
        #expect(graph["definitions"]?.arrayValue?.first?["path"]?.stringValue == "Sources/App.swift")

        let audit = try await Self.run("localization_audit", arguments: ["cwd": .string(cwd)], client: client)
        #expect(stringsOf(audit, "locales") == ["en", "fr"])
        #expect(audit["totalKeys"]?.intValue == 3)
        let frMissing = audit["missing"]?.arrayValue?.first { $0["locale"]?.stringValue == "fr" }
        #expect(stringsOf(frMissing, "missingKeys") == ["goodbye", "hello"])
        #expect(stringsOf(audit, "unreferencedKeys") == ["goodbye", "hello"])

        let getWelcome = try await Self.run("strings_localization", arguments: ["cwd": .string(cwd), "path": .string("en.lproj/Localizable.strings"), "action": .string("get"), "key": .string("welcome")], client: client)
        #expect(getWelcome["found"]?.boolValue == true)
        #expect(getWelcome["value"]?.stringValue == "Welcome")
        let setFarewell = try await Self.run("strings_localization", arguments: ["cwd": .string(cwd), "path": .string("en.lproj/Localizable.strings"), "action": .string("set"), "key": .string("farewell"), "value": .string("Farewell")], client: client)
        #expect(setFarewell["updated"]?.boolValue == true)
        let getFarewell = try await Self.run("strings_localization", arguments: ["cwd": .string(cwd), "path": .string("en.lproj/Localizable.strings"), "action": .string("get"), "key": .string("farewell")], client: client)
        #expect(getFarewell["value"]?.stringValue == "Farewell")
        let deleteFarewell = try await Self.run("strings_localization", arguments: ["cwd": .string(cwd), "path": .string("en.lproj/Localizable.strings"), "action": .string("delete"), "key": .string("farewell")], client: client)
        #expect(deleteFarewell["deleted"]?.boolValue == true)
        let getGone = try await Self.run("strings_localization", arguments: ["cwd": .string(cwd), "path": .string("en.lproj/Localizable.strings"), "action": .string("get"), "key": .string("farewell")], client: client)
        #expect(getGone["found"]?.boolValue == false)

        let locList = try await Self.run("localization_manager", arguments: ["cwd": .string(cwd), "action": .string("list")], client: client)
        #expect(stringsOf(locList, "stringsFiles").contains("en.lproj/Localizable.strings"))
        #expect(stringsOf(locList, "stringsFiles").contains("fr.lproj/Localizable.strings"))
        #expect(stringsOf(locList, "catalogs").contains("Localizable.xcstrings"))
        let extracted = try await Self.run("localization_manager", arguments: ["cwd": .string(cwd), "action": .string("extract")], client: client)
        #expect(extracted["keyCount"]?.intValue == 3)
        #expect(extracted["keys"]?["welcome"]?["en"]?.stringValue == "Welcome")
        #expect(extracted["keys"]?["welcome"]?["fr"]?.stringValue == "Bienvenue")
        #expect(extracted["keys"]?["goodbye"]?["en"]?.stringValue == "Goodbye")
        #expect(extracted["keys"]?["hello"]?["en"]?.stringValue == "Hello")
        let addedThanks = try await Self.run("localization_manager", arguments: ["cwd": .string(cwd), "action": .string("add"), "key": .string("thanks"), "value": .string("Thanks"), "path": .string("en.lproj/Localizable.strings")], client: client)
        #expect(addedThanks["updated"]?.boolValue == true)
        #expect(try Self.readText("en.lproj/Localizable.strings", in: tempRoot).contains("\"thanks\" = \"Thanks\";"))

        let migrated = try await Self.run("string_catalog_migrator", arguments: ["cwd": .string(cwd)], client: client)
        #expect(migrated["count"]?.intValue == 2)
        #expect(migrated["migrated"]?.arrayValue?.allSatisfy { $0["verified"]?.boolValue == true } == true)
        #expect(migrated["skipped"]?.arrayValue?.isEmpty == true)
        #expect(try Self.readText("en.lproj/Localizable.xcstrings", in: tempRoot).contains("thanks"))

        let statusBefore = try await Self.run("localize_app", arguments: ["cwd": .string(cwd), "action": .string("status")], client: client)
        #expect(statusBefore["exists"]?.boolValue == true)
        #expect(statusBefore["keyCount"]?.intValue == 1)
        #expect(stringsOf(statusBefore, "locales") == ["en"])
        let localized = try await Self.run("localize_app", arguments: [
            "cwd": .string(cwd),
            "action": .string("localize"),
            "languages": .array([.string("fr"), .string("de")]),
            "translations": .array([.object(["locale": .string("fr"), "key": .string("welcome"), "value": .string("Bienvenue")])]),
        ], client: client)
        #expect(localized["keysAdded"]?.intValue == 2)
        #expect(localized["layoutDirection"]?.stringValue == "ltr")
        let statusAfter = try await Self.run("localize_app", arguments: ["cwd": .string(cwd), "action": .string("status")], client: client)
        #expect(statusAfter["keyCount"]?.intValue == 3)
        #expect(stringsOf(statusAfter, "locales").contains("fr"))
        #expect(stringsOf(statusAfter, "locales").contains("de"))
        #expect(stringsOf(statusAfter, "locales").contains("en"))

        let plistName = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("get"), "key": .string("CFBundleName")], client: client)
        #expect(plistName["found"]?.boolValue == true)
        #expect(plistName["value"]?.stringValue == "Demo")
        let plistLocales = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("get"), "key": .string("CFBundleLocalizations")], client: client)
        #expect(stringsOf(plistLocales, "value") == ["fr", "de"])
        let plistRegion = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("get"), "key": .string("CFBundleDevelopmentRegion")], client: client)
        #expect(plistRegion["value"]?.stringValue == "en")
        let plistSet = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("set"), "key": .string("CFBundleVersion"), "value": .string("2")], client: client)
        #expect(plistSet["updated"]?.boolValue == true)
        let plistVersion = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("get"), "key": .string("CFBundleVersion")], client: client)
        #expect(plistVersion["value"]?.intValue == 2)
        let plistDelete = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("delete"), "key": .string("CFBundleVersion")], client: client)
        #expect(plistDelete["deleted"]?.boolValue == true)
        let plistGone = try await Self.run("project_info_plist", arguments: ["cwd": .string(cwd), "action": .string("get"), "key": .string("CFBundleVersion")], client: client)
        #expect(plistGone["found"]?.boolValue == false)

        let entitlements = try await Self.run("project_entitlements", arguments: ["cwd": .string(cwd)], client: client)
        #expect(entitlements["entitlements"]?["com.apple.security.app-sandbox"]?.boolValue == true)
        #expect(entitlements["entitlements"]?["com.apple.security.network.client"]?.boolValue == false)

        let capsList = try await Self.run("project_capabilities", arguments: ["cwd": .string(cwd), "action": .string("list")], client: client)
        #expect(stringsOf(capsList, "enabled").contains("app-sandbox"))
        #expect(stringsOf(capsList, "disabled").contains("network-client"))
        #expect(capsList["otherEntitlements"]?.arrayValue?.contains { $0["key"]?.stringValue == "com.apple.application-identifier" } == true)
        let capsEnable = try await Self.run("project_capabilities", arguments: ["cwd": .string(cwd), "action": .string("enable"), "capability": .string("network-client")], client: client)
        #expect(capsEnable["enabled"]?.boolValue == true)
        let capsListAfterEnable = try await Self.run("project_capabilities", arguments: ["cwd": .string(cwd), "action": .string("list")], client: client)
        #expect(stringsOf(capsListAfterEnable, "enabled").contains("network-client"))
        let capsDisable = try await Self.run("project_capabilities", arguments: ["cwd": .string(cwd), "action": .string("disable"), "capability": .string("app-sandbox")], client: client)
        #expect(capsDisable["enabled"]?.boolValue == false)
        await #expect(throws: SystemToolError.executionFailed(tool: "project_capabilities", message: "Capability bogus-capability is not a boolean entitlement capability. Supported: app-sandbox, audio-input, bluetooth, camera, files-downloads-read-only, files-downloads-read-write, files-user-selected-read-only, files-user-selected-read-write, network-client, network-server, printing, usb.")) {
            try await Self.run("project_capabilities", arguments: ["cwd": .string(cwd), "action": .string("enable"), "capability": .string("bogus-capability")], client: client)
        }

        let entList = try await Self.run("entitlements_manager", arguments: ["cwd": .string(cwd), "action": .string("list")], client: client)
        #expect(entList["entitlements"]?["com.apple.security.network.client"]?.boolValue == true)
        let entAdd = try await Self.run("entitlements_manager", arguments: ["cwd": .string(cwd), "action": .string("add"), "key": .string("com.apple.security.device.camera"), "value": .string("true")], client: client)
        #expect(entAdd["updated"]?.boolValue == true)
        let entRemove = try await Self.run("entitlements_manager", arguments: ["cwd": .string(cwd), "action": .string("remove"), "key": .string("com.apple.security.device.camera")], client: client)
        #expect(entRemove["removed"]?.boolValue == true)

        let colorset = try await Self.run("colorset_builder", arguments: ["cwd": .string(cwd), "name": .string("Accent"), "lightHex": .string("#FF8800")], client: client)
        #expect(colorset["verified"]?.boolValue == true)
        #expect(try Self.readText("Assets.xcassets/Accent.colorset/Contents.json", in: tempRoot).contains("1.000"))

        let imageAdded = try await Self.run("asset_image_add", arguments: ["cwd": .string(cwd), "imageName": .string("Hero"), "source": .string("Sources/hero.png")], client: client)
        #expect(imageAdded["verified"]?.boolValue == true)
        #expect(imageAdded["set"]?.stringValue == "Assets.xcassets/Hero.imageset")

        let catalogList = try await Self.run("asset_catalog_manager", arguments: ["cwd": .string(cwd), "action": .string("list")], client: client)
        #expect(stringsOf(catalogList, "catalogs") == ["Assets.xcassets"])
        let catalogInspect = try await Self.run("asset_catalog_manager", arguments: ["cwd": .string(cwd), "action": .string("inspect"), "name": .string("Logo.imageset")], client: client)
        #expect(catalogInspect["contents"]?.stringValue?.contains("Logo.png") == true)
        let createdImageset = try await Self.run("asset_catalog_manager", arguments: ["cwd": .string(cwd), "action": .string("create_imageset"), "name": .string("Badge"), "source": .string("Sources/hero.png")], client: client)
        #expect(createdImageset["created"]?.boolValue == true)
        let createdColorset = try await Self.run("asset_catalog_manager", arguments: ["cwd": .string(cwd), "action": .string("create_colorset"), "name": .string("Brand"), "lightHex": .string("#112233"), "darkHex": .string("#445566")], client: client)
        #expect(createdColorset["created"]?.boolValue == true)

        let catalogs = try await Self.run("asset_catalog_list", arguments: ["cwd": .string(cwd)], client: client)
        #expect(catalogs["catalogCount"]?.intValue == 1)
        #expect(catalogs["catalogs"]?.arrayValue?.first?["imageSets"]?.intValue == 3)
        #expect(catalogs["catalogs"]?.arrayValue?.first?["colorSets"]?.intValue == 2)
        #expect(catalogs["catalogs"]?.arrayValue?.first?["iconSets"]?.intValue == 1)

        let entries = try await Self.run("entry_points_discover", arguments: ["cwd": .string(cwd), "path": .string("Sources")], client: client)
        #expect(entries["count"]?.intValue == 2)
        #expect(entries["entryPoints"]?.arrayValue?.contains { $0["kind"]?.stringValue == "main" && $0["path"]?.stringValue == "Sources/App.swift" } == true)
        #expect(entries["entryPoints"]?.arrayValue?.contains { $0["kind"]?.stringValue == "mainSwift" && $0["path"]?.stringValue == "Sources/main.swift" } == true)

        let overview = try await Self.run("repo_overview", arguments: ["cwd": .string(cwd)], client: client)
        #expect((overview["fileCount"]?.intValue ?? 0) >= 15)
        #expect(overview["hasReadme"]?.boolValue == true)
        #expect(overview["hasLicense"]?.boolValue == true)
        #expect(overview["languages"]?.arrayValue?.contains { $0["language"]?.stringValue == "Swift" && ($0["files"]?.intValue ?? 0) >= 4 } == true)
        #expect((overview["largestFiles"]?.arrayValue?.isEmpty ?? true) == false)

        let structure = try await Self.run("project_structure_map", arguments: ["cwd": .string(cwd)], client: client)
        #expect(structure["directories"]?.arrayValue?.contains { $0["path"]?.stringValue == "Sources" && ($0["files"]?.intValue ?? 0) >= 3 } == true)
        #expect(stringsOf(structure, "targets") == ["MyApp"])

        let recent = try await Self.run("recent_changes", arguments: ["cwd": .string(cwd), "hours": .int(24)], client: client)
        #expect(recent["files"]?.arrayValue?.contains { $0["path"]?.stringValue == "Sources/App.swift" } == true)

        let readme = try await Self.run("readme_locate", arguments: ["cwd": .string(cwd)], client: client)
        #expect(readme["count"]?.intValue == 1)
        #expect(readme["readmes"]?.arrayValue?.first?["title"]?.stringValue == "Demo App")

        let licenses = try await Self.run("dependency_licenses", arguments: ["cwd": .string(cwd)], client: client)
        #expect(licenses["count"]?.intValue == 4)
        #expect(licenses["hasLicenseFile"]?.boolValue == true)
        #expect(licenses["dependencies"]?.arrayValue?.contains { $0["name"]?.stringValue == "swift-argument-parser" && $0["source"]?.stringValue == "Package.resolved" } == true)
        #expect(licenses["dependencies"]?.arrayValue?.contains { $0["name"]?.stringValue == "Alamofire" && $0["source"]?.stringValue == "Podfile.lock" } == true)

        let stale = try await Self.run("stale_files_report", arguments: ["cwd": .string(cwd), "days": .int(1)], client: client)
        #expect(stale["files"]?.arrayValue?.contains { $0["path"]?.stringValue == "Sources/App.swift" } == false)

        let breakdown = try await Self.run("file_type_breakdown", arguments: ["cwd": .string(cwd)], client: client)
        #expect(breakdown["types"]?.arrayValue?.contains { $0["extension"]?.stringValue == ".swift" && ($0["files"]?.intValue ?? 0) >= 4 } == true)

        let empty = try await Self.run("empty_dirs_find", arguments: ["cwd": .string(cwd)], client: client)
        #expect(stringsOf(empty, "emptyDirectories").contains("EmptyDir"))

        let links = try await Self.run("symlink_audit", arguments: ["cwd": .string(cwd)], client: client)
        #expect(links["count"]?.intValue == 2)
        #expect(links["brokenCount"]?.intValue == 1)
        #expect(links["links"]?.arrayValue?.contains { $0["path"]?.stringValue == "Sources/BrokenLink" && $0["broken"]?.boolValue == true } == true)
        #expect(links["links"]?.arrayValue?.contains { $0["path"]?.stringValue == "Sources/LinkToApp" && $0["broken"]?.boolValue == false } == true)

        let executables = try await Self.run("executable_files_scan", arguments: ["cwd": .string(cwd)], client: client)
        #expect(executables["executables"]?.arrayValue?.contains { $0["path"]?.stringValue == "Sources/run.sh" } == true)

        let sizes = try await Self.run("dir_size_report", arguments: ["cwd": .string(cwd)], client: client)
        #expect(sizes["directories"]?.arrayValue?.contains { $0["directory"]?.stringValue == "Sources" } == true)
        #expect((sizes["totalBytes"]?.intValue ?? 0) > 0)

        let images = try await Self.run("image_asset_size_report", arguments: ["cwd": .string(cwd), "maxKilobytes": .int(1)], client: client)
        #expect(images["count"]?.intValue == 1)
        #expect(images["images"]?.arrayValue?.first?["path"]?.stringValue == "Assets.xcassets/Logo.imageset/Logo.png")
        #expect(images["images"]?.arrayValue?.first?["sizeBytes"]?.intValue == 2048)

        let coreData = try await Self.run("core_data_model_inspector", arguments: ["cwd": .string(cwd)], client: client)
        #expect(coreData["modelCount"]?.intValue == 1)
        #expect(coreData["models"]?.arrayValue?.first?["entityCount"]?.intValue == 2)
        let itemEntity = coreData["models"]?.arrayValue?.first?["entities"]?.arrayValue?.first { $0["name"]?.stringValue == "Item" }
        #expect(itemEntity?["attributes"]?.arrayValue?.count == 2)
        #expect(itemEntity?["relationships"]?.arrayValue?.first?["destination"]?.stringValue == "Owner")

        let schema = try await Self.run("swift_data_schema_auditor", arguments: ["cwd": .string(cwd)], client: client)
        #expect(schema["modelCount"]?.intValue == 2)
        #expect(schema["issues"]?.arrayValue?.count == 1)
        #expect(schema["issues"]?.arrayValue?.first?.stringValue?.contains("Owner") == true)
        #expect(schema["models"]?.arrayValue?.contains { $0["model"]?.stringValue == "Item" && ($0["relationships"]?.arrayValue?.count ?? 0) == 1 } == true)

        let privacy = try await Self.run("privacy_manifest_auditor", arguments: ["cwd": .string(cwd)], client: client)
        #expect(privacy["tracking"]?.boolValue == false)
        #expect(privacy["collectedDataTypes"]?.intValue == 1)
        #expect(privacy["accessedApiTypes"]?.intValue == 2)
        #expect(privacy["issueCount"]?.intValue == 0)

        let systems = try await Self.run("build_system_detect", arguments: ["cwd": .string(cwd)], client: client)
        #expect(systems["count"]?.intValue == 5)
        let systemNames = systems["systems"]?.arrayValue?.compactMap { $0["system"]?.stringValue } ?? []
        #expect(systemNames.contains("xcodeproj"))
        #expect(systemNames.contains("SwiftPM"))
        #expect(systemNames.contains("CocoaPods"))
        #expect(systemNames.contains("Carthage"))
        #expect(systemNames.contains("xcodegen"))

        let progress = try await Self.run("session_progress_report", arguments: ["cwd": .string(cwd)], client: client)
        #expect(progress["found"]?.boolValue == true)
        #expect(progress["phases"]?.arrayValue?.compactMap { $0["title"]?.stringValue } == ["Setup", "Build"])
        #expect(progress["failures"]?.arrayValue?.contains { $0.stringValue == "Build failed on first try." } == true)

        let env = try await Self.run("env_info", arguments: [:], client: client)
        #expect((env["arch"]?.stringValue?.isEmpty ?? true) == false)
        #expect((env["cpuCount"]?.intValue ?? 0) > 0)
        #expect((env["physicalMemoryBytes"]?.intValue ?? 0) > 0)
        #expect((env["hostName"]?.stringValue?.isEmpty ?? true) == false)

        let derived = try await Self.run("derived_data_locate", arguments: ["path": .string(cwd + "/EmptyDD")], client: client)
        #expect(derived["exists"]?.boolValue == true)
        #expect(derived["directories"]?.arrayValue?.isEmpty == true)
        #expect(derived["totalBytes"]?.intValue == 0)
        #expect(derived["path"]?.stringValue?.hasSuffix("/EmptyDD") == true)

        let envList = try await Self.run("environment_variable_manager", arguments: ["action": .string("list")], client: client)
        #expect(stringsOf(envList, "keys").contains("PATH"))
        let envGet = try await Self.run("environment_variable_manager", arguments: ["action": .string("get"), "key": .string("PATH")], client: client)
        #expect(envGet["found"]?.boolValue == true)
        #expect((envGet["value"]?.stringValue?.isEmpty ?? true) == false)
        let envMissing = try await Self.run("environment_variable_manager", arguments: ["action": .string("get"), "key": .string("DEFINITELY_NOT_SET_XYZ")], client: client)
        #expect(envMissing["found"]?.boolValue == false)

        let lookup = try await Self.run("tool_capability_lookup", arguments: ["tool": .string("read_file")], client: client)
        #expect(lookup["action"]?.stringValue == "workspace.read_file")
        #expect(lookup["channel"]?.stringValue == "desktop")
        #expect(lookup["parameters"]?.arrayValue?.contains { $0["name"]?.stringValue == "cwd" } == true)

        _ = try await Self.run("manage_memory", arguments: ["action": .string("store"), "key": .string("slice14-memory"), "value": .string("remember this"), "scope": .string("test")], client: client)
        let listed = try await Self.run("manage_memory", arguments: ["action": .string("list"), "scope": .string("test")], client: client)
        #expect(listed.arrayValue?.contains { $0["key"]?.stringValue == "slice14-memory" && $0["value"]?.stringValue == "remember this" } == true)
        _ = try await Self.run("manage_memory", arguments: ["action": .string("delete"), "key": .string("slice14-memory"), "scope": .string("test")], client: client)
        let listedAfterDelete = try await Self.run("manage_memory", arguments: ["action": .string("list"), "scope": .string("test")], client: client)
        #expect(listedAfterDelete.arrayValue?.contains { $0["key"]?.stringValue == "slice14-memory" } == false)

        let skills = try await Self.run("search_skills", arguments: ["query": .string("system"), "limit": .int(5)], client: client)
        #expect(skills["searched"]?.stringValue == "bundled SystemAssets index")
        #expect(skills["results"]?.arrayValue != nil)

        await #expect(throws: SystemToolError.executionFailed(tool: "use_app", message: "use_app action activate has no engine tool; the capability is not implemented.")) {
            try await Self.run("use_app", arguments: ["threadId": .string("test-thread"), "action": .string("activate")], client: client)
        }

        await client.close()
    }

    @Test("Memory store round-trips per entry and delete leaves siblings")
    func memoryStorePerEntryRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        _ = try await Self.run("mem_store", arguments: ["key": .string("slice15-alpha"), "value": .string("one")], client: client)
        _ = try await Self.run("mem_store", arguments: ["key": .string("slice15-beta"), "value": .string("two")], client: client)
        let retrieved = try await Self.run("mem_retrieve", arguments: ["key": .string("slice15-alpha")], client: client)
        #expect(retrieved["value"]?.stringValue == "one")
        let deleted = try await Self.run("mem_delete", arguments: ["key": .string("slice15-alpha")], client: client)
        #expect(deleted["deleted"]?.boolValue == true)
        let survivor = try await Self.run("mem_retrieve", arguments: ["key": .string("slice15-beta")], client: client)
        #expect(survivor["value"]?.stringValue == "two")
        var deletedRetrieveFailed = false
        do {
            _ = try await Self.run("mem_retrieve", arguments: ["key": .string("slice15-alpha")], client: client)
        } catch {
            deletedRetrieveFailed = true
        }
        #expect(deletedRetrieveFailed)
        await client.close()
    }

    @Test("Slice 14: invalid Slice 14 arguments are refused before any runtime call")
    func sliceFourteenValidationRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path

        await #expect(throws: SystemToolError.missingArgument(tool: "package_dependency_add", argument: "url")) {
            try await Self.run("package_dependency_add", arguments: ["cwd": .string(cwd), "version": .string("1.0.0")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "package_dependency_add", message: "package_dependency_add url must be an https or git@ URL.")) {
            try await Self.run("package_dependency_add", arguments: ["cwd": .string(cwd), "url": .string("ftp://example.com/x.git"), "version": .string("1.0.0")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "colorset_builder", message: "Color hex must be #RRGGBB, for example #FF8800.")) {
            try await Self.run("colorset_builder", arguments: ["cwd": .string(cwd), "name": .string("Bad"), "lightHex": .string("#XYZ")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "strings_localization", message: "strings_localization action must be get, set, or delete.")) {
            try await Self.run("strings_localization", arguments: ["cwd": .string(cwd), "path": .string("en.lproj/Localizable.strings"), "action": .string("bogus"), "key": .string("welcome")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "environment_variable_manager", message: "environment_variable_manager action must be list or get. The process environment cannot be mutated by a tool; use a terminal export instead.")) {
            try await Self.run("environment_variable_manager", arguments: ["action": .string("set"), "key": .string("FOO"), "value": .string("bar")], client: client)
        }
        await #expect(throws: SystemToolError.missingArgument(tool: "manage_memory", argument: "confirm")) {
            try await Self.run("manage_memory", arguments: ["action": .string("clear"), "scope": .string("test")], client: client)
        }
        await #expect(throws: SystemToolError.missingArgument(tool: "use_app", argument: "action")) {
            try await Self.run("use_app", arguments: ["threadId": .string("test-thread")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "fetch_documentation", message: "fetch_documentation url must be an https URL on developer.apple.com.")) {
            try await Self.run("fetch_documentation", arguments: ["threadId": .string("test-thread"), "url": .string("https://example.com/x")], client: client)
        }
        await #expect(throws: SystemToolError.missingArgument(tool: "fetch_documentation", argument: "query")) {
            try await Self.run("fetch_documentation", arguments: ["threadId": .string("test-thread")], client: client)
        }
        await #expect(throws: SystemToolError.missingArgument(tool: "github_repo", argument: "owner")) {
            try await Self.run("github_repo", arguments: ["threadId": .string("test-thread"), "operation": .string("repository_info")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "localization_manager", message: "localization_manager add path must end in .strings or .xcstrings.")) {
            try await Self.run("localization_manager", arguments: ["cwd": .string(cwd), "action": .string("add"), "key": .string("x"), "value": .string("y"), "path": .string("notes.txt")], client: client)
        }

        await client.close()
    }

    @Test("Slice 18 tools register with their real backend actions")
    func sliceEighteenToolsRegister() {
        let expected: [(String, String, SystemToolChannel)] = [
            ("svg_to_png", "terminal.create", .engine),
            ("intel_generate_tests", "workspace.write_file", .desktop),
            ("search_web", "web.fetch", .desktop),
            ("reverse_analyze", "terminal.create", .engine),
            ("report_to_user", "workspace.write_file", .desktop),
            ("intel_explain_code", "workspace.read_file", .desktop),
        ]
        #expect(expected.count == 6)
        for (name, action, channel) in expected {
            guard let definition = SystemToolRegistry.definition(named: name, for: .system) else {
                Issue.record("Slice 18 tool missing from registry: \(name)")
                continue
            }
            #expect(definition.action == action)
            #expect(definition.channel == channel)
            #expect(!definition.parameters.isEmpty)
            #expect(definition.parameters.contains { $0.required })
        }
        #expect(SystemToolRegistry.definition(named: "svg_to_png", for: .system)?.parameters.map(\.name) == ["threadId", "cwd", "path", "output", "width", "height"])
        #expect(SystemToolRegistry.definition(named: "intel_generate_tests", for: .system)?.parameters.map(\.name) == ["cwd", "path", "testPath", "module", "overwrite"])
        #expect(SystemToolRegistry.definition(named: "search_web", for: .system)?.parameters.map(\.name) == ["threadId", "query", "maxResults"])
        #expect(SystemToolRegistry.definition(named: "reverse_analyze", for: .system)?.parameters.map(\.name) == ["threadId", "path", "inspection", "symbol", "cwd", "timeoutSeconds"])
        #expect(SystemToolRegistry.definition(named: "report_to_user", for: .system)?.parameters.map(\.name) == ["cwd", "summary", "path", "title"])
        #expect(SystemToolRegistry.definition(named: "intel_explain_code", for: .system)?.parameters.map(\.name) == ["cwd", "path"])
        #expect(SystemToolRegistry.definition(named: "svg_to_png", for: .system)?.description.contains("Output is PNG only; complex SVGs can distort at small sizes.") == true)
        #expect(SystemToolRegistry.definition(named: "intel_generate_tests", for: .system)?.description.contains("template stubs from regex-extracted symbols, not LLM-written tests") == true)
        #expect(SystemToolRegistry.definition(named: "search_web", for: .system)?.description.contains("unofficial DuckDuckGo HTML scraping, no search API; results may be empty if DDG blocks or changes markup; failure is reported, never faked") == true)
        #expect(SystemToolRegistry.definition(named: "reverse_analyze", for: .system)?.description.contains("it is a composition of the named CLI inspections, not the REA subsystem") == true)
        #expect(SystemToolRegistry.definition(named: "report_to_user", for: .system)?.description.contains("the chat reply itself is the actual delivery to the user; the tool records the summary and marks the turn complete, it does not deliver out-of-band") == true)
        #expect(SystemToolRegistry.definition(named: "intel_explain_code", for: .system)?.description.contains("structural overview from regex scans, not an LLM explanation") == true)
    }

    @Test("Slice 22: per-tool parameter descriptions are pinned as the cross-check source of truth")
    func sliceTwentyTwoParamDescriptionsPinned() {
        let expected: [(tool: String, param: String, description: String)] = [
            ("run_build", "threadId", "Owning thread ID, pinned to the session thread when bound; the terminal starts in the thread working directory."),
            ("run_tests", "threadId", "Owning thread ID, pinned to the session thread when bound; the terminal starts in the thread working directory."),
            ("svg_to_png", "path", "SVG file path relative to the working directory."),
            ("intel_generate_tests", "path", "Swift source file or directory relative to the working directory."),
            ("search_web", "threadId", "Owning thread ID, pinned to the session thread when bound. Only used by the MCP server path."),
            ("intel_explain_code", "path", "Source file relative to the working directory."),
        ]
        for (tool, param, description) in expected {
            let actual = SystemToolRegistry.definition(named: tool, for: .system)?.parameters.first { $0.name == param }?.description
            #expect(actual == description)
        }
    }

    @Test("Slice 18: intel_generate_tests emits one stub per symbol and refuses overwrite")
    func sliceEighteenGenerateTestsRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("public struct Widget {\n    public func make() -> Int {\n        return 1\n    }\n}\n", to: "Widget.swift", in: tempRoot)
        let generated = try await Self.run("intel_generate_tests", arguments: ["cwd": .string(cwd), "path": .string("Widget.swift"), "testPath": .string("WidgetTests.swift"), "module": .string("Demo")], client: client)
        #expect(generated["symbols"]?.intValue == 2)
        #expect(generated["tests"]?.intValue == 2)
        let content = try Self.readText("WidgetTests.swift", in: tempRoot)
        #expect(content.contains("func testWidget()"))
        #expect(content.contains("func testMake()"))
        #expect(content.contains("@testable import Demo"))
        do {
            _ = try await Self.run("intel_generate_tests", arguments: ["cwd": .string(cwd), "path": .string("Widget.swift"), "testPath": .string("WidgetTests.swift"), "module": .string("Demo")], client: client)
            Issue.record("Expected executionFailed for intel_generate_tests over an existing file")
        } catch let error as SystemToolError {
            #expect(error == .executionFailed(tool: "intel_generate_tests", message: "A file already exists at that path; use write_file to overwrite it."))
        } catch {
            Issue.record("Unexpected error for intel_generate_tests over an existing file: \(error)")
        }
        let overwritten = try await Self.run("intel_generate_tests", arguments: ["cwd": .string(cwd), "path": .string("Widget.swift"), "testPath": .string("WidgetTests.swift"), "module": .string("Demo"), "overwrite": .bool(true)], client: client)
        #expect(overwritten["tests"]?.intValue == 2)
        await client.close()
    }

    @Test("Slice 18: report_to_user appends completion records to agent_notes.md")
    func sliceEighteenReportToUserRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        let first = try await Self.run("report_to_user", arguments: ["cwd": .string(cwd), "summary": .string("Finished the thing.")], client: client)
        #expect(first["completed"]?.boolValue == true)
        #expect(first["path"]?.stringValue == ".assist_temp/artifacts/agent_notes.md")
        let second = try await Self.run("report_to_user", arguments: ["cwd": .string(cwd), "summary": .string("Second note."), "title": .string("Done")], client: client)
        #expect(second["completed"]?.boolValue == true)
        let notes = try Self.readText(".assist_temp/artifacts/agent_notes.md", in: tempRoot)
        #expect(notes.contains("Finished the thing."))
        #expect(notes.contains("Second note."))
        #expect(notes.contains("## Completion"))
        #expect(notes.contains("## Done"))
        #expect(notes.contains("seconds since the Unix epoch") == false)
        #expect(notes.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"#, options: .regularExpression) != nil)
        await client.close()
    }

    @Test("Slice 18: intel_explain_code composes summary, API surface, and doc comments")
    func sliceEighteenExplainCodeRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("public struct Widget {\n    /// Makes a widget.\n    public func make() {}\n}", to: "Widget.swift", in: tempRoot)
        let explained = try await Self.run("intel_explain_code", arguments: ["cwd": .string(cwd), "path": .string("Widget.swift")], client: client)
        #expect(explained["lines"]?.intValue == 4)
        #expect(explained["codeLines"]?.intValue == 3)
        #expect(explained["commentLines"]?.intValue == 1)
        #expect(explained["blankLines"]?.intValue == 0)
        #expect(explained["publicDeclarationCount"]?.intValue == 2)
        #expect(explained["docCommentCount"]?.intValue == 1)
        await client.close()
    }

    @Test("Slice 18: invalid Slice 18 arguments are refused before any runtime call")
    func sliceEighteenInvalidArgumentsRefused() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cwd = tempRoot.path
        try Self.writeText("let x = 1\n", to: "Empty.swift", in: tempRoot)
        await #expect(throws: SystemToolError.executionFailed(tool: "svg_to_png", message: "svg_to_png path must end in .svg.")) {
            try await Self.run("svg_to_png", arguments: ["threadId": .string("test-thread"), "cwd": .string(cwd), "path": .string("photo.png")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "svg_to_png", message: "svg_to_png width must be 1 to 4096.")) {
            try await Self.run("svg_to_png", arguments: ["threadId": .string("test-thread"), "cwd": .string(cwd), "path": .string("icon.svg"), "width": .int(0)], client: client)
        }
        await #expect(throws: SystemToolError.missingArgument(tool: "search_web", argument: "query")) {
            try await Self.run("search_web", arguments: ["threadId": .string("test-thread")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "reverse_analyze", message: "reverse_analyze inspection must be artifact, disassembly, demangle, or sqlite_schema. REA evidence IDs and confidence scores are unavailable because the REA subsystem does not exist, and Go or managed-metadata inspection is not supported.")) {
            try await Self.run("reverse_analyze", arguments: ["threadId": .string("test-thread"), "path": .string("app.bin"), "inspection": .string("rea_evidence")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "intel_generate_tests", message: "No symbols found in Empty.swift; no test stubs were written.")) {
            try await Self.run("intel_generate_tests", arguments: ["cwd": .string(cwd), "path": .string("Empty.swift"), "testPath": .string("EmptyTests.swift"), "module": .string("Demo")], client: client)
        }
        await #expect(throws: SystemToolError.executionFailed(tool: "report_to_user", message: "report_to_user summary must not be empty.")) {
            try await Self.run("report_to_user", arguments: ["cwd": .string(cwd), "summary": .string("   ")], client: client)
        }
        await client.close()
    }

    @Test("write_file writes real content through execute()")
    func writeFileWritesRealContent() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let written = try await Self.run(
            "write_file",
            arguments: ["cwd": .string(tempRoot.path), "path": .string("notes/hello.txt"), "content": .string("hello through the registry\n")],
            client: client
        )
        #expect(written["path"]?.stringValue == "notes/hello.txt")
        #expect(try Self.readText("notes/hello.txt", in: tempRoot) == "hello through the registry\n")
        await client.close()
    }

    @Test("read_file reads real content through execute()")
    func readFileReadsRealContent() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try Self.writeText("alpha\nbeta\n", to: "docs/readme.txt", in: tempRoot)
        let read = try await Self.run(
            "read_file",
            arguments: ["cwd": .string(tempRoot.path), "path": .string("docs/readme.txt")],
            client: client
        )
        #expect(read["path"]?.stringValue == "docs/readme.txt")
        #expect(read["content"]?.stringValue == "alpha\nbeta\n")
        await client.close()
    }

    @Test("search_files finds a real token through execute()")
    func searchFilesFindsRealToken() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try Self.writeText("first line\nlet marker = \"Slice148SearchToken\"\nlast line\n", to: "Sources/Store.swift", in: tempRoot)
        try Self.writeText("nothing to see here\n", to: "Sources/Other.swift", in: tempRoot)
        let hits = try await Self.run(
            "search_files",
            arguments: ["cwd": .string(tempRoot.path), "query": .string("Slice148SearchToken")],
            client: client
        )
        let rows = hits.arrayValue ?? []
        #expect(rows.count == 1)
        #expect(rows[0]["path"]?.stringValue == "Sources/Store.swift")
        #expect(rows[0]["lineNumber"]?.intValue == 2)
        #expect(rows[0]["lineText"]?.stringValue?.contains("Slice148SearchToken") == true)
        await client.close()
    }

    @Test("create_terminal returns a live terminal id through execute()")
    func createTerminalReturnsLiveId() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "Slice148Terminal")
        let threadID = try await client.newThread(projectID: projectID)
        let created = try await Self.run(
            "create_terminal",
            arguments: ["threadId": .string(threadID.uuidString)],
            client: client
        )
        guard let terminalId = created.stringValue, !terminalId.isEmpty else {
            Issue.record("Expected a non-empty terminal id, got \(created)")
            await client.close()
            return
        }
        let viewport = try await client.readTerminalViewport(id: terminalId, dark: true)
        #expect(viewport.rows > 0)
        #expect(viewport.cols > 0)
        try await client.closeTerminal(id: terminalId)
        await client.close()
    }

    @Test("write_terminal and read_terminal round-trip text through execute()")
    func writeAndReadTerminalRoundTrip() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectID = try await client.createProject(path: projectDir.path, name: "Slice148Terminal")
        let threadID = try await client.newThread(projectID: projectID)
        let created = try await Self.run(
            "create_terminal",
            arguments: ["threadId": .string(threadID.uuidString)],
            client: client
        )
        guard let terminalId = created.stringValue, !terminalId.isEmpty else {
            Issue.record("Expected a non-empty terminal id, got \(created)")
            await client.close()
            return
        }
        let written = try await Self.run(
            "write_terminal",
            arguments: ["terminalId": .string(terminalId), "text": .string("echo hello-terminal-148\n")],
            client: client
        )
        #expect(written["terminalId"]?.stringValue == terminalId)
        var sawEcho = false
        for _ in 0..<60 {
            let snapshot = try await Self.run(
                "read_terminal",
                arguments: ["terminalId": .string(terminalId)],
                client: client
            )
            let lines = snapshot["lines"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if lines.joined(separator: "\n").contains("hello-terminal-148") {
                sawEcho = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(sawEcho)
        try await client.closeTerminal(id: terminalId)
        await client.close()
    }


    private static func assistant(
        id: UUID = UUID(),
        profile: RemoteAssistant.PermissionProfile
    ) -> RemoteAssistant {
        RemoteAssistant(
            id: id,
            name: "Profile Probe",
            category: .codeReviewSecurity,
            systemPrompt: "Probe.",
            permissionProfile: profile
        )
    }

    private static func expectProfileDenied(
        _ tool: String,
        arguments: [String: JSONValue],
        profile: AssistantPermissionProfile,
        client: AgentsRuntimeClient
    ) async {
        do {
            _ = try await SystemToolRegistry.execute(
                tool, arguments: arguments, toolset: .system, runtime: client, permissionProfile: profile
            )
            Issue.record("Expected toolNotActive error for \(tool) under \(profile)")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: tool, toolset: .system))
        } catch {
            Issue.record("Unexpected error for \(tool): \(error)")
        }
    }

    @Test("Read-only profile denies write tools before any dispatch")
    func readOnlyProfileDeniesWriteTools() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let denied: [String] = [
            "write_file", "edit_file", "delete_file", "git_commit", "create_terminal",
            "use_terminal", "mem_store", "use_app", "use_workers", "simulator_boot",
            "code_snippet_manager", "string_catalog_migrator", "write_terminal", "run_build",
        ]
        for tool in denied {
            await Self.expectProfileDenied(tool, arguments: [:], profile: .readOnly, client: client)
        }
        let probe = tempRoot.appendingPathComponent("probe.txt")
        await Self.expectProfileDenied(
            "write_file",
            arguments: [
                "cwd": .string(tempRoot.path),
                "path": .string("probe.txt"),
                "content": .string("must not land"),
            ],
            profile: .readOnly,
            client: client
        )
        #expect(!FileManager.default.fileExists(atPath: probe.path))
        await client.close()
    }

    @Test("Read-only profile allows read tools")
    func readOnlyProfileAllowsReadTools() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let listed = try await SystemToolRegistry.execute(
            "view_memory",
            arguments: ["scope": .string("global")],
            toolset: .system, runtime: client, permissionProfile: .readOnly
        )
        #expect(listed.arrayValue != nil)
        let files = try await SystemToolRegistry.execute(
            "list_files",
            arguments: ["cwd": .string(tempRoot.path)],
            toolset: .system, runtime: client, permissionProfile: .readOnly
        )
        #expect(files.arrayValue != nil)
        _ = try await SystemToolRegistry.execute(
            "write_file",
            arguments: [
                "cwd": .string(tempRoot.path),
                "path": .string("seed.txt"),
                "content": .string("seed"),
            ],
            toolset: .system, runtime: client
        )
        let read = try await SystemToolRegistry.execute(
            "read_file",
            arguments: ["cwd": .string(tempRoot.path), "path": .string("seed.txt")],
            toolset: .system, runtime: client, permissionProfile: .readOnly
        )
        #expect(read["content"]?.stringValue == "seed")
        await client.close()
    }

    @Test("Approval-required profile denies terminal, git-mutating, and delete tools")
    func approvalRequiredProfileDeniesRiskyTools() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let denied: [String] = [
            "use_terminal", "run_build", "create_terminal", "project_build", "write_terminal",
            "image_get_dimensions", "simulator_list", "project_clean",
            "git_push", "git_commit", "git_branch_create", "version_control_operator",
            "git_stash_operator", "git_bisect",
            "delete_file", "mem_clear", "delete_worker", "test_snapshot_manage",
        ]
        for tool in denied {
            await Self.expectProfileDenied(tool, arguments: [:], profile: .approvalRequired, client: client)
        }
        let stored = try await SystemToolRegistry.execute(
            "mem_store",
            arguments: ["key": .string("approved"), "value": .string("yes"), "scope": .string("global")],
            toolset: .system, runtime: client, permissionProfile: .approvalRequired
        )
        #expect(stored["overwritten"]?.boolValue == false)
        await client.close()
    }

    @Test("Workspace-modify and terminal profiles deny nothing at the gate")
    func permissiveProfilesDenyNothing() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        for profile in [AssistantPermissionProfile.workspaceModify, AssistantPermissionProfile.terminal] {
            do {
                _ = try await SystemToolRegistry.execute(
                    "write_file", arguments: [:], toolset: .system, runtime: client, permissionProfile: profile
                )
                Issue.record("Expected missingArgument error for write_file under \(profile)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: "write_file", argument: "cwd"))
            } catch {
                Issue.record("Unexpected error for write_file: \(error)")
            }
            do {
                _ = try await SystemToolRegistry.execute(
                    "use_terminal", arguments: [:], toolset: .system, runtime: client, permissionProfile: profile
                )
                Issue.record("Expected missingArgument error for use_terminal under \(profile)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: "use_terminal", argument: "threadId"))
            } catch {
                Issue.record("Unexpected error for use_terminal: \(error)")
            }
            do {
                _ = try await SystemToolRegistry.execute(
                    "git_push", arguments: [:], toolset: .system, runtime: client, permissionProfile: profile
                )
                Issue.record("Expected missingArgument error for git_push under \(profile)")
            } catch let error as SystemToolError {
                #expect(error == .missingArgument(tool: "git_push", argument: "threadId"))
            } catch {
                Issue.record("Unexpected error for git_push: \(error)")
            }
        }
        await client.close()
    }

    @Test("No assistant profile behaves exactly as today")
    func noAssistantProfileBehavesAsToday() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            _ = try await SystemToolRegistry.execute(
                "write_file", arguments: [:], toolset: .system, runtime: client
            )
            Issue.record("Expected missingArgument error for write_file without a profile")
        } catch let error as SystemToolError {
            #expect(error == .missingArgument(tool: "write_file", argument: "cwd"))
        } catch {
            Issue.record("Unexpected error for write_file: \(error)")
        }
        let stored = try await SystemToolRegistry.execute(
            "mem_store",
            arguments: ["key": .string("plain"), "value": .string("yes"), "scope": .string("global")],
            toolset: .system, runtime: client
        )
        #expect(stored["overwritten"]?.boolValue == false)
        await client.close()
    }

    @Test("Profile gate applies through use_mcp sub-dispatch")
    func profileGateAppliesThroughUseMcp() async throws {
        let (client, tempRoot) = try Self.makeClient()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            _ = try await SystemToolRegistry.execute(
                "use_mcp",
                arguments: [
                    "serverName": .string("coincide"),
                    "toolName": .string("mem_store"),
                    "arguments": .string("{\"key\": \"via_mcp\", \"value\": \"no\", \"scope\": \"global\"}"),
                ],
                toolset: .system, runtime: client, permissionProfile: .readOnly
            )
            Issue.record("Expected toolNotActive error for mem_store reached through use_mcp under read-only")
        } catch let error as SystemToolError {
            #expect(error == .toolNotActive(tool: "mem_store", toolset: .system))
        } catch {
            Issue.record("Unexpected error for use_mcp mem_store: \(error)")
        }
        let listed = try await SystemToolRegistry.execute(
            "use_mcp",
            arguments: [
                "serverName": .string("coincide"),
                "toolName": .string("view_memory"),
                "arguments": .string("{\"scope\": \"global\"}"),
            ],
            toolset: .system, runtime: client, permissionProfile: .readOnly
        )
        #expect(listed.arrayValue != nil)
        await client.close()
    }

    @Test("Permission profile resolves from thread to assistant, failing closed")
    func permissionProfileResolution() {
        let readOnlyID = UUID()
        let modifyID = UUID()
        let terminalID = UUID()
        let approvalID = UUID()
        let unknownProfileID = UUID()
        let assistants = [
            Self.assistant(id: readOnlyID, profile: .readOnly),
            Self.assistant(id: modifyID, profile: .workspaceModify),
            Self.assistant(id: terminalID, profile: .terminal),
            Self.assistant(id: approvalID, profile: .approvalRequired),
            Self.assistant(id: unknownProfileID, profile: .unknown),
        ]
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: nil, in: assistants) == nil)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: readOnlyID.uuidString, in: assistants) == .readOnly)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: modifyID.uuidString, in: assistants) == .workspaceModify)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: terminalID.uuidString, in: assistants) == .terminal)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: approvalID.uuidString, in: assistants) == .approvalRequired)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: unknownProfileID.uuidString, in: assistants) == .readOnly)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: UUID().uuidString, in: assistants) == .readOnly)
        #expect(SystemToolRegistry.permissionProfile(forAssistantId: "not-a-uuid", in: assistants) == .readOnly)
        let plainThread = RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Plain",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default")
        )
        #expect(SystemToolRegistry.permissionProfile(forThread: plainThread, in: assistants) == nil)
        let assistedThread = RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Assisted",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default"),
            assistantId: approvalID.uuidString
        )
        #expect(SystemToolRegistry.permissionProfile(forThread: assistedThread, in: assistants) == .approvalRequired)
        let orphanThread = RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Orphan",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default"),
            assistantId: UUID().uuidString
        )
        #expect(SystemToolRegistry.permissionProfile(forThread: orphanThread, in: assistants) == .readOnly)
    }

    @Test("Permission profile deny sets name only registered tools")
    func permissionProfileDenySetsAreRegisteredTools() {
        let registered = Set(SystemToolRegistry.systemTools.map(\\.name))
        #expect(SystemToolRegistry.readOnlyDeniedToolNames.count == 150)
        #expect(SystemToolRegistry.approvalRequiredDeniedToolNames.count == 86)
        #expect(SystemToolRegistry.readOnlyDeniedToolNames.isSubset(of: registered))
        #expect(SystemToolRegistry.approvalRequiredDeniedToolNames.isSubset(of: registered))
        #expect(SystemToolRegistry.readOnlyDeniedToolNames.contains("write_file"))
        #expect(!SystemToolRegistry.readOnlyDeniedToolNames.contains("read_file"))
        #expect(!SystemToolRegistry.approvalRequiredDeniedToolNames.contains("read_file"))
        #expect(!SystemToolRegistry.approvalRequiredDeniedToolNames.contains("mem_store"))
        for tool in [
            "dead_code_eliminator", "entitlements_manager", "env_capture_logs", "execution_plan",
            "intel_breakdown_task", "intel_plan_task", "json_to_plist", "mem_context_snapshot",
            "project_capabilities", "project_info_plist", "read_terminal", "system_notification_tool",
            "use_mcp", "github_repo", "zoom",
        ] {
            #expect(SystemToolRegistry.readOnlyDeniedToolNames.contains(tool))
        }
        for tool in [
            "git_conflict_resolver", "manage_memory", "project_restore", "project_snapshot",
            "safe_undo", "github_repo",
        ] {
            #expect(SystemToolRegistry.approvalRequiredDeniedToolNames.contains(tool))
        }
        #expect(!SystemToolRegistry.approvalRequiredDeniedToolNames.contains("zoom"))
        #expect(SystemToolRegistry.isDeniedByPermissionProfile("write_file", profile: .readOnly))
        #expect(!SystemToolRegistry.isDeniedByPermissionProfile("read_file", profile: .readOnly))
        #expect(SystemToolRegistry.isDeniedByPermissionProfile("use_terminal", profile: .approvalRequired))
        #expect(SystemToolRegistry.isDeniedByPermissionProfile("git_push", profile: .approvalRequired))
        #expect(SystemToolRegistry.isDeniedByPermissionProfile("delete_file", profile: .approvalRequired))
        #expect(!SystemToolRegistry.isDeniedByPermissionProfile("write_file", profile: .approvalRequired))
        #expect(!SystemToolRegistry.isDeniedByPermissionProfile("write_file", profile: .workspaceModify))
        #expect(!SystemToolRegistry.isDeniedByPermissionProfile("use_terminal", profile: .terminal))
        #expect(!SystemToolRegistry.isDeniedByPermissionProfile("git_push", profile: .terminal))
    }

    @Test("Permission profile deny sets match the shared manifest")
    func permissionProfileDenySetsMatchSharedManifest() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let manifestURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Agents/Resources/ProfileDenyLists.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ProfileDenyLists.Manifest.self, from: data)
        #expect(manifest.readOnlyDenied == manifest.readOnlyDenied.sorted())
        #expect(manifest.approvalRequiredDenied == manifest.approvalRequiredDenied.sorted())
        #expect(Set(manifest.readOnlyDenied).count == manifest.readOnlyDenied.count)
        #expect(Set(manifest.approvalRequiredDenied).count == manifest.approvalRequiredDenied.count)
        #expect(SystemToolRegistry.readOnlyDeniedToolNames == Set(manifest.readOnlyDenied))
        #expect(SystemToolRegistry.approvalRequiredDeniedToolNames == Set(manifest.approvalRequiredDenied))
    }

}
