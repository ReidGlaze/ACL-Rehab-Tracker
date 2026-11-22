import SwiftUI
import PhotosUI
import UIKit
import StoreKit

enum MeasureScreenState {
    case camera
    case processing
    case result
    case saving
    /// Accurate mode only: the photo can't be measured, or the AI check asked for a retake.
    case retake
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
    @AppStorage("aiAnalysisConsented") private var aiAnalysisConsented = false
    @State private var showConsentSheet = false
    @State private var pendingAction: PendingAction?

    // Accurate mode. A missing stored value means the original Standard photo method.
    @AppStorage(MeasureMode.storageKey) private var measureModeRaw = MeasureMode.standard.rawValue
    @State private var showModeSheet = false
    /// Non-nil while an Accurate-mode result is on screen. Nil for a Standard photo result.
    @State private var accurateKeypoints: KneeKeypoints?
    @State private var accurateAdjusted = false
    @State private var accurateNote: String?
    @State private var retakeIssue: RetakeIssue?
    /// Which method the spinner is describing; differs from the setting during a one-photo fallback.
    @State private var processingMode: MeasureMode = .standard

    private var measureMode: MeasureMode { MeasureMode(rawValue: measureModeRaw) ?? .standard }

    enum RetakeIssue: Equatable {
        /// The phone couldn't find a hip, knee and ankle. Carries the AI check's note, if any.
        case noLeg(String?)
        /// The AI check said the photo isn't usable, with what to change.
        case check(String?)
    }

    /// Below this joint confidence the result is shown with a note to check the dots.
    private static let lowConfidence = 0.3
    #if ACL_MODEL_TEST
    @State private var comparisonResults: [ModelTestResult] = []

    /// One backend's answer for a single photo, so test builds can compare models on identical input.
    struct ModelTestResult: Identifiable {
        let id = UUID()
        let label: String
        let pose: PoseResult?
        let elapsed: TimeInterval
        let failure: String?
    }

    struct TestBackend {
        let label: String
        let functionName: String
        /// nil for endpoints that pin their own model (production, and the Gemini test endpoint).
        let model: String?
    }

    /// The first entry is the baseline: it drives the main angle display and is what Save stores.
    /// Backends run sequentially, so keep this list short -- each entry adds ~10-15s per photo.
    /// Swap a `model` string for "claude-sonnet-5-5" / "claude-haiku-5-5" once Model Garden
    /// access is granted. Rows 1 and 2 are the same model on the same prompt and differ only in
    /// thinking config (production's fixed budget_tokens vs adaptive at effort high), so a gap
    /// between them is the thinking change rather than the model.
    private static let testBackends: [TestBackend] = [
        TestBackend(label: "Opus 4.6 \u{2014} prod", functionName: "analyzeKneeAngle", model: nil),
        TestBackend(label: "Opus 5.5 \u{2014} high", functionName: "analyzeKneeAngleClaudeTest", model: "claude-opus-5-5"),
        TestBackend(label: "Sonnet 5.5 \u{2014} high", functionName: "analyzeKneeAngleClaudeTest", model: "claude-sonnet-5-5")
    ]
    #endif

    enum PendingAction {
        case capture
        case photoPicker
    }

