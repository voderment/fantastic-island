import Foundation

struct DesignTokenLocalizedText {
    let english: String
    let simplifiedChinese: String
    let traditionalChinese: String

    init(_ english: String, _ simplifiedChinese: String, _ traditionalChinese: String? = nil) {
        self.english = english
        self.simplifiedChinese = simplifiedChinese
        self.traditionalChinese = traditionalChinese ?? simplifiedChinese
    }

    func resolve(for locale: Locale) -> String {
        switch DesignTokenEditorLocalization.language(for: locale) {
        case .english:
            return english
        case .simplifiedChinese:
            return simplifiedChinese
        case .traditionalChinese:
            return traditionalChinese
        }
    }
}

enum DesignTokenEditorLocalization {
    enum Language {
        case english
        case simplifiedChinese
        case traditionalChinese
    }

    enum ChromeText {
        case windowTitle
        case sidebarSection
        case writebackSection
        case sessionSection
        case debugSurfaceSection
        case panelLockTitle
        case mockScenarioTitle
        case triggerMockScenario
        case debugActiveState
        case savedConfigsSection
        case noSavedConfigs
        case revert
        case resetSingleToken
        case loadSavedConfig
        case saveConfig
        case writeBack
        case writeBackAll
        case openWorkspace
        case ready
        case dirty
        case selected
        case writebackCount
        case yes
        case no
        case none
        case unsavedChangesTitle
        case unsavedChangesMessage
        case discard
        case cancel
        case saveSucceededPrefix
        case saveFailedPrefix
        case writebackSucceededPrefix
        case writebackFailedPrefix
        case writebackAllSucceededPrefix
        case writebackAllFailedPrefix
        case revertedMessage
    }

    static func language(for locale: Locale) -> Language {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") {
            if identifier.contains("hant") || identifier.contains("tw") || identifier.contains("hk") || identifier.contains("mo") {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }
        return .english
    }

    static func text(_ chromeText: ChromeText, locale: Locale) -> String {
        chromeText.localizedText.resolve(for: locale)
    }

    static func groupTitle(_ group: IslandDesignTokenGroup, locale: Locale) -> String {
        (groupTitles[group] ?? DesignTokenLocalizedText(group.rawValue, group.rawValue)).resolve(for: locale)
    }

    static func title(for descriptor: IslandDesignTokenDescriptor, locale: Locale) -> String {
        (tokenTitles[descriptor.key] ?? DesignTokenLocalizedText(descriptor.title, descriptor.title)).resolve(for: locale)
    }

    static func detail(for descriptor: IslandDesignTokenDescriptor, locale: Locale) -> String {
        (tokenDetails[descriptor.key] ?? DesignTokenLocalizedText(descriptor.detail, descriptor.detail)).resolve(for: locale)
    }

    static func saveSucceededMessage(path: String, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Saved config to \(path)"
        case .simplifiedChinese:
            return "已将当前配置保存到 \(path)"
        case .traditionalChinese:
            return "已將目前設定儲存到 \(path)"
        }
    }

    static func writebackSucceededMessage(fileCount: Int, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Wrote \(fileCount) file(s)."
        case .simplifiedChinese:
            return "已回写 \(fileCount) 个文件。"
        case .traditionalChinese:
            return "已回寫 \(fileCount) 個檔案。"
        }
    }

    static func writebackGroupCountMessage(groupCount: Int, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "\(groupCount) group(s)"
        case .simplifiedChinese:
            return "\(groupCount) 组"
        case .traditionalChinese:
            return "\(groupCount) 組"
        }
    }

    static func singleTokenRevertedMessage(tokenName: String, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Reset \(tokenName) to the last saved value."
        case .simplifiedChinese:
            return "已将 \(tokenName) 恢复到上次保存的值。"
        case .traditionalChinese:
            return "已將 \(tokenName) 恢復到上次儲存的值。"
        }
    }

    static func loadedSavedConfigMessage(configName: String, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Loaded \(configName)"
        case .simplifiedChinese:
            return "已加载配置 \(configName)"
        case .traditionalChinese:
            return "已載入設定 \(configName)"
        }
    }

