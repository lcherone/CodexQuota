import AppKit
import CodexQuotaCore
import SwiftUI

struct MainView: View {
    var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var adding = false
    @State private var draft = ""
    @State private var confirmingRemoval = false

    private var palette: Palette { Palette.current(scheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let note = model.libraryNote {
                        noteLine(note)
                        hairline
                    }
                    if model.store.accounts.isEmpty {
                        emptyState
                    } else if let account = model.selectedAccount {
                        accountBody(account, now: context.date)
                    }
                    hairline
                    footer
                }
            }
            .frame(width: 328)
            .frame(maxHeight: 560)
            .fixedSize(horizontal: true, vertical: true)
        }
        .background(palette.background)
        .onChange(of: model.selectedAccount?.id) {
            confirmingRemoval = false
            adding = false
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
    }

    private var footer: some View {
        HStack {
            Text("Codex Quota")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(palette.ink)
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No accounts yet.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Text("Add a personal or work account. Sign-in opens in the browser, and the Codex home stays on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            addForm
        }
        .padding(12)
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
                signedOut(account, sample: sample, pace: pace)
            } else if sample == nil && model.phase[account.id] == nil {
                waiting(account)
            } else {
                todaySection(sample: sample, pace: pace)
                if let pace {
                    hairline
                    paceSection(pace)
                }
                if let sample, let reached = sample.reached {
                    noteLine(reachedSentence(reached))
                }
            }
            hairline
            accountsSection
            hairline
            historySection(totals, weeks: weeks)
        }
    }

    private func header(_ account: AccountRecord, sample: UsageSample?) -> some View {
        let busy = model.phase[account.id] == .refreshing || model.phase[account.id] == .signingIn
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                if busy {
                    Text(model.phase[account.id] == .signingIn ? "Signing in" : "Checking")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
                plainButton("Refresh", disabled: busy) {
                    Task { await model.refresh(account.id) }
                }
                if model.authRequired.contains(account.id) || sample == nil {
                    plainButton("Sign in", disabled: busy) {
                        Task { await model.signIn(account.id) }
                    }
                } else {
                    plainButton("Sign out", disabled: busy) {
                        Task { await model.signOut(account.id) }
                    }
                }
            }
            Text(metaLine(account, sample: sample))
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func metaLine(_ account: AccountRecord, sample: UsageSample?) -> String {
        var parts = [planLabel(sample?.planType)]
        if let email = sample?.email { parts.append(email) }
        if let sample { parts.append(LondonClock.checkedLine(sample.sampledAt)) }
        if model.authRequired.contains(account.id) { parts.append("Sign in") }
        return parts.joined(separator: " · ")
    }

    private func waiting(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sign in to read this week")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Text("Codex Quota asks the Codex app server for the weekly allowance. The browser sign-in belongs to \(account.label).")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private func signedOut(_ account: AccountRecord, sample: UsageSample?, pace: PaceReport?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sign in to \(account.label)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Text("The previous reading stays on this Mac until the next sign-in.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let pace {
                Text("Last week reading \(Int(pace.weeklyUsedPercent.rounded()))%, reset \(LondonClock.resetLine(pace.reset)).")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let used = sample?.usedPercent {
                Text("Last week reading \(Int(used.rounded()))%.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink)
            }
        }
        .padding(12)
    }

    private func todaySection(sample: UsageSample?, pace: PaceReport?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Today")
            Text(heroNumber(pace: pace, sample: sample))
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .accessibilityLabel(heroAccess(pace: pace, sample: sample))
            Text(heroCaption(pace))
                .font(.system(size: 12))
                .foregroundStyle(palette.ink)
            Text(daySentence(pace))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let pace {
                Text("Week \(Int(pace.weeklyUsedPercent.rounded()))% used. \(weekSentence(pace))")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let used = sample?.usedPercent {
                Text("Week \(Int(used.rounded()))% used.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            if let minutes = sample?.shortDurationMins, let used = sample?.shortUsedPercent {
                Text("\(shortLabel(minutes)) \(Int(used.rounded()))% used.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(12)
    }

    private func paceSection(_ pace: PaceReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Pace")
            Text(pace.weekHasRoom ? "Room later this week" : "Tight later this week")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.ink)
            Text(roomSentence(pace))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                ForEach(pace.slices, id: \.index) { slice in
                    VStack(spacing: 2) {
                        Text(weekday(slice.midpoint))
                        Text(sliceFigure(slice))
                            .monospacedDigit()
                    }
                    .font(.system(size: 10, weight: slice.index == pace.todayIndex ? .semibold : .regular))
                    .foregroundStyle(slice.index == pace.todayIndex ? palette.ink : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(LondonClock.dayLabel(slice.midpoint)) \(slice.points.map { "\(Int($0.rounded())) percent of the week" } ?? "no reading")")
                }
            }
            Text("Each slice is \(String(format: "%.1f", pace.sliceBudget))% of the week. Reset \(LondonClock.resetLine(pace.reset)).")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Accounts")
            ForEach(model.store.accounts) { account in
                accountRow(account)
            }
            if adding {
                addForm
            } else {
                HStack(spacing: 12) {
                    plainButton("Add account") {
                        draft = model.suggestedLabel()
                        adding = true
                        confirmingRemoval = false
                    }
                    if model.selectedAccount != nil {
                        plainButton("Remove") { confirmingRemoval = true }
                    }
                }
            }
            if confirmingRemoval, let account = model.selectedAccount {
                Text("Remove \(account.label) from this Mac? This deletes the Codex home Codex Quota created for that account.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    plainButton("Remove from this Mac") {
                        model.removeAccount(account.id)
                        confirmingRemoval = false
                    }
                    plainButton("Cancel") { confirmingRemoval = false }
                }
            }
        }
        .padding(12)
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        let selected = model.selectedAccount?.id == account.id
        let sample = model.latestSample(for: account.id)
        return Button {
            model.select(account.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.label)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(palette.ink)
                    Text(rowSubtitle(account))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(accountFigure(account, sample: sample))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .overlay(Rectangle().stroke(selected ? palette.hairline : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func historySection(_ totals: UsageTotals, weeks: [WeekStat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Weeks")
            if weeks.isEmpty {
                Text("No week history yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(Array(weeks.prefix(8))) { week in
                    HStack {
                        Text(week.complete ? "Week ending \(LondonClock.dayLabel(week.resetsAt))" : "This week")
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 8)
                        Text("\(Int(week.usedPercent.rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(palette.ink)
                    }
                    .font(.system(size: 12))
                }
            }
            statRow("Lifetime tokens", tokenText(totals.lifetimeTokens))
            statRow("Peak day", tokenText(totals.peakDailyTokens))
            statRow("Recorded tokens", tokenText(totals.recordedTokens))
            statRow("Average week", totals.averageWeeklyPercent.map { "\(Int($0.rounded()))%" } ?? "—")
            Text(totals.weeks == 1 ? "1 week in the library." : "\(totals.weeks) weeks in the library.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
        }
        .padding(12)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(palette.ink)
        }
        .font(.system(size: 12))
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(Rectangle().stroke(palette.hairline, lineWidth: 1))
            HStack(spacing: 12) {
                plainButton("Add") {
                    model.addAccount(label: draft)
                    adding = false
                }
                plainButton("Cancel") { adding = false }
            }
            Text("Sign-in happens after you add it.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
        }
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
            .padding(.vertical, 8)
    }

    private func plainButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.ink)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
    }

    private func rowSubtitle(_ account: AccountRecord) -> String {
        if model.authRequired.contains(account.id) { return "Sign in" }
        if let email = model.latestSample(for: account.id)?.email { return email }
        switch model.phase[account.id] {
        case .refreshing: return "Checking"
        case .signingIn: return "Signing in"
        case let .failed(message): return message
        default: return "Not signed in"
        }
    }

    private func accountFigure(_ account: AccountRecord, sample: UsageSample?) -> String {
        if model.authRequired.contains(account.id) { return "Sign in" }
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
        if slice.kind == .partial { return "≥\(number)" }
        return "\(number)"
    }

    private func heroNumber(pace: PaceReport?, sample: UsageSample?) -> String {
        if let pace, let today = pace.todaySlicePercent, pace.todayKind == .measured || pace.todayKind == .estimated {
            return "\(Int(today.rounded()))%"
        }
        if let pace, let today = pace.todaySlicePercent, pace.todayKind == .partial {
            return "≥\(Int(today.rounded()))%"
        }
        if let used = sample?.usedPercent {
            return "\(Int(used.rounded()))%"
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
            return pace == nil ? "of the weekly allowance" : "of today's slice"
        }
    }

    private func heroAccess(pace: PaceReport?, sample: UsageSample?) -> String {
        "\(heroNumber(pace: pace, sample: sample)). \(daySentence(pace))"
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

    private func weekSentence(_ pace: PaceReport) -> String {
        switch pace.weekLinearStatus {
        case .over: return "The week is ahead of an even split."
        case .under: return "The week is behind an even split."
        case .on: return "The week is on an even split."
        case .unknown: return "The week's even split is still unknown."
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
