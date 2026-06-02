import Foundation

struct CodexTokenUsageHistoryScanner {
    var rootURL: URL
    var maxAge: TimeInterval
    var maxFiles: Int
    var maxReadBytesPerFile: UInt64

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true),
        maxAge: TimeInterval = 86_400 * 370,
        maxFiles: Int = 1_200,
        maxReadBytesPerFile: UInt64 = 12 * 1024 * 1024
    ) {
        self.rootURL = rootURL
        self.maxAge = maxAge
        self.maxFiles = maxFiles
        self.maxReadBytesPerFile = maxReadBytesPerFile
    }

    func scan(now: Date = .now) -> CodexTokenUsageHistory {
        guard FileManager.default.fileExists(atPath: rootURL.path),
              let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return .empty
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard modifiedAt >= cutoff else {
                continue
            }

            candidates.append((fileURL, modifiedAt))
        }

        let files = candidates
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }

                return lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(maxFiles)

        return files.reduce(into: CodexTokenUsageHistory()) { history, candidate in
            scan(fileURL: candidate.url, into: &history)
        }
    }

    private func scan(fileURL: URL, into history: inout CodexTokenUsageHistory) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return
        }

        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else {
            return
        }

        let readSize = min(fileSize, maxReadBytesPerFile)
        let readStart = fileSize - readSize
        try? handle.seek(toOffset: readStart)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return
        }

        let startsAtFileBeginning = readStart == 0
        if !startsAtFileBeginning {
            trimLeadingPartialLine(from: &data)
        }

        var previousCumulativeTokens: Int?
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        for line in lines where line.contains("\"token_count\"") {
            guard let object = jsonObject(for: String(line)),
                  let sample = CodexTokenUsageSample.fromRolloutObject(object) else {
                continue
            }

            if let lastTokens = sample.lastTokens {
                history.record(tokens: lastTokens, at: sample.capturedAt)
                previousCumulativeTokens = sample.cumulativeTokens ?? previousCumulativeTokens
                continue
            }

            guard let cumulativeTokens = sample.cumulativeTokens else {
                continue
            }

            if let previousCumulativeTokens {
                history.record(tokens: max(0, cumulativeTokens - previousCumulativeTokens), at: sample.capturedAt)
            } else if startsAtFileBeginning {
                history.record(tokens: cumulativeTokens, at: sample.capturedAt)
            }
            previousCumulativeTokens = cumulativeTokens
        }
    }

    private func trimLeadingPartialLine(from data: inout Data) {
        let newline = UInt8(ascii: "\n")
        guard let newlineIndex = data.firstIndex(of: newline) else {
            data.removeAll(keepingCapacity: false)
            return
        }

        data.removeSubrange(...newlineIndex)
    }
}
