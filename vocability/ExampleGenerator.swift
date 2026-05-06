//
//  ExampleGenerator.swift
//  vocability
//
//  Created by Mehmet Akdemir on 25.01.2026.
//

import Foundation

class ExampleGenerator {
    
    // Şimdilik mock data, sonra AI API entegrasyonu yapılabilir
    // OpenAI, Anthropic Claude, veya başka bir AI servisi kullanılabilir
    
    func generateExample(for word: Word) async throws -> String {
        // Simüle edilmiş network delay
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 saniye
        
        // Mock alternatif örnek cümleler
        let alternatives: [String: [String]] = [
            "Eloquent": [
                "His eloquent presentation captivated the entire audience.",
                "The lawyer's eloquent defense swayed the jury.",
                "She expressed her thoughts in an eloquent manner."
            ],
            "Resilient": [
                "Despite the setbacks, he remained resilient and determined.",
                "The resilient athlete bounced back from injury stronger than before.",
                "Her resilient spirit helped her overcome every challenge."
            ],
            "Ambiguous": [
                "The contract's ambiguous wording led to confusion.",
                "His ambiguous response left everyone uncertain about his intentions.",
                "The instructions were too ambiguous to follow correctly."
            ],
            "Diligent": [
                "The diligent worker always completed tasks ahead of schedule.",
                "She was diligent in her studies, reviewing notes every evening.",
                "His diligent approach to research produced excellent results."
            ],
            "Pragmatic": [
                "We need a pragmatic solution that actually works in practice.",
                "Her pragmatic approach saved the company thousands of dollars.",
                "He took a pragmatic view, focusing on what was achievable."
            ],
            "Tenacious": [
                "The tenacious detective never gave up on the case.",
                "Her tenacious pursuit of justice inspired many.",
                "He was tenacious in defending his position."
            ],
            "Meticulous": [
                "The meticulous editor caught every single typo.",
                "She was meticulous about keeping detailed records.",
                "His meticulous planning ensured the event's success."
            ],
            "Ubiquitous": [
                "Coffee shops have become ubiquitous in modern cities.",
                "The ubiquitous presence of smartphones changed society.",
                "Social media is now ubiquitous in daily life."
            ],
            "Ephemeral": [
                "The ephemeral nature of fame is often overlooked.",
                "These ephemeral moments of joy are what make life special.",
                "The ephemeral beauty of autumn leaves is fleeting."
            ],
            "Serendipity": [
                "Finding that perfect apartment was pure serendipity.",
                "Their meeting was a moment of serendipity.",
                "Sometimes serendipity leads to the best discoveries."
            ],
            "Perspicacious": [
                "The perspicacious investor saw the opportunity others missed.",
                "Her perspicacious analysis revealed the underlying problem.",
                "He was perspicacious in identifying the key issues."
            ],
            "Magnanimous": [
                "The magnanimous winner congratulated all competitors.",
                "She was magnanimous in victory, sharing credit with her team.",
                "His magnanimous gesture resolved the conflict peacefully."
            ],
            "Ineffable": [
                "The ineffable beauty of the sunset left them speechless.",
                "There's an ineffable quality to great art.",
                "The feeling was ineffable, beyond words."
            ],
            "Voracious": [
                "He was a voracious reader, finishing books in days.",
                "The voracious appetite of the growing company required constant funding.",
                "She had a voracious curiosity about the world."
            ],
            "Pernicious": [
                "The pernicious effects of gossip spread quickly through the office.",
                "This pernicious habit was slowly destroying his health.",
                "The pernicious influence of misinformation is dangerous."
            ],
            "Capricious": [
                "The capricious weather made planning difficult.",
                "Her capricious mood swings were hard to predict.",
                "The capricious nature of the market worried investors."
            ],
            "Benevolent": [
                "The benevolent organization helped thousands of families.",
                "His benevolent nature made him beloved by all.",
                "She showed benevolent concern for everyone's wellbeing."
            ],
            "Alacrity": [
                "He accepted the challenge with alacrity.",
                "She responded to the request with alacrity and enthusiasm.",
                "The team tackled the project with remarkable alacrity."
            ],
            "Cacophony": [
                "The cacophony of city sounds overwhelmed the visitor.",
                "A cacophony of voices filled the crowded room.",
                "The cacophony of construction disrupted the neighborhood."
            ],
            "Gregarious": [
                "His gregarious personality made him popular at parties.",
                "She was gregarious and loved meeting new people.",
                "The gregarious nature of the event brought everyone together."
            ],
            "Idiosyncratic": [
                "His idiosyncratic style of painting was instantly recognizable.",
                "The author's idiosyncratic writing voice set her apart.",
                "Each artist has their own idiosyncratic approach."
            ],
            "Juxtapose": [
                "The exhibition juxtaposed ancient and modern art.",
                "The film juxtaposes scenes of wealth and poverty.",
                "She liked to juxtapose different textures in her designs."
            ],
            "Kaleidoscope": [
                "The festival was a kaleidoscope of colors and sounds.",
                "Her mind was a kaleidoscope of creative ideas.",
                "The city at night becomes a kaleidoscope of lights."
            ],
            "Laconic": [
                "His laconic reply left much unsaid.",
                "The laconic message conveyed everything needed.",
                "She was known for her laconic but insightful comments."
            ],
            "Melancholy": [
                "A mood of melancholy settled over the group.",
                "The melancholy melody brought tears to her eyes.",
                "There was a melancholy beauty in the abandoned garden."
            ],
            "Nebulous": [
                "The plan was still nebulous and needed more detail.",
                "His ideas were nebulous and hard to pin down.",
                "The concept remained nebulous despite lengthy discussions."
            ],
            "Ostentatious": [
                "The ostentatious display of wealth was off-putting.",
                "Her ostentatious jewelry drew unwanted attention.",
                "He avoided ostentatious behavior, preferring subtlety."
            ],
            "Paradigm": [
                "This represents a paradigm shift in our thinking.",
                "The new technology created a paradigm in the industry.",
                "We need to change our paradigm about education."
            ]
        ]
        
        // Kelime için alternatif örnekler varsa rastgele birini seç
        if let wordAlternatives = alternatives[word.word], !wordAlternatives.isEmpty {
            return wordAlternatives.randomElement() ?? word.exampleSentence
        }
        
        // Alternatif yoksa, mevcut örneği biraz değiştirerek yeni bir tane oluştur
        return generateVariation(of: word.exampleSentence, word: word.word)
    }
    
    private func generateVariation(of sentence: String, word: String) -> String {
        // Basit bir variation generator (gerçek AI entegrasyonu için placeholder)
        let variations = [
            sentence.replacingOccurrences(of: word, with: word),
            sentence.replacingOccurrences(of: word.lowercased(), with: word.lowercased()),
            sentence.replacingOccurrences(of: word.capitalized, with: word.capitalized)
        ]
        
        // Basit bir alternatif oluştur
        var newSentence = sentence
        if let firstWord = sentence.components(separatedBy: " ").first {
            let alternatives: [String: String] = [
                "She": "He",
                "He": "She",
                "The": "A",
                "A": "The",
                "His": "Her",
                "Her": "His"
            ]
            if let replacement = alternatives[firstWord] {
                newSentence = sentence.replacingOccurrences(of: firstWord, with: replacement)
            }
        }
        
        return newSentence.isEmpty ? sentence : newSentence
    }
}
