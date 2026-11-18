import CoincideRemoteKit
import Foundation

public enum AssistantReportBuilder {
    public struct Input: Sendable {
        public var record: WorkerRecord
        public var definition: AssistantDefinition
        public var transcriptItems: [RemoteItem]?
        public var diff: RemoteDiff?
        public var turnChangedFiles: [RemoteChangedFile]?
        public var diffUnavailableReason: String?

        public init(
            record: WorkerRecord, definition: AssistantDefinition, transcriptItems: [RemoteItem]? = nil,
            diff: RemoteDiff? = nil, turnChangedFiles: [RemoteChangedFile]? = nil,
            diffUnavailableReason: String? = nil
        ) {
            self.record = record
            self.definition = definition
            self.transcriptItems = transcriptItems
            self.diff = diff
            self.turnChangedFiles = turnChangedFiles
            self.diffUnavailableReason = diffUnavailableReason
        }
    }

    public static let defaultDiffUnavailableReason =
        "The worker thread diff was not supplied with this run record, so changed files cannot be listed."

    public static func build(_ input: Input) -> AssistantReport {
        let header = makeHeader(input)
        let parsed = AssistantResultTextParser.parse(input.record.result)
        let errors = parsed.errors(for: input.record)
        switch input.definition.category {
        case .codeReviewSecurity:
            return .review(AssistantReviewReport(
                header: header,
                summary: parsed.summary,
                findings: parsed.findings,
                recommendations: parsed.recommendations,
                warnings: parsed.warnings,
                errors: errors,
                nextSteps: parsed.nextSteps,
                noModificationsConfirmed: noModificationsConfirmed(input)
            ))
        case .buildingFixing, .codeMaintenance, .gitWorkflowAutomation:
            let (files, availability) = resolveDiff(input)
            return .build(AssistantBuildReport(
                header: header,
                summary: parsed.summary,
                actionsTaken: parsed.actionsTaken,
                filesChanged: files,
                diffAvailability: availability,
                testsRun: parsed.testsRun,
                warnings: parsed.warnings,
                errors: errors,
                nextSteps: parsed.nextSteps
            ))
        case .repositoryIntelligence, .specializedProductivity:
            return .analysis(AssistantAnalysisReport(
                header: header,
                summary: parsed.summary,
                findings: parsed.findings,
                evidence: parsed.evidence,
                recommendations: parsed.recommendations,
                warnings: parsed.warnings,
                errors: errors,
                nextSteps: parsed.nextSteps,
                noModificationsConfirmed: noModificationsConfirmed(input)
            ))
        }
    }

    private static func makeHeader(_ input: Input) -> AssistantReportHeader {
        let record = input.record
        let definition = input.definition
        let startedAt = Date(timeIntervalSince1970: record.startedAt)
        let duration: Double?
        if let completedAt = record.completedAt {
            duration = max(0, completedAt - record.startedAt)
        } else if record.elapsedSeconds > 0 {
            duration = record.elapsedSeconds
        } else {
            duration = nil
        }
        let toolItems = (input.transcriptItems ?? []).filter { $0.kind == .tool }
        let toolActivity = toolItems.map(AssistantToolActivity.init(item:))
        let model = definition.modelConfig.model
            ?? (input.transcriptItems ?? []).first(where: { $0.kind == .assistant && $0.modelID != nil })?.modelID
        var metadata: [AssistantReportMetadataEntry] = []
        metadata.append(AssistantReportMetadataEntry(key: "Run", value: record.id))
        metadata.append(AssistantReportMetadataEntry(key: "Workspace thread", value: record.threadId))
        metadata.append(AssistantReportMetadataEntry(key: "Parent thread", value: record.parentThreadId))
        metadata.append(AssistantReportMetadataEntry(
            key: "Transcript",
            value: "\(record.transcriptStart) + \(record.transcriptItems) items"
        ))
        if !record.targetFiles.isEmpty {
            metadata.append(AssistantReportMetadataEntry(
                key: "Target files", value: record.targetFiles.joined(separator: ", ")))
        }
        if !toolActivity.isEmpty {
            metadata.append(AssistantReportMetadataEntry(
                key: "Tool calls", value: "\(toolActivity.count)"))
        }
        return AssistantReportHeader(
            assistantID: definition.id,
            assistantName: definition.name,
            category: definition.category,
            runID: record.id,
            runName: record.name,
            task: record.task,
            parentThreadID: record.parentThreadId,
            workerThreadID: record.threadId,
            provider: record.provider,
            model: model,
            startedAt: startedAt,
            durationSeconds: duration,
            status: AssistantReportStatus(workerStatus: record.status),
            error: record.error,
            targetFiles: record.targetFiles,
            transcriptItems: record.transcriptItems,
            toolActivity: toolActivity,
            metadata: metadata
        )
    }

