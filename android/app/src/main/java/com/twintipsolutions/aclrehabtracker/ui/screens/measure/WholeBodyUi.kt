package com.twintipsolutions.aclrehabtracker.ui.screens.measure

import android.graphics.Bitmap
import android.media.AudioManager
import android.media.ToneGenerator
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.twintipsolutions.aclrehabtracker.data.model.KneeSide
import com.twintipsolutions.aclrehabtracker.data.model.MeasureMode
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.pose.KneeKeypoints
import com.twintipsolutions.aclrehabtracker.data.pose.NPoint
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import kotlin.math.min
import kotlin.math.roundToInt

// Everything Whole-body mode adds to the Measure tab. None of it shows in Standard photo.
// The Android twin of iOS MeasureModePicker.swift, PoseGuide.swift and KneeKeypointEditor.swift.

/** The small "Beta" tag shown next to the Whole-body mode name. */
@Composable
fun BetaTag(modifier: Modifier = Modifier) {
    Text(
        text = "Beta",
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.Primary,
        maxLines = 1,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(AppColors.Primary.copy(alpha = 0.15f))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

@Composable
private fun PlainTag(text: String) {
    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.TextSecondary,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(AppColors.SurfaceLight)
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

/** The row on the Measure tab that shows which method is in use and opens the chooser. */
@Composable
fun MeasureModeRow(mode: MeasureMode, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(AppColors.Surface)
            .clickable(onClickLabel = "Opens the method chooser", onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = "Measuring method: ${mode.spokenTitle}" }
            .testTag("measureMode.row")
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // The name takes whatever width "Change" leaves, and only then shortens.
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("Method", fontSize = 15.sp, color = AppColors.TextSecondary, maxLines = 1)
            Text(
                mode.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false)
            )
            if (mode.isBeta) BetaTag()
        }
        Text("Change", fontSize = 15.sp, color = AppColors.Primary, maxLines = 1)
    }
}

/** Lets the user pick a measuring method and explains, briefly, what each one does. */
@Composable
fun MeasureModeSheet(selection: MeasureMode, onSelect: (MeasureMode) -> Unit, onDone: () -> Unit) {
    Dialog(onDismissRequest = onDone, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.Background)
                .systemBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("How do you want to measure?", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = AppColors.Text)
            Text(
                "Both methods save to the same history. You can switch any time.",
                fontSize = 15.sp, color = AppColors.TextSecondary
            )
            MeasureMode.entries.forEach { mode ->
                val isSelected = mode == selection
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(AppColors.Surface)
                        .border(2.dp, if (isSelected) AppColors.Primary else Color.Transparent, RoundedCornerShape(16.dp))
                        .clickable { onSelect(mode) }
                        .semantics(mergeDescendants = true) {
                            contentDescription = "${mode.spokenTitle}. ${mode.summary}"
                            stateDescription = if (isSelected) "Selected" else "Not selected"
                        }
                        .testTag("measureMode.${mode.key}")
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(mode.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
                            if (mode == MeasureMode.STANDARD) PlainTag("Default")
                            if (mode.isBeta) BetaTag()
                        }
                        Text(mode.summary, fontSize = 15.sp, color = AppColors.TextSecondary)
                    }
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .clip(CircleShape)
                            .background(if (isSelected) AppColors.Primary else Color.Transparent)
                            .border(2.dp, if (isSelected) AppColors.Primary else AppColors.Border, CircleShape)
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(AppColors.Surface)
                    .testTag("measureMode.explainer")
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("HOW WHOLE-BODY MODE WORKS", fontSize = 13.sp, color = AppColors.TextSecondary, letterSpacing = 1.sp)
                    BetaTag()
                }
                ExplainerStep(
                    1, "Whole body, side-on",
                    "Prop your phone up or ask someone to take the photo. Head to feet in the picture, with the camera looking at the side of your leg."
                )
                ExplainerStep(
                    2, "Your phone measures the angle",
                    "It marks your hip, knee and ankle and measures the angle between the lines. You see the lines on your photo and can drag a dot if one is off. Pinch the photo to zoom in."
                )
                Text(
                    "A close-up of just your knee won't work in this mode. Use Standard photo for those. Either way, this is for personal tracking and is not a medical device.",
                    fontSize = 13.sp, color = AppColors.TextTertiary
                )
            }

            Button(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth().height(52.dp).testTag("measureMode.done"),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
                shape = RoundedCornerShape(16.dp)
            ) { Text("Done", fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
        }
    }
}

