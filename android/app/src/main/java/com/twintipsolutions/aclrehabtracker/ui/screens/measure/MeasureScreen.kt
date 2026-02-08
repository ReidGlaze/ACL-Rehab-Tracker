package com.twintipsolutions.aclrehabtracker.ui.screens.measure

import android.Manifest
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
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
import android.app.Activity
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

private enum class MeasureScreenState {
    CAMERA, PROCESSING, RESULT, SAVING
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun MeasureScreen() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    val vibrator = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(android.content.Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(android.content.Context.VIBRATOR_SERVICE) as Vibrator
        }
    }
    fun hapticClick() {
        vibrator.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
    }
    fun hapticSuccess() {
        vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
    }
    fun hapticError() {
        vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 40, 60, 40), -1))
    }

    var selectedType by remember { mutableStateOf(MeasurementType.EXTENSION) }
    var screenState by remember { mutableStateOf(MeasureScreenState.CAMERA) }
    var capturedImagePath by remember { mutableStateOf<String?>(null) }
    var frozenPreviewBitmap by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var poseResult by remember { mutableStateOf<PoseResult?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var successMessage by remember { mutableStateOf<String?>(null) }
    var userProfile by remember { mutableStateOf<UserProfile?>(null) }

    val cameraService = remember { CameraService(context) }
    val cameraPermissionState = rememberPermissionState(Manifest.permission.CAMERA)
    val snackbarHostState = remember { SnackbarHostState() }

    // Photo picker launcher
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        uri?.let {
            scope.launch {
                try {
                    errorMessage = null
                    // Copy picked image to temp file
                    val inputStream = context.contentResolver.openInputStream(it)
                    val tempFile = java.io.File(context.cacheDir, "picked_${System.currentTimeMillis()}.jpg")
                    inputStream?.use { input ->
                        tempFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    capturedImagePath = tempFile.absolutePath
                    screenState = MeasureScreenState.PROCESSING
                    val result = GeminiPoseService.detectKneeAngle(
                        imagePath = tempFile.absolutePath,
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
    }

    fun handlePickFromLibrary() {
        photoPickerLauncher.launch(
            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
        )
    }

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
        hapticClick()
        scope.launch {
            try {
                errorMessage = null
                // Grab frozen frame from preview before switching to processing
                frozenPreviewBitmap = cameraService.getPreviewBitmap()
                // Show processing state immediately so user knows photo was taken
                screenState = MeasureScreenState.PROCESSING
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
                hapticError()
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
                    } catch (e: Exception) {
                        android.util.Log.e("MeasureScreen", "Photo upload failed", e)
                        // Continue saving measurement without photo
                    }
                }

                val measurement = Measurement(
                    type = selectedType,
                    angle = result.angle,
                    weekPostOp = weekPostOp,
                    photoUrl = photoUrl
                )
                FirestoreService.saveMeasurement(uid, measurement)
                // Reset with success feedback
                hapticSuccess()
                successMessage = "Measurement saved!"
                screenState = MeasureScreenState.CAMERA
                capturedImagePath = null
                poseResult = null

                // In-app review prompt
                val prefs = context.getSharedPreferences("acl_rehab_prefs", android.content.Context.MODE_PRIVATE)
                val newCount = prefs.getInt("measurement_save_count", 0) + 1
                prefs.edit().putInt("measurement_save_count", newCount).apply()

                val shouldPrompt = newCount == 2 || (newCount > 2 && newCount % 20 == 0)
                if (shouldPrompt) {
                    val lastPrompt = prefs.getLong("last_review_prompt_date", 0L)
                    val daysSince = java.util.concurrent.TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - lastPrompt)
                    if (daysSince >= 30) {
                        prefs.edit().putLong("last_review_prompt_date", System.currentTimeMillis()).apply()
                        try {
                            val reviewManager = ReviewManagerFactory.create(context)
                            val reviewInfo = reviewManager.requestReviewFlow().await()
                            (context as? Activity)?.let { activity ->
                                reviewManager.launchReviewFlow(activity, reviewInfo)
                            }
                        } catch (_: Exception) { /* Review flow is best-effort */ }
                    }
                }
            } catch (e: Exception) {
                hapticError()
                errorMessage = e.message ?: "Failed to save"
                screenState = MeasureScreenState.RESULT
            }
        }
    }

    fun handleRetake() {
        screenState = MeasureScreenState.CAMERA
        capturedImagePath = null
        poseResult = null
        frozenPreviewBitmap = null
    }

    // Show success snackbar
    LaunchedEffect(successMessage) {
        successMessage?.let {
            snackbarHostState.showSnackbar(it, duration = SnackbarDuration.Short)
            successMessage = null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            when (screenState) {
                MeasureScreenState.CAMERA, MeasureScreenState.PROCESSING -> {
                    CameraView(
                        selectedType = selectedType,
                        onTypeChange = { selectedType = it },
                        cameraPermissionGranted = cameraPermissionState.status.isGranted,
                        onRequestPermission = { cameraPermissionState.launchPermissionRequest() },
                        cameraService = cameraService,
                        onCapture = { handleCapture() },
                        onPickFromLibrary = { handlePickFromLibrary() },
                        onFlipCamera = { cameraService.flipCamera(lifecycleOwner) },
                        isProcessing = screenState == MeasureScreenState.PROCESSING,
                        capturedImagePath = capturedImagePath,
                        frozenPreviewBitmap = frozenPreviewBitmap
                    )
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

        // Success snackbar
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter)
        )

        // Error dialog - at MeasureScreen level so it shows over any state
        if (errorMessage != null) {
            AlertDialog(
                onDismissRequest = { errorMessage = null },
                title = { Text("Error", color = AppColors.Text) },
                text = { Text(errorMessage ?: "", color = AppColors.TextSecondary) },
                confirmButton = {
                    TextButton(onClick = { errorMessage = null }) {
                        Text("OK", color = AppColors.Primary)
                    }
                },
                containerColor = AppColors.Surface
            )
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
    onPickFromLibrary: () -> Unit,
    onFlipCamera: () -> Unit,
    isProcessing: Boolean = false,
    capturedImagePath: String? = null,
    frozenPreviewBitmap: android.graphics.Bitmap? = null
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp)
    ) {
        // Header row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 24.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Measure",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            )
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

        // Camera Preview or Permission Request - fills remaining space
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface),
            contentAlignment = Alignment.Center
        ) {
            if (cameraPermissionGranted) {
                // Always keep camera preview in the tree so the PreviewView doesn't flash
                CameraPreview(
                    previewView = cameraService.getPreviewView(),
                    modifier = Modifier.fillMaxSize()
                )
                if (isProcessing) {
                    // Layer captured/frozen image on top of live preview
                    val displayBitmap = capturedImagePath?.let { path ->
                        remember(path) { BitmapFactory.decodeFile(path) }
                    } ?: frozenPreviewBitmap
                    if (displayBitmap != null) {
                        Image(
                            bitmap = displayBitmap.asImageBitmap(),
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop
                        )
                    }
                    // Dark overlay (fully opaque if no frozen frame to hide live feed)
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(AppColors.Background.copy(alpha = if (displayBitmap != null) 0.6f else 0.85f))
                    )
                    // Spinner + text
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(40.dp),
                            color = AppColors.Primary,
                            strokeWidth = 3.dp
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "Analyzing...",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.Text
                        )
                    }
                }
            } else if (!isProcessing) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "Camera access required",
                        color = AppColors.TextSecondary,
                        fontSize = 17.sp
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "To photograph your knee for angle measurement",
                        color = AppColors.TextTertiary,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 32.dp)
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

        Spacer(modifier = Modifier.height(12.dp))

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

        Spacer(modifier = Modifier.height(16.dp))

        // Bottom controls: Library | Capture | Flip Camera
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 32.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Photo library picker (left)
            IconButton(
                onClick = onPickFromLibrary,
                modifier = Modifier
                    .size(48.dp)
                    .background(AppColors.Surface, RoundedCornerShape(12.dp))
            ) {
                Icon(
                    painter = androidx.compose.ui.res.painterResource(
                        id = android.R.drawable.ic_menu_gallery
                    ),
                    contentDescription = "Pick from library",
                    tint = AppColors.Text,
                    modifier = Modifier.size(24.dp)
                )
            }

            // Capture button (center)
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(AppColors.Background)
                    .clickable(enabled = cameraPermissionGranted) { onCapture() },
                contentAlignment = Alignment.Center
            ) {
                // Outer ring
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(AppColors.Text.copy(alpha = if (cameraPermissionGranted) 1f else 0.4f)),
                    contentAlignment = Alignment.Center
                ) {
                    // Inner gap
                    Box(
                        modifier = Modifier
                            .size(74.dp)
                            .clip(CircleShape)
                            .background(AppColors.Background),
                        contentAlignment = Alignment.Center
                    ) {
                        // Red fill
                        Box(
                            modifier = Modifier
                                .size(64.dp)
                                .clip(CircleShape)
                                .background(
                                    if (cameraPermissionGranted) AppColors.Primary
                                    else AppColors.Primary.copy(alpha = 0.4f)
                                )
                        )
                    }
                }
            }

            // Flip camera (right)
            IconButton(
                onClick = onFlipCamera,
                enabled = cameraPermissionGranted,
                modifier = Modifier
                    .size(48.dp)
                    .background(AppColors.Surface, RoundedCornerShape(12.dp))
            ) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = "Switch camera",
                    tint = if (cameraPermissionGranted) AppColors.Text else AppColors.Text.copy(alpha = 0.4f),
                    modifier = Modifier.size(24.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
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
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "${measurementType.displayName} Result",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Photo preview - use weight to fill available space like iOS .fit
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
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

        Spacer(modifier = Modifier.height(16.dp))

        // Angle display card
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "MEASURED ANGLE",
                fontSize = 13.sp,
                color = AppColors.TextSecondary,
                letterSpacing = 1.sp
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "${angle}°",
                fontSize = 64.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            )
            Text(
                text = "Goal: ${goalAngle}°",
                fontSize = 17.sp,
                color = AppColors.TextTertiary
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "For personal tracking only. Not for medical diagnosis.",
                fontSize = 12.sp,
                color = AppColors.TextTertiary,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

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
