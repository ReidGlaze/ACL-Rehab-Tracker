package com.twintipsolutions.aclrehabtracker.ui.screens.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors

@Composable
fun InjuryInfoScreen(
    selectedKnee: KneeSide,
    onKneeChange: (KneeSide) -> Unit,
    selectedInjuryType: InjuryType,
    onInjuryTypeChange: (InjuryType) -> Unit,
    onContinue: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(32.dp)
    ) {
        Spacer(modifier = Modifier.height(60.dp))

        Text(
            text = "Injury Details",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "This helps us personalize your tracking",
            fontSize = 17.sp,
            color = AppColors.TextSecondary
        )

        Spacer(modifier = Modifier.height(40.dp))

        // Knee Selection
        Text(
            text = "Which knee?",
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            KneeSide.entries.forEach { knee ->
                val isSelected = knee == selectedKnee
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(if (isSelected) AppColors.Primary else AppColors.Surface)
                        .clickable { onKneeChange(knee) }
                        .padding(vertical = 20.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = knee.displayName,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (isSelected) AppColors.Text else AppColors.TextSecondary
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Injury Type Selection
        Text(
            text = "Type of injury",
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(16.dp))

        InjuryType.entries.forEach { type ->
            val isSelected = type == selectedInjuryType
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (isSelected) AppColors.Surface else AppColors.Background)
                    .then(
                        if (isSelected) Modifier.border(
                            1.dp,
                            AppColors.Primary,
                            RoundedCornerShape(12.dp)
                        )
                        else Modifier.border(
                            1.dp,
                            AppColors.SurfaceLight,
                            RoundedCornerShape(12.dp)
                        )
                    )
                    .clickable { onInjuryTypeChange(type) }
                    .padding(16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = type.displayName,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (isSelected) AppColors.Text else AppColors.TextSecondary
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = type.description,
                            fontSize = 13.sp,
                            color = AppColors.TextTertiary
                        )
                    }
                    if (isSelected) {
                        Text("✓", fontSize = 17.sp, color = AppColors.Success)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
            shape = RoundedCornerShape(16.dp)
        ) {
            Text("Continue", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}
