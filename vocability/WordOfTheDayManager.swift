//
//  WordOfTheDayManager.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine

class WordOfTheDayManager: ObservableObject {
    @Published var currentWords: [Word] = []
    
    private let words: [Word] = [
        Word(id: .stable(from: "Eloquent"), word: "Eloquent", definition: "Fluent or persuasive in speaking or writing.", exampleSentence: "She gave an eloquent speech that moved the audience.", phonetic: "el-uh-kwuhnt"),
        Word(id: .stable(from: "Resilient"), word: "Resilient", definition: "Able to withstand or recover quickly from difficult conditions.", exampleSentence: "The resilient community rebuilt after the natural disaster.", phonetic: "ri-zil-yuhnt"),
        Word(id: .stable(from: "Ambiguous"), word: "Ambiguous", definition: "Having more than one possible meaning; unclear.", exampleSentence: "His ambiguous statement left everyone confused.", phonetic: "am-big-yoo-uhs"),
        Word(id: .stable(from: "Diligent"), word: "Diligent", definition: "Having or showing care and conscientiousness in one's work or duties.", exampleSentence: "The diligent student studied every night.", phonetic: "dil-i-juhnt"),
        Word(id: .stable(from: "Pragmatic"), word: "Pragmatic", definition: "Dealing with things sensibly and realistically.", exampleSentence: "We need a pragmatic approach to solve this problem.", phonetic: "prag-mat-ik"),
        Word(id: .stable(from: "Tenacious"), word: "Tenacious", definition: "Tending to keep a firm hold of something; persistent.", exampleSentence: "She was tenacious in pursuing her goals.", phonetic: "tuh-ney-shuhs"),
        Word(id: .stable(from: "Meticulous"), word: "Meticulous", definition: "Showing great attention to detail; very careful and precise.", exampleSentence: "The artist was meticulous about every brushstroke.", phonetic: "muh-tik-yuh-luhs"),
        Word(id: .stable(from: "Ubiquitous"), word: "Ubiquitous", definition: "Present, appearing, or found everywhere.", exampleSentence: "Smartphones have become ubiquitous in modern society.", phonetic: "yoo-bik-wi-tuhs"),
        Word(id: .stable(from: "Ephemeral"), word: "Ephemeral", definition: "Lasting for a very short time.", exampleSentence: "The beauty of cherry blossoms is ephemeral.", phonetic: "ih-fem-er-uhl"),
        Word(id: .stable(from: "Serendipity"), word: "Serendipity", definition: "The occurrence of pleasant or beneficial things by chance.", exampleSentence: "Finding that rare book was pure serendipity.", phonetic: "ser-uhn-dip-i-tee"),
        Word(id: .stable(from: "Perspicacious"), word: "Perspicacious", definition: "Having keen mental perception and understanding.", exampleSentence: "The perspicacious detective solved the case quickly.", phonetic: "pur-spi-key-shuhs"),
        Word(id: .stable(from: "Magnanimous"), word: "Magnanimous", definition: "Generous in forgiving; noble in mind.", exampleSentence: "She was magnanimous in victory.", phonetic: "mag-nan-uh-muhs"),
        Word(id: .stable(from: "Ineffable"), word: "Ineffable", definition: "Too great or extreme to be expressed in words.", exampleSentence: "The ineffable beauty of the sunset left us speechless.", phonetic: "in-ef-uh-buhl"),
        Word(id: .stable(from: "Voracious"), word: "Voracious", definition: "Wanting or devouring great quantities of food or knowledge.", exampleSentence: "He was a voracious reader.", phonetic: "vuh-rey-shuhs"),
        Word(id: .stable(from: "Pernicious"), word: "Pernicious", definition: "Having a harmful effect, especially in a gradual or subtle way.", exampleSentence: "The pernicious influence of gossip spread quickly.", phonetic: "per-nish-uhs"),
        Word(id: .stable(from: "Capricious"), word: "Capricious", definition: "Given to sudden and unaccountable changes of mood or behavior.", exampleSentence: "The capricious weather changed from sunny to stormy.", phonetic: "kuh-prish-uhs"),
        Word(id: .stable(from: "Benevolent"), word: "Benevolent", definition: "Well meaning and kindly.", exampleSentence: "The benevolent teacher helped students after school.", phonetic: "buh-nev-uh-luhnt"),
        Word(id: .stable(from: "Alacrity"), word: "Alacrity", definition: "Brisk and cheerful readiness.", exampleSentence: "She accepted the invitation with alacrity.", phonetic: "uh-lak-ri-tee"),
        Word(id: .stable(from: "Cacophony"), word: "Cacophony", definition: "A harsh, discordant mixture of sounds.", exampleSentence: "The cacophony of the city streets was overwhelming.", phonetic: "kuh-kof-uh-nee"),
        Word(id: .stable(from: "Gregarious"), word: "Gregarious", definition: "Fond of company; sociable.", exampleSentence: "She was gregarious and loved hosting parties.", phonetic: "gri-gair-ee-uhs"),
        Word(id: .stable(from: "Idiosyncratic"), word: "Idiosyncratic", definition: "Relating to idiosyncrasy; peculiar or individual.", exampleSentence: "His idiosyncratic style made him stand out.", phonetic: "id-ee-oh-sin-krat-ik"),
        Word(id: .stable(from: "Juxtapose"), word: "Juxtapose", definition: "Place or deal with close together for contrasting effect.", exampleSentence: "The artist juxtaposed light and dark in her painting.", phonetic: "juhk-stuh-pohz"),
        Word(id: .stable(from: "Kaleidoscope"), word: "Kaleidoscope", definition: "A constantly changing pattern or sequence of elements.", exampleSentence: "The festival was a kaleidoscope of colors and sounds.", phonetic: "kuh-lahy-duh-skohp"),
        Word(id: .stable(from: "Laconic"), word: "Laconic", definition: "Using very few words.", exampleSentence: "His laconic reply left much unsaid.", phonetic: "luh-kon-ik"),
        Word(id: .stable(from: "Melancholy"), word: "Melancholy", definition: "A feeling of pensive sadness, typically with no obvious cause.", exampleSentence: "A mood of melancholy settled over the group.", phonetic: "mel-uhn-kol-ee"),
        Word(id: .stable(from: "Nebulous"), word: "Nebulous", definition: "In the form of a cloud or haze; hazy.", exampleSentence: "The plan was still nebulous and needed more detail.", phonetic: "neb-yuh-luhs"),
        Word(id: .stable(from: "Ostentatious"), word: "Ostentatious", definition: "Designed to impress or attract notice.", exampleSentence: "The ostentatious display of wealth was off-putting.", phonetic: "os-ten-tey-shuhs"),
        Word(id: .stable(from: "Paradigm"), word: "Paradigm", definition: "A typical example or pattern of something.", exampleSentence: "This represents a paradigm shift in our thinking.", phonetic: "par-uh-dahym")
    ]
    
