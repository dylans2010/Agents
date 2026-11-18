import AppKit
import CoincideRemoteKit
import Foundation
import UserNotifications

public enum AssistantNotificationCategory: String, CaseIterable, Sendable {
    case runCompleted
    case runFailed
    case needsApproval
    case automationExecuted
    case significantFindings

    public var title: String {
        switch self {
        case .runCompleted: return "Run completed"
        case .runFailed: return "Run failed"
        case .needsApproval: return "Run needs approval"
        case .automationExecuted: return "Automation task executed"
        case .significantFindings: return "Significant findings"
        }
    }

    public var detail: String {
        switch self {
        case .runCompleted: return "An assistant finishes a run."
        case .runFailed: return "An assistant run fails."
        case .needsApproval: return "An assistant run waits for an approval or an answer."
        case .automationExecuted: return "A scheduled run finishes on a thread with active schedules."
        case .significantFindings: return "A finished assistant worker produced a result to review."
        }
    }

    public var defaultsKey: String {
        "coincide.assistantNotifications.\(rawValue)"
    }
}

@Observable
@MainActor
public final class AssistantNotificationSettings {
    public static let shared = AssistantNotificationSettings()
    public static let masterKey = "coincide.assistantNotifications.enabled"

    private let defaults: UserDefaults

    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.masterKey) }
    }

    public var runCompletedEnabled: Bool {
        didSet { defaults.set(runCompletedEnabled, forKey: AssistantNotificationCategory.runCompleted.defaultsKey) }
    }

    public var runFailedEnabled: Bool {
        didSet { defaults.set(runFailedEnabled, forKey: AssistantNotificationCategory.runFailed.defaultsKey) }
    }

    public var needsApprovalEnabled: Bool {
        didSet { defaults.set(needsApprovalEnabled, forKey: AssistantNotificationCategory.needsApproval.defaultsKey) }
    }

    public var automationExecutedEnabled: Bool {
        didSet { defaults.set(automationExecutedEnabled, forKey: AssistantNotificationCategory.automationExecuted.defaultsKey) }
    }

    public var significantFindingsEnabled: Bool {
        didSet { defaults.set(significantFindingsEnabled, forKey: AssistantNotificationCategory.significantFindings.defaultsKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.masterKey) as? Bool ?? true
        self.runCompletedEnabled = defaults.object(forKey: AssistantNotificationCategory.runCompleted.defaultsKey) as? Bool ?? true
        self.runFailedEnabled = defaults.object(forKey: AssistantNotificationCategory.runFailed.defaultsKey) as? Bool ?? true
        self.needsApprovalEnabled = defaults.object(forKey: AssistantNotificationCategory.needsApproval.defaultsKey) as? Bool ?? true
        self.automationExecutedEnabled = defaults.object(forKey: AssistantNotificationCategory.automationExecuted.defaultsKey) as? Bool ?? true
        self.significantFindingsEnabled = defaults.object(forKey: AssistantNotificationCategory.significantFindings.defaultsKey) as? Bool ?? true
    }

    public func isCategoryEnabled(_ category: AssistantNotificationCategory) -> Bool {
        guard isEnabled else { return false }
        switch category {
        case .runCompleted: return runCompletedEnabled
        case .runFailed: return runFailedEnabled
        case .needsApproval: return needsApprovalEnabled
        case .automationExecuted: return automationExecutedEnabled
        case .significantFindings: return significantFindingsEnabled
        }
    }

    public func setCategoryEnabled(_ enabled: Bool, for category: AssistantNotificationCategory) {
        switch category {
        case .runCompleted: runCompletedEnabled = enabled
        case .runFailed: runFailedEnabled = enabled
        case .needsApproval: needsApprovalEnabled = enabled
        case .automationExecuted: automationExecutedEnabled = enabled
        case .significantFindings: significantFindingsEnabled = enabled
        }
    }
}

public protocol AssistantNotificationPosting {
    func add(_ request: UNNotificationRequest)
}

public struct UserNotificationCenterPoster: AssistantNotificationPosting {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func add(_ request: UNNotificationRequest) {
        center.add(request)
    }
}

@MainActor
public final class AssistantNotificationManager {
    private let settings: AssistantNotificationSettings
    private let poster: any AssistantNotificationPosting
    private let isAppActive: () -> Bool
    private let bundleIdentifier: String?
    private var notifiedKeys: Set<String> = []

    public init(
        settings: AssistantNotificationSettings = .shared,
        poster: any AssistantNotificationPosting = UserNotificationCenterPoster(),
        isAppActive: @escaping () -> Bool = { NSApp.isActive },
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.settings = settings
        self.poster = poster
        self.isAppActive = isAppActive
        self.bundleIdentifier = bundleIdentifier
    }

