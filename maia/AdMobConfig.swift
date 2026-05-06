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

    /// Mağaza / Release: AdMob konsolundan banner birim kimliği (yukarıdaki test ile değiştirin).
    private static let productionBannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    /// Mağaza / Release: AdMob konsolundan rewarded birim kimliği.
    private static let productionRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    /// Mağaza / Release: AdMob konsolundan rewarded interstitial birim kimliği.
    private static let productionRewardedInterstitialUnitID = "ca-app-pub-3940256099942544/6978759866"

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
}
