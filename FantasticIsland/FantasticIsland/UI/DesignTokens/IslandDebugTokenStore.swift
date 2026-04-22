import Combine
import Foundation

@MainActor
final class IslandDebugTokenStore: ObservableObject {
    @Published private(set) var savedTokens: IslandDesignTokens
    @Published private(set) var workingTokens: IslandDesignTokens
    @Published private(set) var savedConfigs: [DesignTokenSavedConfig] = []

    private let writer: DesignTokenWriter
    private let writebackService: DesignTokenWritebackService

    init(
        initialTokens: IslandDesignTokens? = nil,
        writer: DesignTokenWriter? = nil,
        writebackService: DesignTokenWritebackService? = nil
    ) {
        let resolvedTokens = initialTokens ?? IslandDesignTokens.sourceDefaults()
        self.savedTokens = resolvedTokens
        self.workingTokens = resolvedTokens
        self.writer = writer ?? DesignTokenWriter()
        self.writebackService = writebackService ?? DesignTokenWritebackService()
        IslandDesignTokenRuntime.current = resolvedTokens
        refreshSavedConfigs()
    }

    var hasUnsavedChanges: Bool {
        workingTokens != savedTokens
    }

    func setNumber(_ value: Double, for descriptor: IslandDesignTokenDescriptor) {
        var next = workingTokens
        descriptor.setNumber(&next, value)
        applyWorkingTokens(next)
    }

    func setColor(_ value: IslandColorToken, for descriptor: IslandDesignTokenDescriptor) {
        var next = workingTokens
        descriptor.setColor(&next, value)
        applyWorkingTokens(next)
    }

    func isModified(_ descriptor: IslandDesignTokenDescriptor) -> Bool {
        switch descriptor.kind {
        case .color:
            return descriptor.getColor(workingTokens) != descriptor.getColor(savedTokens)
        case .slider, .number:
            return descriptor.getNumber(workingTokens) != descriptor.getNumber(savedTokens)
        }
    }

    func revert(_ descriptor: IslandDesignTokenDescriptor) {
        var next = workingTokens

        switch descriptor.kind {
        case .color:
            descriptor.setColor(&next, descriptor.getColor(savedTokens))
        case .slider, .number:
            descriptor.setNumber(&next, descriptor.getNumber(savedTokens))
        }

        applyWorkingTokens(next)
    }

    func revert() {
        applyWorkingTokens(savedTokens)
    }

    func saveConfig() throws -> URL {
        let workspace = try writer.write(tokens: workingTokens)
        savedTokens = workingTokens
        refreshSavedConfigs()
        return workspace
    }

    func loadSavedConfig(_ config: DesignTokenSavedConfig) throws {
        let loadedTokens = try writer.loadSavedConfig(config)
        savedTokens = loadedTokens
        applyWorkingTokens(loadedTokens)
    }

    func refreshSavedConfigs() {
        savedConfigs = writer.listSavedConfigs()
    }

    @discardableResult
    func writeBack(groups: Set<IslandDesignTokenGroup>) throws -> [URL] {
        _ = try saveConfig()
        return try writebackService.writeBack(tokens: workingTokens, groups: groups)
    }

    @discardableResult
    func writeBackAll() throws -> [URL] {
        try writeBack(groups: Set(IslandDesignTokenGroup.allCases))
    }

    private func applyWorkingTokens(_ tokens: IslandDesignTokens) {
        workingTokens = tokens
        IslandDesignTokenRuntime.current = tokens
    }
}
