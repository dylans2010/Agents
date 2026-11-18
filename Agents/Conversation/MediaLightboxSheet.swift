import AppKit
import CoincideRemoteKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared In-Memory Media Cache

@MainActor
final class TranscriptMediaCache {
    static let shared = TranscriptMediaCache()

    private let imageCache = NSCache<NSString, NSImage>()
    private var rawDataCache: [String: RemoteMediaData] = [:]

    private init() {
        imageCache.countLimit = 180
        imageCache.totalCostLimit = 96 * 1024 * 1024
    }

    private func cacheKey(threadID: UUID, itemID: UUID, index: Int, full: Bool) -> String {
        "\(threadID.uuidString):\(itemID.uuidString):\(index):\(full ? "full" : "thumb")"
    }

    func cached(threadID: UUID, itemID: UUID, index: Int, full: Bool) -> (NSImage, RemoteMediaData)? {
        let key = cacheKey(threadID: threadID, itemID: itemID, index: index, full: full)
        guard let image = imageCache.object(forKey: key as NSString),
              let meta = rawDataCache[key]
        else {
            return nil
        }
        return (image, meta)
    }

    func store(
        _ mediaData: RemoteMediaData,
        image: NSImage,
        threadID: UUID,
        itemID: UUID,
        index: Int,
        full: Bool
    ) {
        let key = cacheKey(threadID: threadID, itemID: itemID, index: index, full: full)
        imageCache.setObject(image, forKey: key as NSString, cost: mediaData.data.count)
        if rawDataCache.count > 200 {
            rawDataCache.removeAll(keepingCapacity: true)
        }
        rawDataCache[key] = mediaData
    }
}

// MARK: - Lightbox Presentation Model

nonisolated struct MediaLightboxTarget: Identifiable, Hashable, Sendable {
    let threadID: UUID
    let itemID: UUID
    let media: RemoteMedia

    var id: String { "\(threadID.uuidString):\(itemID.uuidString):\(media.index)" }
}

// MARK: - Inline Media Strip View

struct InlineMediaStripView: View {
    let item: RemoteItem
    let threadID: UUID
    let appModel: AppModel
    var alignment: HorizontalAlignment = .leading

    @State private var selectedTarget: MediaLightboxTarget? = nil

    var body: some View {
        let mediaItems = item.media ?? []
        if !mediaItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(mediaItems) { entry in
                        MediaThumbnailTile(
                            threadID: threadID,
                            itemID: item.id,
                            media: entry,
                            appModel: appModel
                        ) {
                            selectedTarget = MediaLightboxTarget(
                                threadID: threadID,
                                itemID: item.id,
                                media: entry
                            )
                        }
                    }
                }
            }
            .sheet(item: $selectedTarget) { target in
                MediaLightboxSheet(target: target, appModel: appModel)
            }
        }
    }
}

private struct MediaThumbnailTile: View {
    let threadID: UUID
    let itemID: UUID
    let media: RemoteMedia
    let appModel: AppModel
    let onOpen: () -> Void

    @State private var thumbnailImage: NSImage? = nil
    @State private var loadFailed = false
    @State private var isHovering = false

