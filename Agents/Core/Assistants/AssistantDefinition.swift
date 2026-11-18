import CoincideRemoteKit
import CryptoKit
import Foundation

public enum AssistantValidationIssue: Hashable, Sendable {
    case emptyName
    case nameTooLong
    case nameHasControlCharacters
    case descriptionTooLong
    case descriptionHasNUL
    case iconTooLong
    case iconHasControlCharacters
    case emptySystemPrompt
    case systemPromptTooLong
    case systemPromptHasNUL
    case emptyModel
    case modelTooLong
    case tooManyIntendedTasks
    case intendedTaskTooLong(index: Int)
    case intendedTaskHasNUL(index: Int)
    case expectedOutputFormatTooLong
    case expectedOutputFormatHasNUL
    case emptyToolName
    case toolNameTooLong(name: String)
    case toolNameHasControlCharacters(name: String)
    case duplicateToolName(name: String)
    case unknownTool(name: String)
    case tooManyInputRequirements
    case inputRequirementTooLong(index: Int)
    case inputRequirementHasNUL(index: Int)
    case versionTooLow
    case invalidStableID
}

public struct AssistantDefinition: Hashable, Sendable, Identifiable {
    public static let nameLimit = 1024
    public static let descriptionLimit = 4096
    public static let iconLimit = 128
    public static let systemPromptLimit = 1_048_576
    public static let modelLimit = 256
    public static let intendedTaskLimit = 512
    public static let intendedTasksLimit = 32
    public static let outputFormatLimit = 4096
    public static let toolNameLimit = 256
    public static let inputRequirementLimit = 512
    public static let inputRequirementsLimit = 16

    public static let builtInPrefix = "builtin."
    public static let customPrefix = "custom."
    public static let persistenceNamespace = UUID(uuidString: "a0c85a04-06f7-468f-8f4d-187c87ee3fbc")!

    public var id: String
    public var name: String
    public var description: String
    public var category: AssistantCategory
    public var icon: String
    public var systemPrompt: String
    public var intendedTasks: [String]
    public var expectedOutputFormat: String
    public var allowedTools: [String]?
    public var modelConfig: AssistantModelConfig
    public var permissionProfile: AssistantPermissionProfile
    public var inputRequirements: [String]?
    public var version: Int
    public var isBuiltIn: Bool
    public var customized: Bool

    public init(
        id: String, name: String, description: String = "", category: AssistantCategory, icon: String = "",
        systemPrompt: String, intendedTasks: [String] = [], expectedOutputFormat: String = "",
        allowedTools: [String]? = nil, modelConfig: AssistantModelConfig = .appDefault,
        permissionProfile: AssistantPermissionProfile = .readOnly, inputRequirements: [String]? = nil,
        version: Int = 1, isBuiltIn: Bool = true, customized: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.icon = icon
        self.systemPrompt = systemPrompt
        self.intendedTasks = intendedTasks
        self.expectedOutputFormat = expectedOutputFormat
        self.allowedTools = allowedTools
        self.modelConfig = modelConfig
        self.permissionProfile = permissionProfile
        self.inputRequirements = inputRequirements
        self.version = version
        self.isBuiltIn = isBuiltIn
        self.customized = customized
    }

    public init?(stored record: RemoteAssistant) {
        guard record.source == .custom, let category = AssistantCategory(remote: record.category) else {
            return nil
        }
        self.init(
            id: Self.customID(record.id),
            name: record.name,
            description: record.description,
            category: category,
            icon: record.icon,
            systemPrompt: record.systemPrompt,
            intendedTasks: record.intendedTasks,
            expectedOutputFormat: record.expectedOutputFormat,
            allowedTools: record.allowedTools,
            modelConfig: AssistantModelConfig(provider: record.provider, model: record.model),
            permissionProfile: AssistantPermissionProfile(remote: record.permissionProfile) ?? .readOnly,
            inputRequirements: record.inputRequirements,
            version: record.version,
            isBuiltIn: false,
            customized: false
        )
    }

    public static func builtInID(category: AssistantCategory, slug: String) -> String {
        precondition(Self.isValidSlug(slug), "Invalid assistant slug: \(slug)")
        return "builtin.\(category.rawValue).\(slug)"
    }

    public static func customID(_ id: UUID) -> String {
        "custom.\(id.uuidString.lowercased())"
    }

    public static func isBuiltInID(_ id: String) -> Bool {
        id.hasPrefix(builtInPrefix)
    }

    public static func isCustomID(_ id: String) -> Bool {
        id.hasPrefix(customPrefix)
    }

