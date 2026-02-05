package com.twintipsolutions.aclrehabtracker.data.model

import com.google.firebase.Timestamp
import java.util.Date

enum class KneeSide(val displayName: String) {
    LEFT("Left"),
    RIGHT("Right");

    companion object {
        fun fromString(value: String): KneeSide {
            return when (value.lowercase()) {
                "left" -> LEFT
                "right" -> RIGHT
                else -> LEFT
            }
        }
    }
}

enum class InjuryType(val displayName: String, val firestoreValue: String) {
    ACL_ONLY("ACL Only", "acl_only"),
    ACL_MENISCUS("ACL + Meniscus", "acl_meniscus"),
    ACL_MCL("ACL + MCL", "acl_mcl"),
    ACL_MENISCUS_MCL("ACL + Meniscus + MCL", "acl_meniscus_mcl"),
    OTHER("Other", "other");

    companion object {
        fun fromString(value: String): InjuryType {
            return entries.find { it.firestoreValue == value } ?: ACL_ONLY
        }
    }
}

data class UserProfile(
    val id: String = "",
    val name: String = "",
    val surgeryDate: Date? = null,
    val injuredKnee: KneeSide = KneeSide.LEFT,
    val injuryType: InjuryType = InjuryType.ACL_ONLY,
    val createdAt: Date = Date()
) {
    companion object {
        fun fromFirestore(id: String, data: Map<String, Any?>): UserProfile {
            return UserProfile(
                id = id,
                name = data["name"] as? String ?: data["displayName"] as? String ?: "",
                surgeryDate = (data["surgeryDate"] as? Timestamp)?.toDate(),
                injuredKnee = KneeSide.fromString(data["injuredKnee"] as? String ?: "left"),
                injuryType = InjuryType.fromString(data["injuryType"] as? String ?: "acl_only"),
                createdAt = (data["createdAt"] as? Timestamp)?.toDate() ?: Date()
            )
        }
    }

    fun toFirestore(): Map<String, Any?> {
        return mapOf(
            "name" to name,
            "surgeryDate" to surgeryDate?.let { Timestamp(it) },
            "injuredKnee" to injuredKnee.name.lowercase(),
            "injuryType" to injuryType.firestoreValue,
            "createdAt" to Timestamp(createdAt)
        )
    }
}
