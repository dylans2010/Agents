@preconcurrency import AVFAudio
import CoreAudio
import Foundation
import Observation
@preconcurrency import Speech

// MARK: - CoreAudio Input Device Enumeration

public nonisolated struct MicrophoneDevice: Hashable, Sendable, Identifiable {
    public let deviceID: AudioDeviceID
    public let uid: String
    public let name: String

    public var id: String { uid }

    public init(deviceID: AudioDeviceID, uid: String, name: String) {
        self.deviceID = deviceID
        self.uid = uid
        self.name = name
    }
}

public nonisolated enum VoiceMicrophoneDevices {
    public static func all() -> [MicrophoneDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }

        return ids.compactMap { id in
            guard hasInputChannels(id),
                  let uid = copyStringProperty(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = copyStringProperty(id, selector: kAudioObjectPropertyName)
            else {
                return nil
            }
            return MicrophoneDevice(deviceID: id, uid: uid, name: name)
        }
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func copyStringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value
        else {
            return nil
        }
        return value.takeRetainedValue() as String
    }
}

// MARK: - Smart UTF-16 Dictation Insertion

public nonisolated struct DictationInsertion: Equatable, Sendable {
    public private(set) var range: NSRange
    public private(set) var inserted: String = ""
    private let before: unichar?
    private let after: unichar?

    public init(text: String, selection: NSRange) {
        let string = text as NSString
        let location = min(max(0, selection.location), string.length)
        let length = min(max(0, selection.length), string.length - location)
        self.range = NSRange(location: location, length: length)
        self.before = location > 0 ? string.character(at: location - 1) : nil
        self.after = location + length < string.length ? string.character(at: location + length) : nil
    }

    public mutating func update(_ transcript: String) -> (range: NSRange, replacement: String)? {
        let replacement = spaced(transcript)
        guard replacement != inserted else { return nil }
        let edit = (range: range, replacement: replacement)
        inserted = replacement
        range = NSRange(location: range.location, length: (replacement as NSString).length)
        return edit
    }

    public var caret: NSRange {
        NSRange(location: range.location + range.length, length: 0)
    }

    public func spaced(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var result = trimmed
        if let before, !Self.isSpace(before) {
            result = " " + result
        }
        if let after, !Self.isSpace(after), !Self.isClosingPunctuation(after) {
            result += " "
        }
        return result
    }

    private static func isSpace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isClosingPunctuation(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet(charactersIn: ".,;:!?)]}”’'\"…").contains(scalar)
    }
}

// MARK: - Nonisolated AVAudioEngine Capture

nonisolated final class VoiceAudioCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noInput
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone input is available."
            case .unsupportedFormat: "The microphone’s audio format isn’t supported."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false

    func start(
        deviceUID: String?,
        format: AVAudioFormat,
        sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        level: @escaping @Sendable (Float) -> Void
    ) throws {
        stop()
        let input = engine.inputNode
        if let deviceUID,
           let device = VoiceMicrophoneDevices.all().first(where: { $0.uid == deviceUID }),
           let audioUnit = input.audioUnit
        {
            var id = device.deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.noInput
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw CaptureError.unsupportedFormat
        }
        let ratio = format.sampleRate / inputFormat.sampleRate

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            level(Self.rmsLevel(of: buffer))
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                return
            }
            nonisolated(unsafe) var supplied = false
            var convError: NSError?
            converter.convert(to: converted, error: &convError) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if convError == nil, converted.frameLength > 0 {
                sink(converted)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        lock.withLock { running = true }
    }

    func stop() {
        let wasRunning = lock.withLock {
            defer { running = false }
            return running
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for index in 0..<count {
            sum += channel[index] * channel[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, (decibels + 50) / 50))
    }
}

// MARK: - Nonisolated On-Device Apple Speech Recognizer

