import SwiftUI

// Copyright 2026 Fantastic Island contributors
// Portions adapted from open-vibe-island contributors
//
// This file is part of Fantastic Island.
//
// Fantastic Island is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3.
//
// Fantastic Island is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Fantastic Island. If not, see <https://www.gnu.org/licenses/>.
//
// This file adapts work from open-vibe-island:
// https://github.com/Octane0411/open-vibe-island
// Original file: Sources/OpenIslandApp/NotchShape.swift
// Modified for Fantastic Island on 2026-04-13.
struct CodexNotchShape: InsettableShape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topCornerRadius, bottomCornerRadius), insetAmount) }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            insetAmount = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let topR = min(topCornerRadius, insetRect.width / 4, insetRect.height / 4)
        let bottomR = min(bottomCornerRadius, insetRect.width / 4, insetRect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + topR, y: insetRect.minY + topR),
            control: CGPoint(x: insetRect.minX + topR, y: insetRect.minY)
        )
        path.addLine(to: CGPoint(x: insetRect.minX + topR, y: insetRect.maxY - bottomR))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + topR + bottomR, y: insetRect.maxY),
            control: CGPoint(x: insetRect.minX + topR, y: insetRect.maxY)
        )
        path.addLine(to: CGPoint(x: insetRect.maxX - topR - bottomR, y: insetRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX - topR, y: insetRect.maxY - bottomR),
            control: CGPoint(x: insetRect.maxX - topR, y: insetRect.maxY)
        )
        path.addLine(to: CGPoint(x: insetRect.maxX - topR, y: insetRect.minY + topR))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX, y: insetRect.minY),
            control: CGPoint(x: insetRect.maxX - topR, y: insetRect.minY)
        )
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

extension CodexNotchShape {
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 20
    static let openedTopRadius: CGFloat = 22
    static let openedBottomRadius: CGFloat = 36
}
