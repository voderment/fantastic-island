import AppKit
import ApplicationServices
import Foundation

enum IslandFullscreenMonitor {
    static func frontmostAppIsFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else {
            return false
        }

        var fullscreenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, &fullscreenValue) == .success,
              let isFullscreen = fullscreenValue as? Bool else {
            return false
        }

        return isFullscreen
    }
}
