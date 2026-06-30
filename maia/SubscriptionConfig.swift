//
//  SubscriptionConfig.swift
//  maia
//
// Create one subscription group in App Store Connect with the same product IDs.
// Regional pricing: set primary tier in ASC; Apple converts other storefronts.
// App uses Product.displayPrice — do not hard-code currency strings.
// Local test: MaiaProducts.storekit (default storefront TUR). Change via Xcode → Debug → StoreKit.
//

import Foundation

enum SubscriptionConfig {
    /// Same group ID as App Store Connect / MaiaProducts.storekit.
    static let subscriptionGroupID = "maia_premium_group"

    static let premiumMonthlyProductID = "com.mehmetakdemir.maia.premium.monthly"
    static let premiumYearlyProductID = "com.mehmetakdemir.maia.premium.yearly"

    static let premiumProductIDs: [String] = [
        premiumMonthlyProductID,
        premiumYearlyProductID
    ]

    static var defaultSelectedProductID: String { premiumYearlyProductID }

    // Launch (Turkey): monthly ~₺119, yearly ~₺799 — keep in sync with MaiaProducts.storekit and ASC.

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

    /// Paywall titles from app locale (Localizable), not StoreKit product names.
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
