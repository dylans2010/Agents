import Foundation
import Testing
@testable import Agents

@Suite("Specialized Productivity Presets: Catalog Content & Validation")
struct SpecializedProductivityPresetsTests {

    private static let expectedNames = [
        "UI Consistency Auditor",
        "Localization Assistant",
        "Accessibility Fixer",
        "Security Patch Assistant",
        "Build Configuration Auditor",
        "Database Migration Planner",
        "Product Requirements Analyst",
        "Implementation Planner",
        "Technical Researcher",
        "Project Progress Reporter",
    ]

    private static let expectedSlugs = [
        "ui-consistency-auditor",
        "localization-assistant",
        "accessibility-fixer",
        "security-patch-assistant",
        "build-configuration-auditor",
        "database-migration-planner",
        "product-requirements-analyst",
        "implementation-planner",
        "technical-researcher",
        "project-progress-reporter",
    ]

    private static let domainKeywords: [String: [String]] = [
        "ui-consistency-auditor": ["Human Interface Guidelines", "SF Symbol", "Dynamic Type", "color palette"],
        "localization-assistant": ["NSLocalizedString", "String Catalog", "pluralization", "right-to-left"],
        "accessibility-fixer": ["VoiceOver", "accessibilityLabel", "WCAG", "accessibilityHint"],
        "security-patch-assistant": ["OWASP", "Keychain", "certificate pinning", "SQL injection"],
        "build-configuration-auditor": ["xcconfig", "entitlements", "provisioning", "pbxproj"],
        "database-migration-planner": ["Core Data", "SwiftData", "mapping model", "lightweight migration"],
        "product-requirements-analyst": ["acceptance criteria", "Given-When-Then", "non-functional"],
        "implementation-planner": ["dependency graph", "call hierarchy", "integration points"],
        "technical-researcher": ["primary source", "official documentation", "never invent an API"],
        "project-progress-reporter": ["commit log", "pull requests", "test coverage"],
    ]

    private static func slug(of definition: AssistantDefinition) -> String {
        String(definition.id.dropFirst("builtin.specialized-productivity.".count))
    }

    @Test("Specialized productivity holds exactly the ten spec presets in order")
    func tenPresetsInSpecOrder() {
        #expect(SpecializedProductivityPresets.all.count == 10)
        #expect(SpecializedProductivityPresets.all.map(\.name) == Self.expectedNames)
        #expect(SpecializedProductivityPresets.all.map(Self.slug) == Self.expectedSlugs)
    }

    @Test("Preset IDs are unique and follow the builtin specialized-productivity scheme")
    func idsAreUniqueAndWellFormed() {
        let ids = SpecializedProductivityPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for definition in SpecializedProductivityPresets.all {
            #expect(definition.id.hasPrefix("builtin.specialized-productivity."))
            #expect(definition.id == AssistantDefinition.builtInID(
                category: .specializedProductivity, slug: Self.slug(of: definition)))
        }
    }

    @Test("Slugs are unique and pass the lowercase-kebab slug rule")
    func slugsAreUniqueAndValid() {
        let slugs = SpecializedProductivityPresets.all.map(Self.slug)
        #expect(Set(slugs).count == slugs.count)
        for slug in slugs {
            #expect(AssistantDefinition.isValidSlug(slug))
        }
    }

    @Test("Every preset is in the specialized productivity category at version 1")
    func categoryAndVersion() {
        for definition in SpecializedProductivityPresets.all {
            #expect(definition.category == .specializedProductivity)
            #expect(definition.version == 1)
            #expect(definition.isBuiltIn)
        }
    }

    @Test("Descriptions and system prompts are non-empty and prompts are detailed")
    func promptsAreDetailed() {
        for definition in SpecializedProductivityPresets.all {
            #expect(!definition.description.isEmpty)
            #expect(!definition.systemPrompt.isEmpty)
            #expect(definition.systemPrompt.count >= 600)
            #expect(!definition.expectedOutputFormat.isEmpty)
            #expect(!definition.intendedTasks.isEmpty)
        }
    }

    @Test("Every system prompt carries at least two keywords of its own specialty")
    func promptsCarryDomainKeywords() {
        for definition in SpecializedProductivityPresets.all {
            let keywords = Self.domainKeywords[Self.slug(of: definition)] ?? []
            #expect(!keywords.isEmpty)
            let hits = keywords.filter { definition.systemPrompt.contains($0) }
            #expect(hits.count >= 2)
        }
    }

    @Test("Every preset passes validation with no issues")
    func allPresetsValidateCleanly() {
        for definition in SpecializedProductivityPresets.all {
            #expect(definition.validationIssues().isEmpty)
        }
    }

    @Test("Every allowed tool exists in the system tool registry")
    func allowedToolsExistInRegistry() {
        for definition in SpecializedProductivityPresets.all {
            let unknown = SystemToolRegistry.unknownToolNames(in: definition.allowedTools)
            #expect(unknown.isEmpty)
            #expect(!(definition.allowedTools ?? []).isEmpty)
        }
    }

    @Test("Read-only presets stay read-only and the two fixers may modify the workspace")
    func permissionProfilesMatchIntent() {
        let readOnlySlugs: Set<String> = [
            "ui-consistency-auditor", "localization-assistant", "build-configuration-auditor",
            "database-migration-planner", "product-requirements-analyst", "implementation-planner",
            "technical-researcher", "project-progress-reporter",
        ]
        for definition in SpecializedProductivityPresets.all {
            let slug = Self.slug(of: definition)
            if readOnlySlugs.contains(slug) {
                #expect(definition.permissionProfile == .readOnly)
            }
        }
        let fixer = SpecializedProductivityPresets.all.first { Self.slug(of: $0) == "accessibility-fixer" }
        #expect(fixer?.permissionProfile == .workspaceModify)
        let security = SpecializedProductivityPresets.all.first { Self.slug(of: $0) == "security-patch-assistant" }
        #expect(security?.permissionProfile == .approvalRequired)
    }

    @Test("Model config defaults to the app default for every preset")
    func modelConfigIsAppDefault() {
        for definition in SpecializedProductivityPresets.all {
            #expect(definition.modelConfig == .appDefault)
        }
    }

    @Test("The group is registered in the built-in preset catalog")
    func groupIsRegisteredInBuiltInPresets() {
        #expect(BuiltInPresets.groups.contains(SpecializedProductivityPresets.all))
        #expect(BuiltInPresets.all.contains { $0.category == .specializedProductivity })
    }
}
