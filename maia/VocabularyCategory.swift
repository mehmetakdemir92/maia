//
//  VocabularyCategory.swift
//  maia
//
//  Premium kelime odağı: General (varsayılan), IELTS/TOEFL, Seyahat, Kariyer.
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
