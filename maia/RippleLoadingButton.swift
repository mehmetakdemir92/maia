//
//  RippleLoadingButton.swift
//  maia
//

import SwiftUI

enum RippleWaveStyle {
  /// primaryButtonGradient gibi koyu arka planlar
  case onDark
  /// Light glass / muted chip backgrounds
  case onLight
}

/// Button with ripple animation in palette colors while loading.
struct RippleLoadingButton<Label: View>: View {
  let isLoading: Bool
  let cornerRadius: CGFloat
  var rippleStyle: RippleWaveStyle = .onDark
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button {
      guard !isLoading else { return }
      action()
    } label: {
      label()
        .overlay {
          RippleWaveOverlay(
            isAnimating: isLoading,
            cornerRadius: cornerRadius,
            style: rippleStyle
          )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .allowsHitTesting(!isLoading)
    .animation(.easeInOut(duration: 0.2), value: isLoading)
  }
}

// MARK: - Palette

private enum RippleBlue {
  /// Parlak elektrik mavisi
  static let electric = Color(red: 56 / 255, green: 189 / 255, blue: 255 / 255)
  static let vivid = Color(red: 96 / 255, green: 198 / 255, blue: 255 / 255)
  /// Ana aksiyon mavisi
  static let core = Color(red: 66 / 255, green: 146 / 255, blue: 255 / 255)
}

// MARK: - Ripple overlay

private struct RippleWaveOverlay: View {
  let isAnimating: Bool
  let cornerRadius: CGFloat
  let style: RippleWaveStyle

  private struct RippleSpec {
    let phaseOffset: Double
    let speed: Double
    let jitterX: CGFloat
    let jitterY: CGFloat
    let wobbleSeed: Double
    let colorSlot: Int
  }

  private let specs: [RippleSpec] = [
    RippleSpec(phaseOffset: 0.00, speed: 1.05, jitterX: -4, jitterY: 3, wobbleSeed: 0.7, colorSlot: 0),
    RippleSpec(phaseOffset: 0.31, speed: 0.88, jitterX: 5, jitterY: -2, wobbleSeed: 2.1, colorSlot: 1),
    RippleSpec(phaseOffset: 0.58, speed: 1.18, jitterX: -2, jitterY: -5, wobbleSeed: 4.3, colorSlot: 2),
    RippleSpec(phaseOffset: 0.79, speed: 0.95, jitterX: 3, jitterY: 4, wobbleSeed: 6.0, colorSlot: 0),
  ]

  private let baseCycle = 1.4

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 60, paused: !isAnimating)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate

      GeometryReader { geo in
        let size = geo.size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = hypot(size.width, size.height) * 0.78

        Canvas { context, canvasSize in
          for spec in specs {
            drawRipple(
              context: &context,
              time: time,
              spec: spec,
              center: center,
              maxRadius: maxRadius,
              canvasSize: canvasSize
            )
          }
        }
        .frame(width: size.width, height: size.height)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .blendMode(style == .onDark ? .plusLighter : .normal)
    .allowsHitTesting(false)
    .opacity(isAnimating ? 1 : 0)
    .animation(.easeOut(duration: 0.25), value: isAnimating)
  }

  private func drawRipple(
    context: inout GraphicsContext,
    time: TimeInterval,
    spec: RippleSpec,
    center: CGPoint,
    maxRadius: CGFloat,
    canvasSize: CGSize
  ) {
    let cycle = baseCycle / spec.speed
    let phase = (time / cycle + spec.phaseOffset).truncatingRemainder(dividingBy: 1)
    let eased = 1 - pow(1 - phase, 1.45 + spec.wobbleSeed * 0.08)
    let fade = max(0, 1 - phase)
    guard fade > 0.02 else { return }

    let radius = maxRadius * eased
    let driftX = spec.jitterX + CGFloat(Darwin.sin(time * 1.7 + spec.wobbleSeed) * 5)
    let driftY = spec.jitterY + CGFloat(Darwin.cos(time * 2.1 + spec.wobbleSeed * 1.3) * 4)
    let origin = CGPoint(x: center.x + driftX, y: center.y + driftY)

    let fillPath = wobblyPath(
      center: origin,
      baseRadius: radius,
      time: time,
      seed: spec.wobbleSeed,
      irregularity: 0.11
    )

    let fillOpacity = style == .onDark ? fade * 0.72 : fade * 0.5
    let fillColor = rippleColor(slot: spec.colorSlot, fade: fillOpacity, forFill: true)
    context.fill(fillPath, with: .color(fillColor))

    let ringPath = wobblyPath(
      center: origin,
      baseRadius: radius * 0.92,
      time: time + 0.15,
      seed: spec.wobbleSeed + 1.9,
      irregularity: 0.14
    )
    let ringOpacity = style == .onDark ? fade * 0.95 : fade * 0.72
    let ringColor = rippleColor(slot: (spec.colorSlot + 1) % 3, fade: ringOpacity, forFill: false)
    context.stroke(
      ringPath,
      with: .color(ringColor),
      style: StrokeStyle(
        lineWidth: max(0.9, 2.2 * fade),
        lineCap: .round,
        lineJoin: .round
      )
    )

    // Second thin ring with phase offset
    if fade > 0.25 {
      let innerPath = wobblyPath(
        center: origin,
        baseRadius: radius * 0.62,
        time: time - 0.22,
        seed: spec.wobbleSeed + 3.4,
        irregularity: 0.09
      )
      let innerOpacity = style == .onDark ? fade * 0.65 : fade * 0.45
      context.stroke(
        innerPath,
        with: .color(rippleColor(slot: spec.colorSlot, fade: innerOpacity, forFill: false)),
        style: StrokeStyle(lineWidth: max(0.5, 1.1 * fade), lineCap: .round)
      )
    }

    _ = canvasSize
  }

  /// Slightly wavy ring instead of a perfect circle.
  private func wobblyPath(
    center: CGPoint,
    baseRadius: CGFloat,
    time: TimeInterval,
    seed: Double,
    irregularity: CGFloat
  ) -> Path {
    var path = Path()
    let segments = 56
    guard baseRadius > 1 else { return path }

    for i in 0...segments {
      let t = Double(i) / Double(segments)
      let angle = t * 2 * .pi
      let wobble =
        Darwin.sin(angle * 3 + time * 2.6 + seed) * Double(irregularity)
        + Darwin.cos(angle * 5 - time * 1.9 + seed * 1.7) * Double(irregularity * 0.65)
        + Darwin.sin(angle * 7 + time * 3.3 + seed * 0.4) * Double(irregularity * 0.35)
      let r = baseRadius * (1 + CGFloat(wobble))
      let point = CGPoint(
        x: center.x + CGFloat(Darwin.cos(angle)) * r,
        y: center.y + CGFloat(Darwin.sin(angle)) * r
      )
      if i == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    path.closeSubpath()
    return path
  }

  private func rippleColor(slot: Int, fade: Double, forFill: Bool) -> Color {
    let blues = [RippleBlue.electric, RippleBlue.vivid, RippleBlue.core]
    let base = blues[slot % blues.count]
    let strength = min(1, fade)

    switch style {
    case .onDark:
      return base.opacity(strength * (forFill ? 0.85 : 1.0))
    case .onLight:
      return base.opacity(strength * (forFill ? 0.55 : 0.75))
    }
  }
}
