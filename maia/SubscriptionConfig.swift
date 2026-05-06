//
//  SubscriptionConfig.swift
//  maia
//
//  App Store Connect’te aynı ID’lerle abonelik oluşturulmalı (plan: aylık + yıllık tek grup).
//

import Foundation

enum SubscriptionConfig {
    static let premiumMonthlyProductID = "com.mehmetakdemir.maia.premium.monthly"
    static let premiumYearlyProductID = "com.mehmetakdemir.maia.premium.yearly"

    static let premiumProductIDs: [String] = [
        premiumMonthlyProductID,
        premiumYearlyProductID
    ]
}
