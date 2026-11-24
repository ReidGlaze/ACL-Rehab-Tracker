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
import androidx.compose.ui.graphics.Color
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
import com.twintipsolutions.aclrehabtracker.data.service.AnalyticsService
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
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.twintipsolutions.aclrehabtracker.data.model.KneeSide
import com.twintipsolutions.aclrehabtracker.data.model.MeasureMode
import com.twintipsolutions.aclrehabtracker.data.pose.KneeBend
import com.twintipsolutions.aclrehabtracker.data.pose.KneeGeometry
import com.twintipsolutions.aclrehabtracker.data.pose.KneeKeypoints
import com.twintipsolutions.aclrehabtracker.data.pose.KneeLeg
import com.twintipsolutions.aclrehabtracker.data.service.KneePoseEstimator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

private enum class MeasureScreenState {
    CAMERA, PROCESSING, RESULT, SAVING,
    /** Whole-body mode only: the phone couldn't find a whole leg in the photo. */
    RETAKE
}

/**
 * Lets UI tests drive the Measure tab without a camera, a photo picker or a signed-in user.
 * The app itself always passes null.
 */
class MeasureTestHooks(
    /** Used in place of the photo picker when the library button is tapped. */
    val photoPath: String? = null,
    /** Stands in for the knee saved in the profile. */
    val injuredKnee: KneeSide? = null,
    /** Starts in this mode instead of the saved one, and doesn't save changes. */
    val mode: MeasureMode? = null,
)

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun MeasureScreen(testHooks: MeasureTestHooks? = null) {
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

    // --- Whole-body mode (opt-in). Standard photo is the default and none of this touches it. ---
    val prefs = remember { context.getSharedPreferences(MeasureMode.PREFS, android.content.Context.MODE_PRIVATE) }
    var measureMode by remember { mutableStateOf(testHooks?.mode ?: MeasureMode.load(context)) }
    var showModeSheet by remember { mutableStateOf(false) }
    var showPoseGuide by remember { mutableStateOf(false) }
    var selfTimerSeconds by remember { mutableIntStateOf(if (testHooks != null) 0 else prefs.getInt(MeasureMode.KEY_SELF_TIMER, 0)) }
    var countdownRemaining by remember { mutableStateOf<Int?>(null) }
    var countdownJob by remember { mutableStateOf<Job?>(null) }
    val beeper = remember { CountdownBeeper() }
    /** The photo as displayed (upright), with the dots drawn on it. */
    var wholeBodyBitmap by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var wholeBodyKeypoints by remember { mutableStateOf<KneeKeypoints?>(null) }
    var wholeBodyNote by remember { mutableStateOf<String?>(null) }
    var wholeBodyAdjusted by remember { mutableStateOf(false) }

    val requestedKnee: KneeLeg? = (testHooks?.injuredKnee ?: userProfile?.injuredKnee)?.let {
        if (it == KneeSide.LEFT) KneeLeg.LEFT else KneeLeg.RIGHT
    }
    val wholeBodyAngle: Int? = wholeBodyKeypoints?.let { points ->
        wholeBodyBitmap?.let { KneeGeometry.flexion(points, it.width, it.height) }?.let(KneeGeometry::display)
    }

    fun cancelCountdown() {
        countdownJob?.cancel()
        countdownJob = null
        countdownRemaining = null
    }

    /** Finds hip, knee and ankle on the phone. Nothing is uploaded and no model is called. */
    suspend fun analyzeWholeBody(path: String) {
        val type = selectedType
        val bitmap = withContext(Dispatchers.IO) { KneePoseEstimator.loadUpright(path) }
        val estimate = bitmap?.let {
            KneePoseEstimator.estimate(it, if (type == MeasurementType.FLEXION) KneeBend.FLEXION else KneeBend.EXTENSION, requestedKnee)
        }
        wholeBodyBitmap = bitmap
        poseResult = null
        if (estimate == null) {
            wholeBodyKeypoints = null
            screenState = MeasureScreenState.RETAKE
        } else {
            wholeBodyKeypoints = estimate.keypoints
            wholeBodyNote = KneeGeometry.resultNote(estimate, requestedKnee)
            wholeBodyAdjusted = false
            screenState = MeasureScreenState.RESULT
        }
    }

    // The mode can't change under a running countdown, and the screen stays on while it counts.
    val view = LocalView.current
    DisposableEffect(countdownRemaining != null) {
        view.keepScreenOn = countdownRemaining != null
        onDispose { view.keepScreenOn = false }
    }
    DisposableEffect(Unit) {
        onDispose {
            countdownJob?.cancel()
            beeper.finish()
        }
    }

    // Photo picker launcher
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        uri?.let {
            val type = selectedType
            AnalyticsService.measurementStarted(type, AnalyticsService.Source.LIBRARY)
            scope.launch {
                var stage = AnalyticsService.FailureStage.CAPTURE
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
                    if (measureMode == MeasureMode.ACCURATE) {
                        analyzeWholeBody(tempFile.absolutePath)
                        return@launch
                    }
                    stage = AnalyticsService.FailureStage.ANALYSIS
                    val result = GeminiPoseService.detectKneeAngle(
                        imagePath = tempFile.absolutePath,
                        injuredKnee = userProfile?.injuredKnee?.name?.lowercase(),
                        injuryType = userProfile?.injuryType?.firestoreValue
                    )
                    AnalyticsService.measurementAnalyzed(type, AnalyticsService.Source.LIBRARY)
                    poseResult = result
                    screenState = MeasureScreenState.RESULT
                } catch (e: Exception) {
                    AnalyticsService.measurementFailed(type, AnalyticsService.Source.LIBRARY, stage)
                    errorMessage = e.message ?: "Failed to analyze image"
                    screenState = MeasureScreenState.CAMERA
                }
            }
        }
    }

    fun handlePickFromLibrary() {
        cancelCountdown()
        val testPhoto = testHooks?.photoPath
        if (testPhoto != null && measureMode == MeasureMode.ACCURATE) {
            scope.launch {
                capturedImagePath = testPhoto
                screenState = MeasureScreenState.PROCESSING
                analyzeWholeBody(testPhoto)
            }
            return
        }
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
        val type = selectedType
        AnalyticsService.measurementStarted(type, AnalyticsService.Source.CAMERA)
        scope.launch {
            var stage = AnalyticsService.FailureStage.CAPTURE
            try {
                errorMessage = null
                // Grab frozen frame from preview before switching to processing
                frozenPreviewBitmap = cameraService.getPreviewBitmap()
                // Show processing state immediately so user knows photo was taken
                screenState = MeasureScreenState.PROCESSING
                val path = cameraService.capturePhoto()
                capturedImagePath = path
                if (measureMode == MeasureMode.ACCURATE) {
                    analyzeWholeBody(path)
                    return@launch
                }
                stage = AnalyticsService.FailureStage.ANALYSIS
                val result = GeminiPoseService.detectKneeAngle(
                    imagePath = path,
                    injuredKnee = userProfile?.injuredKnee?.name?.lowercase(),
                    injuryType = userProfile?.injuryType?.firestoreValue
                )
                AnalyticsService.measurementAnalyzed(type, AnalyticsService.Source.CAMERA)
                poseResult = result
                screenState = MeasureScreenState.RESULT
            } catch (e: Exception) {
                AnalyticsService.measurementFailed(type, AnalyticsService.Source.CAMERA, stage)
                hapticError()
                errorMessage = e.message ?: "Failed to analyze image"
                screenState = MeasureScreenState.CAMERA
            }
        }
    }

    /** The shutter: in Whole-body mode with the self-timer on it counts down first; tap again to cancel. */
    fun handleCapturePressed() {
        if (countdownRemaining != null) {
            cancelCountdown()
            return
        }
        if (measureMode == MeasureMode.ACCURATE && selfTimerSeconds > 0) {
            val seconds = selfTimerSeconds
            countdownJob = scope.launch {
                beeper.prepare()
                for (remaining in seconds downTo 1) {
                    countdownRemaining = remaining
                    beeper.playTick()
                    delay(1000)
                }
                beeper.playShutter()
                countdownRemaining = null
                countdownJob = null
                handleCapture()
            }
        } else {
            handleCapture()
        }
    }

    /** From the retake screen: measure this one photo the original way instead. */
    fun measureWithStandardInstead() {
        val path = capturedImagePath ?: return
        val type = selectedType
        scope.launch {
            try {
                wholeBodyKeypoints = null
                wholeBodyBitmap = null
                screenState = MeasureScreenState.PROCESSING
                val result = GeminiPoseService.detectKneeAngle(
                    imagePath = path,
                    injuredKnee = userProfile?.injuredKnee?.name?.lowercase(),
                    injuryType = userProfile?.injuryType?.firestoreValue
                )
                poseResult = result
                screenState = MeasureScreenState.RESULT
            } catch (e: Exception) {
                AnalyticsService.measurementFailed(type, null, AnalyticsService.FailureStage.ANALYSIS)
                hapticError()
                errorMessage = e.message ?: "Failed to analyze image"
                screenState = MeasureScreenState.CAMERA
            }
        }
    }

    fun handleSave() {
        scope.launch {
            val uid = AuthService.currentUserId ?: return@launch
            // Whole-body mode saves the angle of the dots as they are now; Standard photo the model's.
            val isWholeBody = wholeBodyKeypoints != null
            val angle = (if (isWholeBody) wholeBodyAngle else poseResult?.angle) ?: return@launch
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
                    angle = angle,
                    weekPostOp = weekPostOp,
                    photoUrl = photoUrl,
                    // Standard photo writes neither field, exactly as before.
                    method = if (isWholeBody) Measurement.METHOD_ON_DEVICE else null,
                    adjusted = if (isWholeBody) wholeBodyAdjusted else null
                )
                FirestoreService.saveMeasurement(uid, measurement)
                // Reset with success feedback
                hapticSuccess()
                successMessage = "Measurement saved!"
                screenState = MeasureScreenState.CAMERA
                capturedImagePath = null
                poseResult = null
                wholeBodyKeypoints = null
                wholeBodyBitmap = null
                wholeBodyNote = null

                // In-app review prompt
                val prefs = context.getSharedPreferences("acl_rehab_prefs", android.content.Context.MODE_PRIVATE)
                val newCount = prefs.getInt("measurement_save_count", 0) + 1
                prefs.edit().putInt("measurement_save_count", newCount).apply()
                AnalyticsService.measurementSaved(measurement.type, newCount)

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
                AnalyticsService.measurementFailed(selectedType, null, AnalyticsService.FailureStage.SAVE)
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
        wholeBodyKeypoints = null
        wholeBodyBitmap = null
        wholeBodyNote = null
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
                        onCapture = { handleCapturePressed() },
                        onPickFromLibrary = { handlePickFromLibrary() },
                        onFlipCamera = { cancelCountdown(); cameraService.flipCamera(lifecycleOwner) },
                        isProcessing = screenState == MeasureScreenState.PROCESSING,
                        capturedImagePath = capturedImagePath,
                        frozenPreviewBitmap = frozenPreviewBitmap,
                        mode = measureMode,
                        onModeRowClick = { cancelCountdown(); showModeSheet = true },
                        onShowPoseGuide = { cancelCountdown(); showPoseGuide = true },
                        selfTimerSeconds = selfTimerSeconds,
                        onCycleSelfTimer = {
                            cancelCountdown()
                            selfTimerSeconds = when (selfTimerSeconds) { 0 -> 5; 5 -> 10; else -> 0 }
                            if (testHooks == null) prefs.edit().putInt(MeasureMode.KEY_SELF_TIMER, selfTimerSeconds).apply()
                        },
                        countdownRemaining = countdownRemaining
                    )
                }
                MeasureScreenState.RETAKE -> {
                    WholeBodyRetakeView(
                        bitmap = wholeBodyBitmap,
                        measurementType = selectedType,
                        onRetake = {
                            AnalyticsService.measurementRetaken(selectedType)
                            handleRetake()
                        },
                        onUseStandard = { measureWithStandardInstead() },
                        onShowPoseGuide = { showPoseGuide = true }
                    )
                }
                MeasureScreenState.RESULT, MeasureScreenState.SAVING -> {
                    ResultView(
                        imagePath = capturedImagePath,
                        angle = wholeBodyAngle ?: poseResult?.angle ?: 0,
                        goalAngle = selectedType.goalAngle,
                        measurementType = selectedType,
                        isSaving = screenState == MeasureScreenState.SAVING,
                        wholeBodyBitmap = wholeBodyBitmap,
                        wholeBodyKeypoints = wholeBodyKeypoints,
                        onKeypointsChange = { wholeBodyKeypoints = it },
                        onKeypointsEdited = { wholeBodyAdjusted = true },
                        wholeBodyNote = wholeBodyNote,
                        onSave = { handleSave() },
                        onRetake = {
                            AnalyticsService.measurementRetaken(selectedType)
                            handleRetake()
                        }
                    )
                }
            }
        }

        if (showModeSheet) {
            MeasureModeSheet(
                selection = measureMode,
                onSelect = {
                    measureMode = it
                    if (testHooks == null) MeasureMode.save(context, it)
                },
                onDone = {
                    showModeSheet = false
                    // The first switch to Whole-body mode shows how to pose, once.
                    if (measureMode == MeasureMode.ACCURATE && !prefs.getBoolean(MeasureMode.KEY_POSE_GUIDE_SEEN, false)) {
                        prefs.edit().putBoolean(MeasureMode.KEY_POSE_GUIDE_SEEN, true).apply()
                        showPoseGuide = true
                    }
                }
            )
        }
        if (showPoseGuide) {
            PoseGuideSheet(
                type = selectedType,
                side = testHooks?.injuredKnee ?: userProfile?.injuredKnee,
                onDone = { showPoseGuide = false }
            )
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
    frozenPreviewBitmap: android.graphics.Bitmap? = null,
    mode: MeasureMode = MeasureMode.STANDARD,
    onModeRowClick: () -> Unit = {},
    onShowPoseGuide: () -> Unit = {},
    selfTimerSeconds: Int = 0,
    onCycleSelfTimer: () -> Unit = {},
    countdownRemaining: Int? = null
) {
    val cameraAvailable = cameraService.cameraAvailable
    val canCapture = cameraPermissionGranted && cameraAvailable
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

        Spacer(modifier = Modifier.height(12.dp))

        // Measuring method (Standard photo by default)
        MeasureModeRow(mode = mode, onClick = onModeRowClick)

        Spacer(modifier = Modifier.height(12.dp))

        // Camera Preview or Permission Request - fills remaining space
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface),
            contentAlignment = Alignment.Center
        ) {
            if (cameraPermissionGranted && !cameraAvailable && !isProcessing) {
                // No camera on this device: the library still works.
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                    modifier = Modifier.testTag("measure.noCamera")
                ) {
                    Text(text = "Camera not available", color = AppColors.Text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Use the photo library button below instead",
                        color = AppColors.TextSecondary,
                        fontSize = 14.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 32.dp)
                    )
                }
            } else if (cameraPermissionGranted) {
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
                    AnalyzingStatus(mode)
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
            // Whole-body mode extras, on top of the preview: how to pose, self-timer, the count.
            if (mode == MeasureMode.ACCURATE && !isProcessing) {
                if (countdownRemaining != null) {
                    Column(
                        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(
                            text = "$countdownRemaining",
                            fontSize = 120.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            modifier = Modifier.testTag("measure.countdown")
                        )
                        Text(
                            text = "Get into position. Tap the button to cancel.",
                            fontSize = 15.sp,
                            color = Color.White,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(horizontal = 24.dp)
                        )
                    }
                }
                Row(
                    modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    CameraPill("How to pose", "How to pose", isOn = false, tag = "measure.poseGuide", onClick = onShowPoseGuide)
                    CameraPill(
                        text = if (selfTimerSeconds == 0) "Timer off" else "Timer ${selfTimerSeconds}s",
                        description = if (selfTimerSeconds == 0) "Self-timer off" else "Self-timer $selfTimerSeconds seconds",
                        isOn = selfTimerSeconds > 0,
                        tag = "measure.selfTimer",
                        onClick = onCycleSelfTimer
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Instructions
        Text(
            text = mode.instruction(selectedType),
            color = AppColors.TextSecondary,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .testTag("measure.instruction")
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
                    .testTag("measure.library")
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
                    .clickable(enabled = canCapture) { onCapture() }
                    .semantics { contentDescription = if (countdownRemaining != null) "Cancel self-timer" else "Take photo" }
                    .testTag("measure.capture"),
                contentAlignment = Alignment.Center
            ) {
                // Outer ring
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(AppColors.Text.copy(alpha = if (canCapture) 1f else 0.4f)),
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
                        // Red fill (a square "stop" while the self-timer is counting)
                        Box(
                            modifier = Modifier
                                .size(if (countdownRemaining != null) 30.dp else 64.dp)
                                .clip(if (countdownRemaining != null) RoundedCornerShape(6.dp) else CircleShape)
                                .background(
                                    if (canCapture) AppColors.Primary
                                    else AppColors.Primary.copy(alpha = 0.4f)
                                )
                        )
                    }
                }
            }

            // Flip camera (right)
            IconButton(
                onClick = onFlipCamera,
                enabled = canCapture,
                modifier = Modifier
                    .size(48.dp)
                    .background(AppColors.Surface, RoundedCornerShape(12.dp))
            ) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = "Switch camera",
                    tint = if (canCapture) AppColors.Text else AppColors.Text.copy(alpha = 0.4f),
                    modifier = Modifier.size(24.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

/** Analysis steps as (message, starts at ms). Keep in sync with iOS `AnalyzingStatusView`. */
private val analyzingSteps = listOf(
    "Analyzing your photo..." to 0L,
    "Measuring your knee angle..." to 4_000L,
    "Almost done..." to 11_000L
)

/**
 * Spinner shown while the photo is analyzed. Analysis takes ~15s, so the message advances
 * through steps to show progress instead of sitting on a static "Analyzing...".
 */
@Composable
private fun AnalyzingStatus(mode: MeasureMode = MeasureMode.STANDARD) {
    if (mode == MeasureMode.ACCURATE) {
        // Whole-body mode runs on the phone and takes a second or two.
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(modifier = Modifier.size(40.dp), color = AppColors.Primary, strokeWidth = 3.dp)
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Finding your hip, knee and ankle...",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.Text,
                textAlign = TextAlign.Center
            )
        }
        return
    }
    var stepIndex by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        for (index in 1 until analyzingSteps.size) {
            kotlinx.coroutines.delay(analyzingSteps[index].second - analyzingSteps[index - 1].second)
            stepIndex = index
        }
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        CircularProgressIndicator(
            modifier = Modifier.size(40.dp),
            color = AppColors.Primary,
            strokeWidth = 3.dp
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = analyzingSteps[stepIndex].first,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.Text
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "This usually takes about 15 seconds",
            fontSize = 13.sp,
            color = AppColors.TextSecondary,
            textAlign = TextAlign.Center
        )
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
    onRetake: () -> Unit,
    wholeBodyBitmap: android.graphics.Bitmap? = null,
    wholeBodyKeypoints: KneeKeypoints? = null,
    onKeypointsChange: (KneeKeypoints) -> Unit = {},
    onKeypointsEdited: () -> Unit = {},
    wholeBodyNote: String? = null
) {
    val isWholeBody = wholeBodyBitmap != null && wholeBodyKeypoints != null
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
        // In Whole-body mode the measured lines are drawn on it and can be adjusted.
        if (isWholeBody) {
            KneeKeypointEditor(
                bitmap = wholeBodyBitmap!!,
                keypoints = wholeBodyKeypoints!!,
                onChange = onKeypointsChange,
                onEdit = onKeypointsEdited,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth().weight(1f)
            )
        } else Box(
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
                color = AppColors.Text,
                modifier = Modifier.testTag("measure.angle")
            )
            Text(
                text = "Goal: ${goalAngle}°",
                fontSize = 17.sp,
                color = AppColors.TextTertiary
            )
            if (isWholeBody) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = wholeBodyNote ?: "Measured on your phone from the dots on the photo. Drag a dot if it's off. Pinch the photo to zoom in.",
                    fontSize = 13.sp,
                    color = if (wholeBodyNote == null) AppColors.TextSecondary else AppColors.Warning,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.testTag("measure.accurateNote")
                )
            }
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

