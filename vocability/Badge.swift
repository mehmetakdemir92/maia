//
//  Badge.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine

struct Badge: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let iconName: String
    let requirement: String
    let isUnlocked: Bool
    let unlockedDate: Date?
    
    init(id: UUID = UUID(), name: String, description: String, iconName: String, requirement: String, isUnlocked: Bool = false, unlockedDate: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.requirement = requirement
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
    }
}

class BadgeManager: ObservableObject {
    @Published var badges: [Badge] = []
    
    init() {
        initializeBadges()
        loadBadgeProgress()
    }
    
    private func initializeBadges() {
        badges = [
            Badge(name: "First Steps", description: "Complete your first quiz", iconName: "star.fill", requirement: "Complete 1 quiz"),
            Badge(name: "Week Warrior", description: "Maintain a 7-day streak", iconName: "flame.fill", requirement: "7 day streak"),
            Badge(name: "Monthly Master", description: "15-day streak in a month", iconName: "calendar", requirement: "15 day streak in a month"),
            Badge(name: "Quiz Champion", description: "Complete 10 quizzes", iconName: "trophy.fill", requirement: "Complete 10 quizzes"),
            Badge(name: "Perfect Week", description: "7 perfect quiz scores", iconName: "checkmark.circle.fill", requirement: "7 perfect scores"),
            Badge(name: "Vocabulary Master", description: "Learn 100 words", iconName: "book.fill", requirement: "Learn 100 words")
        ]
    }
    
    func checkAndUnlockBadges(streakCount: Int, quizCount: Int, perfectScores: Int, wordsLearned: Int) {
        // Check streak badges
        if streakCount >= 7 && !badges[1].isUnlocked {
            unlockBadge(at: 1)
        }
        
        // Check quiz badges
        if quizCount >= 1 && !badges[0].isUnlocked {
            unlockBadge(at: 0)
        }
        if quizCount >= 10 && !badges[3].isUnlocked {
            unlockBadge(at: 3)
        }
        
        // Check perfect scores
        if perfectScores >= 7 && !badges[4].isUnlocked {
            unlockBadge(at: 4)
        }
        
        // Check words learned
        if wordsLearned >= 100 && !badges[5].isUnlocked {
            unlockBadge(at: 5)
        }
    }
    
    private func unlockBadge(at index: Int) {
        badges[index] = Badge(
            id: badges[index].id,
            name: badges[index].name,
            description: badges[index].description,
            iconName: badges[index].iconName,
            requirement: badges[index].requirement,
            isUnlocked: true,
            unlockedDate: Date()
        )
        saveBadgeProgress()
    }
    
    private func loadBadgeProgress() {
        // Load badge unlock status from UserDefaults
        // Implementation would load saved badge states
    }
    
    private func saveBadgeProgress() {
        // Save badge unlock status to UserDefaults
        // Implementation would save badge states
    }
}
