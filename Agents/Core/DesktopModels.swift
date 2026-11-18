import CoincideRemoteKit
import Foundation

// MARK: - Dynamic JSON Value

public nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): Int(i)
        case .double(let d): Int(d)
        default: nil
        }
    }

    public var uint64Value: UInt64? {
        switch self {
        case .int(let i) where i >= 0: UInt64(i)
        case .double(let d) where d >= 0: UInt64(d)
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let obj) = self { return obj[key] }
        return nil
    }

    /// Builds an array value from object dictionaries, the shape most tool results collect.
    public nonisolated static func array(_ objects: [[String: JSONValue]]) -> JSONValue {
        .array(objects.map { .object($0) })
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public nonisolated init(nilLiteral: ()) { self = .null }
    public nonisolated init(booleanLiteral value: Bool) { self = .bool(value) }
    public nonisolated init(integerLiteral value: Int64) { self = .int(value) }
    public nonisolated init(floatLiteral value: Double) { self = .double(value) }
    public nonisolated init(stringLiteral value: String) { self = .string(value) }
    public nonisolated init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public nonisolated init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Lenient Dynamic CodingKey Helper

nonisolated struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

nonisolated extension KeyedDecodingContainer where K == AnyCodingKey {
    func string(_ keys: String...) -> String? {
        for k in keys {
            if let v = try? decodeIfPresent(String.self, forKey: AnyCodingKey(k)) { return v }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for k in keys {
            if let v = try? decodeIfPresent(Bool.self, forKey: AnyCodingKey(k)) { return v }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for k in keys {
            if let v = try? decodeIfPresent(Int.self, forKey: AnyCodingKey(k)) { return v }
            if let d = try? decodeIfPresent(Double.self, forKey: AnyCodingKey(k)) { return Int(d) }
        }
        return nil
    }

    func int64(_ keys: String...) -> Int64? {
        for k in keys {
            if let v = try? decodeIfPresent(Int64.self, forKey: AnyCodingKey(k)) { return v }
            if let d = try? decodeIfPresent(Double.self, forKey: AnyCodingKey(k)) { return Int64(d) }
        }
        return nil
    }

    func uint64(_ keys: String...) -> UInt64? {
        for k in keys {
            if let v = try? decodeIfPresent(UInt64.self, forKey: AnyCodingKey(k)) { return v }
            if let i = try? decodeIfPresent(Int64.self, forKey: AnyCodingKey(k)), i >= 0 { return UInt64(i) }
            if let d = try? decodeIfPresent(Double.self, forKey: AnyCodingKey(k)), d >= 0 { return UInt64(d) }
        }
        return nil
    }

    func double(_ keys: String...) -> Double? {
        for k in keys {
            if let v = try? decodeIfPresent(Double.self, forKey: AnyCodingKey(k)) { return v }
            if let i = try? decodeIfPresent(Int64.self, forKey: AnyCodingKey(k)) { return Double(i) }
        }
        return nil
    }

    func date(_ keys: String...) -> Date? {
        for k in keys {
            let key = AnyCodingKey(k)
            if let d = try? decodeIfPresent(Date.self, forKey: key) { return d }
            if let ms = try? decodeIfPresent(Double.self, forKey: key) {
                return Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000.0 : ms)
            }
            if let iso = try? decodeIfPresent(String.self, forKey: key),
               let parsed = ISO8601DateFormatter().date(from: iso)
            {
                return parsed
            }
        }
        return nil
    }

    func decodeValue<T: Decodable>(_ type: T.Type, keys: String...) -> T? {
        for k in keys {
            if let v = try? decodeIfPresent(type, forKey: AnyCodingKey(k)) { return v }
        }
        return nil
    }
}

// MARK: - Runtime Poll Status

public nonisolated struct TurnResultEntry: Codable, Hashable, Sendable {
    public var serial: UInt64
    public var threadID: String
    public var outcome: String

    public init(serial: UInt64 = 0, threadID: String = "", outcome: String = "") {
        self.serial = serial
        self.threadID = threadID
        self.outcome = outcome
    }
}

public nonisolated struct RuntimePollStatus: Codable, Hashable, Sendable {
    public var busy: Bool
    public var revision: UInt64
    public var running: Int
    public var runningThreadIDs: [String]
    public var starting: Int
    public var startingThreadIDs: [String]
    public var pendingApprovals: Int
    public var pendingQuestions: Int
    public var dataDir: String
    public var activationRequested: Bool
    public var requestedOpenThreadID: String?
    public var shutdownRequested: Bool
    public var legacyImportAvailable: Bool
    public var legacyAntigravityBinary: String?
    public var turnResultsSerial: UInt64
    public var turnResultsRecent: [TurnResultEntry]

    public init(
        busy: Bool = false,
        revision: UInt64 = 0,
        running: Int = 0,
        runningThreadIDs: [String] = [],
        starting: Int = 0,
        startingThreadIDs: [String] = [],
        pendingApprovals: Int = 0,
        pendingQuestions: Int = 0,
        dataDir: String = "",
        activationRequested: Bool = false,
        requestedOpenThreadID: String? = nil,
        shutdownRequested: Bool = false,
        legacyImportAvailable: Bool = false,
        legacyAntigravityBinary: String? = nil,
        turnResultsSerial: UInt64 = 0,
        turnResultsRecent: [TurnResultEntry] = []
    ) {
        self.busy = busy
        self.revision = revision
        self.running = running
        self.runningThreadIDs = runningThreadIDs
        self.starting = starting
        self.startingThreadIDs = startingThreadIDs
        self.pendingApprovals = pendingApprovals
        self.pendingQuestions = pendingQuestions
        self.dataDir = dataDir
        self.activationRequested = activationRequested
        self.requestedOpenThreadID = requestedOpenThreadID
        self.shutdownRequested = shutdownRequested
        self.legacyImportAvailable = legacyImportAvailable
        self.legacyAntigravityBinary = legacyAntigravityBinary
        self.turnResultsSerial = turnResultsSerial
        self.turnResultsRecent = turnResultsRecent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.busy = c.bool("busy", "isBusy") ?? false
        self.revision = c.uint64("revision", "rev") ?? 0

        if let ids = c.decodeValue([String].self, keys: "running", "runningThreads", "runningThreadIDs") {
            self.runningThreadIDs = ids
            self.running = c.int("runningCount") ?? ids.count
        } else if let count = c.int("running", "runningCount") {
            self.running = count
            self.runningThreadIDs = c.decodeValue([String].self, keys: "runningThreadIDs", "runningThreads") ?? []
        } else if let flag = c.bool("running") {
            self.running = flag ? 1 : 0
            self.runningThreadIDs = []
        } else {
            self.running = 0
            self.runningThreadIDs = []
        }

        if let ids = c.decodeValue([String].self, keys: "starting", "startingThreads", "startingThreadIDs") {
            self.startingThreadIDs = ids
            self.starting = c.int("startingCount") ?? ids.count
        } else if let count = c.int("starting", "startingCount") {
            self.starting = count
            self.startingThreadIDs = c.decodeValue([String].self, keys: "startingThreadIDs", "startingThreads") ?? []
        } else if let flag = c.bool("starting") {
            self.starting = flag ? 1 : 0
            self.startingThreadIDs = []
        } else {
            self.starting = 0
            self.startingThreadIDs = []
        }

        if let count = c.int("pendingApprovalsCount") {
            self.pendingApprovals = count
        } else if let byThread = c.decodeValue([String: Int].self, keys: "pendingApprovals") {
            self.pendingApprovals = byThread.values.reduce(0, +)
        } else if let approvalIDs = c.decodeValue([String].self, keys: "pendingApprovals") {
            self.pendingApprovals = approvalIDs.count
        } else {
            self.pendingApprovals = c.int("pendingApprovals", "pending_approvals", "approvals") ?? 0
        }

        if let count = c.int("pendingQuestionsCount") {
            self.pendingQuestions = count
        } else if let byThread = c.decodeValue([String: Int].self, keys: "pendingQuestions") {
            self.pendingQuestions = byThread.values.reduce(0, +)
        } else if let questionIDs = c.decodeValue([String].self, keys: "pendingQuestions") {
            self.pendingQuestions = questionIDs.count
        } else {
            self.pendingQuestions = c.int("pendingQuestions", "pending_questions", "questions") ?? 0
        }

        self.dataDir = c.string("dataDir", "data_dir", "dataDirectory") ?? ""
        self.activationRequested = c.bool("activationRequested") ?? false
        if let openID = c.string("requestedOpen") {
            self.requestedOpenThreadID = openID
        } else if let openObj = c.decodeValue([String: JSONValue].self, keys: "requestedOpen") {
            self.requestedOpenThreadID = openObj["threadId"]?.stringValue ?? openObj["threadID"]?.stringValue
        } else {
            self.requestedOpenThreadID = nil
        }
        self.shutdownRequested = c.bool("shutdownRequested") ?? false
        self.legacyImportAvailable = c.bool("legacyImportAvailable", "legacy_import_available", "canImportLegacy") ?? false
        self.legacyAntigravityBinary = c.string("legacyAntigravityBinary", "legacy_antigravity_binary", "antigravityBinary")
        if let turnResults = c.decodeValue([String: JSONValue].self, keys: "turnResults") {
            self.turnResultsSerial = turnResults["serial"]?.uint64Value ?? 0
            self.turnResultsRecent = turnResults["recent"]?.arrayValue?.compactMap { entry in
                guard let object = entry.objectValue,
                      let threadID = object["threadId"]?.stringValue,
                      !threadID.isEmpty
                else { return nil }
                return TurnResultEntry(
                    serial: object["serial"]?.uint64Value ?? 0,
                    threadID: threadID,
                    outcome: object["outcome"]?.stringValue ?? ""
                )
            } ?? []
        } else {
            self.turnResultsSerial = 0
            self.turnResultsRecent = []
        }
    }

    public func newlyFinishedTurns(since lastSerial: UInt64) -> (entries: [TurnResultEntry], watermark: UInt64) {
        if turnResultsSerial < lastSerial {
            return ([], turnResultsSerial)
        }
        let entries = turnResultsRecent
            .filter { $0.serial > lastSerial }
            .sorted { $0.serial < $1.serial }
        return (entries, max(lastSerial, turnResultsSerial))
    }

    public var totalAttentionCount: Int {
        pendingApprovals + pendingQuestions
    }

    public var hasActiveTurns: Bool {
        running > 0 || starting > 0
    }
}

// MARK: - Providers, Accounts, Antigravity & ACP Registry

public nonisolated struct ProviderKeyChoice: Codable, Hashable, Sendable, Identifiable {
    public var envName: String
    public var label: String
    public var id: String { envName }

    public init(envName: String, label: String) {
        self.envName = envName
        self.label = label
    }
}

public nonisolated struct ProviderSetupCommand: Codable, Hashable, Sendable, Identifiable {
    public var action: String
    public var label: String
    public var command: String
    public var id: String { "\(action):\(command)" }

    public init(action: String, label: String, command: String) {
        self.action = action
        self.label = label
        self.command = command
    }
}

public nonisolated struct ProviderKeyAccountInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var name: String
    public var revision: String?
    public var keyVariable: String?
    public var hasKey: Bool
    public var hasAdminKey: Bool
    public var isSelected: Bool

    public init(
        id: String,
        provider: String = "",
        name: String,
        revision: String? = nil,
        keyVariable: String? = nil,
        hasKey: Bool = true,
        hasAdminKey: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.revision = revision
        self.keyVariable = keyVariable
        self.hasKey = hasKey
        self.hasAdminKey = hasAdminKey
        self.isSelected = isSelected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.string("id", "accountID", "accountId") ?? UUID().uuidString.lowercased()
        self.provider = c.string("provider", "providerID", "providerId") ?? ""
        self.name = c.string("name", "label", "title") ?? "API Key"
        self.revision = c.string("revision")
        self.keyVariable = c.string("keyVariable", "envName", "key_variable", "envVar")
        self.hasKey = c.bool("hasKey", "has_key", "configured") ?? false
        self.hasAdminKey = c.bool("hasAdminKey", "has_admin_key") ?? false
        self.isSelected = c.bool("isSelected", "selected", "isDefault") ?? false
    }
}

public nonisolated struct ProviderLoginAccountInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var name: String
    public var revision: String?
    public var homePath: String?
    public var envVar: String?
    public var loginCommand: String?
    public var isReady: Bool
    public var statusText: String?
    public var loginState: String?
    public var authURL: String?

    public init(
        id: String,
        provider: String = "",
        name: String,
        revision: String? = nil,
        homePath: String? = nil,
        envVar: String? = nil,
        loginCommand: String? = nil,
        isReady: Bool = false,
        statusText: String? = nil,
        loginState: String? = nil,
        authURL: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.revision = revision
        self.homePath = homePath
        self.envVar = envVar
        self.loginCommand = loginCommand
        self.isReady = isReady
        self.statusText = statusText
        self.loginState = loginState
        self.authURL = authURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.string("id", "accountID", "accountId") ?? UUID().uuidString.lowercased()
        self.provider = c.string("provider", "providerID", "providerId") ?? ""
        self.name = c.string("name", "label", "title") ?? "Account"
        self.revision = c.string("revision")
        self.homePath = c.string("homePath", "home", "profilePath")
        self.envVar = c.string("envVar", "envName")
        self.loginCommand = c.string("loginCommand", "command")
        self.isReady = c.bool("isReady", "ready", "authenticated") ?? false
        self.statusText = c.string("statusText", "status", "detail")
        self.loginState = c.string("loginState", "state")
        self.authURL = c.string("authURL", "authUrl", "url")
    }
}