    var body: some View {
        Group {
            switch screenState {
            case .camera, .processing:
                cameraView
            case .result, .saving:
                resultView
            case .retake:
                retakeView
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
        .sheet(isPresented: $showModeSheet) {
            MeasureModeSheet(selection: Binding(
                get: { measureMode },
                set: { newMode in
                    guard newMode != measureMode else { return }
                    measureModeRaw = newMode.rawValue
                    AnalyticsService.measureModeSelected(newMode)
                }
            ))
            .presentationDetents([.large])
        }
        #if DEBUG
        .task {
            // Screenshots: `-showMeasureModeSheet YES` opens the method chooser.
            if UserDefaults.standard.bool(forKey: "showMeasureModeSheet") {
                showModeSheet = true
            }
            // UI tests: `-testPhoto /path/to.jpg` feeds a photo straight in (the simulator has no camera).
            if let path = UserDefaults.standard.string(forKey: "testPhoto"), let image = UIImage(contentsOfFile: path) {
                try? await Task.sleep(for: .milliseconds(800))
                handleSelectedPhoto(image)
            }
        }
        #endif
        .sheet(isPresented: $showConsentSheet) {
            AIConsentView(
                onAgree: {
                    AnalyticsService.aiConsent(accepted: true)
                    aiAnalysisConsented = true
                    let action = pendingAction
                    pendingAction = nil
                    showConsentSheet = false
                    if action == .photoPicker {
                        showPhotoPicker = true
                    }
                },
                onCancel: {
                    AnalyticsService.aiConsent(accepted: false)
                    pendingAction = nil
                    showConsentSheet = false
                }
            )
            .presentationDetents([.large])
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
                .padding(.bottom, AppSpacing.sm)

            // Measuring method (Standard photo by default)
            MeasureModeRow(mode: measureMode) { showModeSheet = true }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)
                .disabled(screenState == .processing)

            #if ACL_MODEL_TEST
            modelTestControls
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)
            #endif

            // Camera Preview
            cameraPreview
                .padding(.horizontal, AppSpacing.lg)

            // Instructions
            Text(measureMode.instruction(for: measurementType))
                .font(AppTypography.subhead)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .accessibilityIdentifier("measure.instruction")

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
            Button(action: {
                if aiAnalysisConsented {
                    showPhotoPicker = true
                } else {
                    pendingAction = .photoPicker
                    showConsentSheet = true
                }
            }) {
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
            Button(action: {
                if aiAnalysisConsented {
                    handleCapture()
                } else {
                    pendingAction = .capture
                    showConsentSheet = true
                }
            }) {
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

    #if ACL_MODEL_TEST
    private var modelTestControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("MODEL TEST BUILD")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
                .tracking(1)

            Text("Every photo is measured by all \(Self.testBackends.count) models so the angles are directly comparable. The first result is the one saved.")
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.md)
    }
    #endif

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
                    AnalyzingStatusView(mode: processingMode)
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


    // MARK: - Retake View (Accurate mode)
    private var retakeView: some View {
        let noLeg: Bool
        let note: String?
        switch retakeIssue {
        case .noLeg(let message): noLeg = true; note = message
        case .check(let message): noLeg = false; note = message
        case nil: noLeg = true; note = nil
        }

        return VStack(spacing: AppSpacing.lg) {
            Text(noLeg ? "Couldn't measure this photo" : "Let's retake that")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)

            photoPreview
                .padding(.horizontal, AppSpacing.lg)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(note ?? (noLeg
                    ? "Your phone couldn't find your hip, knee and ankle."
                    : "This photo may not give a reliable angle."))
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("retake.message")

                Text("Accurate mode needs your whole body in the photo, head to feet, taken from the side.")
                    .font(AppTypography.subhead)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .cornerRadius(AppRadius.lg)
            .padding(.horizontal, AppSpacing.lg)

            VStack(spacing: AppSpacing.sm) {
                Button(action: handleRetake) {
                    Text("Retake")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: true))

                if noLeg {
                    Button(action: measureWithStandardInstead) {
                        Text("Measure it with Standard photo")
                    }
                    .buttonStyle(SecondaryButtonStyle(isEnabled: true))
                    .accessibilityIdentifier("retake.useStandard")
                } else {
                    Button(action: { screenState = .result }) {
                        Text("Use this photo anyway")
                    }
                    .buttonStyle(SecondaryButtonStyle(isEnabled: true))
                    .accessibilityIdentifier("retake.useAnyway")
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
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

            // Photo Preview. In Accurate mode the measured lines are drawn on it and can be adjusted.
            if let image = cameraService.capturedImage, accurateKeypoints != nil {
                KneeKeypointEditor(
                    image: image,
                    keypoints: Binding(
                        get: { accurateKeypoints ?? KneeKeypoints(hip: .init(x: 0, y: 0), knee: .init(x: 0, y: 0), ankle: .init(x: 0, y: 0)) },
                        set: { accurateKeypoints = $0 }
                    ),
                    onEdit: { accurateAdjusted = true }
                )
                .padding(.horizontal, AppSpacing.lg)
                .disabled(screenState == .saving)
            } else {
                photoPreview
                    .padding(.horizontal, AppSpacing.lg)
            }

            // Angle Display
            angleDisplay
                .padding(.horizontal, AppSpacing.lg)

            #if ACL_MODEL_TEST
            // Accurate mode calls no model, so the comparison table would be an empty box.
            if accurateKeypoints == nil {
                comparisonTable
                    .padding(.horizontal, AppSpacing.lg)
            }
            #endif

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

            Text("\(displayedAngle)\u{00B0}")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(AppColors.text)
                .accessibilityIdentifier("measure.angle")

            Text("Goal: \(measurementType.goalAngle)\u{00B0}")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textTertiary)

            if accurateKeypoints != nil {
                Text(accurateNote ?? "Measured on your phone from the dots on the photo. Drag a dot if it's off.")
                    .font(AppTypography.footnote)
                    .foregroundColor(accurateNote == nil ? AppColors.textSecondary : AppColors.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.xs)
                    .accessibilityIdentifier("measure.accurateNote")
            }

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

    #if ACL_MODEL_TEST
    private var comparisonTable: some View {
        // Scrolls within a fixed height so model reasoning can be long without pushing the
        // Retake/Save buttons off screen.
        ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(comparisonResults) { result in
                HStack(alignment: .firstTextBaseline) {
                    Text(result.label)
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()

                    if let pose = result.pose {
                        Text(comparisonAngleText(for: result, pose: pose))
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.text)
                    } else {
                        Text("failed")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Text(String(format: "%.1fs", result.elapsed))
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                }

                if let failure = result.failure {
                    Text(failure)
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textTertiary)
                }

                // Why the model gave that angle. Sent to this device only, never logged server-side.
                if let reasoning = result.pose?.reasoning {
                    Text(reasoning)
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 260)
        .padding(AppSpacing.md)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    /// Shows the angle, plus its signed difference from the baseline for every other backend.
    private func comparisonAngleText(for result: ModelTestResult, pose: PoseResult) -> String {
        guard let baseline = comparisonResults.first?.pose,
              result.id != comparisonResults.first?.id else {
            return "\(pose.angle)\u{00B0}"
        }
        let delta = pose.angle - baseline.angle
        return "\(pose.angle)\u{00B0}  (\(delta >= 0 ? "+" : "")\(delta))"
    }
    #endif

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.md) {
            Button(action: {
                AnalyticsService.measurementRetaken(type: measurementType)
                handleRetake()
            }) {
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
        // Haptic feedback on capture
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Show processing state immediately so user knows photo was taken
        processingMode = measureMode
        screenState = .processing

        let type = measurementType
        AnalyticsService.measurementStarted(type: type, source: .camera)

        Task {
            var stage: AnalyticsService.FailureStage = .capture
            do {
                // Capture the actual photo (capturedImage set by delegate)
                let imagePath = try await cameraService.capturePhoto()

                // Measure with the selected method
                stage = .analysis
                try await measure(imagePath: imagePath, type: type)
                AnalyticsService.measurementAnalyzed(type: type, source: .camera)
            } catch {
                AnalyticsService.measurementFailed(type: type, source: .camera, stage: stage)
                await MainActor.run {
                    let notification = UINotificationFeedbackGenerator()
                    notification.notificationOccurred(.error)
                    errorMessage = error.localizedDescription
                    showError = true
                    screenState = .camera
                }
            }
        }
    }

    private func handleSelectedPhoto(_ image: UIImage) {
        // Show processing spinner immediately
        processingMode = measureMode
        screenState = .processing

        let type = measurementType
        AnalyticsService.measurementStarted(type: type, source: .library)

        Task {
            var stage: AnalyticsService.FailureStage = .capture
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

                // Measure with the selected method
                stage = .analysis
                try await measure(imagePath: fileURL.path, type: type)
                AnalyticsService.measurementAnalyzed(type: type, source: .library)
            } catch {
                AnalyticsService.measurementFailed(type: type, source: .library, stage: stage)
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
        accurateKeypoints = nil
        accurateAdjusted = false
        accurateNote = nil
        retakeIssue = nil
        cameraService.capturedImage = nil
        cameraService.capturedImagePath = nil
        screenState = .camera
        #if ACL_MODEL_TEST
        comparisonResults = []
        #endif
    }

    /// The angle on the result screen. In Accurate mode it is computed from the dots, live.
    private var displayedAngle: Int {
        if let keypoints = accurateKeypoints, let image = cameraService.capturedImage,
           let flexion = KneeAngleMath.flexion(keypoints, imageSize: image.size) {
            return KneeAngleMath.display(flexion)
        }
        return poseResult?.angle ?? 0
    }

    /// Runs the selected method on the captured photo and moves to the next screen.
    private func measure(imagePath: String, type: MeasurementType) async throws {
        let mode = await MainActor.run { measureMode }
        if mode == .accurate, let image = await MainActor.run(body: { cameraService.capturedImage }) {
            await measureAccurately(image: image, type: type)
            return
        }
        let detectedPose = try await analyze(imagePath: imagePath)
        await MainActor.run {
            poseResult = detectedPose
            screenState = .result
        }
    }

    /// Accurate mode: the phone finds hip, knee and ankle while Gemini checks the photo is usable.
    /// The check can ask for a retake but can never block: if it can't run, the measurement stands.
    @MainActor
    private func measureAccurately(image: UIImage, type: MeasurementType) async {
        async let pose = KneeAnalyzer.shared.detectPose(image: image, type: type, injuredKnee: userProfile?.injuredKnee)
        async let check = KneeAnalyzer.shared.checkPhoto(image: image, type: type)
        let estimate = await pose
        let checked = await check

        #if DEBUG
        // UI tests: the photo check needs a deployed backend, so its verdict can be forced.
        let verdict = UserDefaults.standard.string(forKey: "forceCheckMessage")
            .map { KneePhotoCheck(passed: false, problem: "framing", message: $0) } ?? checked
        #else
        let verdict = checked
        #endif

        guard let estimate else {
            AnalyticsService.accurateModeOutcome("no_leg")
            retakeIssue = .noLeg(verdict?.passed == false ? verdict?.message : nil)
            screenState = .retake
            return
        }

        accurateKeypoints = estimate.keypoints
        accurateAdjusted = false
        accurateNote = estimate.confidence < Self.lowConfidence
            ? "Your phone wasn't sure about this photo. Check the dots and drag any that are off."
            : nil

        if let verdict, !verdict.passed {
            AnalyticsService.accurateModeOutcome("check_failed")
            retakeIssue = .check(verdict.message)
            screenState = .retake
            return
        }
        AnalyticsService.accurateModeOutcome(verdict == nil ? "measured_unchecked" : "measured")
        screenState = .result
    }

    /// From the retake screen: measure this one photo the original way instead.
    private func measureWithStandardInstead() {
        guard let imagePath = cameraService.capturedImagePath else {
            handleRetake()
            return
        }
        let type = measurementType
        accurateKeypoints = nil
        retakeIssue = nil
        processingMode = .standard
        screenState = .processing
        Task {
            do {
                let detectedPose = try await analyze(imagePath: imagePath)
                await MainActor.run {
                    poseResult = detectedPose
                    screenState = .result
                }
            } catch {
                AnalyticsService.measurementFailed(type: type, source: nil, stage: .analysis)
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    handleRetake()
                }
            }
        }
    }

    /// Release builds measure with the production function. Test builds measure the same photo
    /// with every backend and return the baseline, so saving behaves identically either way.
    private func analyze(imagePath: String) async throws -> PoseResult {
        #if ACL_MODEL_TEST
        let results = await runModelComparison(imagePath: imagePath)
        await MainActor.run { comparisonResults = results }

        guard let pose = results.first(where: { $0.pose != nil })?.pose else {
            throw GeminiPoseError.detectionFailed(
                results.first?.failure ?? "No model returned a measurement."
            )
        }
        return pose
        #else
        return try await GeminiPoseService.shared.detectKneeAngle(
            imagePath: imagePath,
            injuredKnee: userProfile?.injuredKnee,
            injuryType: userProfile?.injuryType
        )
        #endif
    }

    #if ACL_MODEL_TEST
    /// Measures one photo with each backend in turn. Sequential so the reported timings aren't
    /// distorted by contention, and per-backend failures never hide the other results.
    private func runModelComparison(imagePath: String) async -> [ModelTestResult] {
        var results: [ModelTestResult] = []

        for backend in Self.testBackends {
            let startedAt = Date()
            do {
                let pose = try await GeminiPoseService.shared.detectKneeAngle(
                    imagePath: imagePath,
                    injuredKnee: userProfile?.injuredKnee,
                    injuryType: userProfile?.injuryType,
                    functionName: backend.functionName,
                    model: backend.model
                )
                results.append(ModelTestResult(
                    label: backend.label,
                    pose: pose,
                    elapsed: Date().timeIntervalSince(startedAt),
                    failure: nil
                ))
            } catch {
                results.append(ModelTestResult(
                    label: backend.label,
                    pose: nil,
                    elapsed: Date().timeIntervalSince(startedAt),
                    failure: error.localizedDescription
                ))
            }
        }

        return results
    }
    #endif

    private func checkAndRequestReview() {
        let dominated = saveCount == 2 || (saveCount > 2 && saveCount % 20 == 0)
        guard dominated else { return }

        let lastPrompt = Date(timeIntervalSince1970: lastReviewPromptDateInterval)
        let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? Int.max
        guard daysSinceLastPrompt >= 30 else { return }

        lastReviewPromptDateInterval = Date().timeIntervalSince1970
        requestReview()
    }

    private func handleSave() {
        guard poseResult != nil || accurateKeypoints != nil,
              let uid = authService.currentUserId else { return }

        // Read once, before the screen changes: in Accurate mode the angle comes from the dots.
        let angle = displayedAngle
        let method: MeasurementMethod? = accurateKeypoints != nil ? .onDevice : nil
        let adjusted: Bool? = accurateKeypoints != nil ? accurateAdjusted : nil

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
                    angle: angle,
                    timestamp: Date(),
                    weekPostOp: weekPostOp,
                    photoUrl: photoUrl,
                    method: method,
                    adjusted: adjusted
                )

                _ = try await FirestoreService.shared.saveMeasurement(uid: uid, measurement: measurement)

                await MainActor.run {
                    // Success haptic
                    let notification = UINotificationFeedbackGenerator()
                    notification.notificationOccurred(.success)

                    handleRetake() // Reset to camera view
                    showSuccessBanner = true
                    saveCount += 1
                    AnalyticsService.measurementSaved(type: measurement.type, saveCount: saveCount)
                    checkAndRequestReview()
                    // Auto-hide after 2 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showSuccessBanner = false
                    }
                }
            } catch {
                AnalyticsService.measurementFailed(type: measurementType, source: nil, stage: .save)
                await MainActor.run {
                    let notification = UINotificationFeedbackGenerator()
                    notification.notificationOccurred(.error)
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

/// Spinner shown while the photo is analyzed. Analysis takes ~15s, so the message advances
/// through steps to show progress instead of sitting on a static "Analyzing...".
/// Keep the steps and timings in sync with Android's `AnalyzingStatus` in MeasureScreen.kt.
private struct AnalyzingStatusView: View {
    var mode: MeasureMode = .standard

    private static let standardSteps: [(message: String, startsAt: Duration)] = [
        ("Analyzing your photo...", .zero),
        ("Measuring your knee angle...", .seconds(4)),
        ("Almost done...", .seconds(11)),
    ]

    /// Accurate mode runs on the phone, so it is quicker; the wait is the photo check.
    private static let accurateSteps: [(message: String, startsAt: Duration)] = [
        ("Finding your hip, knee and ankle...", .zero),
        ("Checking the photo...", .seconds(2)),
        ("Almost done...", .seconds(7)),
    ]

    private var steps: [(message: String, startsAt: Duration)] {
        mode == .accurate ? Self.accurateSteps : Self.standardSteps
    }

    @State private var stepIndex = 0

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text(steps[stepIndex].message)
                .font(AppTypography.headline)
                .foregroundColor(.white)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: stepIndex)
            Text(mode == .accurate ? "This usually takes a few seconds" : "This usually takes about 15 seconds")
                .font(AppTypography.footnote)
                .foregroundColor(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .task {
            for index in steps.indices.dropFirst() {
                let wait = steps[index].startsAt - steps[index - 1].startsAt
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    return // View disappeared; stop advancing.
                }
                stepIndex = index
            }
        }
    }
}

#Preview {
    MeasureView()
}