@Composable
private fun ExplainerStep(number: Int, title: String, detail: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Text("$number. $title", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
        Text(detail, fontSize = 15.sp, color = AppColors.TextSecondary)
    }
}

/** Small capsule buttons that sit on top of the camera preview. */
@Composable
fun CameraPill(text: String, description: String, isOn: Boolean, tag: String, onClick: () -> Unit) {
    Text(
        text = text,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.White,
        maxLines = 1,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (isOn) AppColors.Primary else Color.Black.copy(alpha = 0.55f))
            .clickable(onClick = onClick)
            .semantics { contentDescription = description }
            .testTag(tag)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    )
}

/**
 * A simple side-on drawing of the pose for one movement, as the phone should see it. Drawn for the
 * right knee (head at the left, right leg nearest the camera) and mirrored for the left.
 */
@Composable
fun PoseIllustration(type: MeasurementType, side: KneeSide?, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier.fillMaxWidth().aspectRatio(300f / 112f).clearAndSetSemantics {}) {
        // Design space is 300 x 112 (drawn with the floor at y = 124, so shifted up by 34).
        val s = min(size.width / 300f, size.height / 112f)
        val flip = if (side == KneeSide.LEFT) -1f else 1f
        withTransform({
            scale(flip, 1f, pivot = Offset(size.width / 2, size.height / 2))
            translate((size.width - 300 * s) / 2, (size.height - 112 * s) / 2)
        }) {
            fun p(x: Float, y: Float) = Offset(x * s, (y - 34) * s)
            val grey = AppColors.TextSecondary
            val accent = AppColors.Primary
            val limb = 9 * s
            // The phone's view: whole body inside the frame.
            drawRoundRect(
                AppColors.Border, topLeft = p(6f, 38f), size = Size(288 * s, 104 * s),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(12 * s),
                style = Stroke(2 * s, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6 * s, 5 * s)))
            )
            drawLine(AppColors.Border, p(18f, 124f), p(282f, 124f), 2 * s)
            // Far leg, flat on the floor.
            drawLine(grey, p(132f, 114f), p(250f, 116f), limb, StrokeCap.Round)
            drawLine(grey, p(250f, 116f), p(256f, 101f), limb, StrokeCap.Round)
            // Head, torso and arm.
            drawCircle(grey, 13 * s, p(39f, 105f))
            drawLine(grey, p(62f, 110f), p(132f, 112f), 15 * s, StrokeCap.Round)
            drawLine(AppColors.TextTertiary, p(66f, 116f), p(112f, 119f), 6 * s, StrokeCap.Round)
            // The leg being measured, nearest the camera.
            val flexion = type == MeasurementType.FLEXION
            val hip = p(132f, 110f)
            val knee = if (flexion) p(176f, 58f) else p(191f, 110f)
            val ankle = if (flexion) p(200f, 112f) else p(250f, 110f)
            val toe = if (flexion) p(217f, 113f) else p(256f, 95f)
            drawLine(accent, hip, knee, limb, StrokeCap.Round)
            drawLine(accent, knee, ankle, limb, StrokeCap.Round)
            drawLine(accent, ankle, toe, limb, StrokeCap.Round)
            listOf(hip, knee, ankle).forEach {
                drawCircle(Color.White, 6.5f * s, it)
                drawCircle(accent, 4 * s, it)
            }
        }
    }
}

/** "How to pose" for Whole-body mode: one drawing per movement and four short rules. */
@Composable
fun PoseGuideSheet(type: MeasurementType, side: KneeSide?, onDone: () -> Unit) {
    val legName = side?.let { "Your ${it.displayName.lowercase()} leg" } ?: "The leg you're measuring"
    Dialog(onDismissRequest = onDone, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.Background)
                .systemBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("How to pose", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = AppColors.Text)
                BetaTag()
            }
            // The movement being measured now comes first.
            val order = if (type == MeasurementType.FLEXION) listOf(MeasurementType.FLEXION, MeasurementType.EXTENSION)
            else listOf(MeasurementType.EXTENSION, MeasurementType.FLEXION)
            order.forEach { movement ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(AppColors.Surface)
                        .border(2.dp, if (movement == type) AppColors.Primary else Color.Transparent, RoundedCornerShape(16.dp))
                        .testTag("poseGuide.${movement.name.lowercase()}")
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(movement.displayName, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
                        if (movement == type) PlainTag("Measuring now")
                    }
                    PoseIllustration(movement, side)
                    Text(
                        if (movement == MeasurementType.FLEXION)
                            "Lie on your back and slide your heel in to bend the knee as far as it goes."
                        else "Lie on your back and straighten the knee as far as it goes.",
                        fontSize = 15.sp, color = AppColors.TextSecondary
                    )
                }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(AppColors.Surface)
                    .testTag("poseGuide.rules")
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                listOf(
                    "Side-on to the camera",
                    "Whole body in the frame, head to feet",
                    "Phone propped at knee height",
                    "$legName nearest the camera",
                ).forEach { Text("•  $it", fontSize = 15.sp, color = AppColors.Text) }
            }
            Text(
                "Sitting or standing works too, as long as the camera sees you from the side.",
                fontSize = 13.sp, color = AppColors.TextTertiary
            )
            Button(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth().height(52.dp).testTag("poseGuide.done"),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
                shape = RoundedCornerShape(16.dp)
            ) { Text("Got it", fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
        }
    }
}