public nonisolated struct AntigravityStatusInfo: Codable, Hashable, Sendable {
    public var authentication: String
    public var authenticationVerified: Bool
    public var handshakeVerified: Bool
    public var probeState: String?
    public var probeCheckedAt: Date?
    public var probeDetail: String?
    public var probeUsedKey: Bool
    public var binaryPath: String?
    public var helperPath: String?
    public var legacyBinaryPath: String?
    public var termsURL: String?
    public var accounts: [ProviderKeyAccountInfo]

    public init(
        authentication: String = "gemini_api_key_only",
        authenticationVerified: Bool = false,
        handshakeVerified: Bool = false,
        probeState: String? = nil,
        probeCheckedAt: Date? = nil,
        probeDetail: String? = nil,
        probeUsedKey: Bool = false,
        binaryPath: String? = nil,
        helperPath: String? = nil,
        legacyBinaryPath: String? = nil,
        termsURL: String? = "https://antigravity.google/docs/ide/extensions/acp",
        accounts: [ProviderKeyAccountInfo] = []
    ) {
        self.authentication = authentication
        self.authenticationVerified = authenticationVerified
        self.handshakeVerified = handshakeVerified
        self.probeState = probeState
        self.probeCheckedAt = probeCheckedAt
        self.probeDetail = probeDetail
        self.probeUsedKey = probeUsedKey
        self.binaryPath = binaryPath
        self.helperPath = helperPath
        self.legacyBinaryPath = legacyBinaryPath
        self.termsURL = termsURL
        self.accounts = accounts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.authentication = c.string("authentication", "authMode") ?? "gemini_api_key_only"
        self.authenticationVerified = c.bool("authenticationVerified", "verified") ?? false
        self.handshakeVerified = c.bool("handshakeVerified") ?? false
        if let probe = c.decodeValue([String: JSONValue].self, keys: "probe") {
            self.probeState = probe["state"]?.stringValue
            self.probeDetail = probe["detail"]?.stringValue
            self.probeUsedKey = probe["usedKey"]?.boolValue ?? false
            if let checked = probe["checkedAtUnix"]?.doubleValue {
                self.probeCheckedAt = Date(timeIntervalSince1970: checked)
            } else {
                self.probeCheckedAt = nil
            }
        } else {
            self.probeState = nil
            self.probeDetail = nil
            self.probeUsedKey = false
            self.probeCheckedAt = nil
        }
        self.binaryPath = c.string("binaryPath", "executable", "executablePath")
        self.helperPath = c.string("helperPath", "companion", "helper")
        self.legacyBinaryPath = c.string("legacyBinaryPath", "legacyAntigravityBinary")
        self.termsURL = c.string("termsURL", "termsUrl")
        if let arr = c.decodeValue([ProviderKeyAccountInfo].self, keys: "accounts", "keyAccounts") {
            self.accounts = arr
        } else if let map = c.decodeValue([String: JSONValue].self, keys: "accounts") {
            self.accounts = map.keys.sorted().map { key in
                let entry = map[key]
                return ProviderKeyAccountInfo(
                    id: key,
                    provider: "antigravity",
                    name: entry?["name"]?.stringValue ?? key,
                    keyVariable: "GEMINI_API_KEY",
                    hasKey: entry?["hasKey"]?.boolValue ?? false
                )
            }
        } else {
            self.accounts = []
        }
    }
}

