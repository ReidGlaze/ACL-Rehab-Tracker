package com.twintipsolutions.aclrehabtracker.ui.screens.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors
import com.twintipsolutions.aclrehabtracker.util.DateHelpers
import java.util.Calendar
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SurgeryDateScreen(
    surgeryDate: Date,
    onDateChange: (Date) -> Unit,
    onComplete: () -> Unit,
    isLoading: Boolean = false
) {
    val datePickerState = rememberDatePickerState(
        initialSelectedDateMillis = surgeryDate.time,
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                val minDate = Calendar.getInstance().apply {
                    set(2020, Calendar.JANUARY, 1)
                }.timeInMillis
                val maxDate = Calendar.getInstance().apply {
                    add(Calendar.YEAR, 1)
                }.timeInMillis
                return utcTimeMillis in minDate..maxDate
            }
        }
    )

    LaunchedEffect(datePickerState.selectedDateMillis) {
        datePickerState.selectedDateMillis?.let { millis ->
            onDateChange(Date(millis))
        }
    }

    val weekPostOp = remember(surgeryDate) {
        DateHelpers.calculateWeekPostOp(surgeryDate)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
            .navigationBarsPadding()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(60.dp))

        Text(
            text = "Surgery Date",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "When did you have your surgery?",
            fontSize = 17.sp,
            color = AppColors.TextSecondary
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Week post-op indicator
        Box(
            modifier = Modifier
                .background(AppColors.Success, RoundedCornerShape(12.dp))
                .padding(horizontal = 24.dp, vertical = 12.dp)
        ) {
            Text(
                text = "Week $weekPostOp Post-Op",
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.Background
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Date Picker
        DatePicker(
            state = datePickerState,
            modifier = Modifier.weight(1f),
            colors = DatePickerDefaults.colors(
                containerColor = AppColors.Background,
                titleContentColor = AppColors.Text,
                headlineContentColor = AppColors.Text,
                weekdayContentColor = AppColors.TextSecondary,
                subheadContentColor = AppColors.TextSecondary,
                yearContentColor = AppColors.Text,
                currentYearContentColor = AppColors.Primary,
                selectedYearContainerColor = AppColors.Primary,
                selectedYearContentColor = AppColors.Text,
                dayContentColor = AppColors.Text,
                selectedDayContainerColor = AppColors.Primary,
                selectedDayContentColor = AppColors.Text,
                todayContentColor = AppColors.Primary,
                todayDateBorderColor = AppColors.Primary
            ),
            title = null,
            headline = null,
            showModeToggle = false
        )

        Button(
            onClick = onComplete,
            enabled = !isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.Primary),
            shape = RoundedCornerShape(16.dp)
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = AppColors.Text,
                    strokeWidth = 2.dp
                )
            } else {
                Text("Start Tracking", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
