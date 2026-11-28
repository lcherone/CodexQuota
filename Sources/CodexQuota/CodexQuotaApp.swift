import AppKit
import CodexQuotaCore
import CodexQuotaModel
import SwiftUI

extension Notification.Name {
    static let quotaPanelEscape = Notification.Name("CodexQuota.panelEscape")
}

@main
struct CodexQuotaApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let status = StatusController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIcon.image()
        installMainMenu()
        status.install(model: appModel)
        appModel.start()
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch, !CommandLine.arguments.contains("--background") {
            status.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        status.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let application = NSMenuItem()
        application.submenu = NSMenu(title: "Codex Quota")
        application.submenu?.addItem(withTitle: "Quit Codex Quota", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(application)
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            // Undo is supplied dynamically by the responder chain.
            ("Undo", Selector(("undo:")), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.submenu?.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }
}

@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = QuotaPanel()
    private var host: NSHostingView<MainView>?
    private weak var model: AppModel?
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var availableHeight: CGFloat = 640

    func install(model: AppModel) {
        self.model = model
        let host = NSHostingView(rootView: MainView(model: model, availableHeight: availableHeight, onDismiss: { [weak self] in
            self?.hide()
        }))
        host.sizingOptions = [.intrinsicContentSize]
        host.wantsLayer = true
        host.layer?.cornerRadius = 8
        host.layer?.masksToBounds = true
        self.host = host
        panel.contentView = host
        item.menu = nil
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        applyTitle()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyTitle()
            }
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model?.loginItem.refresh()
        fit()
        placeUnderStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    private func hide() {
        panel.orderOut(nil)
        removeMonitors()
    }

    private func fit() {
        guard let host else { return }
        let screen = item.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maxHeight = min(PanelMetrics.maximumHeight, max(240, (screen?.height ?? 640) - 24))
        if availableHeight != maxHeight, let model {
            availableHeight = maxHeight
            host.rootView = MainView(model: model, availableHeight: availableHeight, onDismiss: { [weak self] in
                self?.hide()
            })
        }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        size.width = PanelMetrics.width
        if size.height < 80 || !size.height.isFinite {
            size.height = min(480, maxHeight)
        }
        size.height = min(size.height, maxHeight)
        if panel.contentLayoutRect.size != size {
            panel.setContentSize(size)
        }
    }

    private func placeUnderStatusItem() {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var frame = panel.frame
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        frame.origin.x = anchor.midX - frame.width / 2
        frame.origin.y = anchor.minY - frame.height - 4
        if frame.maxX > visible.maxX - 4 {
            frame.origin.x = visible.maxX - frame.width - 4
        }
        if frame.minX < visible.minX + 4 {
            frame.origin.x = visible.minX + 4
        }
        if frame.minY < visible.minY + 4 {
            frame.origin.y = visible.minY + 4
        }
        panel.setFrame(frame, display: true)
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.hideIfClick(at: point)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let escape = event.type == .keyDown && event.keyCode == 53
            let click = event.type == .leftMouseDown || event.type == .rightMouseDown
            let point = NSEvent.mouseLocation
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if escape, self.panel.isVisible {
                    NotificationCenter.default.post(name: .quotaPanelEscape, object: self.panel)
                    return true
                }
                if click {
                    self.hideIfClick(at: point)
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func hideIfClick(at point: NSPoint) {
        guard panel.isVisible else { return }
        if panel.frame.contains(point) { return }
        if let button = item.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            if anchor.contains(point) { return }
        }
        hide()
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func applyTitle() {
        let presentation = model?.menuBarPresentation
            ?? MenuBarPresentation(selectedAccountLabel: nil, accountCount: 0, stateTitle: "Quota")
        item.button?.title = presentation.title
        item.button?.toolTip = presentation.toolTip
        item.button?.setAccessibilityLabel(presentation.accessibilityLabel)
        if panel.isVisible {
            let previous = panel.frame.size
            fit()
            if panel.frame.size != previous {
                placeUnderStatusItem()
            }
        }
    }
}

final class QuotaPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
