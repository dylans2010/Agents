import Foundation

public nonisolated enum SystemPromptBudget: Sendable {
    public static let defaultBudgetTokens = 6000
    public static let minimumBudgetTokens = 1500
    public static let maximumBudgetTokens = 6000

    public static func budget(contextWindowTokens: Int?) -> Int {
        guard let window = contextWindowTokens, window > 0 else {
            return defaultBudgetTokens
        }
        return min(maximumBudgetTokens, max(minimumBudgetTokens, window / 16))
    }
}
