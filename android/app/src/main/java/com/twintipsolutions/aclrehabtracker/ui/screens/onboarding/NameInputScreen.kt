package com.twintipsolutions.aclrehabtracker.ui.screens.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.twintipsolutions.aclrehabtracker.ui.theme.AppColors

@Composable
fun NameInputScreen(
    name: String,
    onNameChange: (String) -> Unit,
    onContinue: () -> Unit
) {
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.Background)
            .padding(32.dp)
    ) {
        Spacer(modifier = Modifier.height(60.dp))

        Text(
            text = "What's your name?",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "We'll use this to personalize your experience",
            fontSize = 17.sp,
            color = AppColors.TextSecondary
        )

        Spacer(modifier = Modifier.height(40.dp))

        BasicTextField(
            value = name,
            onValueChange = onNameChange,
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focusRequester),
            textStyle = TextStyle(
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.Text
            ),
            cursorBrush = SolidColor(AppColors.Primary),
            singleLine = true,
            decorationBox = { innerTextField ->
                Column {
                    Box {
                        if (name.isEmpty()) {
                            Text(
                                "Your name",
                                fontSize = 28.sp,
                                fontWeight = FontWeight.Bold,
                                color = AppColors.TextTertiary
                            )
                        }
                        innerTextField()
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(3.dp)
                            .background(
                                if (name.isNotEmpty()) AppColors.Primary else AppColors.SurfaceLight,
                                RoundedCornerShape(1.5.dp)
                            )
                    )
                }
            }
        )

        Spacer(modifier = Modifier.weight(1f))

        if (name.isNotBlank()) {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.CenterEnd
            ) {
                IconButton(
                    onClick = onContinue,
                    modifier = Modifier
                        .size(56.dp)
                        .background(AppColors.Primary, CircleShape)
                ) {
                    Text("→", fontSize = 24.sp, color = AppColors.Text)
                }
            }
        }
    }
}
