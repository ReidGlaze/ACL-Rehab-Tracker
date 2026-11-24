package com.twintipsolutions.aclrehabtracker.data.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class CameraService(private val context: Context) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var isUsingFrontCamera = false
    private var previewView: PreviewView? = null

    /**
     * False once we know this device has no usable camera (some tablets, Chromebooks and
     * emulators). The Measure tab then offers the photo library instead of a dead shutter.
     */
    var cameraAvailable by mutableStateOf(true)
        private set

    fun getPreviewView(): PreviewView {
        if (previewView == null) {
            previewView = PreviewView(context)
        }
        return previewView!!
    }

    fun setupCamera(lifecycleOwner: LifecycleOwner, onReady: () -> Unit = {}) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            // On a device with no camera CameraX can fail to start at all; that must not crash.
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCamera(lifecycleOwner)
                onReady()
            } catch (e: Exception) {
                android.util.Log.w("CameraService", "Camera unavailable", e)
                cameraAvailable = false
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCamera(lifecycleOwner: LifecycleOwner) {
        val provider = cameraProvider ?: return
        provider.unbindAll()

        fun has(selector: CameraSelector) = runCatching { provider.hasCamera(selector) }.getOrDefault(false)
        val hasBack = has(CameraSelector.DEFAULT_BACK_CAMERA)
        val hasFront = has(CameraSelector.DEFAULT_FRONT_CAMERA)
        if (!hasBack && !hasFront) {
            imageCapture = null
            cameraAvailable = false
            return
        }
        // Use the camera that was asked for when it exists, otherwise the one the device has.
        if (isUsingFrontCamera && !hasFront) isUsingFrontCamera = false
        if (!isUsingFrontCamera && !hasBack) isUsingFrontCamera = true

        val cameraSelector = if (isUsingFrontCamera) {
            CameraSelector.DEFAULT_FRONT_CAMERA
        } else {
            CameraSelector.DEFAULT_BACK_CAMERA
        }

        val preview = Preview.Builder().build().also {
            it.surfaceProvider = previewView?.surfaceProvider
        }

        imageCapture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()

        try {
            provider.bindToLifecycle(lifecycleOwner, cameraSelector, preview, imageCapture)
            cameraAvailable = true
        } catch (e: Exception) {
            android.util.Log.w("CameraService", "Could not start the camera", e)
            imageCapture = null
            cameraAvailable = false
        }
    }

    fun flipCamera(lifecycleOwner: LifecycleOwner) {
        isUsingFrontCamera = !isUsingFrontCamera
        bindCamera(lifecycleOwner)
    }

    suspend fun capturePhoto(): String = suspendCoroutine { continuation ->
        val capture = imageCapture ?: run {
            continuation.resumeWithException(Exception("Camera not ready"))
            return@suspendCoroutine
        }

        capture.takePicture(
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(image: ImageProxy) {
                    try {
                        val bitmap = imageProxyToBitmap(image)
                        val file = saveToTempFile(bitmap)
                        image.close()
                        continuation.resume(file.absolutePath)
                    } catch (e: Exception) {
                        image.close()
                        continuation.resumeWithException(e)
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    continuation.resumeWithException(exception)
                }
            }
        )
    }

    private fun imageProxyToBitmap(image: ImageProxy): Bitmap {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)

        val rotation = image.imageInfo.rotationDegrees
        if (rotation == 0) return bitmap

        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun saveToTempFile(bitmap: Bitmap): File {
        val file = File(context.cacheDir, "capture_${System.currentTimeMillis()}.jpg")
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        return file
    }

    fun getPreviewBitmap(): Bitmap? = previewView?.bitmap

    fun stopCamera() {
        cameraProvider?.unbindAll()
    }
}
