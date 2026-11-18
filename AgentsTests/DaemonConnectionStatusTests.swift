import Foundation
import Testing
@testable import Agents

@Suite("Daemon Connection Status")
struct DaemonConnectionStatusTests {

    @Test("Runtime open with no poll failures is connected")
    func openRuntimeIsConnected() {
        #expect(
            DaemonConnectionStatus.status(
                runtimeOpen: true, consecutivePollFailures: 0, lastPollError: nil, openFailure: nil
            ) == .connected
        )
    }

    @Test("One failed poll stays connected, below the unreachable threshold")
    func singlePollFailureStaysConnected() {
        #expect(
            DaemonConnectionStatus.status(
                runtimeOpen: true, consecutivePollFailures: 1,
                lastPollError: "Engine lock poisoned", openFailure: nil
            ) == .connected
        )
    }

    @Test("Repeated failed polls are unreachable with the poll error as the diagnosis")
    func repeatedPollFailuresAreUnreachable() {
        let status = DaemonConnectionStatus.status(
            runtimeOpen: true, consecutivePollFailures: 2,
            lastPollError: "Engine lock poisoned", openFailure: nil
        )
        #expect(status == .unreachable(detail: "Engine lock poisoned"))
        #expect(status.detail == "Engine lock poisoned")
        #expect(!status.isConnected)
    }

    @Test("No runtime and no recorded failure is still checking, never unreachable")
    func noRuntimeNoFailureIsChecking() {
        #expect(
            DaemonConnectionStatus.status(
                runtimeOpen: false, consecutivePollFailures: 0, lastPollError: nil, openFailure: nil
            ) == .checking
        )
    }

    @Test("A data-directory open failure is misconfigured, with the runtime message kept")
    func dataDirectoryFailureIsMisconfigured() {
        for message in [
            "Failed to open Agents runtime: Data directory path must be absolute",
            "Failed to open Agents runtime: Failed to create data directory /tmp/nope",
            "Failed to open Agents runtime: Data directory must be a regular directory, not a symlink",
            "Failed to open Agents runtime: HOME is missing",
        ] {
            #expect(DaemonConnectionStatus.classifyOpenFailure(message) == .misconfigured(detail: message))
        }
    }

    @Test("Any other open failure is unreachable, never misconfigured or connected")
    func otherOpenFailuresAreUnreachable() {
        for message in [
            "Failed to open Agents runtime: Unknown runtime initialization failure",
            "Failed to open Agents runtime: FFI panic: something broke",
        ] {
            let status = DaemonConnectionStatus.classifyOpenFailure(message)
            #expect(status == .unreachable(detail: message))
            #expect(!status.isConnected)
        }
    }

    @Test("An open failure never maps to connected")
    func openFailureNeverConnected() {
        #expect(
            DaemonConnectionStatus.status(
                runtimeOpen: false, consecutivePollFailures: 0, lastPollError: nil,
                openFailure: "Failed to open Agents runtime: boom"
            ) != .connected
        )
    }

    @Test("Sanitized data-directory failures still classify as misconfigured")
    func sanitizedDataDirectoryFailuresStayMisconfigured() {
        for rustMessage in [
            "Data directory path must be absolute",
            "Failed to create data directory /tmp/nope",
            "HOME is missing",
        ] {
            let sanitized = ErrorSanitizer.displayMessage(for: AgentsRuntimeError.openFailed(rustMessage))
            #expect(DaemonConnectionStatus.classifyOpenFailure(sanitized) == .misconfigured(detail: sanitized))
        }
    }

    @Test("Titles name the state without inventing a cause")
    func titlesNameTheState() {
        #expect(DaemonConnectionStatus.connected.title == "Agents runtime connected")
        #expect(DaemonConnectionStatus.checking.title == "Connecting to the Agents runtime…")
        #expect(DaemonConnectionStatus.unreachable(detail: "x").title == "Agents runtime unreachable")
        #expect(DaemonConnectionStatus.misconfigured(detail: "x").title == "Agents runtime misconfigured")
        #expect(DaemonConnectionStatus.connected.detail == nil)
        #expect(DaemonConnectionStatus.checking.detail == nil)
    }
}
