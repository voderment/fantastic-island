import AppKit
import SwiftUI

private let compactIslandFanIconSize: CGFloat = 20

struct IslandFanIconView: View, Equatable {
    let animationState: IslandFanAnimationState

    var body: some View {
        Group {
            if let compactFanSymbol = CodexIslandFanAssets.compactFanSymbol {
                RotatingImageView(
                    image: compactFanSymbol,
                    size: CGSize(width: compactIslandFanIconSize, height: compactIslandFanIconSize),
                    tintColor: .white,
                    animationState: animationState
                )
            } else {
                compactFallbackSymbol(rotationDegrees: animationState.rotationDegrees())
            }
        }
        .frame(width: compactIslandFanIconSize, height: compactIslandFanIconSize)
    }

    private func compactFallbackSymbol(rotationDegrees: Double) -> some View {
        Image(systemName: "fanblades.fill")
            .font(.system(size: compactIslandFanIconSize, weight: .semibold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(rotationDegrees))
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

struct OpenedIslandFanHeroView: View {
    let animationState: IslandFanAnimationState
    let logoPreset: WindDriveLogoPreset
    let customImage: NSImage?

    var body: some View {
        ZStack {
            basePlate
            fanBladeLayer
            logoHub
        }
        .frame(width: IslandWindDriveMetrics.panelSide, height: IslandWindDriveMetrics.panelSide)
        .shadow(
            color: .black.opacity(IslandWindDriveMetrics.heroShadowOpacity),
            radius: IslandWindDriveMetrics.heroShadowRadius,
            y: IslandWindDriveMetrics.heroShadowYOffset
        )
        .accessibilityHidden(true)
    }

    private var basePlate: some View {
        RoundedRectangle(cornerRadius: IslandWindDriveMetrics.heroCornerRadius, style: .continuous)
            .fill(
                Color.black
                    .opacity(IslandWindDriveMetrics.basePlateOpacity)
                    .shadow(.inner(color: .white, radius: 20, x: 0, y: 0))
            )
    }

    private var fanBladeLayer: RotatingFanBladeView {
        RotatingFanBladeView(animationState: animationState)
    }

    private var logoHub: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: IslandWindDriveMetrics.hubDiameter, height: IslandWindDriveMetrics.hubDiameter)

            WindDriveMarkView(
                preset: logoPreset,
                customImage: customImage,
                size: IslandWindDriveMetrics.logoSize,
                presetForegroundStyle: AnyShapeStyle(.white.opacity(0.96))
            )
        }
    }
}

private struct RotatingFanBladeView: View, Equatable {
    let animationState: IslandFanAnimationState

    var body: some View {
        Group {
            if let fanBladeImage = CodexIslandFanAssets.fanBlade {
                RotatingImageView(
                    image: fanBladeImage,
                    size: fanBladeImage.size,
                    tintColor: nil,
                    animationState: animationState,
                    supportsMotionBlur: true
                )
            } else {
                fallbackBlade
            }
        }
    }

    private var fallbackBlade: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 136, height: 136)

            RotatingImageView(
                image: CodexIslandFanAssets.largeFanSymbol,
                size: CGSize(width: 72, height: 72),
                tintColor: .white,
                animationState: animationState,
                supportsMotionBlur: true
            )
        }
    }
}

private struct RotatingImageView: NSViewRepresentable, Equatable {
    let image: NSImage?
    let size: CGSize
    let tintColor: NSColor?
    let animationState: IslandFanAnimationState
    var supportsMotionBlur = false

    static func == (lhs: RotatingImageView, rhs: RotatingImageView) -> Bool {
        lhs.size == rhs.size
            && lhs.tintColor == rhs.tintColor
            && lhs.animationState == rhs.animationState
            && lhs.supportsMotionBlur == rhs.supportsMotionBlur
            && lhs.image.map(ObjectIdentifier.init) == rhs.image.map(ObjectIdentifier.init)
    }

    func makeNSView(context: Context) -> RotatingImageContainerView {
        let view = RotatingImageContainerView()
        view.configure(
            image: image,
            size: size,
            tintColor: tintColor,
            animationState: animationState,
            supportsMotionBlur: supportsMotionBlur
        )
        return view
    }

    func updateNSView(_ nsView: RotatingImageContainerView, context: Context) {
        nsView.configure(
            image: image,
            size: size,
            tintColor: tintColor,
            animationState: animationState,
            supportsMotionBlur: supportsMotionBlur
        )
    }
}

