import AppKit
import CodexQuotaCore
import CodexQuotaModel

@MainActor
let appModel = AppModel(
    history: AppHistory(.resolve()),
    service: AppQuotaService(.production()),
    notifications: LocalNotificationController(),
    loginItem: LoginItemController(),
    openBrowser: { url in
        Task { @MainActor in NSWorkspace.shared.open(url) }
    }
)
