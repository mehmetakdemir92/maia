//
//  LegalDocumentView.swift
//  maia
//

import SwiftUI

enum LegalDocumentType: Hashable, Identifiable {
    case terms
    case privacy
    case subscription

    var id: String { englishTitle }

    /// Legal screens are always shown in English (App Store / legal consistency).
    var englishTitle: String {
        switch self {
        case .terms: return "Terms of Use"
        case .privacy: return "Privacy Policy"
        case .subscription: return "Subscription Terms"
        }
    }

    var bodyText: String {
        switch self {
        case .terms:
            return """
            TERMS OF USE

            By using the Maia app, you agree to these terms.

            1) Account and security
            - You are responsible for keeping your account credentials secure.
            - If you notice unauthorized use of your account, you must notify us.

            2) Permitted use
            - The app may only be used for lawful, educational purposes.
            - Unauthorized access, attempts to disrupt the service, or reverse engineering are prohibited.

            3) Paid features and subscriptions
            - Premium content may be offered as part of a subscription.
            - Billing, renewal, and cancellation are handled by the Apple App Store.

            4) Changes
            - App features and these terms may be updated from time to time.
            - Material changes will be communicated in the app when possible.

            5) Limitation of liability
            - The app is provided "as is."
            - To the extent permitted by law, we are not liable for indirect damages or service interruptions.

            6) Contact
            - Legal inquiries: \(AppContact.supportEmail)
            """
        case .privacy:
            return """
            PRIVACY POLICY

            This policy explains what data Maia processes and why.

            1) Data we process
            - Account data (email, user identifier)
            - App usage and technical data (analytics, crash logs)
            - Subscription and entitlement status

            2) Purposes
            - Provide sign-in and core app features
            - Improve security, performance, and product quality
            - Deliver Premium features

            3) Third-party services
            - Firebase/Google services may be used for authentication, storage, and analytics.

            4) Retention
            - Data is kept only as long as needed for the purposes above.
            - Deletion or anonymization is applied when legally required or upon valid requests.

            5) Your rights
            - You may request access, correction, or deletion where applicable law allows.

            6) Contact
            - Privacy requests: \(AppContact.privacyEmail)
            """
        case .subscription:
            return """
            SUBSCRIPTION TERMS

            - Payment is charged to your Apple ID account at confirmation of purchase.
            - Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period.
            - Renewal charges may be applied to your account within 24 hours before the current period ends.
            - Manage or cancel subscriptions in your App Store account settings.
            - If a free trial is offered, it converts to a paid subscription unless canceled before the trial ends.
            """
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocumentType

    var body: some View {
        ScrollView {
            Text(document.bodyText)
                .font(.body)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(document.englishTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
