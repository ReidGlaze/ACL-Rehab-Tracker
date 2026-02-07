package com.twintipsolutions.aclrehabtracker.data.service

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.model.UserProfile
import kotlinx.coroutines.tasks.await

object FirestoreService {
    private val db = FirebaseFirestore.getInstance()

    // --- User Profile ---

    suspend fun saveUserProfile(uid: String, profile: UserProfile) {
        db.collection("users").document(uid)
            .collection("profile").document("info")
            .set(profile.toFirestore())
            .await()
    }

    suspend fun getUserProfile(uid: String): UserProfile? {
        val doc = db.collection("users").document(uid)
            .collection("profile").document("info")
            .get()
            .await()
        val data = doc.data ?: return null
        return UserProfile.fromFirestore(uid, data)
    }

    // --- Measurements ---

    suspend fun saveMeasurement(uid: String, measurement: Measurement): String {
        val docRef = db.collection("users").document(uid)
            .collection("measurements")
            .add(measurement.toFirestore())
            .await()
        return docRef.id
    }

    suspend fun getMeasurements(uid: String): List<Measurement> {
        val snapshot = db.collection("users").document(uid)
            .collection("measurements")
            .orderBy("timestamp", Query.Direction.DESCENDING)
            .get()
            .await()
        return snapshot.documents.mapNotNull { doc ->
            doc.data?.let { Measurement.fromFirestore(doc.id, it) }
        }
    }

    suspend fun getMeasurementsByType(uid: String, type: MeasurementType): List<Measurement> {
        val snapshot = db.collection("users").document(uid)
            .collection("measurements")
            .whereEqualTo("type", type.name.lowercase())
            .orderBy("timestamp", Query.Direction.DESCENDING)
            .get()
            .await()
        return snapshot.documents.mapNotNull { doc ->
            doc.data?.let { Measurement.fromFirestore(doc.id, it) }
        }
    }

    suspend fun updateMeasurementPhotoUrl(uid: String, measurementId: String, photoUrl: String) {
        db.collection("users").document(uid)
            .collection("measurements").document(measurementId)
            .update("photoUrl", photoUrl)
            .await()
    }

    suspend fun deleteMeasurement(uid: String, measurementId: String) {
        db.collection("users").document(uid)
            .collection("measurements").document(measurementId)
            .delete()
            .await()
    }

    suspend fun deleteUserData(uid: String) {
        val batch = db.batch()

        // Delete profile
        val profileRef = db.collection("users").document(uid)
            .collection("profile").document("info")
        batch.delete(profileRef)

        // Delete all measurements
        val snapshot = db.collection("users").document(uid)
            .collection("measurements")
            .get()
            .await()
        for (doc in snapshot.documents) {
            batch.delete(doc.reference)
        }

        batch.commit().await()
    }
}
