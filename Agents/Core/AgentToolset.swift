import Foundation

public nonisolated enum AgentToolset: String, Codable, CaseIterable, Sendable {
    case system
    case provider

    public static let userDefaultsKey = "coincide.agentToolset"

    public var title: String {
        switch self {
        case .system: "System Tools"
        case .provider: "Provider Tools"
        }
    }

    public var detail: String {
        switch self {
        case .system:
            "Sessions run with the Agents system prompt and the system tool registry."
        case .provider:
            "Sessions run with the provider's own tools and no system prompt."
        }
    }

    public init(storedValue: String?) {
        guard let storedValue else {
            self = .system
            return
        }
        self = AgentToolset(rawValue: storedValue) ?? .system
    }

    public static func load(from defaults: UserDefaults = .standard) -> AgentToolset {
        AgentToolset(storedValue: defaults.string(forKey: userDefaultsKey))
    }

    public static func save(_ toolset: AgentToolset, to defaults: UserDefaults = .standard) {
        defaults.set(toolset.rawValue, forKey: userDefaultsKey)
    }

    public static func effective(stored toolset: String?) -> AgentToolset {
        guard let toolset else {
            return .provider
        }
        return AgentToolset(rawValue: toolset) ?? .provider
    }
}