public nonisolated struct ProviderProbeResult: Codable, Hashable, Sendable {
    public var provider: String
    public var ok: Bool
    public var approved: Bool
    public var version: String?
    public var executablePath: String?
    public var companionPath: String?
    public var authenticated: Bool?
    public var accountSummary: String?
    public var message: String?
    public var modelsCount: Int?
    public var probeState: String?
    public var probeMode: String?
    public var probeDetail: String?

    public init(
        provider: String,
        ok: Bool,
        approved: Bool = false,
        version: String? = nil,
        executablePath: String? = nil,
        companionPath: String? = nil,
        authenticated: Bool? = nil,
        accountSummary: String? = nil,
        message: String? = nil,
        modelsCount: Int? = nil,
        probeState: String? = nil,
        probeMode: String? = nil,
        probeDetail: String? = nil
    ) {
        self.provider = provider
        self.ok = ok
        self.approved = approved
        self.version = version
        self.executablePath = executablePath
        self.companionPath = companionPath
        self.authenticated = authenticated
        self.accountSummary = accountSummary
        self.message = message
        self.modelsCount = modelsCount
        self.probeState = probeState
        self.probeMode = probeMode
        self.probeDetail = probeDetail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.provider = c.string("provider", "id") ?? ""
        self.executablePath = c.string("executable", "executablePath", "path", "binaryPath")
        self.companionPath = c.string("companion", "helperPath")
        self.approved = c.bool("approved") ?? (self.executablePath != nil)
        self.version = c.string("version", "agentVersion")
        self.authenticated = c.bool("authenticated", "isAuthenticated", "ready")
        self.accountSummary = c.string("account")
        self.message = c.string("statusNote", "message", "detail", "status", "error")
        if let modelsArr = c.decodeValue([JSONValue].self, keys: "models") {
            self.modelsCount = modelsArr.count
        } else {
            self.modelsCount = c.int("modelsCount", "modelCount")
        }
        if let probe = c.decodeValue([String: JSONValue].self, keys: "probe") {
            self.probeState = probe["state"]?.stringValue
            self.probeMode = probe["mode"]?.stringValue
            self.probeDetail = probe["detail"]?.stringValue
            if self.executablePath == nil {
                self.executablePath = probe["executable"]?.stringValue
            }
            if self.probeState == "authenticated" {
                self.authenticated = true
            }
            if self.message == nil {
                self.message = self.probeDetail
            }
        } else {
            self.probeState = nil
            self.probeMode = nil
            self.probeDetail = nil
        }
        if let probeState = self.probeState {
            self.ok = probeState == "handshakeOk" || probeState == "authenticated"
        } else {
            self.ok = c.bool("ok", "ready", "installed", "valid")
                ?? (self.executablePath != nil && c.string("error") == nil)
        }
    }
}

public nonisolated struct CatalogModelEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var name: String
    public var description: String?
    public var efforts: [String]
    public var defaultEffort: String?
    public var speeds: [RemoteSpeed]
    public var supportsImages: Bool
    public var isFavorite: Bool
    public var isHidden: Bool
    public var isVisible: Bool
    public var isDefault: Bool
    public var isCustom: Bool

    public init(
        id: String,
        provider: String = "",
        name: String,
        description: String? = nil,
        efforts: [String] = [],
        defaultEffort: String? = nil,
        speeds: [RemoteSpeed] = [],
        supportsImages: Bool = true,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        isVisible: Bool = true,
        isDefault: Bool = false,
        isCustom: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.description = description
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.speeds = speeds
        self.supportsImages = supportsImages
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.isVisible = isVisible
        self.isDefault = isDefault
        self.isCustom = isCustom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let modelID = c.string("id", "modelID", "modelId") ?? "default"
        self.id = modelID
        self.provider = c.string("provider", "providerID", "providerId") ?? ""
        self.name = c.string("displayName", "name", "title") ?? modelID
        self.description = c.string("description", "detail")
        self.efforts = c.decodeValue([String].self, keys: "reportedEfforts", "efforts", "reasoningEfforts") ?? []
        self.defaultEffort = c.string("defaultEffort", "default_effort")
        self.speeds = c.decodeValue([RemoteSpeed].self, keys: "reportedSpeeds", "speeds") ?? []
        self.supportsImages = c.bool("supportsImages", "supports_images", "vision") ?? true
        let hiddenFlag = c.bool("hidden", "isHidden") ?? false
        self.isFavorite = c.bool("favorite", "isFavorite") ?? false
        self.isHidden = hiddenFlag
        self.isVisible = c.bool("isVisible", "visible") ?? !hiddenFlag
        self.isDefault = c.bool("isDefault", "default") ?? false
        self.isCustom = c.bool("custom", "isCustom") ?? false
    }
}

public nonisolated struct DesktopProviderInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var isACP: Bool
    public var isEnabled: Bool
    public var isApproved: Bool
    public var isInstalled: Bool
    public var state: String
    public var configuredExecutable: String?
    public var approvedExecutable: String?
    public var effectiveExecutable: String?
    public var approvedCompanion: String?
    public var candidateExecutables: [String]
    public var environment: [String: String]
    public var keyChoices: [ProviderKeyChoice]
    public var setupCommands: [ProviderSetupCommand]
    public var supportsAPIKeyAccounts: Bool
    public var supportsLoginAccounts: Bool
    public var defaultKeyVariable: String?
    public var keyAccounts: [ProviderKeyAccountInfo]
    public var loginAccounts: [ProviderLoginAccountInfo]
    public var antigravityStatus: AntigravityStatusInfo?
    public var models: [CatalogModelEntry]
    public var errorMessage: String?

    public var executablePath: String? {
        effectiveExecutable ?? configuredExecutable ?? approvedExecutable
    }

    public var discoveredPath: String? {
        candidateExecutables.first ?? effectiveExecutable
    }

    public init(
        id: String,
        displayName: String,
        isACP: Bool = false,
        isEnabled: Bool = true,
        isApproved: Bool = false,
        isInstalled: Bool = false,
        state: String = "unknown",
        configuredExecutable: String? = nil,
        approvedExecutable: String? = nil,
        effectiveExecutable: String? = nil,
        approvedCompanion: String? = nil,
        candidateExecutables: [String] = [],
        environment: [String: String] = [:],
        keyChoices: [ProviderKeyChoice] = [],
        setupCommands: [ProviderSetupCommand] = [],
        supportsAPIKeyAccounts: Bool = true,
        supportsLoginAccounts: Bool = false,
        defaultKeyVariable: String? = nil,
        keyAccounts: [ProviderKeyAccountInfo] = [],
        loginAccounts: [ProviderLoginAccountInfo] = [],
        antigravityStatus: AntigravityStatusInfo? = nil,
        models: [CatalogModelEntry] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.isACP = isACP
        self.isEnabled = isEnabled
        self.isApproved = isApproved
        self.isInstalled = isInstalled
        self.state = state
        self.configuredExecutable = configuredExecutable
        self.approvedExecutable = approvedExecutable
        self.effectiveExecutable = effectiveExecutable
        self.approvedCompanion = approvedCompanion
        self.candidateExecutables = candidateExecutables
        self.environment = environment
        self.keyChoices = keyChoices
        self.setupCommands = setupCommands
        self.supportsAPIKeyAccounts = supportsAPIKeyAccounts
        self.supportsLoginAccounts = supportsLoginAccounts
        self.defaultKeyVariable = defaultKeyVariable
        self.keyAccounts = keyAccounts
        self.loginAccounts = loginAccounts
        self.antigravityStatus = antigravityStatus
        self.models = models
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let providerID = c.string("id", "provider", "providerId") ?? "unknown"
        self.id = providerID
        self.displayName = c.string("displayName", "display_name", "name", "title")
            ?? AgentBranding.displayName(for: providerID)
        self.isACP = c.bool("isAcp", "isACP") ?? providerID.hasPrefix("acp-")
        self.isEnabled = c.bool("enabled", "isEnabled") ?? true
        self.isApproved = c.bool("approved", "isApproved") ?? false
        self.configuredExecutable = c.string("configuredExecutable", "executablePath", "customPath")
        self.approvedExecutable = c.string("approvedExecutable")
        let candidates = c.decodeValue([String].self, keys: "candidateExecutables", "candidates") ?? []
        self.candidateExecutables = candidates
        self.effectiveExecutable = c.string("effectiveExecutable", "executable")
            ?? self.approvedExecutable ?? self.configuredExecutable ?? candidates.first
        self.approvedCompanion = c.string("approvedCompanion", "helperPath")
        self.environment = c.decodeValue([String: String].self, keys: "environment") ?? [:]
        let choices = c.decodeValue([ProviderKeyChoice].self, keys: "keyChoices") ?? []
        self.keyChoices = choices
        self.setupCommands = c.decodeValue([ProviderSetupCommand].self, keys: "setupCommands") ?? []
        self.isInstalled = c.bool("isInstalled", "installed")
            ?? (self.effectiveExecutable != nil || !candidates.isEmpty)
        if let explicitState = c.string("state", "status") {
            self.state = explicitState
        } else if !self.isEnabled {
            self.state = "off"
        } else if self.isApproved && self.effectiveExecutable != nil {
            self.state = "ready"
        } else if self.isInstalled {
            self.state = "attention"
        } else {
            self.state = "notInstalled"
        }
        self.supportsAPIKeyAccounts = c.bool("supportsAPIKeyAccounts", "supportsKeyAccounts")
            ?? (!choices.isEmpty || providerID == "antigravity")
        self.supportsLoginAccounts = c.bool("signInSupported", "supportsLoginAccounts") ?? false
        self.defaultKeyVariable = choices.first?.envName
            ?? c.string("defaultKeyVariable", "keyVariable")
            ?? Self.inferredKeyVariable(for: providerID)
        self.keyAccounts = c.decodeValue([ProviderKeyAccountInfo].self, keys: "keyAccounts", "apiKeyAccounts") ?? []
        self.loginAccounts = c.decodeValue([ProviderLoginAccountInfo].self, keys: "loginAccounts", "profiles") ?? []
        self.antigravityStatus = c.decodeValue(AntigravityStatusInfo.self, keys: "antigravityStatus", "antigravity")
        self.models = c.decodeValue([CatalogModelEntry].self, keys: "models") ?? []
        self.errorMessage = c.string("errorMessage", "error")
    }

    public static func inferredKeyVariable(for provider: String) -> String? {
        switch provider.lowercased() {
        case "antigravity": "GEMINI_API_KEY"
        case "claude": "ANTHROPIC_API_KEY"
        case "codex": "OPENAI_API_KEY"
        case "grok": "XAI_API_KEY"
        case "cursor": "CURSOR_API_KEY"
        default: nil
        }
    }
}

