import AppKit
import CoincideRemoteKit
@preconcurrency import Speech
import SwiftUI

public struct VoiceSettingsPane: View {
    @Bindable public var appModel: AppModel

    @State private var supportedLocales: [LocaleOption] = []
    @State private var testPreviewTranscript: String = ""

    private struct LocaleOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var dictation: VoiceDictationController {
        appModel.voiceDictation
    }

    private var approximateDecibelsText: String {
        guard dictation.isRecording else { return "Idle" }
        let normalized = Double(max(0, min(1, dictation.audioLevel)))
        let db = Int((normalized * 50.0 - 50.0).rounded())
        return "\(db) dB"
    }

    public var body: some View {
        Form {
            inputHardwareSection
            speechLocaleSection
            liveTestDictationSection
        }
        .formStyle(.grouped)
        .navigationTitle("Voice")
        .onAppear {
            dictation.refreshMicrophones()
            loadSupportedSpeechLocales()
        }
        .onDisappear {
            if dictation.isRecording || dictation.isPreparing {
                Task { await dictation.cancelRecording() }
            }
        }
    }

    // MARK: - 1. Input Microphone & Live Meter

    private var inputHardwareSection: some View {
        Section {
            HStack(spacing: 10) {
                Picker(
                    "Input Microphone",
                    selection: Binding(
                        get: { dictation.selectedMicrophoneUID ?? "__system_default__" },
                        set: { newVal in
                            dictation.selectedMicrophoneUID = (newVal == "__system_default__") ? nil : newVal
                        }
                    )
                ) {
                    Text("System Default Input").tag("__system_default__")
                    ForEach(dictation.availableMicrophones) { mic in
                        Text(mic.name).tag(mic.uid)
                    }
                }

                Button {
                    dictation.refreshMicrophones()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            LabeledContent("Input Level") {
                HStack(spacing: 10) {
                    ProgressView(value: Double(dictation.audioLevel), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(dictation.audioLevel > 0.8 ? AppTheme.warning : AppTheme.success)
                        .frame(width: 220)

                    Text(approximateDecibelsText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        } header: {
            Text("Audio Input")
        } footer: {
            Text("Coincide captures microphone audio only while dictation is active and processes speech 100% on-device on this Mac.")
        }
    }

    // MARK: - 2. Speech Recognition Locale

    private var speechLocaleSection: some View {
        Section {
            Picker(
                "Speech Locale",
                selection: Binding(
                    get: { dictation.selectedLocaleIdentifier },
                    set: { dictation.selectedLocaleIdentifier = $0 }
                )
            ) {
                ForEach(supportedLocales) { option in
                    Text(option.title).tag(option.id)
                }
            }

            if let progress = dictation.downloadProgress {
                LabeledContent("Downloading Speech Assets") {
                    HStack(spacing: 8) {
                        ProgressView(value: progress, total: 1.0)
                            .frame(width: 180)
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
        } header: {
            Text("On-Device Apple Speech")
        } footer: {
            Text("Uses macOS SpeechAnalyzer with automatic SFSpeechRecognizer on-device fallback—no audio ever leaves your Mac.")
        }
    }

    // MARK: - 3. Test Dictation Preview

    private var liveTestDictationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await toggleTestDictation() }
                    } label: {
                        HStack(spacing: 6) {
                            if dictation.isPreparing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                                    .foregroundStyle(dictation.isRecording ? AppTheme.danger : .primary)
                            }
                            Text(
                                dictation.isPreparing
                                    ? "Preparing Speech Engine…"
                                    : (dictation.isRecording ? "Stop Test Dictation" : "Start Test Dictation")
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(dictation.isRecording ? AppTheme.danger : AppTheme.accent)
                    .disabled(dictation.isPreparing)

                    if !testPreviewTranscript.isEmpty || !dictation.partialTranscript.isEmpty {
                        Button("Clear") {
                            testPreviewTranscript = ""
                        }
                        .controlSize(.small)
                    }

                    Spacer()

                    if dictation.isRecording {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppTheme.danger)
                                .frame(width: 7, height: 7)
                            Text("Listening…")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }
                }

                let displayedText = dictation.isRecording
                    ? (dictation.partialTranscript.isEmpty ? testPreviewTranscript : dictation.partialTranscript)
                    : (testPreviewTranscript.isEmpty ? dictation.partialTranscript : testPreviewTranscript)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(AppTheme.textBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .strokeBorder(
                                    dictation.isRecording ? AppTheme.accent : AppTheme.separator,
                                    lineWidth: 1
                                )
                        )

                    if displayedText.isEmpty {
                        Text("Click “Start Test Dictation” and speak into your microphone to preview live transcription…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .padding(10)
                    } else {
                        Text(displayedText)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
                .frame(minHeight: 88)

                if let err = dictation.lastError, !err.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                        Text(err)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Live Dictation Test")
        }
    }

    // MARK: - Helpers

    private func toggleTestDictation() async {
        if dictation.isRecording || dictation.isPreparing {
            let finalText = await dictation.stopRecording()
            if !finalText.isEmpty {
                testPreviewTranscript = finalText
            }
        } else {
            testPreviewTranscript = ""
            await dictation.startRecording { partial in
                testPreviewTranscript = partial
            }
        }
    }

    private func loadSupportedSpeechLocales() {
        let rawLocales = SFSpeechRecognizer.supportedLocales()
        var options: [LocaleOption] = rawLocales.map { loc in
            let id = loc.identifier
            let localized = Locale.current.localizedString(forIdentifier: id) ?? id
            return LocaleOption(id: id, title: "\(localized) (\(id))")
        }
        let currentID = dictation.selectedLocaleIdentifier
        if !options.contains(where: { $0.id == currentID }) {
            let name = Locale.current.localizedString(forIdentifier: currentID) ?? currentID
            options.append(LocaleOption(id: currentID, title: "\(name) (\(currentID))"))
        }
        options.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        self.supportedLocales = options
    }
}
