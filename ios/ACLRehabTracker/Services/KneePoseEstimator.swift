import CoreGraphics
import Foundation
import simd
import Vision

/// The joints of both legs as Vision reported them, normalized with a top-left origin.
struct KneeSkeleton: Sendable {
    struct Leg: Sendable {
        var hip: NormalizedPoint?
        var knee: NormalizedPoint?
        var ankle: NormalizedPoint?
        /// Lowest confidence of the three joints, 0...1.
        var confidence: Double = 0

        var keypoints: KneeKeypoints? {
            guard let hip, let knee, let ankle else { return nil }
            return KneeKeypoints(hip: hip, knee: knee, ankle: ankle)
        }
    }

    var left = Leg()
    var right = Leg()
    /// Which side of the body is toward the camera, when the photo is clearly a side view.
    var sideFacingCamera: KneeLeg?

    func leg(_ side: KneeLeg) -> Leg { side == .left ? left : right }

    /// Confidence of the better complete leg, or 0 when neither leg is complete.
    var bestConfidence: Double {
        KneeLeg.allCases.compactMap { leg($0).keypoints == nil ? nil : leg($0).confidence }.max() ?? 0
    }
}

struct KneePoseEstimate: Sendable {
    var keypoints: KneeKeypoints
    /// The leg the points are on. Usually the requested one; see `KneeGeometry.chooseLeg`.
    var measuredLeg: KneeLeg
    /// Lowest joint confidence of the measured leg, 0...1.
    var confidence: Double
    /// Which side of the body is toward the camera. Nil when it can't be told (a front view, or
    /// the head and the knees disagree).
    var sideFacingCamera: KneeLeg?
    /// Angle from Vision's 3D body model, when it ran. Recorded for the accuracy harness only;
    /// the app shows the angle of the drawn points.
    var flexion3D: Double?
}

/// Pure geometry, kept apart from Vision so it can be unit tested.
enum KneeGeometry {
    /// How much more bent (or straighter) one leg must be before it overrides the requested leg.
    static let clearlyDifferentMargin = 20.0

    /// Picks the leg to measure. In a side view Vision often swaps left and right, and in most
    /// rehab photos only one leg is doing the movement. So when the two legs clearly differ, the
    /// one doing the movement wins: the more bent leg for flexion, the straighter one for
    /// extension. Otherwise the requested leg, then the one Vision is surer of.
    static func chooseLeg(_ skeleton: KneeSkeleton, requested: KneeLeg?, bend: KneeBend, imageSize: CGSize) -> KneeLeg? {
        let usable = KneeLeg.allCases.filter { skeleton.leg($0).keypoints != nil }
        guard let first = usable.first else { return nil }
        guard usable.count == 2 else { return first }

        func flexion(_ side: KneeLeg) -> Double? {
            skeleton.leg(side).keypoints.flatMap { KneeAngleMath.flexion($0, imageSize: imageSize) }
        }
        if let left = flexion(.left), let right = flexion(.right), abs(left - right) >= clearlyDifferentMargin {
            let moreBent: KneeLeg = left > right ? .left : .right
            return bend == .flexion ? moreBent : moreBent.opposite
        }
        if let requested { return requested }
        return skeleton.left.confidence >= skeleton.right.confidence ? .left : .right
    }

    /// How far sideways (as a share of its own length) a "forward" clue must point before it counts.
    static let minimumSideways = 0.35
    /// Shoulders this far apart, as a share of the torso's length, mean the camera is looking at
    /// the front or back of the body rather than its side. Square-on is about 0.8; a profile near 0.
    static let maximumShoulderSpreadForSideView = 0.45
    /// A knee has to be bent at least this much before its direction says which way the body faces.
    static let minimumBendForFacing = 25.0

