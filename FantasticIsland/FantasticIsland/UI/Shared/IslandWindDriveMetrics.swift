import CoreGraphics

@MainActor
enum IslandWindDriveMetrics {
    static let defaultPanelSide: CGFloat = 218
    static let defaultHeroCornerRadius: CGFloat = 24
    static let defaultHeroShadowOpacity: CGFloat = 0.28
    static let defaultHeroShadowRadius: CGFloat = 24
    static let defaultHeroShadowYOffset: CGFloat = 14
    static let defaultBasePlateOpacity: CGFloat = 0.2
    static let defaultHubDiameter: CGFloat = 46
    static let defaultLogoSize: CGFloat = 28

    static var panelSide: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.panelSide) }
    static var heroCornerRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.heroCornerRadius) }
    static var heroShadowOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.heroShadowOpacity) }
    static var heroShadowRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.heroShadowRadius) }
    static var heroShadowYOffset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.heroShadowYOffset) }
    static var basePlateOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.basePlateOpacity) }
    static var hubDiameter: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.hubDiameter) }
    static var logoSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.logoSize) }
}