public nonisolated struct ACPRegistryAgentInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var providerID: String
    public var name: String
    public var description: String?
    public var website: String?
    public var icon: String?
    public var executable: String?
    public var arguments: [String]
    public var isInstalled: Bool
    public var isRegistered: Bool

    public init(
        id: String,
        providerID: String? = nil,
        name: String,
        description: String? = nil,
        website: String? = nil,
        icon: String? = nil,
        executable: String? = nil,
        arguments: [String] = [],
        isInstalled: Bool = false,
        isRegistered: Bool = false
    ) {
        self.id = id
        self.providerID = providerID ?? "acp-\(id)"
        self.name = name
        self.description = description
        self.website = website
        self.icon = icon
        self.executable = executable
        self.arguments = arguments
        self.isInstalled = isInstalled
        self.isRegistered = isRegistered
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let rawID = c.string("id", "agentId", "agentID") ?? UUID().uuidString.lowercased()
        self.id = rawID
        self.providerID = c.string("providerID", "providerId", "provider")
            ?? (rawID.hasPrefix("acp-") ? rawID : "acp-\(rawID)")
        self.name = c.string("name", "displayName", "title") ?? rawID
        self.description = c.string("description", "summary", "detail")
        self.website = c.string("website", "homepage", "url")
        self.icon = c.string("icon", "iconUrl")
        self.executable = c.string("executable", "binary", "path")
        self.arguments = c.decodeValue([String].self, keys: "arguments", "args") ?? []
        self.isInstalled = c.bool("isInstalled", "installed") ?? (self.executable != nil)
        self.isRegistered = c.bool("isRegistered", "registered", "added") ?? false
    }
}

// MARK: - Integrated PTY Terminal Models

public nonisolated struct TerminalSessionSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var threadID: String
    public var number: Int
    public var name: String
    public var title: String
    public var directory: String
    public var busy: Bool
    public var foreground: String?
    public var exited: Bool
    public var exitCode: Int?
    public var exitMessage: String?
    public var keepOpen: Bool
    public var bells: Int

    public init(
        id: String,
        threadID: String = "",
        number: Int = 1,
        name: String = "Terminal 1",
        title: String = "Terminal",
        directory: String = "",
        busy: Bool = false,
        foreground: String? = nil,
        exited: Bool = false,
        exitCode: Int? = nil,
        exitMessage: String? = nil,
        keepOpen: Bool = false,
        bells: Int = 0
    ) {
        self.id = id
        self.threadID = threadID
        self.number = number
        self.name = name
        self.title = title
        self.directory = directory
        self.busy = busy
        self.foreground = foreground
        self.exited = exited
        self.exitCode = exitCode
        self.exitMessage = exitMessage
        self.keepOpen = keepOpen
        self.bells = bells
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.string("terminalId", "terminalID", "id") ?? UUID().uuidString.lowercased()
        self.threadID = c.string("threadId", "threadID") ?? ""
        self.number = c.int("number") ?? 1
        let fallbackName = "Terminal \(self.number)"
        self.name = c.string("name") ?? fallbackName
        self.title = c.string("title") ?? self.name
        self.directory = c.string("directory", "cwd", "path") ?? ""
        self.busy = c.bool("busy", "isBusy") ?? false
        self.foreground = c.string("foreground", "process", "command")
        self.exitCode = c.int("exitCode", "exit_code")
        self.exited = c.bool("exited", "isExited") ?? (self.exitCode != nil)
        self.exitMessage = c.string("exitMessage", "message", "exit_message")
        self.keepOpen = c.bool("keepOpen", "keep_open") ?? false
        self.bells = c.int("bells") ?? 0
    }
}

public nonisolated struct TerminalStyledRun: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var columnCount: Int
    public var foregroundRGB: [UInt8]?
    public var backgroundRGB: [UInt8]?
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var dim: Bool
    public var inverse: Bool
    public var linkIndex: Int?
    public var linkURL: String?

    public init(
        id: Int = 0,
        text: String,
        columnCount: Int? = nil,
        foregroundRGB: [UInt8]? = nil,
        backgroundRGB: [UInt8]? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        dim: Bool = false,
        inverse: Bool = false,
        linkIndex: Int? = nil,
        linkURL: String? = nil
    ) {
        self.id = id
        self.text = text
        self.columnCount = columnCount ?? text.count
        self.foregroundRGB = foregroundRGB
        self.backgroundRGB = backgroundRGB
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.dim = dim
        self.inverse = inverse
        self.linkIndex = linkIndex
        self.linkURL = linkURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let txt = c.string("text") ?? ""
        self.id = c.int("col", "id", "startCol") ?? 0
        self.text = txt
        self.columnCount = c.int("columnCount", "cols", "width") ?? txt.count
        self.foregroundRGB = c.decodeValue([UInt8].self, keys: "fg", "foregroundRGB", "foreground")
        self.backgroundRGB = c.decodeValue([UInt8].self, keys: "bg", "backgroundRGB", "background")
        self.bold = c.bool("bold") ?? false
        self.italic = c.bool("italic") ?? false
        self.underline = c.bool("underline") ?? false
        self.strikethrough = c.bool("strikethrough", "strikeout") ?? false
        self.dim = c.bool("dim") ?? false
        self.inverse = c.bool("inverse") ?? false
        self.linkIndex = c.int("link")
        self.linkURL = c.string("linkURL", "linkUrl", "href")
    }
}

public nonisolated struct TerminalViewportLine: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var wrapped: Bool
    public var runs: [TerminalStyledRun]

    public init(id: Int, text: String = "", wrapped: Bool = false, runs: [TerminalStyledRun] = []) {
        self.id = id
        self.text = text
        self.wrapped = wrapped
        self.runs = runs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.int("id", "row", "line") ?? 0
        self.text = c.string("text") ?? ""
        self.wrapped = c.bool("wrapped", "wrapline") ?? false
        self.runs = c.decodeValue([TerminalStyledRun].self, keys: "runs", "spans") ?? []
    }
}

