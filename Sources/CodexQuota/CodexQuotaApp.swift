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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        NSApp.activate()
        return true
    }
}

@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var model: AppModel?
    private var timer: Timer?

    func install(model: AppModel) {
        self.model = model
        item.menu = nil
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        applyTitle()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyTitle()
            }
        }
    }

    @objc private func toggleWindow() {
        NSApp.setActivationPolicy(.accessory)
        let windows = mainWindows()
        if windows.contains(where: { $0.isVisible && !$0.isMiniaturized }) {
            for window in windows where window.isVisible {
                window.orderOut(nil)
            }
            return
        }
        AppDelegate.shared?.openMain?()
        for window in mainWindows() {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    private func mainWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            window.title == "Codex Quota" || window.canBecomeMain
        }
    }

    private func applyTitle() {
        item.button?.title = model?.menuTitle ?? "Quota"
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
