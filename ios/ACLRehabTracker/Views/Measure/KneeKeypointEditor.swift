import SwiftUI

/// Shows the photo with hip, knee and ankle drawn on it. Each dot can be dragged, and the angle
/// updates as it moves. The number always matches the picture because both come from the same
/// three points.
struct KneeKeypointEditor: View {
    let image: UIImage
    @Binding var keypoints: KneeKeypoints
    var onEdit: () -> Void = {}

    @State private var activeJoint: Joint?

    enum Joint: String, CaseIterable { case hip, knee, ankle }

    var body: some View {
        GeometryReader { proxy in
            let frame = fittedRect(imageSize: image.size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                    .position(x: frame.midX, y: frame.midY)

                overlay(in: frame)
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    @ViewBuilder
    private func overlay(in frame: CGRect) -> some View {
        let hip = viewPoint(keypoints.hip, frame)
        let knee = viewPoint(keypoints.knee, frame)
        let ankle = viewPoint(keypoints.ankle, frame)

        // White underlay so the lines read on any photo.
        Path { p in
            p.move(to: hip)
            p.addLine(to: knee)
            p.addLine(to: ankle)
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        .shadow(color: .black.opacity(0.35), radius: 3)

        Path { p in
            p.move(to: hip)
            p.addLine(to: knee)
            p.addLine(to: ankle)
        }
        .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        ForEach(Joint.allCases, id: \.self) { joint in
            handle(for: joint, frame: frame)
        }
    }

    private func handle(for joint: Joint, frame: CGRect) -> some View {
        let point = viewPoint(value(for: joint), frame)
        let isActive = activeJoint == joint
        return ZStack {
            Circle().fill(.white).frame(width: isActive ? 30 : 24, height: isActive ? 30 : 24)
            Circle().fill(AppColors.primary).frame(width: isActive ? 20 : 15, height: isActive ? 20 : 15)
        }
        .shadow(color: .black.opacity(0.3), radius: 3)
        .frame(width: 56, height: 56) // generous touch target
        .contentShape(Circle())
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    activeJoint = joint
                    set(NormalizedPoint(
                        x: Double((drag.location.x - frame.minX) / frame.width),
                        y: Double((drag.location.y - frame.minY) / frame.height)
                    ).clamped, for: joint)
                }
                .onEnded { _ in
                    activeJoint = nil
                    onEdit()
                }
        )
        .accessibilityLabel("\(joint.rawValue.capitalized) point")
        .accessibilityHint("Drag to adjust")
        .accessibilityIdentifier("keypoint.\(joint.rawValue)")
    }

    private func value(for joint: Joint) -> NormalizedPoint {
        switch joint {
        case .hip: return keypoints.hip
        case .knee: return keypoints.knee
        case .ankle: return keypoints.ankle
        }
    }

    private func set(_ point: NormalizedPoint, for joint: Joint) {
        switch joint {
        case .hip: keypoints.hip = point
        case .knee: keypoints.knee = point
        case .ankle: keypoints.ankle = point
        }
    }

    private func viewPoint(_ p: NormalizedPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(p.x) * frame.width, y: frame.minY + CGFloat(p.y) * frame.height)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
