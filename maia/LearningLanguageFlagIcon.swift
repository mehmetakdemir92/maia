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
                USFlagView()
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

// MARK: - United States (simplified Stars and Stripes)

private struct USFlagView: View {
    private let red = Color(red: 0.70, green: 0.13, blue: 0.20)
    private let blue = Color(red: 0.06, green: 0.20, blue: 0.45)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stripeHeight = h / 13

            ZStack {
                // 13 horizontal stripes.
                VStack(spacing: 0) {
                    ForEach(0..<13, id: \.self) { idx in
                        Rectangle()
                            .fill(idx.isMultiple(of: 2) ? red : .white)
                            .frame(height: stripeHeight)
                    }
                }

                // Blue canton.
                Rectangle()
                    .fill(blue)
                    .frame(width: w * 0.45, height: stripeHeight * 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: w, height: h)
        }
    }
}
