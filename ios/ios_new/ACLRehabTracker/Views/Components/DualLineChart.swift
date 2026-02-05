import SwiftUI

/// A daily average data point for charting
struct DailyAverage: Identifiable {
    let id = UUID()
    let date: Date
    let average: Double
    let count: Int
}

/// Dual line chart showing Extension and Flexion daily averages
struct DualLineChart: View {
    let measurements: [Measurement]

    private let chartPadding = EdgeInsets(top: 30, leading: 50, bottom: 50, trailing: 20)

    // Y-axis range: 0° to 140° to show both extension and flexion
    private let yMin: CGFloat = -5
    private let yMax: CGFloat = 145

    // Colors
    private let extensionColor = Color(hex: "4A9EFF") // Blue
    private let flexionColor = AppColors.primary // Pink

    private var extensionAverages: [DailyAverage] {
        computeDailyAverages(for: .extension)
    }

    private var flexionAverages: [DailyAverage] {
        computeDailyAverages(for: .flexion)
    }

    private var allDates: [Date] {
        let extensionDates = extensionAverages.map { $0.date }
        let flexionDates = flexionAverages.map { $0.date }
        let combined = Set(extensionDates + flexionDates)
        return combined.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Title
            Text("Progress Over Time")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.text)

            // Legend
            legend

            if measurements.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    // MARK: - Legend
    private var legend: some View {
        HStack(spacing: AppSpacing.lg) {
            legendItem(color: extensionColor, label: "Extension", goal: "Goal: 0°")
            legendItem(color: flexionColor, label: "Flexion", goal: "Goal: 135°")
        }
    }

    private func legendItem(color: Color, label: String, goal: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(AppTypography.caption1)
                    .foregroundColor(AppColors.text)
                Text(goal)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)

