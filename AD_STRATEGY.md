# Maia — Ad strategy (AdMob)

Summary: **light, focused** ads for free users; Premium is fully ad-free. Goal: protect retention and premium conversion, avoid aggressive full-screen ad stacking.

---

## 1. Current model (matches code)

### FREE

| Placement | Format | Frequency |
|-----------|--------|-----------|
| **Today** | Inline banner (after 1st word card) | 1 banner per session |
| **Quiz** | None | — |
| **Quiz complete** | Interstitial | Max **1** per day (first completed quiz) |
| **Streak recovery** | Rewarded (opt-in) | When user taps "Watch ad" |

### PREMIUM

- All ads disabled
- Premium features: ad-free + AI diary correction + Generate More + stats

### Intentionally excluded

- App open ad
- Interstitial on tab switches
- Bottom banner during quiz
- Auto rewarded video after 2nd quiz
- Bottom banner on Diary / Profile / Streak

---

## 2. File map

| File | Role |
|------|------|
| `TodayTabView.swift` | `InlineBannerAdRow` — only after 1st card |
| `QuizView.swift` | `QuizInterstitialAdPresenter` on quiz complete (1st quiz/day) |
| `StreakView.swift` | `StreakRecoveryRewardedService` — opt-in rewarded |
| `BannerAdView.swift` | Banner UIViewRepresentable + analytics |
| `QuizInterstitialAdPresenter.swift` | Interstitial preload + presentation |
| `DailyQuizAdTracker.swift` | Daily quiz completion counter (interstitial cap) |
| `AdMobConfig.swift` | Test / production ad unit IDs |
| `AppAnalytics.swift` | Placement event names |

`RewardedVideoAdPresenter.swift` — 2nd-quiz auto-rewarded removed; file kept for future opt-in rewarded flows.

---

## 3. Measurement (AdMob + analytics)

Track by placement:

- `today_inline_banner_after_first` — banner impression / fail
- `quiz_complete_interstitial` — interstitial shown
- Streak recovery rewarded (Streak screen)

Compare: premium conversion rate, DAU, quiz completion rate.

---

## 4. Next steps (when users reach 100+)

1. Verify production ad units (`AdMobConfig` + Info.plist `GADApplicationIdentifier`)
2. Adaptive banner (`GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth`)
3. Mediation (Meta, etc.) — fill rate / eCPM
4. A/B: Today inline vs bottom banner (one only)

**Avoid for now:** app open ad, interstitial on every navigation, in-quiz banner, forced rewarded.

---

## 5. Policy

- Interstitial only at natural pause points (quiz finished, before Continue)
- No full-screen ads mid learning flow
- ATT: `TrackingPermission` on banner display (existing)

---

*Last updated: ad simplification — Today 1 inline, no quiz banner, 1 interstitial/day, streak opt-in rewarded.*
