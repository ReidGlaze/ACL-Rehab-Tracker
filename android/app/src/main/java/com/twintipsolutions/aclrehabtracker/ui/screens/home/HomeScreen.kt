package com.twintipsolutions.aclrehabtracker.ui.screens.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToMeasure: () -> Unit = {},
    onNavigateToProfile: () -> Unit = {}
) {
    val context = LocalContext.current
    var userProfile by remember { mutableStateOf<UserProfile?>(null) }
    var latestExtension by remember { mutableStateOf<Measurement?>(null) }
    var latestFlexion by remember { mutableStateOf<Measurement?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun loadCachedProfile(): UserProfile? {
        val prefs = context.getSharedPreferences("acl_rehab_prefs", android.content.Context.MODE_PRIVATE)
        val name = prefs.getString("cached_name", null) ?: return null
        val surgeryDateMs = prefs.getLong("cached_surgery_date", 0L)
        return UserProfile(
            id = "cached",
            name = name,
            surgeryDate = if (surgeryDateMs > 0) Date(surgeryDateMs) else null
        )
    }

    suspend fun loadData() {
        val uid = AuthService.currentUserId
        if (uid == null) {
            // Fall back to locally cached profile from onboarding
            if (userProfile == null) {
                userProfile = loadCachedProfile()
            }
            isLoading = false
            return
        }
        try {
            userProfile = FirestoreService.getUserProfile(uid)
            // If Firestore returns null, try local cache
            if (userProfile == null) {
                userProfile = loadCachedProfile()
            }
            val measurements = FirestoreService.getMeasurements(uid)
            latestExtension = measurements.firstOrNull { it.type == MeasurementType.EXTENSION }
            latestFlexion = measurements.firstOrNull { it.type == MeasurementType.FLEXION }
        } catch (_: Exception) {
            // On network error, fall back to cached profile
            if (userProfile == null) {
                userProfile = loadCachedProfile()
            }
            errorMessage = "Failed to load data. Pull to refresh to try again."
        }
        isLoading = false
    }

    LaunchedEffect(Unit) { loadData() }

    val weekPostOp = remember(userProfile) {
        DateHelpers.calculateWeekPostOp(userProfile?.surgeryDate)
    }
    val daysUntilSurgery = remember(userProfile) {
        DateHelpers.daysUntilSurgery(userProfile?.surgeryDate)
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
                    val greeting = userProfile?.name
                        ?.takeIf { it.isNotEmpty() }
                        ?.let { "Hey, $it" }
                        ?: "Today"
                    Text(
                        text = greeting,
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
                        .background(AppColors.SurfaceLight)
                        .clickable { onNavigateToProfile() },
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
                    if (daysUntilSurgery > 0) {
                        // Surgery is in the future
                        Text(
                            text = "Surgery in",
                            fontSize = 17.sp,
                            color = AppColors.Background
                        )
                        Text(
                            text = "$daysUntilSurgery",
                            fontSize = 72.sp,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.Background
                        )
                        Text(
                            text = if (daysUntilSurgery == 1) "Day" else "Days",
                            fontSize = 17.sp,
                            color = AppColors.Background
                        )
                    } else if (daysUntilSurgery == 0 && weekPostOp == 0) {
                        // Surgery day
                        Text(
                            text = "Week",
                            fontSize = 17.sp,
                            color = AppColors.Background
                        )
                        Text(
                            text = "0",
                            fontSize = 72.sp,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.Background
                        )
                        Text(
                            text = "Surgery Day",
                            fontSize = 17.sp,
                            color = AppColors.Background
                        )
                    } else {
                        // Post-op recovery
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
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Latest Measurements
            Text(
                text = "Latest Measurements",
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
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
            .padding(24.dp),
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
            color = if (value == "--") AppColors.TextTertiary else AppColors.Text
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = goal,
            fontSize = 13.sp,
            color = AppColors.TextTertiary
        )
    }
}
