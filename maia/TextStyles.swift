//
//  TextStyles.swift
//  maia
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import SwiftUI

struct SubtleStrokeText: ViewModifier {
    var textColor: Color = .white
    var strokeColor: Color = .black.opacity(0.55)
    var radius: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .foregroundColor(textColor)
            // stroke hissi veren çok hafif gölge
            .shadow(color: strokeColor, radius: radius, x: 0, y: 0)
    }
}

extension View {
    func subtleStrokeText(
        textColor: Color = .white,
        strokeColor: Color = .black.opacity(0.55),
        radius: CGFloat = 1
    ) -> some View {
        modifier(SubtleStrokeText(textColor: textColor, strokeColor: strokeColor, radius: radius))
    }

    /// Referans “Focus” pill: güçlü blur, kenar daha opak / merkez saydam, üst sheen, ince çerçeve, yumuşak gölge.
    func wordCardGlassBackground(cornerRadius: CGFloat = 22) -> some View {
        modifier(WordCardGlassBackground(cornerRadius: cornerRadius, variant: .standard))
    }

    /// Profil istatistik kartları: daha az gölge, kenar daha okunur, içerik sıkı.
    func statCardGlassBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(WordCardGlassBackground(cornerRadius: cornerRadius, variant: .statCompact))
    }

    // MARK: - Cam kart tipografisi (yalnızca metin; arka plan / blur’a dokunulmaz)

    /// Ana kelime — açık cam üzerinde koyu metin (beyaz halo yok)
    func glassCardWordTitle() -> some View {
        foregroundColor(AppColors.glassCardTitle)
            .fontDesign(.serif)
            .tracking(-0.12)
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    /// DEFINITION / EXAMPLE — küçük başlık, üst harf, net ayrım
    func glassCardSectionLabel() -> some View {
        font(.caption.weight(.bold))
            .foregroundColor(AppColors.glassCardMuted)
            .textCase(.uppercase)
            .tracking(0.85)
    }

    func glassCardPhonetic() -> some View {
        font(.subheadline.weight(.medium))
            .foregroundColor(AppColors.glassCardMuted)
            .italic()
    }

    /// Tanım / örnek gövdesi — geniş satır aralığı + ince gölge (ince italik bile okunur)
    func glassCardReadableBody() -> some View {
        foregroundColor(AppColors.glassCardBody)
            .lineSpacing(9)
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
    }
}

/// iOS liquid glass — `thinMaterial` ile belirgin backdrop blur; radyal kenar buzu + üst yatay parlama.
private struct WordCardGlassBackground: ViewModifier {
    enum Variant {
        case standard
        case statCompact
    }

    var cornerRadius: CGFloat
    var variant: Variant = .standard

    private var edgeStrokeWidth: CGFloat {
        switch variant {
        case .standard: return 1
        case .statCompact: return 1.35
        }
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let borderGradient = variant == .statCompact
            ? AppColors.glassStatBorderGradient
            : AppColors.glassBorderGradient

        let clipped = content
            .background {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let edgeR = hypot(w, h) * 0.52

                    ZStack {
                        // Güçlü buzlanma (referanstaki backdrop blur hissi)
                        shape.fill(.thinMaterial)

                        // Kenar “çerçeve” — orta alan daha saydam kalır
                        shape.fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.4),
                                    .init(color: Color.white.opacity(0.1), location: 0.78),
                                    .init(color: Color.white.opacity(0.2), location: 0.94),
                                    .init(color: Color.white.opacity(0.26), location: 1)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: edgeR
                            )
                        )

                        // Üst yatay cam parlaması (sheen)
                        VStack(spacing: 0) {
                            AppColors.glassTopSheenGradient
                            .frame(height: min(h * 0.22, 40))
                            Spacer(minLength: 0)
                        }
                        .frame(width: w, height: h)
                        .clipShape(shape)

                        shape.strokeBorder(borderGradient, lineWidth: edgeStrokeWidth)
                    }
                }
            }
            .clipShape(shape)

        switch variant {
        case .standard:
            return clipped
                .shadow(color: Color.black.opacity(0.14), radius: 28, x: 0, y: 16)
                .shadow(color: Color.white.opacity(0.12), radius: 8, x: 0, y: -2)
        case .statCompact:
            return clipped
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
                .shadow(color: Color.white.opacity(0.07), radius: 4, x: 0, y: -1)
        }
    }
}
