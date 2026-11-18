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
        #expect(tools.count == 107)
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
            "mcp.tools", "git.stash", "git.blame", "git.bisect", "git.cherry_pick",
            "git.rollback", "git.checkpoints.create", "git.checkpoints.list",
            "git.checkpoints.restore",
        ])
        #expect(tools.allSatisfy { !$0.parameters.isEmpty })
        #expect(tools.allSatisfy { $0.parameters.contains { $0.required } })
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
}
