import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistants: Models, Protocol, Bridge Shapes & Validation")
struct AssistantTests {

    private static let assistantID = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!

    private static let assistantJSON = """
        {
            "id": "AAAAAAAA-1111-4111-8111-111111111111",
            "name": "Reviewer",
            "description": "Reviews code",
            "icon": "magnifier",
            "category": "code-review-security",
            "systemPrompt": "Review carefully.",
            "intendedTasks": ["Review pull requests"],
            "expectedOutputFormat": "Markdown",
            "allowedTools": ["use_workers"],
            "provider": "claude",
            "model": "claude-sonnet-4",
            "permissionProfile": "read-only",
            "inputRequirements": ["A diff"],
            "version": 3,
            "source": "custom",
            "isFavorite": true,
            "lastUsedAt": 1790000000000,
            "createdAt": 1780000000000,
            "updatedAt": 1785000000000
        }
        """

    @Test("Assistant decodes the adapter's remote shape, with millisecond timestamps")
    func assistantDecodesRemoteShape() throws {
        let assistant = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistant.self, from: Data(Self.assistantJSON.utf8))
        #expect(assistant.id == Self.assistantID)
        #expect(assistant.name == "Reviewer")
        #expect(assistant.description == "Reviews code")
        #expect(assistant.icon == "magnifier")
        #expect(assistant.category == .codeReviewSecurity)
        #expect(assistant.systemPrompt == "Review carefully.")
        #expect(assistant.intendedTasks == ["Review pull requests"])
        #expect(assistant.expectedOutputFormat == "Markdown")
        #expect(assistant.allowedTools == ["use_workers"])
        #expect(assistant.provider == "claude")
        #expect(assistant.model == "claude-sonnet-4")
        #expect(assistant.permissionProfile == .readOnly)
        #expect(assistant.inputRequirements == ["A diff"])
        #expect(assistant.version == 3)
        #expect(assistant.source == .custom)
        #expect(assistant.isFavorite == true)
        #expect(assistant.lastUsedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(assistant.createdAt == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(assistant.updatedAt == Date(timeIntervalSince1970: 1_785_000_000))
        let roundTripped = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistant.self, from: try RemoteProtocol.makeEncoder().encode(assistant))
        #expect(roundTripped == assistant)
    }

    @Test("Assistant ignores fields a newer Mac adds")
    func assistantIgnoresUnknownFields() throws {
        let json = String(Self.assistantJSON.dropLast(2)) + """
            ,
                "futureField": "kept by the Mac",
                "nested": {"a": 1}
            }
            """
        let assistant = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistant.self, from: Data(json.utf8))
        #expect(assistant.name == "Reviewer")
        #expect(assistant.category == .codeReviewSecurity)
    }

    @Test("Assistant decodes unknown enum values as unknown instead of failing")
    func assistantUnknownEnumValuesDecodeSafely() throws {
        let json = """
            {
                "id": "AAAAAAAA-1111-4111-8111-111111111111",
                "name": "Mystery",
                "category": "not-a-category",
                "systemPrompt": "Do something.",
                "permissionProfile": "do-anything",
                "source": "builtin"
            }
            """
        let assistant = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistant.self, from: Data(json.utf8))
        #expect(assistant.category == .unknown)
        #expect(assistant.permissionProfile == .unknown)
        #expect(assistant.source == .unknown)
        #expect(assistant.name == "Mystery")
    }

    @Test("Assistant fills missing fields with the Rust serde defaults")
    func assistantMissingFieldsUseDefaults() throws {
        let json = "{\"id\": \"AAAAAAAA-1111-4111-8111-111111111111\"}"
        let assistant = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistant.self, from: Data(json.utf8))
        #expect(assistant.name == "")
        #expect(assistant.category == .unknown)
        #expect(assistant.systemPrompt == "")
        #expect(assistant.intendedTasks == [])
        #expect(assistant.permissionProfile == .readOnly)
        #expect(assistant.version == 1)
        #expect(assistant.source == .unknown)
        #expect(assistant.isFavorite == false)
        #expect(assistant.lastUsedAt == nil)
    }

    @Test("Assistant draft omits a nil id so the adapter mints one, and keeps a set id")
    func assistantDraftNilIDMeansCreate() throws {
        let create = RemoteAssistantDraft(name: "New", category: .buildingFixing, systemPrompt: "Fix it.")
        let createJSON = String(data: try RemoteProtocol.makeEncoder().encode(create), encoding: .utf8) ?? ""
        #expect(!createJSON.contains("\"id\":"))
        let edit = RemoteAssistantDraft(
            id: Self.assistantID, name: "New", category: .buildingFixing, systemPrompt: "Fix it.")
        let editJSON = String(data: try RemoteProtocol.makeEncoder().encode(edit), encoding: .utf8) ?? ""
        #expect(editJSON.contains("\"id\":\"\(Self.assistantID.uuidString)\""))
        let roundTripped = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistantDraft.self, from: try RemoteProtocol.makeEncoder().encode(edit))
        #expect(roundTripped == edit)
    }

    @Test("Assistant draft encodes the full editable shape")
    func assistantDraftEncodesEditableShape() throws {
        let draft = RemoteAssistantDraft(
            name: "Reviewer", description: "Reviews code", icon: "magnifier",
            category: .codeReviewSecurity, systemPrompt: "Review carefully.",
            intendedTasks: ["Review pull requests"], expectedOutputFormat: "Markdown",
            allowedTools: ["use_workers"], provider: "claude", model: "claude-sonnet-4",
            permissionProfile: .readOnly, inputRequirements: ["A diff"], version: 3,
            source: .custom, isFavorite: true)
        let decoded = try JSONSerialization.jsonObject(
            with: try RemoteProtocol.makeEncoder().encode(draft)) as? [String: Any]
        #expect(decoded?["name"] as? String == "Reviewer")
        #expect(decoded?["category"] as? String == "code-review-security")
        #expect(decoded?["permissionProfile"] as? String == "read-only")
        #expect(decoded?["source"] as? String == "custom")
        #expect(decoded?["version"] as? Int == 3)
        #expect(decoded?["allowedTools"] as? [String] == ["use_workers"])
        #expect(decoded?["isFavorite"] as? Bool == true)
    }

    @Test("Allowed-tools validation accepts registry names and rejects unknown ones")
    func allowedToolsValidationRejectsUnknownNames() async {
        let known = RemoteAssistantDraft(
            name: "A", category: .codeMaintenance, systemPrompt: "S", allowedTools: ["use_workers"])
        #expect(await AppModel.unknownAllowedTools(in: known).isEmpty)
        let mixed = RemoteAssistantDraft(
            name: "A", category: .codeMaintenance, systemPrompt: "S",
            allowedTools: ["use_workers", "not_a_real_tool"])
        #expect(await AppModel.unknownAllowedTools(in: mixed) == ["not_a_real_tool"])
        let none = RemoteAssistantDraft(name: "A", category: .codeMaintenance, systemPrompt: "S")
        #expect(await AppModel.unknownAllowedTools(in: none).isEmpty)
    }

    @Test("Allowed-tools validation works on a bare tool list too")
    func allowedToolsValidationAcceptsBareList() async {
        #expect(await AppModel.unknownAllowedTools(in: ["use_workers"] as [String]?).isEmpty)
        #expect(await AppModel.unknownAllowedTools(in: ["not_a_real_tool"] as [String]?) == ["not_a_real_tool"])
        #expect(await AppModel.unknownAllowedTools(in: nil as [String]?).isEmpty)
    }

    @Test("Delete-assistant request carries the id as assistantID")
    func deleteAssistantRequestShape() throws {
        let id = UUID()
        let message = RemoteClientMessage(request: .deleteAssistant(assistantID: id))
        let data = try RemoteProtocol.makeEncoder().encode(message)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["type"] as? String == "deleteAssistant")
        #expect((decoded?["body"] as? [String: Any])?["assistantID"] as? String == id.uuidString)
        let roundTripped = try RemoteProtocol.makeDecoder().decode(RemoteClientMessage.self, from: data)
        #expect(roundTripped.request == .deleteAssistant(assistantID: id))
    }

    @Test("New-thread request carries the assistant id and defaults it to nil")
    func newThreadRequestCarriesAssistantId() throws {
        let id = UUID()
        let message = RemoteClientMessage(request: .newThread(
            projectID: nil, systemPrompt: "Behave.", toolset: "system",
            allowedTools: ["read_file"], assistantId: id.uuidString))
        let data = try RemoteProtocol.makeEncoder().encode(message)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((decoded?["body"] as? [String: Any])?["assistantId"] as? String == id.uuidString)
        let roundTripped = try RemoteProtocol.makeDecoder().decode(RemoteClientMessage.self, from: data)
        #expect(roundTripped.request == .newThread(
            projectID: nil, systemPrompt: "Behave.", toolset: "system",
            allowedTools: ["read_file"], assistantId: id.uuidString))
        let legacy = RemoteClientMessage(request: .newThread(
            projectID: nil, systemPrompt: nil, toolset: nil, allowedTools: nil))
        let legacyData = try RemoteProtocol.makeEncoder().encode(legacy)
        let legacyDecoded = try RemoteProtocol.makeDecoder().decode(RemoteClientMessage.self, from: legacyData)
        guard case .newThread(_, _, _, _, let legacyAssistant) = legacyDecoded.request else {
            Issue.record("Expected newThread request")
            return
        }
        #expect(legacyAssistant == nil)
    }

    @Test("Thread summary carries the assistant id and decodes legacy summaries without it")
    func threadSummaryAssistantIdRoundTrips() throws {
        let encoder = RemoteProtocol.makeEncoder()
        let decoder = RemoteProtocol.makeDecoder()
        let id = UUID()
        let summary = RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Test",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default"),
            assistantId: id.uuidString
        )
        let data = try encoder.encode(summary)
        #expect(try decoder.decode(RemoteThreadSummary.self, from: data).assistantId == id.uuidString)
        let legacy = RemoteThreadSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Test",
            selection: RemoteSelection(provider: "codex", modelID: "default", modelName: "Default")
        )
        let legacyData = try encoder.encode(legacy)
        #expect(!String(data: legacyData, encoding: .utf8)!.contains("assistantId"))
        #expect(try decoder.decode(RemoteThreadSummary.self, from: legacyData).assistantId == nil)
    }

    @Test("Worker record decodes the assistant id")
    func workerRecordDecodesAssistantId() throws {
        let json = """
            {"id":"w1","name":"alpha","parentThreadId":"p","threadId":"t","task":"Do it.","provider":"codex","targetFiles":[],"status":"running","cancelRequested":false,"transcriptStart":0,"transcriptItems":0,"elapsedSeconds":0,"createdAt":0,"startedAt":0,"completedAt":null,"error":null,"result":null,"assistantId":"AAAAAAAA-1111-4111-8111-111111111111"}
            """
        let record = try JSONDecoder().decode(WorkerRecord.self, from: Data(json.utf8))
        #expect(record.assistantId == "AAAAAAAA-1111-4111-8111-111111111111")
        let legacy = try JSONDecoder().decode(WorkerRecord.self, from: Data("""
            {"id":"w1","name":"alpha","parentThreadId":"p","threadId":"t","task":"Do it.","provider":"codex","targetFiles":[],"status":"running","cancelRequested":false,"transcriptStart":0,"transcriptItems":0,"elapsedSeconds":0,"createdAt":0,"startedAt":0,"completedAt":null,"error":null,"result":null}
            """.utf8))
        #expect(legacy.assistantId == nil)
    }

    @Test("Save-assistant request carries the draft as the body")
    func saveAssistantRequestShape() throws {
        let draft = RemoteAssistantDraft(name: "New", category: .buildingFixing, systemPrompt: "Fix it.")
        let message = RemoteClientMessage(request: .saveAssistant(draft))
        let data = try RemoteProtocol.makeEncoder().encode(message)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"type\":\"saveAssistant\""))
        #expect(json.contains("\"name\":\"New\""))
        #expect(!json.contains("\"id\":"))
        let roundTripped = try RemoteProtocol.makeDecoder().decode(RemoteClientMessage.self, from: data)
        #expect(roundTripped.request == .saveAssistant(draft))
    }

    @Test("Assistants list response decodes with baseline and origin")
    func assistantsListResponseDecodes() throws {
        let json = """
            {"v":1,"kind":"response","re":"local","type":"assistants",\
            "body":{"assistants":[\(Self.assistantJSON)],"baseline":"aabbcc","origin":"local"}}
            """
        let message = try RemoteProtocol.makeDecoder().decode(
            RemoteServerMessage.self, from: Data(json.utf8))
        guard case .response(_, let result) = message else {
            Issue.record("Expected a response message")
            return
        }
        guard case .assistants(let list) = result else {
            Issue.record("Expected an assistants result")
            return
        }
        #expect(list.assistants.count == 1)
        #expect(list.assistants.first?.name == "Reviewer")
        #expect(list.baseline == "aabbcc")
        #expect(list.origin == "local")
    }

    @Test("Assistants list skips a record that does not decode instead of losing the list")
    func assistantsListSkipsUndecodableRecords() throws {
        let json = """
            {"assistants":[\(Self.assistantJSON),{"name":"Broken"}],"baseline":"","origin":"empty"}
            """
        let list = try RemoteProtocol.makeDecoder().decode(
            RemoteAssistants.self, from: Data(json.utf8))
        #expect(list.assistants.count == 1)
        #expect(list.assistants.first?.name == "Reviewer")
    }

    @Test("Save-assistant response carries the saved id")
    func saveAssistantResponseCarriesSavedID() throws {
        let id = UUID()
        let json = """
            {"v":1,"kind":"response","re":"local","type":"assistant","body":{"value":"\(id.uuidString)"}}
            """
        let message = try RemoteProtocol.makeDecoder().decode(
            RemoteServerMessage.self, from: Data(json.utf8))
        guard case .response(_, let result) = message else {
            Issue.record("Expected a response message")
            return
        }
        guard case .assistant(let saved) = result else {
            Issue.record("Expected an assistant result")
            return
        }
        #expect(saved == id)
    }
}