    @discardableResult
    public func notifyTurnFinished(thread: RemoteThreadSummary, outcome: String, assistantName: String?) -> Bool {
        guard let assistantID = thread.assistantId, !assistantID.isEmpty else { return false }
        let category: AssistantNotificationCategory
        switch outcome {
        case "failed":
            category = .runFailed
        case "completed":
            if (thread.scheduleCount ?? 0) > 0 {
                category = .automationExecuted
            } else {
                category = .runCompleted
            }
        default:
            return false
        }
        let title = assistantName ?? "Assistant"
        let body: String
        switch category {
        case .runFailed:
            body = thread.title.isEmpty ? "Its run failed." : "Failed: \(thread.title)"
        case .automationExecuted:
            body = thread.title.isEmpty ? "A scheduled run finished." : "Scheduled run finished: \(thread.title)"
        case .runCompleted:
            body = thread.title.isEmpty ? "Finished its run." : "Finished: \(thread.title)"
        case .needsApproval, .significantFindings:
            body = thread.title
        }
        post(category: category, runID: thread.id.uuidString, title: title, body: body, assistantID: assistantID, threadID: thread.id.uuidString)
        return true
    }

    @discardableResult
    public func notifyApprovalNeeded(threads: [RemoteThreadSummary], assistantName: (String) -> String?) -> Bool {
        var handled = false
        for thread in threads {
            guard let assistantID = thread.assistantId, !assistantID.isEmpty else { continue }
            guard thread.pendingApprovals > 0 || thread.pendingQuestions > 0 else { continue }
            handled = true
            let approvals = thread.pendingApprovals
            let questions = thread.pendingQuestions
            let body: String
            if approvals > 0 && questions > 0 {
                body = "\(approvals) approval(s) and \(questions) question(s) waiting."
            } else if approvals > 0 {
                body = "\(approvals) tool approval\(approvals == 1 ? "" : "s") waiting."
            } else {
                body = "\(questions) agent question\(questions == 1 ? "" : "s") waiting."
            }
            let title = assistantName(assistantID) ?? "Assistant"
            post(
                category: .needsApproval,
                runID: thread.id.uuidString,
                title: "\(title) Needs Input",
                body: body,
                assistantID: assistantID,
                threadID: thread.id.uuidString,
                dedupKey: "needsApproval:\(thread.id.uuidString):\(approvals):\(questions)"
            )
        }
        return handled
    }

    @discardableResult
    public func notifyWorkerTerminal(_ worker: WorkerRecord, assistantName: String?) -> Bool {
        guard let assistantID = worker.assistantId, !assistantID.isEmpty else { return false }
        guard worker.isTerminal else { return false }
        let title = assistantName ?? "Assistant"
        switch worker.status {
        case "completed":
            let result = worker.result ?? ""
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let excerpt = OutputRedactionGate.shared.notificationExcerpt(for: result)
            let body = excerpt.isEmpty
                ? "Findings ready in \(worker.name)."
                : "Findings ready in \(worker.name): \(excerpt)"
            post(
                category: .significantFindings,
                runID: worker.threadId,
                title: title,
                body: body,
                assistantID: assistantID,
                threadID: worker.threadId
            )
            return true
        case "failed":
            post(
                category: .runFailed,
                runID: worker.threadId,
                title: title,
                body: "Failed: \(worker.name)",
                assistantID: assistantID,
                threadID: worker.threadId
            )
            return true
        default:
            return false
        }
    }

    public func allowsTaskNotification(task: AssistantTaskRecord, outcome: String, scheduleCount: Int) -> Bool {
        switch outcome {
        case "completed":
            guard task.notifications.onSuccess else { return false }
            return settings.isCategoryEnabled(scheduleCount > 0 ? .automationExecuted : .runCompleted)
        case "failed":
            guard task.notifications.onFailure else { return false }
            return settings.isCategoryEnabled(.runFailed)
        default:
            return false
        }
    }

    @discardableResult
    private func post(
        category: AssistantNotificationCategory,
        runID: String,
        title: String,
        body: String,
        assistantID: String,
        threadID: String,
        dedupKey: String? = nil
    ) -> Bool {
        guard settings.isCategoryEnabled(category) else { return false }
        guard !isAppActive() else { return false }
        guard bundleIdentifier != nil else { return false }
        let key = dedupKey ?? "\(category.rawValue):\(runID)"
        guard notifiedKeys.insert(key).inserted else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "assistantID": assistantID,
            "threadID": threadID,
            "runID": runID,
            "category": category.rawValue
        ]
        let request = UNNotificationRequest(
            identifier: "assistant-\(category.rawValue)-\(runID)",
            content: content,
            trigger: nil
        )
        poster.add(request)
        return true
    }
}