/** Whole-body mode only: the phone couldn't find a hip, knee and ankle in the photo. */
@Composable
private fun WholeBodyRetakeView(
    bitmap: android.graphics.Bitmap?,
    measurementType: MeasurementType,
    onRetake: () -> Unit,
    onUseStandard: () -> Unit,
    onShowPoseGuide: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Couldn't measure this photo",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(16.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface),
            contentAlignment = Alignment.Center
        ) {
            bitmap?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = "Captured photo",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit
                )
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.Surface)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Your phone couldn't find your hip, knee and ankle.",
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.Text,
                modifier = Modifier.testTag("retake.message")
            )
            Text(
                text = "Whole-body mode needs your whole body in the photo, head to feet, taken from the side.",
                fontSize = 15.sp,
                color = AppColors.TextSecondary
            )
            Text(
                text = "How to pose for ${measurementType.displayName.lowercase()}",
                fontSize = 15.sp,
                color = AppColors.Primary,
                modifier = Modifier.clickable(onClick = onShowPoseGuide).testTag("retake.poseGuide")
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Button(
            onClick = onRetake,
            modifier = Modifier.fillMaxWidth().height(52.dp).testTag("retake.retake"),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
            shape = RoundedCornerShape(16.dp)
        ) { Text("Retake", fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedButton(
            onClick = onUseStandard,
            modifier = Modifier.fillMaxWidth().height(52.dp).testTag("retake.useStandard"),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.Text)
        ) { Text("Measure with Standard photo", fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
    }
}