public nonisolated struct TerminalViewportSnapshot: Codable, Hashable, Sendable {
    public var terminalID: String
    public var title: String
    public var directory: String?
    public var rows: Int
    public var cols: Int
    public var revision: UInt64
    public var displayOffset: Int
    public var historySize: Int
    public var atBottom: Bool
    public var alternateScreen: Bool
    public var exitCode: Int?
    public var cursorRow: Int
    public var cursorCol: Int
    public var cursorVisible: Bool
    public var cursorShape: String
    public var cursorBlinking: Bool
    public var lines: [TerminalViewportLine]
    public var links: [String]

    public init(
        terminalID: String = "",
        title: String = "Terminal",
        directory: String? = nil,
        rows: Int = 24,
        cols: Int = 80,
        revision: UInt64 = 0,
        displayOffset: Int = 0,
        historySize: Int = 0,
        atBottom: Bool = true,
        alternateScreen: Bool = false,
        exitCode: Int? = nil,
        cursorRow: Int = 0,
        cursorCol: Int = 0,
        cursorVisible: Bool = true,
        cursorShape: String = "block",
        cursorBlinking: Bool = false,
        lines: [TerminalViewportLine] = [],
        links: [String] = []
    ) {
        self.terminalID = terminalID
        self.title = title
        self.directory = directory
        self.rows = rows
        self.cols = cols
        self.revision = revision
        self.displayOffset = displayOffset
        self.historySize = historySize
        self.atBottom = atBottom
        self.alternateScreen = alternateScreen
        self.exitCode = exitCode
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.cursorVisible = cursorVisible
        self.cursorShape = cursorShape
        self.cursorBlinking = cursorBlinking
        self.lines = lines
        self.links = links
    }

    private struct RawGridCell: Decodable {
        var text: String?
        var link: Int?
        var width: Int?
        var continuation: Bool?
        var wrapline: Bool?
        var foreground: [UInt8]?
        var background: [UInt8]?
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var inverse: Bool?
        var dim: Bool?
        var strikethrough: Bool?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.terminalID = c.string("terminalId", "terminalID", "id") ?? ""
        self.title = c.string("title", "name") ?? "Terminal"
        self.directory = c.string("directory", "cwd")
        self.rows = c.int("rows") ?? 24
        self.cols = c.int("cols", "columns") ?? 80
        self.revision = c.uint64("revision") ?? 0
        self.exitCode = c.int("exitCode", "exit_code")
        let parsedLinks = c.decodeValue([String].self, keys: "links") ?? []
        self.links = parsedLinks

        if let viewport = c.decodeValue([String: JSONValue].self, keys: "viewport") {
            let offset = viewport["displayOffset"]?.intValue ?? c.int("displayOffset") ?? 0
            self.displayOffset = offset
            self.historySize = viewport["historySize"]?.intValue ?? c.int("historySize") ?? 0
            self.atBottom = viewport["atBottom"]?.boolValue ?? (offset == 0)
            self.alternateScreen = viewport["alternateScreen"]?.boolValue ?? false
        } else {
            let offset = c.int("displayOffset", "scrollOffset") ?? 0
            self.displayOffset = offset
            self.historySize = c.int("historySize", "scrollback") ?? 0
            self.atBottom = offset == 0
            self.alternateScreen = false
        }

        if let cursor = c.decodeValue([String: JSONValue].self, keys: "cursor") {
            self.cursorRow = cursor["row"]?.intValue ?? 0
            self.cursorCol = cursor["col"]?.intValue ?? 0
            self.cursorVisible = cursor["visible"]?.boolValue ?? true
            self.cursorShape = cursor["shape"]?.stringValue ?? "block"
            self.cursorBlinking = cursor["blinking"]?.boolValue ?? false
        } else {
            self.cursorRow = c.int("cursorRow") ?? 0
            self.cursorCol = c.int("cursorCol") ?? 0
            self.cursorVisible = c.bool("cursorVisible") ?? true
            self.cursorShape = c.string("cursorShape") ?? "block"
            self.cursorBlinking = c.bool("cursorBlinking") ?? false
        }

        // Fast path 1: `coincide-macos-ffi` pre-coalesced `runs: [[TerminalStyledRun]]` + `lines: [String]`
        if let rowRuns = try? c.decode([[TerminalStyledRun]].self, forKey: AnyCodingKey("runs")) {
            let plainLines = c.decodeValue([String].self, keys: "lines") ?? []
            self.lines = rowRuns.enumerated().map { rowIdx, runs in
                let resolvedRuns = runs.map { r -> TerminalStyledRun in
                    var copy = r
                    if copy.linkURL == nil, let linkIdx = copy.linkIndex, (0..<parsedLinks.count).contains(linkIdx) {
                        copy.linkURL = parsedLinks[linkIdx]
                    }
                    return copy
                }
                let plain = rowIdx < plainLines.count ? plainLines[rowIdx] : resolvedRuns.map(\.text).joined()
                return TerminalViewportLine(id: rowIdx, text: plain, wrapped: false, runs: resolvedRuns)
            }
            return
        }

        // Fast path 2: structured `[TerminalViewportLine]`
        if let structuredLines = try? c.decode([TerminalViewportLine].self, forKey: AnyCodingKey("lines")) {
            self.lines = structuredLines.enumerated().map { idx, line in
                var updated = line
                if updated.id == 0 && idx > 0 { updated.id = idx }
                return updated
            }
            return
        }

        // Fallback path 3: `grid: [[RawGridCell]]` + `lines: [String]`
        let plainLines = c.decodeValue([String].self, keys: "lines") ?? []
        if let grid = try? c.decode([[RawGridCell]].self, forKey: AnyCodingKey("grid")) {
            self.lines = grid.enumerated().map { rowIndex, rowCells in
                let plain = rowIndex < plainLines.count ? plainLines[rowIndex] : ""
                let wrapped = rowCells.last?.wrapline ?? false
                let runs = Self.coalesceRuns(cells: rowCells, links: parsedLinks)
                return TerminalViewportLine(id: rowIndex, text: plain, wrapped: wrapped, runs: runs)
            }
        } else {
            self.lines = plainLines.enumerated().map { idx, text in
                TerminalViewportLine(
                    id: idx,
                    text: text,
                    wrapped: false,
                    runs: text.isEmpty ? [] : [TerminalStyledRun(id: 0, text: text)]
                )
            }
        }
    }

    private static func coalesceRuns(cells: [RawGridCell], links: [String]) -> [TerminalStyledRun] {
        var runs: [TerminalStyledRun] = []
        var current: TerminalStyledRun?
        var col = 0

        for cell in cells {
            if cell.continuation == true || cell.width == 0 {
                continue
            }
            let ch = cell.text ?? " "
            let cellWidth = max(1, cell.width ?? 1)
            let linkURL: String? = cell.link.flatMap { idx in
                (0..<links.count).contains(idx) ? links[idx] : nil
            }
            let bold = cell.bold ?? false
            let italic = cell.italic ?? false
            let underline = cell.underline ?? false
            let strikethrough = cell.strikethrough ?? false
            let dim = cell.dim ?? false
            let inverse = cell.inverse ?? false

            if var active = current,
               active.foregroundRGB == cell.foreground,
               active.backgroundRGB == cell.background,
               active.bold == bold,
               active.italic == italic,
               active.underline == underline,
               active.strikethrough == strikethrough,
               active.dim == dim,
               active.inverse == inverse,
               active.linkURL == linkURL
            {
                active.text.append(ch)
                active.columnCount += cellWidth
                current = active
            } else {
                if let active = current {
                    runs.append(active)
                }
                current = TerminalStyledRun(
                    id: col,
                    text: ch,
                    columnCount: cellWidth,
                    foregroundRGB: cell.foreground,
                    backgroundRGB: cell.background,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough,
                    dim: dim,
                    inverse: inverse,
                    linkIndex: cell.link,
                    linkURL: linkURL
                )
            }
            col += cellWidth
        }

        if let active = current {
            runs.append(active)
        }
        return runs
    }
}

// MARK: - Workspace Files, Search & Instructions

public nonisolated struct MemoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var scope: String
    public var value: String
    public var updatedAt: Double

    public var id: String { scope + "\u{1f}" + key }

    public init(key: String, scope: String, value: String, updatedAt: Double) {
        self.key = key
        self.scope = scope
        self.value = value
        self.updatedAt = updatedAt
    }
}

public nonisolated struct WorkerSpawnRequest: Codable, Hashable, Sendable {
    public var name: String
    public var task: String
    public var targetFiles: [String]
    public var assistantId: String? = nil

    public init(name: String, task: String, targetFiles: [String], assistantId: String? = nil) {
        self.name = name
        self.task = task
        self.targetFiles = targetFiles
        self.assistantId = assistantId
    }
}

public nonisolated struct WorkerProgress: Codable, Hashable, Sendable {
    public var stage: String
    public var transcriptItems: Int
    public var elapsedSeconds: Double

    public init(stage: String, transcriptItems: Int, elapsedSeconds: Double) {
        self.stage = stage
        self.transcriptItems = transcriptItems
        self.elapsedSeconds = elapsedSeconds
    }
}

