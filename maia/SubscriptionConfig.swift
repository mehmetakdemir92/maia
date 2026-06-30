//
//  SubscriptionConfig.swift
//  maia
//
//  App Store Connect’te aynı Product ID’lerle tek abonelik grubu oluşturulmalı.
//  Bölgesel fiyat: ASC’de ana ülke fiyat kademesi seçilir; diğer ülkeler Apple tarafından dönüştürülür.
//  Uygulama `Product.displayPrice` kullanır — sabit para birimi yazmayın.
//  Yerel test: MaiaProducts.storekit (varsayılan vitrin TUR). Xcode → Debug → StoreKit → Storefront değiştirilebilir.
//

import Foundation

enum SubscriptionConfig {
    /// App Store Connect / MaiaProducts.storekit ile aynı grup kimliği.
    static let subscriptionGroupID = "maia_premium_group"

    static let premiumMonthlyProductID = "com.mehmetakdemir.maia.premium.monthly"
    static let premiumYearlyProductID = "com.mehmetakdemir.maia.premium.yearly"

    static let premiumProductIDs: [String] = [
        premiumMonthlyProductID,
        premiumYearlyProductID
    ]

    static var defaultSelectedProductID: String { premiumYearlyProductID }

    // Lansman (Türkiye): aylık ~₺119, yıllık ~₺799 — MaiaProducts.storekit ve ASC ile aynı tutun.

    static func isYearly(_ productID: String) -> Bool {
        productID == premiumYearlyProductID
    }

    static func planType(for productID: String) -> String {
        switch productID {
        case premiumMonthlyProductID: return "monthly"
        case premiumYearlyProductID: return "yearly"
        default: return "unknown"
        }
    }

    /// Paywall başlıkları — App Store / StoreKit adı değil; uygulama dili (`Localizable`).
    static func planDisplayName(for productID: String) -> String {
        if isYearly(productID) {
            return String(localized: "Premium Yearly")
        }
        return String(localized: "Premium Monthly")
    }

    static func planDescription(for productID: String) -> String {
        if isYearly(productID) {
            return String(localized: "Billed yearly. 7-day free trial for new subscribers.")
        }
        return String(localized: "Billed monthly. Cancel anytime in App Store settings.")
    }
}
