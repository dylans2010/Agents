import AppKit
import CoincideRemoteKit
import CoreImage
import SwiftUI

public struct RemoteSettingsPane: View {
    @Bindable public var appModel: AppModel

    @State private var isTogglingServer: Bool = false
    @State private var isPairingBusy: Bool = false
    @State private var showResetIdentityConfirm: Bool = false
    @State private var isResettingIdentity: Bool = false

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var snapshot: RemoteServerSnapshot {
        appModel.remoteServer
    }

    public var body: some View {
        Form {
            serverControlSection
            pairingSection
            pairedDevicesSection
            securityIdentitySection
        }
        .formStyle(.grouped)
        .navigationTitle("Coincide Remote")
        .task {
            await appModel.refreshRemoteServer()
        }
        .alert("Reset TLS 1.3 Identity?", isPresented: $showResetIdentityConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Identity", role: .destructive) {
                Task { await resetTLSIdentity() }
            }
        } message: {
            Text("Generating a new TLS certificate invalidates all currently paired iPhones and iPads. You will need to scan a new QR code on each device.")
        }
    }

    // MARK: - 1. Server Status & Addresses

    private var serverControlSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { snapshot.enabled },
                    set: { newEnabled in
                        Task {
                            isTogglingServer = true
                            defer { isTogglingServer = false }
                            await appModel.setRemoteServerEnabled(newEnabled)
                        }
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Enable Coincide Remote LAN / Tailscale Server")
                            .font(.system(size: 13, weight: .semibold))

                        serverStatusBadge
                    }
                    Text("Connect from Coincide Remote on iPhone or iPad over Bonjour LAN or Tailscale with mutual TLS 1.3.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
            .disabled(isTogglingServer)

            if let name = snapshot.serverName, !name.isEmpty {
                LabeledContent("Server Name") {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                }
            }

            if let port = snapshot.port {
                LabeledContent("Listening Port") {
                    Text("\(port)")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !snapshot.addresses.isEmpty {
                LabeledContent("Reachable Addresses") {
                    VStack(alignment: .trailing, spacing: 3) {
                        ForEach(snapshot.addresses, id: \.self) { addr in
                            let formatted = snapshot.port.map { "\(addr):\($0)" } ?? addr
                            Text(formatted)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let err = snapshot.errorMessage, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.danger)
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.danger)
                }
            }
        } header: {
            Text("Remote Server")
        }
    }

    private var serverStatusBadge: some View {
        let isLive = snapshot.enabled && snapshot.errorMessage == nil
        let label = snapshot.enabled ? snapshot.status.capitalized : "Off"
        let tint = isLive ? AppTheme.success : (snapshot.enabled ? AppTheme.warning : AppTheme.tertiaryLabel)
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    // MARK: - 2. QR Code Device Pairing

    private var pairingSection: some View {
        Section {
            if let pairing = snapshot.pairing, !pairing.uri.isEmpty {
                VStack(alignment: .center, spacing: 14) {
                    if let qrNSImage = generateQRCodeImage(from: pairing.uri) {
                        Image(nsImage: qrNSImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 196, height: 196)
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(AppTheme.separator, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }

                    VStack(spacing: 4) {
                        Text("Scan with Coincide Remote on iPhone or iPad")
                            .font(.system(size: 13, weight: .semibold))

                        if let expiresAt = pairing.expiresAt {
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                let remaining = Int(max(0, expiresAt.timeIntervalSince(context.date)))
                                if remaining > 0 {
                                    Text("One-time pairing token expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(remaining < 30 ? AppTheme.warning : AppTheme.secondaryLabel)
                                } else {
                                    Text("Pairing code expired — generate a new code.")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.danger)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Copy Pairing URI") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(pairing.uri, forType: .string)
                            appModel.presentToast("Copied Pairing URI", style: .info)
                        }
                        .controlSize(.small)

                        Button("Refresh Code") {
                            Task {
                                isPairingBusy = true
                                defer { isPairingBusy = false }
                                await appModel.beginRemotePairing()
                            }
                        }
                        .controlSize(.small)
                        .disabled(isPairingBusy)

                        Button("Cancel Pairing") {
                            Task {
                                isPairingBusy = true
                                defer { isPairingBusy = false }
                                await appModel.cancelRemotePairing()
                            }
                        }
                        .controlSize(.small)
                        .disabled(isPairingBusy)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pair iPhone or iPad")
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            snapshot.enabled
                                ? "Generates a short-lived QR code pinning this Mac's TLS certificate."
                                : "Enable the Coincide Remote server above first to pair a device."
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    Spacer()

                    Button {
                        Task {
                            isPairingBusy = true
                            defer { isPairingBusy = false }
                            if !snapshot.enabled {
                                await appModel.setRemoteServerEnabled(true)
                            }
                            await appModel.beginRemotePairing()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isPairingBusy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "qrcode")
                            }
                            Text("Pair iPhone or iPad")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPairingBusy)
                }
            }
        } header: {
            Text("Device Pairing")
        }
    }

    // MARK: - 3. Paired Devices

    private var pairedDevicesSection: some View {
        Section {
            if snapshot.devices.isEmpty {
                Text("No paired iOS or iPadOS devices yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else {
                ForEach(snapshot.devices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 15))
                            .foregroundStyle(device.isConnected ? AppTheme.success : AppTheme.secondaryLabel)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(device.name)
                                    .font(.system(size: 13, weight: .medium))
                                if device.isConnected {
                                    Text("Connected")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppTheme.success)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(AppTheme.success.opacity(0.14)))
                                }
                            }

                            HStack(spacing: 8) {
                                if let paired = device.pairedAt {
                                    Text("Paired \(paired, style: .date)")
                                }
                                if let seen = device.lastSeenAt {
                                    Text("· Last seen \(seen, style: .relative) ago")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                        }

                        Spacer()

                        Button("Revoke", role: .destructive) {
                            Task { await appModel.revokeRemoteDevice(device.id) }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Paired Devices (\(snapshot.devices.count))")
        }
    }

    // MARK: - 4. TLS 1.3 Identity & Fingerprint

    private var securityIdentitySection: some View {
        Section {
            LabeledContent("TLS 1.3 SHA-256 Fingerprint") {
                let fp = snapshot.displayFingerprint ?? snapshot.fingerprint ?? "Generated on first enable"
                Text(fp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .textSelection(.enabled)
            }

            if let serverID = snapshot.serverID, !serverID.isEmpty {
                LabeledContent("Server Identifier") {
                    Text(serverID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    showResetIdentityConfirm = true
                } label: {
                    HStack(spacing: 5) {
                        if isResettingIdentity {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Reset TLS Identity…")
                    }
                }
                .controlSize(.small)
                .disabled(isResettingIdentity)
            }
        } header: {
            Text("Cryptographic Identity")
        } footer: {
            Text("Every remote connection uses pinned mutual TLS 1.3 certificates stored in your local Agents store.")
        }
    }

    // MARK: - CoreImage QR Generator & Actions

    private func generateQRCodeImage(from payload: String) -> NSImage? {
        guard let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let scaleTransform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height)
        )
    }

    private func resetTLSIdentity() async {
        guard let runtime = appModel.runtime else { return }
        isResettingIdentity = true
        defer { isResettingIdentity = false }
        do {
            appModel.remoteServer = try await runtime.resetRemoteIdentity()
            appModel.presentToast("Reset TLS Identity", detail: "All previous device pairings were cleared", style: .info)
        } catch {
            appModel.presentError(error)
        }
    }
}