    /// Which side of the body is toward the camera, from one clue: a direction that runs up the
    /// body and a direction that points to the body's front. Points are in pixels, y down.
    /// Someone standing and facing the right edge of the photo shows the camera their right side;
    /// so does someone lying on their back with their head at the left edge.
    static func sideFacingCamera(up: CGVector, forward: CGVector) -> KneeLeg? {
        let lu = hypot(up.dx, up.dy), lf = hypot(forward.dx, forward.dy)
        guard lu > 1e-6, lf > 1e-6 else { return nil }
        let cross = Double((up.dx * forward.dy - up.dy * forward.dx) / (lu * lf))
        guard abs(cross) >= minimumSideways else { return nil }
        return cross > 0 ? .right : .left
    }

    /// The same question asked of one leg: a knee only bends forward, so a bent knee points to the
    /// body's front. Nil for a leg that is nearly straight.
    static func sideFacingCamera(leg: KneeKeypoints, imageSize: CGSize) -> KneeLeg? {
        guard let bend = KneeAngleMath.flexion(leg, imageSize: imageSize), bend >= minimumBendForFacing else { return nil }
        let hip = leg.hip.toPixels(in: imageSize), knee = leg.knee.toPixels(in: imageSize), ankle = leg.ankle.toPixels(in: imageSize)
        let mid = CGPoint(x: (hip.x + ankle.x) / 2, y: (hip.y + ankle.y) / 2)
        return sideFacingCamera(up: CGVector(dx: hip.x - ankle.x, dy: hip.y - ankle.y),
                                forward: CGVector(dx: knee.x - mid.x, dy: knee.y - mid.y))
    }

    /// Combines the head's answer with the bent knees'. Any disagreement means "can't tell", and so
    /// does a face that is in view but not in profile: that is a front or back view, where a
    /// raised knee would otherwise look like a sideways one.
    static func sideFacingCamera(head: KneeLeg?, headInView: Bool, legs: [KneeLeg?]) -> KneeLeg? {
        if headInView, head == nil { return nil }
        let votes = ([head] + legs).compactMap { $0 }
        guard let first = votes.first, votes.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// How the side the user is rehabbing compares with the side the camera can see.
    enum SideFit: Equatable, Sendable {
        /// No side is saved in the profile, so there is nothing to compare.
        case notAsked
        case matches
        /// The other side of the body is toward the camera.
        case opposite(facing: KneeLeg)
        case unknown
    }

    static func sideFit(requested: KneeLeg?, facing: KneeLeg?) -> SideFit {
        guard let requested else { return .notAsked }
        guard let facing else { return .unknown }
        return facing == requested ? .matches : .opposite(facing: facing)
    }

    static func flexion3D(hip: SIMD3<Float>, knee: SIMD3<Float>, ankle: SIMD3<Float>) -> Double? {
        let a = hip - knee, b = ankle - knee
        let la = simd_length(a), lb = simd_length(b)
        guard la > 1e-5, lb > 1e-5 else { return nil }
        let inner = Double(acos(min(max(simd_dot(a, b) / (la * lb), -1), 1))) * 180 / .pi
        return 180 - inner
    }

    /// Maps a point found in a rotated copy of the photo back onto the original photo.
    static func unrotate(_ p: NormalizedPoint, from rotation: KneePoseEstimator.Rotation) -> NormalizedPoint {
        switch rotation {
        case .none: return p
        case .clockwise: return NormalizedPoint(x: p.y, y: 1 - p.x)
        case .counterclockwise: return NormalizedPoint(x: 1 - p.y, y: p.x)
        }
    }
}

/// On-device body pose with Apple's Vision framework. Nothing leaves the phone.
enum KneePoseEstimator {
    private typealias Joint2D = VNHumanBodyPoseObservation.JointName
    private typealias Joint3D = VNHumanBodyPose3DObservation.JointName

    /// How the photo was turned before detection. People doing heel slides are lying down, and
    /// Vision finds a body far more reliably when it is upright in the picture.
    enum Rotation: CaseIterable, Sendable {
        case none
        case clockwise
        case counterclockwise
    }

