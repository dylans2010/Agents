import Foundation

public enum AssistantModelConfig: Hashable, Sendable {
    case appDefault
    case specific(provider: String, model: String)
    case currentAppModel

    public init(provider: String?, model: String?) {
        if let provider, let model {
            self = .specific(provider: provider, model: model)
        } else {
            self = .appDefault
        }
    }

    public var provider: String? {
        if case .specific(let provider, _) = self { return provider }
        return nil
    }

    public var model: String? {
        if case .specific(_, let model) = self { return model }
        return nil
    }

    public func resolvingCurrent(provider: String?, model: String?) -> AssistantModelConfig {
        if case .currentAppModel = self {
            return AssistantModelConfig(provider: provider, model: model)
        }
        return self
    }
}
