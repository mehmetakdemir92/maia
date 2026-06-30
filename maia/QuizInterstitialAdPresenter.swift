//
//  QuizInterstitialAdPresenter.swift
//  maia
//

import GoogleMobileAds
import UIKit

/// Quiz tamamlanınca ücretsiz kullanıcıya tam ekran interstitial (yüklenmişse).
@MainActor
final class QuizInterstitialAdPresenter: NSObject, GADFullScreenContentDelegate {
    static let shared = QuizInterstitialAdPresenter()

    private var interstitial: GADInterstitialAd?
    private var isLoading = false

    private override init() {
        super.init()
    }

    func preload() {
        guard interstitial == nil, !isLoading else { return }
        isLoading = true
        GADInterstitialAd.load(
            withAdUnitID: AdMobConfig.interstitialAdUnitID,
            request: GADRequest()
        ) { [weak self] ad, error in
            Task { @MainActor in
                self?.isLoading = false
                if let ad {
                    self?.interstitial = ad
                    ad.fullScreenContentDelegate = self
                } else if let error {
                    print("Interstitial preload failed:", error.localizedDescription)
                }
            }
        }
    }

    func presentIfAvailable() {
        guard let ad = interstitial, let root = Self.topViewController() else {
            preload()
            return
        }
        ad.present(fromRootViewController: root)
        AppAnalytics.shared.log(AppAnalyticsEventName.adInterstitialShown, params: [
            "placement": AppAnalyticsPlacement.quizCompleteInterstitial
        ])
    }

    func adDidDismissFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        interstitial = nil
        preload()
    }

    func ad(_ ad: any GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        print("Interstitial present failed:", error.localizedDescription)
        interstitial = nil
        preload()
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        var top = scene.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
