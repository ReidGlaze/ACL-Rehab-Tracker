import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Last updated: November 3, 2026")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textSecondary)

                    section(title: "What Data We Collect") {
                        """
                        ACL Rehab Tracker collects the following information to help you track \
                        your rehabilitation progress:

                        • Your name (for personalization)
                        • Surgery date and injury details (to calculate recovery week)
                        • Knee angle measurements (extension and flexion values)
                        • Knee photos you submit for AI angle analysis

                        All data is associated with an anonymous account — we do not collect \
                        your email, phone number, or any other personal identifiers.
                        """
                    }

                    section(title: "How Data Is Stored") {
                        """
                        Your data is stored securely in Google Firebase (Firestore and Cloud Storage) \
                        and is associated only with your anonymous user ID. Photos are stored in \
                        Firebase Storage and are only accessible to your account.
                        """
                    }

                    section(title: "AI Knee Angle Analysis") {
                        """
                        When you submit a photo for angle measurement, the following data is sent \
                        through a secure Google Cloud Function to an AI model hosted on Google Cloud \
                        Vertex AI (such as Anthropic's Claude or Google's Gemini):

                        • Your knee photo (image data)
                        • Your injured knee side (left or right)
                        • Your injury type (e.g., ACL reconstruction)

                        This data is used solely to estimate your knee angle. The specific AI model \
                        may change as we improve accuracy, but processing always takes place on \
                        Google Cloud Vertex AI. The photo is analyzed in real time and is not stored \
                        or retained by the AI model after processing. Google processes this data \
                        under their Cloud data processing terms.
                        """
                    }

                    section(title: "Analytics") {
                        """
                        We use Google Analytics for Firebase to understand how the app is used, \
                        such as app opens, screens viewed, and whether measurements succeed. This \
                        usage data is tied to a random app identifier, not to your name, and never \
                        includes your photos, knee angles, or injury details.
                        """
                    }

                    section(title: "Third-Party Data Processing") {
                        """
                        Your knee photos and injury details are processed on Google Cloud Vertex AI \
                        for AI-powered angle analysis, and anonymous usage data is processed by \
                        Google Analytics for Firebase. Google acts as a data processor for both.

                        Apart from this processing, we do not sell, share, or distribute \
                        your data to any other third parties. Your rehabilitation data is used \
                        solely to provide you with the app's features.
                        """
                    }

                    section(title: "Data Deletion") {
                        """
                        Since your account is anonymous, uninstalling the app effectively removes \
                        your access to the data. If you would like your data permanently deleted \
                        from our servers, please contact us.
                        """
                    }

                    section(title: "Contact") {
                        "If you have questions about this policy, contact us at support@twintipsolutions.com."
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(AppColors.background)
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.text)

            Text(content())
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

#Preview {
    PrivacyPolicyView()
}