/**
 * The self-timer's sound: a short beep each second and a longer one when the photo is taken. It
 * uses the media volume, so it is heard even when the ringer is silent; the whole point is hearing
 * the count from across the room. Sound is best-effort: a device without audio must not crash.
 */
class CountdownBeeper {
    private var tone: ToneGenerator? = null

    fun prepare() {
        if (tone == null) tone = runCatching { ToneGenerator(AudioManager.STREAM_MUSIC, 100) }.getOrNull()
    }

    fun playTick() { runCatching { tone?.startTone(ToneGenerator.TONE_PROP_BEEP, 120) } }

    fun playShutter() { runCatching { tone?.startTone(ToneGenerator.TONE_DTMF_D, 450) } }

    fun finish() {
        runCatching { tone?.release() }
        tone = null
    }
}

enum class KneeJoint(val label: String) { HIP("Hip"), KNEE("Knee"), ANKLE("Ankle") }

private const val MAX_ZOOM = 5f
private const val DOUBLE_TAP_ZOOM = 2.5f

/**
 * Shows the photo with hip, knee and ankle drawn on it. Each dot can be dragged, and the angle
 * updates as it moves, because the number is computed from the same three points.
 *
 * The photo can be pinched to zoom and dragged to pan, and double tap zooms in or back out. Zooming
 * only changes where things are drawn: the dots are stored as fractions of the image, never as
 * screen positions, so the angle is the same at any zoom. The dots keep their size on screen.
 */
