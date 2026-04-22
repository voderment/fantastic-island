import SwiftUI

enum IslandModuleScrollCoordinateSpace {
    static let name = "island.module.scroll"
}

struct IslandModuleScrollAction {
    private let handler: @MainActor (AnyHashable, UnitPoint) -> Void

    init(_ handler: @escaping @MainActor (AnyHashable, UnitPoint) -> Void = { _, _ in }) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction(_ id: some Hashable, anchor: UnitPoint = .top) {
        handler(AnyHashable(id), anchor)
    }
}

private struct IslandModuleScrollActionKey: EnvironmentKey {
    static let defaultValue = IslandModuleScrollAction()
}

private struct IslandModuleScrollOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var islandModuleScrollAction: IslandModuleScrollAction {
        get { self[IslandModuleScrollActionKey.self] }
        set { self[IslandModuleScrollActionKey.self] = newValue }
    }

    var islandModuleScrollOffset: CGFloat {
        get { self[IslandModuleScrollOffsetKey.self] }
        set { self[IslandModuleScrollOffsetKey.self] = newValue }
    }
}
