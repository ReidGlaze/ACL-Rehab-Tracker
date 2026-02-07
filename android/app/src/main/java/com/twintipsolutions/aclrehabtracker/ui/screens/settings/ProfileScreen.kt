package com.twintipsolutions.aclrehabtracker.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.data.model.InjuryType
import com.twintipsolutions.aclrehabtracker.data.model.KneeSide
import com.twintipsolutions.aclrehabtracker.data.model.UserProfile
import com.twintipsolutions.aclrehabtracker.data.service.AuthService
import com.twintipsolutions.aclrehabtracker.data.service.FirestoreService
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import android.content.Context
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import com.twintipsolutions.aclrehabtracker.BuildConfig
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    onBack: () -> Unit = {},
    onNavigateToPrivacyPolicy: () -> Unit = {},
    onAccountDeleted: () -> Unit = {}
) {
    val context = LocalContext.current
    var name by remember { mutableStateOf("") }
    var injuredKnee by remember { mutableStateOf(KneeSide.LEFT) }
    var injuryType by remember { mutableStateOf(InjuryType.ACL_ONLY) }
    var surgeryDate by remember { mutableStateOf<Date?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isSaving by remember { mutableStateOf(false) }
    var showDatePicker by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun loadCachedProfile() {
        val prefs = context.getSharedPreferences("acl_rehab_prefs", Context.MODE_PRIVATE)
        val cachedName = prefs.getString("cached_name", null)
        if (cachedName != null) {
            name = cachedName
            val surgeryMs = prefs.getLong("cached_surgery_date", 0L)
            if (surgeryMs > 0) surgeryDate = Date(surgeryMs)
            val kneeStr = prefs.getString("cached_injured_knee", null)
            if (kneeStr != null) injuredKnee = KneeSide.fromString(kneeStr)
            val injuryStr = prefs.getString("cached_injury_type", null)
            if (injuryStr != null) injuryType = InjuryType.fromString(injuryStr)
        }
    }

    LaunchedEffect(Unit) {
        val uid = AuthService.currentUserId
        if (uid == null) {
            loadCachedProfile()
            isLoading = false
            return@LaunchedEffect
        }
        try {
            val profile = FirestoreService.getUserProfile(uid)
            if (profile != null) {
                name = profile.name
                injuredKnee = profile.injuredKnee
                injuryType = profile.injuryType
                surgeryDate = profile.surgeryDate
            } else {
                loadCachedProfile()
            }
        } catch (_: Exception) {
            loadCachedProfile()
            errorMessage = "Failed to load profile."
        }
        isLoading = false
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Profile") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                },
                windowInsets = WindowInsets(0),
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.Background,
                    titleContentColor = AppColors.Text,
                    navigationIconContentColor = AppColors.Text
                )
            )
        }
    ) { innerPadding ->
        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(AppColors.Background)
                    .padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(color = AppColors.Primary)
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(AppColors.Background)
                    .padding(innerPadding)
                    .verticalScroll(rememberScrollState())
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Avatar
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(AppColors.SurfaceLight),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = name.takeIf { it.isNotEmpty() }?.first()?.uppercase() ?: "?",
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.Text
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Name Field
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Name",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Text
                    )
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Your name") },
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = AppColors.Text,
                            unfocusedTextColor = AppColors.Text,
                            focusedBorderColor = AppColors.Primary,
                            unfocusedBorderColor = AppColors.Border,
                            focusedContainerColor = AppColors.InputBackground,
                            unfocusedContainerColor = AppColors.InputBackground,
                            focusedPlaceholderColor = AppColors.TextTertiary,
                            unfocusedPlaceholderColor = AppColors.TextTertiary
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Knee Selection
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Injured Knee",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Text
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        KneeSide.entries.forEach { side ->
                            val isSelected = injuredKnee == side
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(if (isSelected) AppColors.Surface else AppColors.Background)
                                    .border(
                                        1.dp,
                                        if (isSelected) AppColors.Primary else AppColors.Border,
                                        RoundedCornerShape(12.dp)
                                    )
                                    .clickable { injuredKnee = side }
                                    .padding(vertical = 16.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = side.displayName,
                                    fontSize = 17.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (isSelected) AppColors.Text else AppColors.TextSecondary
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Injury Type
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Injury Type",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Text
                    )
                    InjuryType.entries.forEach { type ->
                        val isSelected = injuryType == type
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(if (isSelected) AppColors.Surface else AppColors.Background)
                                .border(
                                    1.dp,
                                    if (isSelected) AppColors.Primary else AppColors.Border,
                                    RoundedCornerShape(12.dp)
                                )
                                .clickable { injuryType = type }
                                .padding(16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = type.displayName,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (isSelected) AppColors.Text else AppColors.TextSecondary,
                                modifier = Modifier.weight(1f)
                            )
                            if (isSelected) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = "Selected",
                                    tint = AppColors.Success
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Surgery Date
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Surgery Date",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Text
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(AppColors.InputBackground)
                            .border(1.dp, AppColors.Border, RoundedCornerShape(12.dp))
                            .clickable { showDatePicker = true }
                            .padding(16.dp)
                    ) {
                        Text(
                            text = surgeryDate?.let {
                                SimpleDateFormat("MMMM d, yyyy", Locale.getDefault()).format(it)
                            } ?: "Select date",
                            fontSize = 17.sp,
                            color = if (surgeryDate != null) AppColors.Text else AppColors.TextTertiary
                        )
                    }
                }

                Spacer(modifier = Modifier.height(32.dp))

                // Save Button
                Button(
                    onClick = {
                        scope.launch {
                            isSaving = true
                            val uid = AuthService.currentUserId
                            if (uid != null) {
                                try {
                                    val profile = UserProfile(
                                        id = uid,
                                        name = name,
                                        surgeryDate = surgeryDate,
                                        injuredKnee = injuredKnee,
                                        injuryType = injuryType
                                    )
                                    FirestoreService.saveUserProfile(uid, profile)
                                    onBack()
                                } catch (_: Exception) {
                                    errorMessage = "Failed to save profile. Please try again."
                                }
                            }
                            isSaving = false
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    enabled = !isSaving,
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
                        Text(
                            text = "Save Changes",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                // Privacy Policy Link
                Spacer(modifier = Modifier.height(16.dp))
                TextButton(onClick = onNavigateToPrivacyPolicy) {
                    Text(
                        text = "Privacy Policy",
                        fontSize = 13.sp,
                        color = AppColors.TextSecondary,
                        textDecoration = TextDecoration.Underline
                    )
                }

                // Delete Account
                Spacer(modifier = Modifier.height(24.dp))
                TextButton(onClick = { showDeleteConfirmation = true }) {
                    Text(
                        text = "Delete Account",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                // Version Info
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    fontSize = 11.sp,
                    color = AppColors.TextTertiary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }

    // Error Dialog
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

    // Delete Confirmation Dialog
    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text("Delete Account?") },
            text = { Text("This will permanently delete your account and all data. This action cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirmation = false
                    scope.launch {
                        try {
                            val uid = AuthService.currentUserId
                            if (uid != null) {
                                FirestoreService.deleteUserData(uid)
                            }
                            AuthService.deleteUser()
                            context.getSharedPreferences("acl_rehab_prefs", Context.MODE_PRIVATE)
                                .edit().putBoolean("onboarding_complete", false).apply()
                            onAccountDeleted()
                        } catch (_: Exception) {
                            errorMessage = "Failed to delete account. Please try again."
                        }
                    }
                }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) { Text("Cancel") }
            }
        )
    }

    // Date Picker Dialog
    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = surgeryDate?.time ?: System.currentTimeMillis()
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    datePickerState.selectedDateMillis?.let { millis ->
                        surgeryDate = Date(millis)
                    }
                    showDatePicker = false
                }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("Cancel")
                }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }
}
