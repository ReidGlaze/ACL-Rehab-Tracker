package com.twintipsolutions.aclrehabtracker.ui.screens.home

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.model.UserProfile
import com.twintipsolutions.aclrehabtracker.data.service.AuthService
import com.twintipsolutions.aclrehabtracker.data.service.FirestoreService
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import com.twintipsolutions.aclrehabtracker.util.DateHelpers
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(onNavigateToMeasure: () -> Unit = {}) {
    var userProfile by remember { mutableStateOf<UserProfile?>(null) }
    var latestExtension by remember { mutableStateOf<Measurement?>(null) }
    var latestFlexion by remember { mutableStateOf<Measurement?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    suspend fun loadData() {
        val uid = AuthService.currentUserId ?: return
        try {
            userProfile = FirestoreService.getUserProfile(uid)
            val measurements = FirestoreService.getMeasurements(uid)
            latestExtension = measurements.firstOrNull { it.type == MeasurementType.EXTENSION }
            latestFlexion = measurements.firstOrNull { it.type == MeasurementType.FLEXION }
        } catch (_: Exception) { }
        isLoading = false
    }

    LaunchedEffect(Unit) { loadData() }

    val weekPostOp = remember(userProfile) {
        DateHelpers.calculateWeekPostOp(userProfile?.surgeryDate)
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
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
        ) {
            // Header with avatar
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Today",
                        fontSize = 34.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.Text
                    )
                    Text(
                        text = DateHelpers.todayFormatted(),
                        fontSize = 17.sp,
                        color = AppColors.TextSecondary
                    )
                }

                // Avatar circle
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(AppColors.SurfaceLight),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = userProfile?.name
                            ?.takeIf { it.isNotEmpty() }
                            ?.first()
                            ?.uppercase()
                            ?: "?",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Text
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Week Card
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(AppColors.Success)
                    .padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "Week",
                        fontSize = 17.sp,
                        color = AppColors.Background
                    )
                    Text(
                        text = "$weekPostOp",
                        fontSize = 72.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.Background
                    )
                    Text(
                        text = "Post-Op Recovery",
                        fontSize = 17.sp,
                        color = AppColors.Background
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Latest Measurements
            Text(
                text = "Latest Measurements",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            )

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                MeasurementCard(
                    title = "EXTENSION",
                    value = latestExtension?.angle?.let { "${it}°" } ?: "--",
                    goal = "Goal: 0°",
                    modifier = Modifier.weight(1f)
                )
                MeasurementCard(
                    title = "FLEXION",
                    value = latestFlexion?.angle?.let { "${it}°" } ?: "--",
                    goal = "Goal: 135°",
                    modifier = Modifier.weight(1f)
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Spacer(modifier = Modifier.height(24.dp))

            // Measure Now Button
            Button(
                onClick = onNavigateToMeasure,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
                shape = RoundedCornerShape(16.dp)
            ) {
                Text(
                    text = "Measure Now",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Last Updated
            val lastTimestamp = latestExtension?.timestamp ?: latestFlexion?.timestamp
            if (lastTimestamp != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Last updated: ${SimpleDateFormat("MMM d, h:mm a", Locale.getDefault()).format(lastTimestamp)}",
                    fontSize = 12.sp,
                    color = AppColors.TextTertiary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
private fun MeasurementCard(
    title: String,
    value: String,
    goal: String,
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
            text = title,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = AppColors.TextSecondary,
            letterSpacing = 1.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = value,
            fontSize = 36.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = goal,
            fontSize = 13.sp,
            color = AppColors.TextTertiary
        )
    }
}
