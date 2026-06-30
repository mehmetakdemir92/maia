//
//  Colors.swift
//  maia
//
//  Created by Mehmet Akdemir on 21.01.2026.
//
import SwiftUI

enum AppColors {

    // MARK: - Core colors

    static let primaryButton = Color(
        red: 66/255,
        green: 136/255,
        blue: 232/255
    )

    // MARK: - Shared gradients
    

    static let primaryButtonGradient = LinearGradient(
        colors: [
            Color(red: 42/255, green: 75/255, blue: 140/255),
            Color(red: 23/255, green: 22/255, blue: 64/255),
            Color(red: 42/255, green: 75/255, blue: 140/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark indigo for profile stat numbers.
    static let statValueColor = Color(red: 23/255, green: 22/255, blue: 64/255)

    static let quizProgressGradient = LinearGradient(
        colors: [
            Color(red: 251/255, green: 191/255, blue: 36/255), // yellow-400
            Color(red: 132/255, green: 204/255, blue: 22/255)  // green-500
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    

    static let glassSceneGradient = LinearGradient(
        colors: [
            Color(red: 23/255, green: 22/255, blue: 64/255),
            Color(red: 55/255, green: 114/255, blue: 166/255),
            Color(red: 42/255, green: 75/255, blue: 140/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let profileUpsellOverlayGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.2),
            Color.white.opacity(0.04),
            Color.black.opacity(0.07)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let profileUpsellBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.72),
            Color.white.opacity(0.2),
            Color.black.opacity(0.1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let badgeUnlockedCircleGradient = LinearGradient(
        colors: [.orange.opacity(0.4), primaryButton.opacity(0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let badgeLockedCircleGradient = LinearGradient(
        colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.25)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let badgeUnlockedIconGradient = LinearGradient(
        colors: [.orange, primaryButton],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let badgeLockedIconGradient = LinearGradient(
        colors: [.gray, .gray.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let celebrationFlameGradient = LinearGradient(
        colors: [.orange, .red],
        startPoint: .bottom,
        endPoint: .top
    )

    static func animatedFlameGradient(opacity: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                .orange.opacity(opacity),
                .red.opacity(opacity * 0.7)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    static let glassBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.85),
            Color.white.opacity(0.28),
            Color.white.opacity(0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassStatBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.92),
            Color.white.opacity(0.38),
            Color.black.opacity(0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassTopSheenGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.55),
            Color.white.opacity(0.12),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Additional colors

    static let MahoganyRed = Color(
        red: 186/255,
        green: 24/255,
        blue: 27/255
    )

    static let Lavender = Color(
        red: 223/255,
        green: 231/255,
        blue: 253/255
    )

    static let success = Color(
        red: 34/255,
        green: 197/255,
        blue: 94/255
    )

    static let secondaryText = Color(
        red: 100/255,
        green: 116/255,
        blue: 139/255
    )

    // MARK: - Liquid glass card (dark text on light frost)

    /// Headword — slate-950 (max contrast on light glass and colored gradient)
    static let glassCardTitle = Color(red: 2/255, green: 6/255, blue: 23/255)
    /// Definition / example body — slate-900
    static let glassCardBody = Color(red: 15/255, green: 23/255, blue: 42/255)
    /// Labels / phonetic — slate-600
    static let glassCardMuted = Color(red: 51/255, green: 65/255, blue: 85/255)
}
