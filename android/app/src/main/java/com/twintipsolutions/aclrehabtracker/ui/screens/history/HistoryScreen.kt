package com.twintipsolutions.aclrehabtracker.ui.screens.history

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
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
import com.twintipsolutions.aclrehabtracker.data.service.StorageService
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
    var selectedWeek by remember { mutableStateOf<Int?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var selectedPhotoUrl by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var measurementToDelete by remember { mutableStateOf<Measurement?>(null) }
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
            errorMessage = "Failed to load history."
        }
        isLoading = false
    }

    LaunchedEffect(Unit) { loadData() }

    val availableWeeks = remember(measurements) {
        measurements.map { it.weekPostOp }.toSet().sorted()
    }

    val filteredMeasurements = remember(measurements, selectedFilter, selectedWeek) {
        measurements.filter { m ->
            val typeMatch = when (selectedFilter) {
                HistoryFilter.ALL -> true
                HistoryFilter.EXTENSION -> m.type == MeasurementType.EXTENSION
                HistoryFilter.FLEXION -> m.type == MeasurementType.FLEXION
            }
            val weekMatch = selectedWeek == null || m.weekPostOp == selectedWeek
            typeMatch && weekMatch
        }
    }

    val groupedMeasurements = remember(filteredMeasurements) {
        DateHelpers.groupByDate(filteredMeasurements) { it.timestamp }
    }

    // Delete confirmation dialog
    if (measurementToDelete != null) {
        AlertDialog(
            onDismissRequest = { measurementToDelete = null },
            title = { Text("Delete Measurement", color = AppColors.Text) },
            text = {
                Text(
                    "This will permanently delete this measurement and its photo. This cannot be undone.",
                    color = AppColors.TextSecondary
                )
            },
            containerColor = AppColors.Surface,
            confirmButton = {
                TextButton(onClick = {
                    val measurement = measurementToDelete ?: return@TextButton
                    measurementToDelete = null
                    scope.launch {
                        val uid = AuthService.currentUserId ?: return@launch
                        try {
                            // Delete photo from Storage if it exists
                            if (measurement.photoUrl.isNotEmpty()) {
                                try { StorageService.deletePhoto(uid, measurement.id) } catch (_: Exception) {}
                            }
                            // Delete measurement from Firestore
                            FirestoreService.deleteMeasurement(uid, measurement.id)
                            // Remove from local list
                            measurements = measurements.filter { it.id != measurement.id }
                        } catch (_: Exception) {
                            errorMessage = "Failed to delete measurement."
                        }
                    }
                }) {
                    Text("Delete", color = Color.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { measurementToDelete = null }) {
                    Text("Cancel", color = AppColors.TextSecondary)
                }
            }
        )
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

            // Week Scroller
            if (availableWeeks.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))

                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    // "All" chip
                    item {
                        val isSelected = selectedWeek == null
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(16.dp))
                                .background(
                                    if (isSelected) AppColors.Primary.copy(alpha = 0.3f)
                                    else AppColors.Surface
                                )
                                .clickable { selectedWeek = null }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = "All",
                                fontSize = 13.sp,
                                color = if (isSelected) AppColors.Text else AppColors.TextSecondary,
                                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                            )
                        }
                    }

                    // Week chips
                    items(availableWeeks) { week ->
                        val isSelected = selectedWeek == week
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(16.dp))
                                .background(
                                    if (isSelected) AppColors.Primary.copy(alpha = 0.3f)
                                    else AppColors.Surface
                                )
                                .clickable { selectedWeek = week }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = "Wk $week",
                                fontSize = 13.sp,
                                color = if (isSelected) AppColors.Text else AppColors.TextSecondary,
                                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                            )
                        }
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
                            fontSize = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.Text
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Take your first measurement to see it here",
                            fontSize = 17.sp,
                            color = AppColors.TextSecondary
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
                                text = dateLabel.uppercase(),
                                fontSize = 13.sp,
                                color = AppColors.TextSecondary,
                                letterSpacing = 1.sp,
                                modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                            )
                        }
                        items(items, key = { it.id }) { measurement ->
                            val dismissState = rememberSwipeToDismissBoxState(
                                confirmValueChange = { value ->
                                    if (value == SwipeToDismissBoxValue.EndToStart) {
                                        measurementToDelete = measurement
                                        false // Don't actually dismiss, let the dialog handle it
                                    } else {
                                        false
                                    }
                                }
                            )

                            SwipeToDismissBox(
                                state = dismissState,
                                enableDismissFromStartToEnd = false,
                                backgroundContent = {
                                    val bgColor by animateColorAsState(
                                        if (dismissState.targetValue == SwipeToDismissBoxValue.EndToStart)
                                            Color.Red else AppColors.Background,
                                        label = "swipe-bg"
                                    )
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(bgColor)
                                            .padding(horizontal = 20.dp),
                                        contentAlignment = Alignment.CenterEnd
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Delete,
                                            contentDescription = "Delete",
                                            tint = Color.White
                                        )
                                    }
                                }
                            ) {
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
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Thumbnail
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(AppColors.SurfaceLight),
            contentAlignment = Alignment.Center
        ) {
            if (measurement.photoUrl.isNotEmpty()) {
                AsyncImage(
                    model = measurement.photoUrl,
                    contentDescription = "Measurement photo",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
            } else {
                Icon(
                    painter = androidx.compose.ui.res.painterResource(
                        id = android.R.drawable.ic_menu_camera
                    ),
                    contentDescription = "No photo",
                    tint = AppColors.TextTertiary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        // Type badge + angle + time
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.3f))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = shortName,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Text
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                Text(
                    text = "${measurement.angle}°",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.Text
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = DateHelpers.formatTime(measurement.timestamp),
                fontSize = 13.sp,
                color = AppColors.TextSecondary
            )
        }

        // Week badge
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = "Week ${measurement.weekPostOp}",
                fontSize = 11.sp,
                color = AppColors.TextSecondary,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(AppColors.SurfaceLight)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            )
        }
    }
}
