package com.twintipsolutions.aclrehabtracker.ui.screens.onboarding

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors

@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    var visible by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { visible = true }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        AnimatedVisibility(
            visible = visible,
            enter = fadeIn() + slideInVertically { -40 }
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "ACL Rehab\nTracker",
                    fontSize = 40.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.Text,
                    textAlign = TextAlign.Center,
                    lineHeight = 48.sp
                )

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = "Track your recovery journey",
                    fontSize = 17.sp,
                    color = AppColors.TextSecondary,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(48.dp))

                FeatureRow(title = "Measure", description = "Capture knee angles with your camera")
                Spacer(modifier = Modifier.height(16.dp))
                FeatureRow(title = "Track", description = "Monitor your progress over time")
                Spacer(modifier = Modifier.height(16.dp))
                FeatureRow(title = "Store", description = "Keep photos of your measurements")
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
            shape = RoundedCornerShape(16.dp)
        ) {
            Text("Get Started", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun FeatureRow(title: String, description: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(AppColors.Surface, RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = title.first().toString(),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Primary
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Column {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
            Text(description, fontSize = 15.sp, color = AppColors.TextSecondary)
        }
    }
}
