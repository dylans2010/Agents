import Foundation
import Testing
@testable import Agents

@Suite("Code Review & Security Presets: the ten built-in review assistants")
struct CodeReviewSecurityPresetsTests {

    private static let expectedNames = [
        "PR Reviewer",
        "Security Auditor",
        "Bug Risk Reviewer",
        "API Compatibility Reviewer",
        "Swift Code Reviewer",
        "TypeScript Reviewer",
        "Accessibility Reviewer",
        "Error Handling Reviewer",
        "Database Schema Reviewer",
        "Release Readiness Reviewer",
    ]

    private static let expectedSlugs = [
        "pr-reviewer",
        "security-auditor",
        "bug-risk-reviewer",
        "api-compatibility-reviewer",
        "swift-code-reviewer",
        "typescript-reviewer",
        "accessibility-reviewer",
        "error-handling-reviewer",
        "database-schema-reviewer",
        "release-readiness-reviewer",
    ]

    private static let domainKeywords: [[String]] = [
        ["pull request", "diff"],
        ["injection", "OWASP"],
        ["regression", "side effect"],
        ["breaking change", "semver"],
        ["Sendable", "concurrency"],
        ["type narrowing", "generics"],
        ["VoiceOver", "Dynamic Type"],
        ["silent failure", "Result"],
        ["migration", "foreign key"],
        ["blocker", "rollback"],
    ]

    private static let mutatingToolNames: Set<String> = [
        "write_file", "file_write", "create_file", "file_create",
        "edit_file", "multi_edit_file", "code_replace", "code_insert",
        "code_multi_edit", "code_generate", "code_format", "swift_format_lint",
        "delete_file", "file_delete", "delete_directory",
        "move_file", "file_move", "copy_file", "file_copy",
        "create_directory", "dir_create", "dir_delete",
        "file_append", "file_backup", "file_rename", "regex_replace_in_files",
        "create_terminal", "write_terminal", "read_terminal", "use_terminal",
        "run_command", "run_build", "run_tests",
        "git_commit", "git_push", "git_pull",
        "git_branch_create", "git_branch_checkout", "git_cherry_pick",
        "git_stash_operator", "git_conflict_resolver", "git_bisect",
        "mem_store", "mem_delete", "mem_clear", "save_to_memory",
        "context_persistence_store", "mem_context_snapshot",
        "use_workers", "cancel_worker", "delete_worker", "start_subagent",
        "create_artifact", "delete_artifact", "execution_plan",
        "automated_repair_engine", "patch_application_engine",
        "code_mutation_engine", "dead_code_eliminator",
        "plist_edit", "plist_editor", "import_cleanup",
        "batch_rename_files", "symbol_rename_project", "symbol_move_file",
        "safe_undo", "project_restore", "project_clean", "project_archive",
        "click", "double_click", "right_click", "click_point", "drag",
        "type_text", "set_value", "press_key", "hotkey", "scroll",
        "move_cursor", "launch_app", "invoke_menu", "set_window_frame",
    ]

    @Test("The group holds exactly the ten spec presets, in spec order")
    func groupHoldsExactlyTenPresetsInOrder() {
        #expect(CodeReviewSecurityPresets.all.count == 10)
        #expect(CodeReviewSecurityPresets.all.map(\.name) == Self.expectedNames)
    }

    @Test("IDs are unique, built-in, and match the category slug pattern")
    func idsAreUniqueBuiltInAndPatterned() {
        let ids = CodeReviewSecurityPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for (index, preset) in CodeReviewSecurityPresets.all.enumerated() {
            #expect(preset.id.hasPrefix("builtin.code-review-security."))
            #expect(
                preset.id == AssistantDefinition.builtInID(
                    category: .codeReviewSecurity, slug: Self.expectedSlugs[index]))
        }
    }

    @Test("Slugs derived from IDs are unique and valid kebab slugs")
    func slugsAreUniqueAndValid() {
        let slugs = CodeReviewSecurityPresets.all.map { preset in
            String(preset.id.dropFirst("builtin.code-review-security.".count))
        }
        #expect(slugs == Self.expectedSlugs)
        #expect(Set(slugs).count == slugs.count)
        for slug in slugs {
            #expect(AssistantDefinition.isValidSlug(slug))
        }
    }

    @Test("Descriptions and system prompts are substantive and specialized")
    func descriptionsAndPromptsAreSubstantive() {
        for (index, preset) in CodeReviewSecurityPresets.all.enumerated() {
            #expect(!preset.description.isEmpty, "Empty description: \(preset.name)")
            #expect(!preset.systemPrompt.isEmpty, "Empty system prompt: \(preset.name)")
            #expect(preset.systemPrompt.count >= 600, "Short system prompt: \(preset.name)")
            #expect(!preset.expectedOutputFormat.isEmpty, "Empty output format: \(preset.name)")
            for keyword in Self.domainKeywords[index] {
                #expect(
                    preset.systemPrompt.contains(keyword),
                    "Missing domain keyword \(keyword) in \(preset.name)")
            }
        }
    }

    @Test("Every preset is a version 1 code-review-security assistant")
    func presetsAreVersionOneInCategory() {
        for preset in CodeReviewSecurityPresets.all {
            #expect(preset.category == .codeReviewSecurity)
            #expect(preset.version == 1)
            #expect(preset.isBuiltIn)
        }
    }

    @Test("Every preset is read-only with the app default model")
    func presetsAreReadOnlyWithAppDefaultModel() {
        for preset in CodeReviewSecurityPresets.all {
            #expect(preset.permissionProfile == .readOnly)
            #expect(preset.modelConfig == .appDefault)
        }
    }

    @Test("Every preset declares real registry tools and no mutating ones")
    func allowedToolsAreRealAndReadOnly() {
        for preset in CodeReviewSecurityPresets.all {
            let tools = preset.allowedTools
            #expect(tools != nil, "Missing allowedTools: \(preset.name)")
            #expect(!(tools ?? []).isEmpty, "Empty allowedTools: \(preset.name)")
            #expect(
                SystemToolRegistry.unknownToolNames(in: tools).isEmpty,
                "Unknown tools in \(preset.name): \(SystemToolRegistry.unknownToolNames(in: tools))")
            let mutating = (tools ?? []).filter { Self.mutatingToolNames.contains($0) }
            #expect(mutating.isEmpty, "Mutating tools in \(preset.name): \(mutating)")
        }
    }

    @Test("Every preset passes its own validation with no issues")
    func presetsValidateCleanly() {
        for preset in CodeReviewSecurityPresets.all {
            #expect(preset.validationIssues().isEmpty, "Issues in \(preset.name): \(preset.validationIssues())")
        }
    }

    @Test("The group is registered in the built-in preset catalog")
    func groupIsRegisteredInBuiltInPresets() {
        #expect(BuiltInPresets.groups.contains(CodeReviewSecurityPresets.all))
        let registeredIDs = Set(BuiltInPresets.all.map(\.id))
        for preset in CodeReviewSecurityPresets.all {
            #expect(registeredIDs.contains(preset.id), "Not registered: \(preset.id)")
        }
    }

    @Test("Intended tasks and output formats are concrete, not empty")
    func tasksAndOutputFormatsAreConcrete() {
        for preset in CodeReviewSecurityPresets.all {
            #expect(!preset.intendedTasks.isEmpty, "No intended tasks: \(preset.name)")
            for task in preset.intendedTasks {
                #expect(!task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            #expect(preset.expectedOutputFormat.contains("file and line"))
        }
    }
}