            Text("No data yet")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textSecondary)

            Text("Take measurements to track your progress")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart Content
    private var chartContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 220

            let innerWidth = width - chartPadding.leading - chartPadding.trailing
            let innerHeight = height - chartPadding.top - chartPadding.bottom

            ZStack {
                // Grid lines
                gridLines(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top)

                // Goal lines (dashed)
                goalLines(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top)

                // Extension line (blue)
                dataLine(
                    averages: extensionAverages,
                    color: extensionColor,
                    innerWidth: innerWidth,
                    innerHeight: innerHeight
                )
                .offset(x: chartPadding.leading, y: chartPadding.top)

                // Flexion line (pink)
                dataLine(
                    averages: flexionAverages,
                    color: flexionColor,
                    innerWidth: innerWidth,
                    innerHeight: innerHeight
                )
                .offset(x: chartPadding.leading, y: chartPadding.top)

                // Y-axis labels
                yAxisLabels(innerHeight: innerHeight)

                // X-axis labels
                xAxisLabels(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top + innerHeight + 8)
            }
        }
        .frame(height: 220)
    }

    // MARK: - Grid Lines
    private func gridLines(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        ZStack {
            // Horizontal grid lines at 0, 45, 90, 135
            ForEach([0, 45, 90, 135], id: \.self) { value in
                let y = getY(CGFloat(value), innerHeight: innerHeight)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: innerWidth, y: y))
                }
                .stroke(AppColors.border, lineWidth: 1)
            }
        }
    }

    // MARK: - Goal Lines
    private func goalLines(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        ZStack {
            // Extension goal at 0°
            let y0 = getY(0, innerHeight: innerHeight)
            Path { path in
                path.move(to: CGPoint(x: 0, y: y0))
                path.addLine(to: CGPoint(x: innerWidth, y: y0))
            }
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .foregroundColor(extensionColor.opacity(0.6))

            // Flexion goal at 135°
            let y135 = getY(135, innerHeight: innerHeight)
            Path { path in
                path.move(to: CGPoint(x: 0, y: y135))
                path.addLine(to: CGPoint(x: innerWidth, y: y135))
            }
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .foregroundColor(flexionColor.opacity(0.6))
        }
    }

    // MARK: - Data Line
    private func dataLine(averages: [DailyAverage], color: Color, innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        ZStack {
            // Line
            if averages.count > 1 {
                Path { path in
                    guard !averages.isEmpty else { return }

                    let firstPoint = CGPoint(
                        x: getX(averages[0].date, innerWidth: innerWidth),
                        y: getY(CGFloat(averages[0].average), innerHeight: innerHeight)
                    )
                    path.move(to: firstPoint)

                    for i in 1..<averages.count {
                        let point = CGPoint(
                            x: getX(averages[i].date, innerWidth: innerWidth),
                            y: getY(CGFloat(averages[i].average), innerHeight: innerHeight)
                        )
                        path.addLine(to: point)
                    }
                }
                .stroke(color, lineWidth: 3)
            }

            // Points
            ForEach(averages) { avg in
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(AppColors.surface, lineWidth: 2)
                    )
                    .position(
                        x: getX(avg.date, innerWidth: innerWidth),
                        y: getY(CGFloat(avg.average), innerHeight: innerHeight)
                    )
            }
        }
    }

    // MARK: - Y-Axis Labels
    private func yAxisLabels(innerHeight: CGFloat) -> some View {
        VStack(alignment: .trailing) {
            ForEach([135, 90, 45, 0], id: \.self) { value in
                Text("\(value)°")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 40, alignment: .trailing)

                if value != 0 {
                    Spacer()
                }
            }
        }
        .frame(height: innerHeight)
        .offset(y: chartPadding.top)
    }

    // MARK: - X-Axis Labels
    private func xAxisLabels(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        let dates = allDates
        guard !dates.isEmpty else { return AnyView(EmptyView()) }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"

        return AnyView(
            HStack {
                if let first = dates.first {
                    Text(formatter.string(from: first))
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                if dates.count > 1, let last = dates.last {
                    Text(formatter.string(from: last))
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .frame(width: innerWidth)
        )
    }

    // MARK: - Helpers
    private func computeDailyAverages(for type: MeasurementType) -> [DailyAverage] {
        let filtered = measurements.filter { $0.type == type }

        // Group by day
        let calendar = Calendar.current
        var grouped: [Date: [Int]] = [:]

        for measurement in filtered {
            let dayStart = calendar.startOfDay(for: measurement.timestamp)
            grouped[dayStart, default: []].append(measurement.angle)
        }

        // Compute averages
        return grouped.map { date, angles in
            let avg = Double(angles.reduce(0, +)) / Double(angles.count)
            return DailyAverage(date: date, average: avg, count: angles.count)
        }
        .sorted { $0.date < $1.date }
    }

    private func getX(_ date: Date, innerWidth: CGFloat) -> CGFloat {
        let dates = allDates
        guard dates.count > 1,
              let firstDate = dates.first,
              let lastDate = dates.last else {
            return innerWidth / 2
        }

        let totalRange = lastDate.timeIntervalSince(firstDate)
        guard totalRange > 0 else { return innerWidth / 2 }

        let position = date.timeIntervalSince(firstDate)
        return CGFloat(position / totalRange) * innerWidth
    }

    private func getY(_ value: CGFloat, innerHeight: CGFloat) -> CGFloat {
        let normalized = (value - yMin) / (yMax - yMin)
        return innerHeight * (1 - normalized)
    }
}

#Preview {
    VStack {
        DualLineChart(
            measurements: [
                // Extension measurements (should trend down toward 0)
                Measurement(id: "1", type: .extension, angle: 20, timestamp: Date().addingTimeInterval(-86400 * 10), weekPostOp: 1),
                Measurement(id: "2", type: .extension, angle: 18, timestamp: Date().addingTimeInterval(-86400 * 10), weekPostOp: 1),
                Measurement(id: "3", type: .extension, angle: 15, timestamp: Date().addingTimeInterval(-86400 * 7), weekPostOp: 2),
                Measurement(id: "4", type: .extension, angle: 10, timestamp: Date().addingTimeInterval(-86400 * 3), weekPostOp: 2),
                Measurement(id: "5", type: .extension, angle: 5, timestamp: Date(), weekPostOp: 3),

                // Flexion measurements (should trend up toward 135)
                Measurement(id: "6", type: .flexion, angle: 60, timestamp: Date().addingTimeInterval(-86400 * 10), weekPostOp: 1),
                Measurement(id: "7", type: .flexion, angle: 75, timestamp: Date().addingTimeInterval(-86400 * 7), weekPostOp: 2),
                Measurement(id: "8", type: .flexion, angle: 90, timestamp: Date().addingTimeInterval(-86400 * 3), weekPostOp: 2),
                Measurement(id: "9", type: .flexion, angle: 110, timestamp: Date(), weekPostOp: 3),
            ]
        )

        DualLineChart(measurements: [])
    }
    .padding()
    .background(AppColors.background)
}
