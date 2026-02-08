import Foundation
import Vision
import UIKit
import CoreMedia
import CoreVideo

class PoseDetectionService {
    static let shared = PoseDetectionService()

    private init() {}

    /// Detect pose from an image file path
    /// - Parameter imagePath: Path to the image file
    /// - Returns: PoseResult containing keypoints and calculated knee angle
    func detectPose(imagePath: String) async throws -> PoseResult {
        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            throw PoseDetectionError.imageLoadFailed
        }

        return try await detectPose(cgImage: cgImage, imageSize: image.size)
    }

    /// Detect pose from a UIImage
    /// - Parameter image: UIImage to analyze
    /// - Returns: PoseResult containing keypoints and calculated knee angle
    func detectPose(image: UIImage) async throws -> PoseResult {
        guard let cgImage = image.cgImage else {
            throw PoseDetectionError.imageLoadFailed
        }

        return try await detectPose(cgImage: cgImage, imageSize: image.size)
    }

    /// Detect pose from a CMSampleBuffer (for live video frames)
    /// - Parameter sampleBuffer: The video frame buffer
    /// - Returns: PoseResult containing normalized keypoints (0-1) for overlay rendering
    func detectPose(sampleBuffer: CMSampleBuffer) async throws -> PoseResult {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw PoseDetectionError.imageLoadFailed
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        // Try all orientations to find one that works
        let orientations: [CGImagePropertyOrientation] = [.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored]

        for orientation in orientations {
            if let result = try? await tryDetectPose(pixelBuffer: pixelBuffer, orientation: orientation, imageSize: imageSize) {
                print("✅ SUCCESS with orientation: \(orientation.rawValue)")
                return result
            }
        }

        throw PoseDetectionError.noBodyDetected
    }

    private func tryDetectPose(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, imageSize: CGSize) async throws -> PoseResult {
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let request = VNDetectHumanBodyPoseRequest { request, error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    continuation.resume(throwing: PoseDetectionError.detectionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNHumanBodyPoseObservation],
                      let observation = observations.first else {
                    continuation.resume(throwing: PoseDetectionError.noBodyDetected)
                    return
                }

                do {
                    let result = try self.extractLegKeypointsNormalized(from: observation, imageSize: imageSize)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(throwing: PoseDetectionError.detectionFailed(error.localizedDescription))
                }
            }
        }
    }

    private func detectPose(cgImage: CGImage, imageSize: CGSize) async throws -> PoseResult {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: PoseDetectionError.detectionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNHumanBodyPoseObservation],
                      let observation = observations.first else {
                    continuation.resume(throwing: PoseDetectionError.noBodyDetected)
                    return
                }

                do {
                    let result = try self.extractLegKeypoints(from: observation, imageSize: imageSize)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: PoseDetectionError.detectionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Extract keypoints with normalized coordinates (0-1) for overlay rendering
    private func extractLegKeypointsNormalized(from observation: VNHumanBodyPoseObservation,
                                               imageSize: CGSize) throws -> PoseResult {
        let (hip, knee, ankle) = try getLegKeypoints(from: observation, preferRight: true)

        // For overlay, we keep normalized coordinates but flip Y for SwiftUI coordinate system
        // Vision uses bottom-left origin, SwiftUI uses top-left
        let hipPoint = CGPoint(x: hip.location.x, y: 1 - hip.location.y)
        let kneePoint = CGPoint(x: knee.location.x, y: 1 - knee.location.y)
        let anklePoint = CGPoint(x: ankle.location.x, y: 1 - ankle.location.y)

        // Calculate angle using normalized points (works the same)
        let angle = calculateKneeAngleNormalized(hip: hipPoint, knee: kneePoint, ankle: anklePoint)

        return PoseResult(
            hip: Keypoint(x: hipPoint.x, y: hipPoint.y, confidence: hip.confidence),
            knee: Keypoint(x: kneePoint.x, y: kneePoint.y, confidence: knee.confidence),
            ankle: Keypoint(x: anklePoint.x, y: anklePoint.y, confidence: ankle.confidence),
            angle: angle
        )
    }

    private func extractLegKeypoints(from observation: VNHumanBodyPoseObservation,
                                     imageSize: CGSize) throws -> PoseResult {
        // Try to get right leg keypoints first, fall back to left leg
        let (hip, knee, ankle) = try getLegKeypoints(from: observation, preferRight: true)

        // Convert normalized coordinates to image coordinates
        let hipPoint = convertPoint(hip.location, imageSize: imageSize)
        let kneePoint = convertPoint(knee.location, imageSize: imageSize)
        let anklePoint = convertPoint(ankle.location, imageSize: imageSize)

        // Calculate knee angle
        let angle = calculateKneeAngle(hip: hipPoint, knee: kneePoint, ankle: anklePoint)

        return PoseResult(
            hip: Keypoint(x: hipPoint.x, y: hipPoint.y, confidence: hip.confidence),
            knee: Keypoint(x: kneePoint.x, y: kneePoint.y, confidence: knee.confidence),
            ankle: Keypoint(x: anklePoint.x, y: anklePoint.y, confidence: ankle.confidence),
            angle: angle
        )
    }

    private func getLegKeypoints(from observation: VNHumanBodyPoseObservation,
                                 preferRight: Bool) throws -> (hip: VNRecognizedPoint, knee: VNRecognizedPoint, ankle: VNRecognizedPoint) {
        // Define joint names for both legs
        let rightJoints: [VNHumanBodyPoseObservation.JointName] = [.rightHip, .rightKnee, .rightAnkle]
        let leftJoints: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .leftKnee, .leftAnkle]

        let primaryJoints = preferRight ? rightJoints : leftJoints
        let fallbackJoints = preferRight ? leftJoints : rightJoints

        // Try primary side first
        if let points = try? getJointPoints(from: observation, joints: primaryJoints) {
            return points
        }

        // Fall back to other side
        if let points = try? getJointPoints(from: observation, joints: fallbackJoints) {
            return points
        }

        throw PoseDetectionError.keypointsNotDetected
    }

    private func getJointPoints(from observation: VNHumanBodyPoseObservation,
                                joints: [VNHumanBodyPoseObservation.JointName]) throws
    -> (hip: VNRecognizedPoint, knee: VNRecognizedPoint, ankle: VNRecognizedPoint) {
        let minConfidence: Float = 0.1  // Lower threshold for testing

        let hip = try observation.recognizedPoint(joints[0])
        let knee = try observation.recognizedPoint(joints[1])
        let ankle = try observation.recognizedPoint(joints[2])

        print("🦵 Joint confidence - Hip: \(hip.confidence), Knee: \(knee.confidence), Ankle: \(ankle.confidence)")

        guard hip.confidence > minConfidence,
              knee.confidence > minConfidence,
              ankle.confidence > minConfidence else {
            throw PoseDetectionError.lowConfidence
        }

        return (hip, knee, ankle)
    }

    private func convertPoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        // VNRecognizedPoint uses normalized coordinates (0-1) with origin at bottom-left
        // Convert to image coordinates with origin at top-left
        return CGPoint(
            x: point.x * imageSize.width,
            y: (1 - point.y) * imageSize.height  // Flip Y axis
        )
    }

    private func calculateKneeAngle(hip: CGPoint, knee: CGPoint, ankle: CGPoint) -> Int {
        // Calculate vectors from knee to hip and knee to ankle
        let v1 = CGPoint(x: hip.x - knee.x, y: hip.y - knee.y)
        let v2 = CGPoint(x: ankle.x - knee.x, y: ankle.y - knee.y)

        // Calculate dot product and magnitudes
        let dotProduct = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)

        // Calculate angle in radians then convert to degrees
        let cosAngle = dotProduct / (mag1 * mag2)
        let angleRadians = acos(min(max(cosAngle, -1), 1))  // Clamp to [-1, 1]
        let angleDegrees = angleRadians * 180 / .pi

        // Return the angle (180 - angle gives the interior knee angle)
        // For extension: 180° = fully straight, <180° = flexed
        // We want to report deviation from straight, so:
        // 0° extension means fully straight (180° interior angle)
        return Int(round(180 - angleDegrees))
    }

    private func calculateKneeAngleNormalized(hip: CGPoint, knee: CGPoint, ankle: CGPoint) -> Int {
        // Same calculation works for normalized coordinates
        return calculateKneeAngle(hip: hip, knee: knee, ankle: ankle)
    }
}

// MARK: - Pose Detection Errors

enum PoseDetectionError: LocalizedError {
    case imageLoadFailed
    case detectionFailed(String)
    case noBodyDetected
    case keypointsNotDetected
    case lowConfidence

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Failed to load image"
        case .detectionFailed(let message):
            return "Detection failed: \(message)"
        case .noBodyDetected:
            return "No body detected in image"
        case .keypointsNotDetected:
            return "Could not detect leg keypoints"
        case .lowConfidence:
            return "Low confidence keypoints"
        }
    }
}
