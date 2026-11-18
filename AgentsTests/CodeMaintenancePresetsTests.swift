import Foundation
import Testing
@testable import Agents

@Suite("Code Maintenance Presets: IDs, Content, Tools & Validation")
struct CodeMaintenancePresetsTests {

    private static let expectedNames: [String] = [
        "Dead Code Remover",
        "Code Cleanup Assistant",
        "Refactoring Specialist",
        "Duplicate Code Finder",
        "Dependency Auditor",
        "Performance Optimizer",
        "Memory Leak Investigator",
        "Architecture Analyst",
        "Documentation Generator",
        "Naming & Readability Specialist",
    ]

    private static let expectedSlugs: [String] = [
        "dead-code-remover",
        "code-cleanup-assistant",
        "refactoring-specialist",
        "duplicate-code-finder",
        "dependency-auditor",
        "performance-optimizer",
        "memory-leak-investigator",
        "architecture-analyst",
        "documentation-generator",
        "naming-readability-specialist",
    ]

    private static let expectedKeywords: [String: (String, String)] = [
        "dead-code-remover": ("dead code", "unused symbol"),
        "code-cleanup-assistant": ("formatting", "organization"),
        "refactoring-specialist": ("behavior-preserving", "extract method"),
        "duplicate-code-finder": ("duplicated", "consolidation"),
        "dependency-auditor": ("lockfile", "transitive"),
        "performance-optimizer": ("bottleneck", "profiling"),
        "memory-leak-investigator": ("retain cycle", "Instruments"),
        "architecture-analyst": ("coupling", "separation of concerns"),
        "documentation-generator": ("DocC", "doc comment"),
        "naming-readability-specialist": ("naming convention", "identifier"),
    ]

    private static let expectedProfiles: [String: AssistantPermissionProfile] = [
        "dead-code-remover": .approvalRequired,
        "code-cleanup-assistant": .workspaceModify,
        "refactoring-specialist": .approvalRequired,
        "duplicate-code-finder": .readOnly,
        "dependency-auditor": .readOnly,
        "performance-optimizer": .workspaceModify,
        "memory-leak-investigator": .readOnly,
        "architecture-analyst": .readOnly,
        "documentation-generator": .workspaceModify,
        "naming-readability-specialist": .workspaceModify,
    ]

    private static func slug(of preset: AssistantDefinition) -> String {
        String(preset.id.split(separator: ".").last ?? "")
    }

    @Test("Code Maintenance group holds exactly the ten spec presets, in order")
    func groupHoldsExactlyTenPresetsInOrder() {
        #expect(CodeMaintenancePresets.all.count == 10)
        #expect(CodeMaintenancePresets.all.map(\.name) == Self.expectedNames)
        #expect(CodeMaintenancePresets.all.map { Self.slug(of: $0) } == Self.expectedSlugs)
    }

    @Test("Preset IDs are unique and match the builtin.code-maintenance slug pattern")
    func idsAreUniqueAndMatchBuiltinPattern() {
        let ids = CodeMaintenancePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for (preset, slug) in zip(CodeMaintenancePresets.all, Self.expectedSlugs) {
            #expect(preset.id == "builtin.code-maintenance.\(slug)")
            #expect(preset.id == AssistantDefinition.builtInID(category: .codeMaintenance, slug: slug))
            #expect(AssistantDefinition.isValidSlug(slug))
        }
    }

    @Test("No duplicate slugs across the ten presets")
    func noDuplicateSlugs() {
        let slugs = CodeMaintenancePresets.all.map { Self.slug(of: $0) }
        #expect(Set(slugs).count == slugs.count)
    }

    @Test("Every preset has a non-empty description and a detailed system prompt")
    func descriptionsAndPromptsAreDetailed() {
        for preset in CodeMaintenancePresets.all {
            #expect(!preset.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!preset.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(preset.systemPrompt.count >= 600, "Prompt too short for \(preset.name)")
            #expect(!preset.expectedOutputFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!preset.intendedTasks.isEmpty)
        }
    }

    @Test("Every system prompt contains its specialty's domain keywords")
    func promptsContainDomainKeywords() {
        for preset in CodeMaintenancePresets.all {
            let keywords = Self.expectedKeywords[Self.slug(of: preset)]
            #expect(keywords != nil, "No keywords recorded for \(preset.name)")
            guard let (first, second) = keywords else { continue }
            #expect(preset.systemPrompt.contains(first), "\(preset.name) prompt lacks \(first)")
            #expect(preset.systemPrompt.contains(second), "\(preset.name) prompt lacks \(second)")
        }
    }

    @Test("Every preset lists only real registry tools")
    func allowedToolsAllExistInRegistry() {
        for preset in CodeMaintenancePresets.all {
            #expect(preset.allowedTools != nil, "\(preset.name) has no tool list")
            #expect(!(preset.allowedTools ?? []).isEmpty)
            #expect(
                SystemToolRegistry.unknownToolNames(in: preset.allowedTools).isEmpty,
                "Unknown tools in \(preset.name): \(SystemToolRegistry.unknownToolNames(in: preset.allowedTools))"
            )
        }
    }

    @Test("Read-only presets grant no write, edit, or terminal tools")
    func readOnlyPresetsHaveNoMutatingTools() {
        let mutating: Set<String> = [
            "write_file", "file_write", "create_file", "edit_file", "multi_edit_file",
            "code_replace", "code_multi_edit", "delete_file", "delete_directory",
            "move_file", "copy_file", "create_directory", "create_terminal",
            "write_terminal", "run_build", "run_tests", "git_commit", "git_push",
            "symbol_rename_project", "symbol_move_file", "dead_code_eliminator",
        ]
        for preset in CodeMaintenancePresets.all where preset.permissionProfile == .readOnly {
            let tools = Set(preset.allowedTools ?? [])
            #expect(tools.isDisjoint(with: mutating), "\(preset.name) is read-only but lists mutating tools")
        }
    }

    @Test("Every preset is in the code-maintenance category, version 1, built-in")
    func categoryVersionAndBuiltInFlags() {
        for preset in CodeMaintenancePresets.all {
            #expect(preset.category == .codeMaintenance)
            #expect(preset.version == 1)
            #expect(preset.isBuiltIn == true)
            #expect(preset.customized == false)
            #expect(preset.modelConfig == .appDefault)
        }
    }

    @Test("Permission profiles match the destructive or read-only nature of each preset")
    func permissionProfilesAreHonest() {
        for preset in CodeMaintenancePresets.all {
            let expected = Self.expectedProfiles[Self.slug(of: preset)]
            #expect(expected != nil, "No profile recorded for \(preset.name)")
            #expect(preset.permissionProfile == expected)
        }
    }

    @Test("Every preset passes validation with no issues")
    func allPresetsValidateCleanly() {
        for preset in CodeMaintenancePresets.all {
            #expect(preset.validationIssues().isEmpty, "\(preset.name) issues: \(preset.validationIssues())")
        }
    }

    @Test("The group is registered in BuiltInPresets and loads through the catalog")
    func groupIsRegisteredInBuiltInPresets() {
        #expect(BuiltInPresets.groups.contains(CodeMaintenancePresets.all))
        let catalog = AssistantCatalog()
        for preset in CodeMaintenancePresets.all {
            #expect(catalog.definition(forStableID: preset.id)?.name == preset.name)
        }
    }
}