public nonisolated struct WorkerRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var parentThreadId: String
    public var threadId: String
    public var task: String
    public var provider: String
    public var targetFiles: [String]
    public var status: String
    public var cancelRequested: Bool
    public var transcriptStart: Int
    public var transcriptItems: Int
    public var elapsedSeconds: Double
    public var createdAt: Double
    public var startedAt: Double
    public var completedAt: Double?
    public var error: String?
    public var result: String?
    public var progress: WorkerProgress?
    public var assistantId: String? = nil

    public var isTerminal: Bool {
        status == "completed" || status == "failed" || status == "cancelled"
    }

    public var isRunning: Bool {
        status == "running"
    }

    public static func runningWorkers(from workers: [WorkerRecord]) -> [WorkerRecord] {
        workers.filter(\.isRunning)
    }

    public static func terminalWorkers(from workers: [WorkerRecord]) -> [WorkerRecord] {
        workers.filter(\.isTerminal)
    }

    public static func bulkFailureMessage(action: String, attempted: Int, failures: [String]) -> String? {
        guard !failures.isEmpty else { return nil }
        return "Failed to \(action) \(failures.count) of \(attempted) workers: \(failures.joined(separator: "; "))"
    }

    public func isOrphan(knownParentThreadIDs: Set<String>?) -> Bool {
        guard let knownParentThreadIDs else { return false }
        let parent = parentThreadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parent.isEmpty else { return true }
        return !knownParentThreadIDs.contains(parent.lowercased())
    }
}

public nonisolated struct WorkerPlanStep: Codable, Hashable, Sendable {
    public var name: String
    public var task: String
    public var targetFiles: [String]

    public init(name: String, task: String, targetFiles: [String]) {
        self.name = name
        self.task = task
        self.targetFiles = targetFiles
    }
}

public nonisolated struct WorkerPlan: Codable, Hashable, Sendable, Identifiable {
    public var planId: String
    public var parentThreadId: String
    public var task: String
    public var steps: [WorkerPlanStep]
    public var createdAt: Double
    public var objective: String?
    public var mode: String?
    public var markdown: String?
    public var filesListed: Int?
    public var relevantFiles: Int?
    public var agentNotesPath: String?

    public var id: String { planId }

    public init(planId: String, parentThreadId: String, task: String, steps: [WorkerPlanStep], createdAt: Double) {
        self.planId = planId
        self.parentThreadId = parentThreadId
        self.task = task
        self.steps = steps
        self.createdAt = createdAt
    }
}

public nonisolated struct WorkspaceFileEntry: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var sizeBytes: Int64?
    public var gitStatus: String?
    public var modifiedAt: Double?
    public var isSymlink: Bool?
    public var symlinkTarget: String?
    public var isExecutable: Bool?

    public var id: String { path }

    public init(
        path: String,
        name: String? = nil,
        isDirectory: Bool = false,
        sizeBytes: Int64? = nil,
        gitStatus: String? = nil,
        modifiedAt: Double? = nil,
        isSymlink: Bool? = nil,
        symlinkTarget: String? = nil,
        isExecutable: Bool? = nil
    ) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.gitStatus = gitStatus
        self.modifiedAt = modifiedAt
        self.isSymlink = isSymlink
        self.symlinkTarget = symlinkTarget
        self.isExecutable = isExecutable
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let pathString = try? single.decode(String.self)
        {
            let isDir = pathString.hasSuffix("/")
            let clean = isDir ? String(pathString.dropLast()) : pathString
            self.path = clean
            self.name = (clean as NSString).lastPathComponent
            self.isDirectory = isDir
            self.sizeBytes = nil
            self.gitStatus = nil
            self.modifiedAt = nil
            self.isSymlink = nil
            self.symlinkTarget = nil
            self.isExecutable = nil
            return
        }
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let p = c.string("path", "relativePath", "file") ?? ""
        self.path = p
        self.name = c.string("name", "fileName") ?? (p as NSString).lastPathComponent
        self.isDirectory = c.bool("isDirectory", "isDir", "directory") ?? (c.string("kind", "type") == "directory")
        self.sizeBytes = c.int64("sizeBytes", "byteLen", "size")
        self.gitStatus = c.string("gitStatus", "status")
        self.modifiedAt = c.double("modifiedAt", "mtime", "modified")
        self.isSymlink = c.bool("isSymlink", "symlink")
        self.symlinkTarget = c.string("symlinkTarget", "linkTarget")
        self.isExecutable = c.bool("isExecutable", "executable")
    }
}

public nonisolated struct WorkspaceSearchHit: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var lineNumber: Int
    public var column: Int
    public var lineText: String

    public var id: String { "\(path):\(lineNumber):\(column)" }

    public init(path: String, lineNumber: Int, column: Int = 1, lineText: String) {
        self.path = path
        self.lineNumber = lineNumber
        self.column = column
        self.lineText = lineText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.path = c.string("path", "file") ?? ""
        self.lineNumber = c.int("line", "lineNumber", "row") ?? 1
        self.column = c.int("column", "col") ?? 1
        self.lineText = c.string("text", "lineText", "preview", "snippet") ?? ""
    }
}

public nonisolated struct WorkspaceFileDocument: Codable, Hashable, Sendable {
    public var path: String
    public var absolutePath: String?
    public var content: String
    public var lineCount: Int
    public var sizeBytes: Int64
    public var isBinary: Bool
    public var isTruncated: Bool
    public var language: String?

    public init(
        path: String,
        absolutePath: String? = nil,
        content: String,
        lineCount: Int? = nil,
        sizeBytes: Int64? = nil,
        isBinary: Bool = false,
        isTruncated: Bool = false,
        language: String? = nil
    ) {
        self.path = path
        self.absolutePath = absolutePath
        self.content = content
        self.lineCount = lineCount ?? max(1, content.components(separatedBy: "\n").count)
        self.sizeBytes = sizeBytes ?? Int64(content.utf8.count)
        self.isBinary = isBinary
        self.isTruncated = isTruncated
        self.language = language
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let p = c.string("path", "relativePath") ?? ""
        self.path = p
        self.absolutePath = c.string("absolutePath", "resolvedPath", "fullPath")
        if let text = c.string("content", "text", "body") {
            self.content = text
        } else if let lines = c.decodeValue([String].self, keys: "lines") {
            self.content = lines.joined(separator: "\n")
        } else {
            self.content = ""
        }
        self.lineCount = c.int("totalLines", "lineCount", "linesCount")
            ?? max(1, self.content.components(separatedBy: "\n").count)
        self.sizeBytes = c.int64("byteLen", "sizeBytes", "size", "bytes") ?? Int64(self.content.utf8.count)
        self.isBinary = c.bool("isBinary", "binary") ?? false
        self.isTruncated = c.bool("truncated", "isTruncated") ?? false
        self.language = c.string("language", "lang") ?? (p as NSString).pathExtension.lowercased()
    }
}

public nonisolated struct WorkspaceEdit: Codable, Hashable, Sendable {
    public var oldText: String
    public var newText: String
    public var mode: String

    public init(oldText: String, newText: String, mode: String = "replace") {
        self.oldText = oldText
        self.newText = newText
        self.mode = mode
    }
}

public nonisolated struct WorkspaceFileOpenRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var path: String
    public var line: Int?
    public var column: Int?

    public init(id: UUID = UUID(), path: String, line: Int? = nil, column: Int? = nil) {
        self.id = id
        self.path = path
        self.line = line
        self.column = column
    }
}

public nonisolated struct InstructionFileDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var relativePath: String?
    public var title: String
    public var scope: String
    public var provider: String?
    public var exists: Bool
    public var isSymlink: Bool
    public var linkTarget: String?
    public var sizeBytes: Int64?

    public var id: String { path }

    public init(
        path: String,
        relativePath: String? = nil,
        title: String? = nil,
        scope: String = "project",
        provider: String? = nil,
        exists: Bool = true,
        isSymlink: Bool = false,
        linkTarget: String? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.path = path
        self.relativePath = relativePath
        self.title = title ?? (path as NSString).lastPathComponent
        self.scope = scope
        self.provider = provider
        self.exists = exists
        self.isSymlink = isSymlink
        self.linkTarget = linkTarget
        self.sizeBytes = sizeBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let p = c.string("path", "filePath") ?? ""
        self.path = p
        self.relativePath = c.string("relativePath")
        self.title = c.string("label", "title", "name") ?? (p as NSString).lastPathComponent
        self.scope = c.string("scope", "kind") ?? "project"
        self.provider = c.string("provider")
        self.exists = c.bool("exists", "isPresent") ?? true
        self.isSymlink = c.bool("isSymlink") ?? false
        self.linkTarget = c.string("linkTarget")
        self.sizeBytes = c.int64("byteLen", "sizeBytes", "size")
    }
}

