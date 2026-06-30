//
//  GlassSceneBackground.swift
//  maia
//
//  Referans “liquid glass” kartların arkasında görünen gökyüzü + sıcak ton bulanık sahne.
//

import SwiftUI

/// Tam ekran gradient — cam kartların arkasından renk kırılması için (Focus pill referansı).
struct GlassSceneBackground: View {
    var isAnimated: Bool = false

    var body: some View {
        if isAnimated {
            TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let p1 = CGPoint(
                    x: 0.18 + 0.24 * sin(t * 1.02),
                    y: 0.22 + 0.20 * cos(t * 0.94)
                )
                let p2 = CGPoint(
                    x: 0.78 + 0.26 * cos(t * 0.86),
                    y: 0.68 + 0.22 * sin(t * 0.92)
                )
                let p3 = CGPoint(
                    x: 0.48 + 0.25 * sin(t * 0.74 + 1.6),
                    y: 0.40 + 0.22 * cos(t * 0.80 + 0.9)
                )

                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        AppColors.glassSceneGradient

                        Circle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: size.width * 0.70, height: size.width * 0.70)
                            .position(x: size.width * p1.x, y: size.height * p1.y)
                            .blur(radius: 90)

                        Circle()
                            .fill(Color(red: 122 / 255, green: 204 / 255, blue: 255 / 255).opacity(0.34))
                            .frame(width: size.width * 0.78, height: size.width * 0.78)
                            .position(x: size.width * p2.x, y: size.height * p2.y)
                            .blur(radius: 96)

                        Circle()
                            .fill(Color(red: 140 / 255, green: 173 / 255, blue: 255 / 255).opacity(0.30))
                            .frame(width: size.width * 0.66, height: size.width * 0.66)
                            .position(x: size.width * p3.x, y: size.height * p3.y)
                            .blur(radius: 80)
                    }
                    .drawingGroup()
                }
            }
            .ignoresSafeArea()
        } else {
            AppColors.glassSceneGradient.ignoresSafeArea()
        }
    }
}
