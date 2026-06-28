import AppKit
import Combine
import SwiftUI

struct FanModuleRenderState {
    let animationState: IslandFanAnimationState
    let logoPreset: WindDriveLogoPreset
    let customImage: NSImage?
}

@MainActor
final class FanModuleModel: ObservableObject, IslandModule {
    static let moduleID = "fan"

    let id = FanModuleModel.moduleID
    let title = "Fan"
    let symbolName = "fanblades.fill"
    let iconAssetName: String? = "fanicon"

    @Published private(set) var animationState = IslandFanAnimationState(
        anchorDate: .now,
        anchorDegrees: 0,
        rotationPeriod: 2,
        isSpinning: false
    )
    @Published private(set) var logoPreset: WindDriveLogoPreset = .defaultMark
    @Published private(set) var customImage: NSImage?

    var collapsedSummaryItems: [CollapsedSummaryItem] { [] }
    var taskActivityContribution = TaskActivityContribution()
    var allowsInternalScrolling: Bool { false }

    var preferredOpenedContentHeight: CGFloat {
        CodexIslandChromeMetrics.moduleChromeHeight + FanModuleMetrics.visualHeight
    }

    func makeRenderSnapshot(presentation: IslandModulePresentationContext) -> IslandModuleRenderSnapshot {
        IslandModuleRenderSnapshot(
            id: "\(id)::\(presentation.cacheKey)",
            moduleID: id,
            presentation: presentation,
            preferredHeight: preferredOpenedContentHeight,
            allowsInternalScrolling: allowsInternalScrolling,
            view: AnyView(FanModuleContentView(state: makeRenderState()))
        )
    }

    func makeLiveContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(FanModuleLiveContentView(model: self))
    }

    func updatePresentation(
        animationState: IslandFanAnimationState,
        logoPreset: WindDriveLogoPreset,
        customImage: NSImage?
    ) {
        let currentImageIdentifier = self.customImage.map(ObjectIdentifier.init)
        let nextImageIdentifier = customImage.map(ObjectIdentifier.init)
        guard self.animationState != animationState
            || self.logoPreset != logoPreset
            || currentImageIdentifier != nextImageIdentifier else {
            return
        }

        self.animationState = animationState
        self.logoPreset = logoPreset
        self.customImage = customImage
    }

    func makeRenderState() -> FanModuleRenderState {
        FanModuleRenderState(
            animationState: animationState,
            logoPreset: logoPreset,
            customImage: customImage
        )
    }
}
