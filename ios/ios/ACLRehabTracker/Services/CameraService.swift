import Foundation
import AVFoundation
import UIKit
import Combine
import CoreMedia

@MainActor
class CameraService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isCameraReady = false
    @Published var capturedImage: UIImage?
    @Published var capturedImagePath: String?
    @Published var error: CameraError?
    @Published var currentPoseResult: PoseResult?

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var captureCompletion: ((Result<String, Error>) -> Void)?

    // Throttle frame processing to ~15 FPS
    private var lastFrameTime: CFAbsoluteTime = 0
    private let frameInterval: CFAbsoluteTime = 1.0 / 15.0

    // Video processing queue
    private let videoProcessingQueue = DispatchQueue(label: "com.aclrehab.videoProcessing", qos: .userInitiated)

    override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        isAuthorized = status == .authorized
    }

    func requestPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            isAuthorized = granted
        }
        return granted
    }

    // MARK: - Camera Setup

    func setupCamera() async throws {
        guard isAuthorized else {
            throw CameraError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                let session = AVCaptureSession()
                session.sessionPreset = .photo

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    continuation.resume(throwing: CameraError.noCameraAvailable)
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if session.canAddInput(input) {
                        session.addInput(input)
                    }

                    // Photo output
                    let photoOutput = AVCapturePhotoOutput()
                    if session.canAddOutput(photoOutput) {
                        session.addOutput(photoOutput)
                    }

                    // Video output for live pose detection
                    let videoOutput = AVCaptureVideoDataOutput()
                    videoOutput.setSampleBufferDelegate(self, queue: self.videoProcessingQueue)
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]

                    if session.canAddOutput(videoOutput) {
                        session.addOutput(videoOutput)
                    }

                    self.captureSession = session
                    self.photoOutput = photoOutput
                    self.videoOutput = videoOutput

                    session.startRunning()

                    DispatchQueue.main.async {
                        self.isCameraReady = true
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: CameraError.setupFailed)
                }
            }
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() async throws -> String {
        guard let photoOutput = photoOutput else {
            throw CameraError.cameraNotInitialized
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: CameraError.cameraNotInitialized)
                return
            }

            self.captureCompletion = { result in
                continuation.resume(with: result)
            }

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Cleanup

    func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        photoOutput = nil
        videoOutput = nil
        isCameraReady = false
        currentPoseResult = nil
    }

    // MARK: - Preview Layer

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }

    var session: AVCaptureSession? {
        captureSession
    }

    // MARK: - Helper Methods

    private func saveImageToTemporaryFile(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "capture_\(UUID().uuidString).jpg"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error = error {
                captureCompletion?(.failure(CameraError.captureFailed(error.localizedDescription)))
                captureCompletion = nil
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                captureCompletion?(.failure(CameraError.processingFailed))
                captureCompletion = nil
                return
            }

            capturedImage = image

            if let path = saveImageToTemporaryFile(image) {
                capturedImagePath = path
                captureCompletion?(.success(path))
            } else {
                captureCompletion?(.failure(CameraError.saveFailed))
            }
            captureCompletion = nil
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle to ~15 FPS
        let currentTime = CFAbsoluteTimeGetCurrent()
        guard currentTime - lastFrameTime >= frameInterval else { return }

        // Process frame for pose detection
        Task {
            do {
                let result = try await PoseDetectionService.shared.detectPose(sampleBuffer: sampleBuffer)
                await MainActor.run {
                    self.currentPoseResult = result
                }
            } catch {
                // Silently ignore detection failures on individual frames
                // This is expected when no body is visible
            }
        }

        // Update on non-isolated context
        DispatchQueue.main.async {
            self.lastFrameTime = currentTime
        }
    }
}

// MARK: - Camera Errors

enum CameraError: LocalizedError {
    case notAuthorized
    case noCameraAvailable
    case setupFailed
    case cameraNotInitialized
    case captureFailed(String)
    case processingFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access not authorized"
        case .noCameraAvailable:
            return "No camera available"
        case .setupFailed:
            return "Failed to setup camera"
        case .cameraNotInitialized:
            return "Camera not initialized"
        case .captureFailed(let message):
            return "Failed to capture photo: \(message)"
        case .processingFailed:
            return "Failed to process photo data"
        case .saveFailed:
            return "Failed to save photo"
        }
    }
}
