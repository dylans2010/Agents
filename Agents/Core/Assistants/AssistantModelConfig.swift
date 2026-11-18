import Foundation

public enum AssistantModelConfig: Hashable, Sendable {
    case appDefault
    case specific(provider: String, model: String)
    case providerOnly(String)
    case modelOnly(String)
    case currentAppModel

    public init(provider: String?, model: String?) {
        switch (provider, model) {
        case let (provider?, model?):
            self = .specific(provider: provider, model: model)
        case let (provider?, nil):
            self = .providerOnly(provider)
        case let (nil, model?):
            self = .modelOnly(model)
        case (nil, nil):
            self = .appDefault
        }
    }

    public var provider: String? {
        switch self {
        case .specific(let provider, _), .providerOnly(let provider):
            return provider
        case .appDefault, .modelOnly, .currentAppModel:
            return nil
        }
    }

    public var model: String? {
        switch self {
        case .specific(_, let model), .modelOnly(let model):
            return model
        case .appDefault, .providerOnly, .currentAppModel:
            return nil
        }
    }

    public func resolvingCurrent(provider: String?, model: String?) -> AssistantModelConfig {
        if case .currentAppModel = self {
            return AssistantModelConfig(provider: provider, model: model)
        }
        return self
    }
}
