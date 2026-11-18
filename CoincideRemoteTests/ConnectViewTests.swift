import Foundation
import Testing

@testable import CoincideRemote

@Suite("Connect View")
struct ConnectViewTests {

    @Test("Setup instructions name the real Mac Settings path")
    func instructionsNameRealSettingsPath() {
        #expect(ConnectView.macSetupInstructions.contains("System › Remote"))
        #expect(ConnectView.macSetupInstructions.contains("Pair iPhone or iPad"))
        #expect(!ConnectView.macSetupInstructions.contains("General › Remote"))
    }

    @Test("Local Network denial states that discovery is off while pairing still works")
    func localNetworkDenialStatesConsequence() {
        #expect(ConnectView.localNetworkDeniedMessage.contains("no Macs appear here"))
        #expect(ConnectView.localNetworkDeniedMessage.contains("still pair by scanning the code"))
        #expect(ConnectView.localNetworkDeniedMessage.contains("Paired Macs"))
    }
}
