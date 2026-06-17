import Foundation

struct HorizonShelfResolvedDrop: Equatable {
    let index: Int
    let url: URL
}

enum HorizonShelfDropOrdering {
    static func orderedUniqueURLs(from drops: [HorizonShelfResolvedDrop]) -> [URL] {
        var seen = Set<URL>()
        return drops
            .sorted { lhs, rhs in
                if lhs.index != rhs.index {
                    return lhs.index < rhs.index
                }
                return lhs.url.path < rhs.url.path
            }
            .compactMap { drop in
                guard seen.insert(drop.url).inserted else {
                    return nil
                }
                return drop.url
            }
    }
}
