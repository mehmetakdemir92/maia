//
//  StreakCelebrationView.swift
//  maia
//
// The reward beat of the habit loop. The old version scaled a flame once and
// left; the streak number was already sitting at its final value, so the one
// thing the learner just earned was the one thing that never moved.
//
// Self-contained on purpose — no app state, no managers — so it can be flipped
// through in the Xcode canvas without running the app.
//

import SwiftUI

struct StreakCelebrationView: View {

    /// The streak the learner has *after* finishing today.
    let streak: Int

    /// Honour the system setting: rising embers and a flickering flame are
    /// exactly the kind of motion this preference exists to suppress.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flameScale: CGFloat = 0.6
    @State private var flameGlow: Double = 0.35
    @State private var embersLaunched = false
    @State private var displayedStreak: Int = 0
    @State private var cardScale: CGFloat = 0.88
    @State private var cardOpacity: Double = 0

    private let embers: [Ember] = Ember.scatter(count: 14)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                flame
                    .frame(height: 92)

                Text("Day completed!")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                // Counts the last step rather than showing the final number
                // outright, so the streak visibly ticks over to what was
                // just earned.
                Text(String(format: String(localized: "%lld day streak"), Int64(displayedStreak)))
                    .font(.headline)
                    .foregroundColor(.orange)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            .padding(32)
            .background(AppColors.Lavender)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
        }
        .onAppear(perform: start)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "Day completed. %lld day streak"), Int64(streak))))
    }

    // MARK: - Pieces

    private var flame: some View {
        ZStack {
            if !reduceMotion {
                ForEach(embers) { ember in
                    Circle()
                        .fill(AppColors.celebrationFlameGradient)
                        .frame(width: ember.size, height: ember.size)
                        .offset(
                            x: ember.drift,
                            y: embersLaunched ? -ember.rise : 12
                        )
                        .opacity(embersLaunched ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: ember.duration).delay(ember.delay),
                            value: embersLaunched
                        )
                }
            }

            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.celebrationFlameGradient)
                .scaleEffect(flameScale)
                .shadow(color: .orange.opacity(flameGlow), radius: 18)
        }
    }

    // MARK: - Choreography

    private func start() {
        displayedStreak = max(0, streak - 1)

        guard !reduceMotion else {
            cardScale = 1
            cardOpacity = 1
            flameScale = 1
            displayedStreak = streak
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
            cardScale = 1
            cardOpacity = 1
        }

        // Flame overshoots, then settles — the pop that reads as "earned".
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.06)) {
            flameScale = 1.18
        }
        withAnimation(.easeInOut(duration: 0.24).delay(0.42)) {
            flameScale = 1.0
            flameGlow = 0.65
        }

        embersLaunched = true

        // The number turns over just after the flame peaks, so the two beats
        // read as cause and effect rather than firing at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.snappy(duration: 0.3)) {
                displayedStreak = streak
            }
        }
    }
}

// MARK: - Embers

private struct Ember: Identifiable {
    let id = UUID()
    let drift: CGFloat
    let size: CGFloat
    let rise: CGFloat
    let delay: Double
    let duration: Double

    /// Fixed spread rather than a uniform ring: embers off a flame are uneven,
    /// and an even ring reads as a loading spinner.
    static func scatter(count: Int) -> [Ember] {
        (0..<count).map { _ in
            Ember(
                drift: .random(in: -34...34),
                size: .random(in: 3...7),
                rise: .random(in: 58...104),
                delay: .random(in: 0...0.28),
                duration: .random(in: 0.6...1.05)
            )
        }
    }
}

#Preview("Streak celebration") {
    ZStack {
        GlassSceneBackground()
        StreakCelebrationView(streak: 7)
    }
}

#Preview("First day") {
    ZStack {
        GlassSceneBackground()
        StreakCelebrationView(streak: 1)
    }
}
