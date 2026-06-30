//
//  BuildFeatures.swift
//  maia
//
// Internal DEBUG flags (disabled in Archive / TestFlight / App Store).
//

import Foundation

enum BuildFeatures {
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// DEBUG builds only: test premium without a subscription.
    /// Always false in Archive (TestFlight / App Store) builds.
    static var allowsInternalPremiumOverride: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
