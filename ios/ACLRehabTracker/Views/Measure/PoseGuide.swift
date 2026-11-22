import SwiftUI

/// A simple side-on drawing of the pose for one movement, as the phone should see it.
/// Drawn for the right knee (head at the left, right leg nearest the camera) and mirrored for the left.
struct PoseIllustration: View {
    let type: MeasurementType
    let side: KneeSide?

    var body: some View {
        Canvas { context, size in
            // Design space is 300 x 112 (drawn with the floor at y = 124, so shift up); scale to fit.
            let scale = min(size.width / 300, size.height / 112)
            context.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 112 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: -34)

            let grey = GraphicsContext.Shading.color(AppColors.textSecondary)
            let accent = GraphicsContext.Shading.color(AppColors.primary)
            let limb = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)

            // The phone's view: whole body inside the frame.
            let frame = Path(roundedRect: CGRect(x: 6, y: 38, width: 288, height: 104), cornerRadius: 12)
            context.stroke(frame, with: .color(AppColors.border), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))

            // Floor.
            var floor = Path()
            floor.move(to: CGPoint(x: 18, y: 124)); floor.addLine(to: CGPoint(x: 282, y: 124))
            context.stroke(floor, with: .color(AppColors.border), lineWidth: 2)

            // Far leg, flat on the floor.
            var farLeg = Path()
            farLeg.move(to: CGPoint(x: 132, y: 114)); farLeg.addLine(to: CGPoint(x: 250, y: 116)); farLeg.addLine(to: CGPoint(x: 256, y: 101))
            context.stroke(farLeg, with: grey, style: limb)

            // Head, torso and arm.
            context.fill(Path(ellipseIn: CGRect(x: 26, y: 92, width: 26, height: 26)), with: grey)
            var torso = Path()
            torso.move(to: CGPoint(x: 62, y: 110)); torso.addLine(to: CGPoint(x: 132, y: 112))
            context.stroke(torso, with: grey, style: StrokeStyle(lineWidth: 15, lineCap: .round))
            var arm = Path()
            arm.move(to: CGPoint(x: 66, y: 116)); arm.addLine(to: CGPoint(x: 112, y: 119))
            context.stroke(arm, with: .color(AppColors.textTertiary), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            // The leg being measured, nearest the camera.
            let hip = CGPoint(x: 132, y: 110)
            let knee = type == .flexion ? CGPoint(x: 176, y: 58) : CGPoint(x: 191, y: 110)
            let ankle = type == .flexion ? CGPoint(x: 200, y: 112) : CGPoint(x: 250, y: 110)
            let toe = type == .flexion ? CGPoint(x: 217, y: 113) : CGPoint(x: 256, y: 95)
            var nearLeg = Path()
            nearLeg.move(to: hip); nearLeg.addLine(to: knee); nearLeg.addLine(to: ankle); nearLeg.addLine(to: toe)
            context.stroke(nearLeg, with: accent, style: limb)
            for joint in [hip, knee, ankle] {
                context.fill(Path(ellipseIn: CGRect(x: joint.x - 6.5, y: joint.y - 6.5, width: 13, height: 13)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: joint.x - 4, y: joint.y - 4, width: 8, height: 8)), with: accent)
            }
        }
        .aspectRatio(300.0 / 112.0, contentMode: .fit)
        .scaleEffect(x: side == .left ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// "How to pose" for Accurate mode: one drawing per movement and four short rules.
struct PoseGuideSheet: View {
    let type: MeasurementType
    let side: KneeSide?
    @Environment(\.dismiss) private var dismiss

    private var legName: String {
        side.map { "Your \($0.displayName.lowercased()) leg" } ?? "The leg you're measuring"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("How to pose")
                        .font(AppTypography.title2)
                        .foregroundColor(AppColors.text)

                    // The movement being measured now comes first.
                    ForEach(type == .flexion ? [MeasurementType.flexion, .extension] : [.extension, .flexion], id: \.self) { movement in
                        poseCard(movement)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        rule("arrow.left.and.right", "Side-on to the camera")
                        rule("figure.stand", "Whole body in the frame, head to feet")
                        rule("iphone", "Phone propped at knee height")
                        rule("checkmark.circle", "\(legName) nearest the camera")
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface)
                    .cornerRadius(AppRadius.lg)
                    .accessibilityIdentifier("poseGuide.rules")

                    Text("Sitting or standing works too, as long as the camera sees you from the side.")
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: { dismiss() }) {
                        Text("Got it")
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: true))
                    .accessibilityIdentifier("poseGuide.done")
                }
                .padding(AppSpacing.lg)
            }
            .background(AppColors.background)
            .navigationTitle("Accurate mode")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func poseCard(_ movement: MeasurementType) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text(movement.displayName)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)
                if movement == type {
                    Text("Measuring now")
                        .font(AppTypography.caption2.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(AppColors.surfaceLight)
                        .cornerRadius(AppRadius.sm)
                }
            }
            PoseIllustration(type: movement, side: side)
            Text(movement == .flexion
                 ? "Lie on your back and slide your heel in to bend the knee as far as it goes."
                 : "Lie on your back and straighten the knee as far as it goes.")
                .font(AppTypography.subhead)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(movement == type ? AppColors.primary : Color.clear, lineWidth: 2)
        )
        .cornerRadius(AppRadius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("poseGuide.\(movement.rawValue)")
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(AppColors.primary)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .font(AppTypography.subhead)
                .foregroundColor(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PoseGuideSheet(type: .flexion, side: .left)
}
