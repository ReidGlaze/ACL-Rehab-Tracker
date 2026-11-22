import Foundation
import UIKit
import FirebaseFunctions

/// The AI check's verdict on whether a photo is usable for Accurate mode.
struct KneePhotoCheck: Equatable {
    var passed: Bool
    /// One of the `checkKneePhoto` problem codes.
    var problem: String
    /// A short note for the user. Nil when the photo passed or the check gave none.
    var message: String?
}

/// Accurate mode: the phone finds the joints, and (separately) Gemini says whether the photo is
/// usable. The app computes the angle from the three points, so the number always matches the
/// lines drawn on the photo.
final class KneeAnalyzer {
    static let shared = KneeAnalyzer()

    private lazy var functions = Functions.functions(region: "us-central1")

    private init() {}

    /// On-device. Nil when no complete leg (hip, knee and ankle) is found.
    func detectPose(image: UIImage, type: MeasurementType, injuredKnee: KneeSide?) async -> KneePoseEstimate? {
        guard let cgImage = image.uprightCGImage(maxDimension: 2000) else { return nil }
        let bend: KneeBend = type == .flexion ? .flexion : .extension
        let requested: KneeLeg? = injuredKnee.map { $0 == .left ? .left : .right }
        return await Task.detached(priority: .userInitiated) {
            KneePoseEstimator.estimate(image: cgImage, bend: bend, requested: requested)
        }.value
    }

    /// Returns nil when the check couldn't run (offline, rate limited, not deployed). A check that
    /// can't run must never stop the user from measuring.
    func checkPhoto(image: UIImage, type: MeasurementType) async -> KneePhotoCheck? {
        guard let cgImage = image.uprightCGImage(maxDimension: 1280),
              let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else { return nil }
        do {
            let callable = functions.httpsCallable("checkKneePhoto")
            callable.timeoutInterval = 30
            let response = try await callable.call([
                "imageBase64": jpeg.base64EncodedString(),
                "measurementType": type.rawValue,
            ] as [String: Any])
            return Self.parseCheck(response.data)
        } catch {
            return nil
        }
    }

    static func parseCheck(_ data: Any) -> KneePhotoCheck? {
        guard let dict = data as? [String: Any], let ok = dict["ok"] as? Bool else { return nil }
        return KneePhotoCheck(passed: ok, problem: dict["problem"] as? String ?? "none", message: dict["message"] as? String)
    }
}

extension UIImage {
    /// The pixels the way the photo is displayed (EXIF orientation applied), scaled down so the
    /// longer side is at most `maxDimension`.
    func uprightCGImage(maxDimension: CGFloat) -> CGImage? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
