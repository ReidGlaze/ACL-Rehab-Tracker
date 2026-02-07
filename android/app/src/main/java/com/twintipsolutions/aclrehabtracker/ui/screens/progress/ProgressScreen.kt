package com.twintipsolutions.aclrehabtracker.ui.screens.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.service.AuthService
import com.twintipsolutions.aclrehabtracker.data.service.FirestoreService
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import com.twintipsolutions.aclrehabtracker.util.DateHelpers
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgressScreen() {
    var measurements by remember { mutableStateOf<List<Measurement>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    suspend fun loadData() {
        val uid = AuthService.currentUserId
        if (uid == null) {
            isLoading = false
            return
        }
        try {
            measurements = FirestoreService.getMeasurements(uid)
        } catch (_: Exception) {
            errorMessage = "Failed to load progress data."
        }
        isLoading = false
    }

    LaunchedEffect(Unit) { loadData() }

    val latestExtension = remember(measurements) {
        measurements.firstOrNull { it.type == MeasurementType.EXTENSION }
    }
    val latestFlexion = remember(measurements) {
        measurements.firstOrNull { it.type == MeasurementType.FLEXION }
    }

    // Compute daily averages for chart
    val extensionChartData = remember(measurements) {
        computeDailyAverages(measurements.filter { it.type == MeasurementType.EXTENSION })
    }
    val flexionChartData = remember(measurements) {
        computeDailyAverages(measurements.filter { it.type == MeasurementType.FLEXION })
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text("Error") },
            text = { Text(errorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text("OK") }
            }
        )
    }

    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = {
            scope.launch {
                isRefreshing = true
                loadData()
                isRefreshing = false
            }
        },
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
    ) {
    if (isLoading) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator(color = AppColors.Primary)
        }
    } else {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp)
    ) {
        // Header
        Text(
            text = "Progress",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Current Status Cards
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            StatusCard(
                type = MeasurementType.EXTENSION,
                value = latestExtension?.angle,
                color = AppColors.ExtensionBlue,
                modifier = Modifier.weight(1f)
            )
            StatusCard(
                type = MeasurementType.FLEXION,
                value = latestFlexion?.angle,
                color = AppColors.FlexionPink,
                modifier = Modifier.weight(1f)
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Dual Line Chart
        DualLineChart(
            extensionData = extensionChartData,
            flexionData = flexionChartData
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Stats
        StatsSection(measurements)
    }
    } // end else (not loading)
    }
}

private fun computeDailyAverages(measurements: List<Measurement>): List<Pair<Float, Float>> {
    if (measurements.isEmpty()) return emptyList()

    val sorted = measurements.sortedBy { it.timestamp.time }
    val firstTime = sorted.first().timestamp.time.toFloat()
    val grouped = sorted.groupBy { DateHelpers.dateKey(it.timestamp) }

    return grouped.entries.sortedBy { it.key }.map { (_, dayMeasurements) ->
        val avgTime = dayMeasurements.map { it.timestamp.time }.average().toFloat()
        val avgAngle = dayMeasurements.map { it.angle }.average().toFloat()
        val dayOffset = (avgTime - firstTime) / (1000f * 60f * 60f * 24f) // days from start
        dayOffset to avgAngle
    }
}

@Composable
private fun StatusCard(
    type: MeasurementType,
    value: Int?,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(AppColors.Surface)
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = type.displayName.uppercase(),
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = color,
            letterSpacing = 1.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = value?.let { "$it°" } ?: "--",
            fontSize = 36.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = if (value != null) "Goal: ${type.goalAngle}°" else "No data",
            fontSize = 11.sp,
            color = AppColors.TextTertiary
        )

        // Progress bar
        if (value != null) {
            Spacer(modifier = Modifier.height(8.dp))
            val progress = if (type == MeasurementType.EXTENSION) {
                (1f - value / 30f).coerceIn(0f, 1f)
            } else {
                (value / 135f).coerceIn(0f, 1f)
            }
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = color,
                trackColor = AppColors.SurfaceLight
            )
        }
    }
}

