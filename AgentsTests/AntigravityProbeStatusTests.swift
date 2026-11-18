import Foundation
import Testing
@testable import Agents

@Suite("Antigravity probe status decoding")
struct AntigravityProbeStatusTests {

    private func decodeStatus(_ json: String) throws -> AntigravityStatusInfo {
        try JSONDecoder().decode(AntigravityStatusInfo.self, from: Data(json.utf8))
    }

    private func decodeProbe(_ json: String) throws -> ProviderProbeResult {
        try JSONDecoder().decode(ProviderProbeResult.self, from: Data(json.utf8))
    }

    @Test("Authenticated probe decodes verified flags and probe fields")
    func authenticatedProbeStatus() throws {
        let status = try decodeStatus("""
        {"authentication":"gemini_api_key_only","authenticationVerified":true,"handshakeVerified":true,"probe":{"state":"authenticated","mode":"authenticate","executable":"/Volumes/Apps/agy_acp_server.par","accountId":"3f2b8c1e-9d4a-4b6f-8e2d-1c0a9b8f7e6d","keyRevision":"r1","usedKey":true,"protocolVersion":1,"authMethods":["gemini-api-key"],"serverName":"antigravity-acp","serverVersion":"1.0","authenticateResultKeys":[],"errorCode":null,"detail":null,"checkedAtUnix":1763472000,"durationMs":812},"accounts":{"3f2b8c1e-9d4a-4b6f-8e2d-1c0a9b8f7e6d":{"name":"Main","auth":"apiKey","hasKey":true}},"termsURL":"https://antigravity.google/docs/ide/extensions/acp","remaining":["quota_display","windows_runtime"]}
        """)
        #expect(status.authenticationVerified == true)
        #expect(status.handshakeVerified == true)
        #expect(status.probeState == "authenticated")
        #expect(status.probeUsedKey == true)
        #expect(status.probeDetail == nil)
        #expect(status.probeCheckedAt == Date(timeIntervalSince1970: 1763472000))
        #expect(status.accounts.count == 1)
        #expect(status.accounts[0].hasKey == true)
    }

    @Test("Status without a probe decodes unverified with no probe fields")
    func statusWithoutProbe() throws {
        let status = try decodeStatus("""
        {"authentication":"gemini_api_key_only","authenticationVerified":false,"handshakeVerified":false,"probe":null,"accounts":{},"termsURL":"https://antigravity.google/docs/ide/extensions/acp","remaining":["quota_display","windows_runtime"]}
        """)
        #expect(status.authenticationVerified == false)
        #expect(status.handshakeVerified == false)
        #expect(status.probeState == nil)
        #expect(status.probeCheckedAt == nil)
        #expect(status.probeUsedKey == false)
        #expect(status.accounts.isEmpty)
    }

    @Test("Handshake probe result decodes ok with the probe detail as message")
    func handshakeProbeResult() throws {
        let result = try decodeProbe("""
        {"provider":"antigravity","probe":{"state":"handshakeOk","mode":"handshake","executable":"/Volumes/Apps/agy_acp_server.par","accountId":null,"keyRevision":null,"usedKey":false,"protocolVersion":1,"authMethods":["gemini-api-key"],"serverName":"antigravity-acp","serverVersion":"1.0","authenticateResultKeys":[],"errorCode":null,"detail":null,"checkedAtUnix":1763472000,"durationMs":640},"antigravityStatus":null}
        """)
        #expect(result.provider == "antigravity")
        #expect(result.ok == true)
        #expect(result.probeState == "handshakeOk")
        #expect(result.probeMode == "handshake")
        #expect(result.authenticated == nil)
        #expect(result.executablePath == "/Volumes/Apps/agy_acp_server.par")
        #expect(result.probeUsedKey == false)
        #expect(result.probeAccountId == nil)
        #expect(result.probeProtocolVersion == 1)
        #expect(result.probeAuthMethods == ["gemini-api-key"])
    }

    @Test("Rejected probe result decodes not ok with the server detail")
    func rejectedProbeResult() throws {
        let result = try decodeProbe("""
        {"provider":"antigravity","probe":{"state":"authRejected","mode":"invalid-key","executable":"/Volumes/Apps/agy_acp_server.par","accountId":null,"keyRevision":null,"usedKey":true,"protocolVersion":1,"authMethods":["gemini-api-key"],"serverName":null,"serverVersion":null,"authenticateResultKeys":[],"errorCode":-32001,"detail":"Antigravity server rejected API-key authentication: API key not valid. Please pass a valid API key.","checkedAtUnix":1763472000,"durationMs":512},"antigravityStatus":null}
        """)
        #expect(result.ok == false)
        #expect(result.probeState == "authRejected")
        #expect(result.probeMode == "invalid-key")
        #expect(result.authenticated == nil)
        #expect(result.message == "Antigravity server rejected API-key authentication: API key not valid. Please pass a valid API key.")
        #expect(result.probeUsedKey == true)
        #expect(result.probeAccountId == nil)
        #expect(result.probeProtocolVersion == 1)
        #expect(result.probeAuthMethods == ["gemini-api-key"])
    }

    @Test("Probe result without a probe decodes empty probe fields")
    func probeResultWithoutProbe() throws {
        let result = try decodeProbe("""
        {"provider":"antigravity","executable":"/Volumes/Apps/agy_acp_server.par","approved":true}
        """)
        #expect(result.probeState == nil)
        #expect(result.probeMode == nil)
        #expect(result.probeDetail == nil)
        #expect(result.probeUsedKey == false)
        #expect(result.probeAccountId == nil)
        #expect(result.probeProtocolVersion == nil)
        #expect(result.probeAuthMethods.isEmpty)
    }

    @Test("Authenticated probe result decodes used key and account id")
    func authenticatedProbeResult() throws {
        let result = try decodeProbe("""
        {"provider":"antigravity","probe":{"state":"authenticated","mode":"authenticate","executable":"/Volumes/Apps/agy_acp_server.par","accountId":"3f2b8c1e-9d4a-4b6f-8e2d-1c0a9b8f7e6d","keyRevision":"r1","usedKey":true,"protocolVersion":1,"authMethods":["gemini-api-key"],"serverName":"antigravity-acp","serverVersion":"1.0","authenticateResultKeys":["account"],"errorCode":null,"detail":null,"checkedAtUnix":1763472000,"durationMs":812},"antigravityStatus":null}
        """)
        #expect(result.ok == true)
        #expect(result.probeState == "authenticated")
        #expect(result.probeMode == "authenticate")
        #expect(result.authenticated == true)
        #expect(result.probeUsedKey == true)
        #expect(result.probeAccountId == "3f2b8c1e-9d4a-4b6f-8e2d-1c0a9b8f7e6d")
        #expect(result.probeProtocolVersion == 1)
        #expect(result.probeAuthMethods == ["gemini-api-key"])
    }
}
