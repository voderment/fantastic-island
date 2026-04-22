import AppKit
import SwiftUI

@MainActor
final class IslandSettingsWindowController: NSObject, NSWindowDelegate {
    private weak var model: IslandAppModel?
    private var windowController: NSWindowController?

    init(model: IslandAppModel) {
        self.model = model
    }

    func show() {
        guard let model else {
            return
        }

        let controller = windowController ?? makeWindowController(model: model)
        windowController = controller

        if let hostingController = controller.contentViewController as? NSHostingController<IslandSettingsView> {
            hostingController.rootView = IslandSettingsView(model: model)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController(model: IslandAppModel) -> NSWindowController {
        let hostingController = NSHostingController(rootView: IslandSettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.delegate = self
        window.title = "Settings"
        let fixedSize = NSSize(width: 820, height: 610)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = true
        window.animationBehavior = .utilityWindow
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true

        return NSWindowController(window: window)
    }
}
