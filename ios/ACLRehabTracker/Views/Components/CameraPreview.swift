import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.session = session
    }
}

class CameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var session: AVCaptureSession? {
        didSet {
            setupPreviewLayer()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    private func setupPreviewLayer() {
        previewLayer?.removeFromSuperlayer()

        guard let session = session else { return }

        let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        newPreviewLayer.videoGravity = .resizeAspectFill
        newPreviewLayer.frame = bounds
        layer.addSublayer(newPreviewLayer)
        previewLayer = newPreviewLayer
    }
}

// MARK: - Live Pose Overlay

struct PoseOverlay: View {
    let poseResult: PoseResult?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let pose = poseResult {
                    // Draw lines connecting the joints
                    Path { path in
                        let hipPoint = convertToViewCoordinates(pose.hip, in: geometry.size)
                        let kneePoint = convertToViewCoordinates(pose.knee, in: geometry.size)
                        let anklePoint = convertToViewCoordinates(pose.ankle, in: geometry.size)

                        path.move(to: hipPoint)
                        path.addLine(to: kneePoint)
                        path.addLine(to: anklePoint)
                    }
                    .stroke(AppColors.primary, lineWidth: 3)

                    // Hip marker
                    JointMarker(
                        position: convertToViewCoordinates(pose.hip, in: geometry.size),
                        confidence: pose.hip.confidence,
                        label: "Hip"
                    )

                    // Knee marker
                    JointMarker(
                        position: convertToViewCoordinates(pose.knee, in: geometry.size),
                        confidence: pose.knee.confidence,
                        label: "Knee"
                    )

                    // Ankle marker
                    JointMarker(
                        position: convertToViewCoordinates(pose.ankle, in: geometry.size),
                        confidence: pose.ankle.confidence,
                        label: "Ankle"
                    )

                    // Live angle display
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(pose.angle)\u{00B0}")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(AppColors.primary.opacity(0.8))
                                .cornerRadius(AppRadius.md)
                                .padding()
                        }
                        Spacer()
                    }
                } else {
                    // Show guide overlay when no pose detected
                    CameraGuideOverlay()
                }
            }
        }
    }

    private func convertToViewCoordinates(_ keypoint: Keypoint, in size: CGSize) -> CGPoint {
        // Keypoints are already in normalized coordinates (0-1) with Y flipped for SwiftUI
        CGPoint(
            x: keypoint.x * size.width,
            y: keypoint.y * size.height
        )
    }
}

// MARK: - Joint Marker View

struct JointMarker: View {
    let position: CGPoint
    let confidence: Float
    let label: String

    private var markerSize: CGFloat { 24 }
    private var opacity: Double { Double(min(max(confidence, 0.5), 1.0)) }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: markerSize, height: markerSize)

            // Filled inner circle
            Circle()
                .fill(AppColors.primary)
                .frame(width: markerSize - 6, height: markerSize - 6)
        }
        .opacity(opacity)
        .position(position)
        .animation(.easeOut(duration: 0.1), value: position.x)
        .animation(.easeOut(duration: 0.1), value: position.y)
    }
}

// MARK: - Guide Overlay (shown when no pose detected)

struct CameraGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Vertical guide line
                Rectangle()
                    .fill(AppColors.primary.opacity(0.4))
                    .frame(width: 2, height: geometry.size.height * 0.6)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Joint markers
                Circle()
                    .stroke(AppColors.primary.opacity(0.6), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.3)

                Circle()
                    .stroke(AppColors.primary.opacity(0.6), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.5)

                Circle()
                    .stroke(AppColors.primary.opacity(0.6), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.7)

                // Hint text
                VStack {
                    Spacer()
                    Text("Position leg in frame")
                        .font(AppTypography.footnote)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(AppRadius.sm)
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

// MARK: - Camera Placeholder

struct CameraPlaceholder: View {
    var message: String = "Camera Preview"
    var submessage: String = "Position your leg in frame"

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Text(message)
                .font(AppTypography.title3)
                .foregroundColor(AppColors.textSecondary)

            Text(submessage)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.surface)
    }
}

#Preview {
    ZStack {
        Color.black
        PoseOverlay(poseResult: PoseResult(
            hip: Keypoint(x: 0.5, y: 0.3, confidence: 0.9),
            knee: Keypoint(x: 0.5, y: 0.5, confidence: 0.9),
            ankle: Keypoint(x: 0.5, y: 0.7, confidence: 0.9),
            angle: 175
        ))
    }
    .frame(width: 300, height: 400)
}
