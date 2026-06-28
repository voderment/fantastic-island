import SwiftUI

enum FanModuleMetrics {
    static let visualHeight: CGFloat = 286
    static let airflowHeight: CGFloat = 252
    static let fanClearance: CGFloat = 118
}

struct FanModuleLiveContentView: View {
    @ObservedObject var model: FanModuleModel

    var body: some View {
        FanModuleContentView(state: model.makeRenderState())
    }
}

struct FanModuleContentView: View {
    let state: FanModuleRenderState

    var body: some View {
        ZStack {
            FanAirflowFieldView(isSpinning: state.animationState.isSpinning)
                .frame(height: FanModuleMetrics.airflowHeight)
                .opacity(state.animationState.isSpinning ? 1 : 0.56)
                .allowsHitTesting(false)

            OpenedIslandFanHeroView(
                animationState: state.animationState,
                logoPreset: state.logoPreset,
                customImage: state.customImage,
                showsBasePlate: false
            )
        }
        .frame(maxWidth: .infinity, minHeight: FanModuleMetrics.visualHeight, alignment: .center)
    }
}

private struct FanAirflowFieldView: View {
    let isSpinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isSpinning && !reduceMotion {
                TimelineView(.animation) { timeline in
                    FanAirflowCanvasView(
                        time: timeline.date.timeIntervalSinceReferenceDate,
                        isSpinning: true
                    )
                }
            } else {
                FanAirflowCanvasView(time: 0, isSpinning: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct FanAirflowCanvasView: View {
    let time: TimeInterval
    let isSpinning: Bool

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            guard size.width > 0, size.height > 0 else {
                return
            }

            drawAmbientGlow(in: &context, size: size)
            drawBroadFlow(in: &context, size: size)
            drawMovingStreaks(in: &context, size: size)
            drawRotorWash(in: &context, size: size)
        }
    }

    private var intensity: Double {
        isSpinning ? 1 : 0.38
    }

    private func drawAmbientGlow(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let pulse = isSpinning ? 0.84 + sin(time * 1.5) * 0.10 : 0.62
        let glowRect = CGRect(
            x: size.width * 0.22,
            y: size.height * 0.25,
            width: size.width * 0.56,
            height: size.height * 0.44
        )

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white.opacity(0.13 * pulse * intensity), location: 0),
                        .init(color: Color(red: 0.72, green: 0.94, blue: 1).opacity(0.07 * pulse * intensity), location: 0.42),
                        .init(color: Color.clear, location: 1),
                    ]),
                    center: center,
                    startRadius: 8,
                    endRadius: max(size.width, size.height) * 0.34
                )
            )
        }
    }

    private func drawBroadFlow(in context: inout GraphicsContext, size: CGSize) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))

            for index in 0..<7 {
                let lane = Double(index) / 6
                let phase = time * (isSpinning ? 0.52 : 0.10) + Double(index) * 0.86
                let laneOffset = CGFloat(lane - 0.5) * size.height * 0.46
                let baseline = size.height * 0.50 + laneOffset
                let wave = sin(phase) * 0.5 + cos(phase * 0.73) * 0.5
                let amplitude = size.height * (0.018 + CGFloat(index % 3) * 0.006)
                let path = airflowPath(
                    size: size,
                    baseline: baseline,
                    amplitude: amplitude,
                    wave: CGFloat(wave)
                )

                layer.stroke(
                    path,
                    with: .linearGradient(
                        airflowGradient(opacity: (0.16 - Double(abs(index - 3)) * 0.016) * intensity),
                        startPoint: CGPoint(x: size.width * 0.02, y: baseline),
                        endPoint: CGPoint(x: size.width * 0.98, y: baseline)
                    ),
                    style: StrokeStyle(lineWidth: max(18, size.height * 0.09), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func drawMovingStreaks(in context: inout GraphicsContext, size: CGSize) {
        let speed = isSpinning ? 64 : 12

        for index in 0..<11 {
            let lane = Double(index) / 10
            let phase = time * (isSpinning ? 0.74 : 0.12) + Double(index) * 0.54
            let laneOffset = CGFloat(lane - 0.5) * size.height * 0.56
            let baseline = size.height * 0.50 + laneOffset
            let wave = CGFloat(sin(phase))
            let path = airflowPath(
                size: size,
                baseline: baseline,
                amplitude: size.height * 0.018,
                wave: wave
            )

            context.stroke(
                path,
                with: .linearGradient(
                    airflowGradient(opacity: (0.18 - Double(abs(index - 5)) * 0.014) * intensity),
                    startPoint: CGPoint(x: size.width * 0.04, y: baseline),
                    endPoint: CGPoint(x: size.width * 0.96, y: baseline)
                ),
                style: StrokeStyle(
                    lineWidth: index % 3 == 0 ? 1.8 : 1.2,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [28, 52],
                    dashPhase: -CGFloat(time * Double(speed) + Double(index) * 17)
                )
            )
        }
    }

    private func drawRotorWash(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.50)
        let radiusBase = min(size.width, size.height) * 0.25

        for index in 0..<4 {
            let phase = time * (isSpinning ? 42 : 6) + Double(index) * 58
            var path = Path()
            path.addArc(
                center: center,
                radius: radiusBase + CGFloat(index) * 9,
                startAngle: .degrees(phase),
                endAngle: .degrees(phase + 54),
                clockwise: false
            )

            context.stroke(
                path,
                with: .color(Color.white.opacity((0.035 - Double(index) * 0.005) * intensity)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
        }
    }

    private func airflowPath(size: CGSize, baseline: CGFloat, amplitude: CGFloat, wave: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.05, y: baseline - wave * amplitude))
        path.addCurve(
            to: CGPoint(x: size.width * 0.95, y: baseline + wave * amplitude * 0.36),
            control1: CGPoint(x: size.width * 0.28, y: baseline + amplitude * (1.6 + wave)),
            control2: CGPoint(x: size.width * 0.68, y: baseline - amplitude * (1.4 - wave))
        )
        return path
    }

    private func airflowGradient(opacity: Double) -> Gradient {
        Gradient(stops: [
            .init(color: Color.clear, location: 0),
            .init(color: Color(red: 0.67, green: 0.90, blue: 1).opacity(opacity * 0.55), location: 0.18),
            .init(color: Color.white.opacity(opacity), location: 0.50),
            .init(color: Color(red: 0.88, green: 0.94, blue: 1).opacity(opacity * 0.48), location: 0.80),
            .init(color: Color.clear, location: 1),
        ])
    }
}
