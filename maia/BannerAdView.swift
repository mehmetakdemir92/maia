//
//  BannerAdView.swift
//  maia
//

import SwiftUI
import GoogleMobileAds
import UIKit

/// Bottom banner for free users (below tabs / quiz).
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    var placement: String = AppAnalyticsPlacement.todayBottomBanner

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.placement = placement
        return coordinator
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
        var placement: String = AppAnalyticsPlacement.todayBottomBanner

        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            AppAnalytics.shared.log(AppAnalyticsEventName.adBannerImpression, params: [
                "placement": placement
            ])
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("Banner ad failed (\(placement)): \(error.localizedDescription)")
            AppAnalytics.shared.log(AppAnalyticsEventName.adBannerFailed, params: [
                "placement": placement,
                "error": String(describing: (error as NSError).code)
            ])
        }
    }
}
