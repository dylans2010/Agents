import SwiftUI

public struct AssistantPromptEditorView: View {
    @Binding public var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    private static let guidance: [(symbol: String, suggestion: String)] = [
        (symbol: "1.circle", suggestion: "State the assistant's job in one sentence first, then the rules it must follow."),
        (symbol: "2.circle", suggestion: "Name the tools it should reach for and the ones it must leave alone."),
        (symbol: "3.circle", suggestion: "Say how it should report back: format, length, and what to include."),
        (symbol: "4.circle", suggestion: "Write hard rules as plain sentences. The assistant follows them as written."),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.guidance, id: \.suggestion) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 1)
                        Text(item.suggestion)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("These are suggestions only. Nothing here is added to the prompt unless you type it.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            TextEditor(text: $text)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(minHeight: 140, maxHeight: 220)
                .padding(6)
                .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )

            HStack {
                Text("System prompt")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
                Text("\(text.utf8.count)/\(AssistantDefinition.systemPromptLimit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(
                        text.utf8.count > AssistantDefinition.systemPromptLimit
                            ? AppTheme.danger : AppTheme.tertiaryLabel
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Stored exactly as typed")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                Text("The text below is the exact system prompt that will be saved. Nothing is added, removed, or reworded.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                ScrollView {
                    Text(text.isEmpty ? "Nothing typed yet." : text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(text.isEmpty ? AppTheme.tertiaryLabel : AppTheme.primaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 64, maxHeight: 140)
                .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )
            }
        }
    }
}