@Composable
fun KneeKeypointEditor(
    bitmap: Bitmap,
    keypoints: KneeKeypoints,
    onChange: (KneeKeypoints) -> Unit,
    onEdit: () -> Unit,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val image = remember(bitmap) { bitmap.asImageBitmap() }
    val current by rememberUpdatedState(keypoints)
    val isEnabled by rememberUpdatedState(enabled)
    var zoom by remember(bitmap) { mutableFloatStateOf(1f) }
    var offset by remember(bitmap) { mutableStateOf(Offset.Zero) }
    var active by remember { mutableStateOf<KneeJoint?>(null) }
    val density = LocalDensity.current

    BoxWithConstraints(modifier = modifier.clip(RoundedCornerShape(16.dp)).background(AppColors.Surface)) {
        val cw = constraints.maxWidth.toFloat()
        val ch = constraints.maxHeight.toFloat()
        val fit = min(cw / bitmap.width, ch / bitmap.height)
        val baseW = bitmap.width * fit
        val baseH = bitmap.height * fit
        val base = Rect(Offset((cw - baseW) / 2, (ch - baseH) / 2), Size(baseW, baseH))
        val isZoomed = zoom > 1.01f

        fun clamp(o: Offset, z: Float) = Offset(
            o.x.coerceIn(-baseW * (z - 1) / 2, baseW * (z - 1) / 2),
            o.y.coerceIn(-baseH * (z - 1) / 2, baseH * (z - 1) / 2),
        )
        /** Sets the zoom so the part of the photo under `anchor` stays under it, then pans. */
        fun zoomTo(target: Float, anchor: Offset, pan: Offset = Offset.Zero) {
            val newZoom = target.coerceIn(1f, MAX_ZOOM)
            val rel = (anchor - base.center - offset) / zoom
            zoom = newZoom
            offset = if (newZoom <= 1.01f) Offset.Zero else clamp(anchor - base.center - rel * newZoom + pan, newZoom)
        }
        // Where the (zoomed) photo sits. Read in draw and gesture code, so it follows the state.
        fun frame() = Rect(
            Offset(base.center.x + offset.x - baseW * zoom / 2, base.center.y + offset.y - baseH * zoom / 2),
            Size(baseW * zoom, baseH * zoom)
        )
        fun toScreen(p: NPoint, f: Rect) = Offset(f.left + p.x.toFloat() * f.width, f.top + p.y.toFloat() * f.height)

        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .testTag("keypoint.photo")
                .semantics {
                    contentDescription = "Photo with hip, knee and ankle marked"
                    stateDescription = if (isZoomed) "Zoomed in %.1f times".format(zoom) else "Not zoomed"
                }
                .pointerInput(bitmap, cw, ch) {
                    detectTransformGestures { centroid, pan, gestureZoom, _ ->
                        if (gestureZoom != 1f || zoom > 1.01f) zoomTo(zoom * gestureZoom, centroid, pan)
                    }
                }
                .pointerInput(bitmap, cw, ch) {
                    detectTapGestures(onDoubleTap = { tap ->
                        if (zoom > 1.01f) { zoom = 1f; offset = Offset.Zero } else zoomTo(DOUBLE_TAP_ZOOM, tap)
                    })
                }
        ) {
            val f = frame()
            clipRect(base.left, base.top, base.right, base.bottom) {
                drawImage(
                    image,
                    dstOffset = IntOffset(f.left.roundToInt(), f.top.roundToInt()),
                    dstSize = IntSize(f.width.roundToInt(), f.height.roundToInt())
                )
                val hip = toScreen(current.hip, f)
                val knee = toScreen(current.knee, f)
                val ankle = toScreen(current.ankle, f)
                // White underlay so the lines read on any photo.
                drawLine(Color.White, hip, knee, 6.dp.toPx(), StrokeCap.Round)
                drawLine(Color.White, knee, ankle, 6.dp.toPx(), StrokeCap.Round)
                drawLine(AppColors.Primary, hip, knee, 3.dp.toPx(), StrokeCap.Round)
                drawLine(AppColors.Primary, knee, ankle, 3.dp.toPx(), StrokeCap.Round)
            }
        }

        val touch = 52.dp
        val touchPx = with(density) { touch.toPx() }
        val visible = base.inflate(with(density) { 12.dp.toPx() })
        KneeJoint.entries.forEach { joint ->
            val f = frame()
            val point = when (joint) {
                KneeJoint.HIP -> keypoints.hip
                KneeJoint.KNEE -> keypoints.knee
                KneeJoint.ANKLE -> keypoints.ankle
            }
            val at = toScreen(point, f)
            // A dot that is zoomed out of view is not shown and can't catch touches.
            if (visible.contains(at) || active == joint) {
                val isActive = active == joint
                Box(
                    modifier = Modifier
                        .offset { IntOffset((at.x - touchPx / 2).roundToInt(), (at.y - touchPx / 2).roundToInt()) }
                        .size(touch)
                        .testTag("keypoint.${joint.name.lowercase()}")
                        .semantics { contentDescription = "${joint.label} point. Drag to adjust" }
                        .pointerInput(joint, bitmap, cw, ch) {
                            detectDragGestures(
                                onDragStart = { active = joint },
                                onDragEnd = { active = null; onEdit() },
                                onDragCancel = { active = null },
                            ) { change, drag ->
                                change.consume()
                                if (!isEnabled) return@detectDragGestures
                                val now = frame()
                                val p = when (joint) {
                                    KneeJoint.HIP -> current.hip
                                    KneeJoint.KNEE -> current.knee
                                    KneeJoint.ANKLE -> current.ankle
                                }
                                // Stay inside the part of the photo that is showing, then turn the
                                // screen position into a fraction of the (zoomed) image.
                                val moved = toScreen(p, now) + drag
                                val x = moved.x.coerceIn(base.left, base.right)
                                val y = moved.y.coerceIn(base.top, base.bottom)
                                val next = NPoint(((x - now.left) / now.width).toDouble(), ((y - now.top) / now.height).toDouble()).clamped
                                onChange(
                                    when (joint) {
                                        KneeJoint.HIP -> current.copy(hip = next)
                                        KneeJoint.KNEE -> current.copy(knee = next)
                                        KneeJoint.ANKLE -> current.copy(ankle = next)
                                    }
                                )
                            }
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Box(Modifier.size(if (isActive) 30.dp else 24.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(if (isActive) 20.dp else 15.dp).clip(CircleShape).background(AppColors.Primary))
                    }
                }
            }
        }

        if (isZoomed) {
            Box(modifier = Modifier.fillMaxSize().padding(10.dp), contentAlignment = Alignment.TopEnd) {
                CameraPill("Reset zoom", "Reset zoom, %.1fx".format(zoom), isOn = false, tag = "keypoint.resetZoom") {
                    zoom = 1f
                    offset = Offset.Zero
                }
            }
        }
    }
}
