import SwiftUI
import PhotosUI

enum MeasureScreenState {
    case camera
    case processing
    case result
    case saving
}

struct MeasureView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var authService = AuthService.shared

    @State private var measurementType: MeasurementType = .extension
    @State private var screenState: MeasureScreenState = .camera
    @State private var poseResult: PoseResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var userProfile: UserProfile?

    var body: some View {
        Group {
            switch screenState {
            case .camera:
                cameraView
            case .processing:
                processingView
            case .result, .saving:
                resultView
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

                // Flip Camera Button
                Button(action: { cameraService.flipCamera() }) {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(AppColors.text)
                        .frame(width: 44, height: 44)
                        .background(AppColors.surface)
                        .cornerRadius(AppRadius.md)
                }
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

            // Capture Button (only when camera is ready)
            if cameraService.isCameraReady {
                captureButton
                    .padding(.bottom, AppSpacing.xl)
            } else {
                Spacer()
                    .frame(height: 80 + AppSpacing.xl)
            }
        }
    }

    // MARK: - Processing View (shows captured image while analyzing)
    private var processingView: some View {
        ZStack {
            // Show the captured image
            if let image = cameraService.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }

            // Dark overlay
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            // Loading indicator
            VStack(spacing: AppSpacing.lg) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)

                Text("Analyzing your knee angle...")
                    .font(AppTypography.title3)
                    .foregroundColor(.white)
            }
        }
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
                    .cornerRadius(AppRadius.lg)
            } else {
                // Camera not available - show test mode option (works in simulator)
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondary)

                    Text("Camera not available")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.text)

                    Text("Use photo library to test")
                        .font(AppTypography.subhead)
                        .foregroundColor(AppColors.textSecondary)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text("Pick from Library")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.text)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColors.primary)
                            .cornerRadius(AppRadius.md)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.surface)
                .cornerRadius(AppRadius.lg)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3/4, contentMode: .fit)
        .onChange(of: selectedPhotoItem) { _, newItem in
            handleSelectedPhoto(newItem)
        }
    }

    private var captureButton: some View {
        Button(action: handleCapture) {
            ZStack {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 80, height: 80)

                Circle()
                    .stroke(AppColors.text, lineWidth: 4)
                    .frame(width: 80, height: 80)

                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.background))
                } else {
                    Circle()
                        .fill(AppColors.primary)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(isProcessing || !cameraService.isCameraReady)
        .opacity(isProcessing ? 0.7 : 1.0)
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
                errorMessage = error.localizedDescription
                showError = true
            }
        }
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
        Task {
            do {
                // Capture the actual photo
                let imagePath = try await cameraService.capturePhoto()

                // Transition to processing view (shows captured image with loading)
                await MainActor.run {
                    screenState = .processing
                }

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

    private func handleSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            do {
                // Load the image data
                guard let data = try await item.loadTransferable(type: Data.self),
                      let originalImage = UIImage(data: data) else {
                    throw NSError(domain: "MeasureView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
                }

                // Save image to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "photo_\(UUID().uuidString).jpg"
                let fileURL = tempDir.appendingPathComponent(fileName)

                guard let jpegData = originalImage.jpegData(compressionQuality: 0.9) else {
                    throw NSError(domain: "MeasureView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image"])
                }
                try jpegData.write(to: fileURL)

                await MainActor.run {
                    cameraService.capturedImage = originalImage
                    cameraService.capturedImagePath = fileURL.path
                    screenState = .processing
                }

                // Analyze image with Gemini (no MediaPipe overlay)
                let detectedPose = try await GeminiPoseService.shared.detectKneeAngle(
                    imagePath: fileURL.path,
                    injuredKnee: userProfile?.injuredKnee,
                    injuryType: userProfile?.injuryType
                )

                await MainActor.run {
                    poseResult = detectedPose
                    screenState = .result
                    selectedPhotoItem = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func handleRetake() {
        poseResult = nil
        cameraService.capturedImage = nil
        cameraService.capturedImagePath = nil
        screenState = .camera
        selectedPhotoItem = nil
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
                    photoUrl = try await StorageService.shared.uploadImage(
                        uid: uid,
                        measurementId: measurementId,
                        image: image
                    )
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

#Preview {
    MeasureView()
}
