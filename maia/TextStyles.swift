//
//  TextStyles.swift
//  maia
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import SwiftUI

extension View {
    /// Prevents Material layers from shifting in system dark mode; glass stays on the light palette.
    func glassMaterialIgnoresSystemColorScheme() -> some View {
        environment(\.colorScheme, .light)
    }
}

struct SubtleStrokeText: ViewModifier {
    var textColor: Color = .white
    var strokeColor: Color = .black.opacity(0.55)
    var radius: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .foregroundColor(textColor)
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

    /// Focus pill reference: strong blur, opaque edge / clear center, top sheen, thin border.
    func wordCardGlassBackground(cornerRadius: CGFloat = 22) -> some View {
        modifier(WordCardGlassBackground(cornerRadius: cornerRadius, variant: .standard))
    }

    /// Profile stat cards: lighter shadow, clearer edge, tighter content.
    func statCardGlassBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(WordCardGlassBackground(cornerRadius: cornerRadius, variant: .statCompact))
    }

    // MARK: - Glass card typography (text only)

    /// Headword — dark text on light glass
    func glassCardWordTitle() -> some View {
        foregroundColor(AppColors.glassCardTitle)
            .fontDesign(.serif)
            .tracking(-0.12)
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    /// DEFINITION / EXAMPLE — small caps label
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

    /// Definition / example body — generous line spacing
    func glassCardReadableBody() -> some View {
        foregroundColor(AppColors.glassCardBody)
            .lineSpacing(9)
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
    }

    /// English gloss under a non-English example sentence
    func glassCardExampleGloss() -> some View {
        font(.subheadline)
            .foregroundColor(AppColors.glassCardMuted.opacity(0.72))
            .lineSpacing(2)
    }
}

/// Example sentence with optional faded translation underneath.
struct ExampleSentenceRow: View {
    let sentence: String
    let gloss: String?
    /// Headword to paint gold inside the sentence; nil keeps plain body styling.
    var highlightWord: String? = nil
    var learningLanguage: LearningLanguage = .english

    /// Backward-compatible alias used by older call sites.
    init(
        sentence: String,
        englishGloss: String?,
        highlightWord: String? = nil,
        learningLanguage: LearningLanguage = .english
    ) {
        self.sentence = sentence
        self.gloss = englishGloss
        self.highlightWord = highlightWord
        self.learningLanguage = learningLanguage
    }

    init(
        sentence: String,
        gloss: String?,
        highlightWord: String? = nil,
        learningLanguage: LearningLanguage = .english
    ) {
        self.sentence = sentence
        self.gloss = gloss
        self.highlightWord = highlightWord
        self.learningLanguage = learningLanguage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.body.weight(.bold))
                .foregroundColor(AppColors.glassCardBody)
                .frame(width: 14, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                highlightedSentence
                    .font(.body.weight(.medium))
                    .italic()
                    .lineSpacing(3)
                    .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(sentence)

                if let gloss {
                    Text(gloss)
                        .glassCardExampleGloss()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(gloss)
                }
            }
        }
    }

    @ViewBuilder
    private var highlightedSentence: some View {
        if let highlightWord, !highlightWord.isEmpty,
           let attributed = Self.highlightedText(
            sentence: sentence,
            headword: highlightWord,
            language: learningLanguage
           ) {
            attributed
        } else {
            Text(sentence)
                .foregroundColor(AppColors.glassCardBody)
        }
    }

    /// Builds `Text` with the headword (and common inflections) in a white→gold gradient.
    private static func highlightedText(
        sentence: String,
        headword: String,
        language: LearningLanguage
    ) -> Text? {
        let ranges = matchRanges(in: sentence, headword: headword, language: language)
        guard !ranges.isEmpty else { return nil }

        var result = Text("")
        var cursor = sentence.startIndex
        for range in ranges {
            if cursor < range.lowerBound {
                result = result + Text(String(sentence[cursor..<range.lowerBound]))
                    .foregroundColor(AppColors.glassCardBody)
            }
            let match = String(sentence[range])
            result = result + Text(match)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.exampleHeadwordGradient)
            cursor = range.upperBound
        }
        if cursor < sentence.endIndex {
            result = result + Text(String(sentence[cursor...]))
                .foregroundColor(AppColors.glassCardBody)
        }
        return result
    }

    /// Case-insensitive lemma matches, including language-specific inflection suffixes.
    private static func matchRanges(
        in sentence: String,
        headword: String,
        language: LearningLanguage
    ) -> [Range<String.Index>] {
        let lemma = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty else { return [] }

        let escaped = NSRegularExpression.escapedPattern(for: lemma)
        let suffixAlternation = language.headwordSuffixes
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let suffixGroup = suffixAlternation.isEmpty ? "" : "(?:\(suffixAlternation))?"
        let pattern = "\\b\(escaped)\(suffixGroup)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return regex.matches(in: sentence, options: [], range: nsRange).compactMap { match in
            Range(match.range, in: sentence)
        }
    }
}

/// iOS liquid glass — thinMaterial backdrop blur with radial frost and top sheen.
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
                        // Strong frost (backdrop blur)
                        shape.fill(.thinMaterial)

                        // Edge frame — center stays more transparent
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

                        // Top horizontal glass sheen
                        VStack(spacing: 0) {
                            AppColors.glassTopSheenGradient
                            .frame(height: min(h * 0.22, 40))
                            Spacer(minLength: 0)
                        }
                        .frame(width: w, height: h)
                        .clipShape(shape)

                        shape.strokeBorder(borderGradient, lineWidth: edgeStrokeWidth)
                    }
                    .glassMaterialIgnoresSystemColorScheme()
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