@Composable
private fun DualLineChart(
    extensionData: List<Pair<Float, Float>>,
    flexionData: List<Pair<Float, Float>>
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(AppColors.Surface)
            .padding(16.dp)
    ) {
        Text(
            text = "Progress Over Time",
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Legend
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            LegendItem(color = AppColors.ExtensionBlue, label = "Extension", goal = "Goal: 0°")
            LegendItem(color = AppColors.FlexionPink, label = "Flexion", goal = "Goal: 135°")
        }

        Spacer(modifier = Modifier.height(16.dp))

        if (extensionData.isEmpty() && flexionData.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        painter = androidx.compose.ui.res.painterResource(
                            id = android.R.drawable.ic_menu_recent_history
                        ),
                        contentDescription = null,
                        modifier = Modifier.size(40.dp),
                        tint = AppColors.TextTertiary
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "No data yet",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.TextSecondary
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Take measurements to track\nyour progress",
                        fontSize = 15.sp,
                        color = AppColors.TextTertiary,
                        textAlign = TextAlign.Center
                    )
                }
            }
        } else {
            val allData = extensionData + flexionData
            val maxDay = allData.maxOfOrNull { it.first } ?: 1f
            val yMax = 145f

            Canvas(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(200.dp)
            ) {
                val chartWidth = size.width
                val chartHeight = size.height
                val dash = PathEffect.dashPathEffect(floatArrayOf(10f, 10f))

                // Grid lines every 45 degrees
                for (gridAngle in listOf(0f, 45f, 90f, 135f)) {
                    val y = chartHeight * (1f - gridAngle / yMax)
                    drawLine(
                        color = Color.White.copy(alpha = 0.1f),
                        start = Offset(0f, y),
                        end = Offset(chartWidth, y),
                        strokeWidth = 1f
                    )
                }

                // Extension goal line (0°)
                val y0 = chartHeight * (1f - 0f / yMax)
                drawLine(
                    color = AppColors.ExtensionBlue.copy(alpha = 0.5f),
                    start = Offset(0f, y0),
                    end = Offset(chartWidth, y0),
                    strokeWidth = 2f,
                    pathEffect = dash
                )

                // Flexion goal line (135°)
                val y135 = chartHeight * (1f - 135f / yMax)
                drawLine(
                    color = AppColors.FlexionPink.copy(alpha = 0.5f),
                    start = Offset(0f, y135),
                    end = Offset(chartWidth, y135),
                    strokeWidth = 2f,
                    pathEffect = dash
                )

                // Draw extension line
                drawDataLine(extensionData, AppColors.ExtensionBlue, maxDay, yMax, chartWidth, chartHeight)

                // Draw flexion line
                drawDataLine(flexionData, AppColors.FlexionPink, maxDay, yMax, chartWidth, chartHeight)
            }
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawDataLine(
    data: List<Pair<Float, Float>>,
    color: Color,
    maxDay: Float,
    yMax: Float,
    chartWidth: Float,
    chartHeight: Float
) {
    if (data.size < 2) {
        // Draw single point
        data.firstOrNull()?.let { (day, angle) ->
            val x = if (maxDay > 0) (day / maxDay) * chartWidth else chartWidth / 2
            val y = chartHeight * (1f - angle / yMax)
            drawCircle(color, radius = 5f, center = Offset(x, y))
        }
        return
    }

    val points = data.map { (day, angle) ->
        val x = if (maxDay > 0) (day / maxDay) * chartWidth else 0f
        val y = chartHeight * (1f - angle / yMax)
        Offset(x, y)
    }

    // Draw connecting lines
    for (i in 0 until points.size - 1) {
        drawLine(
            color = color,
            start = points[i],
            end = points[i + 1],
            strokeWidth = 3f,
            cap = StrokeCap.Round
        )
    }

    // Draw points
    points.forEach { point ->
        drawCircle(color, radius = 5f, center = point)
        drawCircle(AppColors.Surface, radius = 3f, center = point)
    }
}

@Composable
private fun LegendItem(color: Color, label: String, goal: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .clip(CircleShape)
                .background(color)
        )
        Spacer(modifier = Modifier.width(6.dp))
        Column {
            Text(text = label, fontSize = 12.sp, color = AppColors.Text)
            Text(text = goal, fontSize = 10.sp, color = AppColors.TextTertiary)
        }
    }
}

@Composable
private fun StatsSection(measurements: List<Measurement>) {
    val extensions = measurements.filter { it.type == MeasurementType.EXTENSION }.sortedBy { it.timestamp.time }
    val flexions = measurements.filter { it.type == MeasurementType.FLEXION }.sortedBy { it.timestamp.time }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (extensions.isNotEmpty()) {
            StatsRow(
                type = MeasurementType.EXTENSION,
                color = AppColors.ExtensionBlue,
                best = "${extensions.minOf { it.angle }}°",
                latest = "${extensions.last().angle}°"
            )
        }
        if (flexions.isNotEmpty()) {
            StatsRow(
                type = MeasurementType.FLEXION,
                color = AppColors.FlexionPink,
                best = "${flexions.maxOf { it.angle }}°",
                latest = "${flexions.last().angle}°"
            )
        }

        // Total count
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(AppColors.Surface)
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(text = "Total Measurements", fontSize = 15.sp, color = AppColors.TextSecondary)
            Text(text = "${measurements.size}", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
        }
    }
}

@Composable
private fun StatsRow(
    type: MeasurementType,
    color: Color,
    best: String,
    latest: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(AppColors.Surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // Label with dot
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f)
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(color)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = type.displayName,
                fontSize = 15.sp,
                color = AppColors.Text
            )
        }

        // Best
        Column(horizontalAlignment = Alignment.End) {
            Text(text = "Best", fontSize = 11.sp, color = AppColors.TextTertiary)
            Text(text = best, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = color)
        }

        Spacer(modifier = Modifier.width(16.dp))

        // Latest
        Column(horizontalAlignment = Alignment.End) {
            Text(text = "Latest", fontSize = 11.sp, color = AppColors.TextTertiary)
            Text(text = latest, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
        }
    }
}