    private var fallbackSymbol: String {
        switch media.kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .interactive: "macwindow"
        case .unknown: "doc.richtext"
        }
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                if let thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 148, height: 104)
                        .clipped()
                } else if loadFailed || media.kind == .audio || media.kind == .interactive {
                    VStack(spacing: 6) {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text(media.label.isEmpty ? media.kind.rawValue.capitalized : media.label)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .frame(width: 148, height: 104)
                    .background(AppTheme.elevatedCardFill)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 148, height: 104)
                        .background(AppTheme.elevatedCardFill)
                }

                if media.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isHovering || !media.label.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(media.label.isEmpty ? "Preview" : media.label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(6)
                    .opacity(isHovering ? 1.0 : 0.82)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(isHovering ? AppTheme.accent : AppTheme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(media.label.isEmpty ? "Open full-size media preview" : media.label)
        .accessibilityLabel(media.label.isEmpty ? "Open full-size media preview" : "Preview \(media.label)")
        .task(id: "\(threadID.uuidString):\(itemID.uuidString):\(media.index)") {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard media.kind == .image || media.kind == .video else { return }
        if let cached = TranscriptMediaCache.shared.cached(
            threadID: threadID,
            itemID: itemID,
            index: media.index,
            full: false
        ) {
            thumbnailImage = cached.0
            return
        }
        guard let client = appModel.runtime else { return }
        do {
            let fetched = try await client.fetchMedia(
                thread: threadID,
                itemID: itemID,
                index: media.index,
                full: false
            )
            if let img = NSImage(data: fetched.data) {
                TranscriptMediaCache.shared.store(
                    fetched,
                    image: img,
                    threadID: threadID,
                    itemID: itemID,
                    index: media.index,
                    full: false
                )
                thumbnailImage = img
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - Full-Resolution Media Lightbox Sheet

struct MediaLightboxSheet: View {
    let target: MediaLightboxTarget
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: NSImage? = nil
    @State private var mediaMeta: RemoteMediaData? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var fitToWindow = true
    @State private var copiedImage = false

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)

                VStack(alignment: .leading, spacing: 1) {
                    Text(target.media.label.isEmpty ? "Image Preview" : target.media.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)
                    if let meta = mediaMeta {
                        Text("\(meta.width) × \(meta.height) px · \(ByteCountFormatter.string(fromByteCount: Int64(meta.data.count), countStyle: .file))")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }

                Spacer()

                // Zoom controls
                if fullImage != nil {
                    HStack(spacing: 4) {
                        Button {
                            fitToWindow = true
                            zoomScale = 1.0
                        } label: {
                            Text("Fit")
                                .font(.system(size: 11, weight: fitToWindow ? .semibold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            fitToWindow = false
                            zoomScale = max(0.25, zoomScale - 0.25)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Zoom out")

                        Text("\(Int((zoomScale * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .frame(width: 44)

                        Button {
                            fitToWindow = false
                            zoomScale = min(4.0, zoomScale + 0.25)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Zoom in")
                    }

                    Button {
                        copyImageToPasteboard()
                    } label: {
                        Label(copiedImage ? "Copied" : "Copy Image", systemImage: copiedImage ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        saveImageToDisk()
                    } label: {
                        Label("Save…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close preview")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.controlBackground)

            Divider()

            // Canvas
            GeometryReader { geo in
                ZStack {
                    AppTheme.underPageBackground.ignoresSafeArea()

                    if isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading full-resolution image…")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    } else if let fullImage {
                        if fitToWindow {
                            Image(nsImage: fullImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(20)
                                .frame(width: geo.size.width, height: geo.size.height)
                        } else {
                            ScrollView([.horizontal, .vertical]) {
                                let baseWidth = CGFloat(mediaMeta?.width ?? Int(fullImage.size.width))
                                let baseHeight = CGFloat(mediaMeta?.height ?? Int(fullImage.size.height))
                                Image(nsImage: fullImage)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(
                                        width: max(60, baseWidth * zoomScale),
                                        height: max(60, baseHeight * zoomScale)
                                    )
                                    .padding(24)
                                    .frame(
                                        minWidth: geo.size.width,
                                        minHeight: geo.size.height
                                    )
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Preview Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage ?? "This attachment could not be rendered.")
                        )
                    }
                }
            }
        }
        .frame(minWidth: 740, idealWidth: 900, minHeight: 540, idealHeight: 660)
        .task {
            await loadFullMedia()
        }
    }

    private func loadFullMedia() async {
        isLoading = true
        errorMessage = nil

        if let cached = TranscriptMediaCache.shared.cached(
            threadID: target.threadID,
            itemID: target.itemID,
            index: target.media.index,
            full: true
        ) {
            fullImage = cached.0
            mediaMeta = cached.1
            isLoading = false
            return
        }

        // Show cached thumbnail immediately if available while full-res loads
        if let thumb = TranscriptMediaCache.shared.cached(
            threadID: target.threadID,
            itemID: target.itemID,
            index: target.media.index,
            full: false
        ) {
            fullImage = thumb.0
            mediaMeta = thumb.1
        }

        guard let client = appModel.runtime else {
            isLoading = false
            return
        }

        do {
            let fullData = try await client.fetchMedia(
                thread: target.threadID,
                itemID: target.itemID,
                index: target.media.index,
                full: true
            )
            if let decoded = NSImage(data: fullData.data) {
                TranscriptMediaCache.shared.store(
                    fullData,
                    image: decoded,
                    threadID: target.threadID,
                    itemID: target.itemID,
                    index: target.media.index,
                    full: true
                )
                fullImage = decoded
                mediaMeta = fullData
            } else if fullImage == nil {
                errorMessage = "Unsupported image encoding."
            }
        } catch {
            if fullImage == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func copyImageToPasteboard() {
        guard let fullImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fullImage])
        copiedImage = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedImage = false
        }
    }

    private func saveImageToDisk() {
        guard let data = mediaMeta?.data else { return }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let ext = isPNG ? "png" : "jpg"

        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [isPNG ? .png : .jpeg]
        let baseName = target.media.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseName.isEmpty {
            panel.nameFieldStringValue = "coincide-image-\(target.media.index + 1).\(ext)"
        } else if (baseName as NSString).pathExtension.isEmpty {
            panel.nameFieldStringValue = "\(baseName).\(ext)"
        } else {
            panel.nameFieldStringValue = baseName
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                appModel.presentToast("Saved Image", detail: url.lastPathComponent, style: .success)
            } catch {
                appModel.presentError(error)
            }
        }
    }
}
