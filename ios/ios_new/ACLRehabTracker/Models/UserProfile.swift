import Foundation
import FirebaseFirestore

// MARK: - Knee Side

enum KneeSide: String, Codable, CaseIterable {
    case left = "left"
    case right = "right"

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

// MARK: - Injury Type

enum InjuryType: String, Codable, CaseIterable {
    case aclOnly = "acl_only"
    case aclMeniscus = "acl_meniscus"
    case aclMcl = "acl_mcl"
    case aclMeniscusMcl = "acl_meniscus_mcl"
    case other = "other"

    var displayName: String {
        switch self {
        case .aclOnly: return "ACL Only"
        case .aclMeniscus: return "ACL + Meniscus"
        case .aclMcl: return "ACL + MCL"
        case .aclMeniscusMcl: return "ACL + Meniscus + MCL"
        case .other: return "Other"
        }
    }

    var description: String {
        switch self {
        case .aclOnly: return "Anterior cruciate ligament reconstruction"
        case .aclMeniscus: return "ACL reconstruction with meniscus repair"
        case .aclMcl: return "ACL and medial collateral ligament"
        case .aclMeniscusMcl: return "ACL, meniscus, and MCL repair"
        case .other: return "Other knee procedure"
        }
    }
}

// MARK: - User Profile

struct UserProfile: Codable, Identifiable {
    var id: String?
    var name: String
    var surgeryDate: Date
    var injuredKnee: KneeSide
    var injuryType: InjuryType
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case surgeryDate
        case injuredKnee
        case injuryType
        case createdAt
    }

    init(name: String, surgeryDate: Date, injuredKnee: KneeSide = .right, injuryType: InjuryType = .aclOnly, createdAt: Date = Date()) {
        self.name = name
        self.surgeryDate = surgeryDate
        self.injuredKnee = injuredKnee
        self.injuryType = injuryType
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)

        // Handle Firestore Timestamp conversion
        if let timestamp = try? container.decode(Timestamp.self, forKey: .surgeryDate) {
            surgeryDate = timestamp.dateValue()
        } else {
            surgeryDate = try container.decode(Date.self, forKey: .surgeryDate)
        }

        if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = try container.decode(Date.self, forKey: .createdAt)
        }

        // Decode new fields with defaults for existing users
        injuredKnee = (try? container.decode(KneeSide.self, forKey: .injuredKnee)) ?? .right
        injuryType = (try? container.decode(InjuryType.self, forKey: .injuryType)) ?? .aclOnly
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(Timestamp(date: surgeryDate), forKey: .surgeryDate)
        try container.encode(injuredKnee, forKey: .injuredKnee)
        try container.encode(injuryType, forKey: .injuryType)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
    }
}