#if DEBUG
    static func debugLockModeTitle(_ mode: IslandDebugPanelLockMode, locale: Locale) -> String {
        let text: DesignTokenLocalizedText
        switch mode {
        case .automatic:
            text = DesignTokenLocalizedText("Auto", "自动", "自動")
        case .peek:
            text = DesignTokenLocalizedText("Lock Peek", "常开 Peek", "常開 Peek")
        case .expanded:
            text = DesignTokenLocalizedText("Lock Expanded", "常开展开态", "常開展開態")
        }

        return text.resolve(for: locale)
    }

    static func debugScenarioTitle(_ scenario: IslandDebugMockScenario, locale: Locale) -> String {
        let text: DesignTokenLocalizedText
        switch scenario {
        case .none:
            text = DesignTokenLocalizedText("Live Data", "实时数据", "即時資料")
        case .codexApprovalPeek:
            text = DesignTokenLocalizedText("Codex Approval Peek", "Codex 审批 Peek", "Codex 審批 Peek")
        case .codexCompletedPeek:
            text = DesignTokenLocalizedText("Codex Completed Peek", "Codex 完成通知 Peek", "Codex 完成通知 Peek")
        case .playerTrackSwitchPeek:
            text = DesignTokenLocalizedText("Player Track Peek", "Player 切歌 Peek", "Player 切歌 Peek")
        }

        return text.resolve(for: locale)
    }

    static func debugScenarioDetail(_ scenario: IslandDebugMockScenario, locale: Locale) -> String {
        let text: DesignTokenLocalizedText
        switch scenario {
        case .none:
            text = DesignTokenLocalizedText("Use the current runtime activity stream without injecting a mock scene.", "不注入 mock，直接使用当前运行时活动流。", "不注入 mock，直接使用目前執行中的活動流。")
        case .codexApprovalPeek:
            text = DesignTokenLocalizedText("Actionable Codex permission card for tuning interactive peek layout and hit targets.", "用于调试可交互 Peek 布局与命中区域的 Codex 审批卡片。", "用於調試可互動 Peek 版面與命中區域的 Codex 審批卡片。")
        case .codexCompletedPeek:
            text = DesignTokenLocalizedText("Transient Codex completion card for tuning notification-style peek spacing and text rhythm.", "用于调试通知型 Peek 间距与文本节奏的 Codex 完成卡片。", "用於調試通知型 Peek 間距與文字節奏的 Codex 完成卡片。")
        case .playerTrackSwitchPeek:
            text = DesignTokenLocalizedText("Player artwork-and-text peek for tuning media notification spacing and minimum height.", "用于调试媒体通知封面与文本布局的 Player 切歌卡片。", "用於調試媒體通知封面與文字版面的 Player 切歌卡片。")
        }

        return text.resolve(for: locale)
    }

    static func debugLockModeChangedMessage(mode: IslandDebugPanelLockMode, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Updated panel lock mode to \(debugLockModeTitle(mode, locale: locale))."
        case .simplifiedChinese:
            return "已将面板锁定模式切换为 \(debugLockModeTitle(mode, locale: locale))。"
        case .traditionalChinese:
            return "已將面板鎖定模式切換為 \(debugLockModeTitle(mode, locale: locale))。"
        }
    }

    static func debugScenarioSelectedMessage(scenario: IslandDebugMockScenario, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Selected mock scene: \(debugScenarioTitle(scenario, locale: locale))."
        case .simplifiedChinese:
            return "已选择调试场景：\(debugScenarioTitle(scenario, locale: locale))。"
        case .traditionalChinese:
            return "已選擇調試場景：\(debugScenarioTitle(scenario, locale: locale))。"
        }
    }

    static func debugTriggerSucceededMessage(scenario: IslandDebugMockScenario, locale: Locale) -> String {
        switch language(for: locale) {
        case .english:
            return "Triggered \(debugScenarioTitle(scenario, locale: locale))."
        case .simplifiedChinese:
            return "已触发 \(debugScenarioTitle(scenario, locale: locale))。"
        case .traditionalChinese:
            return "已觸發 \(debugScenarioTitle(scenario, locale: locale))。"
        }
    }
