//
//  ShimmerSweep.swift
//  maia
//
// A light sweeping across a surface, for marking a card as earned.
//
// Deliberately a *sweep*, not a glow: a persistent glow competes with the
// glass card's own sheen and reads as "selected", while a sweep that crosses
// once and leaves reads as something that just happened. It is also cheap —
// one gradient moving behind a mask, no per-frame work.
//

import SwiftUI

extension View {
    /// Runs a highlight across this view whenever `trigger` becomes true.
    ///
    /// - Parameters:
    ///   - trigger: pass the condition that means "this was just earned".
    ///   - repeating: keep sweeping every few seconds. Off by default —
    ///     a loop on a card the learner is trying to read is a distraction.
    func shimmerSweep(when trigger: Bool, repeating: Bool = false) -> some View {
        modifier(ShimmerSweep(isActive: trigger, repeats: repeating))
    }
}

struct ShimmerSweep: ViewModifier {
    let isActive: Bool
    var repeats: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && !reduceMotion {
                    GeometryReader { geo in
                        let span = geo.size.width

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.42), location: 0.45),
                                .init(color: .white.opacity(0.62), location: 0.5),
                                .init(color: .white.opacity(0.42), location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        // A band roughly half the card's width, pushed from
                        // fully off one edge to fully off the other.
                        .frame(width: span * 0.55)
                        .offset(x: phase * (span * 1.6))
                        .rotationEffect(.degrees(18))
                        .blendMode(.plusLighter)
                    }
                    // Masked by the card itself so the sweep keeps to its
                    // shape and cannot spill past a rounded corner. The mask
                    // goes on the overlay, NOT on the whole modifier output:
                    // masking the composed view by a translucent glass card
                    // would let the card's own alpha eat into it and leave it
                    // dimmed even while no sweep is running.
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear { runIfNeeded() }
            .onChange(of: isActive) { _, _ in runIfNeeded() }
    }

    private func runIfNeeded() {
        guard isActive, !reduceMotion else { return }
        phase = -1
        withAnimation(
            repeats
                ? .easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.2)
                : .easeInOut(duration: 1.15)
        ) {
            phase = 1
        }
    }
}

#Preview("Sweep on a word card") {
    struct Demo: View {
        @State private var earned = false
        var body: some View {
            ZStack {
                GlassSceneBackground()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("abandon")
                            .font(.title.weight(.semibold))
                            .glassCardWordTitle()
                        Text("To leave a person, place, or plan behind for good.")
                            .glassCardReadableBody()
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wordCardGlassBackground(cornerRadius: 22)
                    .shimmerSweep(when: earned)

                    Button(earned ? "Reset" : "Mark as learned") {
                        earned.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
    return Demo()
}
