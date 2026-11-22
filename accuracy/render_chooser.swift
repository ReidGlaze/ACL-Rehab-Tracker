// Renders the Accurate-mode chooser and the Measure-tab method row to PNG on this Mac, using the
// app's own SwiftUI views. A stand-in for simulator screenshots when a simulator is not available;
// fonts and spacing are the app's, system chrome (sheet, status bar) is not drawn.
//
//   accuracy/render_chooser.sh <outDir>
import AppKit
import SwiftUI

/// The app's type lives in Measurement.swift, which needs Firebase. Only what the views use.
enum MeasurementType: String, CaseIterable {
    case `extension`
    case flexion
}

@MainActor
func save<V: View>(_ view: V, width: CGFloat, to path: String) {
    let content = view
        .buttonStyle(.plain)
        .frame(width: width)
        .background(AppColors.background)
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 3
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("could not render \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

@main
struct RenderChooser {
    @MainActor
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for mode in MeasureMode.allCases {
            save(MeasureModeChooser(selection: .constant(mode)).padding(AppSpacing.lg),
                 width: 393, to: "\(out)/chooser-\(mode.rawValue)-selected.png")
            save(VStack(spacing: AppSpacing.sm) {
                    MeasureModeRow(mode: mode) {}
                    Text(mode.instruction(for: .flexion))
                        .font(AppTypography.subhead)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                 }.padding(AppSpacing.lg),
                 width: 393, to: "\(out)/measure-row-\(mode.rawValue).png")
        }
    }
}
