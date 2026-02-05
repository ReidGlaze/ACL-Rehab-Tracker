import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    var id: String?
    var name: String
    var surgeryDate: Date
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case surgeryDate
        case createdAt
    }

    init(name: String, surgeryDate: Date, createdAt: Date = Date()) {
        self.name = name
        self.surgeryDate = surgeryDate
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(Timestamp(date: surgeryDate), forKey: .surgeryDate)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
    }
}
