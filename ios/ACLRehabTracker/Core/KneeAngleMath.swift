import CoreGraphics
import Foundation

/// A point in normalized image coordinates: (0,0) is the top-left corner, (1,1) the bottom-right.
struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    var clamped: NormalizedPoint {
        NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    func toPixels(in size: CGSize) -> CGPoint {
        CGPoint(x: x * Double(size.width), y: y * Double(size.height))
    }
}

/// The three points that define a knee angle: thigh runs hip to knee, shin runs knee to ankle.
struct KneeKeypoints: Codable, Hashable, Sendable {
    var hip: NormalizedPoint
    var knee: NormalizedPoint
    var ankle: NormalizedPoint
}

/// Which movement the user is measuring. Mirrors `MeasurementType` without depending on it,
/// so this file can be compiled on its own by the accuracy harness.
enum KneeBend: String, Sendable {
    case flexion
    case `extension`
}

enum KneeLeg: String, CaseIterable, Sendable {
    case left
    case right

    var opposite: KneeLeg { self == .left ? .right : .left }
}

enum KneeAngleMath {
    /// Angle at `vertex` between the rays to `a` and `b`, in degrees (0...180).
    /// Nil when either ray has no length.
    static func angle(at vertex: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double? {
        let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let len1 = hypot(v1.dx, v1.dy)
        let len2 = hypot(v2.dx, v2.dy)
        guard len1 > 1e-9, len2 > 1e-9 else { return nil }
        let cosine = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2)
        return acos(min(max(Double(cosine), -1), 1)) * 180 / .pi
    }

    /// Knee flexion the way the app has always reported it: a straight leg is 0 degrees and a
    /// right-angle bend is 90. That is 180 minus the angle between thigh and shin at the knee.
    ///
    /// Normalized points are scaled to pixels first; otherwise a non-square photo distorts the angle.
    static func flexion(_ points: KneeKeypoints, imageSize: CGSize) -> Double? {
        guard imageSize.width > 0, imageSize.height > 0,
              let inner = angle(
                at: points.knee.toPixels(in: imageSize),
                points.hip.toPixels(in: imageSize),
                points.ankle.toPixels(in: imageSize)
              ) else { return nil }
        return 180 - inner
    }

    /// Whole degrees, the precision the app stores and shows.
    static func display(_ degrees: Double) -> Int {
        max(0, min(180, Int(degrees.rounded())))
    }
}
