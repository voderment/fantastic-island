#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class DesignTokenEditorWindowController: NSObject, NSWindowDelegate {
    private weak var model: IslandAppModel?
    private let store: IslandDebugTokenStore
    private let localeProvider: () -> Locale
    private var windowController: NSWindowController?

    init(model: IslandAppModel, store: IslandDebugTokenStore, localeProvider: @escaping () -> Locale) {
        self.model = model
        self.store = store
        self.localeProvider = localeProvider
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller
        let locale = localeProvider()

        if let hostingController = controller.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = makeRootView(locale: locale)
        }

        controller.window?.title = DesignTokenEditorLocalization.text(.windowTitle, locale: locale)
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard store.hasUnsavedChanges else {
            return true
        }
        let locale = localeProvider()

        let alert = NSAlert()
        alert.messageText = DesignTokenEditorLocalization.text(.unsavedChangesTitle, locale: locale)
        alert.informativeText = DesignTokenEditorLocalization.text(.unsavedChangesMessage, locale: locale)
        alert.addButton(withTitle: DesignTokenEditorLocalization.text(.saveConfig, locale: locale))
        alert.addButton(withTitle: DesignTokenEditorLocalization.text(.discard, locale: locale))
        alert.addButton(withTitle: DesignTokenEditorLocalization.text(.cancel, locale: locale))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                _ = try store.saveConfig()
                return true
            } catch {
                let failure = NSAlert(error: error)
                failure.runModal()
                return false
            }
        case .alertSecondButtonReturn:
            store.revert()
            return true
        default:
            return false
        }
    }

    private func makeWindowController() -> NSWindowController {
        let locale = localeProvider()
        let hostingController = NSHostingController(rootView: makeRootView(locale: locale))
        let window = NSWindow(contentViewController: hostingController)
        window.delegate = self
        window.title = DesignTokenEditorLocalization.text(.windowTitle, locale: locale)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.minSize = NSSize(width: 1100, height: 720)
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = .black
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        return NSWindowController(window: window)
    }

    private func makeRootView(locale: Locale) -> AnyView {
        guard let model else {
            return AnyView(EmptyView())
        }

        return AnyView(
            DesignTokenEditorView(model: model, store: store)
                .environment(\.locale, locale)
        )
    }
}
#endif
