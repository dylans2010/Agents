import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant Report Builder")
struct AssistantReportBuilderTests {

    private static func makeDefinition(
        category: AssistantCategory,
        permissionProfile: AssistantPermissionProfile = .readOnly,
        modelConfig: AssistantModelConfig = .specific(provider: "claude", model: "claude-sonnet-4")
    ) -> AssistantDefinition {
        AssistantDefinition(
            id: "builtin.\(category.rawValue).test",
            name: "Test Assistant",
            category: category,
            systemPrompt: "Do the work.",
            modelConfig: modelConfig,
            permissionProfile: permissionProfile
        )
    }

    private static func makeRecord(
        status: String = "completed",
        result: String? = nil,
        error: String? = nil,
        targetFiles: [String] = [],
        transcriptItems: Int = 0,
        elapsedSeconds: Double = 90,
        completedAt: Double? = 1090
    ) -> WorkerRecord {
        WorkerRecord(
            id: "w1", name: "worker-one", parentThreadId: "p1", threadId: "t1",
            task: "Review the auth module.", provider: "claude", targetFiles: targetFiles,
            status: status, cancelRequested: false, transcriptStart: 0,
            transcriptItems: transcriptItems, elapsedSeconds: elapsedSeconds, createdAt: 1000,
            startedAt: 1000, completedAt: completedAt, error: error, result: result, progress: nil
        )
    }

    private static func makeDiffFile(
        path: String = "Sources/Auth.swift",
        status: String = "modified",
        additions: Int = 12,
        deletions: Int = 3,
        patch: String = "@@ -1,3 +1,4 @@\n context\n+added\n-removed\n context\n"
    ) -> RemoteDiff.File {
        RemoteDiff.File(
            path: path, status: status, additions: additions, deletions: deletions,
            isBinary: false, patch: patch
        )
    }

    private static func makeToolItem(title: String, category: String, status: String) -> RemoteItem {
        RemoteItem(
            id: UUID(), index: 0, kind: .tool, text: "", title: title, detail: "Read the file",
            category: category, status: status
        )
    }

