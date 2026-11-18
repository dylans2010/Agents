import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant launch form")
@MainActor
struct AssistantLaunchViewModelTests {

    private final class LaunchRecorder {
        var calls: [(assistant: RemoteAssistant, task: String, projectID: UUID?)] = []
        var result = AssistantLaunchResult()

        func record(assistant: RemoteAssistant, task: String, projectID: UUID?) -> AssistantLaunchResult {
            calls.append((assistant: assistant, task: task, projectID: projectID))
            return result
        }
    }

    private static func definition(
        requirements: [String]? = nil,
        modelConfig: AssistantModelConfig = .appDefault,
        permissionProfile: AssistantPermissionProfile = .readOnly
    ) -> AssistantDefinition {
        AssistantDefinition(
            id: AssistantDefinition.builtInID(category: .buildingFixing, slug: "feature-builder"),
            name: "Feature Builder",
            description: "Builds features.",
            category: .buildingFixing,
            icon: "hammer",
            systemPrompt: "You are a senior feature engineer. Build the feature.",
            intendedTasks: ["Build features"],
            expectedOutputFormat: "A summary.",
            modelConfig: modelConfig,
            permissionProfile: permissionProfile,
            inputRequirements: requirements
        )
    }

    private static func viewModel(
        assistant: AssistantDefinition,
        recorder: LaunchRecorder? = nil
    ) -> AssistantLaunchViewModel {
        AssistantLaunchViewModel(
            assistant: assistant,
            launcher: { assistant, task, projectID in
                if let recorder {
                    return recorder.record(assistant: assistant, task: task, projectID: projectID)
                }
                return AssistantLaunchResult()
            }
        )
    }

    @Test("Assistant with no requirements yields only the task field")
    func noRequirementsYieldsOnlyTaskField() {
        let missing = Self.viewModel(assistant: Self.definition(requirements: nil))
        #expect(missing.fields.isEmpty)
        let empty = Self.viewModel(assistant: Self.definition(requirements: []))
        #expect(empty.fields.isEmpty)
    }