    private static func noModificationsConfirmed(_ input: Input) -> Bool {
        if let diff = input.diff {
            return diff.files.isEmpty
        }
        return false
    }

    private static func resolveDiff(_ input: Input) -> ([RemoteDiff.File], AssistantDiffAvailability) {
        if let diff = input.diff {
            if diff.files.isEmpty {
                return ([], .confirmedNoChanges)
            }
            return (diff.files, .attached)
        }
        if let changed = input.turnChangedFiles, !changed.isEmpty {
            let files = changed.map { file in
                RemoteDiff.File(
                    path: file.path, oldPath: file.oldPath, status: file.status,
                    additions: file.additions, deletions: file.deletions, isBinary: false, patch: ""
                )
            }
            return (files, .attached)
        }
        return ([], .unavailable(reason: input.diffUnavailableReason ?? defaultDiffUnavailableReason))
    }
}

struct AssistantParsedResult {
    var summary: String?
    var findings: [AssistantFinding]
    var evidence: [AssistantEvidence]
    var recommendations: [String]
    var actionsTaken: [String]
    var testsRun: [AssistantTestResult]
    var warnings: [String]
    var errors: [String]
    var nextSteps: [String]

    func errors(for record: WorkerRecord) -> [String] {
        var all = errors
        if let recordError = record.error?.trimmingCharacters(in: .whitespacesAndNewlines), !recordError.isEmpty,
           !all.contains(recordError) {
            all.append(recordError)
        }
        return all
    }
}

enum AssistantResultTextParser {
    private static let extensionlessFileNames: Set<String> = [
        "Makefile", "Dockerfile", "Gemfile", "Rakefile", "LICENSE", "CHANGELOG",
        "COPYING", "AUTHORS", "Vagrantfile", "Brewfile", "Podfile", "Fastfile"
    ]

