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
    @State private var selectedProductID: String = SubscriptionConfig.premiumYearlyProductID

    init(placement: String = "general") {
        self.placement = placement
    }

    private func planType(for productID: String) -> String {
        if productID == SubscriptionConfig.premiumMonthlyProductID { return "monthly" }
        if productID == SubscriptionConfig.premiumYearlyProductID { return "yearly" }
        return "unknown"
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

                        Text("Enjoy an ad-free experience, word focus categories, and AI-powered extra example sentences.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.92))

                        VStack(alignment: .leading, spacing: 12) {
                            featureRow(String(localized: "No ads"), icon: "eye.slash.fill")
                            featureRow(String(localized: "Word focus categories"), icon: "book.closed.fill")
                            featureRow(String(localized: "Generate more example sentences"), icon: "wand.and.stars")
                        }
                        .padding(.vertical, 8)

                        if let loadError {
                            Text(loadError)
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }

                        if products.isEmpty && loadError == nil {
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
                                Text("Subscribe")
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
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        return Button {
            selectedProductID = product.id
            AppAnalytics.shared.log(AppAnalyticsEventName.paywallPlanSelected, params: [
                "placement": placement,
                "product_id": product.id,
                "plan_type": planType(for: product.id)
            ])
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? .green : .white.opacity(0.5))
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

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: SubscriptionConfig.premiumProductIDs)
            let sorted = loaded.sorted { a, b in
                if a.id == SubscriptionConfig.premiumYearlyProductID { return true }
                if b.id == SubscriptionConfig.premiumYearlyProductID { return false }
                return a.displayName < b.displayName
            }
            await MainActor.run {
                products = sorted
                if !sorted.contains(where: { $0.id == selectedProductID }),
                   let first = sorted.first {
                    selectedProductID = first.id
                }
                loadError = sorted.isEmpty ? String(localized: "Products unavailable. Check App Store Connect / StoreKit config.") : nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }

    private func purchaseSelected() async {
        guard let product = products.first(where: { $0.id == selectedProductID }) else { return }
        AppAnalytics.shared.log(AppAnalyticsEventName.paywallCtaTapped, params: [
            "placement": placement,
            "product_id": product.id,
            "plan_type": planType(for: product.id)
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
                "plan_type": planType(for: product.id),
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
