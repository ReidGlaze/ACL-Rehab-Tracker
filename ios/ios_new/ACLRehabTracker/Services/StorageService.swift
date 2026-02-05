import Foundation
import FirebaseStorage
import UIKit

class StorageService {
    static let shared = StorageService()
    private let storage = Storage.storage()

    private init() {}

    /// Upload a photo to Firebase Storage
    /// - Parameters:
    ///   - uid: User ID
    ///   - measurementId: Measurement ID for organizing photos
    ///   - localPath: Local file path of the image
    /// - Returns: Download URL of the uploaded photo
    func uploadPhoto(uid: String, measurementId: String, localPath: String) async throws -> String {
        let fileURL = URL(fileURLWithPath: localPath)
        let data = try Data(contentsOf: fileURL)

        let reference = storage.reference().child("users/\(uid)/photos/\(measurementId).jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await reference.putDataAsync(data, metadata: metadata)
        let downloadURL = try await reference.downloadURL()

        return downloadURL.absoluteString
    }

    /// Upload a UIImage to Firebase Storage
    /// - Parameters:
    ///   - uid: User ID
    ///   - measurementId: Measurement ID for organizing photos
    ///   - image: UIImage to upload
    /// - Returns: Download URL of the uploaded photo
    func uploadImage(uid: String, measurementId: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw StorageError.imageConversionFailed
        }

        let reference = storage.reference().child("users/\(uid)/photos/\(measurementId).jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await reference.putDataAsync(data, metadata: metadata)
        let downloadURL = try await reference.downloadURL()

        return downloadURL.absoluteString
    }

    /// Delete a photo from Firebase Storage
    /// - Parameters:
    ///   - uid: User ID
    ///   - measurementId: Measurement ID
    func deletePhoto(uid: String, measurementId: String) async throws {
        let reference = storage.reference().child("users/\(uid)/photos/\(measurementId).jpg")
        try await reference.delete()
    }

    /// Download a photo from Firebase Storage URL
    /// - Parameter urlString: The Firebase Storage download URL
    /// - Returns: UIImage if successful
    func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw StorageError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw StorageError.imageConversionFailed
        }

        return image
    }
}

enum StorageError: LocalizedError {
    case imageConversionFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG data"
        case .invalidURL:
            return "Invalid storage URL"
        }
    }
}
