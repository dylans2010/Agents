import Foundation
import Testing
@testable import Agents

@Suite("Building & Fixing Presets")
struct BuildingFixingPresetsTests {

    private static let expectedNames: [String] = [
        "Feature Builder",
        "Bug Fixer",
        "Crash Investigator",
        "UI Modernizer",
        "SwiftUI Specialist",
        "AppKit Specialist",
        "API Integration Builder",
        "Test Generator",
        "Test Failure Fixer",
        "Migration Assistant",
    ]

    private static let expectedIDs: [String] = [
        "builtin.building-fixing.feature-builder",
        "builtin.building-fixing.bug-fixer",
        "builtin.building-fixing.crash-investigator",
        "builtin.building-fixing.ui-modernizer",
        "builtin.building-fixing.swiftui-specialist",
        "builtin.building-fixing.appkit-specialist",
        "builtin.building-fixing.api-integration-builder",
        "builtin.building-fixing.test-generator",
        "builtin.building-fixing.test-failure-fixer",
        "builtin.building-fixing.migration-assistant",
    ]

    private static let domainKeywords: [String: [String]] = [
        "feature-builder": ["integration", "acceptance criteria"],
        "bug-fixer": ["reproduce", "root cause"],
        "crash-investigator": ["stack trace", "symbolication"],
        "ui-modernizer": ["visually consistent", "accessibility"],
        "swiftui-specialist": ["@state", "view lifecycle"],
        "appkit-specialist": ["nsview", "responder chain"],
        "api-integration-builder": ["authentication", "endpoint"],
        "test-generator": ["edge case", "assertion"],
        "test-failure-fixer": ["failing test", "flakiness"],
        "migration-assistant": ["migration plan", "backward compatibility"],
    ]

    @Test("Building & Fixing catalog holds exactly the ten presets")
    func presetCountIsTen() {
        #expect(BuildingFixingPresets.all.count == 10)
    }

    @Test("Preset IDs are unique and match the builtin.building-fixing pattern")
    func idsAreUniqueAndPatterned() {
        let ids = BuildingFixingPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(id.hasPrefix("builtin.building-fixing."))
        }
        #expect(ids == Self.expectedIDs)
    }

    @Test("Preset names are exactly the ten specified names in order")
    func namesMatchSpecInOrder() {
        #expect(BuildingFixingPresets.all.map(\.name) == Self.expectedNames)
    }

    @Test("Descriptions and system prompts are non-empty and prompts are detailed")
    func descriptionsAndPromptsAreDetailed() {
        for preset in BuildingFixingPresets.all {
            #expect(!preset.description.isEmpty)
            #expect(!preset.systemPrompt.isEmpty)
            #expect(preset.systemPrompt.count >= 600)
        }
    }

    @Test("Each system prompt contains at least two keywords specific to its specialty")
    func promptsContainDomainKeywords() {
        for preset in BuildingFixingPresets.all {
            let slug = preset.id.split(separator: ".").last.map(String.init) ?? ""
            let keywords = Self.domainKeywords[slug] ?? []
            #expect(keywords.count == 2)
            let prompt = preset.systemPrompt.lowercased()
            for keyword in keywords {
                #expect(prompt.contains(keyword), "Preset \(preset.name) prompt lacks keyword \(keyword)")
            }
        }
    }

    @Test("Every listed tool exists in the system tool registry")
    func allowedToolsExistInRegistry() {
        for preset in BuildingFixingPresets.all {
            let unknown = SystemToolRegistry.unknownToolNames(in: preset.allowedTools)
            #expect(unknown.isEmpty, "Preset \(preset.name) lists unknown tools: \(unknown)")
            #expect(preset.allowedTools != nil)
            #expect(!(preset.allowedTools?.isEmpty ?? true))
        }
    }

    @Test("All presets belong to the Building & Fixing category")
    func categoriesAreBuildingFixing() {
        for preset in BuildingFixingPresets.all {
            #expect(preset.category == .buildingFixing)
        }
    }

    @Test("All presets are version 1")
    func versionsAreOne() {
        for preset in BuildingFixingPresets.all {
            #expect(preset.version == 1)
        }
    }

    @Test("No two presets share a slug and every slug is valid")
    func slugsAreUniqueAndValid() {
        let slugs = BuildingFixingPresets.all.map { $0.id.split(separator: ".").last.map(String.init) ?? "" }
        #expect(Set(slugs).count == slugs.count)
        for slug in slugs {
            #expect(AssistantDefinition.isValidSlug(slug))
        }
    }

    @Test("Every preset passes validation with no issues")
    func presetsPassValidation() {
        for preset in BuildingFixingPresets.all {
            #expect(preset.validationIssues().isEmpty, "Preset \(preset.name) issues: \(preset.validationIssues())")
        }
    }

    @Test("Built-in groups include the Building & Fixing presets")
    func groupsIncludeBuildingFixingPresets() {
        #expect(BuiltInPresets.groups.contains(BuildingFixingPresets.all))
        #expect(BuiltInPresets.all.contains { $0.id == "builtin.building-fixing.feature-builder" })
    }

    @Test("Read-only diagnosis preset uses the read-only profile and no write tools")
    func crashInvestigatorIsReadOnly() {
        let investigator = BuildingFixingPresets.all.first { $0.id == "builtin.building-fixing.crash-investigator" }
        #expect(investigator?.permissionProfile == .readOnly)
        let writeTools = ["write_file", "edit_file", "multi_edit_file", "delete_file"]
        #expect(!(investigator?.allowedTools?.contains(where: writeTools.contains) ?? true))
    }

    @Test("Wide-ranging presets require approval")
    func wideRangingPresetsRequireApproval() {
        let approvalIDs: Set<String> = [
            "builtin.building-fixing.feature-builder",
            "builtin.building-fixing.migration-assistant",
        ]
        for preset in BuildingFixingPresets.all where approvalIDs.contains(preset.id) {
            #expect(preset.permissionProfile == .approvalRequired)
        }
    }

    @Test("Every preset declares the input it needs")
    func inputRequirementsAreDeclared() {
        for preset in BuildingFixingPresets.all {
            #expect(preset.inputRequirements != nil)
            #expect(!(preset.inputRequirements?.isEmpty ?? true))
        }
        let crash = BuildingFixingPresets.all.first { $0.id == "builtin.building-fixing.crash-investigator" }
        #expect(crash?.inputRequirements?.contains { $0.lowercased().contains("stack trace") } == true)
        let failure = BuildingFixingPresets.all.first { $0.id == "builtin.building-fixing.test-failure-fixer" }
        #expect(failure?.inputRequirements?.contains { $0.lowercased().contains("failing test") } == true)
    }
}
