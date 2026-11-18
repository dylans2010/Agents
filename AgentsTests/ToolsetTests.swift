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
        #expect(tools.count == 166)
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
            "workers.cancel", "workers.plan", "workers.breakdown", "workers.execution_plan",
            "computer_use.request",
            "system.open_in_finder", "system.reveal_in_finder",
            "mcp.tools", "git.stash", "git.blame", "git.bisect", "git.cherry_pick",
            "git.rollback", "git.checkpoints.create", "git.checkpoints.list",
            "git.checkpoints.restore",
        ])
        #expect(tools.allSatisfy { !$0.parameters.isEmpty })
        let allOptionalTools: Set<String> = [
            "create_terminal", "view_memory", "mem_context_snapshot", "list_workers",
            "env_capture_logs",
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
            ("save_to_memory", "memory.store", .engine),
            ("use_mcp", "mcp.tools", .engine),
            ("take_screenshot", "computer_use.request", .engine),
            ("start_subagent", "workers.spawn", .engine),
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
            request: .newThread(projectID: projectID, systemPrompt: "Behave.", toolset: "system")
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(RemoteClientMessage.self, from: data)
        guard case .newThread(let decodedProject, let prompt, let toolset) = decoded.request else {
            Issue.record("Expected newThread request")
            return
        }
        #expect(decodedProject == projectID)
        #expect(prompt == "Behave.")
        #expect(toolset == "system")
    }

    @Test("Old new-thread messages without prompt fields decode to nils")
    func oldNewThreadDecodes() throws {
        let json = """
        {"v":1,"id":"old","type":"newThread","body":{"projectID":"\(UUID().uuidString)"}}
        """
        let decoded = try RemoteProtocol.makeDecoder().decode(
            RemoteClientMessage.self, from: Data(json.utf8)
        )
        guard case .newThread(let project, let prompt, let toolset) = decoded.request else {
            Issue.record("Expected newThread request")
            return
        }
        #expect(project != nil)
        #expect(prompt == nil)
        #expect(toolset == nil)
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
    }

    @Test("Only Codex and Claude accept a per-thread system prompt")
    func systemPromptSupportMatrix() {
        #expect(AgentToolset.systemPromptSupported(provider: "codex"))
        #expect(AgentToolset.systemPromptSupported(provider: "claude"))
        #expect(!AgentToolset.systemPromptSupported(provider: "opencode"))
        #expect(!AgentToolset.systemPromptSupported(provider: "lithos"))
        #expect(!AgentToolset.systemPromptSupported(provider: "grok"))
        #expect(!AgentToolset.systemPromptSupported(provider: "cursor"))
        #expect(!AgentToolset.systemPromptSupported(provider: "antigravity"))
        #expect(!AgentToolset.systemPromptSupported(provider: "acp-foo"))
        #expect(!AgentToolset.systemPromptSupported(provider: ""))
        let message = AgentToolset.systemPromptUnsupportedMessage(provider: "opencode")
        #expect(message.contains("opencode"))
        #expect(message.contains("Codex"))
        #expect(message.contains("Claude"))
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
        #expect(SystemToolRegistry.definition(named: "use_app", for: .system) == nil)
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
}
