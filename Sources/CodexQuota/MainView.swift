import AppKit
import CodexQuotaCore
import CodexQuotaModel
import SwiftUI

struct MainView: View {
    var model: AppModel
    var availableHeight: CGFloat = 640
    @Environment(\.colorScheme) private var scheme
    @State private var adding = false
    @State private var renaming = false
    @State private var draft = ""
    @State private var confirmingRemoval = false
    @State private var dailyExpanded = false
    @State private var weeklyHistoryExpanded = false
    @FocusState private var nameFocused: Bool

    private var palette: Palette { Palette.current(resolvedScheme) }

    private var resolvedScheme: ColorScheme {
        switch model.store.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return scheme
        }
    }

    private var forcedScheme: ColorScheme? {
        switch model.store.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let note = model.libraryNote {
                            noteLine(note)
                        }
                        if model.store.accounts.isEmpty {
                            emptyState
                        } else if let account = model.selectedAccount {
                            accountBody(account, now: context.date)
                        }
                    }
                }
                .frame(maxHeight: max(PanelMetrics.minimumScrollHeight, availableHeight - PanelMetrics.footerAllowance))
                hairline
                footer
            }
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: true, vertical: true)
        }
        .background(palette.background)
        .preferredColorScheme(forcedScheme)
        .background(AppearanceAnchor(choice: model.store.appearance))
        .onChange(of: model.selectedAccount?.id) {
            confirmingRemoval = false
            adding = false
            renaming = false
            dailyExpanded = false
            weeklyHistoryExpanded = false
        }
        .onChange(of: adding) {
            if !adding { nameFocused = false }
        }
        .onChange(of: renaming) {
            if !renaming { nameFocused = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.loginItem.refresh()
            Task { await model.refreshAlertPermission() }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            startupSection
            alertsSection
            HStack(spacing: 8) {
                Picker("Appearance", selection: Binding(
                    get: { model.store.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    Text("System").tag(PanelAppearance.system)
                    Text("Light").tag(PanelAppearance.light)
                    Text("Dark").tag(PanelAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(palette.ink)
                .frame(maxWidth: 210)
                .disabled(!model.libraryReady)
                Spacer(minLength: 8)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 10)
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { model.loginItem.isEnabled },
                set: { model.loginItem.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .tint(palette.ink)
            .disabled(!model.loginItem.canConfigure)
            if !model.loginItem.canConfigure {
                Text("Install in Applications to enable startup.")
                    .foregroundStyle(palette.secondary)
            }
            if model.loginItem.needsApproval {
                Text("Allow Codex Quota in Login Items to finish setup.")
                    .foregroundStyle(palette.secondary)
                actionButton("Open Login Items", icon: "gearshape") { model.loginItem.openSettings() }
            }
            if let error = model.loginItem.error {
                Text(error)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                actionButton("Open Login Items", icon: "gearshape") { model.loginItem.openSettings() }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Quota alerts", isOn: Binding(
                get: { model.alertsEnabled },
                set: { enabled in Task { await model.setAlertsEnabled(enabled) } }
            ))
            .toggleStyle(.checkbox)
            .tint(palette.ink)
            .disabled(!model.libraryReady || model.alertPermission == .unavailable)
            if model.alertsEnabled {
                Stepper(
                    "Weekly threshold: \(model.store.alertPreferences.weeklyThreshold)%",
                    value: Binding(
                        get: { model.store.alertPreferences.weeklyThreshold },
                        set: { model.setAlertThreshold($0) }
                    ),
                    in: QuotaAlertPreferences.supportedThresholds,
                    step: 5
                )
                .accessibilityLabel("Weekly quota alert threshold")
                .accessibilityValue("\(model.store.alertPreferences.weeklyThreshold) percent")
            }
            if model.alertPermission == .denied {
                Text("Alerts are off. Allow Codex Quota notifications in System Settings.")
                    .foregroundStyle(palette.secondary)
                actionButton("Open Notification Settings", icon: "gearshape") {
                    model.openNotificationSettings()
                }
            } else if model.alertPermission == .unavailable {
                Text("Notifications are unavailable on this Mac.")
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No accounts yet.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text("Each account keeps its own Codex home on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            if adding {
                addForm
            } else {
                actionButton("Add account", icon: "plus", disabled: !model.libraryReady) {
                    draft = model.suggestedLabel()
                    adding = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func accountBody(_ account: AccountRecord, now: Date) -> some View {
        let sample = model.latestSample(for: account.id)
        let pace = sample.flatMap { model.paceReport(for: account.id, sample: $0, now: now) }
        let weeks = UsageStats.weeks(samples: model.samples(for: account.id), now: now)
        let totals = UsageStats.totals(samples: model.samples(for: account.id), now: now)
        return VStack(alignment: .leading, spacing: 0) {
            header(account, sample: sample)
            if let message = model.banners[account.id] {
                noteLine(message)
            }
            if sample?.optionalStatisticsArePartial == true {
                noteLine(partialStatisticsNotice(sample))
            }
            if case let .failed(message) = model.phase[account.id] {
                noteLine(message)
            }
            if model.phase[account.id] == .signingIn {
                noteLine("Finish sign-in in the browser. This panel updates when Codex confirms the account.")
            }
            if model.isStale(sample, now: now), model.phase[account.id] != .refreshing {
                noteLine("This reading is getting old. Refresh to check the allowance again.")
            }
            hairline
            if model.authRequired.contains(account.id) {
                signedOut(account, sample: sample, pace: pace, now: now)
            } else if sample == nil {
                waiting(account)
            } else {
                todaySection(sample: sample, pace: pace)
                if let pace {
                    paceSection(pace)
                }
                if let sample, let reached = sample.reached {
                    noteLine(reachedSentence(reached))
                }
            }
            hairline
            accountsSection
            hairline
            historySection(totals, weeks: weeks, sample: sample)
        }
    }

    private func header(_ account: AccountRecord, sample: UsageSample?) -> some View {
        let busy = model.isBusy(account.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(account.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                if busy {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.phase[account.id] == .signingIn ? "Signing in" : "Checking")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
            }
            HStack(spacing: 8) {
                actionButton("Refresh", icon: "arrow.clockwise", disabled: busy || !model.libraryReady) {
                    Task { await model.refresh(account.id) }
                }
                if model.phase[account.id] == .signingIn {
                    actionButton("Cancel sign-in", icon: "xmark.circle") {
                        model.cancelSignIn(account.id)
                    }
                } else if model.authRequired.contains(account.id) || sample == nil {
                    actionButton("Sign in", icon: "person.crop.circle.badge.plus", prominent: true, disabled: busy || !model.libraryReady) {
                        model.signIn(account.id)
                    }
                } else {
                    actionButton("Sign out", icon: "rectangle.portrait.and.arrow.right", disabled: busy || !model.libraryReady) {
                        Task { await model.signOut(account.id) }
                    }
                }
                Spacer(minLength: 0)
            }
            Text(metaLine(account, sample: sample))
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 10)
    }

    private func metaLine(_ account: AccountRecord, sample: UsageSample?) -> String {
        var parts: [String] = []
        if let sample {
            parts.append(planLabel(sample.planType))
            if let email = sample.email { parts.append(email) }
            parts.append(LondonClock.checkedLine(sample.sampledAt))
        } else if model.authRequired.contains(account.id) {
            parts.append("Signed out")
        } else {
            parts.append("No reading yet")
        }
        return parts.joined(separator: " · ")
    }

    private func partialStatisticsNotice(_ sample: UsageSample?) -> String {
        if let checkedAt = sample?.optionalStatisticsSampledAt {
            return "Quota refreshed. Usage stats are from an older check (\(LondonClock.checkedLine(checkedAt))). Refresh to retry."
        }
        return "Quota refreshed, but usage stats are unavailable because that check failed. Refresh to retry."
    }

    private func waiting(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.phase[account.id] == .refreshing ? "Checking \(account.label)" : "No reading yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Text("Refresh reads the allowance. Sign in if Codex asks for this account.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func signedOut(_ account: AccountRecord, sample: UsageSample?, pace: PaceReport?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Signed out")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Text("The last reading stays on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            if let pace {
                Text(lastReading(pace, now: now))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let used = sample?.usedPercent {
                Text("Last reading \(Int(used.rounded()))%.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func lastReading(_ pace: PaceReport, now: Date) -> String {
        let used = Int(pace.weeklyUsedPercent.rounded())
        if pace.reset > now {
            return "Last reading \(used)%. Resets \(LondonClock.resetLine(pace.reset))."
        }
        return "Last reading \(used)%. Reset \(LondonClock.resetLine(pace.reset))."
    }

    private func todaySection(sample: UsageSample?, pace: PaceReport?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 20) {
                metricBlock(
                    "Today",
                    heroNumber(pace: pace, sample: sample),
                    heroCaption(pace),
                    access: heroAccess(pace: pace, sample: sample)
                )
                metricBlock(
                    "Week",
                    weekNumber(pace: pace, sample: sample),
                    weekCaption(pace)
                )
                Spacer(minLength: 0)
            }
            Text(statusLine(pace))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let minutes = sample?.shortDurationMins, let used = sample?.shortUsedPercent {
                Text("\(shortLabel(minutes)) \(Int(used.rounded()))% used.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 12)
    }

    private func metricBlock(_ title: String, _ value: String, _ caption: String, access: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionTitle(title)
            Text(value)
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .accessibilityLabel(access ?? "\(title) \(value). \(caption)")
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
                .frame(maxWidth: 148, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(access ?? "\(title) \(value). \(caption)")
    }

    private func paceSection(_ pace: PaceReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(pace.slices, id: \.index) { slice in
                    let current = slice.index == pace.todayIndex
                    VStack(spacing: 1) {
                        Text(weekday(slice.start))
                        Text(sliceFigure(slice))
                            .monospacedDigit()
                    }
                    .font(.system(size: 11, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? palette.ink : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(current ? palette.ink.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(current ? "Current slice, " : "")\(LondonClock.dayLabel(slice.start)), \(slice.points.map { "\(Int($0.rounded())) percent of the week" } ?? "no reading available")")
                }
            }
            Text("\(pace.weekHasRoom ? "Room later this week" : "Tight later this week"). \(roomSentence(pace))")
                .font(.system(size: 12))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Boxed slice is in progress. Numbers are % of the week. Resets \(LondonClock.resetLine(pace.reset)).")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Accounts")
            ForEach(model.store.accounts) { account in
                accountRow(account)
            }
            if adding {
                addForm
            } else if renaming {
                renameForm
            } else {
                HStack(spacing: 12) {
                    actionButton("Add account", icon: "plus", disabled: !model.libraryReady) {
                        draft = model.suggestedLabel()
                        adding = true
                        renaming = false
                        confirmingRemoval = false
                    }
                    if let account = model.selectedAccount {
                        actionButton("Rename", icon: "pencil", disabled: !model.libraryReady) {
                            draft = account.label
                            renaming = true
                            adding = false
                            confirmingRemoval = false
                        }
                        actionButton("Remove", icon: "trash", destructive: true, disabled: model.isBusy(account.id) || !model.libraryReady) {
                            confirmingRemoval = true
                            renaming = false
                        }
                    }
                }
            }
            if confirmingRemoval, let account = model.selectedAccount {
                Text("Remove \(account.label) from this Mac? This deletes the Codex home Codex Quota created for that account.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        model.removeAccount(account.id)
                        confirmingRemoval = false
                    } label: {
                        Label("Remove from this Mac", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(palette.ink)
                    .disabled(model.isBusy(account.id) || !model.libraryReady)
                    Button("Cancel") { confirmingRemoval = false }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        let selected = model.selectedAccount?.id == account.id
        let sample = model.latestSample(for: account.id)
        return Button {
            model.select(account.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? palette.ink : palette.secondary)
                Text(account.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(palette.ink)
                Text(rowSubtitle(account))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(accountFigure(account, sample: sample))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: PanelMetrics.controlHeight)
            .contentShape(Rectangle())
            .background(selected ? palette.ink.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.libraryReady)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.label). \(rowSubtitle(account)). \(accountFigure(account, sample: sample))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func historySection(_ totals: UsageTotals, weeks: [WeekStat], sample: UsageSample?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle("Weeks")
                Spacer()
                Text(totals.weeks == 1 ? "1 in the library" : "\(totals.weeks) in the library")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
            }
            if weeks.isEmpty {
                Text("No week history yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(Array(weeks.prefix(6))) { week in
                    weekHistoryRow(week)
                }
                if weeks.count > 6 {
                    DisclosureGroup(isExpanded: $weeklyHistoryExpanded) {
                        ForEach(Array(weeks.dropFirst(6))) { week in
                            weekHistoryRow(week)
                        }
                    } label: {
                        Text(weeklyHistoryExpanded ? "Show fewer weeks" : "Show all \(weeks.count) weeks")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink)
                    .tint(palette.secondary)
                    .accessibilityLabel("Weekly history")
                    .accessibilityValue(weeklyHistoryExpanded
                        ? "Expanded, showing \(weeks.count) of \(weeks.count) rows"
                        : "Collapsed, showing 6 of \(weeks.count) rows")
                }
            }
            sectionTitle("Usage stats")
                .padding(.top, 8)
            if let checkedAt = sample?.optionalStatisticsSampledAt {
                Text(LondonClock.checkedLine(checkedAt).replacingOccurrences(of: "Checked", with: "Statistics checked"))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                tokenCell("Lifetime tokens", totals.lifetimeTokens)
                tokenCell("Peak day tokens", totals.peakDailyTokens)
                tokenCell("Recorded tokens", totals.recordedTokens,
                          context: "Sum of daily token totals retained in this Mac's library.")
                completedWeekCell(totals)
                summaryCell("Current week", totals.currentWeekPercent.map { "\(Int($0.rounded()))%" } ?? "—",
                            detail: "Allowance used in the current open week. This partial week is not included in the completed-week average.")
                summaryCell("Current streak", dayCount(sample?.currentStreakDays),
                            detail: dayCount(sample?.currentStreakDays, exact: true))
                summaryCell("Longest streak", dayCount(sample?.longestStreakDays),
                            detail: dayCount(sample?.longestStreakDays, exact: true))
                summaryCell("Longest turn", UsageFormatting.duration(sample?.longestRunningTurnSec),
                            detail: "\(UsageFormatting.exact(sample?.longestRunningTurnSec)) seconds")
            }
            .padding(.top, 4)
            Text("— means the stat wasn't supplied. Hover for exact values.")
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .padding(.top, 4)
            DisclosureGroup("Daily tokens · \(dayCount(Int64(sample?.dailyBuckets.count ?? 0)))", isExpanded: $dailyExpanded) {
                if let buckets = sample?.dailyBuckets, !buckets.isEmpty {
                    ForEach(Array(buckets.sorted { $0.startDate > $1.startDate }.enumerated()), id: \.offset) { _, bucket in
                        HStack {
                            Text(bucket.startDate)
                            Spacer(minLength: 8)
                            Text(UsageFormatting.compact(bucket.tokens))
                                .monospacedDigit()
                        }
                        .help("\(bucket.startDate): \(UsageFormatting.exact(bucket.tokens)) tokens")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(bucket.startDate): \(UsageFormatting.exact(bucket.tokens)) tokens")
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("No daily token totals supplied.")
                        .foregroundStyle(palette.secondary)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.ink)
            .tint(palette.secondary)
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func weekHistoryRow(_ week: WeekStat) -> some View {
        HStack(spacing: 8) {
            Text(week.complete ? "Ended \(LondonClock.dayLabel(week.resetsAt))" : "Resets \(LondonClock.dayLabel(week.resetsAt))")
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Int(week.usedPercent.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private func completedWeekCell(_ totals: UsageTotals) -> some View {
        if let average = totals.completedWeekAveragePercent {
            summaryCell("Completed-week avg", "\(Int(average.rounded()))%",
                        detail: "Average allowance used across completed weeks in this Mac's library.")
        } else if let current = totals.currentWeekPercent {
            summaryCell("Partial-week fallback", "\(Int(current.rounded()))%",
                        detail: "No completed week is available, so this is the current open week's partial usage.")
        } else {
            summaryCell("Completed-week avg", "—",
                        detail: "No completed or current week usage is available.")
        }
    }

    private func tokenCell(_ title: String, _ value: Int64?, context: String = "") -> some View {
        summaryCell(title, UsageFormatting.compact(value),
                    detail: "\(UsageFormatting.exact(value)) tokens. \(context)")
    }

    private func dayCount(_ value: Int64?, exact: Bool = false) -> String {
        guard let value else { return "—" }
        let number = exact ? UsageFormatting.exact(value) : UsageFormatting.compact(value)
        return "\(number) \(value == 1 ? "day" : "days")"
    }

    private func summaryCell(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title): \(value == "—" ? "Not available" : detail)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryDescription(title, value: value, detail: detail))
    }

    private func summaryDescription(_ title: String, value: String, detail: String) -> String {
        if value == "—" { return "\(title): Not available" }
        if value == detail { return "\(title): \(value)" }
        return "\(title): \(value). \(detail)"
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $draft)
                .focused($nameFocused)
                .task { nameFocused = true }
                .onSubmit { addDraftAccount() }
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink)
                .tint(palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(Rectangle().stroke(palette.hairline, lineWidth: 1))
                .disabled(!model.libraryReady)
            HStack(spacing: 12) {
                Button("Add") {
                    addDraftAccount()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(palette.ink)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.libraryReady)
                Button("Cancel") { adding = false }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var renameForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $draft)
                .focused($nameFocused)
                .task { nameFocused = true }
                .onSubmit { renameSelectedAccount() }
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink)
                .tint(palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(Rectangle().stroke(palette.hairline, lineWidth: 1))
                .disabled(!model.libraryReady)
            HStack(spacing: 12) {
                Button("Save") { renameSelectedAccount() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(palette.ink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.libraryReady)
                Button("Cancel") {
                    renaming = false
                    draft = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func addDraftAccount() {
        model.addAccount(label: draft)
        adding = false
        draft = ""
    }

    private func renameSelectedAccount() {
        if let account = model.selectedAccount {
            model.renameAccount(account.id, label: draft)
        }
        renaming = false
        draft = ""
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(palette.secondary)
    }

    private func noteLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            actionButtonLabel(title, icon: icon, destructive: destructive, disabled: disabled, action: action)
                .buttonStyle(.borderedProminent)
                .tint(palette.ink)
        } else {
            actionButtonLabel(title, icon: icon, destructive: destructive, disabled: disabled, action: action)
                .buttonStyle(.bordered)
        }
    }

    private func actionButtonLabel(
        _ title: String,
        icon: String,
        destructive: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Label(title, systemImage: icon)
        }
            .controlSize(.small)
            .frame(minHeight: PanelMetrics.controlHeight)
            .disabled(disabled)
    }

    private func rowSubtitle(_ account: AccountRecord) -> String {
        if model.authRequired.contains(account.id) { return "Signed out" }
        if let email = model.latestSample(for: account.id)?.email { return email }
        switch model.phase[account.id] {
        case .refreshing: return "Checking"
        case .signingIn: return "Signing in"
        case let .failed(message): return message
        default: return "Not signed in"
        }
    }

    private func accountFigure(_ account: AccountRecord, sample: UsageSample?) -> String {
        guard let used = sample?.usedPercent else { return "—" }
        return "\(Int(used.rounded()))%"
    }

    private func weekday(_ date: Date) -> String {
        let calendar = LondonClock.calendar()
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.indices.contains(index) else { return LondonClock.dayLabel(date) }
        return String(symbols[index].prefix(2))
    }

    private func sliceFigure(_ slice: PaceSlice) -> String {
        guard let points = slice.points else { return "—" }
        let number = Int(points.rounded())
        if slice.kind == .partial { return "≥\(number)%" }
        return "\(number)%"
    }

    private func weekNumber(pace: PaceReport?, sample: UsageSample?) -> String {
        if let pace { return "\(Int(pace.weeklyUsedPercent.rounded()))%" }
        if let used = sample?.usedPercent { return "\(Int(used.rounded()))%" }
        return "—"
    }

    private func weekCaption(_ pace: PaceReport?) -> String {
        switch pace?.weekLinearStatus {
        case .over: return "used · ahead"
        case .under: return "used · behind"
        case .on: return "used · even"
        default: return "of the allowance"
        }
    }

    private func statusLine(_ pace: PaceReport?) -> String {
        daySentence(pace)
    }

    private func heroNumber(pace: PaceReport?, sample: UsageSample?) -> String {
        if let pace, let today = pace.todaySlicePercent, pace.todayKind == .measured || pace.todayKind == .estimated {
            return "\(Int(today.rounded()))%"
        }
        if let pace, let today = pace.todaySlicePercent, pace.todayKind == .partial {
            return "≥\(Int(today.rounded()))%"
        }
        return "—"
    }

    private func heroCaption(_ pace: PaceReport?) -> String {
        switch pace?.todayKind {
        case .measured, .estimated:
            return "of today's slice"
        case .partial:
            return "of today's slice, at least"
        default:
            return "of today's slice"
        }
    }

    private func heroAccess(pace: PaceReport?, sample: UsageSample?) -> String {
        "Today \(heroNumber(pace: pace, sample: sample)). \(daySentence(pace))"
    }

    private func daySentence(_ pace: PaceReport?) -> String {
        guard let pace else { return "Today's slice appears when the weekly window has a reset time." }
        switch (pace.dayStatus, pace.todayKind) {
        case (.over, .partial):
            return "Today is already ahead of this slice."
        case (.over, _):
            return pace.todayKind == .estimated ? "Today is ahead of this slice, estimated from daily tokens." : "Today is ahead of this slice."
        case (.under, _):
            return pace.todayKind == .estimated ? "Today is inside this slice, estimated from daily tokens." : "Today is inside this slice."
        case (.on, _):
            return pace.todayKind == .estimated ? "Today is on this slice, estimated from daily tokens." : "Today is on this slice."
        case (.unknown, .partial):
            return "Today's slice is still filling in."
        default:
            return "Today's slice appears after another check in this window."
        }
    }

    private func roomSentence(_ pace: PaceReport) -> String {
        if pace.futureFullSlices == 0 {
            return "This is the last slice before the reset."
        }
        if pace.weekHasRoom {
            return "The remaining days can still each take a full slice."
        }
        return "The remaining days are short of a full slice."
    }

    private func shortLabel(_ minutes: Double) -> String {
        let hours = Int((minutes / 60).rounded())
        if hours == 5 { return "Five-hour window" }
        return "\(hours)-hour window"
    }
}

private struct AppearanceAnchor: NSViewRepresentable {
    var choice: PanelAppearance

    func makeNSView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.choice = choice
        return view
    }

    func updateNSView(_ view: AppearanceView, context: Context) {
        view.choice = choice
    }
}

private final class AppearanceView: NSView {
    var choice: PanelAppearance = .system {
        didSet { apply() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        window?.appearance = switch choice {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