#endif

    private static let groupTitles: [IslandDesignTokenGroup: DesignTokenLocalizedText] = [
        .shell: DesignTokenLocalizedText("Shell", "壳体", "殼體"),
        .peek: DesignTokenLocalizedText("Peek", "Peek", "Peek"),
        .windDrive: DesignTokenLocalizedText("Wind Drive", "Wind Drive", "Wind Drive"),
        .codexExpanded: DesignTokenLocalizedText("Codex Expanded", "Codex 展开态", "Codex 展開態"),
        .clashExpanded: DesignTokenLocalizedText("Clash Expanded", "Clash 展开态", "Clash 展開態"),
        .playerExpanded: DesignTokenLocalizedText("Player Expanded", "Player 展开态", "Player 展開態"),
    ]

    private static let tokenTitles: [IslandDesignTokenKey: DesignTokenLocalizedText] = [
        .shellOpenedShadowHorizontalInset: DesignTokenLocalizedText("Shadow Horizontal Inset", "阴影水平外扩"),
        .shellOpenedSurfaceContentHorizontalInset: DesignTokenLocalizedText("Surface Horizontal Inset", "内容安全水平内边距"),
        .shellClosedHoverScale: DesignTokenLocalizedText("Closed Hover Scale", "收起态悬停缩放"),
        .shellClosedHorizontalPadding: DesignTokenLocalizedText("Closed Horizontal Padding", "收起态水平内边距"),
        .shellClosedFanModuleSpacing: DesignTokenLocalizedText("Closed Fan-to-Modules Spacing", "收起态风扇与模块间距"),
        .shellClosedModuleSpacing: DesignTokenLocalizedText("Closed Module Spacing", "收起态模块间距"),
        .shellClosedModuleContentSpacing: DesignTokenLocalizedText("Closed Module Content Spacing", "收起态单模块内容间距"),
        .shellClosedIconSize: DesignTokenLocalizedText("Closed Icon Size", "收起态图标尺寸"),
        .shellClosedPrimaryFontSize: DesignTokenLocalizedText("Closed Primary Font Size", "收起态主字号"),
        .shellClosedTrafficFontSize: DesignTokenLocalizedText("Closed Traffic Font Size", "收起态流量字号"),
        .shellClosedTrafficLineSpacing: DesignTokenLocalizedText("Closed Traffic Line Spacing", "收起态流量行距"),
        .shellOpenedBodyRevealDelay: DesignTokenLocalizedText("Opened Body Delay", "展开内容显现延迟"),
        .shellOpenLayoutSettleDuration: DesignTokenLocalizedText("Open Layout Settle", "展开布局锁定时长"),
        .shellCloseLayoutSettleDuration: DesignTokenLocalizedText("Close Layout Settle", "收起布局锁定时长"),
        .shellExpandedContentBottomPadding: DesignTokenLocalizedText("Expanded Bottom Padding", "展开内容底部留白"),
        .shellExpandedContentTopPadding: DesignTokenLocalizedText("Expanded Top Padding", "展开内容顶部留白"),
        .shellModuleColumnSpacing: DesignTokenLocalizedText("Module Column Spacing", "双列间距"),
        .shellModuleNavigationRowHeight: DesignTokenLocalizedText("Navigation Row Height", "顶部导航行高度"),
        .shellModuleTabSpacing: DesignTokenLocalizedText("Tab Spacing", "标签间距"),
        .shellModuleTabHorizontalPadding: DesignTokenLocalizedText("Tab Horizontal Padding", "标签水平内边距"),
        .shellModuleTabVerticalPadding: DesignTokenLocalizedText("Tab Vertical Padding", "标签垂直内边距"),
        .shellModuleHeaderToolbarSpacing: DesignTokenLocalizedText("Header Toolbar Spacing", "头部与工具栏间距"),
        .shellModuleToolbarButtonGroupSpacing: DesignTokenLocalizedText("Toolbar Button Group Spacing", "工具栏按钮组间距"),
        .peekContentHorizontalInset: DesignTokenLocalizedText("Peek Horizontal Inset", "Peek 水平内边距"),
        .peekContentTopPadding: DesignTokenLocalizedText("Peek Top Padding", "Peek 顶部留白"),
        .peekContentBottomPadding: DesignTokenLocalizedText("Peek Bottom Padding", "Peek 底部留白"),
        .peekMinimumContentWidth: DesignTokenLocalizedText("Peek Min Width", "Peek 最小宽度"),
        .peekMaximumContentWidth: DesignTokenLocalizedText("Peek Max Width", "Peek 最大宽度"),
        .peekContentWidthFactor: DesignTokenLocalizedText("Peek Width Factor", "Peek 宽度系数"),
        .peekOpenAnimationDuration: DesignTokenLocalizedText("Open Animation", "打开动画时长"),
        .peekCloseAnimationDuration: DesignTokenLocalizedText("Close Animation", "关闭动画时长"),
        .peekChromeRevealAnimationDuration: DesignTokenLocalizedText("Chrome Reveal", "外壳显现时长"),
        .peekBodyCloseFadeDuration: DesignTokenLocalizedText("Body Close Fade", "主体淡出时长"),
        .peekClosedHeaderRevealDuration: DesignTokenLocalizedText("Header Reveal Duration", "收起头部回显时长"),
        .peekClosedHeaderRevealLeadTime: DesignTokenLocalizedText("Header Reveal Lead", "收起头部提前量"),
        .windDrivePanelSide: DesignTokenLocalizedText("Panel Side", "Wind Drive 面板边长"),
        .windDriveHeroCornerRadius: DesignTokenLocalizedText("Hero Corner Radius", "Hero 圆角"),
        .windDriveHeroShadowOpacity: DesignTokenLocalizedText("Hero Shadow Opacity", "Hero 阴影不透明度"),
        .windDriveHeroShadowRadius: DesignTokenLocalizedText("Hero Shadow Radius", "Hero 阴影模糊半径"),
        .windDriveHeroShadowYOffset: DesignTokenLocalizedText("Hero Shadow Y", "Hero 阴影垂直偏移"),
        .windDriveBasePlateOpacity: DesignTokenLocalizedText("Base Plate Opacity", "底板不透明度"),
        .windDriveHubDiameter: DesignTokenLocalizedText("Hub Diameter", "中心 Hub 直径"),
        .windDriveLogoSize: DesignTokenLocalizedText("Logo Size", "Logo 尺寸"),
        .codexPeekRowSpacing: DesignTokenLocalizedText("Codex Peek Row Spacing", "Codex Peek 行内间距"),
        .codexPeekContentSpacing: DesignTokenLocalizedText("Codex Peek Content Spacing", "Codex Peek 文本间距"),
        .codexPeekBadgeSpacing: DesignTokenLocalizedText("Codex Peek Badge Spacing", "Codex Peek 徽标间距"),
        .codexPeekCardHorizontalPadding: DesignTokenLocalizedText("Codex Peek Horizontal Padding", "Codex Peek 水平内边距"),
        .codexPeekCardVerticalPadding: DesignTokenLocalizedText("Codex Peek Vertical Padding", "Codex Peek 垂直内边距"),
        .codexPeekStatusDotSize: DesignTokenLocalizedText("Codex Peek Dot Size", "Codex Peek 状态点尺寸"),
        .codexPeekStatusDotTopPadding: DesignTokenLocalizedText("Codex Peek Dot Top Padding", "Codex Peek 状态点顶部修正"),
        .codexPeekTitleFontSize: DesignTokenLocalizedText("Codex Peek Title Size", "Codex Peek 标题字号"),
        .codexPeekPromptFontSize: DesignTokenLocalizedText("Codex Peek Prompt Size", "Codex Peek Prompt 字号"),
        .codexPeekSummaryFontSize: DesignTokenLocalizedText("Codex Peek Summary Size", "Codex Peek 摘要字号"),
        .codexPeekPromptOpacity: DesignTokenLocalizedText("Codex Peek Prompt Opacity", "Codex Peek Prompt 不透明度"),
        .codexPeekSummaryOpacity: DesignTokenLocalizedText("Codex Peek Summary Opacity", "Codex Peek 摘要不透明度"),
        .codexPeekBackgroundOpacity: DesignTokenLocalizedText("Codex Peek Background Opacity", "Codex Peek 背景不透明度"),
        .codexPeekStatusDotColor: DesignTokenLocalizedText("Codex Peek Status Color", "Codex Peek 状态点颜色"),
        .playerPeekHorizontalSpacing: DesignTokenLocalizedText("Player Peek Horizontal Spacing", "Player Peek 水平间距"),
        .playerPeekTextSpacing: DesignTokenLocalizedText("Player Peek Text Spacing", "Player Peek 文本间距"),
        .playerPeekTitleFontSize: DesignTokenLocalizedText("Player Peek Title Size", "Player Peek 标题字号"),
        .playerPeekArtistFontSize: DesignTokenLocalizedText("Player Peek Artist Size", "Player Peek 歌手字号"),
        .playerPeekContentHorizontalPadding: DesignTokenLocalizedText("Player Peek Horizontal Padding", "Player Peek 水平内边距"),
        .playerPeekContentVerticalPadding: DesignTokenLocalizedText("Player Peek Vertical Padding", "Player Peek 垂直内边距"),
        .playerPeekMinimumHeight: DesignTokenLocalizedText("Player Peek Minimum Height", "Player Peek 最小高度"),
        .playerPeekArtworkCornerRadius: DesignTokenLocalizedText("Player Peek Artwork Radius", "Player Peek 封面圆角"),
        .playerPeekArtworkSize: DesignTokenLocalizedText("Player Peek Artwork Size", "Player Peek 封面尺寸"),
        .playerPeekPlaceholderSymbolSize: DesignTokenLocalizedText("Player Peek Placeholder Size", "Player Peek 占位符尺寸"),
        .playerPeekTitleOpacity: DesignTokenLocalizedText("Player Peek Title Opacity", "Player Peek 标题不透明度"),
        .playerPeekArtistOpacity: DesignTokenLocalizedText("Player Peek Artist Opacity", "Player Peek 歌手不透明度"),
        .playerPeekPlaceholderOpacity: DesignTokenLocalizedText("Player Peek Placeholder Opacity", "Player Peek 占位符不透明度"),
        .playerPeekArtworkBackgroundStartOpacity: DesignTokenLocalizedText("Player Peek Artwork Start Opacity", "Player Peek 封面背景起始不透明度"),
        .playerPeekArtworkBackgroundEndOpacity: DesignTokenLocalizedText("Player Peek Artwork End Opacity", "Player Peek 封面背景结束不透明度"),
        .codexExpandedContentSpacing: DesignTokenLocalizedText("Codex Content Spacing", "Codex 内容主间距"),
        .codexExpandedSectionRowSpacing: DesignTokenLocalizedText("Codex Section Row Spacing", "Codex 卡片间距"),
        .codexExpandedGlobalInfoBadgeSpacing: DesignTokenLocalizedText("Codex Badge Spacing", "Codex 全局信息徽标间距"),
        .codexExpandedEmptyStateMinimumHeight: DesignTokenLocalizedText("Codex Empty Min Height", "Codex 空态最小高度"),
        .codexExpandedCardCornerRadius: DesignTokenLocalizedText("Codex Card Radius", "Codex 卡片圆角"),
        .codexExpandedCardBackgroundOpacity: DesignTokenLocalizedText("Codex Card Background", "Codex 卡片背景不透明度"),
        .codexExpandedCardBorderOpacity: DesignTokenLocalizedText("Codex Card Border", "Codex 卡片边框不透明度"),
        .codexExpandedTitleFontSize: DesignTokenLocalizedText("Codex Title Size", "Codex 标题字号"),
        .codexExpandedSummaryFontSize: DesignTokenLocalizedText("Codex Summary Size", "Codex 摘要字号"),
        .clashExpandedOuterSpacing: DesignTokenLocalizedText("Clash Outer Spacing", "Clash 主间距"),
        .clashExpandedCardSpacing: DesignTokenLocalizedText("Clash Card Spacing", "Clash 卡片间距"),
        .clashExpandedSectionTitleSpacing: DesignTokenLocalizedText("Clash Section Spacing", "Clash 分区标题间距"),
        .clashExpandedCardCornerRadius: DesignTokenLocalizedText("Clash Card Radius", "Clash 卡片圆角"),
        .clashExpandedCardBackgroundOpacity: DesignTokenLocalizedText("Clash Card Background", "Clash 卡片背景不透明度"),
        .clashExpandedCardBorderOpacity: DesignTokenLocalizedText("Clash Card Border", "Clash 卡片边框不透明度"),
        .clashExpandedActionPillCornerRadius: DesignTokenLocalizedText("Clash Pill Radius", "Clash 操作胶囊圆角"),
        .clashExpandedActionPillVerticalPadding: DesignTokenLocalizedText("Clash Pill Vertical Padding", "Clash 操作胶囊垂直内边距"),
        .playerExpandedOuterSpacing: DesignTokenLocalizedText("Player Outer Spacing", "Player 主间距"),
        .playerExpandedPrimaryColumnSpacing: DesignTokenLocalizedText("Player Column Spacing", "Player 双列间距"),
        .playerExpandedTitleBlockSpacing: DesignTokenLocalizedText("Player Title Block Spacing", "Player 标题块间距"),
        .playerExpandedControlsSpacing: DesignTokenLocalizedText("Player Controls Spacing", "Player 控件间距"),
        .playerExpandedArtworkCornerRadius: DesignTokenLocalizedText("Player Artwork Radius", "Player 封面圆角"),
        .playerExpandedArtworkSize: DesignTokenLocalizedText("Player Artwork Size", "Player 封面尺寸"),
        .playerExpandedProgressSectionSpacing: DesignTokenLocalizedText("Player Progress Spacing", "Player 进度区间距"),
        .playerExpandedControlButtonOpacityDisabled: DesignTokenLocalizedText("Player Disabled Controls Opacity", "Player 禁用控件不透明度"),
    ]

    private static let tokenDetails: [IslandDesignTokenKey: DesignTokenLocalizedText] = [
        .shellOpenedShadowHorizontalInset: DesignTokenLocalizedText("Opened shell outer shadow width.", "控制展开态外层阴影横向延展范围，数值越大阴影覆盖越宽。"),
        .shellOpenedSurfaceContentHorizontalInset: DesignTokenLocalizedText("Opened shell content safe inset.", "控制展开态内容距离壳体左右边缘的安全间距。"),
        .shellClosedHoverScale: DesignTokenLocalizedText("Hover scale applied in collapsed state.", "控制收起态鼠标悬停时的放大幅度。"),
        .shellClosedHorizontalPadding: DesignTokenLocalizedText("Left and right inset for the collapsed header row.", "控制收起态整行内容距离左右边缘的留白。"),
        .shellClosedFanModuleSpacing: DesignTokenLocalizedText("Gap between the fan icon and the compact module summary area.", "控制左侧风扇图标和右侧紧凑模块摘要区之间的距离。"),
        .shellClosedModuleSpacing: DesignTokenLocalizedText("Gap between compact module summaries.", "控制收起态各模块摘要之间的横向距离。"),
        .shellClosedModuleContentSpacing: DesignTokenLocalizedText("Gap between icon and text inside one compact module summary.", "控制收起态单个模块里图标与文本之间的距离。"),
        .shellClosedIconSize: DesignTokenLocalizedText("Compact module icon size in collapsed state.", "控制收起态模块图标的尺寸。"),
        .shellClosedPrimaryFontSize: DesignTokenLocalizedText("Main compact summary font size.", "控制收起态主文本的字号。"),
        .shellClosedTrafficFontSize: DesignTokenLocalizedText("Compact Clash traffic text font size.", "控制收起态 Clash 上下行流量文本的字号。"),
        .shellClosedTrafficLineSpacing: DesignTokenLocalizedText("Vertical spacing between upload and download lines.", "控制收起态 Clash 上传下载两行之间的垂直间距。"),
        .shellOpenedBodyRevealDelay: DesignTokenLocalizedText("Delay before expanded body reveal.", "控制壳体展开后主体内容开始出现前的等待时间。"),
        .shellOpenLayoutSettleDuration: DesignTokenLocalizedText("Layout lock duration during expansion.", "控制展开过程中锁定高度与布局的持续时间，用来避免高度跳变。"),
        .shellCloseLayoutSettleDuration: DesignTokenLocalizedText("Layout lock duration during collapse.", "控制收起过程中锁定高度与布局的持续时间。"),
        .shellExpandedContentBottomPadding: DesignTokenLocalizedText("Bottom breathing room for module content.", "调整展开态模块内容底部的呼吸空间。"),
        .shellExpandedContentTopPadding: DesignTokenLocalizedText("Top gap above expanded content.", "调整展开态模块内容上方的起始间隙。"),
        .shellModuleColumnSpacing: DesignTokenLocalizedText("Gap between Wind Drive and right column.", "控制 Wind Drive 面板与右侧模块列之间的距离。"),
        .shellModuleNavigationRowHeight: DesignTokenLocalizedText("Expanded top row baseline height.", "控制展开态标签和工具栏所在顶部行的基准高度。"),
        .shellModuleTabSpacing: DesignTokenLocalizedText("Gap between module tabs.", "控制模块标签之间的水平距离。"),
        .shellModuleTabHorizontalPadding: DesignTokenLocalizedText("Single tab horizontal inset.", "控制单个标签左右的留白。"),
        .shellModuleTabVerticalPadding: DesignTokenLocalizedText("Single tab vertical inset.", "控制单个标签上下的留白。"),
        .shellModuleHeaderToolbarSpacing: DesignTokenLocalizedText("Gap between tabs and toolbar.", "控制标签区域与右侧工具栏之间的距离。"),
        .shellModuleToolbarButtonGroupSpacing: DesignTokenLocalizedText("Gap inside toolbar button group.", "控制工具栏内部按钮组之间的距离。"),
        .peekContentHorizontalInset: DesignTokenLocalizedText("Horizontal inset for peek content.", "控制 peek 内容距离左右边缘的水平留白。"),
        .peekContentTopPadding: DesignTokenLocalizedText("Top breathing room for peek content.", "控制 peek 内容顶部的留白。"),
        .peekContentBottomPadding: DesignTokenLocalizedText("Bottom breathing room for peek content.", "控制 peek 内容底部的留白。"),
        .peekMinimumContentWidth: DesignTokenLocalizedText("Minimum width on narrow screens.", "控制窄屏或紧凑场景下 peek 内容的最小宽度。"),
        .peekMaximumContentWidth: DesignTokenLocalizedText("Maximum width on wide screens.", "控制宽屏场景下 peek 内容的最大宽度。"),
        .peekContentWidthFactor: DesignTokenLocalizedText("Viewport width ratio for peek content.", "控制 peek 内容宽度相对于可用视口宽度的占比。"),
        .peekOpenAnimationDuration: DesignTokenLocalizedText("Closed to peek/expanded morph duration.", "控制从收起态切换到 peek 或 expanded 的过渡时长。"),
        .peekCloseAnimationDuration: DesignTokenLocalizedText("Peek/expanded to closed duration.", "控制从 peek 或 expanded 收回到收起态的过渡时长。"),
        .peekChromeRevealAnimationDuration: DesignTokenLocalizedText("Reveal duration for opened chrome.", "控制打开后外层壳体 chrome 的显现速度。"),
        .peekBodyCloseFadeDuration: DesignTokenLocalizedText("Body fade-out duration during close.", "控制关闭过程中主体内容淡出的时长。"),
        .peekClosedHeaderRevealDuration: DesignTokenLocalizedText("Collapsed header re-entry fade duration.", "控制收起头部重新出现时的淡入时长。"),
        .peekClosedHeaderRevealLeadTime: DesignTokenLocalizedText("How early header starts returning before close ends.", "控制在关闭动画结束前多久开始让收起头部回归。"),
        .windDrivePanelSide: DesignTokenLocalizedText("Expanded Wind Drive panel width/height.", "控制 Wind Drive 展开面板的边长。"),
        .windDriveHeroCornerRadius: DesignTokenLocalizedText("Wind Drive hero tile radius.", "控制 Wind Drive 主面板卡片的圆角。"),
        .windDriveHeroShadowOpacity: DesignTokenLocalizedText("Wind Drive hero shadow opacity.", "控制 Wind Drive 主面板阴影的浓度。"),
        .windDriveHeroShadowRadius: DesignTokenLocalizedText("Wind Drive hero shadow blur radius.", "控制 Wind Drive 主面板阴影的模糊半径。"),
        .windDriveHeroShadowYOffset: DesignTokenLocalizedText("Wind Drive hero shadow y offset.", "控制 Wind Drive 主面板阴影的垂直偏移。"),
        .windDriveBasePlateOpacity: DesignTokenLocalizedText("Base plate fill opacity.", "控制风扇底板填充层的不透明度。"),
        .windDriveHubDiameter: DesignTokenLocalizedText("Center hub diameter.", "控制风扇中心 Hub 的直径。"),
        .windDriveLogoSize: DesignTokenLocalizedText("Logo mark size inside hub.", "控制 Hub 内 Logo 标记的尺寸。"),
        .codexPeekRowSpacing: DesignTokenLocalizedText("Gap between dot and text column.", "控制 Codex Peek 中状态点与文本列之间的距离。"),
        .codexPeekContentSpacing: DesignTokenLocalizedText("Gap between Codex peek text rows.", "控制 Codex Peek 中文本行之间的垂直间距。"),
        .codexPeekBadgeSpacing: DesignTokenLocalizedText("Gap between badge pills.", "控制 Codex Peek 中徽标胶囊之间的距离。"),
        .codexPeekCardHorizontalPadding: DesignTokenLocalizedText("Horizontal padding inside Codex peek card.", "控制 Codex Peek 卡片内部左右留白。"),
        .codexPeekCardVerticalPadding: DesignTokenLocalizedText("Vertical padding inside Codex peek card.", "控制 Codex Peek 卡片内部上下留白。"),
        .codexPeekStatusDotSize: DesignTokenLocalizedText("Completion dot size.", "控制完成状态点的尺寸。"),
        .codexPeekStatusDotTopPadding: DesignTokenLocalizedText("Visual vertical correction for status dot.", "微调状态点的垂直位置补偿。"),
        .codexPeekTitleFontSize: DesignTokenLocalizedText("Title font size for Codex peek.", "控制 Codex Peek 标题的字号。"),
        .codexPeekPromptFontSize: DesignTokenLocalizedText("Prompt font size for Codex peek.", "控制 Codex Peek Prompt 的字号。"),
        .codexPeekSummaryFontSize: DesignTokenLocalizedText("Summary font size for Codex peek.", "控制 Codex Peek 摘要文本的字号。"),
        .codexPeekPromptOpacity: DesignTokenLocalizedText("Prompt text opacity.", "控制 Codex Peek Prompt 文本的不透明度。"),
        .codexPeekSummaryOpacity: DesignTokenLocalizedText("Summary text opacity.", "控制 Codex Peek 摘要文本的不透明度。"),
        .codexPeekBackgroundOpacity: DesignTokenLocalizedText("Peek card background opacity.", "控制 Codex Peek 卡片背景的不透明度。"),
        .codexPeekStatusDotColor: DesignTokenLocalizedText("Semantic status color for completion dot.", "控制完成状态点所使用的语义颜色。"),
        .playerPeekHorizontalSpacing: DesignTokenLocalizedText("Gap between artwork and text block.", "控制 Player Peek 中封面与文本块之间的距离。"),
        .playerPeekTextSpacing: DesignTokenLocalizedText("Gap between title and artist lines.", "控制 Player Peek 标题和歌手两行之间的距离。"),
        .playerPeekTitleFontSize: DesignTokenLocalizedText("Player peek title size.", "控制 Player Peek 标题的字号。"),
        .playerPeekArtistFontSize: DesignTokenLocalizedText("Player peek artist size.", "控制 Player Peek 歌手名称的字号。"),
        .playerPeekContentHorizontalPadding: DesignTokenLocalizedText("Inner horizontal padding inside Player peek content.", "控制 Player Peek 内容内部左右留白。"),
        .playerPeekContentVerticalPadding: DesignTokenLocalizedText("Inner vertical padding inside Player peek content.", "控制 Player Peek 内容内部上下留白。"),
        .playerPeekMinimumHeight: DesignTokenLocalizedText("Minimum content height for Player peek.", "控制 Player Peek 内容的最小高度。"),
        .playerPeekArtworkCornerRadius: DesignTokenLocalizedText("Corner radius for peek artwork.", "控制 Player Peek 封面的圆角。"),
        .playerPeekArtworkSize: DesignTokenLocalizedText("Artwork size in peek mode.", "控制 Player Peek 模式下封面的尺寸。"),
        .playerPeekPlaceholderSymbolSize: DesignTokenLocalizedText("Placeholder symbol size.", "控制无封面时占位图标的尺寸。"),
        .playerPeekTitleOpacity: DesignTokenLocalizedText("Title opacity for player peek.", "控制 Player Peek 标题文本的不透明度。"),
        .playerPeekArtistOpacity: DesignTokenLocalizedText("Artist opacity for player peek.", "控制 Player Peek 歌手文本的不透明度。"),
        .playerPeekPlaceholderOpacity: DesignTokenLocalizedText("Placeholder icon opacity.", "控制占位图标的不透明度。"),
        .playerPeekArtworkBackgroundStartOpacity: DesignTokenLocalizedText("Gradient start opacity behind artwork.", "控制封面背景渐变起始端的不透明度。"),
        .playerPeekArtworkBackgroundEndOpacity: DesignTokenLocalizedText("Gradient end opacity behind artwork.", "控制封面背景渐变结束端的不透明度。"),
        .codexExpandedContentSpacing: DesignTokenLocalizedText("Primary vertical spacing inside Codex expanded content.", "控制 Codex 展开态内部主要纵向间距。"),
        .codexExpandedSectionRowSpacing: DesignTokenLocalizedText("Gap between session cards.", "控制 Codex 会话卡片之间的距离。"),
        .codexExpandedGlobalInfoBadgeSpacing: DesignTokenLocalizedText("Spacing inside Global Info badge row.", "控制 Codex 顶部全局信息徽标行的内部间距。"),
        .codexExpandedEmptyStateMinimumHeight: DesignTokenLocalizedText("Minimum height for Codex empty state.", "控制 Codex 空态面板的最小高度。"),
        .codexExpandedCardCornerRadius: DesignTokenLocalizedText("Common Codex card radius.", "控制 Codex 常用卡片的统一圆角。"),
        .codexExpandedCardBackgroundOpacity: DesignTokenLocalizedText("Common Codex card background opacity.", "控制 Codex 常用卡片背景的不透明度。"),
        .codexExpandedCardBorderOpacity: DesignTokenLocalizedText("Common Codex card border opacity.", "控制 Codex 常用卡片边框的不透明度。"),
        .codexExpandedTitleFontSize: DesignTokenLocalizedText("Primary title size in Codex cards.", "控制 Codex 卡片主标题的字号。"),
        .codexExpandedSummaryFontSize: DesignTokenLocalizedText("Summary text size in Codex cards.", "控制 Codex 卡片摘要文本的字号。"),
        .clashExpandedOuterSpacing: DesignTokenLocalizedText("Primary vertical spacing inside Clash content.", "控制 Clash 展开态内部主要纵向间距。"),
        .clashExpandedCardSpacing: DesignTokenLocalizedText("Gap between Clash cards.", "控制 Clash 卡片之间的距离。"),
        .clashExpandedSectionTitleSpacing: DesignTokenLocalizedText("Spacing below section title.", "控制 Clash 分区标题与内容之间的距离。"),
        .clashExpandedCardCornerRadius: DesignTokenLocalizedText("Common Clash card radius.", "控制 Clash 常用卡片的统一圆角。"),
        .clashExpandedCardBackgroundOpacity: DesignTokenLocalizedText("Common Clash card background opacity.", "控制 Clash 常用卡片背景的不透明度。"),
        .clashExpandedCardBorderOpacity: DesignTokenLocalizedText("Common Clash card border opacity.", "控制 Clash 常用卡片边框的不透明度。"),
        .clashExpandedActionPillCornerRadius: DesignTokenLocalizedText("Corner radius for action pills.", "控制 Clash 操作胶囊按钮的圆角。"),
        .clashExpandedActionPillVerticalPadding: DesignTokenLocalizedText("Vertical padding for action pills.", "控制 Clash 操作胶囊按钮的上下留白。"),
        .playerExpandedOuterSpacing: DesignTokenLocalizedText("Primary vertical spacing inside Player content.", "控制 Player 展开态内部主要纵向间距。"),
        .playerExpandedPrimaryColumnSpacing: DesignTokenLocalizedText("Gap between text column and artwork.", "控制 Player 文本列与封面之间的距离。"),
        .playerExpandedTitleBlockSpacing: DesignTokenLocalizedText("Gap in title block.", "控制 Player 标题块内部的行间距。"),
        .playerExpandedControlsSpacing: DesignTokenLocalizedText("Gap between transport controls.", "控制 Player 播放控制按钮之间的距离。"),
        .playerExpandedArtworkCornerRadius: DesignTokenLocalizedText("Artwork radius in expanded mode.", "控制 Player 展开态封面的圆角。"),
        .playerExpandedArtworkSize: DesignTokenLocalizedText("Artwork size in expanded mode.", "控制 Player 展开态封面的尺寸。"),
        .playerExpandedProgressSectionSpacing: DesignTokenLocalizedText("Gap inside progress section.", "控制 Player 进度区内部的间距。"),
        .playerExpandedControlButtonOpacityDisabled: DesignTokenLocalizedText("Opacity for disabled transport controls.", "控制 Player 禁用播放控制按钮时的不透明度。"),
    ]
}

