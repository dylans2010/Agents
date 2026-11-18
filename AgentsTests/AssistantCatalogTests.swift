import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant Catalog: IDs, Loading, Merge & Validation")
struct AssistantCatalogTests {

    private static func preset(
        id: String = "builtin.code-maintenance.tidy-imports",
        name: String = "Tidy Imports",
        description: String = "Tidies imports",
        category: AssistantCategory = .codeMaintenance,
        icon: String = "arrow.triangle.2.circlepath",
        systemPrompt: String = "Tidy the imports.",
        intendedTasks: [String] = ["Sort imports", "Remove unused imports"],
        expectedOutputFormat: String = "A diff",
        allowedTools: [String]? = ["read_file"],
        modelConfig: AssistantModelConfig = .specific(provider: "claude", model: "claude-sonnet-4"),
        permissionProfile: AssistantPermissionProfile = .workspaceModify,
        inputRequirements: [String]? = ["A workspace path"],
        version: Int = 2
    ) -> AssistantDefinition {
        AssistantDefinition(
            id: id, name: name, description: description, category: category, icon: icon,
            systemPrompt: systemPrompt, intendedTasks: intendedTasks,
            expectedOutputFormat: expectedOutputFormat, allowedTools: allowedTools,
            modelConfig: modelConfig, permissionProfile: permissionProfile,
            inputRequirements: inputRequirements, version: version)
    }

    private static func record(
        for preset: AssistantDefinition,
        source: RemoteAssistant.Source = .override,
        name: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        systemPrompt: String? = nil,
        version: Int? = nil
    ) -> RemoteAssistant {
        RemoteAssistant(
            id: preset.persistenceID ?? UUID(),
            name: name ?? preset.name,
            description: description ?? preset.description,
            icon: icon ?? preset.icon,
            category: preset.category.remote,
            systemPrompt: systemPrompt ?? preset.systemPrompt,
            intendedTasks: preset.intendedTasks,
            expectedOutputFormat: preset.expectedOutputFormat,
            allowedTools: preset.allowedTools,
            provider: preset.modelConfig.provider,
            model: preset.modelConfig.model,
            permissionProfile: preset.permissionProfile.remote,
            inputRequirements: preset.inputRequirements,
            version: version ?? preset.version,
            source: source)
    }

    @Test("Catalog loads with zero presets: empty, no crash, no conflicts")
    func emptyCatalogLoadsWithZeroPresets() {
        #expect(BuiltInPresets.all.isEmpty)
        let catalog = AssistantCatalog()
        #expect(catalog.allDefinitions.isEmpty)
        #expect(catalog.builtInDefinitions.isEmpty)
        #expect(catalog.customDefinitions.isEmpty)
        #expect(catalog.duplicateBuiltinIDs.isEmpty)
        #expect(catalog.unmatchedOverrideIDs.isEmpty)
        #expect(catalog.customizedBuiltIns.isEmpty)
    }

