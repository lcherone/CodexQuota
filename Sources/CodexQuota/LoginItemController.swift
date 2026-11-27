import Foundation
import CodexQuotaModel
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemController: LoginItemControlling {
    private(set) var status = SMAppService.mainApp.status
    public private(set) var error: String?

    public var canConfigure: Bool {
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return bundle.pathExtension == "app"
            && (bundle.path.hasPrefix("/Applications/") || bundle.path.hasPrefix(userApplications + "/"))
    }

    public var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    public var needsApproval: Bool { status == .requiresApproval }

    public func refresh() {
        status = SMAppService.mainApp.status
    }

    public func setEnabled(_ enabled: Bool) {
        guard canConfigure else { return }
        error = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = "Couldn't change launch at login. \(error.localizedDescription)"
        }
        refresh()
    }

    public func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
