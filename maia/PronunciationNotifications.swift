//
//  PronunciationNotifications.swift
//  maia
//

import Foundation

extension Notification.Name {
    /// userInfo: `lemma` (String), `audioURL` (String)
    static let pronunciationAudioURLResolved = Notification.Name("maia.pronunciationAudioURLResolved")
}
