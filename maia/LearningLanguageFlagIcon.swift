//
//  LearningLanguageFlagIcon.swift
//  maia
//
// Drawn flags (not emoji) so they render reliably in Simulator and on device.
//

import SwiftUI

struct LearningLanguageFlagIcon: View {
    let language: LearningLanguage
    var isSelected: Bool = false

    private var cornerRadius: CGFloat { 3 }

    var body: some View {
        Group {
            switch language {
            case .english:
                UKFlagView()
            case .german:
                GermanFlagView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppColors.glassBorderGradient, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                .opacity(isSelected ? 0 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.28 : 0.2), radius: isSelected ? 2 : 1, x: 0, y: 0.5)
    }
}

// MARK: - Germany (horizontal black / red / gold)

private struct GermanFlagView: View {
    var body: some View {
        GeometryReader { geo in
            let stripe = geo.size.height / 3
            VStack(spacing: 0) {
                Color.black.frame(height: stripe)
                Color(red: 0.87, green: 0.15, blue: 0.15).frame(height: stripe)
                Color(red: 1.0, green: 0.81, blue: 0.0).frame(height: stripe)
            }
        }
    }
}

// MARK: - United Kingdom (simplified Union Jack)

private struct UKFlagView: View {
    private let navy = Color(red: 0.0, green: 0.14, blue: 0.44)
    private let red = Color(red: 0.78, green: 0.06, blue: 0.18)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                navy

                // White saltire
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: h * 0.24, lineCap: .butt))

                // Red saltire (simplified centered)
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(red, style: StrokeStyle(lineWidth: h * 0.09, lineCap: .butt))

                // White cross
                Rectangle()
                    .fill(Color.white)
                    .frame(width: w * 0.30, height: h)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: w, height: h * 0.30)

                // Red cross
                Rectangle()
                    .fill(red)
                    .frame(width: w * 0.16, height: h)
                Rectangle()
                    .fill(red)
                    .frame(width: w, height: h * 0.16)
            }
            .frame(width: w, height: h)
        }
    }
}
