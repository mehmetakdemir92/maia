# Maia — reklam stratejisi (AdMob)

Özet: Ücretsiz kullanıcıda **seyrek ve odaklı** reklam; Premium tamamen reklamsız. Amaç retention + premium dönüşümü korumak, agresif tam ekran yığınını önlemek.

---

## 1. Mevcut model (kod ile uyumlu)

### FREE

| Yer | Format | Sıklık |
|-----|--------|--------|
| **Today** | Inline banner (1. kelime kartından sonra) | Oturum başına 1 banner |
| **Quiz** | Yok | — |
| **Quiz bitişi** | Interstitial | Günde en fazla **1** (ilk tamamlanan quiz) |
| **Streak recovery** | Rewarded (opt-in) | Kullanıcı “Watch ad” derse |

### PREMIUM

- Tüm reklamlar kapalı
- Mevcut premium özellikler: reklamsız + AI diary correction + Generate More + stats

### Bilinçli olarak yok

- App open ad
- Tab geçişlerinde interstitial
- Quiz sırasında alt banner
- 2. quiz sonrası otomatik rewarded video
- Diary / Profile / Streak alt banner

---

## 2. Dosya haritası

| Dosya | Rol |
|-------|-----|
| `TodayTabView.swift` | `InlineBannerAdRow` — yalnızca 1. kart sonrası |
| `QuizView.swift` | Quiz bitişinde `QuizInterstitialAdPresenter` (1. quiz/gün) |
| `StreakView.swift` | `StreakRecoveryRewardedService` — opt-in rewarded |
| `BannerAdView.swift` | Banner UIViewRepresentable + analytics |
| `QuizInterstitialAdPresenter.swift` | Interstitial preload + gösterim |
| `DailyQuizAdTracker.swift` | Günlük quiz tamamlama sayacı (interstitial cap) |
| `AdMobConfig.swift` | Test / production ad unit ID’leri |
| `AppAnalytics.swift` | Placement event isimleri |

`RewardedVideoAdPresenter.swift` — 2. quiz auto-rewarded kaldırıldı; dosya ileride opt-in rewarded için tutulabilir.

---

## 3. Ölçüm (AdMob + analytics)

Placement bazlı izle:

- `today_inline_banner_after_first` — banner impression / fail
- `quiz_complete_interstitial` — interstitial shown
- Streak recovery rewarded (Streak ekranı)

Karşılaştır: premium dönüşüm oranı, günlük aktif kullanıcı, quiz tamamlama oranı.

---

## 4. Sonraki adımlar (kullanıcı 100+ olunca)

1. Production ad unit doğrulama (`AdMobConfig` + Info.plist `GADApplicationIdentifier`)
2. Adaptive banner (`GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth`)
3. Mediation (Meta vb.) — doluluk / eCPM
4. A/B: Today’de inline vs alt banner (yalnızca biri)

**Yapma (şimdilik):** App open ad, her geçişte interstitial, quiz içi banner, zorunlu rewarded.

---

## 5. Politika

- Interstitial yalnızca doğal duraklama anında (quiz bitti, Continue öncesi)
- Eğitim akışının ortasında tam ekran reklam yok
- ATT: banner gösteriminde `TrackingPermission` (mevcut)

---

*Son güncelleme: reklam sadeleştirme — Today 1 inline, quiz banner yok, günde 1 interstitial, streak opt-in rewarded.*
