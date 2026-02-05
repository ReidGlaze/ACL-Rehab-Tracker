package com.twintipsolutions.aclrehabtracker.ui.screens.measure

import android.Manifest
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.model.PoseResult
import com.twintipsolutions.aclrehabtracker.data.model.UserProfile
import com.twintipsolutions.aclrehabtracker.data.service.AuthService
import com.twintipsolutions.aclrehabtracker.data.service.CameraService
import com.twintipsolutions.aclrehabtracker.data.service.FirestoreService
import com.twintipsolutions.aclrehabtracker.data.service.GeminiPoseService
import com.twintipsolutions.aclrehabtracker.data.service.StorageService
import com.twintipsolutions.aclrehabtracker.ui.components.CameraPreview
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import com.twintipsolutions.aclrehabtracker.util.DateHelpers
import kotlinx.coroutines.launch

private enum class MeasureScreenState {
    CAMERA, PROCESSING, RESULT, SAVING
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun MeasureScreen() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    var selectedType by remember { mutableStateOf(MeasurementType.EXTENSION) }
    var screenState by remember { mutableStateOf(MeasureScreenState.CAMERA) }
    var capturedImagePath by remember { mutableStateOf<String?>(null) }
    var poseResult by remember { mutableStateOf<PoseResult?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var userProfile by remember { mutableStateOf<UserProfile?>(null) }

    val cameraService = remember { CameraService(context) }
    val cameraPermissionState = rememberPermissionState(Manifest.permission.CAMERA)

    LaunchedEffect(Unit) {
        val uid = AuthService.currentUserId ?: return@LaunchedEffect
        userProfile = try { FirestoreService.getUserProfile(uid) } catch (_: Exception) { null }
    }

    // Setup camera when permission is granted
    LaunchedEffect(cameraPermissionState.status.isGranted) {
        if (cameraPermissionState.status.isGranted) {
            cameraService.setupCamera(lifecycleOwner)
        }
    }

    DisposableEffect(Unit) {
        onDispose { cameraService.stopCamera() }
    }

    fun handleCapture() {
        scope.launch {
            try {
                screenState = MeasureScreenState.PROCESSING
                errorMessage = null
                val path = cameraService.capturePhoto()
                capturedImagePath = path
                val result = GeminiPoseService.detectKneeAngle(
                    imagePath = path,
                    injuredKnee = userProfile?.injuredKnee?.name?.lowercase(),
                    injuryType = userProfile?.injuryType?.firestoreValue
                )
                poseResult = result
                screenState = MeasureScreenState.RESULT
            } catch (e: Exception) {
                errorMessage = e.message ?: "Failed to analyze image"
                screenState = MeasureScreenState.CAMERA
            }
        }
    }

    fun handleSave() {
        scope.launch {
            val uid = AuthService.currentUserId ?: return@launch
            val result = poseResult ?: return@launch
            screenState = MeasureScreenState.SAVING
            try {
                val weekPostOp = DateHelpers.calculateWeekPostOp(userProfile?.surgeryDate)
                val measurementId = java.util.UUID.randomUUID().toString()

                // Upload photo to Firebase Storage
                var photoUrl = ""
                capturedImagePath?.let { path ->
                    try {
                        photoUrl = StorageService.uploadPhoto(uid, measurementId, path)
                    } catch (_: Exception) { }
                }

                val measurement = Measurement(
                    type = selectedType,
                    angle = result.angle,
                    weekPostOp = weekPostOp,
                    photoUrl = photoUrl
                )
                FirestoreService.saveMeasurement(uid, measurement)
                // Reset
                screenState = MeasureScreenState.CAMERA
                capturedImagePath = null
                poseResult = null
            } catch (e: Exception) {
                errorMessage = e.message ?: "Failed to save"
                screenState = MeasureScreenState.RESULT
            }
        }
    }

    fun handleRetake() {
        screenState = MeasureScreenState.CAMERA
        capturedImagePath = null
        poseResult = null
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
    ) {
        when (screenState) {
            MeasureScreenState.CAMERA -> {
                CameraView(
                    selectedType = selectedType,
                    onTypeChange = { selectedType = it },
                    cameraPermissionGranted = cameraPermissionState.status.isGranted,
                    onRequestPermission = { cameraPermissionState.launchPermissionRequest() },
                    cameraService = cameraService,
                    onCapture = { handleCapture() },
                    onFlipCamera = { cameraService.flipCamera(lifecycleOwner) },
                    errorMessage = errorMessage,
                    onDismissError = { errorMessage = null }
                )
            }
            MeasureScreenState.PROCESSING -> {
                ProcessingView(capturedImagePath)
            }
            MeasureScreenState.RESULT, MeasureScreenState.SAVING -> {
                ResultView(
                    imagePath = capturedImagePath,
                    angle = poseResult?.angle ?: 0,
                    goalAngle = selectedType.goalAngle,
                    measurementType = selectedType,
                    isSaving = screenState == MeasureScreenState.SAVING,
                    onSave = { handleSave() },
                    onRetake = { handleRetake() }
                )
            }
        }
    }
}

@Composable
private fun CameraView(
    selectedType: MeasurementType,
    onTypeChange: (MeasurementType) -> Unit,
    cameraPermissionGranted: Boolean,
    onRequestPermission: () -> Unit,
    cameraService: CameraService,
    onCapture: () -> Unit,
    onFlipCamera: () -> Unit,
    errorMessage: String?,
    onDismissError: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        // Header row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Measure",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            )
            // Flip camera button
            if (cameraPermissionGranted) {
                IconButton(
                    onClick = onFlipCamera,
                    modifier = Modifier
                        .size(40.dp)
                        .background(AppColors.Surface, CircleShape)
                ) {
                    Text("↻", fontSize = 20.sp, color = AppColors.Text)
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Type Toggle
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            MeasurementType.entries.forEach { type ->
                val isSelected = type == selectedType
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (isSelected) AppColors.Primary else AppColors.Surface)
                        .clickable { onTypeChange(type) }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = type.displayName,
                        color = if (isSelected) AppColors.Text else AppColors.TextSecondary,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Camera Preview or Permission Request
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(3f / 4f)
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface),
            contentAlignment = Alignment.Center
        ) {
            if (cameraPermissionGranted) {
                CameraPreview(
                    previewView = cameraService.getPreviewView(),
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "Camera access required",
                        color = AppColors.TextSecondary,
                        fontSize = 17.sp
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Button(
                        onClick = onRequestPermission,
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Grant Permission")
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Instructions
        Text(
            text = if (selectedType == MeasurementType.EXTENSION)
                "Straighten your leg as much as possible and capture from the side"
            else
                "Bend your knee as much as possible and capture from the side",
            color = AppColors.TextSecondary,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        )

        Spacer(modifier = Modifier.weight(1f))

        // Capture Button
        if (cameraPermissionGranted) {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(AppColors.Primary)
                        .clickable { onCapture() },
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(68.dp)
                            .clip(CircleShape)
                            .background(AppColors.Primary)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }

    // Error dialog
    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = onDismissError,
            title = { Text("Error", color = AppColors.Text) },
            text = { Text(errorMessage, color = AppColors.TextSecondary) },
            confirmButton = {
                TextButton(onClick = onDismissError) {
                    Text("OK", color = AppColors.Primary)
                }
            },
            containerColor = AppColors.Surface
        )
    }
}

@Composable
private fun ProcessingView(imagePath: String?) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        // Show captured image as background
        imagePath?.let { path ->
            val bitmap = remember(path) { BitmapFactory.decodeFile(path) }
            bitmap?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
            }
        }

        // Dark overlay
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.Background.copy(alpha = 0.7f))
        )

        // Loading indicator
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(
                modifier = Modifier.size(48.dp),
                color = AppColors.Primary,
                strokeWidth = 3.dp
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Analyzing your knee angle...",
                fontSize = 17.sp,
                color = AppColors.Text
            )
        }
    }
}