nonisolated final class MacAppleSpeechEngine: @unchecked Sendable {
    enum Failure: LocalizedError, Equatable {
        case languageUnavailable(String)
        case notAuthorized
        case unavailable

        var errorDescription: String? {
            switch self {
            case .languageUnavailable(let language):
                "On-device speech recognition isn’t available for \(language)."
            case .notAuthorized:
                "Speech recognition isn’t allowed. Enable it in System Settings › Privacy & Security › Speech Recognition."
            case .unavailable:
                "Speech recognition isn’t available right now."
            }
        }
    }

    let locale: Locale
    private let lock = NSLock()

    // SpeechAnalyzer (macOS 26+)
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Error>?

    // SFSpeechRecognizer fallback
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var fallbackDone: CheckedContinuation<String, Error>?
    private var fallbackEnded = false

    private var finalized = ""
    private var volatile = ""

    init(locale: Locale) {
        self.locale = locale
    }

    private var languageName: String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        {
            let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let watcher = Task {
                    while !Task.isCancelled {
                        progress(installation.progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { watcher.cancel() }
                try await installation.downloadAndInstall()
                progress(1.0)
            }
            lock.withLock { self.transcriber = transcriber }
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw Failure.languageUnavailable(languageName)
        }
        guard await Self.requestSpeechAuthorization() else {
            throw Failure.notAuthorized
        }
        guard recognizer.isAvailable else {
            throw Failure.unavailable
        }
        lock.withLock { self.recognizer = recognizer }
    }

    static func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    func preferredAudioFormat() async -> AVAudioFormat? {
        if let transcriber = lock.withLock({ self.transcriber }) {
            return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    func begin(partial: @escaping @Sendable (String) -> Void) async throws {
        lock.withLock {
            finalized = ""
            volatile = ""
            fallbackEnded = false
        }

        if let transcriber = lock.withLock({ self.transcriber }) {
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let results = Task { [weak self] in
                for try await result in transcriber.results {
                    guard let self else { return }
                    let chunk = String(result.text.characters)
                    let combined = self.lock.withLock {
                        if result.isFinal {
                            self.finalized += chunk
                            self.volatile = ""
                        } else {
                            self.volatile = chunk
                        }
                        return self.finalized + self.volatile
                    }
                    partial(combined)
                }
            }
            lock.withLock {
                self.analyzer = analyzer
                self.inputContinuation = continuation
                self.resultsTask = results
            }
            try await analyzer.start(inputSequence: stream)
            return
        }

        guard let recognizer = lock.withLock({ self.recognizer }) else {
            throw Failure.unavailable
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        let task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.lock.withLock { self.finalized = text }
                partial(text)
                if result.isFinal { self.finishFallback() }
            } else if error != nil {
                self.finishFallback()
            }
        }
        lock.withLock {
            self.request = req
            self.recognitionTask = task
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let (input, req) = lock.withLock { (self.inputContinuation, self.request) }
        if let input {
            input.yield(AnalyzerInput(buffer: buffer))
        } else {
            req?.append(buffer)
        }
    }

    func finish() async throws -> String {
        let (analyzer, input, results, req) = lock.withLock {
            (self.analyzer, self.inputContinuation, self.resultsTask, self.request)
        }
        if let analyzer {
            input?.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            _ = try? await results?.value
            return lock.withLock {
                defer { resetLocked() }
                return finalized + volatile
            }
        }
        guard let req else { return "" }
        let finalTranscript = try await withCheckedThrowingContinuation { continuation in
            let existing: String? = lock.withLock {
                guard !fallbackEnded else { return finalized }
                fallbackDone = continuation
                return nil
            }
            if let existing {
                continuation.resume(returning: existing)
            }
            req.endAudio()
        }
        lock.withLock { resetLocked() }
        return finalTranscript
    }

    func cancel() async {
        let (analyzer, input, results, task) = lock.withLock {
            (self.analyzer, self.inputContinuation, self.resultsTask, self.recognitionTask)
        }
        input?.finish()
        results?.cancel()
        task?.cancel()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        lock.withLock { finalized = "" }
        finishFallback()
        lock.withLock { resetLocked() }
    }

    private func finishFallback() {
        let (cont, text) = lock.withLock {
            fallbackEnded = true
            defer { fallbackDone = nil }
            return (fallbackDone, finalized)
        }
        cont?.resume(returning: text)
    }

    private func resetLocked() {
        analyzer = nil
        inputContinuation = nil
        resultsTask = nil
        request = nil
        recognitionTask = nil
        fallbackDone = nil
    }
}

// MARK: - MainActor Observable Voice Dictation Controller

@Observable
@MainActor
public final class VoiceDictationController {
    public private(set) var isRecording: Bool = false
    public private(set) var isPreparing: Bool = false
    public private(set) var downloadProgress: Double? = nil
    public private(set) var audioLevel: Float = 0
    public private(set) var partialTranscript: String = ""
    public private(set) var availableMicrophones: [MicrophoneDevice] = []
    public var lastError: String? = nil

    public var selectedMicrophoneUID: String? {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneUID, forKey: Self.micDefaultsKey)
        }
    }

    public var selectedLocaleIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedLocaleIdentifier, forKey: Self.localeDefaultsKey)
        }
    }

    private static let micDefaultsKey = "coincide.voice.microphoneUID"
    private static let localeDefaultsKey = "coincide.voice.localeIdentifier"

    @ObservationIgnored private let audioCapture = VoiceAudioCapture()
    @ObservationIgnored private var speechEngine: MacAppleSpeechEngine?

    public init() {
        self.selectedMicrophoneUID = UserDefaults.standard.string(forKey: Self.micDefaultsKey)
        self.selectedLocaleIdentifier = UserDefaults.standard.string(forKey: Self.localeDefaultsKey)
            ?? Locale.current.identifier
        self.availableMicrophones = VoiceMicrophoneDevices.all()
    }

    public func refreshMicrophones() {
        availableMicrophones = VoiceMicrophoneDevices.all()
        if let uid = selectedMicrophoneUID,
           !availableMicrophones.contains(where: { $0.uid == uid })
        {
            selectedMicrophoneUID = nil
        }
    }

    public static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    public func startRecording(
        onTranscriptUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async {
        guard !isRecording, !isPreparing else { return }
        lastError = nil
        partialTranscript = ""
        audioLevel = 0
        isPreparing = true
        downloadProgress = nil

        guard await Self.requestMicrophonePermission() else {
            isPreparing = false
            lastError = "Microphone access isn’t allowed. Enable it in System Settings › Privacy & Security › Microphone."
            return
        }

        let locale = Locale(identifier: selectedLocaleIdentifier)
        let engine = MacAppleSpeechEngine(locale: locale)
        self.speechEngine = engine

        do {
            try await engine.prepare { [weak self] fraction in
                Task { @MainActor in
                    self?.downloadProgress = fraction < 1.0 ? fraction : nil
                }
            }
            guard let format = await engine.preferredAudioFormat() else {
                throw MacAppleSpeechEngine.Failure.unavailable
            }
            try await engine.begin { [weak self] transcript in
                Task { @MainActor in
                    self?.partialTranscript = transcript
                    onTranscriptUpdate?(transcript)
                }
            }
            try audioCapture.start(
                deviceUID: selectedMicrophoneUID,
                format: format,
                sink: { buffer in
                    engine.append(buffer)
                },
                level: { [weak self] rms in
                    Task { @MainActor in
                        self?.audioLevel = rms
                    }
                }
            )
            isPreparing = false
            downloadProgress = nil
            isRecording = true
        } catch {
            audioCapture.stop()
            await engine.cancel()
            self.speechEngine = nil
            isPreparing = false
            downloadProgress = nil
            isRecording = false
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    public func stopRecording() async -> String {
        guard isRecording || isPreparing else { return "" }
        audioCapture.stop()
        isRecording = false
        isPreparing = false
        audioLevel = 0
        downloadProgress = nil

        guard let engine = speechEngine else { return partialTranscript }
        speechEngine = nil
        do {
            let final = try await engine.finish()
            let resolved = final.isEmpty ? partialTranscript : final
            partialTranscript = resolved
            return resolved
        } catch {
            lastError = error.localizedDescription
            return partialTranscript
        }
    }

    public func cancelRecording() async {
        audioCapture.stop()
        if let engine = speechEngine {
            speechEngine = nil
            await engine.cancel()
        }
        isRecording = false
        isPreparing = false
        audioLevel = 0
        downloadProgress = nil
        partialTranscript = ""
    }
}
