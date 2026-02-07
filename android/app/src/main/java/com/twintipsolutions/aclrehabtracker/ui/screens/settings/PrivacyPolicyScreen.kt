package com.twintipsolutions.aclrehabtracker.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyPolicyScreen(onBack: () -> Unit = {}) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Privacy Policy") },
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.Background)
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
        ) {
            Text(
                text = "Last updated: February 5, 2026",
                fontSize = 12.sp,
                color = AppColors.TextSecondary
            )

            Spacer(modifier = Modifier.height(20.dp))

            PolicySection(
                title = "What Data We Collect",
                body = "ACL Rehab Tracker collects the following information to help you track " +
                    "your rehabilitation progress:\n\n" +
                    "\u2022 Your name (for personalization)\n" +
                    "\u2022 Surgery date and injury details (to calculate recovery week)\n" +
                    "\u2022 Knee angle measurements (extension and flexion values)\n" +
                    "\u2022 Knee photos you submit for AI angle analysis\n\n" +
                    "All data is associated with an anonymous account \u2014 we do not collect " +
                    "your email, phone number, or any other personal identifiers."
            )

            PolicySection(
                title = "How Data Is Stored",
                body = "Your data is stored securely in Google Firebase (Firestore and Cloud Storage) " +
                    "and is associated only with your anonymous user ID. Photos are stored in " +
                    "Firebase Storage and are only accessible to your account."
            )

            PolicySection(
                title = "AI Knee Angle Analysis",
                body = "When you submit a photo for angle measurement, it is sent to a Google Cloud " +
                    "Function that uses the Gemini AI model to estimate your knee angle. The photo " +
                    "is processed in real time and is not retained by the AI service after analysis."
            )

            PolicySection(
                title = "Third-Party Sharing",
                body = "We do not sell, share, or distribute your data to any third parties. Your " +
                    "rehabilitation data is used solely to provide you with the app's features."
            )

            PolicySection(
                title = "Data Deletion",
                body = "Since your account is anonymous, uninstalling the app effectively removes " +
                    "your access to the data. If you would like your data permanently deleted " +
                    "from our servers, please contact us."
            )

            PolicySection(
                title = "Contact",
                body = "If you have questions about this policy, contact us at support@twintipsolutions.com."
            )
        }
    }
}

@Composable
private fun PolicySection(title: String, body: String) {
    Text(
        text = title,
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.Text
    )
    Spacer(modifier = Modifier.height(8.dp))
    Text(
        text = body,
        fontSize = 17.sp,
        color = AppColors.TextSecondary,
        lineHeight = 24.sp
    )
    Spacer(modifier = Modifier.height(20.dp))
}
