import SwiftUI

/// The row on the Measure tab that shows which method is in use and opens the chooser.
struct MeasureModeRow: View {
    let mode: MeasureMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(mode == .accurate ? AppColors.primary : AppColors.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text("Method")
                    .font(AppTypography.subhead)
                    .foregroundColor(AppColors.textSecondary)

                Text(mode.title)
                    .font(AppTypography.subhead.weight(.semibold))
                    .foregroundColor(AppColors.text)

                Spacer()

                Text("Change")
                    .font(AppTypography.subhead)
                    .foregroundColor(AppColors.primary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm + 2)
            .background(AppColors.surface)
            .cornerRadius(AppRadius.md)
        }
        .accessibilityLabel("Measuring method: \(mode.title)")
        .accessibilityHint("Opens the method chooser")
        .accessibilityIdentifier("measureMode.row")
    }
}

/// Lets the user pick a measuring method and explains, briefly, what each one does.
struct MeasureModeSheet: View {
    @Binding var selection: MeasureMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MeasureModeChooser(selection: $selection, onDone: { dismiss() })
                    .padding(AppSpacing.lg)
            }
            .background(AppColors.background)
            .navigationTitle("Measuring method")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

/// The chooser's content, without the sheet around it, so it can also be rendered on its own.
struct MeasureModeChooser: View {
    @Binding var selection: MeasureMode
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("How do you want to measure?")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.text)

            Text("Both methods save to the same history. You can switch any time.")
                .font(AppTypography.subhead)
                .foregroundColor(AppColors.textSecondary)

            ForEach(MeasureMode.allCases) { mode in
                modeCard(mode)
            }

            howItWorks

            Button(action: onDone) {
                Text("Done")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: true))
            .padding(.top, AppSpacing.sm)
            .accessibilityIdentifier("measureMode.done")
        }
    }

    private func modeCard(_ mode: MeasureMode) -> some View {
        let isSelected = selection == mode
        return Button(action: { selection = mode }) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(mode.title)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.text)
                        if mode == .standard {
                            tag("Default")
                        } else {
                            tag("New")
                        }
                    }
                    Text(mode.summary)
                        .font(AppTypography.subhead)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.border)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isSelected ? AppColors.primary : Color.clear, lineWidth: 2)
            )
            .cornerRadius(AppRadius.lg)
        }
        .accessibilityLabel("\(mode.title). \(mode.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("measureMode.\(mode.rawValue)")
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption2.weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(AppColors.surfaceLight)
            .cornerRadius(AppRadius.sm)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("HOW ACCURATE MODE WORKS")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
                .tracking(1)

            step(1, icon: "figure.stand",
                 title: "Whole body, side-on",
                 detail: "Prop your phone up or ask someone to take the photo. Head to feet in the picture, with the camera looking at the side of your leg.")
            step(2, icon: "checkmark.shield",
                 title: "AI checks the photo",
                 detail: "It only decides whether the photo is usable, for example that your leg isn't cut off. If not, it tells you what to change.")
            step(3, icon: "iphone",
                 title: "Your phone measures the angle",
                 detail: "It marks your hip, knee and ankle and measures the angle between the lines. You see the lines on your photo and can drag a dot if one is off.")

            Text("A close-up of just your knee won't work in this mode. Use Standard photo for those. Either way, this is for personal tracking and is not a medical device.")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
        .accessibilityIdentifier("measureMode.explainer")
    }

    private func step(_ number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.primary)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)
                Text(detail)
                    .font(AppTypography.subhead)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MeasureModeSheet(selection: .constant(.accurate))
}
