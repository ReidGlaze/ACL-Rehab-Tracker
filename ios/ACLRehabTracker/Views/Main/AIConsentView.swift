import SwiftUI

struct AIConsentView: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    private let privacyPolicyURL = URL(string: "https://aclrehabtracker.vercel.app/privacy")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Header
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Image(systemName: "brain")
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.primary)
                            .accessibilityHidden(true)

                        Text("AI Photo Analysis")
                            .font(AppTypography.title2)
                            .foregroundColor(AppColors.text)

                        Text("Before measuring your knee angle, please review how your photo is processed.")
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        bulletPoint(
                            icon: "photo",
                            title: "What is sent",
                            detail: "Your knee photo is sent for AI-powered angle analysis. Your injury side (left/right) and injury type are also sent to improve accuracy."
                        )

                        bulletPoint(
                            icon: "cloud",
                            title: "Who processes it",
                            detail: "Photos are processed by Google's Vertex AI (Gemini model) via a secure Google Cloud Function."
                        )

                        bulletPoint(
                            icon: "clock.arrow.circlepath",
                            title: "How it's handled",
                            detail: "The photo is analyzed in real time and is not stored or retained by the AI service after processing."
                        )
                    }

                    // Privacy Policy link
                    Button(action: { openURL(privacyPolicyURL) }) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "doc.text")
                            Text("View Full Privacy Policy")
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                        }
                        .font(AppTypography.subhead)
                        .foregroundColor(AppColors.primary)
                    }
                    .padding(.top, AppSpacing.xs)

                    // Buttons
                    VStack(spacing: AppSpacing.sm) {
                        Button(action: onAgree) {
                            Text("I Agree")
                        }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: true))

                        Button(action: onCancel) {
                            Text("Cancel")
                        }
                        .buttonStyle(SecondaryButtonStyle(isEnabled: true))
                    }
                    .padding(.top, AppSpacing.md)
                }
                .padding(AppSpacing.lg)
            }
            .background(AppColors.background)
            .navigationTitle("Data Consent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bulletPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.primary)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)

                Text(detail)
                    .font(AppTypography.subhead)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}

#Preview {
    AIConsentView(onAgree: {}, onCancel: {})
}
