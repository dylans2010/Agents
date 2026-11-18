import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Agents Native macOS Core Runtime & UI Integration")
struct AgentsRuntimeTests {

    @Test("DictationInsertion smart spacing around words and punctuation")
    func dictationInsertionSpacing() {
        var insertion = DictationInsertion(text: "Hello world", selection: NSRange(location: 5, length: 0))
        let first = insertion.update("beautiful")
        #expect(first?.range == NSRange(location: 5, length: 0))
        #expect(first?.replacement == " beautiful")
        #expect(insertion.caret == NSRange(location: 15, length: 0))

        var beforePunct = DictationInsertion(text: "Hello!", selection: NSRange(location: 5, length: 0))
        let edit = beforePunct.update("there")
        #expect(edit?.replacement == " there")
    }

    @Test("AgentBranding maps assets and original vs template rendering")
    func agentBrandingConfiguration() {
        #expect(AgentBranding.assetName(for: "antigravity") == "AgentAntigravity")
        #expect(AgentBranding.keepsOriginalColors(for: "antigravity") == true)
        #expect(AgentBranding.assetName(for: "claude") == "AgentClaude")
        #expect(AgentBranding.keepsOriginalColors(for: "claude") == true)
        #expect(AgentBranding.assetName(for: "codex") == "AgentCodex")
        #expect(AgentBranding.keepsOriginalColors(for: "codex") == false)
        #expect(AgentBranding.displayName(for: "lithos") == "Lithos")
        #expect(AgentBranding.displayName(for: "LITHOS") == "Lithos")
        #expect(AgentBranding.normalizedID(" LITHOS ") == "lithos")
        #expect(AgentBranding.assetName(for: "lithos") == "AgentLithos")
        #expect(AgentBranding.keepsOriginalColors(for: "lithos") == false)
        #expect(AgentBranding.assetName(for: "acp-custom") == nil)
    }

