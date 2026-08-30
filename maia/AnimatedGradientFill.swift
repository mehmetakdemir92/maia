//
//  AnimatedGradientFill.swift
//  maia
//
// The drifting-colour treatment from the sign-in screen, small enough to sit
// behind a button.
//
// Same idea as GlassSceneBackground(isAnimated:) — blurred blobs wandering
// over a base gradient — but scaled to a control rather than a full screen,
// and with the motion kept slow. On a screen it reads as atmosphere; on a
// button next to text it has to stay under the threshold where it competes
// with the label.
//

import SwiftUI

struct AnimatedGradientFill: View {

    /// Frames per second. The movement is slow enough that 15 is indis-
    /// tinguishable from 60 here, and a button redrawing 60 times a second
    /// for decoration is not worth the battery.
    private static let fps: Double = 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            AppColors.primaryButtonGradient
        } else {
            TimelineView(.periodic(from: .now, by: 1 / Self.fps)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    // Two blobs on different periods so they drift in and out
                    // of phase instead of settling into a visible loop.
                    let p1 = CGPoint(x: 0.30 + 0.30 * sin(t * 0.55),
                                     y: 0.35 + 0.25 * cos(t * 0.47))
                    let p2 = CGPoint(x: 0.72 + 0.28 * cos(t * 0.41),
                                     y: 0.62 + 0.26 * sin(t * 0.51))

                    ZStack {
                        AppColors.primaryButtonGradient

                        Circle()
                            .fill(Color(red: 122 / 255, green: 204 / 255, blue: 255 / 255).opacity(0.55))
                            .frame(width: w * 0.7, height: w * 0.7)
                            .position(x: w * p1.x, y: h * p1.y)
                            .blur(radius: 26)

                        Circle()
                            .fill(Color(red: 140 / 255, green: 173 / 255, blue: 255 / 255).opacity(0.45))
                            .frame(width: w * 0.6, height: w * 0.6)
                            .position(x: w * p2.x, y: h * p2.y)
                            .blur(radius: 24)
                    }
                    // Flattens the blurs into one layer before compositing —
                    // without it each blurred circle is its own offscreen pass
                    // every frame.
                    .drawingGroup()
                }
            }
        }
    }
}

#Preview("Animated button fill") {
    ZStack {
        GlassSceneBackground()
        HStack(spacing: 8) {
            Image(systemName: "book.fill")
            Text("Start Quiz").font(.headline)
        }
        .foregroundColor(.white)
        .frame(width: 190, height: 58)
        .background(AnimatedGradientFill())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
