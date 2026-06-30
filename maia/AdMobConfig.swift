//
//  AdMobConfig.swift
//  maia
//
//  App Store öncesi:
//  1) Xcode → Target maia → Build Settings → `ADMOB_APPLICATION_IDENTIFIER` (Release): AdMob uygulama kimliği (~ ile biten).
//  2) Aşağıdaki `productionBannerUnitID`: AdMob’da oluşturduğunuz banner birim kimliği.
//  İkisi de Google test ID ile bırakılırsa mağaza build’inde de test reklamları çıkar (geliştirme için uygun).
//

import Foundation

enum AdMobConfig {
    /// Google’ın resmi test uygulama kimliği (geliştirme / inceleme).
    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    /// Test banner birim kimliği.
    static let testBannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    /// Test rewarded birim kimliği (yaklaşık 30sn video test akışı için).
    static let testRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    /// Test rewarded interstitial birim kimliği.
    static let testRewardedInterstitialUnitID = "ca-app-pub-3940256099942544/6978759866"
    /// Test tam ekran interstitial (quiz sonrası).
    static let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// Mağaza / Release — AdMob: Maia Bottom Banner
    private static let productionBannerUnitID = "ca-app-pub-7654068182347889/5664211630"
    /// Mağaza / Release — AdMob: Maia Quiz Rewarded
    private static let productionRewardedUnitID = "ca-app-pub-7654068182347889/6577460757"
    /// Mağaza / Release — AdMob: Maia Quiz Rewarded Interstitial
    private static let productionRewardedInterstitialUnitID = "ca-app-pub-7654068182347889/2556352473"
    /// Mağaza / Release — AdMob: Maia Quiz Interstitial
    private static let productionInterstitialUnitID = "ca-app-pub-7654068182347889/9341252675"

    static var bannerAdUnitID: String {
        #if DEBUG
        return testBannerUnitID
        #else
        return productionBannerUnitID
        #endif
    }

    static var rewardedAdUnitID: String {
        #if DEBUG
        return testRewardedUnitID
        #else
        return productionRewardedUnitID
        #endif
    }

    static var rewardedInterstitialAdUnitID: String {
        #if DEBUG
        return testRewardedInterstitialUnitID
        #else
        return productionRewardedInterstitialUnitID
        #endif
    }

    static var interstitialAdUnitID: String {
        #if DEBUG
        return testInterstitialUnitID
        #else
        return productionInterstitialUnitID
        #endif
    }
}
