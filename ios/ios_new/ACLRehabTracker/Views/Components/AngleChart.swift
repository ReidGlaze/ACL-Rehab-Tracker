import SwiftUI

struct AngleChart: View {
    let measurements: [Measurement]
    let chartType: MeasurementType

    private let chartPadding = EdgeInsets(top: 20, leading: 50, bottom: 40, trailing: 20)

    private var yRange: (min: CGFloat, max: CGFloat) {
        if chartType == .extension {
            return (min: -10, max: 30)
        }
        return (min: 0, max: 150)
    }

    private var milestones: [(value: Int, label: String)] {
        if chartType == .extension {
            return [(value: 0, label: "Full Extension")]
        }
        return [
            (value: 90, label: "90°"),
            (value: 120, label: "120°"),
            (value: 135, label: "Full Flexion")
        ]
    }

    private var sortedMeasurements: [Measurement] {
        measurements.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("\(chartType.displayName) Over Time")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.text)

            if sortedMeasurements.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("No data yet")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textSecondary)

            Text("Take measurements to see your progress")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var chartContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 200

            let innerWidth = width - chartPadding.leading - chartPadding.trailing
            let innerHeight = height - chartPadding.top - chartPadding.bottom

            ZStack {
                // Grid lines
                gridLines(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top)

                // Milestone lines
                milestonesLayer(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top)

                // Data line and points
                dataLayer(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top)

                // Y-axis labels
                yAxisLabels(innerHeight: innerHeight)

                // X-axis labels
                xAxisLabels(innerWidth: innerWidth, innerHeight: innerHeight)
                    .offset(x: chartPadding.leading, y: chartPadding.top + innerHeight + 10)
            }
        }
        .frame(height: 200)
    }

    private func gridLines(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5) { i in
                let ratio = CGFloat(i) / 4.0
                let y = innerHeight * ratio

                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: innerWidth, y: y))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(AppColors.border)
            }
        }
    }

    private func milestonesLayer(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        ZStack {
            ForEach(milestones, id: \.value) { milestone in
                let y = getY(CGFloat(milestone.value), innerHeight: innerHeight)

                if y >= 0 && y <= innerHeight {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: innerWidth, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundColor(AppColors.success)

                    Text(milestone.label)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.success)
                        .position(x: innerWidth - 40, y: y - 10)
                }
            }
        }
    }

    private func dataLayer(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        ZStack {
            // Line
            Path { path in
                guard !sortedMeasurements.isEmpty else { return }

                let firstPoint = CGPoint(
                    x: getX(0, total: sortedMeasurements.count, innerWidth: innerWidth),
                    y: getY(CGFloat(sortedMeasurements[0].angle), innerHeight: innerHeight)
                )
                path.move(to: firstPoint)

                for i in 1..<sortedMeasurements.count {
                    let point = CGPoint(
                        x: getX(i, total: sortedMeasurements.count, innerWidth: innerWidth),
                        y: getY(CGFloat(sortedMeasurements[i].angle), innerHeight: innerHeight)
                    )
                    path.addLine(to: point)
                }
            }
            .stroke(AppColors.primary, lineWidth: 3)

            // Points
            ForEach(Array(sortedMeasurements.enumerated()), id: \.element.id) { index, measurement in
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(AppColors.background, lineWidth: 2)
                    )
                    .position(
                        x: getX(index, total: sortedMeasurements.count, innerWidth: innerWidth),
                        y: getY(CGFloat(measurement.angle), innerHeight: innerHeight)
                    )
            }
        }
    }

    private func yAxisLabels(innerHeight: CGFloat) -> some View {
        VStack {
            ForEach(0..<5) { i in
                let ratio = CGFloat(i) / 4.0
                let value = Int(yRange.max - ratio * (yRange.max - yRange.min))

                Text("\(value)°")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 40, alignment: .trailing)

                if i < 4 {
                    Spacer()
                }
            }
        }
        .frame(height: innerHeight)
        .offset(y: chartPadding.top)
    }

    private func xAxisLabels(innerWidth: CGFloat, innerHeight: CGFloat) -> some View {
        HStack {
            if let first = sortedMeasurements.first {
                Text("Week \(first.weekPostOp)")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if sortedMeasurements.count > 1, let last = sortedMeasurements.last {
                Text("Week \(last.weekPostOp)")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(width: innerWidth)
    }

    private func getX(_ index: Int, total: Int, innerWidth: CGFloat) -> CGFloat {
        if total <= 1 { return innerWidth / 2 }
        return (CGFloat(index) / CGFloat(total - 1)) * innerWidth
    }

    private func getY(_ value: CGFloat, innerHeight: CGFloat) -> CGFloat {
        let normalized = (value - yRange.min) / (yRange.max - yRange.min)
        return innerHeight * (1 - normalized)
    }
}

#Preview {
    VStack {
        AngleChart(
            measurements: [
                Measurement(id: "1", type: .extension, angle: 15, timestamp: Date().addingTimeInterval(-86400 * 14), weekPostOp: 1),
                Measurement(id: "2", type: .extension, angle: 10, timestamp: Date().addingTimeInterval(-86400 * 7), weekPostOp: 2),
                Measurement(id: "3", type: .extension, angle: 5, timestamp: Date(), weekPostOp: 3)
            ],
            chartType: .extension
        )

        AngleChart(
            measurements: [],
            chartType: .flexion
        )
    }
    .padding()
    .background(AppColors.background)
}
