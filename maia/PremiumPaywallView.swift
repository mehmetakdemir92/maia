//
//  PremiumPaywallView.swift
//  maia
//

import SwiftUI
import StoreKit

struct PremiumPaywallView: View {
    let placement: String
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var products: [Product] = []
    @State private var loadError: String?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isLoadingProducts = false
    @State private var selectedProductID: String = SubscriptionConfig.defaultSelectedProductID

    init(placement: String = "general") {
        self.placement = placement
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassSceneBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Premium")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppColors.primaryButtonGradient)

                        Text(String(localized: "Launch pricing — limited time."))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.2), in: Capsule())

                        Text(String(localized: "Enjoy an ad-free experience, AI sentence correction, extra example sentences, and full profile stats."))
                            .font(.body)
                            .foregroundColor(.white.opacity(0.92))

                        VStack(alignment: .leading, spacing: 12) {
                            featureRow(String(localized: "No ads"), icon: "eye.slash.fill")
                            featureRow(String(localized: "AI sentence correction"), icon: "text.badge.checkmark")
                            featureRow(String(localized: "Generate more example sentences"), icon: "wand.and.stars")
                            featureRow(String(localized: "Full profile stats (quiz achievement & max streak)"), icon: "chart.bar.fill")
                        }
                        .padding(.vertical, 8)

                        if let loadError {
                            Text(loadError)
                                .font(.footnote)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                Task { await loadProducts() }
                            } label: {
                                Text(String(localized: "Try again"))
                                    .font(.footnote.weight(.semibold))
                            }
                            .disabled(isLoadingProducts)
                        }

                        if products.isEmpty && loadError == nil && isLoadingProducts {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }

                        ForEach(products, id: \.id) { product in
                            planRow(product)
                        }

                        Button {
                            Task { await purchaseSelected() }
                        } label: {
                            HStack {
                                if isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(subscribeButtonTitle)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.white)
                            .background(AppColors.primaryButtonGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isPurchasing || products.isEmpty)

                        Button {
                            Task { await restore() }
                        } label: {
                            HStack {
                                if isRestoring {
                                    ProgressView()
                                }
                                Text("Restore purchases")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white.opacity(0.95))
                        }
                        .disabled(isRestoring)

                        Link(String(localized: "Terms of use (EULA)"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))

                        Text("Subscription renews automatically until cancelled in App Store account settings.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            AppAnalytics.shared.log(AppAnalyticsEventName.paywallViewed, params: [
                "placement": placement
            ])
            await loadProducts()
        }
    }

    private func featureRow(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.95))
                .frame(width: 24)
            Text(text)
                .foregroundColor(.white.opacity(0.92))
        }
    }

    private func planRow(_ product: Product) -> some View {
        let selected = selectedProductID == product.id
        let isYearly = SubscriptionConfig.isYearly(product.id)
        let introText = introductoryOfferDescription(for: product)

        return Button {
            selectedProductID = product.id
            AppAnalytics.shared.log(AppAnalyticsEventName.paywallPlanSelected, params: [
                "placement": placement,
                "product_id": product.id,
                "plan_type": SubscriptionConfig.planType(for: product.id)
            ])
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(SubscriptionConfig.planDisplayName(for: product.id))
                                .font(.headline)
                                .foregroundColor(.white)
                            if isYearly {
                                Text(String(localized: "Best value"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.85), in: Capsule())
                            }
                        }
                        if let introText {
                            Text(introText)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.green.opacity(0.95))
                        }
                        Text(SubscriptionConfig.planDescription(for: product.id))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(SubscriptionPricing.priceWithBillingPeriod(for: product))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.trailing)
                        if isYearly, let equivalent = SubscriptionPricing.equivalentMonthlyPrice(for: product) {
                            Text(equivalent)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.72))
                        }
                        if isYearly,
                           let monthly = products.first(where: { !SubscriptionConfig.isYearly($0.id) }),
                           let savings = SubscriptionPricing.savingsPercent(monthly: monthly, yearly: product) {
                            Text(String(format: String(localized: "Save %lld%%"), savings))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.green.opacity(0.95))
                        }
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected ? .green : .white.opacity(0.5))
                            .padding(.top, 2)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.14 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.35 : 0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func introductoryOfferDescription(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }
        if offer.paymentMode == .freeTrial {
            let period = offer.period
            switch period.unit {
            case .day where period.value == 7:
                return String(localized: "7-day free trial")
            case .day:
                return String(localized: "\(period.value)-day free trial")
            case .week:
                return String(localized: "\(period.value)-week free trial")
            default:
                return String(localized: "Free trial included")
            }
        }
        return nil
    }

    private var subscribeButtonTitle: String {
        guard let product = products.first(where: { $0.id == selectedProductID }),
              product.subscription?.introductoryOffer?.paymentMode == .freeTrial else {
            return String(localized: "Subscribe")
        }
        return String(localized: "Start free trial")
    }

    private func loadProducts() async {
        await MainActor.run {
            isLoadingProducts = true
            loadError = nil
        }
        defer {
            Task { @MainActor in isLoadingProducts = false }
        }

        let productIDs = SubscriptionConfig.premiumProductIDs
        #if DEBUG
        print("🛒 StoreKit: loading \(productIDs.joined(separator: ", "))")
        #endif

        do {
            let loaded = try await Product.products(for: productIDs)
            let sorted = loaded.sorted { a, b in
                if SubscriptionConfig.isYearly(a.id) { return true }
                if SubscriptionConfig.isYearly(b.id) { return false }
                return SubscriptionConfig.planDisplayName(for: a.id)
                    < SubscriptionConfig.planDisplayName(for: b.id)
            }
            #if DEBUG
            print("🛒 StoreKit: received \(sorted.count) product(s) → \(sorted.map(\.id))")
            #endif
            await MainActor.run {
                products = sorted
                if !sorted.contains(where: { $0.id == selectedProductID }),
                   let first = sorted.first {
                    selectedProductID = first.id
                }
                loadError = sorted.isEmpty ? storeKitUnavailableMessage : nil
            }
        } catch {
            #if DEBUG
            print("🛒 StoreKit load error: \(error)")
            #endif
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }

    private var storeKitUnavailableMessage: String {
        #if DEBUG
        return String(localized: "Plans could not be loaded. In Xcode: Product → Scheme → Edit Scheme → Run → Options → set StoreKit Configuration to MaiaProducts.storekit, then run from Xcode (not an old simulator install).")
        #else
        return String(localized: "Plans could not be loaded. Check your connection or try again later.")
        #endif
    }

    private func purchaseSelected() async {
        guard let product = products.first(where: { $0.id == selectedProductID }) else { return }
        AppAnalytics.shared.log(AppAnalyticsEventName.paywallCtaTapped, params: [
            "placement": placement,
            "product_id": product.id,
            "plan_type": SubscriptionConfig.planType(for: product.id)
        ])
        await MainActor.run { isPurchasing = true }
        do {
            try await userManager.purchase(product)
            await MainActor.run {
                isPurchasing = false
                if userManager.isPremium {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                isPurchasing = false
                loadError = error.localizedDescription
            }
            AppAnalytics.shared.log(AppAnalyticsEventName.purchaseFailed, params: [
                "placement": placement,
                "product_id": product.id,
                "plan_type": SubscriptionConfig.planType(for: product.id),
                "error": String(describing: (error as NSError).code)
            ])
        }
    }

    private func restore() async {
        await MainActor.run { isRestoring = true }
        do {
            try await userManager.restorePurchases()
            await MainActor.run {
                isRestoring = false
                if userManager.isPremium {
                    dismiss()
                } else {
                    loadError = String(localized: "No active subscription found for this Apple ID.")
                }
            }
        } catch {
            await MainActor.run {
                isRestoring = false
                loadError = error.localizedDescription
            }
        }
    }
}

#Preview {
    PremiumPaywallView()
        .environmentObject(UserManager())
}
