//
//  SubscriptionPricing.swift
//  maia
//
//  Fiyatlar App Store / StoreKit’ten gelir (kullanıcının bölgesi ve para birimi).
//  Sabit $ veya ₺ yazmayın — displayPrice ve price kullanın.
//

import Foundation
import StoreKit

enum SubscriptionPricing {
    /// Örn. "₺149,99 / ay" veya "$4.99 / mo" — App Store’un bölgesel formatı.
    static func priceWithBillingPeriod(for product: Product) -> String {
        let period = billingPeriodLabel(for: product)
        guard !period.isEmpty else { return product.displayPrice }
        return String(format: String(localized: "%@ / %@"), product.displayPrice, period)
    }

    /// Yıllık planda aylık eşdeğer: "≈ ₺83,33 / ay"
    static func equivalentMonthlyPrice(for yearlyProduct: Product) -> String? {
        guard SubscriptionConfig.isYearly(yearlyProduct.id),
              yearlyProduct.price > 0 else { return nil }
        let monthly = yearlyProduct.price / 12
        let formatted = monthly.formatted(yearlyProduct.priceFormatStyle)
        let period = String(localized: "mo")
        return String(format: String(localized: "≈ %@ / %@"), formatted, period)
    }

    /// Aylık × 12 ile yıllık karşılaştırıldığında tasarruf yüzdesi.
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
