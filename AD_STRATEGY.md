# Maia — reklam stratejisi (AdMob)

Özet: Şu an **yalnızca Today sekmesinde**, **standart banner**, **ücretsiz kullanıcılar** için (`TodayTabView` + `BannerAdView`). Premium tamamen reklamsız — doğru freemium ayrımı.

---

## 1. Mevcut durum (güçlü yanlar)

- **Tek yerde banner**: Öğrenme akışı (Today) ile sınırlı; Diary / Profile / Streak’te reklam yok → odak ve App Store algısı için iyi.
- **Premium = reklamsız**: Dönüşüm argümanı net.
- **ATT**: Banner görünürken istek (`TrackingPermission`) — yayın öncesi akış düşünülmüş.

---

## 2. Hızlı kazanımlar (düşük risk)

| Öneri | Neden |
|--------|--------|
| **Gerçek ad unit ID’leri** | `AdMobConfig` hâlâ test ID; production’da gerçek banner unit + Info.plist `GADApplicationIdentifier` eşleşmeli. |
| **Adaptive banner** | `GADAdSizeBanner` yerine ekran genişliğine göre adaptive size — daha iyi doluluk ve bazen daha iyi eCPM; alt bantta hâlâ “banner” ailesi. |
| **Yeniden yükleme / root VC** | Sekme değişince veya `scenePhase` ile banner’ın `rootViewController` ve `load` davranışı; bazen eski VC’ye takılı kalır — delegate’te hata log’u var, analytics eklemek faydalı. |
| **Mediation (Meta / başka ağ)** | AdMob mediation ile doluluk ↑; özellikle TR / karma coğrafyada gelir ve gösterim sık sık artar. |

---

## 3. Geliri artıran ama UX’i dikkatle ayarlanan seçenekler

### A) App open ad (uygulama açılışı)

- **Ne zaman**: Cold start / background’dan dönüşte, tam ekran öncesi (Google’ın önerdiği sıklık sınırlarına uyarak).
- **Kim**: Sadece free; Premium kapalı.
- **Risk**: Aşırı sıklık kullanıcıyı yorar → günlük/oturum başı cap (ör. günde max 3–5, veya sadece her 2. açılış).

### B) Interstitial (geçiş)

- **Doğal anlar**: Quiz’den **çıkış** (`QuizView` dismiss), veya “bugünkü kelimeler bitti” sonrası **bir kez**.
- **Kaçınılacak**: Kelime kartı okurken, yazarken, quiz sorusunun ortasında.
- **Sıklık**: Oturum başı en fazla 1 (veya günde 2–3 üst sınır); eğitim uygulamasında “her ekran geçişinde” yapma.

### C) Rewarded (isteğe bağlı, ileride)

- “Bir AI örnek cümle daha” veya “ekstra quiz turu” gibi **net karşılık** verilirse kullanıcı tolere eder; zorunlu rewarded agresif sayılır.

---

## 4. Premium ile denge (para + dönüşüm)

- **Banner + 0 interstitial**: Premium değer önerisi “sessiz uygulama” olabilir ama gelir sınırlı kalır.
- **Banner + seyrek interstitial / app open**: Paywall metninde “Reklamsız deneyim” vurgusu güçlenir; fiyatlandırmayı buna göre konumlandır.
- **A/B**: Ücretsizde reklam yoğunluğu ile premium dönüşüm oranı — AdMob + App Store Connect / StoreKit verisiyle ölç.

---

## 5. Politika ve kalite

- **Google**: Geçiş reklamlarında yanlış yerleştirme (yanlışlıkla tıklama), aşırı sıklık policy ihlali sayılabilir.
- **Apple**: Aşırı tam ekran reklam App Review’da soru çıkarabilir; eğitim tonu ve sıklık sınırı önemli.
- **ATT**: Sadece banner’da değil, ileride başka formatta da tutarlı olun (metin App Store Privacy’dekiyle uyumlu).

---

## 6. Ölçüm (somut metrikler)

AdMob konsolunda şunları izleyin:

- **eCPM** (ülke / format), **doluluk (impression / request)**  
- **Kullanıcı başı günlük gösterim** (banner yenileme + ekranda kalma süresi)  
- **Premium dönüşüm** (reklam ekledikçe düşüyor mu — denge)

---

## 7. Öncelik sırası (öneri)

1. Production ad unit + adaptive banner + mediation hazırlığı  
2. **App open** veya **Quiz çıkışında tek interstitial** (ikisinden biriyle başla, ikisini aynı anda patlatma)  
3. Rewarded sadece net “ödül” ile  
4. Sürekli A/B: reklam sıklığı vs premium geliri (toplam)

---

*Bu dosya yalnızca strateji rehberidir; uygulama davranışını değiştirmek için kod ve AdMob konsol ayarları ayrıca yapılmalıdır.*
