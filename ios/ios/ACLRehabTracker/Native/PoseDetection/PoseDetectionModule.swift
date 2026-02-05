import Foundation
import Vision
import UIKit
import React

@objc(PoseDetectionModule)
class PoseDetectionModule: NSObject {

  @objc
  static func requiresMainQueueSetup() -> Bool {
    return false
  }

  @objc
  func detectPose(_ imagePath: String,
                  resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {

    // Load image
    guard let image = UIImage(contentsOfFile: imagePath),
          let cgImage = image.cgImage else {
      reject("POSE_ERROR", "Failed to load image", nil)
      return
    }

    // Create body pose detection request
    let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
      if let error = error {
        reject("POSE_ERROR", "Detection failed: \(error.localizedDescription)", error)
        return
      }

      guard let observations = request.results as? [VNHumanBodyPoseObservation],
            let observation = observations.first else {
        reject("POSE_ERROR", "No body detected in image", nil)
        return
      }

      // Extract leg keypoints
      do {
        let result = try self?.extractLegKeypoints(from: observation, imageSize: image.size)
        resolve(result)
      } catch {
        reject("POSE_ERROR", "Failed to extract keypoints: \(error.localizedDescription)", error)
      }
    }

    // Perform detection
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        reject("POSE_ERROR", "Failed to perform detection: \(error.localizedDescription)", error)
      }
    }
  }

  private func extractLegKeypoints(from observation: VNHumanBodyPoseObservation,
                                    imageSize: CGSize) throws -> [String: Any] {
    // Try to get right leg keypoints first, fall back to left leg
    let (hip, knee, ankle) = try getLegKeypoints(from: observation, preferRight: true)

    // Convert normalized coordinates to image coordinates
    let hipPoint = convertPoint(hip.location, imageSize: imageSize)
    let kneePoint = convertPoint(knee.location, imageSize: imageSize)
    let anklePoint = convertPoint(ankle.location, imageSize: imageSize)

    // Calculate knee angle
    let angle = calculateKneeAngle(hip: hipPoint, knee: kneePoint, ankle: anklePoint)

    return [
      "hip": [
        "x": hipPoint.x,
        "y": hipPoint.y,
        "confidence": hip.confidence
      ],
      "knee": [
        "x": kneePoint.x,
        "y": kneePoint.y,
        "confidence": knee.confidence
      ],
      "ankle": [
        "x": anklePoint.x,
        "y": anklePoint.y,
        "confidence": ankle.confidence
      ],
      "angle": angle
    ]
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

    throw NSError(domain: "PoseDetection", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Could not detect leg keypoints"])
  }

  private func getJointPoints(from observation: VNHumanBodyPoseObservation,
                              joints: [VNHumanBodyPoseObservation.JointName]) throws
  -> (hip: VNRecognizedPoint, knee: VNRecognizedPoint, ankle: VNRecognizedPoint) {

    let minConfidence: Float = 0.3

    let hip = try observation.recognizedPoint(joints[0])
    let knee = try observation.recognizedPoint(joints[1])
    let ankle = try observation.recognizedPoint(joints[2])

    guard hip.confidence > minConfidence,
          knee.confidence > minConfidence,
          ankle.confidence > minConfidence else {
      throw NSError(domain: "PoseDetection", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Low confidence keypoints"])
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

  private func calculateKneeAngle(hip: CGPoint, knee: CGPoint, ankle: CGPoint) -> Double {
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
    return round(180 - angleDegrees)
  }
}
