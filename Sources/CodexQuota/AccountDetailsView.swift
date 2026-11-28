import CodexQuotaCore
import CodexQuotaModel
import Foundation
import SwiftUI

enum AccountTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case limits = "Limits"
    case usage = "Usage"
    case activity = "Activity"
    var id: String { rawValue }
}

struct DetailsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

struct DetailsField: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
    }
}

enum DetailsFormatting {
    static func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "Not supplied"
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "Not supplied" }
        let formatter = DateFormatter()
        formatter.timeZone = LondonClock.zone
        formatter.dateFormat = "d MMM yyyy, HH:mm z"
        return formatter.string(from: value)
    }

    static func reset(_ value: Date?, now: Date) -> String {
        guard let value else { return "Reset time not supplied" }
        guard value > now else { return "Reset time passed · refresh for the current window" }
        let seconds = max(0, value.timeIntervalSince(now))
        let days = Int(seconds / 86_400)
        let hours = Int(seconds / 3_600) % 24
        let minutes = Int(seconds / 60) % 60
        let remaining = days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes)m"
        return "Resets in \(remaining) · \(date(value))"
    }

    static func micros(_ value: Int64?, dollars: Bool = false) -> String {
        guard let value else { return "Not supplied" }
        let amount = Decimal(value) / 1_000_000
        return (dollars ? "$" : "") + amount.formatted(.number.precision(.fractionLength(0...6))) + (dollars ? " USD" : " credits")
    }
}

struct LimitsDetailsView: View {
    @Environment(\.colorScheme) private var scheme
    var details: QuotaDetails?
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("All quota buckets returned for this account. Missing values are unavailable, not zero.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let details {
                if details.buckets.isEmpty {
                    DetailsSection(title: "Quota windows") {
                        Text("No quota buckets were supplied.").font(.system(size: 12))
                    }
                }
                ForEach(details.buckets) { bucket in
                    DetailsSection(title: planLabel(bucket.name)) {
                        DetailsField(label: "Limit ID", value: bucket.id)
                        DetailsField(label: "Plan", value: bucket.plan.map(planLabel) ?? "Not supplied")
                        if let reached = bucket.reached {
                            Text(reachedSentence(reached)).font(.system(size: 12))
                        }
                        window(bucket.primary, slot: "Primary window")
                        window(bucket.secondary, slot: "Secondary window")
                        DisclosureGroup("Credits and monthly limit") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Credits and monthly spending controls are separate from the quota windows above.")
                                    .foregroundStyle(.secondary)
                                if let credits = bucket.credits {
                                    DetailsField(label: "Credit balance", value: credits.unlimited == true ? "Unlimited" : credits.balance ?? "Not supplied")
                                    DetailsField(label: "Credits available", value: credits.hasCredits.map { $0 ? "Yes" : "No" } ?? "Not supplied")
                                    DetailsField(label: "Unlimited credits", value: credits.unlimited.map { $0 ? "Yes" : "No" } ?? "Not supplied")
                                } else {
                                    Text("Credit balance not supplied.")
                                }
                                if let monthly = bucket.monthlyLimit {
                                    DetailsField(label: "Monthly credit limit", value: monthly.limit ?? "Not supplied")
                                    DetailsField(label: "Credits used", value: monthly.used ?? "Not supplied")
                                    DetailsField(label: "Remaining", value: DetailsFormatting.percent(monthly.remainingPercent))
                                    Text(DetailsFormatting.reset(monthly.resetsAt, now: now))
                                } else {
                                    Text("No monthly credit limit supplied.")
                                }
                                DetailsField(label: "Spending control reached", value: bucket.spendControlReached.map { $0 ? "Yes" : "No" } ?? "Not supplied")
                            }
                            .font(.system(size: 11))
                            .padding(.top, 6)
                        }
                        .font(.system(size: 12))
                    }
                    Divider()
                }
                DetailsSection(title: "Earned quota resets") {
                    DetailsField(label: "Available resets", value: details.availableResets.map { String($0) } ?? "Not supplied")
                    if let resets = details.resets {
                        if resets.isEmpty {
                            Text("No reset detail rows were returned.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        ForEach(resets) { reset in
                            DisclosureGroup(reset.title ?? "Earned reset") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let description = reset.description { Text(description).textSelection(.enabled) }
                                    DetailsField(label: "Status", value: reset.status ?? "Not supplied")
                                    DetailsField(label: "Reset type", value: reset.type == "codexRateLimits" ? "Codex quota windows" : reset.type ?? "Not supplied")
                                    DetailsField(label: "Granted", value: DetailsFormatting.date(reset.grantedAt))
                                    DetailsField(label: "Expires", value: reset.expiresAt.map { DetailsFormatting.date($0) } ?? "No expiry supplied")
                                    DetailsField(label: "Reset ID", value: reset.id)
                                }.font(.system(size: 11)).padding(.top, 6)
                            }.font(.system(size: 12))
                        }
                        if let count = details.availableResets, count > Int64(resets.count) {
                            Text("The service returned details for \(resets.count) of \(count) available resets.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Reset descriptions and expiry dates were not supplied.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            } else {
                DetailsSection(title: "Limits not recorded yet") {
                    Text("Refresh this account to read its quota windows, credits and earned resets.").font(.system(size: 12))
                }
            }
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding).padding(.vertical, 10)
    }

    @ViewBuilder
    private func window(_ window: QuotaWindowDetails?, slot: String) -> some View {
        if let window {
            let duration = window.durationMinutes.map {
                if $0 == 300 { return "Five-hour" }
                if $0 == 10_080 { return "Weekly" }
                return $0.formatted(.number.precision(.fractionLength(0...1))) + " minute"
            } ?? slot
            VStack(alignment: .leading, spacing: 5) {
                DetailsField(label: "\(duration) usage", value: DetailsFormatting.percent(window.usedPercent))
                if let used = window.usedPercent {
                    QuotaMeter(percent: used, color: Palette.current(scheme).accent)
                }
                Text(DetailsFormatting.reset(window.resetsAt, now: now))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        } else {
            DetailsField(label: slot, value: "Not supplied")
        }
    }
}

