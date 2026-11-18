import Foundation
import Testing
@testable import Agents

@Suite("Repository Intelligence Presets")
struct RepositoryIntelligencePresetsTests {

    private static let expectedNames: [String] = [
        "Codebase Explainer",
        "Repository Q&A",
        "Commit Summarizer",
        "Change Impact Analyst",
        "Dependency Map Analyst",
        "Technical Debt Reporter",
        "Project Documentation Analyst",
        "API Documentation Assistant",
        "Onboarding Guide Generator",
        "Changelog Generator",
    ]

    private static let expectedSlugs: [String] = [
        "codebase-explainer",
        "repository-qa",
        "commit-summarizer",
        "change-impact-analyst",
        "dependency-map-analyst",
        "technical-debt-reporter",
        "project-documentation-analyst",
        "api-documentation-assistant",
        "onboarding-guide-generator",
        "changelog-generator",
    ]

    private static let domainKeywords: [[String]] = [
        ["architecture", "module"],
        ["evidence", "file path"],
        ["commit", "diff"],
        ["blast radius", "call graph"],
        ["dependency graph", "module"],
        ["technical debt", "priorit"],
        ["documentation", "coverage"],
        ["endpoint", "signature"],
        ["onboarding", "setup"],
        ["changelog", "conventional commit"],
    ]

    private static let writeEditTerminalTools: Set<String> = [
        "write_file", "edit_file", "multi_edit_file", "code_insert", "code_replace",
        "code_multi_edit", "code_generate", "create_file", "file_write", "file_create",
        "file_append", "file_copy", "file_move", "file_rename", "file_delete",
        "delete_file", "delete_directory", "create_directory", "dir_create", "dir_delete",
        "create_terminal", "write_terminal", "read_terminal", "run_build", "run_tests",
        "run_command", "use_terminal", "git_commit", "git_push", "git_pull",
        "git_branch_create", "git_branch_checkout", "git_cherry_pick", "git_stash_operator",
        "git_conflict_resolver", "move_file", "copy_file", "mem_store", "mem_delete",
        "mem_clear", "code_mutation_engine", "dead_code_eliminator", "automated_repair_engine",
        "patch_application_engine", "regex_replace_in_files", "batch_rename_files",
        "symbol_rename_project", "symbol_move_file", "import_cleanup", "plist_edit",
        "plist_editor", "safe_undo", "start_subagent", "use_workers", "cancel_worker",
        "delete_worker", "execution_plan", "intel_plan_task", "intel_breakdown_task",
        "docs_generate", "readme_generate", "markdown_toc_generate",
    ]

    @Test("Repository Intelligence group holds exactly the 10 presets in spec order")
    func presetCountAndOrder() {
        #expect(RepositoryIntelligencePresets.all.count == 10)
        #expect(RepositoryIntelligencePresets.all.map(\.name) == Self.expectedNames)
    }

    @Test("Preset IDs are unique and match the builtin repository-intelligence pattern")
    func presetIDsAreUniqueAndPatterned() {
        let ids = RepositoryIntelligencePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for (index, preset) in RepositoryIntelligencePresets.all.enumerated() {
            #expect(preset.id == "builtin.repository-intelligence.\(Self.expectedSlugs[index])")
        }
    }

    @Test("No duplicate slugs across the presets")
    func presetSlugsAreUnique() {
        let slugs = RepositoryIntelligencePresets.all.map { $0.id.split(separator: ".").last.map(String.init) ?? "" }
        #expect(slugs == Self.expectedSlugs)
        #expect(Set(slugs).count == slugs.count)
    }

    @Test("Every preset has a non-empty description and a detailed system prompt")
    func presetsHaveDetailedPrompts() {
        for preset in RepositoryIntelligencePresets.all {
            #expect(!preset.description.isEmpty)
            #expect(!preset.systemPrompt.isEmpty)
            #expect(preset.systemPrompt.count >= 600)
        }
    }

    @Test("Every system prompt contains at least two keywords specific to its specialty")
    func promptsContainDomainKeywords() {
        for (index, preset) in RepositoryIntelligencePresets.all.enumerated() {
            let prompt = preset.systemPrompt.lowercased()
            for keyword in Self.domainKeywords[index] {
                #expect(prompt.contains(keyword), "Preset \(preset.name) prompt is missing keyword \(keyword)")
            }
        }
    }

    @Test("Every preset belongs to the repository-intelligence category and is version 1")
    func presetsHaveCategoryAndVersion() {
        for preset in RepositoryIntelligencePresets.all {
            #expect(preset.category == .repositoryIntelligence)
            #expect(preset.version == 1)
        }
    }

    @Test("Every preset is read-only and built in")
    func presetsAreReadOnlyBuiltIns() {
        for preset in RepositoryIntelligencePresets.all {
            #expect(preset.permissionProfile == .readOnly)
            #expect(preset.isBuiltIn)
        }
    }

    @Test("Every allowed tool exists in the system tool registry")
    func allowedToolsExistInRegistry() {
        for preset in RepositoryIntelligencePresets.all {
            #expect(SystemToolRegistry.unknownToolNames(in: preset.allowedTools).isEmpty)
        }
    }

    @Test("No preset exposes a write, edit, or terminal tool")
    func presetsExposeNoWriteEditOrTerminalTools() {
        for preset in RepositoryIntelligencePresets.all {
            let tools = Set(preset.allowedTools ?? [])
            #expect(tools.intersection(Self.writeEditTerminalTools).isEmpty)
        }
    }

    @Test("Every preset passes definition validation")
    func presetsPassValidation() {
        for preset in RepositoryIntelligencePresets.all {
            #expect(preset.validationIssues().isEmpty)
        }
    }

    @Test("Built-in preset group is registered in the catalog groups")
    func presetsAreRegisteredInBuiltInPresets() {
        #expect(BuiltInPresets.groups.contains { $0.map(\.id) == RepositoryIntelligencePresets.all.map(\.id) })
        #expect(BuiltInPresets.all.contains { $0.id == "builtin.repository-intelligence.codebase-explainer" })
    }
}
