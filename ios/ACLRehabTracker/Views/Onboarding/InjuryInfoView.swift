import SwiftUI

struct InjuryInfoView: View {
    @Binding var injuredKnee: KneeSide
    @Binding var injuryType: InjuryType
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack {
                    // Header Section
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("About Your\nInjury")
                            .font(AppTypography.largeTitle)
                            .foregroundColor(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("This helps us identify the correct knee in photos")
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xxl)

                    // Knee Selection
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Which knee was injured?")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.text)

                        HStack(spacing: AppSpacing.md) {
                            ForEach(KneeSide.allCases, id: \.self) { side in
                                KneeSelectionButton(
                                    side: side,
                                    isSelected: injuredKnee == side
                                ) {
                                    injuredKnee = side
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xl)

                    // Injury Type Selection
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Type of injury")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.text)

                        VStack(spacing: AppSpacing.sm) {
                            ForEach(InjuryType.allCases, id: \.self) { type in
                                InjuryTypeButton(
                                    type: type,
                                    isSelected: injuryType == type
                                ) {
                                    injuryType = type
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.lg)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            // Continue Button - pinned outside ScrollView
            Button(action: onContinue) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.text)
            }
            .buttonStyle(SecondaryButtonStyle(isEnabled: true))
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background)
    }
}

// MARK: - Knee Selection Button

struct KneeSelectionButton: View {
    let side: KneeSide
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                // Leg icon with indicator
                ZStack {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 48))
                        .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)

                    // Knee indicator
                    Circle()
                        .fill(isSelected ? AppColors.success : AppColors.textTertiary)
                        .frame(width: 12, height: 12)
                        .offset(x: side == .left ? -8 : 8, y: 8)
                }

                Text(side.displayName)
                    .font(AppTypography.headline)
                    .foregroundColor(isSelected ? AppColors.text : AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(isSelected ? AppColors.surface : AppColors.background)
            .cornerRadius(AppRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isSelected ? AppColors.primary : AppColors.surface, lineWidth: 2)
            )
        }
    }
}

// MARK: - Injury Type Button

struct InjuryTypeButton: View {
    let type: InjuryType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(AppTypography.headline)
                        .foregroundColor(isSelected ? AppColors.text : AppColors.textSecondary)

                    Text(type.description)
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.success)
                        .font(.system(size: 24))
                }
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColors.surface : AppColors.background)
            .cornerRadius(AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isSelected ? AppColors.primary : AppColors.surface, lineWidth: 1)
            )
        }
    }
}

#Preview {
    InjuryInfoView(
        injuredKnee: .constant(.right),
        injuryType: .constant(.aclOnly),
        onContinue: {}
    )
}
