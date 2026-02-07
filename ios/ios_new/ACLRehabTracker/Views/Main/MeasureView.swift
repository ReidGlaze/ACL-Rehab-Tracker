import SwiftUI
import PhotosUI
import UIKit
import StoreKit

enum MeasureScreenState {
    case camera
    case processing
    case result
    case saving
}

struct MeasureView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var authService = AuthService.shared
    @Environment(\.requestReview) private var requestReview

    @State private var measurementType: MeasurementType = .extension
    @State private var screenState: MeasureScreenState = .camera
    @State private var isCameraLoading = true
    @State private var poseResult: PoseResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPhotoPicker = false
    @State private var userProfile: UserProfile?
    @State private var showSuccessBanner = false
    @AppStorage("measurementSaveCount") private var saveCount = 0
    @AppStorage("lastReviewPromptDate") private var lastReviewPromptDateInterval: Double = 0

    var body: some View {
        Group {
            switch screenState {
            case .camera, .processing:
                cameraView
            case .result, .saving:
                resultView
            }
        }
        .overlay(alignment: .top) {
            if showSuccessBanner {
                Text("Measurement saved!")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.success.opacity(0.9))
                    .cornerRadius(AppRadius.md)
                    .padding(.top, AppSpacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: showSuccessBanner)
            }
        }
        .background(AppColors.background)
        .task {
            await setupCamera()
            await loadUserProfile()
        }
        .onDisappear {
            cameraService.stopCamera()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showPhotoPicker) {
            ImagePickerView { image in
                handleSelectedPhoto(image)
            }
        }
    }

    // MARK: - Camera View
    private var cameraView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Measure")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)

            // Type Toggle
            typeToggle
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            // Camera Preview
            cameraPreview
                .padding(.horizontal, AppSpacing.lg)

            // Instructions
            Text(measurementType == .extension
                 ? "Straighten your leg as much as possible and capture from the side"
                 : "Bend your knee as much as possible and capture from the side")
                .font(AppTypography.subhead)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

            // Bottom controls: Library | Capture | Flip Camera
            cameraControls
                .opacity(screenState == .processing ? 0.4 : 1.0)
                .disabled(screenState == .processing)
                .padding(.bottom, AppSpacing.xl)
        }
    }

    private var cameraControls: some View {
        HStack {
            // Photo Library picker (left)
            Button(action: { showPhotoPicker = true }) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(AppColors.text)
                    .frame(width: 48, height: 48)
                    .background(AppColors.surface)
                    .cornerRadius(AppRadius.md)
            }
            .accessibilityLabel("Pick from library")

            Spacer()

            // Capture button (center)
            Button(action: handleCapture) {
                ZStack {
                    Circle()
                        .stroke(AppColors.text, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.text))
                    } else {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            .disabled(isProcessing || (!cameraService.isCameraReady && isCameraLoading))
            .opacity((isProcessing || (!cameraService.isCameraReady && isCameraLoading)) ? 0.4 : 1.0)

            Spacer()

            // Flip camera (right)
            Button(action: { cameraService.flipCamera() }) {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(AppColors.text)
                    .frame(width: 48, height: 48)
                    .background(AppColors.surface)
                    .cornerRadius(AppRadius.md)
            }
            .accessibilityLabel("Switch camera")
            .opacity(cameraService.isCameraReady ? 1.0 : 0.4)
            .disabled(!cameraService.isCameraReady)
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private var typeToggle: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(MeasurementType.allCases, id: \.self) { type in
                Button(action: { measurementType = type }) {
                    Text(type.displayName)
                        .font(AppTypography.headline)
                        .foregroundColor(measurementType == type ? AppColors.text : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(measurementType == type ? AppColors.primary : Color.clear)
                        .cornerRadius(AppRadius.md)
                }
            }
        }
        .padding(AppSpacing.xs)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    private var cameraPreview: some View {
        ZStack {
            if cameraService.isCameraReady, let session = cameraService.session {
                CameraPreview(session: session)

                // Processing overlay on top of camera
                if screenState == .processing {
                    if let image = cameraService.capturedImage {
                        Color.clear.overlay(
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .clipped()
                    }

                    // Dark overlay
                    Color.black.opacity(0.6)

                    // Spinner + text
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Analyzing...")
                            .font(AppTypography.headline)
                            .foregroundColor(.white)
                    }
                }
            } else if isCameraLoading {
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.textSecondary))
                        .scaleEffect(1.5)
                    Text("Starting camera...")
                        .font(AppTypography.subhead)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.surface)
            } else {
                // Camera genuinely not available (simulator)
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true)

                    Text("Camera not available")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.text)

                    Text("Use photo library instead")
                        .font(AppTypography.subhead)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.surface)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3/4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }


    // MARK: - Result View
    private var resultView: some View {
        VStack(spacing: AppSpacing.lg) {
            // Header
            Text("\(measurementType.displayName) Result")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)

            // Photo Preview
            photoPreview
                .padding(.horizontal, AppSpacing.lg)

            // Angle Display
            angleDisplay
                .padding(.horizontal, AppSpacing.lg)

            // Action Buttons
            actionButtons
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
        }
    }

    private var photoPreview: some View {
        Group {
            if let image = cameraService.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(AppRadius.lg)
            } else {
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(AppColors.surface)
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay(
                        Text("Photo Preview")
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.textSecondary)
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var angleDisplay: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("MEASURED ANGLE")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
                .tracking(1)

            Text("\(poseResult?.angle ?? 0)\u{00B0}")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(AppColors.text)

            Text("Goal: \(measurementType.goalAngle)\u{00B0}")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textTertiary)

            // Disclaimer
            Text("For personal tracking only. Not for medical diagnosis.")
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, AppSpacing.sm)
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.md) {
            Button(action: handleRetake) {
                Text("Retake")
            }
            .buttonStyle(SecondaryButtonStyle(isEnabled: screenState != .saving))
            .disabled(screenState == .saving)

            Button(action: handleSave) {
                if screenState == .saving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.text))
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: screenState != .saving))
            .disabled(screenState == .saving)
        }
    }

    // MARK: - Actions
    private func setupCamera() async {
        if !cameraService.isAuthorized {
            _ = await cameraService.requestPermission()
        }

        if cameraService.isAuthorized {
            do {
                try await cameraService.setupCamera()
            } catch {
                print("Camera setup failed: \(error.localizedDescription)")
            }
        }
        isCameraLoading = false
    }

    private func loadUserProfile() async {
        guard let uid = authService.currentUserId else { return }

        do {
            userProfile = try await FirestoreService.shared.getUserProfile(uid: uid)
        } catch {
            print("Failed to load user profile: \(error)")
        }
    }

    private func handleCapture() {
        // Show processing state immediately so user knows photo was taken
        screenState = .processing

        Task {
            do {
                // Capture the actual photo (capturedImage set by delegate)
                let imagePath = try await cameraService.capturePhoto()

                // Send image directly to Gemini for angle analysis with injury info
                let detectedPose = try await GeminiPoseService.shared.detectKneeAngle(
                    imagePath: imagePath,
                    injuredKnee: userProfile?.injuredKnee,
                    injuryType: userProfile?.injuryType
                )
                await MainActor.run {
                    poseResult = detectedPose
                    screenState = .result
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    screenState = .camera
                }
            }
        }
    }

    private func handleSelectedPhoto(_ image: UIImage) {
        // Show processing spinner immediately
        screenState = .processing

        Task {
            do {
                // Save image to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "photo_\(UUID().uuidString).jpg"
                let fileURL = tempDir.appendingPathComponent(fileName)

                guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
                    throw NSError(domain: "MeasureView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image"])
                }
                try jpegData.write(to: fileURL)

                // Update image
                await MainActor.run {
                    cameraService.capturedImage = image
                    cameraService.capturedImagePath = fileURL.path
                }

                // Analyze image with Gemini
                let detectedPose = try await GeminiPoseService.shared.detectKneeAngle(
                    imagePath: fileURL.path,
                    injuredKnee: userProfile?.injuredKnee,
                    injuryType: userProfile?.injuryType
                )

                await MainActor.run {
                    poseResult = detectedPose
                    screenState = .result
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    screenState = .camera
                }
            }
        }
    }

    private func handleRetake() {
        poseResult = nil
        cameraService.capturedImage = nil
        cameraService.capturedImagePath = nil
        screenState = .camera
    }

    private func checkAndRequestReview() {
        let dominated = saveCount == 2 || (saveCount > 2 && saveCount % 20 == 0)
        guard dominated else { return }

        let lastPrompt = Date(timeIntervalSince1970: lastReviewPromptDateInterval)
        let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? Int.max
        guard daysSinceLastPrompt >= 90 else { return }

        lastReviewPromptDateInterval = Date().timeIntervalSince1970
        requestReview()
    }

    private func handleSave() {
        guard let result = poseResult,
              let uid = authService.currentUserId else { return }

        screenState = .saving

        Task {
            do {
                // Get surgery date to calculate week
                let profile = try await FirestoreService.shared.getUserProfile(uid: uid)
                let surgeryDate = profile?.surgeryDate ?? Date()
                let weekPostOp = DateHelpers.calculateWeekPostOp(from: surgeryDate)

                // Generate measurement ID for photo storage
                let measurementId = UUID().uuidString

                // Upload photo to Firebase Storage
                var photoUrl = ""
                if let image = cameraService.capturedImage {
                    do {
                        photoUrl = try await StorageService.shared.uploadImage(
                            uid: uid,
                            measurementId: measurementId,
                            image: image
                        )
                    } catch {
                        print("Photo upload failed: \(error)")
                        // Continue saving measurement without photo
                    }
                }

                let measurement = Measurement(
                    id: measurementId,
                    type: measurementType,
                    angle: result.angle,
                    timestamp: Date(),
                    weekPostOp: weekPostOp,
                    photoUrl: photoUrl
                )

                _ = try await FirestoreService.shared.saveMeasurement(uid: uid, measurement: measurement)

                await MainActor.run {
                    handleRetake() // Reset to camera view
                    showSuccessBanner = true
                    saveCount += 1
                    checkAndRequestReview()
                    // Auto-hide after 2 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showSuccessBanner = false
                    }
                }
            } catch {
                await MainActor.run {
                    screenState = .result
                    errorMessage = "Failed to save measurement: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - PHPicker Wrapper
struct ImagePickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { image, _ in
                guard let uiImage = image as? UIImage else { return }
                DispatchQueue.main.async {
                    self.parent.onImagePicked(uiImage)
                }
            }
        }
    }
}

#Preview {
    MeasureView()
}