    @Test("Assistant with N requirements yields exactly those N fields")
    func requirementCountMatchesFieldCount() {
        let viewModel = Self.viewModel(assistant: Self.definition(requirements: [
            "The branch containing the changes under review",
            "The issue text pasted from the tracker",
            "Review scope: full diff or specific files or areas",
        ]))
        #expect(viewModel.fields.count == 3)
        #expect(viewModel.fields.map(\.requirement) == [
            "The branch containing the changes under review",
            "The issue text pasted from the tracker",
            "Review scope: full diff or specific files or areas",
        ])
        #expect(Set(viewModel.fields.map(\.title)).count == 3)
    }

    @Test("Requirement text maps to the matching field type")
    func requirementKindMapping() {
        let cases: [(String, AssistantLaunchFieldKind)] = [
            ("A description of the feature to build, including its acceptance criteria", .multiLineText),
            ("The staged diff for the changes to describe", .multiLineText),
            ("The crash report, stack trace, or crash log", .multiLineText),
            ("The review comments pasted from the pull request", .multiLineText),
            ("Diff, branch, or commit range under review", .multiLineText),
            ("The base branch and the head branch for the pull request", .pullRequest),
            ("Pull request number, branch name, or diff range to review", .pullRequest),
            ("The repository area or component the issue concerns, if known", .issue),
            ("The branch containing the changes under review", .branch),
            ("The default branch name the repository merges into", .branch),
            ("The list of conflicted files, or the branch being merged", .branch),
            ("Repository or directory to explain", .directory),
            ("The repository working directory to inspect", .directory),
            ("Manifests and lockfiles to audit: Package.swift, Package.resolved, Podfile, or Cartfile", .files),
            ("Schema files, migration files, or database under review", .files),
            ("The file, behavior, or time range to investigate", .files),
            ("Review scope: full diff or specific files or areas", .scope),
            ("Scope of the audit: paths, modules, or the whole workspace", .scope),
            ("Scope: a directory, target, or file to clean up", .scope),
            ("Behavior that must be preserved, including the tests that must keep passing", .constraints),
            ("The platforms, versions, or constraints the answer must respect", .constraints),
            ("Whether deletion is allowed, or report-only", .constraints),
            ("The question about the repository", .text),
            ("Commit SHA or commit range to summarize", .text),
            ("The version number for the release notes", .text),
            ("The technical question to research", .text),
        ]
        for (requirement, expected) in cases {
            #expect(
                AssistantLaunchViewModel.kind(for: requirement) == expected,
                "Requirement '\(requirement)' should map to \(expected)"
            )
        }
    }

    @Test("The task is the only required input")
    func taskIsRequired() {
        let viewModel = Self.viewModel(assistant: Self.definition(requirements: [
            "The branch containing the changes under review",
        ]))
        #expect(viewModel.validationError != nil)
        #expect(viewModel.canLaunch == false)
        viewModel.task = "   "
        #expect(viewModel.validationError != nil)
        viewModel.task = "Fix the crash on launch"
        #expect(viewModel.validationError == nil)
        #expect(viewModel.canLaunch == true)
    }

    @Test("Requirement fields are all optional")
    func requirementFieldsAreOptional() {
        let viewModel = Self.viewModel(assistant: Self.definition(requirements: [
            "The branch containing the changes under review",
            "Repository or directory to explain",
            "The issue text pasted from the tracker",
        ]))
        viewModel.task = "Explain the repository"
        #expect(viewModel.canLaunch == true)
    }

    @Test("Assembled task labels filled inputs and omits empty ones")
    func assembledTaskIncludesLabelsAndOmitsEmpty() {
        let viewModel = Self.viewModel(assistant: Self.definition(requirements: [
            "The branch containing the changes under review",
            "The issue text pasted from the tracker",
            "Review scope: full diff or specific files or areas",
        ]))
        viewModel.task = "Build the thing"
        viewModel.setText("feature/x", forField: 0)
        viewModel.setText("Crash on launch", forField: 1)
        viewModel.extraInstructions = "Be careful."
        #expect(viewModel.assembledTask == """
            Build the thing

            Branch: feature/x

            Input: Crash on launch

            Additional instructions: Be careful.
            """)
    }

    @Test("Assembled task lists chosen files and directories")
    func assembledTaskListsPaths() {
        let viewModel = Self.viewModel(assistant: Self.definition(requirements: [
            "Repository or directory to explain",
            "Manifests and lockfiles to audit: Package.swift, Package.resolved, Podfile, or Cartfile",
        ]))
        viewModel.task = "Audit the dependencies"
        viewModel.setPaths(["/Users/dylan/Projects/App"], forField: 0)
        viewModel.setPaths(["/Users/dylan/Projects/App/Package.swift", "/Users/dylan/Projects/App/Package.resolved"], forField: 1)
        #expect(viewModel.assembledTask == """
            Audit the dependencies

            Directory: /Users/dylan/Projects/App

            Files: /Users/dylan/Projects/App/Package.swift, /Users/dylan/Projects/App/Package.resolved
            """)
    }

    @Test("Assembled task never includes the assistant system prompt")
    func assembledTaskNeverIncludesSystemPrompt() {
        let definition = Self.definition(requirements: ["The branch containing the changes under review"])
        let viewModel = Self.viewModel(assistant: definition)
        viewModel.task = "Review the branch"
        viewModel.setText("main", forField: 0)
        #expect(!viewModel.assembledTask.contains(definition.systemPrompt))
    }

    @Test("Launch reports the created thread id on success")
    func launchReportsThreadID() async {
        let threadID = UUID()
        let recorder = LaunchRecorder()
        recorder.result = AssistantLaunchResult(threadID: threadID, errorMessage: nil)
        let viewModel = Self.viewModel(assistant: Self.definition(), recorder: recorder)
        viewModel.task = "Build the thing"
        await viewModel.launch()
        #expect(viewModel.launchedThreadID == threadID)
        #expect(viewModel.launchError == nil)
        #expect(viewModel.isLaunching == false)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0].task == "Build the thing")
    }

    @Test("Launch surfaces the launcher error")
    func launchSurfacesError() async {
        let recorder = LaunchRecorder()
        recorder.result = AssistantLaunchResult(threadID: nil, errorMessage: "Runtime unavailable")
        let viewModel = Self.viewModel(assistant: Self.definition(), recorder: recorder)
        viewModel.task = "Build the thing"
        await viewModel.launch()
        #expect(viewModel.launchedThreadID == nil)
        #expect(viewModel.launchError == "Runtime unavailable")
        #expect(viewModel.isLaunching == false)
    }

    @Test("Launch does not run with an empty task")
    func launchDoesNotRunWithEmptyTask() async {
        let recorder = LaunchRecorder()
        let viewModel = Self.viewModel(assistant: Self.definition(), recorder: recorder)
        await viewModel.launch()
        #expect(recorder.calls.isEmpty)
        #expect(viewModel.launchError != nil)
        #expect(viewModel.launchedThreadID == nil)
    }

    @Test("Launch passes the remote assistant built from the definition")
    func launchPassesRemoteAssistantFromDefinition() async {
        let definition = Self.definition(
            requirements: ["The branch containing the changes under review"],
            modelConfig: .specific(provider: "claude", model: "claude-sonnet-4"),
            permissionProfile: .approvalRequired
        )
        let recorder = LaunchRecorder()
        let viewModel = Self.viewModel(assistant: definition, recorder: recorder)
        viewModel.task = "Review the branch"
        await viewModel.launch()
        let captured = recorder.calls[0].assistant
        #expect(captured.id == definition.persistenceID)
        #expect(captured.name == "Feature Builder")
        #expect(captured.category == .buildingFixing)
        #expect(captured.systemPrompt == definition.systemPrompt)
        #expect(captured.intendedTasks == ["Build features"])
        #expect(captured.expectedOutputFormat == "A summary.")
        #expect(captured.provider == "claude")
        #expect(captured.model == "claude-sonnet-4")
        #expect(captured.permissionProfile == .approvalRequired)
        #expect(captured.inputRequirements == ["The branch containing the changes under review"])
        #expect(captured.version == 1)
    }

    @Test("Every built-in preset yields one field per requirement")
    func everyBuiltInPresetYieldsOneFieldPerRequirement() {
        for definition in BuiltInPresets.all {
            let viewModel = Self.viewModel(assistant: definition)
            #expect(
                viewModel.fields.count == (definition.inputRequirements ?? []).count,
                "Assistant \(definition.id) should yield one field per requirement"
            )
        }
    }
}
