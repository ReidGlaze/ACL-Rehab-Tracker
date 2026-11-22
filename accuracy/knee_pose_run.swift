// Runs the app's own KneePoseEstimator over labelled photos on this Mac.
// Build and run with accuracy/knee_pose_run.sh.
//
//   knee_pose_run <fixturesDir> <out.json>
//
// File names: <flexion|extension>_<trueAngle|x>_<anything>.jpg. The true angle is knee flexion in
// degrees (straight leg = 0). Use x when it is unknown.
import CoreGraphics
import Foundation
import ImageIO

@main
struct KneePoseRun {
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: knee_pose_run <fixturesDir> <out.json>")
            return
        }
        let dir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
        if let i = args.firstIndex(of: "--good-enough"), i + 1 < args.count, let value = Double(args[i + 1]) {
            KneePoseEstimator.goodEnoughConfidence = value
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.range(of: #"^(flexion|extension)_(\d+|x)_.*\.(jpe?g|png)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
            .sorted()

        var rows: [[String: Any]] = []
        for file in files {
            let parts = file.split(separator: "_").map(String.init)
            guard let bend = KneeBend(rawValue: parts[0]), let image = load(dir.appendingPathComponent(file)) else { continue }
            var row: [String: Any] = ["file": file, "bend": parts[0], "truth": Int(parts[1]) as Any? ?? NSNull(), "found": false]
            let started = Date()
            if let e = KneePoseEstimator.estimate(image: image, bend: bend, requested: nil, include3D: true) {
                let size = CGSize(width: image.width, height: image.height)
                let json = { (p: NormalizedPoint) in ["x": p.x, "y": p.y] }
                row["found"] = true
                row["hip"] = json(e.keypoints.hip); row["knee"] = json(e.keypoints.knee); row["ankle"] = json(e.keypoints.ankle)
                row["angle"] = KneeAngleMath.flexion(e.keypoints, imageSize: size) ?? NSNull()
                row["angle3D"] = e.flexion3D ?? NSNull()
                row["leg"] = e.measuredLeg.rawValue
                row["facing"] = e.sideFacingCamera?.rawValue ?? "unknown"
                row["confidence"] = e.confidence
            }
            row["ms"] = Int(Date().timeIntervalSince(started) * 1000)
            rows.append(row)
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: out)
        print("photos: \(rows.count), found: \(rows.filter { $0["found"] as? Bool == true }.count)")
    }
}
