import CodexQuotaCore
import SwiftUI

struct MainView: View {
    var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var adding = false
    @State private var draft = ""
    @State private var pendingRemoval: AccountRecord?

    private var palette: Palette { Palette.current(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(palette.hairline)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
        }
        .background(palette.background)
        .frame(minWidth: 880, minHeight: 620)
        .sheet(isPresented: $adding) {
            addSheet
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.label ?? "this account")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from this Mac", role: .destructive) {
                if let pendingRemoval { model.removeAccount(pendingRemoval.id) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This deletes the Codex home Codex Quota created for that account. Tokens stay out of the library.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Quota")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text("Weekly allowance, one slice a day.")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            if model.store.accounts.isEmpty {
                Text("No accounts yet.")
                    .font(.callout)
                    .foregroundStyle(palette.muted)
                    .padding(.top, 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.store.accounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                draft = model.suggestedLabel()
                adding = true
            } label: {
                Label("Add account", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            Text("Each account has its own Codex home on this Mac.")
                .font(.caption2)
                .foregroundStyle(palette.muted)
        }
        .padding(20)
        .frame(width: 250)
        .background(palette.sidebar)
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        let selected = model.selectedAccount?.id == account.id
        let samples = model.latestSample(for: account.id)
        return Button {
            model.select(account.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.ink)
                    Text(rowSubtitle(account))
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                if let used = samples?.usedPercent, !model.authRequired.contains(account.id) {
                    Text("\(Int(used.rounded()))%")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(palette.ink)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? palette.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? palette.hairline : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from this Mac", role: .destructive) { pendingRemoval = account }
        }
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

    @ViewBuilder
    private var detail: some View {
        if let note = model.libraryNote {
            VStack(alignment: .leading, spacing: 16) {
                noteBanner(note)
                detailBody
            }
            .padding(28)
        } else {
            detailBody
                .padding(28)
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        if model.store.accounts.isEmpty {
            emptyState
        } else if let account = model.selectedAccount {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                accountDetail(account, now: context.date)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Watch a weekly allowance")
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .foregroundStyle(palette.ink)
            Text("Add a personal or work account. Sign-in opens in the browser, and the Codex home stays on this Mac.")
                .font(.title3)
                .foregroundStyle(palette.muted)
                .frame(maxWidth: 460, alignment: .leading)
            Button("Add account") {
                draft = model.suggestedLabel()
                adding = true
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountDetail(_ account: AccountRecord, now: Date) -> some View {
        let sample = model.latestSample(for: account.id)
        let pace = sample.flatMap { model.paceReport(for: account.id, sample: $0, now: now) }
        let weeks = UsageStats.weeks(samples: model.samples(for: account.id), now: now)
        let totals = UsageStats.totals(samples: model.samples(for: account.id), now: now)
        let busy = model.phase[account.id] == .refreshing || model.phase[account.id] == .signingIn
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(account, sample: sample, busy: busy)
                if let message = model.banners[account.id] {
                    noteBanner(message)
                }
                if case let .failed(message) = model.phase[account.id] {
                    noteBanner(message)
                }
                if model.phase[account.id] == .signingIn {
                    noteBanner("Finish sign-in in the browser. This window will update when Codex confirms the account.")
                }
                if model.isStale(sample, now: now), model.phase[account.id] != .refreshing {
                    noteBanner("This reading is getting old. Refresh to check the allowance again.")
                }
                if model.authRequired.contains(account.id) {
                    signedOut(account, sample: sample, pace: pace)
                } else if sample == nil && model.phase[account.id] == nil {
                    waiting(account)
                } else {
                    hero(sample: sample, pace: pace)
                    if let pace {
                        slices(pace)
                        room(pace)
                    }
                    if let sample, let reached = sample.reached {
                        noteBanner(reachedSentence(reached))
                    }
                    stats(totals, weeks: weeks)
                }
            }
        }
    }

    private func header(_ account: AccountRecord, sample: UsageSample?, busy: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.label)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(palette.ink)
                HStack(spacing: 8) {
                    Text(planLabel(sample?.planType))
                    if let email = sample?.email {
                        Text(email)
                    }
                    if let sample {
                        Text(LondonClock.checkedLine(sample.sampledAt))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(palette.muted)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button("Refresh") { Task { await model.refresh(account.id) } }
                .disabled(busy)
                .keyboardShortcut("r", modifiers: .command)
            if model.authRequired.contains(account.id) || sample == nil {
                Button("Sign in") { Task { await model.signIn(account.id) } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(busy)
            } else {
                Button("Sign out") { Task { await model.signOut(account.id) } }
                    .disabled(busy)
            }
        }
    }

    private func waiting(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to read this week")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.ink)
            Text("Codex Quota asks the Codex app server for the weekly allowance. The browser sign-in belongs to \(account.label).")
                .foregroundStyle(palette.muted)
                .frame(maxWidth: 480, alignment: .leading)
        }
        .quotaCard(palette)
    }

    private func signedOut(_ account: AccountRecord, sample: UsageSample?, pace: PaceReport?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in to \(account.label)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.ink)
            Text("The previous reading stays on this Mac until the next sign-in.")
                .foregroundStyle(palette.muted)
            if let pace {
                Text("Last week reading \(Int(pace.weeklyUsedPercent.rounded()))%, reset \(LondonClock.resetLine(pace.reset)).")
                    .foregroundStyle(palette.ink)
            } else if let used = sample?.usedPercent {
                Text("Last week reading \(Int(used.rounded()))%.")
                    .foregroundStyle(palette.ink)
            }
        }
        .quotaCard(palette)
    }

    private func hero(sample: UsageSample?, pace: PaceReport?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heroNumber(pace: pace, sample: sample))
                .font(.system(size: 72, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(heroColor(pace))
                .accessibilityLabel(heroAccess(pace: pace, sample: sample))
            Text(heroCaption(pace))
                .font(.title3)
                .foregroundStyle(palette.ink)
            if let pace {
                Text(daySentence(pace))
                    .font(.body)
                    .foregroundStyle(palette.muted)
                Text("Week \(Int(pace.weeklyUsedPercent.rounded()))% used. \(weekSentence(pace))")
                    .font(.body)
                    .foregroundStyle(palette.muted)
            } else if let used = sample?.usedPercent {
                Text("Week \(Int(used.rounded()))% used.")
                    .foregroundStyle(palette.muted)
            }
            if let minutes = sample?.shortDurationMins, let used = sample?.shortUsedPercent {
                Text("\(shortLabel(minutes)) \(Int(used.rounded()))% used.")
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
        }
        .quotaCard(palette)
    }

    private func slices(_ pace: PaceReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week")
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("Each slice is \(String(format: "%.1f", pace.sliceBudget))% of the week")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(pace.slices, id: \.index) { slice in
                    VStack(spacing: 8) {
                        sliceColumn(slice, today: slice.index == pace.todayIndex, budget: pace.sliceBudget)
                        Text(LondonClock.dayLabel(slice.midpoint))
                            .font(.caption2)
                            .foregroundStyle(slice.index == pace.todayIndex ? palette.ink : palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Reset \(LondonClock.resetLine(pace.reset)). Days are equal slices of that window, named in London.")
                .font(.caption)
                .foregroundStyle(palette.muted)
        }
        .quotaCard(palette)
    }

    private func sliceColumn(_ slice: PaceSlice, today: Bool, budget: Double) -> some View {
        let fraction = min(1, max(0, (slice.points ?? 0) / budget))
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.hairline.opacity(0.65))
            if slice.points != nil {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(columnColor(slice, today: today).opacity(slice.kind == .estimated ? 0.55 : 1))
                    .frame(height: max(6, 96 * fraction))
            }
        }
        .frame(height: 96)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(today ? palette.accent : Color.clear, lineWidth: 2)
        )
        .accessibilityLabel("\(LondonClock.dayLabel(slice.midpoint)) \(slice.points.map { "\(Int($0.rounded())) percent of the week" } ?? "no reading")")
    }

    private func room(_ pace: PaceReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pace.weekHasRoom ? "Room later this week" : "Tight later this week")
                .font(.headline)
                .foregroundStyle(palette.ink)
            Text(roomSentence(pace))
                .foregroundStyle(palette.muted)
        }
        .quotaCard(palette)
    }

    private func stats(_ totals: UsageTotals, weeks: [WeekStat]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("On this Mac")
                .font(.headline)
                .foregroundStyle(palette.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                metric("Lifetime tokens", tokenText(totals.lifetimeTokens))
                metric("Peak day", tokenText(totals.peakDailyTokens))
                metric("Recorded tokens", tokenText(totals.recordedTokens))
                metric("Average week", totals.averageWeeklyPercent.map { "\(Int($0.rounded()))%" } ?? "—")
            }
            Text(totals.weeks == 1 ? "1 week in the library." : "\(totals.weeks) weeks in the library.")
                .font(.caption)
                .foregroundStyle(palette.muted)
            if !weeks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(weeks.prefix(8))) { week in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(week.complete ? "Week ending \(LondonClock.dayLabel(week.resetsAt))" : "This week")
                                    .foregroundStyle(palette.ink)
                                Spacer()
                                Text("\(Int(week.usedPercent.rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(palette.muted)
                            }
                            .font(.subheadline)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(palette.hairline)
                                    Capsule()
                                        .fill(palette.accent)
                                        .frame(width: geo.size.width * week.usedPercent / 100)
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                }
            }
        }
        .quotaCard(palette)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.muted)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.ink)
        }
    }

    private func noteBanner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(palette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.hairline))
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add account")
                .font(.title2.weight(.semibold))
            Text("Name it however you like. Personal and Work are the usual pair. Sign-in happens after you add it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { adding = false }
                Spacer()
                Button("Add") {
                    model.addAccount(label: draft)
                    adding = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
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

    private func heroColor(_ pace: PaceReport?) -> Color {
        switch pace?.dayStatus {
        case .over: return palette.over
        case .under: return palette.accent
        case .on: return palette.onPace
        default: return palette.ink
        }
    }

    private func heroAccess(pace: PaceReport?, sample: UsageSample?) -> String {
        let number = heroNumber(pace: pace, sample: sample)
        return "\(number). \(daySentence(pace))"
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

    private func columnColor(_ slice: PaceSlice, today: Bool) -> Color {
        if slice.kind == .partial { return palette.onPace }
        if today { return palette.accent }
        return palette.accent
    }

    private func shortLabel(_ minutes: Double) -> String {
        let hours = Int((minutes / 60).rounded())
        if hours == 5 { return "Five-hour window" }
        return "\(hours)-hour window"
    }
}
