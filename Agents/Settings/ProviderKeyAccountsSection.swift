import AppKit
import CoincideRemoteKit
import SwiftUI

public struct ProviderKeyAccountsSection: View {
    @Bindable public var appModel: AppModel
    public let provider: DesktopProviderInfo
    public let title: String
    public let addTitle: String
    public let addButtonTitle: String
    public let emptyText: String
    public let footer: String?
    public let defaultAccountName: String
    public let fixedKeyVariable: String?
    public let addAccount: (String, String, String) async -> String?

    @State private var newAccountName: String
    @State private var newKeyEnvName: String
    @State private var newKeySecret: String = ""
    @State private var isAddingKey: Bool = false
    @State private var renamingAccount: ProviderKeyAccountInfo?
    @State private var renameText: String = ""
    @State private var updatingKeyAccount: ProviderKeyAccountInfo?
    @State private var updatedSecretText: String = ""

    public init(
        appModel: AppModel,
        provider: DesktopProviderInfo,
        title: String,
        addTitle: String,
        addButtonTitle: String,
        emptyText: String,
        footer: String?,
        defaultAccountName: String,
        fixedKeyVariable: String?,
        addAccount: @escaping (String, String, String) async -> String?
    ) {
        self.appModel = appModel
        self.provider = provider
        self.title = title
        self.addTitle = addTitle
        self.addButtonTitle = addButtonTitle
        self.emptyText = emptyText
        self.footer = footer
        self.defaultAccountName = defaultAccountName
        self.fixedKeyVariable = fixedKeyVariable
        self.addAccount = addAccount
        self._newAccountName = State(initialValue: defaultAccountName)
        self._newKeyEnvName = State(
            initialValue: Self.resolvedKeyVariable(fixed: fixedKeyVariable, provider: provider, selectedChoice: "")
        )
    }

    public static func resolvedKeyVariable(fixed: String?, provider: DesktopProviderInfo, selectedChoice: String) -> String {
        if let fixed, !fixed.isEmpty {
            return fixed
        }
        if !selectedChoice.isEmpty {
            return selectedChoice
        }
        return provider.keyChoices.first?.envName
            ?? provider.defaultKeyVariable
            ?? DesktopProviderInfo.inferredKeyVariable(for: provider.id)
            ?? "API_KEY"
    }

    private var resolvedKeyVariable: String {
        Self.resolvedKeyVariable(fixed: fixedKeyVariable, provider: provider, selectedChoice: newKeyEnvName)
    }

    public var body: some View {
        Section {
            if provider.keyAccounts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "key.slash")
                        .foregroundStyle(AppTheme.warning)
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(provider.keyAccounts) { account in
                    accountRow(account)
                }
            }

            addForm
        } header: {
            Text(title)
        } footer: {
            if let footer, !footer.isEmpty {
                Text(footer)
            }
        }
        .onChange(of: provider.id) { _, _ in
            newKeyEnvName = Self.resolvedKeyVariable(fixed: fixedKeyVariable, provider: provider, selectedChoice: "")
        }
        .sheet(item: $renamingAccount) { account in
            renameSheet(account)
        }
        .sheet(item: $updatingKeyAccount) { account in
            updateSheet(account)
        }
    }

    private func accountRow(_ account: ProviderKeyAccountInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: account.hasKey ? "key.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(account.hasKey ? AppTheme.success : AppTheme.warning)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.system(size: 13, weight: .medium))

                    Text(account.hasKey ? "macOS Keychain" : "Missing Key")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(account.hasKey ? AppTheme.success : AppTheme.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill((account.hasKey ? AppTheme.success : AppTheme.danger).opacity(0.14))
                        )
                }

                if let envVar = account.keyVariable ?? fixedKeyVariable {
                    Text(envVar)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }

            Spacer()

            Button("Rename") {
                renameText = account.name
                renamingAccount = account
            }
            .controlSize(.small)

            Button("Update Key…") {
                updatedSecretText = ""
                updatingKeyAccount = account
            }
            .controlSize(.small)

            Button(role: .destructive) {
                Task { await deleteAccount(account) }
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .help("Delete Keychain Account")
            .accessibilityLabel("Delete API key account \(account.name)")
        }
        .padding(.vertical, 2)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(addTitle)
                .font(.system(size: 12.5, weight: .semibold))

            HStack(spacing: 10) {
                TextField("Account Name", text: $newAccountName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

                if fixedKeyVariable == nil && provider.keyChoices.count > 1 {
                    Picker("", selection: $newKeyEnvName) {
                        ForEach(provider.keyChoices) { choice in
                            Text(choice.envName).tag(choice.envName)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("API key environment variable")
                    .frame(minWidth: 140, idealWidth: 170, maxWidth: 210)
                }

                SecureField("Paste \(resolvedKeyVariable)…", text: $newKeySecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button {
                    Task { await add() }
                } label: {
                    HStack(spacing: 6) {
                        if isAddingKey {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(addButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    newKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isAddingKey
                )
            }
        }
        .padding(.top, 6)
    }

    private func renameSheet(_ account: ProviderKeyAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename API Key Account")
                .font(.headline)

            TextField("Account Name", text: $renameText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    renamingAccount = nil
                }
                Button("Save") {
                    let target = account
                    let updatedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    renamingAccount = nil
                    Task { await renameAccount(target, to: updatedName) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)
    }

    private func updateSheet(_ account: ProviderKeyAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update API Key — \(account.name)")
                .font(.headline)

            SecureField("Paste new API key…", text: $updatedSecretText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack {
                Spacer()
                Button("Cancel") {
                    updatedSecretText = ""
                    updatingKeyAccount = nil
                }
                Button("Update Key") {
                    let target = account
                    let secret = updatedSecretText.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatedSecretText = ""
                    updatingKeyAccount = nil
                    Task { await updateAccountKey(target, newKey: secret) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updatedSecretText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 460)
    }

    private func add() async {
        let name = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = newKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isAddingKey = true
        defer { isAddingKey = false }
        let nextName = await addAccount(name.isEmpty ? defaultAccountName : name, key, resolvedKeyVariable)
        newKeySecret = ""
        if let nextName, !nextName.isEmpty {
            newAccountName = nextName
        }
    }

    private func renameAccount(_ account: ProviderKeyAccountInfo, to newName: String) async {
        guard let runtime = appModel.runtime, !newName.isEmpty else { return }
        do {
            _ = try await runtime.renameProviderKeyAccount(
                provider: provider.id,
                accountID: account.id,
                name: newName
            )
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            appModel.presentToast("Account Renamed", detail: newName, style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func updateAccountKey(_ account: ProviderKeyAccountInfo, newKey: String) async {
        guard let runtime = appModel.runtime, !newKey.isEmpty else { return }
        do {
            _ = try await runtime.updateProviderAccountKey(
                provider: provider.id,
                accountID: account.id,
                apiKey: newKey
            )
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            appModel.presentToast("Keychain Secret Updated", detail: account.name, style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func deleteAccount(_ account: ProviderKeyAccountInfo) async {
        guard let runtime = appModel.runtime else { return }
        do {
            try await runtime.deleteProviderAccount(provider: provider.id, accountID: account.id)
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            appModel.presentToast("Account Deleted", detail: account.name, style: .info)
        } catch {
            appModel.presentError(error)
        }
    }
}
