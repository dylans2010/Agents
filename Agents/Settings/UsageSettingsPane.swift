import AppKit
import Charts
import CoincideRemoteKit
import SwiftUI

public struct UsageSettingsPane: View {
    @Bindable public var appModel: AppModel

    private enum ChartMetric: String, CaseIterable, Identifiable {
        case tokens = "Tokens"
        case cost = "Est. Cost (USD)"
        var id: String { rawValue }
    }

    @State private var selectedDays: Int = 30
    @State private var selectedProviderFilter: String = "all"
    @State private var chartMetric: ChartMetric = .tokens
    @State private var report: DesktopUsageReport = DesktopUsageReport()
    @State private var isLoading: Bool = false

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var parsedDailyPoints: [DailyChartPoint] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return report.daily.map { row in
            let resolvedDate: Date
            if row.dayMs > 0 {
                resolvedDate = Date(timeIntervalSince1970: Double(row.dayMs) / 1000.0)
            } else if let parsed = formatter.date(from: row.date) {
                resolvedDate = parsed
            } else {
                resolvedDate = Date()
            }
            let providerLabel = row.provider.isEmpty
                ? "All"
                : AgentBranding.displayName(for: row.provider)
            return DailyChartPoint(
                id: row.id,
                date: resolvedDate,
                dateLabel: row.date,
                providerID: row.provider,
                providerName: providerLabel,
                tokens: Double(row.totals.totalTokens),
                costUSD: row.totals.estimatedCostUSD
            )
        }
        .sorted { $0.date < $1.date }
    }

    private struct DailyChartPoint: Identifiable {
        let id: String
        let date: Date
        let dateLabel: String
        let providerID: String
        let providerName: String
        let tokens: Double
        let costUSD: Double
    }

    public var body: some View {
        VStack(spacing: 0) {
            usageFilterToolbar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    kpiSummaryGrid
                    dailyChartCard
                    rateLimitWindowsSection
                    breakdownColumnsSection
                }
                .padding(18)
            }
        }
        .navigationTitle("Usage")
        .task {
            if appModel.providers.isEmpty {
                await appModel.refreshProviders()
            }
            await reloadUsage(refreshLimits: false)
        }
        .onChange(of: selectedDays) { _, _ in
            Task { await reloadUsage(refreshLimits: false) }
        }
        .onChange(of: selectedProviderFilter) { _, _ in
            Task { await reloadUsage(refreshLimits: false) }
        }
    }

    // MARK: - Top Filter Bar

    private var usageFilterToolbar: some View {
        HStack(spacing: 12) {
            Picker("Period", selection: $selectedDays) {
                Text("7 Days").tag(7)
                Text("30 Days").tag(30)
                Text("90 Days").tag(90)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Usage period")
            .frame(minWidth: 170, idealWidth: 220, maxWidth: 260)

            Picker("Provider", selection: $selectedProviderFilter) {
                Text("All Providers").tag("all")
                ForEach(appModel.providers) { provider in
                    Text(provider.displayName).tag(provider.id)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Usage provider filter")
            .frame(minWidth: 140, idealWidth: 175, maxWidth: 220)

            Picker("Metric", selection: $chartMetric) {
                ForEach(ChartMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Chart metric")
            .frame(minWidth: 150, idealWidth: 190, maxWidth: 230)

            Spacer()

            Button {
                Task { await reloadUsage(refreshLimits: true) }
            } label: {
                HStack(spacing: 5) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
            }
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.controlBackground)
    }

    // MARK: - 1. KPI Summary Cards

    private var kpiSummaryGrid: some View {
        let totals = report.period
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 128), spacing: 10), count: 5),
            spacing: 10
        ) {
            kpiCard(
                title: "Total Tokens",
                value: formatCompactCount(totals.totalTokens),
                subtitle: "\(totals.requests) turns/requests",
                tint: AppTheme.accent
            )
            kpiCard(
                title: "Input Tokens",
                value: formatCompactCount(totals.inputTokens),
                subtitle: "Prompt context",
                tint: AppTheme.info
            )
            kpiCard(
                title: "Output Tokens",
                value: formatCompactCount(totals.outputTokens),
                subtitle: totals.reasoningTokens > 0 ? "+\(formatCompactCount(totals.reasoningTokens)) reasoning" : "Generated tokens",
                tint: AppTheme.merged
            )
            kpiCard(
                title: "Cached Input",
                value: formatCompactCount(totals.cacheReadTokens),
                subtitle: totals.cacheWriteTokens > 0 ? "\(formatCompactCount(totals.cacheWriteTokens)) cache write" : "Prompt cache hits",
                tint: AppTheme.success
            )
            kpiCard(
                title: "Est. API Cost",
                value: formatCurrency(totals.estimatedCostUSD),
                subtitle: "Last \(selectedDays) days",
                tint: AppTheme.warning
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.elevatedCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    // MARK: - 2. Daily SwiftUI Charts Card

    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chartMetric == .tokens ? "Daily Token Usage" : "Daily Estimated API Spend")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text("Last \(selectedDays) Days")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            }

            if parsedDailyPoints.isEmpty {
                ContentUnavailableView(
                    "No Usage Recorded in Period",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Token and cost metrics appear automatically as agents complete turns in Agents.")
                )
                .frame(height: 190)
            } else {
                Chart(parsedDailyPoints) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(
                            chartMetric.rawValue,
                            chartMetric == .tokens ? point.tokens : point.costUSD
                        )
                    )
                    .foregroundStyle(by: .value("Provider", point.providerName))
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if chartMetric == .tokens, let d = value.as(Double.self) {
                                Text(formatCompactCount(Int64(d)))
                            } else if let c = value.as(Double.self) {
                                Text(formatCurrency(c))
                            }
                        }
                    }
                }
                .frame(height: 210)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.elevatedCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    // MARK: - 3. Live Rate-Limit Windows (`RemoteUsage`)

    @ViewBuilder
    private var rateLimitWindowsSection: some View {
        let filteredLimits = appModel.usageLimits.filter {
            selectedProviderFilter == "all" || $0.provider == selectedProviderFilter
        }

        if !filteredLimits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Live Rate-Limit Windows")
                    .font(.system(size: 13.5, weight: .semibold))

                ForEach(filteredLimits) { usage in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            AgentLogoView(provider: usage.provider, size: 15)
                            Text(usage.providerName)
                                .font(.system(size: 12.5, weight: .semibold))
                            if let acct = usage.accountName, !acct.isEmpty {
                                Text("· \(acct)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            Spacer()
                            if let checked = usage.checkedAt {
                                Text("Checked \(checked, style: .relative) ago")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.tertiaryLabel)
                            }
                        }

                        ForEach(usage.windows) { win in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(win.label)
                                        .font(.system(size: 11.5, weight: .medium))
                                    Spacer()
                                    Text("\(Int(win.usedPercent.rounded()))% used")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(tintForPercentage(win.usedPercent))
                                    if let reset = win.resetsAt {
                                        Text("· resets \(reset, style: .relative)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.tertiaryLabel)
                                    }
                                }
                                ProgressView(value: min(100, max(0, win.usedPercent)), total: 100)
                                    .tint(tintForPercentage(win.usedPercent))
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .fill(AppTheme.elevatedCardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - 4. Model & Project Breakdown Lists

    private var breakdownColumnsSection: some View {
        HStack(alignment: .top, spacing: 14) {
            // Models Breakdown
            VStack(alignment: .leading, spacing: 10) {
                Text("By Model")
                    .font(.system(size: 13.5, weight: .semibold))

                if report.models.isEmpty {
                    Text("No model breakdown for this window.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.vertical, 8)
                } else {
                    ForEach(report.models) { row in
                        HStack(spacing: 8) {
                            AgentLogoView(provider: row.provider, size: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.model)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                                Text(AgentBranding.displayName(for: row.provider))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.tertiaryLabel)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatCompactCount(row.totals.totalTokens))
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                Text(formatCurrency(row.totals.estimatedCostUSD))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .fill(AppTheme.elevatedCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )

            // Projects Breakdown
            VStack(alignment: .leading, spacing: 10) {
                Text("By Project")
                    .font(.system(size: 13.5, weight: .semibold))

                if report.projects.isEmpty {
                    Text("No project breakdown for this window.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.vertical, 8)
                } else {
                    ForEach(report.projects) { row in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.info)
                            Text(row.projectName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatCompactCount(row.totals.totalTokens))
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                Text(formatCurrency(row.totals.estimatedCostUSD))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .fill(AppTheme.elevatedCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private func reloadUsage(refreshLimits: Bool) async {
        guard let runtime = appModel.runtime else { return }
        isLoading = true
        defer { isLoading = false }

        let providerArg: String? = selectedProviderFilter == "all" ? nil : selectedProviderFilter
        do {
            async let usageTask = runtime.fetchDesktopUsage(
                days: selectedDays,
                provider: providerArg,
                refresh: refreshLimits
            )
            async let limitsTask = try? runtime.fetchUsageLimits()
            let (fetchedReport, fetchedLimits) = try await (usageTask, limitsTask)
            self.report = fetchedReport
            if let fetchedLimits {
                appModel.usageLimits = fetchedLimits
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private func tintForPercentage(_ pct: Double) -> Color {
        if pct >= 90 { return AppTheme.danger }
        if pct >= 75 { return AppTheme.warning }
        return AppTheme.success
    }

    private func formatCompactCount(_ count: Int64) -> String {
        let absVal = Double(abs(count))
        let sign = count < 0 ? "-" : ""
        if absVal >= 1_000_000_000 {
            return String(format: "%@%.2fB", sign, absVal / 1_000_000_000)
        }
        if absVal >= 1_000_000 {
            return String(format: "%@%.2fM", sign, absVal / 1_000_000)
        }
        if absVal >= 1_000 {
            return String(format: "%@%.1fK", sign, absVal / 1_000)
        }
        return "\(count)"
    }

    private func formatCurrency(_ usd: Double) -> String {
        if usd > 0 && usd < 0.01 {
            return String(format: "$%.4f", usd)
        }
        return String(format: "$%.2f", usd)
    }
}