    @Test("Built-in ID is builtin.<category-slug>.<slug>")
    func builtInIDFormat() {
        #expect(
            AssistantDefinition.builtInID(category: .codeMaintenance, slug: "tidy-imports")
                == "builtin.code-maintenance.tidy-imports")
        #expect(
            AssistantDefinition.builtInID(category: .specializedProductivity, slug: "plan-a-release")
                == "builtin.specialized-productivity.plan-a-release")
    }

    @Test("ID prefix detection separates built-ins, customs and anything else")
    func idPrefixDetection() {
        #expect(AssistantDefinition.isBuiltInID("builtin.code-maintenance.tidy-imports"))
        #expect(!AssistantDefinition.isBuiltInID("custom.aaaaaaaa-1111-4111-8111-111111111111"))
        #expect(!AssistantDefinition.isBuiltInID("builtin"))
        #expect(!AssistantDefinition.isBuiltInID("not-an-id"))
        #expect(AssistantDefinition.isCustomID("custom.aaaaaaaa-1111-4111-8111-111111111111"))
        #expect(!AssistantDefinition.isCustomID("builtin.code-maintenance.tidy-imports"))
        #expect(!AssistantDefinition.isCustomID("custom"))
        #expect(!AssistantDefinition.isCustomID("not-an-id"))
    }

    @Test("Custom ID embeds its UUID and round-trips through the persistence ID")
    func customIDRoundTrips() {
        let uuid = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!
        let stableID = AssistantDefinition.customID(uuid)
        #expect(stableID == "custom.aaaaaaaa-1111-4111-8111-111111111111")
        #expect(AssistantDefinition.persistenceID(forStableID: stableID) == uuid)
        #expect(AssistantDefinition.persistenceID(forStableID: "not-an-id") == nil)
    }

    @Test("Slug validation accepts lowercase kebab and rejects the rest")
    func slugValidation() {
        for slug in ["a", "tidy-imports", "fix-2", "a1-b2-c3"] {
            #expect(AssistantDefinition.isValidSlug(slug), "Expected valid slug: \(slug)")
        }
        for slug in ["", "-x", "x-", "a--b", "HasCaps", "has space", "has_underscore", "has.dot", "é"] {
            #expect(!AssistantDefinition.isValidSlug(slug), "Expected invalid slug: \(slug)")
        }
    }

    @Test("Built-in persistence ID is a deterministic UUIDv5 of the stable ID")
    func persistenceIDIsDeterministicUUIDv5() {
        let first = AssistantDefinition.persistenceID(forStableID: "builtin.code-maintenance.tidy-imports")
        let second = AssistantDefinition.persistenceID(forStableID: "builtin.code-maintenance.tidy-imports")
        #expect(first != nil)
        #expect(first == second)
        let other = AssistantDefinition.persistenceID(forStableID: "builtin.code-maintenance.sort-imports")
        #expect(other != first)
        let bytes = first!.uuid
        #expect((bytes.6 >> 4) == 5)
        #expect((bytes.8 & 0xC0) == 0x80)
    }

    @Test("Category round-trips all six raw values with the exact display names")
    func categoryRoundTripsAllSix() {
        #expect(AssistantCategory.allCases.count == 6)
        let expected: [(String, String)] = [
            ("code-maintenance", "Code Maintenance"),
            ("code-review-security", "Code Review & Security"),
            ("building-fixing", "Building & Fixing"),
            ("repository-intelligence", "Repository Intelligence"),
            ("git-workflow-automation", "Git & Workflow Automation"),
            ("specialized-productivity", "Specialized Engineering & Productivity"),
        ]
        for (rawValue, displayName) in expected {
            let category = AssistantCategory(rawValue: rawValue)
            #expect(category != nil)
            #expect(category?.displayName == displayName)
            #expect(category?.remote.rawValue == rawValue)
            #expect(AssistantCategory(remote: category!.remote) == category)
        }
        #expect(AssistantCategory(remote: .unknown) == nil)
        #expect(AssistantCategory(rawValue: "not-a-category") == nil)
    }

    @Test("Permission profile round-trips its four raw values and rejects unknown")
    func permissionProfileRoundTrips() {
        for rawValue in ["read-only", "workspace-modify", "terminal", "approval-required"] {
            let profile = AssistantPermissionProfile(rawValue: rawValue)
            #expect(profile != nil)
            #expect(profile?.remote.rawValue == rawValue)
            #expect(AssistantPermissionProfile(remote: profile!.remote) == profile)
        }
        #expect(AssistantPermissionProfile(remote: .unknown) == nil)
    }

    @Test("Model config keeps default, specific and current-app-model distinct")
    func modelConfigCases() {
        let specific = AssistantModelConfig(provider: "claude", model: "claude-sonnet-4")
        #expect(specific.provider == "claude")
        #expect(specific.model == "claude-sonnet-4")
        #expect(AssistantModelConfig(provider: nil, model: nil) == .appDefault)
        #expect(AssistantModelConfig.appDefault.provider == nil)
        #expect(AssistantModelConfig.appDefault.model == nil)
        #expect(AssistantModelConfig.currentAppModel.provider == nil)
        let resolved = AssistantModelConfig.currentAppModel.resolvingCurrent(
            provider: "codex", model: "gpt-5")
        #expect(resolved == .specific(provider: "codex", model: "gpt-5"))
        #expect(AssistantModelConfig.currentAppModel.resolvingCurrent(provider: nil, model: nil) == .appDefault)
        #expect(specific.resolvingCurrent(provider: "codex", model: "gpt-5") == specific)
    }

    @Test("An override changes only the fields it differs in and flags the preset customized")
    func mergeOverrideChangesOnlyChangedFields() {
        let preset = Self.preset()
        let catalog = AssistantCatalog(
            builtIns: [preset],
            stored: [Self.record(for: preset, name: "Renamed", icon: "star")])
        let resolved = catalog.builtInDefinitions.first
        #expect(resolved != nil)
        #expect(resolved?.name == "Renamed")
        #expect(resolved?.icon == "star")
        #expect(resolved?.description == preset.description)
        #expect(resolved?.category == preset.category)
        #expect(resolved?.systemPrompt == preset.systemPrompt)
        #expect(resolved?.intendedTasks == preset.intendedTasks)
        #expect(resolved?.expectedOutputFormat == preset.expectedOutputFormat)
        #expect(resolved?.allowedTools == preset.allowedTools)
        #expect(resolved?.modelConfig == preset.modelConfig)
        #expect(resolved?.permissionProfile == preset.permissionProfile)
        #expect(resolved?.inputRequirements == preset.inputRequirements)
        #expect(resolved?.version == preset.version)
        #expect(resolved?.isBuiltIn == true)
        #expect(resolved?.customized == true)
        #expect(catalog.customizedBuiltIns.count == 1)
        #expect(catalog.builtIns.first?.name == preset.name)
    }

    @Test("An override identical to its preset is not a customization")
    func identicalOverrideIsNotCustomized() {
        let preset = Self.preset()
        let catalog = AssistantCatalog(builtIns: [preset], stored: [Self.record(for: preset)])
        #expect(catalog.builtInDefinitions.first?.customized == false)
        #expect(catalog.customizedBuiltIns.isEmpty)
    }

    @Test("restoreDefaults deletes the override and returns the pristine preset")
    func restoreDefaultsDeletesOverride() {
        let preset = Self.preset()
        var catalog = AssistantCatalog(
            builtIns: [preset],
            stored: [Self.record(for: preset, name: "Renamed")])
        #expect(catalog.customizedBuiltIns.count == 1)
        let restored = catalog.restoreDefaults(builtinID: preset.id)
        #expect(restored == preset)
        #expect(catalog.builtInDefinitions.first?.customized == false)
        #expect(catalog.builtInDefinitions.first?.name == preset.name)
        #expect(catalog.customizedBuiltIns.isEmpty)
        #expect(catalog.overrideRecord(forBuiltinID: preset.id) == nil)
    }

    @Test("restoreDefaults on an unknown ID returns nil and changes nothing")
    func restoreDefaultsUnknownIDReturnsNil() {
        let preset = Self.preset()
        var catalog = AssistantCatalog(
            builtIns: [preset],
            stored: [Self.record(for: preset, name: "Renamed")])
        #expect(catalog.restoreDefaults(builtinID: "builtin.code-maintenance.nope") == nil)
        #expect(catalog.customizedBuiltIns.count == 1)
    }

    @Test("A fully custom assistant is listed separately and never looks built-in")
    func customAssistantListedSeparately() {
        let preset = Self.preset()
        let customID = UUID(uuidString: "BBBBBBBB-2222-4222-8222-222222222222")!
        let custom = RemoteAssistant(
            id: customID, name: "My Helper", description: "Helps me",
            category: .buildingFixing, systemPrompt: "Help.",
            source: .custom)
        let catalog = AssistantCatalog(builtIns: [preset], stored: [custom])
        #expect(catalog.customDefinitions.count == 1)
        let definition = catalog.customDefinitions.first
        #expect(definition?.id == "custom.bbbbbbbb-2222-4222-8222-222222222222")
        #expect(definition?.isBuiltIn == false)
        #expect(definition?.customized == false)
        #expect(catalog.allDefinitions.count == 2)
        #expect(catalog.definition(forStableID: "custom.bbbbbbbb-2222-4222-8222-222222222222") != nil)
        #expect(catalog.definition(forPersistenceID: customID)?.isBuiltIn == false)
        #expect(catalog.definition(forPersistenceID: customID)?.name == "My Helper")
        #expect(catalog.definition(forPersistenceID: preset.persistenceID!)?.isBuiltIn == true)
    }

    @Test("A custom record with an unknown category is skipped, not listed")
    func customRecordWithUnknownCategoryIsSkipped() {
        let custom = RemoteAssistant(
            id: UUID(), name: "Mystery", category: .unknown,
            systemPrompt: "Do something.", source: .custom)
        let catalog = AssistantCatalog(stored: [custom])
        #expect(catalog.allDefinitions.isEmpty)
        #expect(AssistantDefinition(stored: custom) == nil)
    }

    @Test("A preset update after customization is reported as a version gap, customization intact")
    func versionGapDetection() {
        let preset = Self.preset(version: 2)
        let catalog = AssistantCatalog(
            builtIns: [preset],
            stored: [Self.record(for: preset, name: "Renamed", version: 1)])
        let gap = catalog.versionGap(for: preset.id)
        #expect(gap?.preset == 2)
        #expect(gap?.customizedAgainst == 1)
        #expect(catalog.presetVersion(for: preset.id) == 2)
        #expect(catalog.builtInDefinitions.first?.name == "Renamed")
        #expect(catalog.builtInDefinitions.first?.customized == true)
        let current = AssistantCatalog(
            builtIns: [preset],
            stored: [Self.record(for: preset, name: "Renamed", version: 2)])
        #expect(current.versionGap(for: preset.id) == nil)
        let plain = AssistantCatalog(builtIns: [preset], stored: [])
        #expect(plain.versionGap(for: preset.id) == nil)
        #expect(plain.versionGap(for: "builtin.code-maintenance.nope") == nil)
    }

    @Test("Duplicate preset IDs are reported deterministically and the first wins")
    func duplicateIDsFirstWins() {
        let first = Self.preset(name: "First")
        let second = Self.preset(name: "Second")
        let catalog = AssistantCatalog(builtIns: [first, second], stored: [])
        #expect(catalog.duplicateBuiltinIDs == [first.id])
        #expect(catalog.builtInDefinitions.count == 1)
        #expect(catalog.builtInDefinitions.first?.name == "First")
        #expect(catalog.allDefinitions.count == 1)
    }

    @Test("Validation rejects empty name and prompt, unknown tools, duplicates and bad versions")
    func validationRejectsBadDefinitions() {
        let empty = Self.preset(name: "  ", systemPrompt: "")
        #expect(empty.validationIssues().contains(.emptyName))
        #expect(empty.validationIssues().contains(.emptySystemPrompt))
        let unknownTool = Self.preset(allowedTools: ["read_file", "not_a_real_tool"])
        #expect(unknownTool.validationIssues().contains(.unknownTool(name: "not_a_real_tool")))
        #expect(!unknownTool.validationIssues().contains(.unknownTool(name: "read_file")))
        let knownTool = Self.preset(allowedTools: ["read_file"])
        #expect(!knownTool.validationIssues().contains(where: {
            if case .unknownTool = $0 { return true }
            return false
        }))
        let duplicatedTool = Self.preset(allowedTools: ["read_file", "read_file"])
        #expect(duplicatedTool.validationIssues().contains(.duplicateToolName(name: "read_file")))
        let overlong = Self.preset(name: String(repeating: "n", count: 1025))
        #expect(overlong.validationIssues().contains(.nameTooLong))
        let badVersion = Self.preset(version: 0)
        #expect(badVersion.validationIssues().contains(.versionTooLow))
        let badID = Self.preset(id: "builtin.wrong-category.tidy-imports")
        #expect(badID.validationIssues().contains(.invalidStableID))
        #expect(Self.preset().validationIssues().isEmpty)
    }

    @Test("An override with no matching preset is reported as unmatched")
    func orphanOverrideReported() {
        let orphanID = UUID(uuidString: "CCCCCCCC-3333-4333-8333-333333333333")!
        let orphan = RemoteAssistant(
            id: orphanID, name: "Orphan", category: .codeMaintenance,
            systemPrompt: "Gone.", source: .override)
        let catalog = AssistantCatalog(stored: [orphan])
        #expect(catalog.unmatchedOverrideIDs == [orphanID])
        #expect(catalog.allDefinitions.isEmpty)
    }

    @Test("Definition lookup by persistence ID finds the built-in by its derived UUID")
    func definitionLookupByPersistenceID() {
        let preset = Self.preset()
        let catalog = AssistantCatalog(
            builtIns: [preset],
            stored: [Self.record(for: preset, name: "Renamed")])
        let found = catalog.definition(forPersistenceID: preset.persistenceID!)
        #expect(found?.name == "Renamed")
        #expect(found?.customized == true)
        #expect(catalog.definition(forPersistenceID: UUID()) == nil)
    }
}
