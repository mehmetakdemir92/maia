//
//  VocabularyCategory.swift
//  maia
//
// Premium word focus: General (default), IELTS/TOEFL, Travel, Career.
//

import Foundation

enum VocabularyCategory: String, CaseIterable, Codable {
    case general
    case ieltsToefl
    case travel
    case career
    
    var displayName: String {
        switch self {
        case .general: return String(localized: "General")
        case .ieltsToefl: return String(localized: "IELTS / TOEFL")
        case .travel: return String(localized: "Travel")
        case .career: return String(localized: "Career")
        }
    }
}