    public static func isValidSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, !slug.hasPrefix("-"), !slug.hasSuffix("-"), !slug.contains("--") else {
            return false
        }
        return slug.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
        }
    }

    public static func deterministicID(namespace: UUID, name: String) -> UUID {
        var namespaceUUID = namespace.uuid
        var input: [UInt8] = []
        withUnsafeBytes(of: &namespaceUUID) { input.append(contentsOf: $0) }
        input.append(contentsOf: Array(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: Data(input)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func persistenceID(forStableID stableID: String) -> UUID? {
        if isCustomID(stableID) {
            return UUID(uuidString: String(stableID.dropFirst(customPrefix.count)))
        }
        if isBuiltInID(stableID) {
            return deterministicID(namespace: persistenceNamespace, name: stableID)
        }
        return nil
    }

    public var persistenceID: UUID? {
        Self.persistenceID(forStableID: id)
    }

    public func applyingOverride(_ record: RemoteAssistant) -> AssistantDefinition {
        guard record.source == .override else { return self }
        var resolved = self
        var changed = false
        if record.name != name {
            resolved.name = record.name
            changed = true
        }
        if record.description != description {
            resolved.description = record.description
            changed = true
        }
        if record.icon != icon {
            resolved.icon = record.icon
            changed = true
        }
        if let recordCategory = AssistantCategory(remote: record.category), recordCategory != category {
            resolved.category = recordCategory
            changed = true
        }
        if record.systemPrompt != systemPrompt {
            resolved.systemPrompt = record.systemPrompt
            changed = true
        }
        if record.intendedTasks != intendedTasks {
            resolved.intendedTasks = record.intendedTasks
            changed = true
        }
        if record.expectedOutputFormat != expectedOutputFormat {
            resolved.expectedOutputFormat = record.expectedOutputFormat
            changed = true
        }
        if record.allowedTools != allowedTools {
            resolved.allowedTools = record.allowedTools
            changed = true
        }
        let recordConfig = AssistantModelConfig(provider: record.provider, model: record.model)
        if recordConfig != modelConfig {
            resolved.modelConfig = recordConfig
            changed = true
        }
        if let recordProfile = AssistantPermissionProfile(remote: record.permissionProfile),
            recordProfile != permissionProfile {
            resolved.permissionProfile = recordProfile
            changed = true
        }
        if record.inputRequirements != inputRequirements {
            resolved.inputRequirements = record.inputRequirements
            changed = true
        }
        resolved.customized = changed
        return resolved
    }

    public func validationIssues() -> [AssistantValidationIssue] {
        var issues: [AssistantValidationIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyName)
        }
        if name.unicodeScalars.count > Self.nameLimit {
            issues.append(.nameTooLong)
        }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            issues.append(.nameHasControlCharacters)
        }
        if description.unicodeScalars.count > Self.descriptionLimit {
            issues.append(.descriptionTooLong)
        }
        if description.contains("\0") {
            issues.append(.descriptionHasNUL)
        }
        if icon.unicodeScalars.count > Self.iconLimit {
            issues.append(.iconTooLong)
        }
        if icon.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            issues.append(.iconHasControlCharacters)
        }
        if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptySystemPrompt)
        }
        if systemPrompt.utf8.count > Self.systemPromptLimit {
            issues.append(.systemPromptTooLong)
        }
        if systemPrompt.contains("\0") {
            issues.append(.systemPromptHasNUL)
        }
        if intendedTasks.count > Self.intendedTasksLimit {
            issues.append(.tooManyIntendedTasks)
        }
        for (index, task) in intendedTasks.enumerated() {
            if task.unicodeScalars.count > Self.intendedTaskLimit {
                issues.append(.intendedTaskTooLong(index: index))
            }
            if task.contains("\0") {
                issues.append(.intendedTaskHasNUL(index: index))
            }
        }
        if expectedOutputFormat.unicodeScalars.count > Self.outputFormatLimit {
            issues.append(.expectedOutputFormatTooLong)
        }
        if expectedOutputFormat.contains("\0") {
            issues.append(.expectedOutputFormatHasNUL)
        }
        if let tools = allowedTools {
            var seen: Set<String> = []
            for tool in tools {
                if tool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.emptyToolName)
                }
                if tool.unicodeScalars.count > Self.toolNameLimit {
                    issues.append(.toolNameTooLong(name: tool))
                }
                if tool.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                    issues.append(.toolNameHasControlCharacters(name: tool))
                }
                if !seen.insert(tool).inserted {
                    issues.append(.duplicateToolName(name: tool))
                }
            }
            for unknown in SystemToolRegistry.unknownToolNames(in: tools) {
                issues.append(.unknownTool(name: unknown))
            }
        }
        if let model = modelConfig.model {
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.emptyModel)
            } else if model.unicodeScalars.count > Self.modelLimit {
                issues.append(.modelTooLong)
            }
        }
        if let requirements = inputRequirements {
            if requirements.count > Self.inputRequirementsLimit {
                issues.append(.tooManyInputRequirements)
            }
            for (index, requirement) in requirements.enumerated() {
                if requirement.unicodeScalars.count > Self.inputRequirementLimit {
                    issues.append(.inputRequirementTooLong(index: index))
                }
                if requirement.contains("\0") {
                    issues.append(.inputRequirementHasNUL(index: index))
                }
            }
        }
        if version < 1 {
            issues.append(.versionTooLow)
        }
        if !hasValidStableID {
            issues.append(.invalidStableID)
        }
        return issues
    }

    private var hasValidStableID: Bool {
        if isBuiltIn {
            let parts = id.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            return parts.count == 3 && parts[0] == "builtin" && parts[1] == category.rawValue
                && Self.isValidSlug(parts[2])
        }
        return Self.isCustomID(id) && persistenceID != nil
    }
}
