import Foundation
import FirebaseFirestore

class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - User Profile

    /// Save user profile to Firestore
    func saveUserProfile(uid: String, profile: UserProfile) async throws {
        let profileRef = db.collection("users").document(uid).collection("profile").document("info")
        try profileRef.setData(from: profile)
    }

    /// Get user profile from Firestore
    func getUserProfile(uid: String) async throws -> UserProfile? {
        let profileRef = db.collection("users").document(uid).collection("profile").document("info")
        let document = try await profileRef.getDocument()

        guard document.exists else { return nil }

        var profile = try document.data(as: UserProfile.self)
        profile.id = document.documentID
        return profile
    }

    // MARK: - Measurements

    /// Save a measurement to Firestore
    func saveMeasurement(uid: String, measurement: Measurement) async throws -> String {
        let measurementsRef = db.collection("users").document(uid).collection("measurements")
        let docRef = try measurementsRef.addDocument(from: measurement)
        return docRef.documentID
    }

    /// Get all measurements for a user, ordered by timestamp descending
    func getMeasurements(uid: String) async throws -> [Measurement] {
        let measurementsRef = db.collection("users").document(uid).collection("measurements")
        let query = measurementsRef.order(by: "timestamp", descending: true)
        let snapshot = try await query.getDocuments()

        return snapshot.documents.compactMap { document in
            var measurement = try? document.data(as: Measurement.self)
            measurement?.id = document.documentID
            return measurement
        }
    }

    /// Get measurements filtered by type
    func getMeasurementsByType(uid: String, type: MeasurementType) async throws -> [Measurement] {
        let measurementsRef = db.collection("users").document(uid).collection("measurements")
        let query = measurementsRef
            .whereField("type", isEqualTo: type.rawValue)
            .order(by: "timestamp", descending: true)
        let snapshot = try await query.getDocuments()

        return snapshot.documents.compactMap { document in
            var measurement = try? document.data(as: Measurement.self)
            measurement?.id = document.documentID
            return measurement
        }
    }

    /// Delete a measurement
    func deleteMeasurement(uid: String, measurementId: String) async throws {
        let measurementRef = db.collection("users").document(uid).collection("measurements").document(measurementId)
        try await measurementRef.delete()
    }

    /// Update photo URL for a measurement
    func updateMeasurementPhotoUrl(uid: String, measurementId: String, photoUrl: String) async throws {
        let measurementRef = db.collection("users").document(uid).collection("measurements").document(measurementId)
        try await measurementRef.updateData(["photoUrl": photoUrl])
    }

    /// Delete all user data (profile + measurements)
    func deleteUserData(uid: String) async throws {
        // Delete profile
        let profileRef = db.collection("users").document(uid).collection("profile").document("info")
        try await profileRef.delete()

        // Delete all measurements
        let measurementsRef = db.collection("users").document(uid).collection("measurements")
        let snapshot = try await measurementsRef.getDocuments()
        for document in snapshot.documents {
            try await document.reference.delete()
        }
    }
}
