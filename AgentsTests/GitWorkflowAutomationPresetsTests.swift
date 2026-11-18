import Foundation
import Testing
@testable import Agents

@Suite("Git Workflow Automation Presets")
struct GitWorkflowAutomationPresetsTests {

    private static let expectedNames = [
        "Commit Message Writer",
        "Branch Cleanup Assistant",
        "PR Description Writer",
        "PR Review Responder",
        "Merge Conflict Resolver",
        "Git History Analyst",
        "Release Notes Writer",
        "Issue Triage Assistant",
        "CI Failure Investigator",
        "Repository Health Monitor",
    ]

    private static let expectedSlugs = [
        "commit-message-writer",
        "branch-cleanup-assistant",
        "pr-description-writer",
        "pr-review-responder",
        "merge-conflict-resolver",
        "git-history-analyst",
        "release-notes-writer",
        "issue-triage-assistant",
        "ci-failure-investigator",
        "repository-health-monitor",
    ]

    private static let domainKeywords: [String: [String]] = [
        "commit-message-writer": ["staged diff", "Conventional Commits"],
        "branch-cleanup-assistant": ["merged", "stale branch"],
        "pr-description-writer": ["pull request", "Testing Notes"],
        "pr-review-responder": ["review feedback", "reviewer"],
        "merge-conflict-resolver": ["conflict markers", "ours"],
        "git-history-analyst": ["bisect", "regression"],
        "release-notes-writer": ["release notes", "Breaking Changes"],
        "issue-triage-assistant": ["duplicate", "severity"],
        "ci-failure-investigator": ["flaky", "deterministic"],
        "repository-health-monitor": ["snapshot", "stale files"],
    ]

    @Test("Preset group has exactly ten definitions")
    func countIsTen() {
        #expect(GitWorkflowAutomationPresets.all.count == 10)
    }

    @Test("Names match the spec, in order")
    func namesMatchSpecInOrder() {
        #expect(GitWorkflowAutomationPresets.all.map(\.name) == Self.expectedNames)
    }

    @Test("IDs are unique and match the built-in git-workflow-automation pattern")
    func idsAreUniqueAndPatterned() {
        let ids = GitWorkflowAutomationPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for (index, preset) in GitWorkflowAutomationPresets.all.enumerated() {
            #expect(preset.id == "builtin.git-workflow-automation.\(Self.expectedSlugs[index])")
        }
    }

    @Test("Slugs are unique and valid")
    func slugsAreUniqueAndValid() {
        #expect(Set(Self.expectedSlugs).count == Self.expectedSlugs.count)
        for slug in Self.expectedSlugs {
            #expect(AssistantDefinition.isValidSlug(slug))
        }
    }

    @Test("Descriptions and system prompts are non-empty, prompts are detailed")
    func promptsAreDetailed() {
        for preset in GitWorkflowAutomationPresets.all {
            #expect(!preset.description.isEmpty)
            #expect(!preset.systemPrompt.isEmpty)
            #expect(preset.systemPrompt.count >= 600)
        }
    }

    @Test("Every prompt carries at least two keywords specific to its specialty")
    func promptsCarryDomainKeywords() {
        for preset in GitWorkflowAutomationPresets.all {
            let slug = preset.id.split(separator: ".").last.map(String.init) ?? ""
            let keywords = Self.domainKeywords[slug] ?? []
            #expect(keywords.count >= 2)
            for keyword in keywords {
                #expect(preset.systemPrompt.contains(keyword), "Missing keyword '\(keyword)' in \(preset.id)")
            }
        }
    }

    @Test("Every allowed tool exists in the system tool registry")
    func allowedToolsExistInRegistry() {
        for preset in GitWorkflowAutomationPresets.all {
            let unknown = SystemToolRegistry.unknownToolNames(in: preset.allowedTools)
            #expect(unknown.isEmpty, "Unknown tools in \(preset.id): \(unknown)")
        }
    }

    @Test("All categories are git-workflow-automation")
    func categoriesAreGitWorkflowAutomation() {
        for preset in GitWorkflowAutomationPresets.all {
            #expect(preset.category == .gitWorkflowAutomation)
        }
    }

    @Test("All versions are 1")
    func versionsAreOne() {
        for preset in GitWorkflowAutomationPresets.all {
            #expect(preset.version == 1)
        }
    }

    @Test("Every definition passes validation with no issues")
    func definitionsValidateCleanly() {
        for preset in GitWorkflowAutomationPresets.all {
            #expect(preset.validationIssues().isEmpty, "Issues in \(preset.id): \(preset.validationIssues())")
        }
    }

    @Test("Permission profiles match the mutating surface of each preset")
    func permissionProfilesAreHonest() {
        let profiles = Dictionary(
            uniqueKeysWithValues: GitWorkflowAutomationPresets.all.map { ($0.id, $0.permissionProfile) })
        #expect(profiles["builtin.git-workflow-automation.commit-message-writer"] == .readOnly)
        #expect(profiles["builtin.git-workflow-automation.branch-cleanup-assistant"] == .approvalRequired)
        #expect(profiles["builtin.git-workflow-automation.pr-description-writer"] == .readOnly)
        #expect(profiles["builtin.git-workflow-automation.pr-review-responder"] == .approvalRequired)
        #expect(profiles["builtin.git-workflow-automation.merge-conflict-resolver"] == .approvalRequired)
        #expect(profiles["builtin.git-workflow-automation.git-history-analyst"] == .readOnly)
        #expect(profiles["builtin.git-workflow-automation.release-notes-writer"] == .readOnly)
        #expect(profiles["builtin.git-workflow-automation.issue-triage-assistant"] == .readOnly)
        #expect(profiles["builtin.git-workflow-automation.ci-failure-investigator"] == .readOnly)
        #expect(profiles["builtin.git-workflow-automation.repository-health-monitor"] == .readOnly)
    }

    @Test("No preset description claims a live service, webhook, or fetch capability")
    func noFakedLiveCapabilities() {
        let forbidden = ["live", "real-time", "webhook", "fetches", "fetched from"]
        for preset in GitWorkflowAutomationPresets.all {
            for phrase in forbidden {
                #expect(!preset.description.localizedCaseInsensitiveContains(phrase), "\(preset.id) description claims '\(phrase)'")
            }
            #expect(preset.systemPrompt.contains("never"), "\(preset.id) prompt states no never-do constraint")
            #expect(!preset.systemPrompt.contains("TODO:"), "\(preset.id) prompt contains a TODO stub")
        }
    }

    @Test("Built-in groups include the git workflow automation presets")
    func groupsIncludeGitWorkflowAutomation() {
        let ids = BuiltInPresets.all.map(\.id)
        for slug in Self.expectedSlugs {
            #expect(ids.contains("builtin.git-workflow-automation.\(slug)"))
        }
    }
}