@Composable
private fun ResultView(
    imagePath: String?,
    angle: Int,
    goalAngle: Int,
    measurementType: MeasurementType,
    isSaving: Boolean,
    onSave: () -> Unit,
    onRetake: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "${measurementType.displayName} Result",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Photo preview
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(3f / 4f)
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface),
            contentAlignment = Alignment.Center
        ) {
            imagePath?.let { path ->
                val bitmap = remember(path) { BitmapFactory.decodeFile(path) }
                bitmap?.let {
                    Image(
                        bitmap = it.asImageBitmap(),
                        contentDescription = "Captured photo",
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Angle display
        Text(
            text = "${angle}°",
            fontSize = 64.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )

        Text(
            text = "${measurementType.displayName} • Goal: ${goalAngle}°",
            fontSize = 17.sp,
            color = AppColors.TextSecondary
        )

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "For personal tracking only. Not for medical diagnosis.",
            fontSize = 12.sp,
            color = AppColors.TextTertiary,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.weight(1f))

        // Buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedButton(
                onClick = onRetake,
                enabled = !isSaving,
                modifier = Modifier
                    .weight(1f)
                    .height(52.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = AppColors.Text
                )
            ) {
                Text("Retake", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }

            Button(
                onClick = onSave,
                enabled = !isSaving,
                modifier = Modifier
                    .weight(1f)
                    .height(52.dp),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
                shape = RoundedCornerShape(16.dp)
            ) {
                if (isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = AppColors.Text,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text("Save", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}
