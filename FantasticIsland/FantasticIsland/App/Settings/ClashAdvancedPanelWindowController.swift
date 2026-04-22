import AppKit
import WebKit

@MainActor
final class ClashAdvancedPanelWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsMagnification = true
        return view
    }()

    func show(url: URL) {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        if webView.url != url {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let contentController = NSViewController()
        contentController.view = webView

        let window = NSWindow(contentViewController: contentController)
        window.delegate = self
        window.title = NSLocalizedString("Clash Advanced Panel", comment: "")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 980, height: 680)
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = .black
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        return NSWindowController(window: window)
    }
}
