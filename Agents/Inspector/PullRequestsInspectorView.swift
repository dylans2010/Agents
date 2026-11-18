import AppKit
import CoincideRemoteKit
import SwiftUI

struct PullRequestsInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    enum StateFilter: String, CaseIterable, Identifiable {
        case open
        case merged
        case closed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: "Open"
            case .merged: "Merged"
            case .closed: "Closed"
            }
        }
    }

    enum InvolvementScope: String, CaseIterable, Identifiable {
        case all = "open"
        case mine = "mine"
        case reviewRequested = "reviewRequested"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .mine: "Mine"
            case .reviewRequested: "Review Requested"
            }
        }
    }

    @State private var stateFilter: StateFilter = .open
    @State private var involvementScope: InvolvementScope = .all
    @State private var searchQuery: String = ""
    @State private var pullRequests: [RemotePullRequest] = []
    @State private var unavailableReason: String?
    @State private var isLoadingList: Bool = false

    @State private var selectedPRNumber: Int?
    @State private var selectedDetail: RemotePullRequestDetail?
    @State private var isLoadingDetail: Bool = false
    @State private var isPerformingAction: Bool = false

    // Review & Merge Composer State
    @State private var reviewCommentBody: String = ""
    @State private var selectedMergeMethod: String = "squash"
    @State private var showMergeConfirmation: Bool = false

    private var activeProject: RemoteProject? {
        guard let proj = appModel.selectedProject, !proj.isChats else {
            return appModel.workspace.projects.first(where: { !$0.isChats })
        }
        return proj
    }

    private var filteredPullRequests: [RemotePullRequest] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return pullRequests }
        return pullRequests.filter { pr in
            "\(pr.number)".contains(q)
                || pr.title.lowercased().contains(q)
                || (pr.author?.lowercased().contains(q) ?? false)
                || pr.headBranch.lowercased().contains(q)
                || pr.baseBranch.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterToolbar
            Divider()

            if activeProject == nil {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "arrow.triangle.pull",
                    description: Text("Add or select a GitHub-backed project folder to browse and review pull requests.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let unavailableReason, !unavailableReason.isEmpty, pullRequests.isEmpty {
                ContentUnavailableView {
                    Label("Pull Requests Unavailable", systemImage: "arrow.triangle.pull")
                } description: {
                    Text(unavailableReason)
                } actions: {
                    Button("Retry") {
                        Task { await loadPullRequests() }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingList && pullRequests.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading \(stateFilter.title.lowercased()) pull requests…")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPullRequests.isEmpty {
                ContentUnavailableView {
                    Label("No \(stateFilter.title) Pull Requests", systemImage: "tray")
                } description: {
                    Text(
                        searchQuery.isEmpty
                            ? "No \(stateFilter.title.lowercased()) pull requests matched the current filter."
                            : "No pull requests matched “\(searchQuery)”."
                    )
                } actions: {
                    HStack(spacing: 8) {
                        if !searchQuery.isEmpty {
                            Button("Clear Search") { searchQuery = "" }
                        }
                        Button("Refresh") {
                            Task { await loadPullRequests() }
                        }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    pullRequestListPane
                        .frame(minHeight: 140, idealHeight: 220, maxHeight: 340)

                    pullRequestDetailPane
                        .frame(minHeight: 220, maxHeight: .infinity)
                }
            }
        }
        .background(AppTheme.windowBackground)
        .task(
            id: PRListReloadKey(
                projectID: activeProject?.id,
                state: stateFilter,
                involvement: involvementScope,
                token: refreshToken
            )
        ) {
            await loadPullRequests()
        }
        .task(id: PRDetailReloadKey(projectID: activeProject?.id, number: selectedPRNumber)) {
            await loadSelectedPullRequestDetail()
        }
        .confirmationDialog(
            "Merge Pull Request #\(selectedDetail?.pullRequest.number ?? 0)?",
            isPresented: $showMergeConfirmation
        ) {
            Button("Merge (\(selectedMergeMethod.capitalized))", role: .destructive) {
                Task { await executeMerge() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let pr = selectedDetail?.pullRequest {
                Text("Merge “\(pr.title)” (\(pr.headBranch) → \(pr.baseBranch)) using \(selectedMergeMethod)?")
            }
        }
    }

    // MARK: - Filter & Search Toolbar

    private var filterToolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Picker("State", selection: $stateFilter) {
                    ForEach(StateFilter.allCases) { state in
                        Text(state.title).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Pull request state filter")
                .controlSize(.small)

                Menu {
                    Picker("Involvement", selection: $involvementScope) {
                        ForEach(InvolvementScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                } label: {
                    Image(systemName: involvementScope == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(involvementScope == .all ? AppTheme.secondaryLabel : AppTheme.accent)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filter by Author / Review (\(involvementScope.title))")
                .accessibilityLabel("Filter pull requests by author or review, currently \(involvementScope.title)")

                Button {
                    Task { await loadPullRequests() }
                } label: {
                    if isLoadingList {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh Pull Requests")
                .accessibilityLabel("Refresh pull requests")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                TextField("Search #number, title, author, branch…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear pull request search")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(AppTheme.textBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(AppTheme.separator, lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.controlBackground)
    }

    // MARK: - PR List Pane

    private var pullRequestListPane: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredPullRequests) { pr in
                    PullRequestSummaryRow(
                        pr: pr,
                        isSelected: selectedPRNumber == pr.number
                    ) {
                        selectedPRNumber = pr.number
                    }
                }
            }
            .padding(6)
        }
        .background(AppTheme.underPageBackground.opacity(0.45))
    }

    // MARK: - PR Detail Pane

    @ViewBuilder
    private var pullRequestDetailPane: some View {
        if selectedPRNumber == nil {
            ContentUnavailableView(
                "Select a Pull Request",
                systemImage: "arrow.triangle.pull",
                description: Text("Choose a pull request above to inspect its description, checks, reviews, and merge options.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingDetail && selectedDetail == nil {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading pull request #\(selectedPRNumber ?? 0)…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = selectedDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detailHeaderCard(detail)
                    detailActionButtonsBar(detail)
                    detailDescriptionCard(detail)

                    if !detail.checks.isEmpty {
                        detailChecksCard(detail)
                    }

                    detailReviewsSection(detail)

                    if detail.pullRequest.state == .open {
                        detailMergeCard(detail)
                    }
                }
                .padding(10)
            }
        } else {
            ContentUnavailableView(
                "Unable to Load Pull Request",
                systemImage: "exclamationmark.triangle",
                description: Text("Select another pull request or click Refresh.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeaderCard(_ detail: RemotePullRequestDetail) -> some View {
        let pr = detail.pullRequest
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("#\(pr.number)")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                prStatePill(pr)

                if let review = pr.review {
                    reviewDecisionBadge(review)
                }

                if let checks = pr.checks {
                    checksSummaryBadge(checks)
                }

                Spacer(minLength: 0)

                if detail.additions != nil || detail.deletions != nil {
                    HStack(spacing: 4) {
                        if let add = detail.additions {
                            Text("+\(add)")
                                .foregroundStyle(AppTheme.diffAdditionText)
                        }
                        if let del = detail.deletions {
                            Text("−\(del)")
                                .foregroundStyle(AppTheme.diffDeletionText)
                        }
                        if let files = detail.changedFiles {
                            Text("(\(files)f)")
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }

            HStack(spacing: 6) {
                if let author = pr.author, !author.isEmpty {
                    Text("@\(author)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                if !pr.headBranch.isEmpty {
                    Text("\(pr.headBranch) → \(pr.baseBranch)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.controlBackground)
                        )
                }

                Spacer(minLength: 0)

                if let updated = pr.updatedAt {
                    Text(updated, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private func detailActionButtonsBar(_ detail: RemotePullRequestDetail) -> some View {
        let pr = detail.pullRequest
        return HStack(spacing: 6) {
            Button {
                Task { await checkoutPullRequestBranch(pr) }
            } label: {
                Label("Checkout PR Branch", systemImage: "arrow.down.to.line.compact")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isPerformingAction || pr.headBranch.isEmpty)

            if pr.isDraft && pr.state == .open {
                Button {
                    Task { await markPullRequestReady(pr) }
                } label: {
                    Text("Mark Ready")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPerformingAction)
            }

            if let url = URL(string: pr.url), !pr.url.isEmpty {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open on GitHub")
            }
        }
    }

    private func detailDescriptionCard(_ detail: RemotePullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESCRIPTION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryLabel)

            if detail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No description provided.")
                    .font(.system(size: 11.5))
                    .italic()
                    .foregroundStyle(AppTheme.tertiaryLabel)
            } else {
                Text(detail.body)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private func detailChecksCard(_ detail: RemotePullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHECKS (\(detail.checks.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryLabel)

            ForEach(Array(detail.checks.enumerated()), id: \.offset) { _, check in
                HStack(spacing: 6) {
                    Image(systemName: checkIcon(for: check.status))
                        .font(.system(size: 11))
                        .foregroundStyle(checkTint(for: check.status))
                    Text(check.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)
                    Spacer()
                    if let urlStr = check.url, let url = URL(string: urlStr) {
                        Button("Details") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private func detailReviewsSection(_ detail: RemotePullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("REVIEWS & COMMENTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
                if isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !detail.reviews.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(detail.reviews.enumerated()), id: \.offset) { _, rev in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("@\(rev.author)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                Spacer()
                                Text(rev.state.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(reviewStateTint(rev.state))
                            }
                            if !rev.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(rev.body)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .fill(AppTheme.controlBackground)
                        )
                    }
                }
            }

            // Submit Review Composer
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reviewCommentBody)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 56, maxHeight: 96)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .fill(AppTheme.textBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 0.85)
                    )

                if reviewCommentBody.isEmpty {
                    Text("Leave a review comment or summary…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 6) {
                Button {
                    Task { await submitReview(event: "COMMENT") }
                } label: {
                    Text("Comment")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPerformingAction || reviewCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await submitReview(event: "APPROVE") }
                } label: {
                    Text("Approve")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.success)
                .controlSize(.small)
                .disabled(isPerformingAction)

                Button {
                    Task { await submitReview(event: "REQUEST_CHANGES") }
                } label: {
                    Text("Request Changes")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPerformingAction || reviewCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private func detailMergeCard(_ detail: RemotePullRequestDetail) -> some View {
        let methods = detail.mergeMethods.isEmpty ? ["squash", "merge", "rebase"] : detail.mergeMethods
        let conflicting = detail.mergeability == "conflicting"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Merge Pull Request", systemImage: "arrow.triangle.merge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                Text(detail.mergeability.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        conflicting
                            ? AppTheme.danger
                            : (detail.mergeability == "mergeable" ? AppTheme.success : AppTheme.secondaryLabel)
                    )
            }

            if conflicting {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.danger)
                    Text("This branch has merge conflicts with \(detail.pullRequest.baseBranch).")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            HStack(spacing: 8) {
                Picker("Strategy", selection: $selectedMergeMethod) {
                    ForEach(methods, id: \.self) { method in
                        Text(method.capitalized).tag(method)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 120)

                Button {
                    showMergeConfirmation = true
                } label: {
                    Text("Merge Pull Request…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPerformingAction || conflicting || detail.pullRequest.isDraft)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    // MARK: - Badges & Visual Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
            .fill(AppTheme.elevatedCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 0.85)
            )
    }

    private func prStatePill(_ pr: RemotePullRequest) -> some View {
        let (label, tint): (String, Color) = {
            if pr.isDraft && pr.state == .open {
                return ("Draft", AppTheme.secondaryLabel)
            }
            switch pr.state {
            case .open: return ("Open", AppTheme.success)
            case .merged: return ("Merged", AppTheme.merged)
            case .closed: return ("Closed", AppTheme.danger)
            case .unknown: return ("Unknown", AppTheme.secondaryLabel)
            }
        }()

        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func reviewDecisionBadge(_ review: RemotePullRequest.Review) -> some View {
        let (label, tint): (String, Color) = switch review {
        case .approved: ("Approved", AppTheme.success)
        case .changesRequested: ("Changes Requested", AppTheme.danger)
        case .reviewRequired: ("Review Required", AppTheme.warning)
        case .unknown: ("Review", AppTheme.secondaryLabel)
        }
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func checksSummaryBadge(_ checks: RemotePullRequest.Checks) -> some View {
        let (icon, tint): (String, Color) = switch checks {
        case .passing: ("checkmark.circle.fill", AppTheme.success)
        case .failing: ("xmark.circle.fill", AppTheme.danger)
        case .pending: ("clock.fill", AppTheme.warning)
        case .unknown: ("questionmark.circle", AppTheme.secondaryLabel)
        }
        return Image(systemName: icon)
            .font(.system(size: 11.5))
            .foregroundStyle(tint)
    }

    private func checkIcon(for status: String) -> String {
        switch status.lowercased() {
        case "success", "passing": "checkmark.circle.fill"
        case "failure", "failing", "actionrequired": "xmark.circle.fill"
        case "pending", "in_progress", "queued": "clock.fill"
        default: "minus.circle"
        }
    }

    private func checkTint(for status: String) -> Color {
        switch status.lowercased() {
        case "success", "passing": AppTheme.success
        case "failure", "failing", "actionrequired": AppTheme.danger
        case "pending", "in_progress", "queued": AppTheme.warning
        default: AppTheme.secondaryLabel
        }
    }

    private func reviewStateTint(_ state: String) -> Color {
        switch state.uppercased() {
        case "APPROVED": AppTheme.success
        case "CHANGES_REQUESTED": AppTheme.danger
        default: AppTheme.secondaryLabel
        }
    }

    // MARK: - Network / Runtime Actions

    private func loadPullRequests() async {
        guard let client = appModel.runtime, let project = activeProject else {
            pullRequests = []
            unavailableReason = nil
            return
        }

        isLoadingList = true
        defer { isLoadingList = false }

        do {
            if stateFilter == .open {
                let list = try await client.fetchPullRequests(
                    RemotePullRequestQuery(projectID: project.id, filter: involvementScope.rawValue)
                )
                self.unavailableReason = list.unavailable.flatMap { $0.isEmpty ? nil : ErrorSanitizer.sanitizeText($0) }
                self.pullRequests = list.items
            } else {
                let listed = try await fetchPullRequestsByStateViaEngine(
                    client: client,
                    project: project,
                    state: stateFilter.rawValue,
                    involvement: involvementScope
                )
                self.unavailableReason = listed.unavailable.flatMap { $0.isEmpty ? nil : ErrorSanitizer.sanitizeText($0) }
                self.pullRequests = listed.items
            }

            if let selected = selectedPRNumber, !pullRequests.contains(where: { $0.number == selected }) {
                selectedPRNumber = pullRequests.first?.number
                selectedDetail = nil
            } else if selectedPRNumber == nil {
                selectedPRNumber = pullRequests.first?.number
            }
        } catch {
            self.unavailableReason = ErrorSanitizer.displayMessage(for: error)
            self.pullRequests = []
        }
    }

    private func loadSelectedPullRequestDetail() async {
        guard let client = appModel.runtime,
              let project = activeProject,
              let number = selectedPRNumber
        else {
            selectedDetail = nil
            return
        }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let detail: RemotePullRequestDetail
            if let tid = appModel.selectedThreadUUID,
               appModel.selectedThread?.projectID == project.id
            {
                detail = try await client.fetchPullRequestDetail(thread: tid, number: number)
            } else {
                detail = try await client.fetchPullRequestDetail(projectID: project.id, number: number)
            }
            if selectedPRNumber == number {
                self.selectedDetail = detail
                if let firstMethod = detail.mergeMethods.first, !detail.mergeMethods.contains(selectedMergeMethod) {
                    self.selectedMergeMethod = firstMethod
                }
            }
        } catch {
            if selectedPRNumber == number {
                self.selectedDetail = nil
            }
        }
    }

    private func checkoutPullRequestBranch(_ pr: RemotePullRequest) async {
        guard let client = appModel.runtime, let project = activeProject else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await client.performPullRequestAction(
                RemotePullRequestCommand(
                    projectID: project.id,
                    number: pr.number,
                    action: .checkOut
                )
            )
            await appModel.refreshWorkspace()
            if case .thread(let newThreadID) = result {
                appModel.selectThread(newThreadID)
            }
            appModel.presentToast(
                "Checked Out PR #\(pr.number)",
                detail: pr.headBranch,
                style: .success
            )
        } catch {
            appModel.presentError(error)
        }
    }

    private func markPullRequestReady(_ pr: RemotePullRequest) async {
        guard let client = appModel.runtime, let project = activeProject else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let res = try await client.performPullRequestAction(
                RemotePullRequestCommand(
                    projectID: project.id,
                    number: pr.number,
                    action: .markReady
                )
            )
            if case .pullRequest(let updated) = res {
                selectedDetail = updated
            } else {
                await loadSelectedPullRequestDetail()
            }
            await loadPullRequests()
            appModel.presentToast("Marked PR #\(pr.number) Ready", style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func submitReview(event: String) async {
        guard let client = appModel.runtime,
              let project = activeProject,
              let number = selectedPRNumber
        else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        let bodyText = reviewCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let res = try await client.performPullRequestAction(
                RemotePullRequestCommand(
                    projectID: project.id,
                    number: number,
                    action: .review,
                    event: event,
                    body: bodyText.isEmpty ? nil : bodyText
                )
            )
            reviewCommentBody = ""
            if case .pullRequest(let updated) = res {
                selectedDetail = updated
            } else {
                await loadSelectedPullRequestDetail()
            }
            await loadPullRequests()
            let toastTitle = switch event {
            case "APPROVE": "Approved PR #\(number)"
            case "REQUEST_CHANGES": "Requested Changes on PR #\(number)"
            default: "Commented on PR #\(number)"
            }
            appModel.presentToast(toastTitle, style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func executeMerge() async {
        guard let client = appModel.runtime,
              let project = activeProject,
              let number = selectedPRNumber
        else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let res = try await client.performPullRequestAction(
                RemotePullRequestCommand(
                    projectID: project.id,
                    number: number,
                    action: .merge,
                    method: selectedMergeMethod
                )
            )
            if case .pullRequest(let updated) = res {
                selectedDetail = updated
            } else {
                await loadSelectedPullRequestDetail()
            }
            await loadPullRequests()
            await appModel.refreshGitState()
            appModel.presentToast("Merged PR #\(number)", detail: selectedMergeMethod.capitalized, style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    /// Queries merged or closed pull requests directly through `github.pr.list` on the Rust engine,
    /// matching the exact polling protocol used by `adapter_bridge.rs`.
    private func fetchPullRequestsByStateViaEngine(
        client: AgentsRuntimeClient,
        project: RemoteProject,
        state: String,
        involvement: InvolvementScope
    ) async throws -> RemotePullRequestList {
        guard let thread = appModel.workspace.threads.first(where: { $0.projectID == project.id }) ?? appModel.selectedThread else {
            return try await client.fetchPullRequests(RemotePullRequestQuery(projectID: project.id, filter: involvement.rawValue))
        }
        let threadID = thread.id.uuidString.lowercased()
        let expandedPath = ExternalEditorService.expandedPath(project.path)
        let canonRoot = URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath().path

        let availInit = try await client.engineRPC(
            method: "github.pr.availability",
            params: ["threadId": .string(threadID)]
        )
        let avail = try await pollGitHubOperation(client: client, threadID: threadID, root: canonRoot, initial: availInit)
        if avail["state"]?.stringValue != "ready" {
            let msg = avail["message"]?.stringValue ?? "GitHub pull requests are unavailable for this project."
            return RemotePullRequestList(items: [], unavailable: msg.isEmpty ? msg : ErrorSanitizer.sanitizeText(msg))
        }
        guard let repo = avail["repository"]?.stringValue else {
            return RemotePullRequestList(items: [], unavailable: "GitHub repository not detected.")
        }

        let involvementParam: String = switch involvement {
        case .mine: "authored"
        case .reviewRequested: "reviewRequested"
        case .all: "all"
        }

        let listInit = try await client.engineRPC(
            method: "github.pr.list",
            params: [
                "threadId": .string(threadID),
                "expectedRoot": .string(canonRoot),
                "repository": .string(repo),
                "state": .string(state),
                "limit": .int(50),
                "involvement": .string(involvementParam),
            ]
        )
        let listed = try await pollGitHubOperation(client: client, threadID: threadID, root: canonRoot, initial: listInit)
        let rawArray = listed["pullRequests"]?.arrayValue ?? listed["items"]?.arrayValue ?? []

        let items: [RemotePullRequest] = rawArray.compactMap { raw in
            guard let num = raw["number"]?.intValue else { return nil }
            let rawState = (raw["state"]?.stringValue ?? state).lowercased()
            let mappedState: RemotePullRequest.State = switch rawState {
            case "merged": .merged
            case "closed": .closed
            default: .open
            }
            let mappedReview: RemotePullRequest.Review? = switch raw["reviewDecision"]?.stringValue {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            case "REVIEW_REQUIRED": .reviewRequired
            default: nil
            }
            let updatedDate: Date? = raw["updatedAt"]?.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) }
            return RemotePullRequest(
                number: num,
                title: raw["title"]?.stringValue ?? "",
                url: raw["url"]?.stringValue ?? "",
                author: raw["author"]?["login"]?.stringValue ?? raw["author"]?.stringValue,
                headBranch: raw["headRefName"]?.stringValue ?? raw["headBranch"]?.stringValue ?? "",
                baseBranch: raw["baseRefName"]?.stringValue ?? raw["baseBranch"]?.stringValue ?? "",
                state: mappedState,
                isDraft: raw["isDraft"]?.boolValue ?? false,
                checks: nil,
                review: mappedReview,
                updatedAt: updatedDate
            )
        }
        return RemotePullRequestList(items: items, unavailable: nil)
    }

    private func pollGitHubOperation(
        client: AgentsRuntimeClient,
        threadID: String,
        root: String,
        initial: JSONValue
    ) async throws -> JSONValue {
        guard let opID = initial["operationId"]?.stringValue else {
            return initial
        }
        let expectedRoot = initial["expectedRoot"]?.stringValue ?? root
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let poll = try await client.engineRPC(
                method: "github.result",
                params: [
                    "threadId": .string(threadID),
                    "expectedRoot": .string(expectedRoot),
                    "operationId": .string(opID),
                ]
            )
            if poll["ready"]?.boolValue == true {
                let result = poll["result"] ?? .object([:])
                if let err = result["error"]?.stringValue, !err.isEmpty {
                    throw AgentsRuntimeError.desktopFailure(err)
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AgentsRuntimeError.desktopFailure("GitHub pull request query timed out.")
    }
}

private struct PRListReloadKey: Equatable {
    let projectID: UUID?
    let state: PullRequestsInspectorView.StateFilter
    let involvement: PullRequestsInspectorView.InvolvementScope
    let token: UUID
}

private struct PRDetailReloadKey: Equatable {
    let projectID: UUID?
    let number: Int?
}

// MARK: - PR Summary Row

private struct PullRequestSummaryRow: View {
    let pr: RemotePullRequest
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    private var stateTint: Color {
        if pr.isDraft && pr.state == .open { return AppTheme.secondaryLabel }
        return switch pr.state {
        case .open: AppTheme.success
        case .merged: AppTheme.merged
        case .closed: AppTheme.danger
        case .unknown: AppTheme.secondaryLabel
        }
    }

    private var stateIcon: String {
        if pr.isDraft && pr.state == .open { return "circle.dashed" }
        return switch pr.state {
        case .open: "arrow.triangle.pull"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stateIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(stateTint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("#\(pr.number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(pr.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    if let author = pr.author, !author.isEmpty {
                        Text("@\(author)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    if !pr.headBranch.isEmpty {
                        Text("\(pr.headBranch) → \(pr.baseBranch)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    if pr.isDraft {
                        Text("Draft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(AppTheme.elevatedCardFill))
                    }
                    if let checks = pr.checks {
                        Circle()
                            .fill(
                                checks == .passing
                                    ? AppTheme.success
                                    : (checks == .failing ? AppTheme.danger : AppTheme.warning)
                            )
                            .frame(width: 7, height: 7)
                    }
                }

                if let review = pr.review {
                    Text(
                        review == .approved
                            ? "Approved"
                            : (review == .changesRequested ? "Changes" : "Review")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        review == .approved
                            ? AppTheme.success
                            : (review == .changesRequested ? AppTheme.danger : AppTheme.tertiaryLabel)
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(
                    isSelected
                        ? AppTheme.unemphasizedSelectedBackground
                        : (isHovered ? AppTheme.subtleHoverFill : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}
