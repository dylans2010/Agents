import CoincideRemoteKit
import SwiftUI

struct TranscriptScrollView: View {
    let transcript: RemoteTranscript
    let appModel: AppModel
    var highlightQuery: String = ""
    var activeFindItemID: UUID? = nil

    @State private var expandedWorkGroups: Set<UUID> = []
    @State private var isLoadingEarlier = false
    @State private var isNearBottom = true
    @State private var scrollNonce: Int = 0
    @State private var blockCache = RenderBlockCache()

    private static let bottomAnchorID = "coincide-transcript-bottom-anchor"

    private var renderBlocks: [TranscriptRenderBlock] {
        blockCache.blocks(for: transcript)
    }

    private var streamingTailSignature: String {
        let lastID = transcript.items.last?.id.uuidString ?? "none"
        let lastLen = transcript.items.last?.text.count ?? 0
        let lastStatus = transcript.items.last?.status ?? ""
        return "\(transcript.items.count):\(lastID):\(lastLen):\(lastStatus):\(transcript.turn.isRunning):\(transcript.turn.isStarting)"
    }

    private var failedWorkGroupIDs: [UUID] {
        renderBlocks.compactMap { block in
            if case .workGroup(let id, let items) = block, items.contains(where: { $0.status == "failed" }) {
                return id
            }
            return nil
        }
    }

    private var failedWorkGroupSignature: String {
        failedWorkGroupIDs.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func expandFailedWorkGroups() {
        for id in failedWorkGroupIDs {
            expandedWorkGroups.insert(id)
        }
    }

    var body: some View {
        let blocks = renderBlocks
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        // Pagination header
                        if transcript.hasEarlier {
                            HStack {
                                Spacer()
                                Button {
                                    guard !isLoadingEarlier else { return }
                                    isLoadingEarlier = true
                                    Task {
                                        await appModel.loadEarlierMessages()
                                        isLoadingEarlier = false
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if isLoadingEarlier {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "arrow.up.circle")
                                                .font(.system(size: 12))
                                        }
                                        Text(isLoadingEarlier ? "Loading earlier messages…" : "Load Earlier Messages")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isLoadingEarlier)
                                Spacer()
                            }
                            .padding(.bottom, 4)
                        }

                        // Virtualized transcript blocks
                        ForEach(blocks) { block in
                            let isFindTarget = activeFindItemID.map { block.containsItem(id: $0) } ?? false
                            TranscriptBlockRowView(
                                block: block,
                                threadID: transcript.thread.id,
                                appModel: appModel,
                                expandedWorkGroups: $expandedWorkGroups,
                                highlightQuery: highlightQuery,
                                isActiveFindMatch: isFindTarget
                            )
                            .id(block.id)
                        }

                        // Background subagents / commands strip
                        if let bgTasks = transcript.turn.backgroundTasks, !bgTasks.isEmpty {
                            ActiveBackgroundTasksStrip(tasks: bgTasks)
                        }

                        // Starting / Streaming live indicator if no work group is actively spinning
                        if (transcript.turn.isStarting || transcript.turn.isRunning),
                           !transcript.items.contains(where: { $0.status == "running" })
                        {
                            HStack(spacing: 8) {
                                AgentLogoView(
                                    provider: transcript.turn.provider ?? transcript.thread.selection.provider,
                                    size: 15
                                )
                                ProgressView()
                                    .controlSize(.small)
                                Text(transcript.turn.isStarting ? "Starting agent session…" : "Working…")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .padding(.vertical, 6)
                        }

                        if let resumesAt = transcript.turn.resumesAt {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.checkmark")
                                    .foregroundStyle(AppTheme.warning)
                                Text("Paused for rate limit · Automatically resumes at \(resumesAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .padding(10)
                            .background(AppTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .frame(maxWidth: AppTheme.conversationColumnMaxWidth, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let distanceFromBottom = geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                    return distanceFromBottom <= 96
                } action: { _, nearBottom in
                    if isNearBottom != nearBottom {
                        isNearBottom = nearBottom
                    }
                }
                .onAppear {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
                .onChange(of: transcript.thread.id) { _, _ in
                    expandedWorkGroups.removeAll()
                    isNearBottom = true
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
                .onChange(of: streamingTailSignature) { _, _ in
                    if isNearBottom {
                        withAnimation(.easeOut(duration: 0.14)) {
                            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: activeFindItemID) { _, targetID in
                    guard let targetID,
                          let matchedBlock = blocks.first(where: { $0.containsItem(id: targetID) })
                    else { return }
                    withAnimation(.snappy(duration: 0.22)) {
                        proxy.scrollTo(matchedBlock.id, anchor: .center)
                    }
                }

                // Floating Jump to Latest capsule
                if !isNearBottom {
                    Button {
                        isNearBottom = true
                        scrollNonce += 1
                        withAnimation(.snappy(duration: 0.22)) {
                            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if transcript.turn.isRunning || transcript.turn.isStarting {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 7, height: 7)
                            }
                            Text("Jump to Latest")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.primaryLabel)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .glassCapsule()
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: isNearBottom)
            .onAppear { expandFailedWorkGroups() }
            .onChange(of: failedWorkGroupSignature) { _, _ in
                expandFailedWorkGroups()
            }
        }
    }
}

@MainActor
private final class RenderBlockCache {
    private var signature: Int?
    private var blocks: [TranscriptRenderBlock] = []

    func blocks(for transcript: RemoteTranscript) -> [TranscriptRenderBlock] {
        var hasher = Hasher()
        hasher.combine(transcript.items)
        hasher.combine(transcript.turnChanges)
        let next = hasher.finalize()
        if signature != next {
            signature = next
            blocks = TranscriptRenderBlock.build(from: transcript)
        }
        return blocks
    }
}
