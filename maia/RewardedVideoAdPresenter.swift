//
//  RewardedVideoAdPresenter.swift
//  maia
//

import Combine
import GoogleMobileAds
import UIKit

/// Rewarded video (rewarded interstitial → rewarded fallback).
@MainActor
final class RewardedVideoAdPresenter: NSObject, GADFullScreenContentDelegate {
    static let shared = RewardedVideoAdPresenter()

    @Published private(set) var isLoading = false

    private var rewardedAd: GADRewardedAd?
    private var rewardedInterstitialAd: GADRewardedInterstitialAd?
    private var didEarnReward = false
    private var onFinish: ((Bool) -> Void)?
    private var analyticsPlacement: String?

    private override init() {
        super.init()
    }

    func preload() {
        guard rewardedAd == nil, rewardedInterstitialAd == nil, !isLoading else { return }
        isLoading = true
        GADRewardedInterstitialAd.load(
            withAdUnitID: AdMobConfig.rewardedInterstitialAdUnitID,
            request: GADRequest()
        ) { [weak self] ad, _ in
            Task { @MainActor in
                self?.isLoading = false
                if let ad {
                    self?.rewardedInterstitialAd = ad
                    ad.fullScreenContentDelegate = self
                }
            }
        }
    }

    func present(placement: String, onFinish: ((Bool) -> Void)? = nil) {
        guard !isLoading else { return }
        self.onFinish = onFinish
        self.analyticsPlacement = placement
        self.didEarnReward = false
        self.isLoading = true

        if let ready = rewardedInterstitialAd {
            isLoading = false
            presentRewardedInterstitial(ready)
            return
        }
        if let ready = rewardedAd {
            isLoading = false
            presentRewarded(ready)
            return
        }

        GADRewardedInterstitialAd.load(
            withAdUnitID: AdMobConfig.rewardedInterstitialAdUnitID,
            request: GADRequest()
        ) { [weak self] interstitialAd, interstitialError in
            Task { @MainActor in
                guard let self else { return }
                if let interstitialAd {
                    self.isLoading = false
                    self.rewardedInterstitialAd = interstitialAd
                    interstitialAd.fullScreenContentDelegate = self
                    self.presentRewardedInterstitial(interstitialAd)
                    return
                }

                GADRewardedAd.load(
                    withAdUnitID: AdMobConfig.rewardedAdUnitID,
                    request: GADRequest()
                ) { [weak self] rewardedAd, rewardedError in
                    Task { @MainActor in
                        self?.isLoading = false
                        if let rewardedAd {
                            self?.rewardedAd = rewardedAd
                            rewardedAd.fullScreenContentDelegate = self
                            self?.presentRewarded(rewardedAd)
                            return
                        }
                        print("Rewarded video unavailable:", rewardedError?.localizedDescription ?? interstitialError?.localizedDescription ?? "")
                        self?.finish(success: false)
                    }
                }
            }
        }
    }

    private func presentRewardedInterstitial(_ ad: GADRewardedInterstitialAd) {
        guard let rootVC = Self.topViewController() else {
            finish(success: false)
            return
        }
        AppAnalytics.shared.log(AppAnalyticsEventName.adRewardedVideoShown, params: [
            "placement": analyticsPlacement ?? "unknown"
        ])
        ad.present(fromRootViewController: rootVC) { [weak self] in
            self?.didEarnReward = true
        }
    }

    private func presentRewarded(_ ad: GADRewardedAd) {
        guard let rootVC = Self.topViewController() else {
            finish(success: false)
            return
        }
        AppAnalytics.shared.log(AppAnalyticsEventName.adRewardedVideoShown, params: [
            "placement": analyticsPlacement ?? "unknown"
        ])
        ad.present(fromRootViewController: rootVC) { [weak self] in
            self?.didEarnReward = true
        }
    }

    func adDidDismissFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        finish(success: didEarnReward)
        rewardedAd = nil
        rewardedInterstitialAd = nil
        preload()
    }

    func ad(_ ad: any GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        print("Rewarded video present failed:", error.localizedDescription)
        finish(success: false)
        rewardedAd = nil
        rewardedInterstitialAd = nil
    }

    private func finish(success: Bool) {
        onFinish?(success)
        onFinish = nil
        analyticsPlacement = nil
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
