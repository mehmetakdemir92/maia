//
//  TrackingPermission.swift
//  maia
//
// ATT for personalized ads (requested once).
//

import AppTrackingTransparency
import Foundation

enum TrackingPermission {
    private static let requestedKey = "didRequestAppTracking"

    static func requestIfNeededOnce() {
        guard !UserDefaults.standard.bool(forKey: requestedKey) else { return }
        UserDefaults.standard.set(true, forKey: requestedKey)

        guard #available(iOS 14, *) else { return }
        ATTrackingManager.requestTrackingAuthorization { _ in }
    }
}
