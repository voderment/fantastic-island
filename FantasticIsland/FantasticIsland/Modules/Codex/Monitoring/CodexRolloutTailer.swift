import Foundation

final class CodexRolloutTailer {
    private struct Observation {
        var session: DiscoveredSession
        var offset: UInt64
        var pendingBuffer = Data()
    }

    private var observations: [String: Observation] = [:]
    private let initialReadLimit: UInt64
    private let quotaScanChunkSize: UInt64 = 512 * 1024
    private let quotaScanMaxBytes: UInt64 = 8 * 1024 * 1024

    init(initialReadLimit: UInt64 = 256 * 1024) {
        self.initialReadLimit = initialReadLimit
    }

    func sync(with sessions: [DiscoveredSession], reducer: CodexSessionReducer) {
        let uniqueSessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, rhs in rhs })

        observations = observations.reduce(into: [:]) { partialResult, entry in
            guard let session = uniqueSessions[entry.key] else {
                return
            }

            var observation = entry.value
            observation.session = session
            partialResult[entry.key] = observation
        }

        for session in uniqueSessions.values {
            reducer.upsertDiscoveredSession(session)
            if observations[session.id] == nil {
                observations[session.id] = bootstrapObservation(for: session, reducer: reducer)
            }
        }

        for key in observations.keys {
            guard var observation = observations[key] else {
                continue
            }

            refresh(observation: &observation, reducer: reducer)
            observations[key] = observation
        }
    }

    private func bootstrapObservation(for session: DiscoveredSession, reducer: CodexSessionReducer) -> Observation {
        let fileURL = URL(fileURLWithPath: session.transcriptPath)
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return Observation(session: session, offset: 0)
        }

        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readLimit = min(initialReadLimit, fileSize)
        guard readLimit > 0 else {
            return Observation(session: session, offset: fileSize)
        }

        try? handle.seek(toOffset: fileSize - readLimit)
        var buffer = (try? handle.readToEnd()) ?? Data()
        if fileSize > readLimit {
            trimLeadingPartialLine(from: &buffer)
        }
        let lines = completeLines(from: &buffer)
        lines.forEach { reducer.applyRolloutLine($0, for: session) }

        if let preferredQuotaSnapshot = resolveLatestQuotaSnapshot(in: fileURL) {
            reducer.applyQuotaSnapshot(preferredQuotaSnapshot)
        }

        return Observation(session: session, offset: fileSize, pendingBuffer: buffer)
    }

    private func refresh(observation: inout Observation, reducer: CodexSessionReducer) {
        let url = URL(fileURLWithPath: observation.session.transcriptPath)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }

        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        if fileSize < observation.offset {
            observation = bootstrapObservation(for: observation.session, reducer: reducer)
            return
        }

        guard fileSize > observation.offset else {
            return
        }

        try? handle.seek(toOffset: observation.offset)
        guard let data = try? handle.readToEnd(),
              !data.isEmpty else {
            return
        }

        observation.offset += UInt64(data.count)
        observation.pendingBuffer.append(data)
        let lines = completeLines(from: &observation.pendingBuffer)
        lines.forEach { reducer.applyRolloutLine($0, for: observation.session) }
    }

    private func completeLines(from buffer: inout Data) -> [String] {
        let newline = UInt8(ascii: "\n")
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else {
                continue
            }
            lines.append(String(decoding: lineData, as: UTF8.self))
        }

        return lines
    }

    private func trimLeadingPartialLine(from buffer: inout Data) {
        let newline = UInt8(ascii: "\n")
        guard let newlineIndex = buffer.firstIndex(of: newline) else {
            buffer.removeAll(keepingCapacity: false)
            return
        }

        buffer.removeSubrange(...newlineIndex)
    }

    private func resolveLatestQuotaSnapshot(in fileURL: URL) -> CodexQuotaSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else {
            return nil
        }

        var scannedBytes: UInt64 = 0
        var trailingBuffer = Data()
        var latestFallbackSnapshot: CodexQuotaSnapshot?

        while scannedBytes < min(fileSize, quotaScanMaxBytes) {
            let remainingBytes = fileSize - scannedBytes
            let chunkSize = min(quotaScanChunkSize, remainingBytes)
            let chunkStart = remainingBytes - chunkSize

            try? handle.seek(toOffset: chunkStart)
            guard var chunk = try? handle.read(upToCount: Int(chunkSize)),
                  !chunk.isEmpty else {
                break
            }

            if !trailingBuffer.isEmpty {
                chunk.append(trailingBuffer)
            }

            let lines = chunk
                .split(separator: UInt8(ascii: "\n"))
                .map { String(decoding: $0, as: UTF8.self) }

            if chunkStart > 0,
               let firstNewlineIndex = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                trailingBuffer = Data(chunk.prefix(upTo: firstNewlineIndex))
            } else {
                trailingBuffer.removeAll(keepingCapacity: false)
            }

            for line in lines.reversed() {
                guard let object = jsonObject(for: line),
                      let snapshot = CodexQuotaSnapshot.fromRolloutObject(object) else {
                    continue
                }

                if snapshot.sourceKind == CodexQuotaSnapshot.SourceKind.preferred {
                    return snapshot
                }

                if latestFallbackSnapshot == nil {
                    latestFallbackSnapshot = snapshot
                }
            }

            scannedBytes += chunkSize
        }

        return latestFallbackSnapshot
    }
}
