import CoincideRemoteKit
import Foundation

public enum WorkerPromptComposer {
    public static func canAcceptSystemPrompt(parentToolset: String?, assistant: RemoteAssistant?) -> Bool {
        guard parentToolset == "provider" else {
            return true
        }
        guard let assistant else {
            return false
        }
        if let allowedTools = assistant.allowedTools, !allowedTools.isEmpty {
            return true
        }
        return assistant.permissionProfile == .readOnly || assistant.permissionProfile == .approvalRequired
    }

    public static func composedPrompt(task: String, assistant: RemoteAssistant?, parentProvider: String?, parentModel: String?, parentToolset: String?, manager: SystemAssetManager = .shared) -> String? {
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard canAcceptSystemPrompt(parentToolset: parentToolset, assistant: assistant) else {
            return nil
        }
        let prompt = manager.systemPrompt(
            for: task,
            provider: assistant?.provider ?? parentProvider,
            model: assistant?.model ?? parentModel,
            assistant: assistant.map { AssistantPromptDescriptor($0) }
        )
        return prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt.text
    }
}
