//
//  BannerAdView.swift
//  maia
//

import SwiftUI
import GoogleMobileAds
import UIKit

/// Alt bant banner; yalnızca ücretsiz kullanıcılar için `TodayTabView` içinde gösterilir.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = Self.topViewController()
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        if uiView.rootViewController == nil {
            uiView.rootViewController = Self.topViewController()
        }
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first { $0.isKeyWindow }?.rootViewController
    }

    final class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            AppAnalytics.shared.log(AppAnalyticsEventName.adBannerImpression, params: [
                "placement": AppAnalyticsPlacement.todayBottomBanner
            ])
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("Banner ad failed: \(error.localizedDescription)")
            AppAnalytics.shared.log(AppAnalyticsEventName.adBannerFailed, params: [
                "placement": AppAnalyticsPlacement.todayBottomBanner,
                "error": String(describing: (error as NSError).code)
            ])
        }
    }
}