// MARK: - Staged Attachments, Usage Report, Remote Server & CLI Session Import

public nonisolated struct StagedAttachment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var originalPath: String?
    public var mimeType: String
    public var sizeBytes: Int64
    public var width: Int?
    public var height: Int?
    public var dataBase64: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        path: String,
        originalPath: String? = nil,
        mimeType: String = "image/png",
        sizeBytes: Int64 = 0,
        width: Int? = nil,
        height: Int? = nil,
        dataBase64: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.originalPath = originalPath
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.width = width
        self.height = height
        self.dataBase64 = dataBase64
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let p = c.string("path", "stagedPath", "filePath") ?? ""
        self.id = c.string("id", "attachmentId", "attachmentID") ?? UUID().uuidString.lowercased()
        self.name = c.string("originalName", "name", "fileName", "filename") ?? (p as NSString).lastPathComponent
        self.path = p
        self.originalPath = c.string("originalPath")
        self.mimeType = c.string("mimeType", "originalMimeType", "mime_type", "contentType") ?? "image/png"
        self.sizeBytes = c.int64("byteLen", "originalByteLen", "sizeBytes", "size") ?? 0
        self.width = c.int("width")
        self.height = c.int("height")
        self.dataBase64 = c.string("dataBase64", "data", "base64")
    }
}

public nonisolated struct DesktopUsageTotals: Codable, Hashable, Sendable {
    public var inputTokens: Int64
    public var cacheReadTokens: Int64
    public var cacheWriteTokens: Int64
    public var outputTokens: Int64
    public var reasoningTokens: Int64
    public var totalTokens: Int64
    public var estimatedCostUSD: Double
    public var requests: Int64

    public init(
        inputTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        cacheWriteTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningTokens: Int64 = 0,
        totalTokens: Int64 = 0,
        estimatedCostUSD: Double = 0,
        requests: Int64 = 0
    ) {
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.requests = requests
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.inputTokens = c.int64("inputTokens") ?? 0
        self.cacheReadTokens = c.int64("cacheReadTokens") ?? 0
        self.cacheWriteTokens = c.int64("cacheWriteTokens") ?? 0
        self.outputTokens = c.int64("outputTokens") ?? 0
        self.reasoningTokens = c.int64("reasoningTokens") ?? 0
        self.totalTokens = c.int64("totalTokens") ?? 0
        self.estimatedCostUSD = c.double("estimatedCostUsd", "estimatedCostUSD", "cost") ?? 0
        self.requests = c.int64("requests") ?? 0
    }
}

public nonisolated struct DesktopUsageDailyRow: Codable, Hashable, Sendable, Identifiable {
    public var date: String
    public var dayMs: Int64
    public var provider: String
    public var totals: DesktopUsageTotals

    public var id: String { "\(date):\(provider)" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.date = c.string("date") ?? ""
        self.dayMs = c.int64("dayMs") ?? 0
        self.provider = c.string("provider") ?? ""
        self.totals = c.decodeValue(DesktopUsageTotals.self, keys: "totals") ?? DesktopUsageTotals()
    }
}

public nonisolated struct DesktopUsageModelRow: Codable, Hashable, Sendable, Identifiable {
    public var provider: String
    public var model: String
    public var totals: DesktopUsageTotals

    public var id: String { "\(provider):\(model)" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.provider = c.string("provider") ?? ""
        self.model = c.string("model") ?? "default"
        self.totals = c.decodeValue(DesktopUsageTotals.self, keys: "totals") ?? DesktopUsageTotals()
    }
}

public nonisolated struct DesktopUsageProjectRow: Codable, Hashable, Sendable, Identifiable {
    public var projectID: String
    public var projectName: String
    public var totals: DesktopUsageTotals

    public var id: String { projectID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.projectID = c.string("projectId", "projectID") ?? ""
        self.projectName = c.string("projectName", "name") ?? "Chats"
        self.totals = c.decodeValue(DesktopUsageTotals.self, keys: "totals") ?? DesktopUsageTotals()
    }
}

public nonisolated struct DesktopUsageReport: Codable, Hashable, Sendable {
    public var days: Int
    public var provider: String?
    public var accountID: String?
    public var today: DesktopUsageTotals
    public var lastWeek: DesktopUsageTotals
    public var lastMonth: DesktopUsageTotals
    public var period: DesktopUsageTotals
    public var daily: [DesktopUsageDailyRow]
    public var models: [DesktopUsageModelRow]
    public var projects: [DesktopUsageProjectRow]
    public var rateLimits: JSONValue

    public init(
        days: Int = 30,
        provider: String? = nil,
        accountID: String? = nil,
        today: DesktopUsageTotals = DesktopUsageTotals(),
        lastWeek: DesktopUsageTotals = DesktopUsageTotals(),
        lastMonth: DesktopUsageTotals = DesktopUsageTotals(),
        period: DesktopUsageTotals = DesktopUsageTotals(),
        daily: [DesktopUsageDailyRow] = [],
        models: [DesktopUsageModelRow] = [],
        projects: [DesktopUsageProjectRow] = [],
        rateLimits: JSONValue = .null
    ) {
        self.days = days
        self.provider = provider
        self.accountID = accountID
        self.today = today
        self.lastWeek = lastWeek
        self.lastMonth = lastMonth
        self.period = period
        self.daily = daily
        self.models = models
        self.projects = projects
        self.rateLimits = rateLimits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.days = c.int("days") ?? 30
        self.provider = c.string("provider")
        self.accountID = c.string("accountId", "accountID")
        self.today = c.decodeValue(DesktopUsageTotals.self, keys: "today") ?? DesktopUsageTotals()
        self.lastWeek = c.decodeValue(DesktopUsageTotals.self, keys: "lastWeek") ?? DesktopUsageTotals()
        self.lastMonth = c.decodeValue(DesktopUsageTotals.self, keys: "lastMonth") ?? DesktopUsageTotals()
        self.period = c.decodeValue(DesktopUsageTotals.self, keys: "period") ?? DesktopUsageTotals()
        self.daily = c.decodeValue([DesktopUsageDailyRow].self, keys: "daily") ?? []
        self.models = c.decodeValue([DesktopUsageModelRow].self, keys: "models") ?? []
        self.projects = c.decodeValue([DesktopUsageProjectRow].self, keys: "projects") ?? []
        self.rateLimits = c.decodeValue(JSONValue.self, keys: "rateLimits") ?? .null
    }
}

public nonisolated struct RemotePairedDeviceInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var pairedAt: Date?
    public var lastSeenAt: Date?
    public var isConnected: Bool

    public init(
        id: String,
        name: String,
        pairedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
        self.isConnected = isConnected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.string("id", "deviceID", "deviceId") ?? UUID().uuidString
        self.name = c.string("name", "deviceName") ?? "iPhone"
        self.pairedAt = c.date("pairedAt", "paired_at")
        self.lastSeenAt = c.date("lastSeenAt", "last_seen_at")
        self.isConnected = c.bool("isConnected", "connected", "online") ?? false
    }
}

public nonisolated struct RemotePairingQRInfo: Codable, Hashable, Sendable {
    public var uri: String
    public var qrMatrix: [String]?
    public var fingerprint: String?
    public var displayFingerprint: String?
    public var serverID: String?
    public var name: String?
    public var port: Int?
    public var expiresAt: Date?

    public init(
        uri: String,
        qrMatrix: [String]? = nil,
        fingerprint: String? = nil,
        displayFingerprint: String? = nil,
        serverID: String? = nil,
        name: String? = nil,
        port: Int? = nil,
        expiresAt: Date? = nil
    ) {
        self.uri = uri
        self.qrMatrix = qrMatrix
        self.fingerprint = fingerprint
        self.displayFingerprint = displayFingerprint
        self.serverID = serverID
        self.name = name
        self.port = port
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.uri = c.string("uri", "qrPayload", "url", "code", "payload") ?? ""
        self.qrMatrix = c.decodeValue([String].self, keys: "qrMatrix")
        self.fingerprint = c.string("fingerprint")
        self.displayFingerprint = c.string("displayFingerprint")
        self.serverID = c.string("serverId", "serverID")
        self.name = c.string("name")
        self.port = c.int("port")
        self.expiresAt = c.date("expiresAt", "expires_at")
    }
}

