import Foundation
import UIKit
import MediaPipeTasksVision

class MediaPipeService {
    static let shared = MediaPipeService()

    private var poseLandmarker: PoseLandmarker?

    private init() {
        setupPoseLandmarker()
    }

    private func setupPoseLandmarker() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else {
            print("❌ MediaPipe: Model file not found")
            return
        }

        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .image
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.5
            options.minPosePresenceConfidence = 0.5
            options.minTrackingConfidence = 0.5

            poseLandmarker = try PoseLandmarker(options: options)
            print("✅ MediaPipe: Pose landmarker initialized")
        } catch {
            print("❌ MediaPipe: Failed to create pose landmarker: \(error)")
        }
    }

    /// Detect pose and draw skeleton overlay on the image
    /// Returns the annotated image with skeleton drawn
    func detectAndDrawSkeleton(image: UIImage) async throws -> UIImage {
        guard let poseLandmarker = poseLandmarker else {
            print("⚠️ MediaPipe not initialized, returning original image")
            return image
        }

        guard let mpImage = try? MPImage(uiImage: image) else {
            throw MediaPipeError.imageConversionFailed
        }

        let result = try poseLandmarker.detect(image: mpImage)

        // Draw skeleton on image
        let annotatedImage = drawSkeleton(on: image, result: result)

        return annotatedImage
    }

    /// Draw skeleton overlay on image
    private func drawSkeleton(on image: UIImage, result: PoseLandmarkerResult) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)

        return renderer.image { context in
            // Draw original image
            image.draw(at: .zero)

            let ctx = context.cgContext

            guard let landmarks = result.landmarks.first, !landmarks.isEmpty else {
                print("⚠️ MediaPipe: No landmarks detected")
                return
            }

            print("✅ MediaPipe: Detected \(landmarks.count) landmarks")

            // Define leg connections (indices from MediaPipe pose landmarks)
            // Right leg: 24 (right hip), 26 (right knee), 28 (right ankle)
            // Left leg: 23 (left hip), 25 (left knee), 27 (left ankle)
            let legConnections = [
                (23, 25), (25, 27),  // Left leg: hip-knee, knee-ankle
                (24, 26), (26, 28),  // Right leg: hip-knee, knee-ankle
                (23, 24),            // Hip connection
            ]

            // Key joint indices for circles
            let keyJoints = [23, 24, 25, 26, 27, 28]  // Hips, knees, ankles

            let imageWidth = image.size.width
            let imageHeight = image.size.height

            // Draw connections (lines)
            ctx.setStrokeColor(UIColor.systemPink.cgColor)
            ctx.setLineWidth(6.0)
            ctx.setLineCap(.round)

            for (startIdx, endIdx) in legConnections {
                guard startIdx < landmarks.count, endIdx < landmarks.count else { continue }

                let start = landmarks[startIdx]
                let end = landmarks[endIdx]

                // Only draw if confidence is reasonable
                guard start.visibility?.floatValue ?? 0 > 0.3,
                      end.visibility?.floatValue ?? 0 > 0.3 else { continue }

                let startPoint = CGPoint(
                    x: CGFloat(start.x) * imageWidth,
                    y: CGFloat(start.y) * imageHeight
                )
                let endPoint = CGPoint(
                    x: CGFloat(end.x) * imageWidth,
                    y: CGFloat(end.y) * imageHeight
                )

                ctx.move(to: startPoint)
                ctx.addLine(to: endPoint)
            }
            ctx.strokePath()

            // Draw joint circles
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.setStrokeColor(UIColor.systemPink.cgColor)
            ctx.setLineWidth(3.0)

            for jointIdx in keyJoints {
                guard jointIdx < landmarks.count else { continue }
                let landmark = landmarks[jointIdx]

                guard landmark.visibility?.floatValue ?? 0 > 0.3 else { continue }

                let point = CGPoint(
                    x: CGFloat(landmark.x) * imageWidth,
                    y: CGFloat(landmark.y) * imageHeight
                )

                let radius: CGFloat = 12
                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                ctx.fillEllipse(in: rect)
                ctx.strokeEllipse(in: rect)
            }

            // Add labels for knee joints
            let kneeIndices = [(25, "L"), (26, "R")]
            for (idx, label) in kneeIndices {
                guard idx < landmarks.count else { continue }
                let landmark = landmarks[idx]
                guard landmark.visibility?.floatValue ?? 0 > 0.3 else { continue }

                let point = CGPoint(
                    x: CGFloat(landmark.x) * imageWidth,
                    y: CGFloat(landmark.y) * imageHeight
                )

                let text = "Knee \(label)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.systemPink.withAlphaComponent(0.7)
                ]

                let textSize = text.size(withAttributes: attrs)
                let textRect = CGRect(
                    x: point.x + 15,
                    y: point.y - textSize.height / 2,
                    width: textSize.width + 8,
                    height: textSize.height + 4
                )

                text.draw(in: textRect, withAttributes: attrs)
            }
        }
    }
}

// MARK: - Errors

enum MediaPipeError: LocalizedError {
    case notInitialized
    case imageConversionFailed
    case detectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "MediaPipe not initialized"
        case .imageConversionFailed:
            return "Failed to convert image for MediaPipe"
        case .detectionFailed(let message):
            return "Detection failed: \(message)"
        }
    }
}
