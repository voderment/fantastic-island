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
    var icon: ((Selection) -> NSImage?)? = nil
    var iconSize: CGFloat = 14
    var itemSpacing: CGFloat = 10
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    var backgroundColor: Color = .white
    var backgroundOpacity: Double = 0.08
    var disabledBackgroundOpacity: Double = 0.05
    var strokeColor: Color? = nil
    var strokeOpacity: Double = 0
    var strokeLineWidth: CGFloat = 0

    @State private var anchorView: NSView?
    @State private var menuController = CapsuleMenuController()

    var body: some View {
        Button(action: presentMenu) {
            HStack(spacing: itemSpacing) {
                if let iconImage = icon?(selection) {
                    Image(nsImage: iconImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(.rect(cornerRadius: iconSize * 0.22))
                }

                menuText(
                    labelTitle?(selection) ?? title(selection),
                    localize: localizeLabel
                )
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(isEnabled ? 0.86 : 0.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
                .frame(maxWidth: maxLabelWidth, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.52 : 0.32))
                    .frame(width: 8)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                backgroundColor.opacity(isEnabled ? backgroundOpacity : disabledBackgroundOpacity),
                in: Capsule()
            )
            .overlay {
                if let strokeColor, strokeLineWidth > 0 {
                    Capsule()
                        .strokeBorder(strokeColor.opacity(strokeOpacity), lineWidth: strokeLineWidth)
                }
            }
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
            icon: icon,
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
        icon: ((Selection) -> NSImage?)?,
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
            menuItem.image = icon?(option).map(Self.menuImage)
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

    private static func menuImage(from image: NSImage) -> NSImage {
        let menuImage = (image.copy() as? NSImage) ?? image
        menuImage.size = NSSize(width: 16, height: 16)
        return menuImage
    }
}
