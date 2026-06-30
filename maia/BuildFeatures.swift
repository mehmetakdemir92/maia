//
//  BuildFeatures.swift
//  maia
//
//  DEBUG dahili test bayrakları (Archive / TestFlight / App Store’da kapalı).
//

import Foundation

enum BuildFeatures {
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// Sadece Xcode DEBUG build'lerinde: abonelik olmadan premium test etmek için.
    /// Archive (TestFlight veya App Store) build'lerinde her zaman false.
    static var allowsInternalPremiumOverride: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
