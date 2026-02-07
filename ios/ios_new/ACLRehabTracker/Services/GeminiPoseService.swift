import Foundation
import UIKit
import FirebaseFunctions

class GeminiPoseService {
    static let shared = GeminiPoseService()

    private lazy var functions = Functions.functions(region: "us-central1")

    private init() {}

    /// Detect knee angle from an image using Vertex AI via Cloud Functions
    /// - Parameters:
    ///   - image: UIImage of the leg
    ///   - injuredKnee: Which knee is injured (left/right) - helps AI identify correct leg
    ///   - injuryType: Type of injury for context
    /// - Returns: PoseResult with the detected angle
    func detectKneeAngle(image: UIImage, injuredKnee: KneeSide? = nil, injuryType: InjuryType? = nil) async throws -> PoseResult {
        // Resize image if too large
        let resizedImage = resizeImageIfNeeded(image, maxDimension: 1024)

        // Convert to base64
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw GeminiPoseError.imageLoadFailed
        }
        let base64String = imageData.base64EncodedString()

        // Build request data
        var requestData: [String: Any] = ["imageBase64": base64String]

        // Add injury info if available
        if let knee = injuredKnee {
            requestData["injuredKnee"] = knee.rawValue
        }
        if let injury = injuryType {
            requestData["injuryType"] = injury.rawValue
        }

        // Call the Cloud Function
        do {
            let callable = functions.httpsCallable("analyzeKneeAngle")
            let result = try await callable.call(requestData)

            guard let data = result.data as? [String: Any] else {
                throw GeminiPoseError.invalidResponse
            }

            return try parseCloudFunctionResponse(data)
        } catch let error as GeminiPoseError {
            throw error
        } catch let error as NSError {
            // Handle Firebase Functions errors with user-friendly messages
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw GeminiPoseError.detectionFailed("Authentication error. Please restart the app and try again.")
                case .unavailable:
                    throw GeminiPoseError.detectionFailed("AI service is temporarily unavailable. Please try again later.")
                case .deadlineExceeded:
                    throw GeminiPoseError.detectionFailed("Analysis took too long. Please try again with a clearer photo.")
                default:
                    throw GeminiPoseError.detectionFailed("Could not analyze the photo. Please try again.")
                }
            }
            throw GeminiPoseError.detectionFailed("Could not analyze the photo. Please check your connection and try again.")
        }
    }

    /// Detect knee angle from an image file path
    func detectKneeAngle(imagePath: String, injuredKnee: KneeSide? = nil, injuryType: InjuryType? = nil) async throws -> PoseResult {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            throw GeminiPoseError.imageLoadFailed
        }
        return try await detectKneeAngle(image: image, injuredKnee: injuredKnee, injuryType: injuryType)
    }

    // MARK: - Private Helpers

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage ?? image
    }

    private func parseCloudFunctionResponse(_ data: [String: Any]) throws -> PoseResult {
        guard let angle = data["angle"] as? Int,
              let confidence = data["confidence"] as? Double,
              let hip = data["hip"] as? [String: Double],
              let knee = data["knee"] as? [String: Double],
              let ankle = data["ankle"] as? [String: Double],
              let hipX = hip["x"], let hipY = hip["y"],
              let kneeX = knee["x"], let kneeY = knee["y"],
              let ankleX = ankle["x"], let ankleY = ankle["y"] else {
            throw GeminiPoseError.invalidResponse
        }

        let clampedAngle = max(0, min(180, angle))

        return PoseResult(
            hip: Keypoint(x: hipX, y: hipY, confidence: Float(confidence)),
            knee: Keypoint(x: kneeX, y: kneeY, confidence: Float(confidence)),
            ankle: Keypoint(x: ankleX, y: ankleY, confidence: Float(confidence)),
            angle: clampedAngle
        )
    }
}

// MARK: - Errors

enum GeminiPoseError: LocalizedError {
    case imageLoadFailed
    case noResponse
    case invalidResponse
    case detectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Failed to load image"
        case .noResponse:
            return "No response from server"
        case .invalidResponse:
            return "Could not parse server response"
        case .detectionFailed(let message):
            return message
        }
    }
}
