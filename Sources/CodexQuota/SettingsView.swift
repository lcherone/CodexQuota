import AppKit
import CodexQuotaCore
import CodexQuotaModel
import SwiftUI

struct QuotaSettingsView: View {
    var model: AppModel
    var onBack: () -> Void
    @State private var changingAlerts = false
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette.current(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.system(size: 17, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Applies to this Mac · Changes save automatically")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    settingsSection("Startup") { startupSection }
                    Divider()
                    settingsSection("Alerts") { alertsSection }
                    Divider()
                    settingsSection("Appearance") {
                        AppearancePicker(model: model, showsIcons: true)
                        Text("System follows your Mac’s appearance.")
                            .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Changes save automatically").font(.system(size: 11)).foregroundStyle(palette.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).keyboardShortcut("q")
            }
            .padding(16)
        }
        .font(.system(size: 13))
        .foregroundStyle(palette.ink)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .buttonStyle(.bordered).controlSize(.small)
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { model.loginItem.isEnabled },
                set: { model.loginItem.setEnabled($0) }
            ))
            .toggleStyle(QuotaCheckboxStyle())
            .font(.system(size: 13, weight: .medium))
            .disabled(!model.loginItem.canConfigure)
            Text("Start quietly in the menu bar when you sign in.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .padding(.leading, 27)
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
                set: { enabled in
                    changingAlerts = true
                    Task {
                        await model.setAlertsEnabled(enabled)
                        changingAlerts = false
                    }
                }
            ))
            .toggleStyle(QuotaCheckboxStyle())
            .font(.system(size: 13, weight: .medium))
            .disabled(!model.libraryReady || changingAlerts || model.alertPermission == .unavailable)
            if changingAlerts {
                ProgressView("Updating notification permission…").controlSize(.small)
            }
            Text("Notify when an account crosses the weekly threshold, goes ahead of its daily slice, or reaches its allowance.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .padding(.leading, 27)
            if model.alertsEnabled {
                HStack(spacing: 8) {
                    Text("Weekly threshold")
                    Spacer()
                    Text("\(model.store.alertPreferences.weeklyThreshold)%")
                        .monospacedDigit().frame(minWidth: 36, alignment: .trailing)
                    thresholdButton("Decrease weekly threshold", icon: "minus", change: -5)
                    thresholdButton("Increase weekly threshold", icon: "plus", change: 5)
                }
                .font(.system(size: 13))
                .padding(.vertical, 8)
                Text("Alerts apply to all accounts.")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
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

    private func thresholdButton(_ title: String, icon: String, change: Int) -> some View {
        let current = model.store.alertPreferences.weeklyThreshold
        let supported = QuotaAlertPreferences.supportedThresholds
        let atBoundary = change < 0 ? current <= supported.lowerBound : current >= supported.upperBound
        return Button {
            model.setAlertThreshold(current + change)
        } label: {
            Image(systemName: icon).frame(width: 16, height: 20)
        }
        .buttonStyle(.bordered)
        .disabled(!model.libraryReady || atBoundary)
        .accessibilityLabel(title)
        .accessibilityValue("\(current) percent")
        .help(title)
    }
}

struct AppearancePicker: View {
    var model: AppModel
    var showsIcons = false
    @Environment(\.colorScheme) private var scheme

    private var selectedSurface: Color {
        scheme == .dark ? .white.opacity(0.16) : Palette.current(scheme).background
    }

    var body: some View {
        Group {
            if showsIcons {
                HStack(spacing: 2) {
                    appearanceButton("System", icon: "desktopcomputer", choice: .system)
                    appearanceButton("Light", icon: "sun.max", choice: .light)
                    appearanceButton("Dark", icon: "moon", choice: .dark)
                }
                .padding(3)
                .background(Palette.current(scheme).ink.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Appearance")
            } else {
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
            }
        }
        .disabled(!model.libraryReady)
    }

    private func appearanceButton(_ title: String, icon: String, choice: PanelAppearance) -> some View {
        let selected = model.store.appearance == choice
        let palette = Palette.current(scheme)
        return Button { model.setAppearance(choice) } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .background(selected ? selectedSurface : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? palette.hairline : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
