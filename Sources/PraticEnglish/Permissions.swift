import Cocoa
import ApplicationServices
import IOKit.hid

enum Permissions {
    static func accessibilityGranted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Desde macOS 10.15, NSEvent global de teclado exige "Input Monitoring".
    static func inputMonitoringGranted(prompt: Bool) -> Bool {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted { return true }
        if prompt {
            // Dispara o diálogo do sistema (apenas 1ª vez; depois precisa ser feito manualmente).
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        return false
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
