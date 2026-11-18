import SwiftUI

public struct AssistantLibraryRow: View {
    public let definition: AssistantDefinition
    public let isFavorite: Bool
    public let onToggleFavorite: () -> Void

    public init(
        definition: AssistantDefinition,
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.definition = definition
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: definition.icon.isEmpty ? "sparkles" : definition.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 30, height: 30)
                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(definition.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    if definition.customized {
                        Text("Customized")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.warning.opacity(0.12), in: Capsule())
                    } else if !definition.isBuiltIn {
                        Text("Custom")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.info)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.info.opacity(0.12), in: Capsule())
                    }
                }

                if !definition.description.isEmpty {
                    Text(definition.description)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                }

                Text(definition.category.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isFavorite ? AppTheme.favoriteStar : AppTheme.quaternaryLabel)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(isFavorite ? "Remove \(definition.name) from favorites" : "Add \(definition.name) to favorites")
        }
        .padding(.vertical, 3)
    }
}
