//
//  TextStyles.swift
//  maia
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import NaturalLanguage
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

    /// Translations start hidden: working out the meaning before checking it
    /// is what makes the example stick. Reading a sentence with the answer
    /// already underneath it is passive.
    @State private var isGlossRevealed = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.body.weight(.bold))
                .foregroundColor(AppColors.glassCardBody)
                .frame(width: 14, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                sentenceWithGlossToggle
                    .font(.body.weight(.medium))
                    .italic()
                    .lineSpacing(3)
                    .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard gloss != nil else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isGlossRevealed.toggle()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sentence)
                    .accessibilityAddTraits(gloss == nil ? [] : .isButton)
                    .accessibilityHint(
                        gloss == nil ? Text("")
                                     : Text(isGlossRevealed ? "Hides the translation"
                                                            : "Shows the translation")
                    )

                if let gloss, isGlossRevealed {
                    Text(gloss)
                        .glassCardExampleGloss()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(gloss)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        // The call site keys its ForEach on the row's position, so this view is
        // reused when the word changes. Without this, a translation left open
        // would still be open on the next word's sentence.
        .onChange(of: sentence) { _, _ in
            isGlossRevealed = false
        }
    }

    /// The sentence with the translation toggle riding at the end of its last
    /// line. Built by concatenating `Text` rather than placing a `Button`
    /// beside it, so the marker flows with the wrapped text instead of being
    /// pushed onto its own line.
    private var sentenceWithGlossToggle: Text {
        guard gloss != nil else { return sentenceText }
        return sentenceText
            + Text(verbatim: "  ")   // separator, not copy — keep it out of the catalog
            + Text(Image(systemName: isGlossRevealed ? "character.bubble.fill" : "character.bubble"))
                .foregroundColor(AppColors.primaryButton)
    }

    private var sentenceText: Text {
        if let highlightWord, !highlightWord.isEmpty,
           let attributed = Self.highlightedText(
            sentence: sentence,
            headword: highlightWord,
            language: learningLanguage
           ) {
            return attributed
        }
        return Text(sentence).foregroundColor(AppColors.glassCardBody)
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

    /// Case-insensitive lemma matches. Tries the OS lemmatizer first (handles
    /// irregular English inflections like consonant doubling, "commit" ->
    /// "committed"). The lemmatizer has no German model at all — as of this SDK,
    /// `NLTagger.availableTagSchemes(for:.word, language: .german)` doesn't
    /// include `.lemma` (French/Portuguese/English do) — so German falls back to
    /// suffix-based matching, then to a hand-built verb-conjugation matcher, then
    /// to separable-prefix-verb handling for verbs like "feststellen" that split
    /// apart in a main clause ("Sie stellte fest, ...").
    private static func matchRanges(
        in sentence: String,
        headword: String,
        language: LearningLanguage
    ) -> [Range<String.Index>] {
        let lemma = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty else { return [] }

        let lemmatizerRanges = lemmatizerMatchRanges(in: sentence, headword: lemma, language: language)
        if !lemmatizerRanges.isEmpty { return lemmatizerRanges }

        let suffixRanges = suffixMatchRanges(in: sentence, headword: lemma, language: language)
        if !suffixRanges.isEmpty { return suffixRanges }

        guard language == .german else { return [] }

        let verbRanges = germanVerbMatchRanges(in: sentence, infinitive: lemma)
        if !verbRanges.isEmpty { return verbRanges }

        return separableVerbMatchRanges(in: sentence, headword: lemma)
    }

    /// German separable-prefix verbs ("feststellen" -> "fest" + "stellen") split
    /// apart in a main clause ("Sie stellte fest, ..."), so neither the joined
    /// headword nor the conjugated stem alone matches the sentence as one span.
    /// Ordered longest-first so a headword picks its longest valid prefix.
    private static let germanSeparablePrefixes: [String] = [
        "hinein", "heraus", "hinüber", "herüber", "zusammen", "auseinander",
        "entgegen", "gegenüber", "zurecht", "vorbei", "weiter", "zurück",
        "ab", "an", "auf", "aus", "bei", "dar", "ein", "fest", "fort",
        "her", "hin", "los", "mit", "nach", "statt", "vor", "weg", "zu", "um"
    ].sorted { $0.count > $1.count }

    /// Fallback for German separable-prefix verbs: splits the headword into its
    /// prefix and the remaining infinitive (itself a real verb, e.g. "stellen").
    /// Tries the past participle first, since it fuses into one token with "ge"
    /// *between* the prefix and stem ("einkaufen" -> "eingekauft", not a split
    /// "ein" + "gekauft"). Otherwise requires BOTH a conjugated form of the
    /// remainder AND the bare prefix word to appear somewhere in the sentence
    /// before highlighting either — so an unrelated word that happens to share
    /// the prefix's spelling (many are common prepositions: "an", "auf", "zu"...)
    /// doesn't get highlighted alone.
    private static func separableVerbMatchRanges(
        in sentence: String,
        headword: String
    ) -> [Range<String.Index>] {
        let lowerHeadword = headword.lowercased()
        guard let prefix = germanSeparablePrefixes.first(where: {
            lowerHeadword.hasPrefix($0) && lowerHeadword.count > $0.count + 1
        }) else { return [] }

        let remainder = String(headword.dropFirst(prefix.count))

        if let fusedRanges = fusedParticipleMatchRanges(in: sentence, prefix: prefix, remainderInfinitive: remainder),
           !fusedRanges.isEmpty {
            return fusedRanges
        }

        let stemRanges = germanVerbMatchRanges(in: sentence, infinitive: remainder)
        guard !stemRanges.isEmpty else { return [] }

        let prefixRanges = wholeWordMatchRanges(in: sentence, word: prefix)
        guard !prefixRanges.isEmpty else { return [] }

        return (stemRanges + prefixRanges).sorted { $0.lowerBound < $1.lowerBound }
    }

    /// A separable verb's past participle fuses as one token with "ge" inserted
    /// between the prefix and stem, not appended after the split prefix.
    private static func fusedParticipleMatchRanges(
        in sentence: String,
        prefix: String,
        remainderInfinitive: String
    ) -> [Range<String.Index>]? {
        let lower = remainderInfinitive.lowercased()
        let stem: String
        if lower.count > 2, lower.hasSuffix("en") {
            stem = String(remainderInfinitive.dropLast(2))
        } else if lower.count > 1, lower.hasSuffix("n") {
            stem = String(remainderInfinitive.dropLast(1))
        } else {
            return nil
        }
        guard !stem.isEmpty else { return nil }

        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let escapedStem = NSRegularExpression.escapedPattern(for: stem)
        let pattern = "\\b\(escapedPrefix)ge\(escapedStem)(?:t|et)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return regex.matches(in: sentence, options: [], range: nsRange).compactMap { match in
            Range(match.range, in: sentence)
        }
    }

    /// Matches conjugated/participle forms of a German verb infinitive by
    /// deriving its stem and applying real conjugation endings, instead of
    /// (wrongly) appending suffixes after the full infinitive — German present
    /// and simple-past endings replace the infinitive's trailing "-en", they
    /// don't follow it ("stellen" -> "stellte", not "stellen" + "te"). Also
    /// tries an umlauted stem ("fahren" -> "fährt") to catch the common class of
    /// strong verbs that only vowel-shift; verbs with a full irregular ablaut
    /// ("nehmen" -> "nahm"/"genommen") aren't covered — that needs a real
    /// dictionary, not a suffix rule.
    private static func germanVerbMatchRanges(
        in sentence: String,
        infinitive: String
    ) -> [Range<String.Index>] {
        let lower = infinitive.lowercased()
        let stem: String
        if lower.count > 2, lower.hasSuffix("en") {
            stem = String(infinitive.dropLast(2))
        } else if lower.count > 1, lower.hasSuffix("n") {
            stem = String(infinitive.dropLast(1))
        } else {
            return []
        }
        guard !stem.isEmpty else { return [] }

        var stems = [stem]
        if let umlauted = umlautedVariant(of: stem) { stems.append(umlauted) }

        let escapedStems = stems.map { NSRegularExpression.escapedPattern(for: $0) }
        let stemAlternation = escapedStems.joined(separator: "|")
        let conjugated = "(?:\(stemAlternation))(?:e|st|t|en|te|test|ten|tet)?"
        let participles = escapedStems.map { "ge\($0)(?:t|et)" }.joined(separator: "|")
        let pattern = "\\b(?:\(conjugated)|\(participles))\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return regex.matches(in: sentence, options: [], range: nsRange).compactMap { match in
            Range(match.range, in: sentence)
        }
    }

    /// Umlauts the last a/o/u (or "au") in a verb stem, e.g. "fahr" -> "fähr"
    /// (fährt), "lauf" -> "läuf" (läuft). Covers one common strong-verb pattern;
    /// not a general German ablaut solver.
    private static func umlautedVariant(of stem: String) -> String? {
        if let range = stem.range(of: "au", options: [.backwards, .caseInsensitive]) {
            var result = stem
            result.replaceSubrange(range, with: "äu")
            return result
        }
        for (from, to) in [("a", "ä"), ("o", "ö"), ("u", "ü")] {
            if let range = stem.range(of: from, options: [.backwards, .caseInsensitive]) {
                var result = stem
                result.replaceSubrange(range, with: to)
                return result
            }
        }
        return nil
    }

    /// Case-insensitive whole-word match, no inflection handling.
    private static func wholeWordMatchRanges(in sentence: String, word: String) -> [Range<String.Index>] {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "\\b\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return regex.matches(in: sentence, options: [], range: nsRange).compactMap { match in
            Range(match.range, in: sentence)
        }
    }

    /// Tags each word in the sentence with its dictionary lemma and compares that
    /// to the headword, so inflected forms are matched by meaning rather than by
    /// guessing which suffix was appended. No-ops for languages without a lemma
    /// model on this SDK (currently German) rather than enumerating for nothing.
    private static func lemmatizerMatchRanges(
        in sentence: String,
        headword: String,
        language: LearningLanguage
    ) -> [Range<String.Index>] {
        let nlLanguage: NLLanguage = language == .german ? .german : .english
        guard NLTagger.availableTagSchemes(for: .word, language: nlLanguage).contains(.lemma) else {
            return []
        }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = sentence
        tagger.setLanguage(nlLanguage, range: sentence.startIndex..<sentence.endIndex)

        let target = headword.lowercased()
        var ranges: [Range<String.Index>] = []
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if let wordLemma = tag?.rawValue.lowercased(), wordLemma == target {
                ranges.append(range)
            }
            return true
        }
        return ranges
    }

    /// Fallback for words the lemmatizer doesn't recognize: exact lemma plus a
    /// fixed list of common suffixes appended directly (no spelling changes).
    private static func suffixMatchRanges(
        in sentence: String,
        headword: String,
        language: LearningLanguage
    ) -> [Range<String.Index>] {
        let escaped = NSRegularExpression.escapedPattern(for: headword)
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
