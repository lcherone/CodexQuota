import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?

    var canConfigure: Bool {
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return bundle.pathExtension == "app"
            && (bundle.path.hasPrefix("/Applications/") || bundle.path.hasPrefix(userApplications + "/"))
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
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

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
