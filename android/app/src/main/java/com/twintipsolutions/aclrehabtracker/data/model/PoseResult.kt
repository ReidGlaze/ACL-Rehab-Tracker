package com.twintipsolutions.aclrehabtracker.data.model

data class Keypoint(
    val x: Float,
    val y: Float,
    val confidence: Float = 1.0f
)

data class PoseResult(
    val hip: Keypoint,
    val knee: Keypoint,
    val ankle: Keypoint,
    val angle: Int,
    val confidence: Double = 0.0
)
