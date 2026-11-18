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
}
