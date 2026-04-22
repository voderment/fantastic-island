import SwiftUI

struct IslandWindDrivePanelView: View {
    let state: IslandWindDrivePanelRenderState

    var body: some View {
        OpenedIslandFanHeroView(
            animationState: state.animationState,
            logoPreset: state.logoPreset,
            customImage: state.customImage
        )
        .frame(
            width: CodexIslandChromeMetrics.windDrivePanelWidth,
            height: CodexIslandChromeMetrics.windDrivePanelHeight,
            alignment: .center
        )
    }
}
