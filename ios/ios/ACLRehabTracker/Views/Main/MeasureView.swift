import SwiftUI

enum MeasureScreenState {
    case camera
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

    var body: some View {
        Group {
            switch screenState {
            case .camera:
                cameraView
            case .result, .saving:
                resultView
            }
        }
        .background(AppColors.background)
        .task {
            await setupCamera()
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

            // Capture Button
            captureButton
                .padding(.bottom, AppSpacing.xl)
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
            } else if let error = cameraService.error {
                CameraPlaceholder(
                    message: error.localizedDescription,
                    submessage: "Tap to retry"
                )
                .cornerRadius(AppRadius.lg)
                .onTapGesture {
                    Task { await setupCamera() }
                }
            } else {
                CameraPlaceholder()
                    .cornerRadius(AppRadius.lg)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3/4, contentMode: .fit)
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
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(AppRadius.lg)

                    // Show pose overlay on captured image
                    if let pose = poseResult {
                        GeometryReader { geometry in
                            PoseOverlay(poseResult: pose)
                        }
                    }
                }
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

    private func handleCapture() {
        isProcessing = true

        Task {
            do {
                // Capture the actual photo
                let imagePath = try await cameraService.capturePhoto()

                // Use the current live pose result if available, otherwise detect from captured image
                if let livePose = cameraService.currentPoseResult {
                    // Re-detect from captured image for accurate coordinates
                    let detectedPose = try await PoseDetectionService.shared.detectPose(imagePath: imagePath)
                    await MainActor.run {
                        poseResult = detectedPose
                        screenState = .result
                        isProcessing = false
                    }
                } else {
                    // Detect from captured image
                    let detectedPose = try await PoseDetectionService.shared.detectPose(imagePath: imagePath)
                    await MainActor.run {
                        poseResult = detectedPose
                        screenState = .result
                        isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
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

                let measurement = Measurement(
                    type: measurementType,
                    angle: result.angle,
                    timestamp: Date(),
                    weekPostOp: weekPostOp,
                    photoUrl: "" // Would upload photo here
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
