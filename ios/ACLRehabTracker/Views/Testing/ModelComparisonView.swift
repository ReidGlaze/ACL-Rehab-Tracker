#if ACL_MODEL_TEST
import SwiftUI
import UIKit

/// Compiled only into the separate development app. No Firestore or Storage writes.
struct ModelComparisonView: View {
    @StateObject private var auth = AuthService.shared
    @State private var image: UIImage?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var consented = false
    @State private var busy = false
    @State private var message: String?
    @State private var knee: KneeSide = .right
    @State private var injury: InjuryType = .aclOnly
    @State private var reference = ""
    @State private var trials: [Trial] = []
    @State private var photoID = UUID().uuidString

    struct Trial: Identifiable {
        let id = UUID()
        let photoID: String
        let model: String
        let angle: Int?
        let seconds: Double
        let reference: Double?
        let error: String?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Compare the same photo")
                        .font(.title2.bold())
                    Text("Results stay in this test session. Nothing is saved to your rehabilitation history.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 230).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Button("Photo Library", systemImage: "photo") { showLibrary = true }
                        Spacer()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Camera", systemImage: "camera") { showCamera = true }
                        }
                    }.buttonStyle(.bordered).disabled(busy)
                    Picker("Injured knee", selection: $knee) {
                        ForEach(KneeSide.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.segmented).disabled(busy)
                    Picker("Injury", selection: $injury) {
                        ForEach(InjuryType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.disabled(busy)
                    TextField("Verified reference angle (optional)", text: $reference)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).disabled(busy)
                    Toggle("I agree to send this photo and injury context to Google Vertex AI for Claude/Gemini analysis.", isOn: $consented)
                        .font(.footnote).disabled(busy)
                    Text("0° = straight. Use an independently verified angle to judge accuracy; model agreement alone is not validation.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Opus only") { start(["analyzeKneeAngle"]) }
                        Button("Gemini only") { start(["analyzeKneeAngleGeminiTest"]) }
                    }.buttonStyle(.bordered).disabled(!canAnalyze)
                    Button { start(["analyzeKneeAngle", "analyzeKneeAngleGeminiTest"]) } label: {
                        Label("Compare both models", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(!canAnalyze)
                    if busy { ProgressView("Analyzing… each model may take up to two minutes.") }
                    if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                    ForEach(trials.reversed()) { trial in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(trial.model).font(.headline)
                                Spacer()
                                if let angle = trial.angle { Text("\(angle)°").font(.title2.bold()) }
                            }
                            Text(String(format: "%.1f seconds", trial.seconds)).font(.caption).foregroundStyle(.secondary)
                            if let angle = trial.angle, let expected = trial.reference {
                                Text(String(format: "Reference %.1f° · absolute error %.1f°", expected, abs(Double(angle) - expected)))
                                    .font(.subheadline)
                            }
                            if let error = trial.error { Text(error).font(.footnote).foregroundStyle(.red) }
                        }.padding().background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !trials.isEmpty {
                        ShareLink("Share session results", item: report)
                        Button("Clear results", role: .destructive) { trials = [] }.disabled(busy)
                    }
                    Divider()
                    Text("Tester UID").font(.caption.bold())
                    Text(auth.currentUserId ?? "Signing in…").font(.caption.monospaced()).textSelection(.enabled)
                    Button("Copy tester UID") { UIPasteboard.general.string = auth.currentUserId }
                        .font(.caption)
                }.padding()
            }
            .background(Color(red: 0.05, green: 0.06, blue: 0.08))
            .navigationTitle("ACL Rehab Test")
            .sheet(isPresented: $showLibrary) { ImagePickerView { setImage($0) } }
            .sheet(isPresented: $showCamera) { TestCameraPicker { setImage($0) }.ignoresSafeArea() }
            .task {
                do {
                    if !auth.isSignedIn { _ = try await auth.signInAnonymously() }
                    if let uid = auth.currentUserId { print("ACL_MODEL_TEST_UID=\(uid)") }
                } catch { message = "Test sign-in failed: \(error.localizedDescription)" }
            }
        }
    }

    private var canAnalyze: Bool { image != nil && consented && !busy && auth.isSignedIn }
    private func setImage(_ image: UIImage) {
        self.image = image
        photoID = UUID().uuidString
        reference = ""
        message = nil
    }

    private func start(_ functions: [String]) {
        guard let image, canAnalyze else { return }
        let expected = Double(reference.replacingOccurrences(of: ",", with: "."))
        if !reference.isEmpty && (expected == nil || !(0...180).contains(expected ?? -1)) {
            message = "Enter a reference angle between 0° and 180°, or leave it blank."
            return
        }
        busy = true
        message = nil
        let selectedPhotoID = photoID
        let selectedKnee = knee
        let selectedInjury = injury
        Task { @MainActor in
            defer { busy = false }
            for function in functions {
                let model = function == "analyzeKneeAngle" ? "Opus 4.6 (production)" : "Gemini 3.8 Flash (test)"
                let started = Date()
                do {
                    let result = try await GeminiPoseService.shared.detectKneeAngle(
                        image: image, injuredKnee: selectedKnee, injuryType: selectedInjury, functionName: function)
                    trials.append(Trial(photoID: selectedPhotoID, model: model, angle: result.angle,
                                        seconds: Date().timeIntervalSince(started), reference: expected, error: nil))
                } catch {
                    trials.append(Trial(photoID: selectedPhotoID, model: model, angle: nil,
                                        seconds: Date().timeIntervalSince(started), reference: expected, error: error.localizedDescription))
                }
            }
        }
    }

    private var report: String {
        let header = "photo_id,model,angle_degrees,seconds,reference_degrees,absolute_error_degrees,status"
        return ([header] + trials.map { trial in
            let angle = trial.angle.map(String.init) ?? ""
            let expected = trial.reference.map { String($0) } ?? ""
            let error = trial.angle.flatMap { angle in trial.reference.map { String(abs(Double(angle) - $0)) } } ?? ""
            return "\(trial.photoID),\(trial.model),\(angle),\(String(format: "%.2f", trial.seconds)),\(expected),\(error),\(trial.error == nil ? "success" : "failed")"
        }).joined(separator: "\n")
    }
}

private struct TestCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: TestCameraPicker
        init(_ parent: TestCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif
