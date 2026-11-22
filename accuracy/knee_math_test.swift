// Unit checks for the Accurate-mode geometry. Run with accuracy/knee_math_test.sh.
// (The app has no unit-test target, so these compile the app's own source files directly.)
import CoreGraphics
import Foundation

var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}
func close(_ a: Double?, _ b: Double, _ tolerance: Double = 0.01) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}
func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }

@main
struct KneeMathTest {
    static func main() {
        let square = CGSize(width: 1000, height: 1000)

        // Flexion convention: straight leg 0, right angle 90, heel to buttock near 180.
        expect(close(KneeAngleMath.flexion(KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.8, 0.5)), imageSize: square), 0), "straight leg is 0")
        expect(close(KneeAngleMath.flexion(KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.5, 0.8)), imageSize: square), 90), "L shape is 90")
        expect(close(KneeAngleMath.flexion(KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.2877, 0.2877)), imageSize: square), 135, 0.1), "45 degrees inside is 135 of flexion")
        expect(close(KneeAngleMath.flexion(KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.2, 0.5)), imageSize: square), 180), "folded leg is 180")

        // The angle does not depend on where the leg is, which way it faces, or how big it is.
        let base = KneeKeypoints(hip: p(0.3, 0.3), knee: p(0.5, 0.5), ankle: p(0.5, 0.8))
        let mirrored = KneeKeypoints(hip: p(0.7, 0.3), knee: p(0.5, 0.5), ankle: p(0.5, 0.8))
        expect(close(KneeAngleMath.flexion(mirrored, imageSize: square), KneeAngleMath.flexion(base, imageSize: square)!), "mirrored photo gives the same angle")

        // A non-square photo must be scaled to pixels first.
        let wide = CGSize(width: 2000, height: 1000)
        let lShapeInPixels = KneeKeypoints(hip: p(0.25, 0.5), knee: p(0.5, 0.5), ankle: p(0.5, 0.9))
        expect(close(KneeAngleMath.flexion(lShapeInPixels, imageSize: wide), 90), "aspect ratio does not distort a right angle")
        let diagonal = KneeKeypoints(hip: p(0.25, 0.5), knee: p(0.5, 0.5), ankle: p(0.75, 1.0))
        expect(close(KneeAngleMath.flexion(diagonal, imageSize: wide), 45), "pixels, not normalized units, define the angle")

        // Degenerate input.
        expect(KneeAngleMath.flexion(KneeKeypoints(hip: p(0.5, 0.5), knee: p(0.5, 0.5), ankle: p(0.5, 0.8)), imageSize: square) == nil, "zero-length thigh has no angle")
        expect(KneeAngleMath.flexion(base, imageSize: .zero) == nil, "empty image has no angle")
        expect(KneeAngleMath.display(89.5) == 90 && KneeAngleMath.display(-3) == 0 && KneeAngleMath.display(200) == 180, "display rounds and clamps")

        // Rotation mapping: a point found in a turned copy lands back where it was.
        let original = p(0.2, 0.7)
        let inClockwise = p(1 - original.y, original.x)         // where it sits after a clockwise quarter turn
        let inCounter = p(original.y, 1 - original.x)
        let backCW = KneeGeometry.unrotate(inClockwise, from: .clockwise)
        let backCCW = KneeGeometry.unrotate(inCounter, from: .counterclockwise)
        expect(abs(backCW.x - 0.2) < 1e-9 && abs(backCW.y - 0.7) < 1e-9, "clockwise maps back")
        expect(abs(backCCW.x - 0.2) < 1e-9 && abs(backCCW.y - 0.7) < 1e-9, "counterclockwise maps back")

        // Leg choice.
        func leg(_ k: KneeKeypoints?, _ confidence: Double) -> KneeSkeleton.Leg {
            KneeSkeleton.Leg(hip: k?.hip, knee: k?.knee, ankle: k?.ankle, confidence: confidence)
        }
        let straight = KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.8, 0.5))
        let bent = KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.5, 0.8))
        let slightlyBent = KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.8, 0.55))

        let heelSlide = KneeSkeleton(left: leg(straight, 0.9), right: leg(bent, 0.4))
        expect(KneeGeometry.chooseLeg(heelSlide, requested: .left, bend: .flexion, imageSize: square) == .right, "flexion measures the clearly bent leg even if the other was requested")
        expect(KneeGeometry.chooseLeg(heelSlide, requested: .right, bend: .extension, imageSize: square) == .left, "extension measures the clearly straighter leg")

        let similar = KneeSkeleton(left: leg(straight, 0.4), right: leg(slightlyBent, 0.9))
        expect(KneeGeometry.chooseLeg(similar, requested: .left, bend: .flexion, imageSize: square) == .left, "similar legs: the requested one")
        expect(KneeGeometry.chooseLeg(similar, requested: nil, bend: .flexion, imageSize: square) == .right, "similar legs, none requested: the more confident one")

        let oneLeg = KneeSkeleton(left: leg(nil, 0), right: leg(bent, 0.5))
        expect(KneeGeometry.chooseLeg(oneLeg, requested: .left, bend: .flexion, imageSize: square) == .right, "only one complete leg: use it")
        let missingAnkle = KneeSkeleton(left: KneeSkeleton.Leg(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: nil, confidence: 0.9), right: leg(nil, 0))
        expect(KneeGeometry.chooseLeg(missingAnkle, requested: .left, bend: .flexion, imageSize: square) == nil, "no complete leg: nothing to measure")
        expect(missingAnkle.bestConfidence == 0, "an incomplete leg has no usable confidence")

        // Turning a real image a quarter turn keeps its size relationship.
        if let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
           let image = context.makeImage() {
            let turned = KneePoseEstimator.rotated(image, .clockwise)
            expect(turned?.width == 20 && turned?.height == 40, "a quarter turn swaps width and height")
        }

        // Which side faces the camera. Pixels, y down.
        let up = CGVector(dx: 0, dy: -1)
        expect(KneeGeometry.sideFacingCamera(up: up, forward: CGVector(dx: 1, dy: 0)) == .right, "standing, facing the right edge: right side to camera")
        expect(KneeGeometry.sideFacingCamera(up: up, forward: CGVector(dx: -1, dy: 0)) == .left, "standing, facing the left edge: left side to camera")
        expect(KneeGeometry.sideFacingCamera(up: CGVector(dx: -1, dy: 0), forward: up) == .right, "on the back, head at the left edge: right side to camera")
        expect(KneeGeometry.sideFacingCamera(up: CGVector(dx: 1, dy: 0), forward: up) == .left, "on the back, head at the right edge: left side to camera")
        expect(KneeGeometry.sideFacingCamera(up: up, forward: CGVector(dx: 0.1, dy: 1)) == nil, "a nose straight below the ears is a front view")
        // Seated facing right: thigh runs right, shin runs down. Mirrored, it faces left.
        let seatedRight = KneeKeypoints(hip: p(0.3, 0.5), knee: p(0.6, 0.5), ankle: p(0.6, 0.8))
        let seatedLeft = KneeKeypoints(hip: p(0.7, 0.5), knee: p(0.4, 0.5), ankle: p(0.4, 0.8))
        expect(KneeGeometry.sideFacingCamera(leg: seatedRight, imageSize: square) == .right, "a knee bent toward the right edge")
        expect(KneeGeometry.sideFacingCamera(leg: seatedLeft, imageSize: square) == .left, "a knee bent toward the left edge")
        expect(KneeGeometry.sideFacingCamera(leg: KneeKeypoints(hip: p(0.2, 0.5), knee: p(0.5, 0.5), ankle: p(0.8, 0.5)), imageSize: square) == nil, "a straight leg says nothing")
        expect(KneeGeometry.sideFacingCamera(head: .right, headInView: true, legs: [.right, nil]) == .right, "head and knee agree")
        expect(KneeGeometry.sideFacingCamera(head: .right, headInView: true, legs: [.left, nil]) == nil, "head and knee disagree")
        expect(KneeGeometry.sideFacingCamera(head: nil, headInView: false, legs: [.left, nil]) == .left, "face hidden: the bent knee decides")
        expect(KneeGeometry.sideFacingCamera(head: nil, headInView: true, legs: [.left, nil]) == nil, "front view: a raised knee is not trusted")
        expect(KneeGeometry.sideFit(requested: nil, facing: .left) == .notAsked, "no saved side, nothing to compare")
        expect(KneeGeometry.sideFit(requested: .left, facing: .left) == .matches, "saved side faces the camera")
        expect(KneeGeometry.sideFit(requested: .left, facing: .right) == .opposite(facing: .right), "other side faces the camera")
        expect(KneeGeometry.sideFit(requested: .left, facing: nil) == .unknown, "side can't be told")

        print(failures == 0 ? "knee math: all checks passed" : "knee math: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
