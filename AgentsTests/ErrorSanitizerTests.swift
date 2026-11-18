import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Error Sanitization Layer")
struct ErrorSanitizerTests {

    @Test("Home, Application Support, and temp paths are stripped")
    func stripsFilesystemPaths() {
        let home = NSHomeDirectory()
        let raw = "Failed to open \(home)/Library/Application Support/Agents/data.db and /tmp/work-123/out.log"
        let clean = ErrorSanitizer.sanitizeText(raw)
        #expect(!clean.contains(home))
        #expect(!clean.contains("Application Support"))
        #expect(!clean.contains("/tmp/work-123"))
        #expect(!clean.contains("data.db"))
        #expect(clean.contains("[application support]") || clean.contains("[path]"))
        #expect(clean.contains("[temporary directory]"))
    }

    @Test("A bare home-directory path is stripped")
    func stripsBareHomePath() {
        let home = NSHomeDirectory()
        let clean = ErrorSanitizer.sanitizeText("Could not read \(home)/.curlrc for this request")
        #expect(!clean.contains(home))
        #expect(!clean.contains(".curlrc"))
    }

    @Test("API keys, bearer tokens, and labeled secrets are stripped")
    func stripsCredentials() {
        let raw = "Probe failed with api_key=sk-test-fake-key-abcdef1234567890 and Authorization: Bearer fake-bearer-token-abcdef1234567890"
        let clean = ErrorSanitizer.sanitizeText(raw)
        #expect(!clean.contains("sk-test-fake-key-abcdef1234567890"))
        #expect(!clean.contains("fake-bearer-token-abcdef1234567890"))
        #expect(clean.contains("[redacted"))
    }

    @Test("GitHub-style and developer keys are stripped")
    func stripsTokenFormats() {
        let raw = "Auth error for github_pat_11FAKE0123456789abcdefghij and sc_dev_live_fake0123456789abcdef"
        let clean = ErrorSanitizer.sanitizeText(raw)
        #expect(!clean.contains("github_pat_11FAKE0123456789abcdefghij"))
        #expect(!clean.contains("sc_dev_live_fake0123456789abcdef"))
        #expect(clean.contains("[redacted"))
    }

    @Test("Thread UUIDs, socket addresses, and URLs are stripped")
    func stripsIdentifiersAndTransport() {
        let raw = "Thread 3F2504E0-4F89-11D3-9A0C-0305E82C3301 failed at 127.0.0.1:51234 via ws://localhost:8080/socket"
        let clean = ErrorSanitizer.sanitizeText(raw)
        #expect(!clean.contains("3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        #expect(!clean.contains("127.0.0.1"))
        #expect(!clean.contains("localhost:8080"))
        #expect(clean.contains("[id]"))
        #expect(clean.contains("[address]"))
    }

    @Test("Internal prompt and asset fragments are stripped")
    func stripsPromptFragments() {
        let raw = "Render failed. See ErrorHandling.md and SystemAssets/TestingStrategy.md. system prompt: You are a fake test assistant"
        let clean = ErrorSanitizer.sanitizeText(raw)
        #expect(!clean.contains("You are a fake test assistant"))
        #expect(!clean.contains("ErrorHandling.md"))
        #expect(!clean.contains("TestingStrategy.md"))
        #expect(clean.contains("[redacted]"))
        #expect(clean.contains("[asset]"))
    }

    @Test("A network failure keeps its actionable part and suggests retry")
    func preservesActionableNetworkMessage() {
        let raw = "Connection to the runtime failed: connection refused at 127.0.0.1:51234"
        let clean = ErrorSanitizer.sanitizeText(raw)
        #expect(clean.contains("Connection to the runtime failed"))
        #expect(clean.contains("connection refused"))
        #expect(clean.contains("try again"))
        #expect(!clean.contains("127.0.0.1"))
    }

    @Test("An error with no actionable detail falls back to a generic retry message")
    func fallsBackWhenNothingRemains() {
        #expect(ErrorSanitizer.sanitizeText("") == "Something went wrong. Try again.")
        #expect(ErrorSanitizer.sanitizeText("   ") == "Something went wrong. Try again.")
    }

    @Test("Error kinds pass through untouched")
    func errorKindPassthrough() {
        #expect(ErrorSanitizer.errorKind(for: AgentsRuntimeError.desktopFailure("boom")) == "desktopFailure")
        #expect(ErrorSanitizer.errorKind(for: AgentsRuntimeError.openFailed("boom")) == "openFailed")
        #expect(ErrorSanitizer.errorKind(for: AgentsRuntimeError.runtimeClosed) == "runtimeClosed")
        #expect(ErrorSanitizer.errorKind(for: AgentsRuntimeError.invalidJSON("boom")) == "invalidJSON")
        #expect(ErrorSanitizer.errorKind(for: AgentsRuntimeError.unexpectedResult(expected: "a", actual: "b")) == "unexpectedResult")
        #expect(ErrorSanitizer.errorKind(for: AgentsRuntimeError.remoteFailure(RemoteError(.notFound, "missing"))) == "notFound")
        #expect(ErrorSanitizer.errorKind(for: RemoteError(.unauthorized, "nope")) == "unauthorized")
        let sanitized = ErrorSanitizer.sanitize(AgentsRuntimeError.desktopFailure("failed at /Users/someone/secret.txt"))
        #expect(sanitized.kind == "desktopFailure")
        #expect(!sanitized.displayMessage.contains("/Users/someone/secret.txt"))
    }

    @Test("Diagnostic form carries the kind and is sanitized too")
    func diagnosticFormSanitized() {
        let error = AgentsRuntimeError.desktopFailure("failed at /Users/someone/secret.txt with token sk-test-fake-key-abcdef1234567890")
        let diagnostic = ErrorSanitizer.diagnosticMessage(for: error)
        #expect(diagnostic.hasPrefix("[desktopFailure]"))
        #expect(!diagnostic.contains("/Users/someone/secret.txt"))
        #expect(!diagnostic.contains("sk-test-fake-key-abcdef1234567890"))
        let bundled = ErrorSanitizer.sanitize(error)
        #expect(bundled.diagnosticMessage == diagnostic)
        #expect(bundled.kind == "desktopFailure")
    }

    @Test("Sanitization is idempotent for repeated application")
    func sanitizationIsIdempotent() {
        let raw = "Failed at /Users/someone/Library/Application Support/Agents/x.db for thread 3F2504E0-4F89-11D3-9A0C-0305E82C3301: connection refused at 127.0.0.1:51234"
        let once = ErrorSanitizer.sanitizeText(raw)
        #expect(ErrorSanitizer.sanitizeText(once) == once)
    }
}
