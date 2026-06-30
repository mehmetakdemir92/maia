//
//  SubscriptionPricing.swift
//  maia
//
// Prices come from App Store / StoreKit (user region and currency).
// Do not hard-code $ or ₺ — use displayPrice and price.
//

import Foundation
import StoreKit

enum SubscriptionPricing {
    /// e.g. "₺149,99 / ay" or "$4.99 / mo" — App Store regional formatting.
    static func priceWithBillingPeriod(for product: Product) -> String {
        let period = billingPeriodLabel(for: product)
        guard !period.isEmpty else { return product.displayPrice }
        return String(format: String(localized: "%@ / %@"), product.displayPrice, period)
    }

    /// Monthly equivalent on yearly plan.
    static func equivalentMonthlyPrice(for yearlyProduct: Product) -> String? {
        guard SubscriptionConfig.isYearly(yearlyProduct.id),
              yearlyProduct.price > 0 else { return nil }
        let monthly = yearlyProduct.price / 12
        let formatted = monthly.formatted(yearlyProduct.priceFormatStyle)
        let period = String(localized: "mo")
        return String(format: String(localized: "≈ %@ / %@"), formatted, period)
    }

    /// Savings percent vs monthly × 12.
    static func savingsPercent(monthly: Product, yearly: Product) -> Int? {
        guard monthly.price > 0, yearly.price > 0 else { return nil }
        let annualIfMonthly = monthly.price * 12
        guard annualIfMonthly > yearly.price else { return nil }
        let ratio = (annualIfMonthly - yearly.price) / annualIfMonthly
        return Int((ratio as NSDecimalNumber).doubleValue * 100)
    }

    private static func billingPeriodLabel(for product: Product) -> String {
        guard let unit = product.subscription?.subscriptionPeriod.unit else { return "" }
        switch unit {
        case .month:
            return String(localized: "mo")
        case .year:
            return String(localized: "yr")
        case .week:
            return String(localized: "wk")
        case .day:
            return String(localized: "day")
        @unknown default:
            return ""
        }
    }
}