    init() {
        loadWordsOfTheDay()
    }
    
    private func loadWordsOfTheDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Use UserDefaults to store the last date and word indices
        let lastDateKey = "lastWordsOfTheDayDate"
        let lastWordIndicesKey = "lastWordsOfTheDayIndices"
        
        if let lastDate = UserDefaults.standard.object(forKey: lastDateKey) as? Date,
           let lastWordIndices = UserDefaults.standard.array(forKey: lastWordIndicesKey) as? [Int],
           calendar.isDate(lastDate, inSameDayAs: today),
           lastWordIndices.count == 3 {
            // Same day, use the same words
            currentWords = lastWordIndices.compactMap { index in
                index < words.count ? words[index] : nil
            }
        } else {
            // New day, select 3 new words
            let wordIndices = selectWordIndicesForDate(today)
            currentWords = wordIndices.compactMap { index in
                index < words.count ? words[index] : nil
            }
            
            // Save the date and indices
            UserDefaults.standard.set(today, forKey: lastDateKey)
            UserDefaults.standard.set(wordIndices, forKey: lastWordIndicesKey)
        }
    }
    
    private func selectWordIndicesForDate(_ date: Date) -> [Int] {
        // Use the date as a seed to consistently select the same words for the same day
        let calendar = Calendar.current
        let daysSinceEpoch = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: date).day ?? 0
        
        // Select 3 different words based on the date
        var indices: [Int] = []
        var usedIndices = Set<Int>()
        
        // Use a pseudo-random generator seeded by the date
        var seed = UInt64(daysSinceEpoch)
        
        for _ in 0..<3 {
            var index: Int
            var attempts = 0
            repeat {
                // Generate index using seeded random
                seed = seed &* 1103515245 &+ 12345
                index = Int(seed % UInt64(words.count))
                attempts += 1
            } while usedIndices.contains(index) && attempts < words.count
            
            indices.append(index)
            usedIndices.insert(index)
        }
        
        return indices
    }
}

