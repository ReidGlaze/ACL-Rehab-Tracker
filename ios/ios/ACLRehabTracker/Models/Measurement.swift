import Foundation
import FirebaseFirestore

enum MeasurementType: String, Codable, CaseIterable {
    case `extension` = "extension"
    case flexion = "flexion"

    var displayName: String {
        switch self {
        case .extension: return "Extension"
        case .flexion: return "Flexion"
        }
    }

    var shortName: String {
        switch self {
        case .extension: return "EXT"
        case .flexion: return "FLX"
        }
    }

    var goalAngle: Int {
        switch self {
        case .extension: return 0
        case .flexion: return 135
        }
    }
}

struct Measurement: Codable, Identifiable {
    var id: String?
    var type: MeasurementType
    var angle: Int
    var timestamp: Date
    var weekPostOp: Int
    var photoUrl: String

    enum CodingKeys: String, CodingKey {
        case type
        case angle
        case timestamp
        case weekPostOp
        case photoUrl
    }

    init(id: String? = nil, type: MeasurementType, angle: Int, timestamp: Date = Date(), weekPostOp: Int, photoUrl: String = "") {
        self.id = id
        self.type = type
        self.angle = angle
        self.timestamp = timestamp
        self.weekPostOp = weekPostOp
        self.photoUrl = photoUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MeasurementType.self, forKey: .type)
        angle = try container.decode(Int.self, forKey: .angle)
        weekPostOp = try container.decode(Int.self, forKey: .weekPostOp)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl) ?? ""

        // Handle Firestore Timestamp conversion
        if let timestamp = try? container.decode(Timestamp.self, forKey: .timestamp) {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(angle, forKey: .angle)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(weekPostOp, forKey: .weekPostOp)
        try container.encode(photoUrl, forKey: .photoUrl)
    }
}

struct Keypoint: Codable {
    var x: CGFloat
    var y: CGFloat
    var confidence: Float
}

struct PoseResult: Codable {
    var hip: Keypoint
    var knee: Keypoint
    var ankle: Keypoint
    var angle: Int
}