    static func parse(_ result: String?) -> AssistantParsedResult {
        var parsed = AssistantParsedResult(
            summary: nil, findings: [], evidence: [], recommendations: [], actionsTaken: [],
            testsRun: [], warnings: [], errors: [], nextSteps: []
        )
        guard let result else { return parsed }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return parsed }
        let sections = splitSections(trimmed)
        parsed.summary = summary(from: sections)
        if let findingsText = sections["findings"] {
            parsed.findings = parseFindings(findingsText)
        }
        if let evidenceText = sections["evidence"] {
            parsed.evidence = parseEvidence(evidenceText)
        }
        parsed.recommendations = entries(in: sections["recommendations"])
        parsed.actionsTaken = entries(in: sections["actions taken"] ?? sections["actions"])
        parsed.testsRun = parseTests(sections["tests"] ?? sections["test results"])
        parsed.warnings = entries(in: sections["warnings"])
        parsed.errors = entries(in: sections["errors"])
        parsed.nextSteps = entries(in: sections["next steps"] ?? sections["next step"])
        return parsed
    }

    private static func splitSections(_ text: String) -> [String: String] {
        var sections: [String: [String]] = [:]
        var currentKey: String?
        var preamble: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if let heading = headingText(line) {
                let key = heading.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                currentKey = key
                if sections[key] == nil {
                    sections[key] = []
                }
            } else if let key = currentKey {
                sections[key, default: []].append(line)
            } else {
                preamble.append(line)
            }
        }
        var result: [String: String] = [:]
        for (key, lines) in sections {
            result[key] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !preamble.isEmpty {
            result[""] = preamble.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func headingText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard hashes.count >= 1, hashes.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return rest
    }

    private static func firstParagraph(_ text: String) -> String? {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.first
    }

    private static func summary(from sections: [String: String]) -> String? {
        if let summaryText = sections["summary"], let paragraph = firstParagraph(summaryText) {
            return paragraph
        }
        if let preamble = sections[""], let paragraph = firstParagraph(preamble) {
            return paragraph
        }
        return nil
    }

    private static func entries(in section: String?) -> [String] {
        guard let section else { return [] }
        var lines: [String] = []
        for raw in section.components(separatedBy: .newlines) {
            let line = stripBullet(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            lines.append(line)
        }
        return lines
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] {
            if text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count))
                break
            }
        }
        if let dot = text.firstIndex(of: ".") {
            let prefix = text[..<dot]
            if !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }), prefix.count <= 2 {
                text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    private static func parseFindings(_ section: String) -> [AssistantFinding] {
        var findings: [AssistantFinding] = []
        for raw in section.components(separatedBy: .newlines) {
            let line = stripBullet(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var severity: AssistantFindingSeverity?
            var remainder = line
            if let colon = remainder.firstIndex(of: ":") {
                let label = String(remainder[..<colon])
                if let parsedSeverity = AssistantFindingSeverity(label: label) {
                    severity = parsedSeverity
                    remainder = String(remainder[remainder.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            let (file, lineNumber, title) = extractFileRef(from: remainder)
            findings.append(AssistantFinding(severity: severity, title: title, file: file, line: lineNumber))
        }
        return findings.sorted {
            let left = $0.severity?.sortOrder ?? Int.max
            let right = $1.severity?.sortOrder ?? Int.max
            if left != right { return left < right }
            return $0.title < $1.title
        }
    }

    private static func parseEvidence(_ section: String) -> [AssistantEvidence] {
        var evidence: [AssistantEvidence] = []
        for raw in section.components(separatedBy: .newlines) {
            let line = stripBullet(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let (file, lineNumber, snippet) = extractFileRef(from: line)
            evidence.append(AssistantEvidence(file: file, line: lineNumber, snippet: snippet))
        }
        return evidence
    }

    private static func parseTests(_ section: String?) -> [AssistantTestResult] {
        guard let section else { return [] }
        var results: [AssistantTestResult] = []
        for raw in section.components(separatedBy: .newlines) {
            let line = stripBullet(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var outcome = AssistantTestOutcome.unknown
            var name = line
            let lower = line.lowercased()
            if lower.hasPrefix("pass:") || lower.hasPrefix("passed:") || lower.hasPrefix("pass ") || lower.hasPrefix("passed ") || line.hasPrefix("✓") {
                outcome = .passed
                name = stripOutcomePrefix(line)
            } else if lower.hasPrefix("fail:") || lower.hasPrefix("failed:") || lower.hasPrefix("fail ") || lower.hasPrefix("failed ") || line.hasPrefix("✗") {
                outcome = .failed
                name = stripOutcomePrefix(line)
            } else if lower.hasPrefix("skip:") || lower.hasPrefix("skipped:") || lower.hasPrefix("skip ") || lower.hasPrefix("skipped ") {
                outcome = .skipped
                name = stripOutcomePrefix(line)
            }
            results.append(AssistantTestResult(name: name, outcome: outcome))
        }
        return results
    }

    private static func stripOutcomePrefix(_ line: String) -> String {
        var text = line
        for marker in ["✓", "✗"] {
            if text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count))
                break
            }
        }
        if let colon = text.firstIndex(of: ":") {
            let label = String(text[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            if ["pass", "passed", "fail", "failed", "skip", "skipped"].contains(label) {
                text = String(text[text.index(after: colon)...])
            }
        } else {
            for word in ["passed ", "failed ", "skipped ", "pass ", "fail ", "skip "] {
                if text.lowercased().hasPrefix(word) {
                    text = String(text.dropFirst(word.count))
                    break
                }
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func extractFileRef(from text: String) -> (String?, Int?, String) {
        let cleaned = text.replacingOccurrences(of: "`", with: "")
        let words = cleaned.components(separatedBy: .whitespaces)
        for (index, word) in words.enumerated() {
            var candidate = word.trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]"))
            if candidate.hasSuffix(":") {
                candidate = String(candidate.dropLast())
            }
            guard let colon = candidate.lastIndex(of: ":") else { continue }
            let path = String(candidate[..<colon])
            let number = String(candidate[candidate.index(after: colon)...])
            guard !path.isEmpty, let lineNumber = Int(number) else { continue }
            let fileName = path.components(separatedBy: "/").last ?? path
            guard path.contains(".") || extensionlessFileNames.contains(fileName) else { continue }
            var remaining = words
            remaining.remove(at: index)
            let title = remaining.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return (path, lineNumber, title.isEmpty ? text : title)
        }
        return (nil, nil, text)
    }
}
