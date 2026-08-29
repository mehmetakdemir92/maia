//
//  ProfileImageCache.swift
//  maia
//
//  Disk cache for the signed-in user's profile photo. Without this,
//  `AsyncImage` re-downloads the full photo from Firebase Storage every time
//  its view appears (Profile tab, Settings row, ...), which is what burned
//  through the project's daily Storage download quota.
//

import SwiftUI

enum ProfileImageCache {
    private static func fileURL(for url: URL) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let key = String(url.absoluteString.hashValue)
        return dir.appendingPathComponent("profile_photo_\(key).jpg")
    }

    static func loadData(for url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url))
    }

    static func save(_ data: Data, for url: URL) {
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    /// Called on sign-out / photo removal so a stale cached photo can't leak
    /// into another account's session.
    static func clear(for url: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: url))
    }
}

/// Drop-in replacement for `AsyncImage` that only hits the network once per
/// URL — every later appearance loads from `ProfileImageCache` instead.
struct CachedProfileImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            uiImage = nil
            return
        }
        if let cached = ProfileImageCache.loadData(for: url), let image = UIImage(data: cached) {
            uiImage = image
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        ProfileImageCache.save(data, for: url)
        uiImage = UIImage(data: data)
    }
}
