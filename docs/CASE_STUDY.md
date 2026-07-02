# Case Study: Building and Shipping Maia

**Maia - Learn Vocab Daily** is a published iOS vocabulary app built end to end by one person: product, iOS client, backend, content pipeline, and App Store operations.

- **App Store:** [Maia - Learn Vocab Daily](https://apps.apple.com/app/id6763566092)
- **Stack:** SwiftUI, Firebase (Auth, Firestore, Storage, Functions), StoreKit 2, AdMob, Gemini, Cloud TTS
- **Role:** Solo developer (design, code, backend, content, ASO)
- **Architecture reference:** [ARCHITECTURE.md](../ARCHITECTURE.md)

This document is not a feature list. It covers the decisions that shaped the app, the bugs that taught me the most, and what I would do differently.

---

## 1. The product thesis

Most vocabulary apps optimize for volume: hundreds of flashcards, endless decks. The users I observed didn't fail because they lacked words; they failed because they quit.

Maia inverts that: **3 carefully chosen words per day**, matched to the user's CEFR level, locked for the day, reinforced by a quiz, a diary, and a streak. The constraint *is* the feature. Every technical decision below follows from it.

---

## 2. Key technical decisions

### 2.1 Bundled word packs instead of live AI generation

The obvious 2026 approach is to generate daily words with an LLM at runtime. I built that first, and then replaced it.

**Problems with live generation:** unpredictable quality (wrong CEFR level, examples that don't contain the headword), per-user API cost, and a hard dependency on network at the exact moment the user opens the app.

**What shipped instead:** a monthly `WordPacks/{yyyy-MM}.json` bundled with the app. Each month has 30 days × 12 curated candidate words with definitions, examples, and quiz questions pre-authored. A Node script (`scripts/generate-monthly-pack.js`) builds packs from a tagged word pool (`word|cefr|domain|pos|register|frequency`).

**Trade-off accepted:** content must be shipped ahead of time with an app update. In exchange: zero runtime AI cost for the core loop, fully offline daily words, and every word a human (me) approved.

### 2.2 Deterministic level mapping (12 candidates → 3 words)

Users sit at one of 11 levels mapped to CEFR bands (A1–C2). Each day the pack offers 12 candidates across bands; `CEFRLevelMapping` picks 3 with rules like *"B2+ users get 2×C1 + 1×B2, never B1 filler"*, with band substitution when a band is missing.

The selection is **deterministic per (day, level)**: two users at the same level see the same words, and reopening the app never reshuffles. Words are then locked in UserDefaults for the day. Determinism made the logic unit-testable and eliminated a whole class of "my words changed" bugs.

### 2.3 Day boundaries in Europe/Istanbul, not UTC

Daily words, quiz attempt limits, streaks, and ad frequency caps all reset "at midnight". But midnight *where*? Using UTC would reset the app at 3 AM for the primary market. Every date key in the app goes through one function that formats the date in `Europe/Istanbul`. Unit tests pin the edge: `2026-06-30 21:00 UTC` must be `2026-07-01` in app terms.

One boundary function, used everywhere, tested once, instead of scattered `Date()` formatting waiting to disagree.

### 2.4 Idempotent quiz completion (the ad-ordering bug)

Originally, quiz side effects (streak, diary entry, stats, spaced-repetition update) ran when the user tapped **Continue** on the results screen. Then I added an interstitial ad *before* Continue for free users. Users who backed out after the ad never tapped Continue, and silently lost their streak for the day.

The fix reordered the pipeline: side effects commit **immediately and idempotently** when the quiz completes (`commitCompletionSideEffectsIfNeeded`, guarded by a flag), and the ad becomes purely cosmetic to the data flow. Lesson: monetization hooks must never sit between a user action and its persistence.

### 2.5 Per-user local state (the profile photo bug)

**The bug:** a Google Sign-In user removes their profile photo. Setting Firebase's `photoURL = nil` doesn't stick: the provider photo re-populates on the next auth reload. The photo kept "coming back."

**The fix:** the app keeps a per-UID `profilePhotoHidden.{uid}` flag in UserDefaults and resolves the displayed photo through one function that respects it. Uploading a new photo clears the flag.

The general pattern this enforced: **all local state is namespaced by UID** (diary, progress, quiz events, photo preferences), and account switches clear the previous user's caches. Cross-account data leaks on a shared device are a category of bug I now design against by default.

### 2.6 Spaced repetition: honest status

Quiz results feed an SM-2 implementation (ease factor, interval, repetitions, next-due date), persisted locally and synced to Firestore. The results screen shows the next review date.

The full review flow (a screen listing due words) exists in code but is **not yet wired into navigation**: it collects data without delivering user value. I left it that way deliberately rather than shipping a half-tested screen, and I count it as the clearest lesson in this project: *a feature that only writes data is not a feature.* It's on the roadmap behind more impactful work.

---

## 3. Testing strategy

The test suite (~50 unit tests) is deliberately concentrated where bugs are expensive and UI tests are useless:

| Area | Why it's tested |
|------|-----------------|
| SM-2 scheduling & grade mapping | Pure math; a silent regression corrupts every user's review schedule |
| CEFR selection rules | Product promise ("level-appropriate words") encoded as assertions |
| WordPack 3-word selection | The actual user-facing daily selection, run against fixture JSON |
| Quiz pass/retry rules (2 of 3, max 3 attempts) | Business rules that UI code merely displays |
| Word pool line parser | Guards the content pipeline that generates monthly packs |
| Daily word validation + Istanbul day boundary | Data quality gate + the timezone edge case |

No snapshot tests, no UI automation: for a solo project, the return on investment lives in the domain logic.

---

## 4. App Store operations (what the funnel taught me)

Shipping was not the finish line. Post-launch analytics showed:

- Product page → download conversion around **27%** (healthy; the page does its job)
- Impressions: **~100 over the period** (the actual bottleneck: nobody sees the app)

Diagnosis: **a conversion-shaped effort spent on a visibility-shaped problem** would have been wasted. So the follow-up release focused on discoverability, not the page: filling the empty subtitle field (30 indexed characters, previously unused), rewriting keywords to remove terms already indexed via the app name, and adding a full Turkish localization, since the Turkish storefront indexes both English and Turkish metadata, effectively doubling keyword coverage for the primary market.

Other operational realities of a live app: monthly content releases (new WordPack per month), Apple developer agreement renewals blocking uploads at the worst time, and history-rewriting a public repo to remove accidentally committed binaries.

---

## 5. What I'd do differently

1. **Pick a sharper niche first.** "Daily vocabulary" competes with free giants. The same architecture pointed at exam preparation (IELTS, or Turkey's YDS/YÖKDİL) would serve users with an urgent, dated need and a willingness to pay.
2. **Wire features end to end or not at all.** The spaced-repetition review screen taught me that "the backend works" is worth nothing until a user can touch it.
3. **Instrument earlier.** I added analytics thinking *after* launch. The impressions-vs-conversion insight above was available from day one; I just wasn't looking.
4. **Ask for reviews from day one.** Ratings compound; starting the in-app review prompt at launch instead of retrofitting it later costs nothing and pays rank.

---

## 6. Summary

| | |
|---|---|
| Scope | iOS app + Firebase backend + AI services + content pipeline, solo |
| Core loop | 3 daily CEFR-matched words → quiz → diary → streak |
| Hardest bug | Provider photo re-population after removal (fixed with per-UID local override) |
| Best decision | Bundled deterministic WordPacks over live AI generation |
| Honest miss | Spaced-repetition review flow built but not surfaced |
| Live skills | StoreKit 2, AdMob mediation, ASO, App Review process, localization |
