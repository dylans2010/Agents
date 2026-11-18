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

    private static let mutatingTools: Set<String> = [
        "write_file", "file_write", "create_file", "file_create",
        "edit_file", "multi_edit_file", "code_replace", "code_insert",
        "code_multi_edit", "code_generate", "code_format", "swift_format_lint",
        "delete_file", "file_delete", "delete_directory", "dir_delete",
        "move_file", "file_move", "copy_file", "file_copy",
        "create_directory", "dir_create", "file_append", "file_backup", "file_rename",
        "regex_replace_in_files", "batch_rename_files",
        "symbol_rename_project", "symbol_move_file", "import_cleanup",
        "plist_edit", "plist_editor", "safe_undo",
        "project_restore", "project_clean", "project_archive",
        "create_terminal", "write_terminal", "read_terminal", "use_terminal",
        "run_command", "run_build", "run_tests",
        "git_commit", "git_push", "git_pull",
        "git_branch_create", "git_branch_checkout", "git_cherry_pick",
        "git_stash_operator", "git_conflict_resolver", "git_bisect",
        "mem_store", "mem_delete", "mem_clear", "save_to_memory",
        "context_persistence_store", "mem_context_snapshot",
        "use_workers", "cancel_worker", "delete_worker", "start_subagent",
        "create_artifact", "delete_artifact", "execution_plan",
        "intel_plan_task", "intel_breakdown_task",
        "automated_repair_engine", "patch_application_engine",
        "code_mutation_engine", "dead_code_eliminator",
        "docs_generate", "readme_generate", "markdown_toc_generate",
        "strings_localization", "localize_app", "string_catalog_migrator",
        "manage_memory", "swift_package_manager",
        "click", "double_click", "right_click", "click_point", "drag",
        "type_text", "set_value", "press_key", "hotkey", "scroll",
        "move_cursor", "launch_app", "invoke_menu", "set_window_frame",
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

    @Test("Read-only presets grant no write, edit, terminal, or other mutating tool")
    func readOnlyPresetsGrantNoMutatingTools() {
        let readOnly = SpecializedProductivityPresets.all.filter { $0.permissionProfile == .readOnly }
        #expect(readOnly.count == 8)
        for definition in readOnly {
            let tools = Set(definition.allowedTools ?? [])
            #expect(tools.isDisjoint(with: Self.mutatingTools), "\(definition.name) is read-only but lists mutating tools")
        }
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
