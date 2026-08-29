//
//  CurriculumState.swift
//  maia
//
// Where the learner stands in the spine, and whether the next slot is open yet.
//
// The pointer is progress-based, never calendar-based: a missed day costs the
// streak, never content. The day gate is what creates the reason to come back
// tomorrow — finite content plus a hard door.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

struct CurriculumState: Codable, Equatable {
    /// One state per learning language: the spines are independent.
    var languageCode: String
    /// 1-based slot the learner will study next.
    var currentSlotIndex: Int
    /// When the last slot was finished. Anchors the day gate.
    var lastCompletedAt: Date?
    /// Slots finished on this spine (stats, streak, placement guard).
    var completedCount: Int
    /// Whether onboarding placement has already run for this language.
    var hasBeenPlaced: Bool

    init(
        languageCode: String,
        currentSlotIndex: Int = 1,
        lastCompletedAt: Date? = nil,
        completedCount: Int = 0,
        hasBeenPlaced: Bool = false
    ) {
        self.languageCode = languageCode
        self.currentSlotIndex = max(1, currentSlotIndex)
        self.lastCompletedAt = lastCompletedAt
        self.completedCount = max(0, completedCount)
        self.hasBeenPlaced = hasBeenPlaced
    }
}

@MainActor
final class CurriculumStateManager: ObservableObject {

    @Published private(set) var state: CurriculumState

    /// Local hour at which a new study day starts. 4am, not midnight, so a
    /// session finished at 01:00 still counts as the previous day instead of
    /// burning two days' content in one sitting.
    static let dayResetHour = 4

    private let db = Firestore.firestore()
    private var lastObservedAuthUID: String?

