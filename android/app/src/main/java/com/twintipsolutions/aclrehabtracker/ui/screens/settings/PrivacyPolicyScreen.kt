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
                text = "Last updated: November 3, 2026",
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
                body = "When you submit a photo for angle measurement, your knee photo, injured knee " +
                    "side, and injury type are sent through a secure Google Cloud Function to an AI " +
                    "model hosted on Google Cloud Vertex AI (such as Anthropic's Claude or Google's " +
                    "Gemini) to estimate your knee angle. The specific AI model may change as we " +
                    "improve accuracy, but processing always takes place on Google Cloud Vertex AI. " +
                    "The photo is analyzed in real time and is not stored or retained by the AI model " +
                    "after processing. Google processes this data under their Cloud data processing terms."
            )

            PolicySection(
                title = "Analytics",
                body = "We use Google Analytics for Firebase to understand how the app is used, such as " +
                    "app opens, screens viewed, and whether measurements succeed. This usage data is " +
                    "tied to a random app identifier, not to your name, and never includes your " +
                    "photos, knee angles, or injury details."
            )

            PolicySection(
                title = "Third-Party Sharing",
                body = "Your knee photos and injury details are processed on Google Cloud Vertex AI for " +
                    "angle analysis, and anonymous usage data is processed by Google Analytics for " +
                    "Firebase. Google acts as a data processor for both. Apart from this processing, " +
                    "we do not sell, share, or distribute your data to any other third parties. Your " +
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
