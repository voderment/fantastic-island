import AppKit
import SwiftUI

struct CapsuleMenuPicker<Selection: Hashable>: View {
    @Binding var selection: Selection

    let options: [Selection]
    let title: (Selection) -> String
    var labelTitle: ((Selection) -> String)? = nil
    var isEnabled: Bool = true
    var localizeLabel = true
    var localizeMenuItems = true
    var maxLabelWidth: CGFloat? = nil

    @State private var anchorView: NSView?
    @State private var menuController = CapsuleMenuController()

    var body: some View {
        Button(action: presentMenu) {
            HStack(spacing: 10) {
                menuText(
                    labelTitle?(selection) ?? title(selection),
                    localize: localizeLabel
                )
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(isEnabled ? 0.86 : 0.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxLabelWidth, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.52 : 0.32))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(isEnabled ? 0.08 : 0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(CapsuleMenuPickerAnchorView(anchorView: $anchorView))
    }

    private func presentMenu() {
        guard isEnabled, let anchorView else { return }

        menuController.present(
            from: anchorView,
            options: options,
            selected: selection,
            title: title,
            localizeTitles: localizeMenuItems
        ) { selectedOption in
            selection = selectedOption
        }
    }

    @ViewBuilder
    private func menuText(_ text: String, localize: Bool) -> some View {
        if localize {
            Text(LocalizedStringKey(text))
        } else {
            Text(verbatim: text)
        }
    }
}

private struct CapsuleMenuPickerAnchorView: NSViewRepresentable {
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            anchorView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard anchorView !== nsView else { return }
        DispatchQueue.main.async {
            anchorView = nsView
        }
    }
}

@MainActor
private final class CapsuleMenuController: NSObject {
    private var handlers: [Int: () -> Void] = [:]

    func present<Selection: Hashable>(
        from anchorView: NSView,
        options: [Selection],
        selected: Selection,
        title: (Selection) -> String,
        localizeTitles: Bool,
        onSelect: @escaping (Selection) -> Void
    ) {
        let menu = NSMenu()
        handlers.removeAll(keepingCapacity: true)

        for (index, option) in options.enumerated() {
            let menuItem = NSMenuItem(
                title: localizeTitles ? NSLocalizedString(title(option), comment: "") : title(option),
                action: #selector(handleSelection(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = index
            menuItem.state = option == selected ? .on : .off
            handlers[index] = {
                onSelect(option)
            }
            menu.addItem(menuItem)
        }

        menu.minimumWidth = max(anchorView.bounds.width, 160)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height + 6), in: anchorView)
    }

    @objc
    private func handleSelection(_ sender: NSMenuItem) {
        handlers[sender.tag]?()
    }
}