private extension DesignTokenEditorLocalization.ChromeText {
    var localizedText: DesignTokenLocalizedText {
        switch self {
        case .windowTitle:
            return DesignTokenLocalizedText("Design Tokens", "设计参数", "設計參數")
        case .sidebarSection:
            return DesignTokenLocalizedText("DESIGN TOKENS", "设计参数", "設計參數")
        case .debugSurfaceSection:
            return DesignTokenLocalizedText("DEBUG SURFACE", "调试态面板", "調試態面板")
        case .panelLockTitle:
            return DesignTokenLocalizedText("PANEL LOCK", "面板锁定", "面板鎖定")
        case .mockScenarioTitle:
            return DesignTokenLocalizedText("MOCK SCENE", "Mock 场景", "Mock 場景")
        case .triggerMockScenario:
            return DesignTokenLocalizedText("Trigger Mock", "触发 Mock", "觸發 Mock")
        case .debugActiveState:
            return DesignTokenLocalizedText("Active Debug State", "当前调试态", "目前調試態")
        case .writebackSection:
            return DesignTokenLocalizedText("WRITE BACK", "回写", "回寫")
        case .sessionSection:
            return DesignTokenLocalizedText("SESSION", "会话", "會話")
        case .savedConfigsSection:
            return DesignTokenLocalizedText("SAVED CONFIGS", "已保存配置", "已儲存設定")
        case .noSavedConfigs:
            return DesignTokenLocalizedText("No saved configs yet.", "还没有已保存配置。", "還沒有已儲存設定。")
        case .revert:
            return DesignTokenLocalizedText("Revert", "还原", "還原")
        case .resetSingleToken:
            return DesignTokenLocalizedText("Reset", "还原此项", "還原此項")
        case .loadSavedConfig:
            return DesignTokenLocalizedText("Load", "加载", "載入")
        case .saveConfig:
            return DesignTokenLocalizedText("Save Config", "保存配置", "儲存設定")
        case .writeBack:
            return DesignTokenLocalizedText("Write Back", "回写", "回寫")
        case .writeBackAll:
            return DesignTokenLocalizedText("Write Back All", "全部回写", "全部回寫")
        case .openWorkspace:
            return DesignTokenLocalizedText("Open Workspace", "打开工作区", "開啟工作區")
        case .ready:
            return DesignTokenLocalizedText("Ready", "就绪", "就緒")
        case .dirty:
            return DesignTokenLocalizedText("Dirty", "未保存修改", "未儲存修改")
        case .selected:
            return DesignTokenLocalizedText("Selected", "当前分组", "目前分組")
        case .writebackCount:
            return DesignTokenLocalizedText("Writeback", "回写分组", "回寫分組")
        case .yes:
            return DesignTokenLocalizedText("YES", "是", "是")
        case .no:
            return DesignTokenLocalizedText("NO", "否", "否")
        case .none:
            return DesignTokenLocalizedText("None", "无", "無")
        case .unsavedChangesTitle:
            return DesignTokenLocalizedText("Unsaved token changes", "存在未保存的参数修改", "存在未儲存的參數修改")
        case .unsavedChangesMessage:
            return DesignTokenLocalizedText("Save the current design token config before closing?", "关闭前是否先保存当前设计参数配置？", "關閉前是否先儲存目前設計參數設定？")
        case .discard:
            return DesignTokenLocalizedText("Discard", "放弃修改", "放棄修改")
        case .cancel:
            return DesignTokenLocalizedText("Cancel", "取消", "取消")
        case .saveSucceededPrefix:
            return DesignTokenLocalizedText("Saved config to", "已将当前配置保存到", "已將目前設定儲存到")
        case .saveFailedPrefix:
            return DesignTokenLocalizedText("Save failed", "保存失败", "儲存失敗")
        case .writebackSucceededPrefix:
            return DesignTokenLocalizedText("Wrote", "已回写", "已回寫")
        case .writebackFailedPrefix:
            return DesignTokenLocalizedText("Write Back failed", "回写失败", "回寫失敗")
        case .writebackAllSucceededPrefix:
            return DesignTokenLocalizedText("Wrote", "已全部回写", "已全部回寫")
        case .writebackAllFailedPrefix:
            return DesignTokenLocalizedText("Write Back All failed", "全部回写失败", "全部回寫失敗")
        case .revertedMessage:
            return DesignTokenLocalizedText("Reverted to last saved config.", "已恢复到上次保存的配置。", "已恢復到上次儲存的設定。")
        }
    }
}

extension IslandDesignTokenGroup {
    func displayTitle(for locale: Locale) -> String {
        DesignTokenEditorLocalization.groupTitle(self, locale: locale)
    }
}

extension IslandDesignTokenDescriptor {
    func displayTitle(for locale: Locale) -> String {
        DesignTokenEditorLocalization.title(for: self, locale: locale)
    }

    func displayDetail(for locale: Locale) -> String {
        DesignTokenEditorLocalization.detail(for: self, locale: locale)
    }
}
