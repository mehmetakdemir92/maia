//
//  FreeUserBannerInset.swift
//  maia
//

import SwiftUI

/// Ücretsiz kullanıcılar için alt banner (premium’da gizlenir).
struct FreeUserBannerInset: ViewModifier {
    let placement: String
    @EnvironmentObject private var userManager: UserManager

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !userManager.isPremium {
                    BannerAdView(adUnitID: AdMobConfig.bannerAdUnitID, placement: placement)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background {
                            Group {
                                Rectangle().fill(.ultraThinMaterial)
                            }
                            .glassMaterialIgnoresSystemColorScheme()
                        }
                        .onAppear {
                            FreeUserBannerInset.requestTrackingOnce()
                        }
                }
            }
    }

    private static var didRequestTracking = false

    static func requestTrackingOnce() {
        guard !didRequestTracking else { return }
        didRequestTracking = true
        TrackingPermission.requestIfNeededOnce()
    }
}

extension View {
    func freeUserBottomBanner(placement: String) -> some View {
        modifier(FreeUserBannerInset(placement: placement))
    }
}

/// Kelime kartları arasına yerleştirilen banner (Today vb.).
struct InlineBannerAdRow: View {
    let placement: String

    var body: some View {
        BannerAdView(adUnitID: AdMobConfig.bannerAdUnitID, placement: placement)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background {
                Group {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            }
            .onAppear {
                FreeUserBannerInset.requestTrackingOnce()
            }
    }
}
