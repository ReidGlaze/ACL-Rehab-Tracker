import Foundation

struct DateHelpers {
    /// Calculate the number of weeks post-operation from the surgery date
    static func calculateWeekPostOp(from surgeryDate: Date) -> Int {
        let now = Date()
        let diffTime = abs(now.timeIntervalSince(surgeryDate))
        let diffDays = Int(diffTime / (60 * 60 * 24))
        return diffDays / 7
    }

    /// Format a date for display (e.g., "January 15, 2024")
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Format a date for short display (e.g., "Jan 15")
    static func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Format a time for display (e.g., "2:30 PM")
    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Format a date with weekday (e.g., "Monday, January 15, 2024")
    static func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }

    /// Get today's date formatted (e.g., "January 15")
    static var todayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }

    /// Group measurements by date string key
    static func groupByDate<T>(_ items: [T], dateExtractor: (T) -> Date) -> [(date: String, items: [T])] {
        var groups: [String: [T]] = [:]

        for item in items {
            let dateKey = formatDate(dateExtractor(item))
            if groups[dateKey] == nil {
                groups[dateKey] = []
            }
            groups[dateKey]?.append(item)
        }

        return groups.map { (date: $0.key, items: $0.value) }
            .sorted { item1, item2 in
                guard let date1 = items.first(where: { formatDate(dateExtractor($0)) == item1.date }).map(dateExtractor),
                      let date2 = items.first(where: { formatDate(dateExtractor($0)) == item2.date }).map(dateExtractor) else {
                    return false
                }
                return date1 > date2
            }
    }
}
