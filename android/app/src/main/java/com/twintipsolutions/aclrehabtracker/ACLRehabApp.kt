package com.twintipsolutions.aclrehabtracker

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.twintipsolutions.aclrehabtracker.data.model.InjuryType
import com.twintipsolutions.aclrehabtracker.data.model.KneeSide
import com.twintipsolutions.aclrehabtracker.data.model.UserProfile
import com.twintipsolutions.aclrehabtracker.data.service.AuthService
import com.twintipsolutions.aclrehabtracker.data.service.FirestoreService
import com.twintipsolutions.aclrehabtracker.ui.screens.history.HistoryScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.home.HomeScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.measure.MeasureScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.onboarding.InjuryInfoScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.onboarding.NameInputScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.onboarding.SurgeryDateScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.onboarding.WelcomeScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.progress.ProgressScreen
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import kotlinx.coroutines.launch
import java.util.Date

sealed class Screen(val route: String, val title: String, val icon: ImageVector) {
    data object Home : Screen("home", "Home", Icons.Default.Home)
    data object Measure : Screen("measure", "Measure", Icons.Default.Add)
    data object History : Screen("history", "History", Icons.Default.DateRange)
    data object Progress : Screen("progress", "Progress", Icons.Default.DateRange)
}

private val bottomNavItems = listOf(
    Screen.Home,
    Screen.Measure,
    Screen.History,
    Screen.Progress
)

private enum class AppState {
    LOADING, ONBOARDING, MAIN
}

private const val PREFS_NAME = "acl_rehab_prefs"
private const val KEY_ONBOARDING_COMPLETE = "onboarding_complete"

@Composable
fun ACLRehabApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var appState by remember { mutableStateOf(AppState.LOADING) }

    // Auth + onboarding check
    LaunchedEffect(Unit) {
        try {
            if (!AuthService.isAuthenticated) {
                AuthService.signInAnonymously()
            }
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val onboardingComplete = prefs.getBoolean(KEY_ONBOARDING_COMPLETE, false)
            appState = if (onboardingComplete) AppState.MAIN else AppState.ONBOARDING
        } catch (_: Exception) {
            // If auth fails, still show onboarding (will retry)
            appState = AppState.ONBOARDING
        }
    }

    when (appState) {
        AppState.LOADING -> LoadingView()
        AppState.ONBOARDING -> OnboardingFlow(
            onComplete = {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean(KEY_ONBOARDING_COMPLETE, true).apply()
                appState = AppState.MAIN
            }
        )
        AppState.MAIN -> MainTabView()
    }
}

@Composable
private fun LoadingView() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(color = AppColors.Primary)
    }
}

@Composable
private fun OnboardingFlow(onComplete: () -> Unit) {
    val scope = rememberCoroutineScope()
    val navController = rememberNavController()

    // Onboarding state
    var name by remember { mutableStateOf("") }
    var selectedKnee by remember { mutableStateOf(KneeSide.LEFT) }
    var selectedInjuryType by remember { mutableStateOf(InjuryType.ACL_ONLY) }
    var surgeryDate by remember { mutableStateOf(Date()) }
    var isSaving by remember { mutableStateOf(false) }

    NavHost(navController = navController, startDestination = "welcome") {
        composable("welcome") {
            WelcomeScreen(onContinue = { navController.navigate("name") })
        }
        composable("name") {
            NameInputScreen(
                name = name,
                onNameChange = { name = it },
                onContinue = { navController.navigate("injury") }
            )
        }
        composable("injury") {
            InjuryInfoScreen(
                selectedKnee = selectedKnee,
                onKneeChange = { selectedKnee = it },
                selectedInjuryType = selectedInjuryType,
                onInjuryTypeChange = { selectedInjuryType = it },
                onContinue = { navController.navigate("surgery_date") }
            )
        }
        composable("surgery_date") {
            SurgeryDateScreen(
                surgeryDate = surgeryDate,
                onDateChange = { surgeryDate = it },
                isLoading = isSaving,
                onComplete = {
                    scope.launch {
                        isSaving = true
                        try {
                            // Ensure authenticated
                            if (!AuthService.isAuthenticated) {
                                AuthService.signInAnonymously()
                            }
                            val uid = AuthService.currentUserId ?: throw Exception("No user ID")
                            val profile = UserProfile(
                                id = uid,
                                name = name,
                                surgeryDate = surgeryDate,
                                injuredKnee = selectedKnee,
                                injuryType = selectedInjuryType
                            )
                            FirestoreService.saveUserProfile(uid, profile)
                            onComplete()
                        } catch (_: Exception) {
                            // Still complete onboarding even if save fails
                            onComplete()
                        }
                        isSaving = false
                    }
                }
            )
        }
    }
}

@Composable
private fun MainTabView() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = AppColors.Surface) {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                bottomNavItems.forEach { screen ->
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = screen.title) },
                        label = { Text(screen.title) },
                        selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = AppColors.Primary,
                            selectedTextColor = AppColors.Primary,
                            unselectedIconColor = AppColors.TextSecondary,
                            unselectedTextColor = AppColors.TextSecondary,
                            indicatorColor = AppColors.Surface
                        )
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Home.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Home.route) {
                HomeScreen(
                    onNavigateToMeasure = {
                        navController.navigate(Screen.Measure.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
            }
            composable(Screen.Measure.route) { MeasureScreen() }
            composable(Screen.History.route) { HistoryScreen() }
            composable(Screen.Progress.route) { ProgressScreen() }
        }
    }
}