    @Test("ExternalEditorService expands home paths and discovers Finder")
    @MainActor
    func externalEditorDiscovery() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ExternalEditorService.expandedPath("~") == home)
        #expect(ExternalEditorService.expandedPath("~/Projects") == "\(home)/Projects")
        #expect(ExternalEditorService.shared.finderTarget != nil)
    }

    @Test("BotPersonalityPreset and SnoozePreset domain catalogs")
    func presetsCatalogVerification() {
        #expect(BotPersonalityPreset.all.count == 10)
        let defaultID = BotPersonalityPreset.defaultID(forCharacter: "star")
        #expect(defaultID == "coach")

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        #expect(SnoozePreset.allCases.count == 5)
        for preset in SnoozePreset.allCases {
            #expect(preset.resolveDate(from: now) > now)
        }
    }

    @Test("End-to-end AgentsRuntimeClient FFI bridge roundtrip including Antigravity & ACP Registry")
    func runtimeClientRoundtrip() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/ct-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")

        let status = try await client.pollStatus()
        #expect(status.busy == false)
        #expect(status.running == 0)

        let projectID = try await client.createProject(path: projectDir.path, name: "SampleSwiftProject")
        let threadID = try await client.newThread(projectID: projectID)

        let ws = try await client.fetchWorkspace(includeArchived: false)
        #expect(ws.projects.contains(where: { $0.id == projectID }))
        #expect(ws.threads.contains(where: { $0.id == threadID }))

        let transcript = try await client.openThread(threadID)
        #expect(transcript.thread.id == threadID)

        let providers = try await client.listAllProviders()
        let antigravity = providers.first(where: { $0.id == "antigravity" })
        #expect(antigravity != nil)
        #expect(antigravity?.supportsAPIKeyAccounts == true)
        #expect(providers.contains(where: { $0.id == "claude" }))
        #expect(providers.contains(where: { $0.id == "codex" }))

        let acpAgents = try await client.fetchACPRegistry(refresh: false)
        #expect(!acpAgents.isEmpty)

        try await client.writeWorkspaceFile(
            cwd: projectDir.path,
            path: "Sources/Greeter.swift",
            content: "struct Greeter { let phrase = \"Hello Swift 6\" }\n"
        )
        let files = try await client.listWorkspaceFiles(cwd: projectDir.path)
        #expect(files.contains(where: { $0.path == "Sources/Greeter.swift" }))

        let doc = try await client.readWorkspaceFile(cwd: projectDir.path, path: "Sources/Greeter.swift")
        #expect(doc.content.contains("Hello Swift 6"))

        let hits = try await client.searchWorkspace(cwd: projectDir.path, query: "Hello Swift 6")
        #expect(hits.first?.path == "Sources/Greeter.swift")

        let instructions = try await client.listInstructions(projectRoot: projectDir.path)
        #expect(!instructions.isEmpty)

        let termID = try await client.createTerminal(threadID: threadID.uuidString)
        let viewport = try await client.readTerminalViewport(id: termID, dark: true)
        #expect(viewport.rows > 0)
        #expect(viewport.cols > 0)
        try await client.closeTerminal(id: termID)

        _ = try await client.deleteThreadPermanently(threadID: threadID.uuidString)
        let restored = try await client.undoDeleteThread()
        #expect(!restored.isEmpty)

        let remoteSnap = try await client.fetchRemoteServerStatus()
        #expect(remoteSnap.enabled == false)

        await client.close()
    }

    @Test("Workspace mutation FFI roundtrip: edit, copy, move, read_dir, delete, regex search")
    func workspaceMutationRoundtrip() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/wm-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let client = try AgentsRuntimeClient(dataDir: dataDir.path, appVersion: "0.2.0-test")
        let cwd = projectDir.path

        try await client.writeWorkspaceFile(
            cwd: cwd,
            path: "Sources/Greeter.swift",
            content: "struct Greeter { let phrase = \"Hello Swift 6\" }\n"
        )

        let edited = try await client.editWorkspaceFile(
            cwd: cwd, path: "Sources/Greeter.swift",
            oldText: "Hello Swift 6", newText: "Hello Agents"
        )
        #expect(edited["edited"]?.boolValue == true)
        #expect(edited["replacements"]?.intValue == 1)
        #expect(edited["lines"]?.arrayValue?.first?.intValue == 1)
        let doc = try await client.readWorkspaceFile(cwd: cwd, path: "Sources/Greeter.swift")
        #expect(doc.content.contains("Hello Agents"))

        do {
            _ = try await client.editWorkspaceFile(
                cwd: cwd, path: "Sources/Greeter.swift",
                oldText: "e", newText: "E"
            )
            Issue.record("Expected ambiguous-anchor error")
        } catch {
        }
        do {
            _ = try await client.editWorkspaceFile(
                cwd: cwd, path: "Sources/Greeter.swift",
                oldText: "missing anchor", newText: "x"
            )
            Issue.record("Expected missing-anchor error")
        } catch {
        }

        let multi = try await client.editWorkspaceFile(
            cwd: cwd, path: "Sources/Greeter.swift",
            edits: [
                WorkspaceEdit(oldText: "let phrase", newText: "let greeting", mode: "replace"),
                WorkspaceEdit(oldText: "Hello Agents", newText: "Hello Agents!", mode: "replace"),
            ]
        )
        #expect(multi["replacements"]?.intValue == 2)
        let afterMulti = try await client.readWorkspaceFile(cwd: cwd, path: "Sources/Greeter.swift")
        #expect(afterMulti.content.contains("let greeting"))
        #expect(afterMulti.content.contains("Hello Agents!"))

        let inserted = try await client.editWorkspaceFile(
            cwd: cwd, path: "Sources/Greeter.swift",
            oldText: "struct Greeter", newText: " // greeted", mode: "insertAfter"
        )
        #expect(inserted["edited"]?.boolValue == true)
        let afterInsert = try await client.readWorkspaceFile(cwd: cwd, path: "Sources/Greeter.swift")
        #expect(afterInsert.content.contains("struct Greeter // greeted"))

        let regexHits = try await client.searchWorkspaceRegex(cwd: cwd, pattern: "Hello (Agents|Swift)")
        #expect(regexHits.first?.path == "Sources/Greeter.swift")
        #expect(try await client.searchWorkspaceRegex(cwd: cwd, pattern: "nomatch").isEmpty)
        do {
            _ = try await client.searchWorkspaceRegex(cwd: cwd, pattern: "([unclosed")
            Issue.record("Expected invalid-pattern error")
        } catch {
        }

        try await client.copyWorkspaceFile(cwd: cwd, path: "Sources/Greeter.swift", destination: "Sources/GreeterCopy.swift")
        let copied = try await client.readWorkspaceFile(cwd: cwd, path: "Sources/GreeterCopy.swift")
        #expect(copied.content == afterInsert.content)

        try await client.moveWorkspaceFile(cwd: cwd, path: "Sources/GreeterCopy.swift", destination: "Sources/Moved.swift")
        #expect(FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("Sources/Moved.swift").path))
        #expect(!FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("Sources/GreeterCopy.swift").path))

        try await client.createWorkspaceDirectory(cwd: cwd, path: "Sources/Nested/Deep")
        let rootEntries = try await client.readWorkspaceDirectory(cwd: cwd, path: "Sources")
        #expect(rootEntries.contains(where: { $0.path == "Sources/Nested" && $0.isDirectory }))
        let tree = try await client.readWorkspaceDirectory(cwd: cwd, recursive: true)
        #expect(tree.contains(where: { $0.path == "Sources/Nested/Deep" && $0.isDirectory }))
        #expect(tree.contains(where: { $0.path == "Sources/Moved.swift" }))

        try await client.deleteWorkspaceFile(cwd: cwd, path: "Sources/Moved.swift")
        #expect(!FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("Sources/Moved.swift").path))
        try await client.deleteWorkspaceDirectory(cwd: cwd, path: "Sources/Nested", recursive: true)
        #expect(!FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("Sources/Nested").path))
        do {
            try await client.deleteWorkspaceFile(cwd: cwd, path: "Sources/Moved.swift")
            Issue.record("Expected delete of missing file to fail")
        } catch {
        }
        do {
            try await client.deleteWorkspaceFile(cwd: cwd, path: "../escape.txt")
            Issue.record("Expected path escape to fail")
        } catch {
        }

        await client.close()
    }

    @Test("AppModel isolated coordinator lifecycle, bot creation, and thread mutations")
    @MainActor
    func appModelIsolatedLifecycle() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)

        let projID = await model.addProject(at: projectDir.path, name: "CoordinatorProject")
        #expect(projID != nil)

        let threadID = await model.createNewThread(in: projID)
        #expect(threadID != nil)

        if let threadID {
            await model.performThreadAction(.rename("Native macOS Session"), on: threadID)
            await model.performThreadAction(.pin(true), on: threadID)
            await model.refreshWorkspace()
            let updated = model.workspace.threads.first(where: { $0.id == threadID })
            #expect(updated?.title == "Native macOS Session")
            #expect(updated?.isPinned == true)
        }

        let botDraft = RemoteBotDraft(
            name: "Architect Bot",
            avatar: RemoteBotAvatar(character: "star", tint: "sky"),
            persona: "Focus on clean Swift 6 and AppKit architecture.",
            personality: RemoteBotPersonality(preset: "mentor", custom: "")
        )
        let botID = await model.saveBot(botDraft)
        #expect(botID != nil)
        #expect(model.workspace.bots?.contains(where: { $0.name == "Architect Bot" }) == true)

        await model.shutdown()
    }

    @Test("AppModel launches an assistant thread carrying its id and tools")
    @MainActor
    func appModelLaunchAssistant() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-launch-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)

        let projID = await model.addProject(at: projectDir.path, name: "LaunchProject")
        #expect(projID != nil)

        let assistant = RemoteAssistant(
            id: UUID(),
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff for security issues.",
            allowedTools: ["read_file"],
            provider: "claude",
            model: "claude-sonnet-4"
        )
        await model.launchAssistant(assistant, task: "Review the latest diff.", in: projID)
        await model.refreshWorkspace()
        let launched = model.workspace.threads.first { $0.assistantId == assistant.id.uuidString }
        #expect(launched != nil)
        #expect(launched?.allowedTools == ["read_file"])
        #expect(model.selectedThread?.id == launched?.id)

        await model.shutdown()
    }

    @Test("AppModel launches an assistant thread on the assistant's configured provider and model")
    @MainActor
    func appModelLaunchAssistantAppliesModelConfig() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-launch-model-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)

        guard let client = model.runtime else {
            Issue.record("Expected a runtime client after bootstrap")
            await model.shutdown()
            return
        }
        let projID = try await client.createProject(path: projectDir.path, name: "LaunchModelProject")
        _ = try await client.saveProjectDefaults(RemoteProjectDefaults(
            projectID: projID, usesGlobalDefaults: false, provider: "codex", modelID: "default"))

        let configured = RemoteAssistant(
            id: UUID(),
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff for security issues.",
            allowedTools: ["read_file"],
            provider: "claude",
            model: "claude-sonnet-4"
        )
        await model.launchAssistant(configured, task: "Review the latest diff.", in: projID)
        await model.refreshWorkspace()
        let launched = model.workspace.threads.first { $0.assistantId == configured.id.uuidString }
        #expect(launched != nil)
        #expect(launched?.selection.provider == "claude")
        #expect(launched?.selection.modelID == "claude-sonnet-4")

        let savedID = await model.saveAssistant(RemoteAssistantDraft(
            name: "Generalist",
            category: .codeReviewSecurity,
            systemPrompt: "Help with the code.",
            allowedTools: ["read_file"]
        ))
        #expect(savedID != nil)
        guard let savedID, let saved = model.assistants.first(where: { $0.id == savedID }) else {
            Issue.record("Expected the saved assistant in the assistant list")
            await model.shutdown()
            return
        }
        await model.launchAssistant(saved, task: "Help with the code.", in: projID)
        await model.refreshWorkspace()
        let defaultLaunched = model.workspace.threads.first { $0.assistantId == saved.id.uuidString }
        #expect(defaultLaunched != nil)
        #expect(defaultLaunched?.selection.provider == "codex")
        #expect(defaultLaunched?.selection.modelID == "default")
        let launchedPrompt = model.systemPrompt(for: defaultLaunched).text
        let descriptorPrompt = model.systemPrompt(
            for: nil, provider: "codex", model: "default",
            assistant: AssistantPromptDescriptor(saved)
        ).text
        #expect(launchedPrompt == descriptorPrompt)

        await model.shutdown()
    }

    @Test("AppModel launches a current-app-model assistant on the selected thread's provider and model")
    @MainActor
    func appModelLaunchAssistantResolvesCurrentAppModel() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-launch-current-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)

        guard let client = model.runtime else {
            Issue.record("Expected a runtime client after bootstrap")
            await model.shutdown()
            return
        }
        let projID = try await client.createProject(path: projectDir.path, name: "LaunchCurrentProject")

        let configured = RemoteAssistant(
            id: UUID(),
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff for security issues.",
            allowedTools: ["read_file"],
            provider: "claude",
            model: "claude-sonnet-4"
        )
        await model.launchAssistant(configured, task: "Review the latest diff.", in: projID)
        await model.refreshWorkspace()
        let launched = model.workspace.threads.first { $0.assistantId == configured.id.uuidString }
        #expect(launched != nil)
        #expect(launched?.selection.provider == "claude")
        #expect(launched?.selection.modelID == "claude-sonnet-4")

        let currentApp = RemoteAssistant(
            id: UUID(),
            name: "Generalist",
            category: .codeReviewSecurity,
            systemPrompt: "Help with the code.",
            allowedTools: ["read_file"]
        )
        await model.launchAssistant(currentApp, modelConfig: .currentAppModel, task: "Help with the code.", in: projID)
        await model.refreshWorkspace()
        let currentLaunched = model.workspace.threads.first { $0.assistantId == currentApp.id.uuidString }
        #expect(currentLaunched != nil)
        #expect(currentLaunched?.selection.provider == "claude")
        #expect(currentLaunched?.selection.modelID == "claude-sonnet-4")

        await model.shutdown()
    }

    @Test("AppModel launchAssistant rejects an empty task without creating a thread")
    @MainActor
    func appModelLaunchAssistantRejectsEmptyTask() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-launch-empty-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)

        let projID = await model.addProject(at: projectDir.path, name: "LaunchEmptyProject")
        #expect(projID != nil)

        let assistant = RemoteAssistant(
            id: UUID(),
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff for security issues.",
            allowedTools: ["read_file"],
            provider: "claude",
            model: "claude-sonnet-4"
        )
        await model.launchAssistant(assistant, task: "   ", in: projID)
        await model.refreshWorkspace()
        #expect(model.workspace.threads.first { $0.assistantId == assistant.id.uuidString } == nil)
        #expect(model.lastError == "Task text is empty")

        await model.shutdown()
    }

    @Test("AppModel refreshAssistants preserves launched assistant threads")
    @MainActor
    func appModelRefreshAssistantsPreservesLaunchedThreads() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-launch-refresh-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)

        let projID = await model.addProject(at: projectDir.path, name: "LaunchRefreshProject")
        #expect(projID != nil)

        let first = RemoteAssistant(
            id: UUID(),
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff for security issues.",
            allowedTools: ["read_file"],
            provider: "claude",
            model: "claude-sonnet-4"
        )
        let second = RemoteAssistant(
            id: UUID(),
            name: "Generalist",
            category: .codeReviewSecurity,
            systemPrompt: "Help with the code.",
            allowedTools: ["read_file"]
        )
        await model.launchAssistant(first, task: "Review the latest diff.", in: projID)
        await model.launchAssistant(second, task: "Help with the code.", in: projID)
        await model.refreshAssistants()
        await model.refreshWorkspace()
        let firstThread = model.workspace.threads.first { $0.assistantId == first.id.uuidString }
        let secondThread = model.workspace.threads.first { $0.assistantId == second.id.uuidString }
        #expect(firstThread != nil)
        #expect(secondThread != nil)
        #expect(firstThread?.id != secondThread?.id)
        #expect(model.selectedThread?.id == secondThread?.id)

        await model.shutdown()
    }

    @Test("RuntimePollStatus decodes turnResults serial and recent entries")
    func pollStatusDecodesTurnResults() throws {
        let payload = """
        {"busy":false,"revision":7,"running":[],"starting":[],"pendingApprovalsCount":0,"pendingQuestionsCount":0,"turnResults":{"serial":3,"recent":[{"serial":2,"threadId":"11111111-1111-1111-1111-111111111111","outcome":"completed"},{"serial":3,"threadId":"22222222-2222-2222-2222-222222222222","outcome":"failed"}]}}
        """
        let status = try RemoteProtocol.makeDecoder().decode(RuntimePollStatus.self, from: Data(payload.utf8))
        #expect(status.turnResultsSerial == 3)
        #expect(status.turnResultsRecent.count == 2)
        #expect(status.turnResultsRecent[0].serial == 2)
        #expect(status.turnResultsRecent[0].threadID == "11111111-1111-1111-1111-111111111111")
        #expect(status.turnResultsRecent[0].outcome == "completed")
        #expect(status.turnResultsRecent[1].serial == 3)
        #expect(status.turnResultsRecent[1].threadID == "22222222-2222-2222-2222-222222222222")
        #expect(status.turnResultsRecent[1].outcome == "failed")
    }

    @Test("RuntimePollStatus without turnResults decodes to an empty result list")
    func pollStatusWithoutTurnResults() throws {
        let payload = """
        {"busy":false,"revision":7,"running":[],"starting":[],"pendingApprovalsCount":0,"pendingQuestionsCount":0}
        """
        let status = try RemoteProtocol.makeDecoder().decode(RuntimePollStatus.self, from: Data(payload.utf8))
        #expect(status.turnResultsSerial == 0)
        #expect(status.turnResultsRecent.isEmpty)
    }

    @Test("Newly finished turns fire exactly once and survive an engine serial reset")
    func newlyFinishedTurnsExactlyOnce() {
        let status = RuntimePollStatus(
            turnResultsSerial: 3,
            turnResultsRecent: [
                TurnResultEntry(serial: 2, threadID: "11111111-1111-1111-1111-111111111111", outcome: "completed"),
                TurnResultEntry(serial: 3, threadID: "22222222-2222-2222-2222-222222222222", outcome: "failed"),
            ]
        )
        let first = status.newlyFinishedTurns(since: 1)
        #expect(first.entries.map(\.serial) == [2, 3])
        #expect(first.watermark == 3)
        let second = status.newlyFinishedTurns(since: first.watermark)
        #expect(second.entries.isEmpty)
        #expect(second.watermark == 3)
        let reset = status.newlyFinishedTurns(since: 9)
        #expect(reset.entries.isEmpty)
        #expect(reset.watermark == 3)
    }

    @Test("Assistant model config maps provider and model into the right case")
    func assistantModelConfigMapping() {
        #expect(AssistantModelConfig(provider: "claude", model: "sonnet") == .specific(provider: "claude", model: "sonnet"))
        #expect(AssistantModelConfig(provider: "claude", model: nil) == .providerOnly("claude"))
        #expect(AssistantModelConfig(provider: nil, model: "sonnet") == .modelOnly("sonnet"))
        #expect(AssistantModelConfig(provider: nil, model: nil) == .appDefault)
        #expect(AssistantModelConfig.specific(provider: "claude", model: "sonnet").provider == "claude")
        #expect(AssistantModelConfig.specific(provider: "claude", model: "sonnet").model == "sonnet")
        #expect(AssistantModelConfig.providerOnly("claude").provider == "claude")
        #expect(AssistantModelConfig.providerOnly("claude").model == nil)
        #expect(AssistantModelConfig.modelOnly("sonnet").provider == nil)
        #expect(AssistantModelConfig.modelOnly("sonnet").model == "sonnet")
        #expect(AssistantModelConfig.appDefault.provider == nil)
        #expect(AssistantModelConfig.appDefault.model == nil)
        #expect(AssistantModelConfig.currentAppModel.provider == nil)
        #expect(AssistantModelConfig.currentAppModel.model == nil)
        #expect(AssistantModelConfig.currentAppModel.resolvingCurrent(provider: "claude", model: "sonnet") == .specific(provider: "claude", model: "sonnet"))
        #expect(AssistantModelConfig.currentAppModel.resolvingCurrent(provider: nil, model: nil) == .appDefault)
        #expect(AssistantModelConfig.currentAppModel.resolvingCurrent(provider: "claude", model: nil) == .providerOnly("claude"))
        #expect(AssistantModelConfig.specific(provider: "claude", model: "sonnet").resolvingCurrent(provider: "other", model: "other") == .specific(provider: "claude", model: "sonnet"))
        #expect(AssistantModelConfig.appDefault.selectionOverride == nil)
        #expect(AssistantModelConfig.currentAppModel.selectionOverride == nil)
        #expect(AssistantModelConfig.specific(provider: "claude", model: "sonnet").selectionOverride == RemoteSelectionOverride(provider: "claude", modelID: "sonnet"))
        #expect(AssistantModelConfig.providerOnly("claude").selectionOverride == RemoteSelectionOverride(provider: "claude"))
        #expect(AssistantModelConfig.modelOnly("sonnet").selectionOverride == RemoteSelectionOverride(modelID: "sonnet"))
    }

    private static func summary(toolset: String?, assistantId: String? = nil) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Test",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default"),
            toolset: toolset,
            assistantId: assistantId
        )
    }

    @Test("AppModel system prompt carries the assistant role and falls back without one")
    @MainActor
    func appModelSystemPromptCarriesAssistantRole() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-prompt-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)
        let descriptor = AssistantPromptDescriptor(id: "assistant-review", name: "Reviewer", systemPrompt: "Be terse.", extraAssetFileNames: [])
        let withRequest = model.systemPrompt(for: "Fix the bug", provider: nil, model: nil, assistant: descriptor)
        #expect(withRequest.assistantID == "assistant-review")
        #expect(withRequest.text.contains("Be terse."))
        #expect(withRequest.text.contains("instructions:"))
        #expect(withRequest.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        let withoutRequest = model.systemPrompt(for: nil, provider: nil, model: nil, assistant: descriptor)
        #expect(withoutRequest.assistantID == "assistant-review")
        #expect(withoutRequest.text.contains("Be terse."))
        let noAssistant = model.systemPrompt(for: "Fix the bug", provider: nil, model: nil)
        #expect(noAssistant.assistantID == nil)
        #expect(noAssistant.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        let empty = model.systemPrompt(for: nil, provider: nil, model: nil)
        #expect(empty.assistantID == nil)
        #expect(empty.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        await model.shutdown()
    }

    @Test("A thread naming an unknown assistant falls back to the uncached prompt")
    @MainActor
    func appModelOrphanAssistantThreadFallsBack() {
        let model = AppModel()
        let thread = Self.summary(toolset: nil, assistantId: UUID().uuidString)
        #expect(thread.assistantId != nil)
        let prompt = model.systemPrompt(for: thread)
        #expect(prompt.assistantID == nil)
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
    }

    @Test("AppModel toolset resolves from the thread, defaulting to provider")
    func appModelToolsetResolvesFromThread() {
        let model = AppModel()
        #expect(model.toolset(for: nil) == .provider)
        #expect(model.toolset(for: Self.summary(toolset: "system")) == .system)
        #expect(model.toolset(for: Self.summary(toolset: "provider")) == .provider)
        #expect(model.toolset(for: Self.summary(toolset: "bogus")) == .provider)
        #expect(model.toolset(for: Self.summary(toolset: nil)) == .provider)
    }

    @Test("An unbootstrapped AppModel refuses work without a runtime")
    @MainActor
    func appModelWithoutRuntimeRefusesWork() async {
        let model = AppModel()
        #expect(model.runtime == nil)
        #expect(await model.sendMessage(text: "Hello") == nil)
        #expect(model.toastMessage != nil)
        #expect(await model.createNewThread() == nil)
        await model.stopActiveTurn()
        #expect(await model.addProject(at: "/tmp/does-not-exist") == nil)
        #expect(await model.saveAssistant(RemoteAssistantDraft(name: "Ghost", category: .codeReviewSecurity, systemPrompt: "Hi.", allowedTools: ["read_file"])) == nil)
    }

    @Test("AppModel deletes, forks, and archives threads")
    @MainActor
    func appModelThreadDeleteForkArchive() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-threads-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)
        let projID = await model.addProject(at: projectDir.path, name: "ThreadProject")
        #expect(projID != nil)
        let firstID = await model.createNewThread(in: projID)
        let secondID = await model.createNewThread(in: projID)
        let first = try #require(firstID)
        let second = try #require(secondID)
        #expect(model.workspace.threads.contains(where: { $0.id == first }))
        #expect(model.workspace.threads.contains(where: { $0.id == second }))
        model.selectThread(second)
        await model.deleteThreadPermanently(first.uuidString)
        #expect(!model.workspace.threads.contains(where: { $0.id == first }))
        #expect(model.workspace.threads.contains(where: { $0.id == second }))
        #expect(model.selectedThreadUUID == second)
        let forked = await model.forkThread(second)
        let forkedID = try #require(forked)
        #expect(forkedID != second)
        #expect(model.selectedThreadUUID == forkedID)
        #expect(model.workspace.threads.contains(where: { $0.id == forkedID }))
        await model.performThreadAction(.archive(true), on: forkedID)
        #expect(!model.workspace.threads.contains(where: { $0.id == forkedID }))
        #expect(!model.filteredThreads.contains(where: { $0.id == forkedID }))
        await model.performThreadAction(.archive(false), on: forkedID)
        #expect(model.workspace.threads.contains(where: { $0.id == forkedID }))
        #expect(model.filteredThreads.contains(where: { $0.id == forkedID }))
        await model.performThreadAction(.delete, on: forkedID)
        #expect(!model.workspace.threads.contains(where: { $0.id == forkedID }))
        await model.shutdown()
    }

    @Test("AppModel thread selection cycles with wraparound")
    @MainActor
    func appModelThreadSelectionCycles() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-select-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)
        let projID = await model.addProject(at: projectDir.path, name: "SelectProject")
        #expect(projID != nil)
        let first = try #require(await model.createNewThread(in: projID))
        let second = try #require(await model.createNewThread(in: projID))
        let third = try #require(await model.createNewThread(in: projID))
        #expect(model.filteredThreads.contains(where: { $0.id == first }))
        #expect(model.filteredThreads.contains(where: { $0.id == second }))
        #expect(model.filteredThreads.contains(where: { $0.id == third }))
        let start = try #require(model.selectedThreadUUID)
        let count = model.filteredThreads.count
        for _ in 0..<count { model.selectNextThread() }
        #expect(model.selectedThreadUUID == start)
        for _ in 0..<count { model.selectPreviousThread() }
        #expect(model.selectedThreadUUID == start)
        let unknown = UUID()
        model.selectThread(unknown)
        #expect(model.selectedThreadUUID == unknown)
        await model.shutdown()
    }

    @Test("AppModel saveAssistant rejects unknown tools")
    @MainActor
    func appModelSaveAssistantRejectsUnknownTools() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-tools-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)
        let saved = await model.saveAssistant(RemoteAssistantDraft(
            name: "Ghost", category: .codeReviewSecurity, systemPrompt: "Hi.",
            allowedTools: ["not_a_real_tool"]))
        #expect(saved == nil)
        #expect(model.lastError?.contains("Unknown assistant tools: not_a_real_tool") == true)
        await model.shutdown()
    }

    @Test("AppModel refuses to remove a project with conversations, then removes it empty")
    @MainActor
    func appModelRemoveProject() async throws {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let tempRoot = URL(fileURLWithPath: "/tmp/am-remove-\(shortID)")
        let dataDir = tempRoot.appendingPathComponent("d")
        let projectDir = tempRoot.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let model = AppModel()
        await model.bootstrap(dataDir: dataDir.path, startPolling: false)
        let projID = try #require(await model.addProject(at: projectDir.path, name: "RemoveProject"))
        #expect(model.workspace.projects.contains(where: { $0.id == projID }))
        let threadID = try #require(await model.createNewThread(in: projID))
        #expect(model.workspace.threads.contains(where: { $0.id == threadID }))
        await model.removeProject(projID)
        #expect(model.workspace.projects.contains(where: { $0.id == projID }))
        #expect(model.lastError?.contains("Move or remove the project's conversations first") == true)
        for thread in model.workspace.threads.filter({ $0.projectID == projID }) {
            await model.deleteThreadPermanently(thread.id.uuidString)
        }
        #expect(!model.workspace.threads.contains(where: { $0.projectID == projID }))
        await model.removeProject(projID)
        #expect(!model.workspace.projects.contains(where: { $0.id == projID }))
        await model.shutdown()
    }
}