    static let minimumJointConfidence: Float = 0.1
    /// An upright result at or above this is used as it is; below it the turned copies are tried too.
    /// Always trying all three scored slightly worse on the accuracy set (median 5.2 vs 4.7 degrees).
    /// A `var` only so the accuracy harness can compare settings.
    static var goodEnoughConfidence = 0.5

    /// Blocking; call off the main thread. `image` must already be upright (EXIF applied).
    static func estimate(image: CGImage, bend: KneeBend, requested: KneeLeg?, include3D: Bool = false) -> KneePoseEstimate? {
        let size = CGSize(width: image.width, height: image.height)

        var best: (skeleton: KneeSkeleton, rotation: Rotation)?
        for rotation in Rotation.allCases {
            guard let turned = rotated(image, rotation), let found = skeleton(in: turned) else { continue }
            let mapped = unrotate(found, from: rotation)
            if mapped.bestConfidence > (best?.skeleton.bestConfidence ?? 0) {
                best = (mapped, rotation)
            }
            if rotation == .none, mapped.bestConfidence >= goodEnoughConfidence { break }
        }

        guard let best,
              let leg = KneeGeometry.chooseLeg(best.skeleton, requested: requested, bend: bend, imageSize: size),
              let points = best.skeleton.leg(leg).keypoints else { return nil }

        return KneePoseEstimate(
            keypoints: KneeKeypoints(hip: points.hip.clamped, knee: points.knee.clamped, ankle: points.ankle.clamped),
            measuredLeg: leg,
            confidence: best.skeleton.leg(leg).confidence,
            sideFacingCamera: best.skeleton.sideFacingCamera,
            flexion3D: include3D ? rotated(image, best.rotation).flatMap { flexion3D(in: $0, leg: leg) } : nil
        )
    }

    // MARK: - Vision

    private static func skeleton(in image: CGImage) -> KneeSkeleton? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("KneePoseEstimator: body pose request failed: \(error)")
            #endif
            return nil
        }

