import CoincideRemoteKit
import Foundation

public struct AssistantPromptDescriptor: Sendable, Hashable {
    public var id: String
    public var name: String
    public var systemPrompt: String
    public var description: String
    public var extraAssetFileNames: [String]

    public init(id: String, name: String, systemPrompt: String, description: String = "", extraAssetFileNames: [String] = []) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.description = description
        self.extraAssetFileNames = extraAssetFileNames
    }

    public init(_ assistant: RemoteAssistant) {
        self.id = assistant.id.uuidString
        self.name = assistant.name
        self.systemPrompt = assistant.systemPrompt
        self.description = assistant.description
        self.extraAssetFileNames = []
    }
}
