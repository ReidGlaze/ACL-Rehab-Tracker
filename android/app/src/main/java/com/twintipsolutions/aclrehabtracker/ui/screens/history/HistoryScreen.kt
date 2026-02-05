package com.twintipsolutions.aclrehabtracker.ui.screens.history

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import coil.compose.AsyncImage
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.service.AuthService
import com.twintipsolutions.aclrehabtracker.data.service.FirestoreService
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import com.twintipsolutions.aclrehabtracker.util.DateHelpers
import kotlinx.coroutines.launch

private enum class HistoryFilter(val label: String) {
    ALL("All"),
    EXTENSION("Extension"),
    FLEXION("Flexion")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen() {
    var measurements by remember { mutableStateOf<List<Measurement>>(emptyList()) }
    var selectedFilter by remember { mutableStateOf(HistoryFilter.ALL) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var selectedPhotoUrl by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    suspend fun loadData() {
        val uid = AuthService.currentUserId ?: return
        try {
            measurements = FirestoreService.getMeasurements(uid)
        } catch (_: Exception) { }
        isLoading = false
    }

    LaunchedEffect(Unit) { loadData() }

    val filteredMeasurements = remember(measurements, selectedFilter) {
        when (selectedFilter) {
            HistoryFilter.ALL -> measurements
            HistoryFilter.EXTENSION -> measurements.filter { it.type == MeasurementType.EXTENSION }
            HistoryFilter.FLEXION -> measurements.filter { it.type == MeasurementType.FLEXION }
        }
    }

    val groupedMeasurements = remember(filteredMeasurements) {
        DateHelpers.groupByDate(filteredMeasurements) { it.timestamp }
    }

    // Photo viewer dialog
    if (selectedPhotoUrl != null) {
        Dialog(onDismissRequest = { selectedPhotoUrl = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(AppColors.Background)
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                AsyncImage(
                    model = selectedPhotoUrl,
                    contentDescription = "Measurement photo",
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(3f / 4f)
                        .clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Crop
                )

                Spacer(modifier = Modifier.height(16.dp))

                Button(
                    onClick = { selectedPhotoUrl = null },
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.Surface),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text("Close", color = AppColors.Text, fontWeight = FontWeight.SemiBold)
                }
            }
        }
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
        ) {
            Spacer(modifier = Modifier.height(24.dp))

            // Header
            Text(
                text = "History",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Filter Pills
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                HistoryFilter.entries.forEach { filter ->
                    val isSelected = filter == selectedFilter
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(20.dp))
                            .background(if (isSelected) AppColors.Primary else AppColors.Surface)
                            .clickable { selectedFilter = filter }
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Text(
                            text = filter.label,
                            fontSize = 15.sp,
                            color = if (isSelected) AppColors.Text else AppColors.TextSecondary,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = AppColors.Primary)
                }
            } else if (filteredMeasurements.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "No measurements yet",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.TextSecondary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Your measurement history will appear here",
                            fontSize = 15.sp,
                            color = AppColors.TextTertiary
                        )
                    }
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(bottom = 16.dp)
                ) {
                    groupedMeasurements.forEach { (dateLabel, items) ->
                        item {
                            Text(
                                text = dateLabel,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = AppColors.TextSecondary,
                                modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                            )
                        }
                        items(items, key = { it.id }) { measurement ->
                            MeasurementRow(
                                measurement = measurement,
                                onTap = {
                                    if (measurement.photoUrl.isNotEmpty()) {
                                        selectedPhotoUrl = measurement.photoUrl
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MeasurementRow(measurement: Measurement, onTap: () -> Unit) {
    val color = if (measurement.type == MeasurementType.EXTENSION) {
        AppColors.ExtensionBlue
    } else {
        AppColors.FlexionPink
    }

    val shortName = if (measurement.type == MeasurementType.EXTENSION) "EXT" else "FLX"

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(AppColors.Surface)
            .clickable(onClick = onTap)
            .padding(16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // Type badge with short name
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(color.copy(alpha = 0.2f))
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text(
                    text = shortName,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = color
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Angle
            Text(
                text = "${measurement.angle}°",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            // Photo indicator
            if (measurement.photoUrl.isNotEmpty()) {
                Text(
                    text = "\uD83D\uDCF7",
                    fontSize = 14.sp,
                    color = AppColors.Primary
                )
                Spacer(modifier = Modifier.width(8.dp))
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = DateHelpers.formatTime(measurement.timestamp),
                    fontSize = 13.sp,
                    color = AppColors.TextSecondary
                )
                Text(
                    text = "Week ${measurement.weekPostOp}",
                    fontSize = 11.sp,
                    color = AppColors.TextTertiary
                )
            }
        }
    }
}