    @Test("Code review category builds a review report")
    func reviewShapeForCodeReviewCategory() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: "All clear."),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.header.assistantName == "Test Assistant")
        #expect(review.summary == "All clear.")
        #expect(review.findings.isEmpty)
        #expect(review.recommendations.isEmpty)
    }

    @Test("Building category builds a build report")
    func buildShapeForBuildingCategory() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: "Fixed the crash."),
            definition: Self.makeDefinition(category: .buildingFixing, permissionProfile: .workspaceModify),
            diff: RemoteDiff(title: "Uncommitted", files: [Self.makeDiffFile()])
        ))
        guard case .build(let build) = report else {
            Issue.record("Expected a build report")
            return
        }
        #expect(build.summary == "Fixed the crash.")
        #expect(build.filesChanged.count == 1)
        #expect(build.filesChanged[0].path == "Sources/Auth.swift")
        #expect(build.diffAvailability == .attached)
        #expect(build.totalAdditions == 12)
        #expect(build.totalDeletions == 3)
    }

    @Test("Repository intelligence category builds an analysis report")
    func analysisShapeForRepositoryIntelligenceCategory() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: "The repo has three modules."),
            definition: Self.makeDefinition(category: .repositoryIntelligence)
        ))
        guard case .analysis(let analysis) = report else {
            Issue.record("Expected an analysis report")
            return
        }
        #expect(analysis.summary == "The repo has three modules.")
        #expect(analysis.evidence.isEmpty)
    }

    @Test("Code maintenance and git automation categories build build reports")
    func buildShapeForOtherChangeCategories() {
        for category in [AssistantCategory.codeMaintenance, .gitWorkflowAutomation] {
            let report = AssistantReportBuilder.build(.init(
                record: Self.makeRecord(),
                definition: Self.makeDefinition(category: category, permissionProfile: .workspaceModify)
            ))
            guard case .build = report else {
                Issue.record("Expected a build report for \(category)")
                return
            }
        }
        let analysis = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(),
            definition: Self.makeDefinition(category: .specializedProductivity)
        ))
        guard case .analysis = analysis else {
            Issue.record("Expected an analysis report for specialized productivity")
            return
        }
    }

    @Test("Summary comes from the Summary section first paragraph, else the first paragraph")
    func summaryComesFromResultText() {
        let result = """
            ## Summary
            The auth module leaks tokens on retry.

            Second paragraph of the summary.

            ## Findings
            - High: Token leak in Sources/Auth.swift:42
            """
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: result),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.summary == "The auth module leaks tokens on retry.")
        #expect(review.findings.count == 1)
        #expect(review.findings[0].severity == .high)
        #expect(review.findings[0].file == "Sources/Auth.swift")
        #expect(review.findings[0].line == 42)
    }

    @Test("A result with no headings yields a summary only, with every other section empty")
    func emptySectionsAreOmitted() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: "Done. Nothing else to report."),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.summary == "Done. Nothing else to report.")
        #expect(review.findings.isEmpty)
        #expect(review.recommendations.isEmpty)
        #expect(review.warnings.isEmpty)
        #expect(review.errors.isEmpty)
        #expect(review.nextSteps.isEmpty)
        #expect(!review.noModificationsConfirmed)
        #expect(!report.markdownRepresentation.contains("## Findings"))
        #expect(!report.markdownRepresentation.contains("## Recommendations"))
        #expect(!report.markdownRepresentation.contains("No workspace modifications"))
    }

    @Test("Findings parse severity labels and file:line refs, sorted critical first")
    func findingsParseSeverityAndFileLine() {
        let result = """
            ## Findings
            - Low: Unused import in Sources/Util.swift:3
            - Critical: Hardcoded secret in Sources/Config.swift:17
            - Medium: Slow loop in Sources/Cache.swift:88
            """
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: result),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.findings.count == 3)
        #expect(review.findings[0].severity == .critical)
        #expect(review.findings[0].file == "Sources/Config.swift")
        #expect(review.findings[0].line == 17)
        #expect(review.findings[1].severity == .medium)
        #expect(review.findings[2].severity == .low)
    }

    @Test("A modifying run attaches the diff files from the worker thread diff")
    func modifyingRunAttachesDiffFiles() {
        let diff = RemoteDiff(title: "Uncommitted", files: [
            Self.makeDiffFile(),
            Self.makeDiffFile(path: "Sources/Net.swift", status: "added", additions: 40, deletions: 0, patch: ""),
        ])
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(targetFiles: ["Sources/Auth.swift"]),
            definition: Self.makeDefinition(category: .buildingFixing, permissionProfile: .workspaceModify),
            diff: diff
        ))
        guard case .build(let build) = report else {
            Issue.record("Expected a build report")
            return
        }
        #expect(build.filesChanged.count == 2)
        #expect(build.diffAvailability == .attached)
        #expect(build.totalAdditions == 52)
    }

    @Test("A modifying run with no diff states the diff source is unavailable with a reason")
    func modifyingRunWithoutDiffStatesUnavailable() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(targetFiles: ["Sources/Auth.swift"]),
            definition: Self.makeDefinition(category: .buildingFixing, permissionProfile: .workspaceModify)
        ))
        guard case .build(let build) = report else {
            Issue.record("Expected a build report")
            return
        }
        #expect(build.filesChanged.isEmpty)
        guard case .unavailable(let reason) = build.diffAvailability else {
            Issue.record("Expected unavailable diff availability")
            return
        }
        #expect(!reason.isEmpty)
        #expect(report.markdownRepresentation.contains("Changed files unavailable"))
    }

    @Test("A modifying run falls back to turn change files when the diff is missing")
    func modifyingRunFallsBackToTurnChangedFiles() {
        let changed = [RemoteChangedFile(path: "Sources/Auth.swift", status: "modified", additions: 5, deletions: 1)]
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(),
            definition: Self.makeDefinition(category: .buildingFixing, permissionProfile: .workspaceModify),
            turnChangedFiles: changed
        ))
        guard case .build(let build) = report else {
            Issue.record("Expected a build report")
            return
        }
        #expect(build.filesChanged.count == 1)
        #expect(build.filesChanged[0].path == "Sources/Auth.swift")
        #expect(build.diffAvailability == .attached)
    }

    @Test("A read-only run with an empty diff confirms no workspace modifications")
    func readOnlyRunWithEmptyDiffConfirmsNoModifications() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: "Reviewed."),
            definition: Self.makeDefinition(category: .codeReviewSecurity),
            diff: RemoteDiff(title: "Uncommitted", files: [])
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.noModificationsConfirmed)
        #expect(report.markdownRepresentation.contains("No workspace modifications were made by this run."))
    }

    @Test("A read-only run without a diff does not claim no modifications")
    func readOnlyRunWithoutDiffOmitsNoModificationClaim() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: "Reviewed."),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(!review.noModificationsConfirmed)
        #expect(!report.markdownRepresentation.contains("No workspace modifications"))
    }

    @Test("A build run with an empty diff reports confirmed no changes")
    func buildRunWithEmptyDiffReportsConfirmedNoChanges() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(),
            definition: Self.makeDefinition(category: .buildingFixing, permissionProfile: .workspaceModify),
            diff: RemoteDiff(title: "Uncommitted", files: [])
        ))
        guard case .build(let build) = report else {
            Issue.record("Expected a build report")
            return
        }
        #expect(build.diffAvailability == .confirmedNoChanges)
    }

    @Test("The record error surfaces in the report errors section")
    func errorsSurfaceRecordError() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(status: "failed", error: "Provider timed out."),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.errors == ["Provider timed out."])
        #expect(review.header.status == .failed)
        #expect(review.header.error == "Provider timed out.")
    }

    @Test("Tool activity comes from transcript tool items only")
    func toolActivityComesFromTranscriptToolItems() {
        let items = [
            Self.makeToolItem(title: "Read Sources/Auth.swift", category: "read", status: "completed"),
            Self.makeToolItem(title: "Search for token", category: "search", status: "completed"),
            RemoteItem(id: UUID(), index: 2, kind: .assistant, text: "Here is the review."),
        ]
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(transcriptItems: 3),
            definition: Self.makeDefinition(category: .codeReviewSecurity),
            transcriptItems: items
        ))
        #expect(report.header.toolActivity.count == 2)
        #expect(report.header.toolActivity[0].title == "Read Sources/Auth.swift")
        #expect(report.header.toolActivity[0].category == "read")
        #expect(report.header.toolActivity[1].category == "search")
    }

    @Test("Duration prefers completed minus started, falling back to elapsed seconds")
    func durationPrefersCompletedMinusStarted() {
        let finished = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(elapsedSeconds: 90, completedAt: 1090),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        #expect(finished.header.durationSeconds == 90)
        let running = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(status: "running", elapsedSeconds: 45, completedAt: nil),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        #expect(running.header.durationSeconds == 45)
        #expect(running.header.status == .running)
    }

    @Test("Header carries the record provider and the definition model")
    func headerCarriesProviderAndModel() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        #expect(report.header.provider == "claude")
        #expect(report.header.model == "claude-sonnet-4")
        #expect(report.header.runName == "worker-one")
        #expect(report.header.workerThreadID == "t1")
    }

    @Test("Tests section parses pass, fail and skip outcomes")
    func testsParsePassFailOutcomes() {
        let result = """
            ## Tests
            - PASS: AuthTests.testLogin
            - FAIL: AuthTests.testRefresh
            - SKIP: AuthTests.testLegacy
            """
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: result),
            definition: Self.makeDefinition(category: .buildingFixing, permissionProfile: .workspaceModify),
            diff: RemoteDiff(title: "Uncommitted", files: [])
        ))
        guard case .build(let build) = report else {
            Issue.record("Expected a build report")
            return
        }
        #expect(build.testsRun.count == 3)
        #expect(build.testsRun[0].outcome == .passed)
        #expect(build.testsRun[0].name == "AuthTests.testLogin")
        #expect(build.testsRun[1].outcome == .failed)
        #expect(build.testsRun[2].outcome == .skipped)
    }

    @Test("Evidence parses file:line refs out of the Evidence section")
    func evidenceParsesFileLineRefs() {
        let result = """
            ## Evidence
            - Sources/Auth.swift:42: token stored in plaintext
            - Sources/Cache.swift:10: unbounded growth
            """
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: result),
            definition: Self.makeDefinition(category: .repositoryIntelligence)
        ))
        guard case .analysis(let analysis) = report else {
            Issue.record("Expected an analysis report")
            return
        }
        #expect(analysis.evidence.count == 2)
        #expect(analysis.evidence[0].file == "Sources/Auth.swift")
        #expect(analysis.evidence[0].line == 42)
        #expect(analysis.evidence[0].snippet == "token stored in plaintext")
    }

    @Test("A missing result yields no summary and no invented sections")
    func missingResultYieldsNoSummary() {
        let report = AssistantReportBuilder.build(.init(
            record: Self.makeRecord(result: nil),
            definition: Self.makeDefinition(category: .codeReviewSecurity)
        ))
        guard case .review(let review) = report else {
            Issue.record("Expected a review report")
            return
        }
        #expect(review.summary == nil)
        #expect(review.findings.isEmpty)
        #expect(report.markdownRepresentation.contains("# Test Assistant"))
    }
}