private enum ActivityTab: String, CaseIterable {
    case conversations = "Conversations"
    case workspace = "Workspace"
}

struct ActivityDetailsView: View {
    var model: AppModel
    var account: AccountRecord
    @Environment(\.colorScheme) private var scheme
    @State private var tab: ActivityTab = .conversations
    @State private var archived = false
    @State private var manualID = ""
    @State private var selectedThreadID: String?
    @State private var selectedTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuotaTabs(values: ActivityTab.allCases, selection: $tab, title: { $0.rawValue })
            if tab == .workspace {
                workspace
            } else if let threadID = selectedThreadID {
                Button("Back to conversations") { selectedThreadID = nil }
                    .buttonStyle(.bordered)
                if let title = selectedTitle { Text(title).font(.system(size: 13, weight: .semibold)) }
                ConversationUsageView(model: model, account: account, threadID: threadID)
                    .id(threadID)
            } else {
                conversations
            }
        }
        .padding(PanelMetrics.horizontalPadding)
        .task(id: "\(account.id)/\(tab.rawValue)/\(archived)") {
            if tab == .workspace {
                await model.loadWorkspaceDetails(account.id)
            } else {
                await model.loadConversations(account.id, archived: archived)
            }
        }
    }

    private var workspace: some View {
        let state = model.workspaceDetails[account.id] ?? DetailsLoad()
        return VStack(alignment: .leading, spacing: 10) {
            loadStatus(state, title: "workspace messages") {
                Task { await model.loadWorkspaceDetails(account.id, force: true) }
            }
            if let value = state.value {
                if !value.featureEnabled {
                    Text("Workspace messages are not enabled for this account.")
                } else if value.messages.isEmpty {
                    Text("No active workspace messages.")
                }
                ForEach(value.messages) { message in
                    DetailsSection(title: message.type?.capitalized ?? "Workspace message") {
                        Text(message.body).font(.system(size: 12)).textSelection(.enabled)
                        DetailsField(label: "Created", value: DetailsFormatting.date(message.createdAt))
                        if let archived = message.archivedAt {
                            DetailsField(label: "Archived", value: DetailsFormatting.date(archived))
                        }
                    }
                    Divider()
                }
            }
        }.font(.system(size: 12))
    }

    private var conversations: some View {
        let key = AppModel.conversationsKey(account.id, archived: archived)
        let state = model.conversationDetails[key] ?? DetailsLoad()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Conversations stored in this account's Codex home. To inspect a conversation from another client, enter its UUID below.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("Archived conversations", isOn: $archived).toggleStyle(QuotaCheckboxStyle())
            loadStatus(state, title: "conversations") {
                Task { await model.loadConversations(account.id, archived: archived, force: true) }
            }
            if let page = state.value {
                if page.conversations.isEmpty { Text("No \(archived ? "archived" : "active") conversations in this Codex home.") }
                ForEach(page.conversations) { conversation in
                    Button {
                        selectedThreadID = conversation.id
                        selectedTitle = conversation.title
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text("\(conversation.provider ?? "Provider unknown") · \(DetailsFormatting.date(conversation.updatedAt))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            if let directory = conversation.directory {
                                Text(directory).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                    Divider()
                }
                if page.nextCursor != nil {
                    Button("Load more conversations") {
                        Task { await model.loadConversations(account.id, archived: archived, more: true) }
                    }.disabled(state.isLoading)
                }
            }
            Divider()
            Text("Inspect a conversation").font(.system(size: 12, weight: .semibold))
            Text("Conversation UUID").font(.system(size: 11, weight: .medium))
            TextField("Conversation UUID", text: $manualID)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 32)
                .onSubmit { inspectManualConversation() }
            if !manualID.isEmpty, UUID(uuidString: manualID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                Label("Enter a valid conversation UUID.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Palette.current(scheme).warning)
            }
            Button("Inspect usage") { inspectManualConversation() }
                .disabled(UUID(uuidString: manualID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
        }.font(.system(size: 12))
    }

    private func inspectManualConversation() {
        let id = manualID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: id) != nil else { return }
        selectedThreadID = id
        selectedTitle = nil
    }
}

@ViewBuilder
@MainActor
private func loadStatus<Value>(_ state: DetailsLoad<Value>, title: String, reload: @escaping () -> Void) -> some View {
    if state.isLoading {
        HStack { ProgressView().controlSize(.small); Text("Loading \(title)…") }.font(.system(size: 11))
    }
    if let error = state.error {
        Text(error).font(.system(size: 11))
        if state.value != nil { Text("Showing the previous result.").font(.system(size: 11)).foregroundStyle(.secondary) }
    }
    HStack {
        if let checked = state.checkedAt {
            Text(LondonClock.checkedLine(checked)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Spacer()
        Button(state.error == nil ? "Refresh details" : "Retry") { reload() }
            .disabled(state.isLoading)
    }
}

private struct ConversationUsageView: View {
    var model: AppModel
    var account: AccountRecord
    var threadID: String

    var body: some View {
        let key = AppModel.conversationUsageKey(account.id, threadID: threadID)
        let state = model.conversationUsageDetails[key] ?? DetailsLoad()
        VStack(alignment: .leading, spacing: 10) {
            Text(threadID).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            loadStatus(state, title: "conversation usage") {
                Task { await model.loadConversationUsage(account.id, threadID: threadID, force: true) }
            }
            if let usage = state.value {
                DetailsSection(title: "Estimated conversation usage") {
                    DetailsField(label: "Estimated credits", value: DetailsFormatting.micros(usage.creditsMicros))
                    DetailsField(label: "Estimated cost", value: DetailsFormatting.micros(usage.usdMicros, dollars: true))
                    if usage.nativeUsdMicros != nil {
                        DetailsField(label: "Native dollar usage", value: DetailsFormatting.micros(usage.nativeUsdMicros, dollars: true))
                    }
                    Text("Estimates are supplied by Codex for this conversation and may change. An unavailable cost is not zero.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if usage.groups.isEmpty { Text("No model breakdown supplied.").font(.system(size: 12)) }
                Text("— means a token count wasn't supplied.").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(Array(usage.groups.enumerated()), id: \.offset) { _, group in
                    DetailsSection(title: group.model ?? "Model not supplied") {
                        DetailsField(label: "Reasoning effort", value: group.reasoningEffort ?? "Not supplied")
                        DetailsField(label: "Speed", value: group.speed ?? "Not supplied")
                        DetailsField(label: "Estimated credits", value: DetailsFormatting.micros(group.creditsMicros))
                        DetailsField(label: "New input tokens", value: UsageFormatting.exact(group.newInputTokens))
                        DetailsField(label: "Cached input tokens", value: UsageFormatting.exact(group.cachedInputTokens))
                        DetailsField(label: "Input tokens", value: UsageFormatting.exact(group.inputTokens))
                        DetailsField(label: "Output tokens", value: UsageFormatting.exact(group.outputTokens))
                        DetailsField(label: "Total tokens", value: UsageFormatting.exact(group.totalTokens))
                    }
                    Divider()
                }
            } else if state.checkedAt != nil, state.error == nil {
                Text("Usage estimates are unavailable for this conversation and the active account.")
                    .font(.system(size: 12))
            }
        }
        .task { await model.loadConversationUsage(account.id, threadID: threadID) }
    }
}
