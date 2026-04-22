import Foundation
import CoreGraphics

struct IslandFanAnimationState: Equatable {
    let anchorDate: Date
    let anchorDegrees: Double
    let rotationPeriod: Double
    let isSpinning: Bool

    var isPaused: Bool { !isSpinning }
    var motionBlurAmount: CGFloat {
        guard isSpinning else {
            return 0
        }

        let blurStartPeriod = 1.28
        let blurPeakPeriod = 0.88
        let clampedPeriod = min(max(rotationPeriod, blurPeakPeriod), blurStartPeriod)
        let progress = (blurStartPeriod - clampedPeriod) / (blurStartPeriod - blurPeakPeriod)
        return CGFloat(progress)
    }

    var motionBlurSpreadDegrees: CGFloat {
        8 * motionBlurAmount
    }

    var motionBlurOpacity: Float {
        Float(0.16 * motionBlurAmount)
    }

    func rotationDegrees(at date: Date = .now) -> Double {
        FanRotationMath.degrees(
            anchorDate: anchorDate,
            anchorDegrees: anchorDegrees,
            rotationPeriod: rotationPeriod,
            isSpinning: isSpinning,
            at: date
        )
    }
}

enum FanRotationMath {
    static func degrees(
        anchorDate: Date,
        anchorDegrees: Double,
        rotationPeriod: Double,
        isSpinning: Bool,
        at date: Date
    ) -> Double {
        guard isSpinning else {
            return anchorDegrees
        }

        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return anchorDegrees + (elapsed * 360 / rotationPeriod)
    }

    static func shouldRetuneRotationPeriod(from previous: Double, to next: Double, threshold: Double) -> Bool {
        abs(previous - next) > threshold
    }
}
