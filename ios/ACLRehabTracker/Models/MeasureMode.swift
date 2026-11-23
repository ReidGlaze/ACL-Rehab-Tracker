import Foundation

/// How the Measure tab turns a photo into an angle. Stored on the device only.
/// The default is the original method, so nothing changes for anyone who never opens the picker.
enum MeasureMode: String, CaseIterable, Identifiable {
    case standard
    case accurate

    /// `@AppStorage` key. A missing value means `.standard`.
    static let storageKey = "measureMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard photo"
        case .accurate: return "Whole-body mode"
        }
    }

    /// Whole-body mode is new and still being tuned, so its name carries a small "Beta" tag.
    var isBeta: Bool { self == .accurate }

    /// The name as VoiceOver should read it.
    var spokenTitle: String { isBeta ? "\(title), beta" : title }

    var icon: String {
        switch self {
        case .standard: return "camera"
        case .accurate: return "figure.stand"
        }
    }

    /// One line under the title in the picker.
    var summary: String {
        switch self {
        case .standard:
            return "Take a photo of your knee from the side. AI estimates the angle. About 15 seconds."
        case .accurate:
            return "Get your whole body in the photo. Your phone finds your hip, knee and ankle and measures between them."
        }
    }

    /// Shown on the Measure tab above the shutter.
    func instruction(for type: MeasurementType) -> String {
        switch (self, type) {
        case (.standard, .extension):
            return "Straighten your leg as much as possible and capture from the side"
        case (.standard, .flexion):
            return "Bend your knee as much as possible and capture from the side"
        case (.accurate, .extension):
            return "Step back until your whole body is in the photo, side-on. Then straighten your leg as much as possible"
        case (.accurate, .flexion):
            return "Step back until your whole body is in the photo, side-on. Then bend your knee as much as possible"
        }
    }
}
