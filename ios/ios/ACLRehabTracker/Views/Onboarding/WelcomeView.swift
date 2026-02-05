import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack {
            Spacer()

            // Header Section
            VStack(alignment: .leading, spacing: 0) {
                Text("ACL Rehab")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)

                Text("Tracker")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.primary)

                Text("Track your knee recovery progress with precision angle measurements")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.top, AppSpacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            Spacer()

            // Illustration
            KneeIllustration()
                .frame(width: 200, height: 200)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.8)

            Spacer()

            // Feature List
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                FeatureItem(text: "Measure knee extension & flexion")
                FeatureItem(text: "Track progress week over week")
                FeatureItem(text: "Visual proof with photo storage")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            Spacer()

            // Button
            Button(action: onContinue) {
                Text("Get Started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
            .opacity(showContent ? 1 : 0)
        }
        .background(AppColors.background)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }
}

// MARK: - Knee Illustration
struct KneeIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.surface)

            VStack(spacing: -8) {
                // Upper leg
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.primary)
                    .frame(width: 20, height: 60)
                    .rotationEffect(.degrees(-15))

                // Knee joint
                Circle()
                    .fill(AppColors.success)
                    .frame(width: 24, height: 24)
                    .zIndex(1)

                // Lower leg
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.primary)
                    .frame(width: 20, height: 60)
                    .rotationEffect(.degrees(15))
            }
        }
    }
}

// MARK: - Feature Item
struct FeatureItem: View {
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(AppColors.primary)
                .frame(width: 8, height: 8)

            Text(text)
                .font(AppTypography.body)
                .foregroundColor(AppColors.text)
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
