import Foundation

struct CollapsedSummaryItem: Identifiable, Hashable {
    let id: String
    let moduleID: String
    let title: String
    let text: String
    let isEnabledByDefault: Bool
}

struct CollapsedSummaryConfiguration: Equatable {
    var visibleIDs: Set<String>
    var usesDefaultSelection: Bool

    static func load() -> CollapsedSummaryConfiguration {
        let defaults = UserDefaults.standard
        guard let storedIDs = defaults.stringArray(forKey: IslandDefaults.collapsedSummaryVisibleIDsKey) else {
            return CollapsedSummaryConfiguration(visibleIDs: [], usesDefaultSelection: true)
        }

        return CollapsedSummaryConfiguration(visibleIDs: Set(storedIDs), usesDefaultSelection: false)
    }

    func isVisible(_ item: CollapsedSummaryItem) -> Bool {
        if usesDefaultSelection {
            return item.isEnabledByDefault
        }

        return visibleIDs.contains(item.id)
    }

    func settingVisibility(
        _ isVisible: Bool,
        for item: CollapsedSummaryItem,
        availableItems: [CollapsedSummaryItem]
    ) -> CollapsedSummaryConfiguration {
        var nextVisibleIDs = usesDefaultSelection
            ? Set(availableItems.filter(\.isEnabledByDefault).map(\.id))
            : visibleIDs

        if isVisible {
            nextVisibleIDs.insert(item.id)
        } else {
            nextVisibleIDs.remove(item.id)
        }

        return CollapsedSummaryConfiguration(visibleIDs: nextVisibleIDs, usesDefaultSelection: false)
    }

    func persist() {
        let storedIDs = Array(visibleIDs).sorted()
        UserDefaults.standard.set(storedIDs, forKey: IslandDefaults.collapsedSummaryVisibleIDsKey)
    }
}
