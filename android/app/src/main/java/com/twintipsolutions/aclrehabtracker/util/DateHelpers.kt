package com.twintipsolutions.aclrehabtracker.util

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

object DateHelpers {
    fun calculateWeekPostOp(surgeryDate: Date?): Int {
        if (surgeryDate == null) return 0
        val diffMillis = Date().time - surgeryDate.time
        val days = TimeUnit.MILLISECONDS.toDays(diffMillis)
        return (days / 7).toInt().coerceAtLeast(0)
    }

    fun daysUntilSurgery(surgeryDate: Date?): Int {
        if (surgeryDate == null) return 0
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.time
        val surgery = Calendar.getInstance().apply {
            time = surgeryDate
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.time
        val diffMillis = surgery.time - today.time
        return TimeUnit.MILLISECONDS.toDays(diffMillis).toInt()
    }

    fun formatDate(date: Date): String {
        return SimpleDateFormat("MMMM d, yyyy", Locale.getDefault()).format(date)
    }

    fun formatShortDate(date: Date): String {
        return SimpleDateFormat("MMM d", Locale.getDefault()).format(date)
    }

    fun formatTime(date: Date): String {
        return SimpleDateFormat("h:mm a", Locale.getDefault()).format(date)
    }

    fun formatFullDate(date: Date): String {
        return SimpleDateFormat("EEEE, MMMM d, yyyy", Locale.getDefault()).format(date)
    }

    fun todayFormatted(): String {
        return SimpleDateFormat("MMMM d", Locale.getDefault()).format(Date())
    }

    fun dateKey(date: Date): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(date)
    }

    fun <T> groupByDate(
        items: List<T>,
        dateExtractor: (T) -> Date
    ): List<Pair<String, List<T>>> {
        return items
            .groupBy { dateKey(dateExtractor(it)) }
            .toSortedMap(compareByDescending { it })
            .map { (key, values) ->
                val displayDate = formatDate(dateExtractor(values.first()))
                displayDate to values
            }
    }
}
