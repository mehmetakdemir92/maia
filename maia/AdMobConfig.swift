//
//  AdMobConfig.swift
//  maia
//
// Before App Store release:
//  1) Set ADMOB_APPLICATION_IDENTIFIER in Release build settings (tilde-suffixed app ID).
//  2) Set productionBannerUnitID below to your AdMob banner unit ID.
//  Leaving both as Google test IDs shows test ads in store builds (fine for development).
//

import Foundation

enum AdMobConfig {
    /// Google's official test app ID (development / review).
    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    static let testBannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    /// Test rewarded unit ID (~30s video test flow).
    static let testRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    static let testRewardedInterstitialUnitID = "ca-app-pub-3940256099942544/6978759866"
    /// Test full-screen interstitial (shown after quiz).
    static let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// Production — AdMob: Maia Bottom Banner
    private static let productionBannerUnitID = "ca-app-pub-7654068182347889/5664211630"
    /// Production — AdMob: Maia Quiz Rewarded
    private static let productionRewardedUnitID = "ca-app-pub-7654068182347889/6577460757"
    /// Production — AdMob: Maia Quiz Rewarded Interstitial
    private static let productionRewardedInterstitialUnitID = "ca-app-pub-7654068182347889/2556352473"
    /// Production — AdMob: Maia Quiz Interstitial
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
