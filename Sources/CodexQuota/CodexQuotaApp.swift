import AppKit
import CodexQuotaCore
import SwiftUI

@main
struct CodexQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Codex Quota", id: "main") {
            RootView()
        }
        .defaultSize(width: 980, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct RootView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainView(model: .shared)
            .onAppear {
                AppDelegate.shared?.openMain = { openWindow(id: "main") }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var openMain: (() -> Void)?
    private let status = StatusController()

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.image()
        status.install(model: .shared)
        AppModel.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMain?()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var model: AppModel?
    private var timer: Timer?

    func install(model: AppModel) {
        self.model = model
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        applyTitle()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyTitle()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }
        if model.store.accounts.isEmpty {
            let empty = NSMenuItem(title: "No accounts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for account in model.store.accounts {
                let entry = NSMenuItem(title: line(for: account, model: model), action: #selector(selectAccount(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = account.id
                entry.state = model.selectedAccount?.id == account.id ? .on : .off
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        add("Open Codex Quota", #selector(openMainWindow), menu)
        add("Refresh", #selector(refreshAccounts), menu, key: "r")
        menu.addItem(.separator())
        add("Quit Codex Quota", #selector(quit), menu, key: "q")
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model?.select(id)
        openMainWindow()
        applyTitle()
    }

    @objc private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        AppDelegate.shared?.openMain?()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshAccounts() {
        Task { await model?.refreshAll() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func add(_ title: String, _ action: Selector, _ menu: NSMenu, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
    }

    private func applyTitle() {
        item.button?.title = model?.menuTitle ?? "Quota"
    }

    private func line(for account: AccountRecord, model: AppModel) -> String {
        if model.authRequired.contains(account.id) {
            return "\(account.label) — sign in"
        }
        guard let latest = model.latestSample(for: account.id) else {
            return account.label
        }
        let pace = model.paceReport(for: account.id, sample: latest, now: Date())
        let title = Pace.menuTitle(
            todaySlicePercent: pace?.todaySlicePercent,
            todayKind: pace?.todayKind ?? .unknown,
            dayStatus: pace?.dayStatus ?? .unknown,
            weeklyUsed: latest.usedPercent
        )
        return "\(account.label) — \(title)"
    }
}

enum AppIcon {
    static func image(side: CGFloat = 1024) -> NSImage {
        let size = NSSize(width: side, height: side)
        return NSImage(size: size, flipped: false) { rect in
            let ink = NSColor(calibratedRed: 0.08, green: 0.32, blue: 0.27, alpha: 1)
            let cream = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.89, alpha: 1)
            let plate = NSBezierPath(
                roundedRect: rect.insetBy(dx: side * 0.06, dy: side * 0.06),
                xRadius: side * 0.22,
                yRadius: side * 0.22
            )
            ink.setFill()
            plate.fill()
            let ringRect = rect.insetBy(dx: side * 0.24, dy: side * 0.24)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = side * 0.055
            cream.withAlphaComponent(0.28).setStroke()
            ring.stroke()
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: side * 0.26,
                startAngle: 210,
                endAngle: -40,
                clockwise: true
            )
            arc.lineWidth = side * 0.055
            arc.lineCapStyle = .round
            cream.setStroke()
            arc.stroke()
            return true
        }
    }
}
