import Foundation
import AVFoundation
import UIKit
import React

@objc(CameraModule)
class CameraModule: NSObject {

  private var captureSession: AVCaptureSession?
  private var photoOutput: AVCapturePhotoOutput?
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var currentResolve: RCTPromiseResolveBlock?
  private var currentReject: RCTPromiseRejectBlock?

  @objc
  static func requiresMainQueueSetup() -> Bool {
    return true
  }

  @objc
  func requestPermission(_ resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
    AVCaptureDevice.requestAccess(for: .video) { granted in
      DispatchQueue.main.async {
        resolve(granted)
      }
    }
  }

  @objc
  func checkPermission(_ resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    resolve(status == .authorized)
  }

  @objc
  func setupCamera(_ resolve: @escaping RCTPromiseResolveBlock,
                   rejecter reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      let session = AVCaptureSession()
      session.sessionPreset = .photo

      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
        DispatchQueue.main.async {
          reject("CAMERA_ERROR", "No camera available", nil)
        }
        return
      }

      do {
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
          session.addInput(input)
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
          session.addOutput(output)
          self.photoOutput = output
        }

        self.captureSession = session
        session.startRunning()

        DispatchQueue.main.async {
          resolve(true)
        }
      } catch {
        DispatchQueue.main.async {
          reject("CAMERA_ERROR", "Failed to setup camera: \(error.localizedDescription)", error)
        }
      }
    }
  }

  @objc
  func capturePhoto(_ resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let photoOutput = self.photoOutput else {
      reject("CAMERA_ERROR", "Camera not initialized", nil)
      return
    }

    self.currentResolve = resolve
    self.currentReject = reject

    let settings = AVCapturePhotoSettings()
    settings.flashMode = .off

    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  @objc
  func stopCamera() {
    captureSession?.stopRunning()
    captureSession = nil
    photoOutput = nil
  }

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

extension CameraModule: AVCapturePhotoCaptureDelegate {
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    if let error = error {
      currentReject?("CAPTURE_ERROR", "Failed to capture photo: \(error.localizedDescription)", error)
      return
    }

    guard let data = photo.fileDataRepresentation(),
          let image = UIImage(data: data) else {
      currentReject?("CAPTURE_ERROR", "Failed to process photo data", nil)
      return
    }

    // Save to temporary file
    if let path = saveImageToTemporaryFile(image) {
      currentResolve?(path)
    } else {
      currentReject?("CAPTURE_ERROR", "Failed to save photo", nil)
    }

    currentResolve = nil
    currentReject = nil
  }
}