        // With several people in the photo, measure the one who takes up the most of it.
        let bodies = (request.results ?? []).compactMap { observation -> (points: [Joint2D: VNRecognizedPoint], span: CGFloat)? in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let confident = points.values.filter { $0.confidence > minimumJointConfidence }
            guard !confident.isEmpty else { return nil }
            let xs = confident.map(\.location.x), ys = confident.map(\.location.y)
            return (points, max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0)))
        }
        guard let body = bodies.max(by: { $0.span < $1.span }) else { return nil }

        func leg(_ hip: Joint2D, _ knee: Joint2D, _ ankle: Joint2D) -> KneeSkeleton.Leg {
            func point(_ name: Joint2D) -> NormalizedPoint? {
                guard let q = body.points[name], q.confidence > minimumJointConfidence else { return nil }
                return NormalizedPoint(x: Double(q.location.x), y: 1 - Double(q.location.y))
            }
            let confidence = [hip, knee, ankle].map { Double(body.points[$0]?.confidence ?? 0) }.min() ?? 0
            return KneeSkeleton.Leg(hip: point(hip), knee: point(knee), ankle: point(ankle), confidence: confidence)
        }
        var skeleton = KneeSkeleton(
            left: leg(.leftHip, .leftKnee, .leftAnkle),
            right: leg(.rightHip, .rightKnee, .rightAnkle)
        )

        // Which side faces the camera. Worked out here, in the turned copy, because a quarter turn
        // does not change the answer but a mirror image would.
        let size = CGSize(width: image.width, height: image.height)
        func pixels(_ names: [Joint2D]) -> CGPoint? {
            let found = names.compactMap { name -> CGPoint? in
                guard let q = body.points[name], q.confidence > minimumJointConfidence else { return nil }
                return CGPoint(x: q.location.x * size.width, y: (1 - q.location.y) * size.height)
            }
            guard !found.isEmpty else { return nil }
            return CGPoint(x: found.map(\.x).reduce(0, +) / CGFloat(found.count),
                           y: found.map(\.y).reduce(0, +) / CGFloat(found.count))
        }
        var head: KneeLeg?
        var headInView = false
        if let top = pixels([.neck]) ?? pixels([.leftShoulder, .rightShoulder]),
           let bottom = pixels([.root]) ?? pixels([.leftHip, .rightHip]),
           let nose = pixels([.nose]), let ears = pixels([.leftEar, .rightEar]) {
            headInView = true
            head = KneeGeometry.sideFacingCamera(
                up: CGVector(dx: top.x - bottom.x, dy: top.y - bottom.y),
                forward: CGVector(dx: nose.x - ears.x, dy: nose.y - ears.y))
        }
        // Shoulders wide apart: a front or back view, whatever the head and knees suggest.
        if let top = pixels([.neck]) ?? pixels([.leftShoulder, .rightShoulder]),
           let bottom = pixels([.root]) ?? pixels([.leftHip, .rightHip]),
           let l = pixels([.leftShoulder]), let r = pixels([.rightShoulder]) {
            let torso = hypot(top.x - bottom.x, top.y - bottom.y)
            if torso > 1, Double(hypot(l.x - r.x, l.y - r.y) / torso) >= KneeGeometry.maximumShoulderSpreadForSideView {
                headInView = true
                head = nil
            }
        }
        skeleton.sideFacingCamera = KneeGeometry.sideFacingCamera(
            head: head, headInView: headInView,
            legs: [skeleton.left, skeleton.right].map { $0.keypoints.flatMap { KneeGeometry.sideFacingCamera(leg: $0, imageSize: size) } }
        )
        return skeleton
    }

    private static func flexion3D(in image: CGImage, leg: KneeLeg) -> Double? {
        let request = VNDetectHumanBodyPose3DRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil, let body = request.results?.first else { return nil }
        func position(_ name: Joint3D) -> SIMD3<Float>? {
            guard let c = (try? body.recognizedPoint(name))?.position.columns.3 else { return nil }
            return SIMD3(c.x, c.y, c.z)
        }
        let names: (Joint3D, Joint3D, Joint3D) = leg == .left
            ? (.leftHip, .leftKnee, .leftAnkle) : (.rightHip, .rightKnee, .rightAnkle)
        guard let hip = position(names.0), let knee = position(names.1), let ankle = position(names.2) else { return nil }
        return KneeGeometry.flexion3D(hip: hip, knee: knee, ankle: ankle)
    }

    // MARK: - Rotation

    private static func unrotate(_ skeleton: KneeSkeleton, from rotation: Rotation) -> KneeSkeleton {
        func leg(_ l: KneeSkeleton.Leg) -> KneeSkeleton.Leg {
            KneeSkeleton.Leg(
                hip: l.hip.map { KneeGeometry.unrotate($0, from: rotation) },
                knee: l.knee.map { KneeGeometry.unrotate($0, from: rotation) },
                ankle: l.ankle.map { KneeGeometry.unrotate($0, from: rotation) },
                confidence: l.confidence
            )
        }
        return KneeSkeleton(left: leg(skeleton.left), right: leg(skeleton.right), sideFacingCamera: skeleton.sideFacingCamera)
    }

    /// A copy of the image turned a quarter turn. `.clockwise` puts the original's left edge on top.
    static func rotated(_ image: CGImage, _ rotation: Rotation) -> CGImage? {
        guard rotation != .none else { return image }
        let w = image.width, h = image.height
        guard let context = CGContext(
            data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // Core Graphics has a bottom-left origin, so a positive angle turns counterclockwise.
        if rotation == .clockwise {
            context.translateBy(x: 0, y: CGFloat(w))
            context.rotate(by: -.pi / 2)
        } else {
            context.translateBy(x: CGFloat(h), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
