import SwiftUI

struct SurgeryDateView: View {
    @Binding var surgeryDate: Date
    var onComplete: () -> Void

    @State private var isLoading = false

    private var weekPostOp: Int {
        DateHelpers.calculateWeekPostOp(from: surgeryDate)
    }

    private var formattedDate: String {
        DateHelpers.formatFullDate(surgeryDate)
    }

    var body: some View {
        VStack {
            // Header Section
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("When was your\nsurgery?")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)

                Text("This helps us calculate your recovery timeline")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xxl)

            // Date Picker
            DatePicker(
                "Surgery Date",
                selection: $surgeryDate,
                in: Date(timeIntervalSince1970: 1577836800)...Calendar.current.date(byAdding: .year, value: 1, to: Date())!, // Jan 1, 2020 to 1 year from now
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)

            // Week Info Card
            VStack(spacing: AppSpacing.xs) {
                Text("You are currently in")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)

                Text("Week \(weekPostOp)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(AppColors.success)

                Text("of your recovery")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: .infinity)
            .background(AppColors.surface)
            .cornerRadius(AppRadius.lg)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xxl)

            Spacer()

            // Start Button
            Button(action: {
                isLoading = true
                onComplete()
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.text))
                } else {
                    Text("Start Tracking")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !isLoading))
            .disabled(isLoading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
        .background(AppColors.background)
    }
}

#Preview {
    SurgeryDateView(surgeryDate: .constant(Date()), onComplete: {})
}