private final class RotatingImageContainerView: NSView {
    private let rotationLayer = CALayer()
    private let trailingGhostLayer = CALayer()
    private let leadingGhostLayer = CALayer()
    private let imageLayer = CALayer()
    private var lastAnimationState: IslandFanAnimationState?
    private var currentSize: CGSize = .zero
    private var currentTintColor: NSColor?
    private var currentImageIdentifier: ObjectIdentifier?
    private var motionBlurEnabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        rotationLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        rotationLayer.contentsGravity = .center
        trailingGhostLayer.contentsGravity = .resizeAspect
        leadingGhostLayer.contentsGravity = .resizeAspect
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(rotationLayer)
        rotationLayer.addSublayer(trailingGhostLayer)
        rotationLayer.addSublayer(leadingGhostLayer)
        rotationLayer.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: currentSize.width, height: currentSize.height)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotationLayer.bounds = bounds
        rotationLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        trailingGhostLayer.frame = rotationLayer.bounds
        leadingGhostLayer.frame = rotationLayer.bounds
        imageLayer.frame = rotationLayer.bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        rotationLayer.contentsScale = scale
        trailingGhostLayer.contentsScale = scale
        leadingGhostLayer.contentsScale = scale
        imageLayer.contentsScale = scale
        CATransaction.commit()
    }

    func configure(
        image: NSImage?,
        size: CGSize,
        tintColor: NSColor?,
        animationState: IslandFanAnimationState,
        supportsMotionBlur: Bool
    ) {
        if currentSize != size {
            currentSize = size
            invalidateIntrinsicContentSize()
        }

        motionBlurEnabled = supportsMotionBlur
        let nextIdentifier = image.map(ObjectIdentifier.init)
        if currentImageIdentifier != nextIdentifier || currentTintColor != tintColor {
            let renderedImage = Self.makeCGImage(from: image, tintColor: tintColor)
            trailingGhostLayer.contents = renderedImage
            leadingGhostLayer.contents = renderedImage
            imageLayer.contents = renderedImage
            currentImageIdentifier = nextIdentifier
            currentTintColor = tintColor
        }

        apply(animationState: animationState)
    }

    private func apply(animationState: IslandFanAnimationState) {
        guard lastAnimationState != animationState else {
            return
        }

        // `rotationDegrees` is the shared clockwise-on-screen semantic.
        // Core Animation's z-rotation renders with the opposite sign here,
        // so the layer renderer converts that semantic locally.
        let currentRadians = -(animationState.rotationDegrees() * .pi / 180)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotationLayer.removeAnimation(forKey: Self.rotationAnimationKey)
        rotationLayer.transform = CATransform3DMakeRotation(CGFloat(currentRadians), 0, 0, 1)
        applyMotionBlur(animationState: animationState)

        if animationState.isSpinning {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = currentRadians
            animation.byValue = -(Double.pi * 2)
            animation.duration = max(animationState.rotationPeriod, 0.01)
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            rotationLayer.add(animation, forKey: Self.rotationAnimationKey)
        }
        CATransaction.commit()

        lastAnimationState = animationState
    }

    private static let rotationAnimationKey = "fantastic-island.rotation"

    private func applyMotionBlur(animationState: IslandFanAnimationState) {
        guard motionBlurEnabled else {
            trailingGhostLayer.opacity = 0
            leadingGhostLayer.opacity = 0
            trailingGhostLayer.transform = CATransform3DIdentity
            leadingGhostLayer.transform = CATransform3DIdentity
            return
        }

        let ghostOpacity = animationState.motionBlurOpacity
        let spreadRadians = animationState.motionBlurSpreadDegrees * (.pi / 180)
        trailingGhostLayer.opacity = ghostOpacity
        leadingGhostLayer.opacity = ghostOpacity * 0.72
        trailingGhostLayer.transform = CATransform3DMakeRotation(spreadRadians, 0, 0, 1)
        leadingGhostLayer.transform = CATransform3DMakeRotation(-spreadRadians * 0.58, 0, 0, 1)
    }

    private static func makeCGImage(from image: NSImage?, tintColor: NSColor?) -> CGImage? {
        guard let image else {
            return nil
        }

        if let tintColor {
            let tintedImage = NSImage(size: image.size)
            tintedImage.lockFocus()
            tintColor.set()
            let rect = CGRect(origin: .zero, size: image.size)
            image.draw(in: rect)
            rect.fill(using: .sourceAtop)
            tintedImage.unlockFocus()
            return tintedImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

struct WindDriveMarkView: View {
    let preset: WindDriveLogoPreset
    let customImage: NSImage?
    let size: CGFloat
    var presetForegroundStyle: AnyShapeStyle = AnyShapeStyle(.black.opacity(0.92))

    var body: some View {
        Group {
            if let customImage {
                Image(nsImage: customImage)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.24))
            } else if let symbolName = preset.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(presetForegroundStyle)
            } else {
                Circle()
                    .fill(presetForegroundStyle)
                    .frame(width: size * 0.68, height: size * 0.68)
            }
        }
        .frame(width: size, height: size)
    }
}

enum CodexIslandFanAssets {
    static let fanBlade = loadImage(named: "fan@2x")
    static let compactFanSymbol =
        assetImage(named: "fanicon")
        ?? systemSymbol(named: "fanblades.fill", pointSize: compactIslandFanIconSize, weight: .semibold)
    static let largeFanSymbol = systemSymbol(named: "fanblades.fill", pointSize: 72, weight: .semibold)

    private static func loadImage(named name: String) -> NSImage? {
        let url =
            Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "source")

        guard let url,
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        return image
    }

    private static func assetImage(named name: String) -> NSImage? {
        NSImage(named: NSImage.Name(name))
    }

    private static func systemSymbol(named name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return image.withSymbolConfiguration(configuration)
    }
}