    init(language: LearningLanguage? = nil) {
        self.state = CurriculumState(languageCode: (language ?? .current).code)
        load()
        lastObservedAuthUID = Auth.auth().currentUser?.uid
        setupAuthListener()
        if Auth.auth().currentUser?.uid != nil {
            syncFromFirestore()
        }
        NotificationCenter.default.addObserver(
            forName: .learningLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadForLanguageChange() }
        }
    }

    // MARK: - Day gate

    /// Calendar day in the learner's OWN timezone, shifted by `dayResetHour`.
    ///
    /// Deliberately not a rolling 24 hours from the last session: with a rolling
    /// window, finishing at 21:00 locks the learner out until 21:00 tomorrow, so
    /// each day must start later than the last. That drift is what kills the habit.
    static func studyDayISO(for date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let shifted = calendar.date(byAdding: .hour, value: -dayResetHour, to: date) ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The instant this study day began (local `dayResetHour`, not midnight).
    /// The single source of truth for "start of day" used everywhere the app
    /// used to run its own Calendar/TimeZone (diary grouping, streak, quiz
    /// checkmarks) — before this, those disagreed with the slot gate and with
    /// each other whenever the learner wasn't in Turkey.
    static func studyDayStart(for date: Date = Date()) -> Date {
        studyDayStart(fromISO: studyDayISO(for: date)) ?? date
    }

    /// True when both instants fall in the same study day.
    static func isSameStudyDay(_ a: Date, _ b: Date) -> Bool {
        studyDayISO(for: a) == studyDayISO(for: b)
    }

    /// Inverse of `studyDayISO`: the start-of-day instant for a previously
    /// formatted key (e.g. a Firestore document ID keyed by study day).
    static func studyDayStart(fromISO key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let shiftedMidnight = formatter.date(from: key) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(byAdding: .hour, value: dayResetHour, to: shiftedMidnight)
    }

    /// Cheap, device-clock heuristic: "did the gate probably change" — good
    /// enough to decide whether to re-check, never good enough to decide
    /// whether to actually unlock. See `isSlotUnlocked(asOf:)` for that.
    var isNextSlotUnlocked: Bool {
        guard let last = state.lastCompletedAt else { return true }
        return Self.studyDayISO(for: last) != Self.studyDayISO()
    }

    var hasCompletedTodaysSlot: Bool { !isNextSlotUnlocked }

    /// The authoritative unlock check. Always call with `trustedNow()`, never
    /// the device clock directly — otherwise setting the clock forward
    /// unlocks the next slot (and lets a learner blow through the whole
    /// spine) without waiting a single real day.
    func isSlotUnlocked(asOf now: Date) -> Bool {
        guard let last = state.lastCompletedAt else { return true }
        return Self.studyDayISO(for: last) != Self.studyDayISO(for: now)
    }

    /// A "now" a spoofed device clock can't fool: it round-trips through
    /// Firestore's serverTimestamp() instead of trusting `Date()`. Falls back
    /// to the device clock when signed out or offline — at that point there's
    /// no server to check against anyway, so it's no more spoofable than
    /// before this existed.
    static func trustedNow() async -> Date {
        guard let uid = Auth.auth().currentUser?.uid else { return Date() }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("appData").document("clockCheck")
        let localBefore = Date()
        do {
            try await ref.setData(["t": FieldValue.serverTimestamp()], merge: true)
            let snapshot = try await ref.getDocument(source: .server)
            guard let timestamp = snapshot.get("t") as? Timestamp else { return Date() }
            // Split the round-trip latency evenly; plenty precise for a
            // once-a-day gate.
            let roundTrip = Date().timeIntervalSince(localBefore)
            return timestamp.dateValue().addingTimeInterval(roundTrip / 2)
        } catch {
            return Date()
        }
    }

    var currentSlotIndex: Int { state.currentSlotIndex }
    var completedCount: Int { state.completedCount }

    // MARK: - Progression

    /// One-time placement from the onboarding CEFR step. Never moves a learner
    /// who has already started.
    func placeIfNeeded(userLevel: Int, slotCount: Int) {
        guard !state.hasBeenPlaced, state.completedCount == 0 else { return }
        state.currentSlotIndex = CurriculumPlacement.startSlot(forUserLevel: userLevel, slotCount: slotCount)
        state.hasBeenPlaced = true
        persist()
    }

    /// Called once the session for the current slot is finished. Stamps
    /// completion with `trustedNow()`, not the device clock — otherwise a
    /// clock rolled forward right before finishing plants a future timestamp
    /// that immediately reopens the gate once the clock is set back.
    func completeCurrentSlot(slotCount: Int) async {
        let now = await Self.trustedNow()
        state.completedCount += 1
        state.lastCompletedAt = now
        if slotCount <= 0 || state.currentSlotIndex < slotCount {
            state.currentSlotIndex += 1
        }
        persist()
    }

    /// End of the authored spine: no new words left, reviews only.
    func hasReachedEndOfSpine(slotCount: Int) -> Bool {
        slotCount > 0 && state.currentSlotIndex >= slotCount && state.completedCount >= slotCount
    }

    /// Developer/testing hook.
    func resetProgress() {
        state = CurriculumState(languageCode: state.languageCode)
        persist()
    }

    private func reloadForLanguageChange() {
        let language = LearningLanguage.current
        guard language.code != state.languageCode else { return }
        state = CurriculumState(languageCode: language.code)
        load()
        syncFromFirestore()
    }

    // MARK: - Persistence

    private var storageKey: String {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        return "curriculumState.\(uid).\(state.languageCode)"
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(CurriculumState.self, from: data),
              decoded.languageCode == state.languageCode else { return }
        state = decoded
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        saveToFirestoreIfSignedIn()
    }

    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let uid = user?.uid
            if uid == self.lastObservedAuthUID { return }
            self.lastObservedAuthUID = uid

            Task { @MainActor in
                // Account switch: never carry one learner's position into another's.
                self.state = CurriculumState(languageCode: LearningLanguage.current.code)
                self.load()
                if uid != nil { self.syncFromFirestore() }
            }
        }
    }

    private func saveToFirestoreIfSignedIn() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var payload: [String: Any] = [
            "currentSlotIndex": state.currentSlotIndex,
            "completedCount": state.completedCount,
            "hasBeenPlaced": state.hasBeenPlaced
        ]
        if let last = state.lastCompletedAt {
            payload["lastCompletedAt"] = Timestamp(date: last)
        }
        db.collection("users").document(uid)
            .collection("curriculum").document(state.languageCode)
            .setData(payload, merge: true) { error in
                if let error = error as NSError?, error.code != 7 {
                    print("❌ CurriculumState Firestore save error:", error.localizedDescription)
                }
            }
    }

    private func syncFromFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let language = state.languageCode
        db.collection("users").document(uid)
            .collection("curriculum").document(language)
            .getDocument { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error as NSError?, error.code != 7 {
                    print("❌ CurriculumState Firestore load error:", error.localizedDescription)
                    return
                }
                guard let data = snapshot?.data() else { return }
                Task { @MainActor in
                    guard self.state.languageCode == language else { return }
                    let remoteCount = data["completedCount"] as? Int ?? 0
                    // The device may hold a session the server has not seen yet;
                    // never rewind a learner who is further along locally.
                    guard remoteCount >= self.state.completedCount else { return }
                    self.state.completedCount = remoteCount
                    self.state.currentSlotIndex = max(1, data["currentSlotIndex"] as? Int ?? self.state.currentSlotIndex)
                    self.state.hasBeenPlaced = data["hasBeenPlaced"] as? Bool ?? self.state.hasBeenPlaced
                    if let timestamp = data["lastCompletedAt"] as? Timestamp {
                        self.state.lastCompletedAt = timestamp.dateValue()
                    }
                    if let encoded = try? JSONEncoder().encode(self.state) {
                        UserDefaults.standard.set(encoded, forKey: self.storageKey)
                    }
                }
            }
    }
}