public nonisolated struct RemoteServerSnapshot: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var status: String
    public var port: Int?
    public var serverID: String?
    public var serverName: String?
    public var fingerprint: String?
    public var displayFingerprint: String?
    public var addresses: [String]
    public var devices: [RemotePairedDeviceInfo]
    public var pairing: RemotePairingQRInfo?
    public var errorMessage: String?

    public init(
        enabled: Bool = false,
        status: String = "off",
        port: Int? = nil,
        serverID: String? = nil,
        serverName: String? = nil,
        fingerprint: String? = nil,
        displayFingerprint: String? = nil,
        addresses: [String] = [],
        devices: [RemotePairedDeviceInfo] = [],
        pairing: RemotePairingQRInfo? = nil,
        errorMessage: String? = nil
    ) {
        self.enabled = enabled
        self.status = status
        self.port = port
        self.serverID = serverID
        self.serverName = serverName
        self.fingerprint = fingerprint
        self.displayFingerprint = displayFingerprint
        self.addresses = addresses
        self.devices = devices
        self.pairing = pairing
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.enabled = c.bool("enabled", "isEnabled") ?? false
        self.status = c.string("status", "state") ?? (self.enabled ? "running" : "off")
        self.port = c.int("port")
        self.serverID = c.string("serverID", "serverId")
        self.serverName = c.string("serverName", "name")
        self.fingerprint = c.string("fingerprint")
        self.displayFingerprint = c.string("displayFingerprint")
        if let addrs = c.decodeValue([String].self, keys: "addresses", "hosts") {
            self.addresses = addrs
        } else if let candidates = c.decodeValue([JSONValue].self, keys: "candidates") {
            self.addresses = candidates.compactMap { $0["host"]?.stringValue ?? $0.stringValue }
        } else {
            self.addresses = []
        }

        let connectedIDs = Set(c.decodeValue([String].self, keys: "connectedDeviceIds", "connected", "connectedDeviceIDs") ?? [])
        let rawDevices = c.decodeValue([RemotePairedDeviceInfo].self, keys: "devices", "pairedDevices") ?? []
        self.devices = rawDevices.map { dev in
            var copy = dev
            if connectedIDs.contains(copy.id) { copy.isConnected = true }
            return copy
        }
        self.pairing = c.decodeValue(RemotePairingQRInfo.self, keys: "pairing", "pairingQR")
        self.errorMessage = c.string("error", "errorMessage", "storageError")
    }
}

public nonisolated struct LegacyImportReport: Codable, Hashable, Sendable {
    public var importedProjects: Int
    public var importedBots: Int
    public var importedThreads: Int
    public var skippedThreads: Int

    public init(
        importedProjects: Int = 0,
        importedBots: Int = 0,
        importedThreads: Int = 0,
        skippedThreads: Int = 0
    ) {
        self.importedProjects = importedProjects
        self.importedBots = importedBots
        self.importedThreads = importedThreads
        self.skippedThreads = skippedThreads
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.importedProjects = c.int("importedProjects") ?? 0
        self.importedBots = c.int("importedBots") ?? 0
        self.importedThreads = c.int("importedThreads") ?? 0
        self.skippedThreads = c.int("skippedThreads") ?? 0
    }
}

public nonisolated struct CLISessionSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var title: String
    public var path: String
    public var cwd: String?
    public var updatedAt: Date?
    public var messageCount: Int
    public var alreadyImported: Bool

    public init(
        id: String,
        provider: String,
        title: String,
        path: String,
        cwd: String? = nil,
        updatedAt: Date? = nil,
        messageCount: Int = 0,
        alreadyImported: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.path = path
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.alreadyImported = alreadyImported
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let p = c.string("path", "sourcePath", "filePath") ?? ""
        self.id = c.string("id", "sessionId", "sessionID") ?? p
        self.provider = c.string("provider") ?? "codex"
        self.title = c.string("title", "summary", "firstPrompt") ?? (p as NSString).lastPathComponent
        self.path = p
        self.cwd = c.string("cwd", "directory", "workingDirectory")
        self.updatedAt = c.date("updatedAt", "modifiedAt", "timestamp")
        self.messageCount = c.int("messageCount", "messages", "turns") ?? 0
        self.alreadyImported = c.bool("alreadyImported", "imported", "existing") ?? false
    }
}

// MARK: - Navigation Tabs, Diff Scope & Toast

public nonisolated enum InspectorTab: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case changes
    case git
    case pullRequests
    case files
    case schedules
    case workers
    case assistants
    case computerUse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .changes: "Changes"
        case .git: "Git"
        case .pullRequests: "Pull Requests"
        case .files: "Files"
        case .schedules: "Schedules"
        case .workers: "Workers"
        case .assistants: "Assistants"
        case .computerUse: "Computer Use"
        }
    }

    public var symbolName: String {
        switch self {
        case .changes: "plusminus"
        case .git: "point.3.connected.trianglepath.dotted"
        case .pullRequests: "arrow.triangle.pull"
        case .files: "folder"
        case .schedules: "calendar.badge.clock"
        case .workers: "person.2"
        case .assistants: "sparkles"
        case .computerUse: "cursorarrow"
        }
    }
}

public nonisolated enum SettingsTab: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case general
    case antigravity
    case providers
    case models
    case instructions
    case memory
    case usage
    case voice
    case remote
    case computerUse
    case assistants
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .antigravity: "Antigravity"
        case .providers: "Providers"
        case .models: "Models"
        case .instructions: "Instructions"
        case .memory: "Memory"
        case .usage: "Usage"
        case .voice: "Voice"
        case .remote: "Remote"
        case .computerUse: "Computer Use"
        case .assistants: "Assistants"
        case .about: "About"
        }
    }

    public var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .antigravity: "sparkles"
        case .providers: "cpu"
        case .models: "slider.horizontal.3"
        case .instructions: "doc.text"
        case .memory: "memorychip"
        case .usage: "chart.bar.xaxis"
        case .voice: "waveform.and.mic"
        case .remote: "iphone.radiowaves.left.and.right"
        case .computerUse: "cursorarrow"
        case .assistants: "person.2"
        case .about: "info.circle"
        }
    }
}

public struct SettingsTabGroup: Hashable, Sendable {
    public let title: String
    public let tabs: [SettingsTab]

    public init(title: String, tabs: [SettingsTab]) {
        self.title = title
        self.tabs = tabs
    }
}

extension SettingsTab {
    public static let groups: [SettingsTabGroup] = [
        SettingsTabGroup(title: "Workspace", tabs: [.general, .instructions, .memory, .assistants]),
        SettingsTabGroup(title: "Providers & Models", tabs: [.antigravity, .providers, .models]),
        SettingsTabGroup(title: "System", tabs: [.computerUse, .voice, .remote, .usage, .about]),
    ]

    public var searchKeywords: [String] {
        switch self {
        case .general:
            ["appearance", "theme", "font", "serif", "toolset", "system tools", "editor", "terminal", "storage", "workspace", "data", "migration"]
        case .antigravity:
            ["gemini", "google", "api key", "keychain", "acp", "runtime", "account", "binary"]
        case .providers:
            ["agents", "claude", "codex", "cursor", "grok", "opencode", "lithos", "acp", "registry", "api key", "keychain", "login", "executable", "auth", "environment"]
        case .models:
            ["catalog", "default", "favorite", "hidden", "custom model", "reasoning", "vision"]
        case .instructions:
            ["agents.md", "claude.md", "gemini.md", "cursorrules", "project", "editor"]
        case .memory:
            ["entries", "clear", "scope", "global"]
        case .computerUse:
            ["computer use", "accessibility", "screen recording", "permissions", "screenshots", "click", "type"]
        case .assistants:
            ["notifications", "automation", "scheduled", "tasks", "runs"]
        case .usage:
            ["tokens", "cost", "rate limit", "spend"]
        case .voice:
            ["dictation", "microphone", "speech", "transcription", "locale"]
        case .remote:
            ["connect", "iphone", "ipad", "pair", "qr", "tls", "certificate", "devices"]
        case .about:
            ["version", "links", "license", "changelog", "github"]
        }
    }

    public func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return true
        }
        let haystack = ([title] + searchKeywords).joined(separator: " ").lowercased()
        return trimmed.split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

public nonisolated enum DiffScope: Codable, Hashable, Sendable {
    case uncommitted
    case turn(UUID)
    case branch
    case compare(from: String, to: String)

    public var turnID: UUID? {
        switch self {
        case .uncommitted: nil
        case .turn(let id): id
        case .branch: nil
        case .compare: nil
        }
    }
}

public nonisolated struct ToastMessage: Codable, Hashable, Sendable, Identifiable {
    public enum Style: String, Codable, Hashable, Sendable {
        case info
        case success
        case warning
        case error
    }

    public var id: UUID
    public var title: String
    public var detail: String?
    public var style: Style
    public var undoActionTitle: String?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        style: Style = .info,
        undoActionTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.style = style
        self.undoActionTitle = undoActionTitle
    }
}
