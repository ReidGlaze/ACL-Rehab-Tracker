import SwiftUI

struct ProgressView: View {
    @StateObject private var authService = AuthService.shared

    @State private var measurements: [Measurement] = []
    @State private var chartType: MeasurementType = .extension
    @State private var isLoading = true

    private var filteredMeasurements: [Measurement] {
        measurements
            .filter { $0.type == chartType }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var progressInfo: (improved: Bool, change: Int)? {
        guard filteredMeasurements.count >= 2 else { return nil }

        let latest = filteredMeasurements[filteredMeasurements.count - 1]
        let previous = filteredMeasurements[filteredMeasurements.count - 2]
        let diff = latest.angle - previous.angle

        if chartType == .extension {
            // For extension, lower is better
            return (improved: diff < 0, change: abs(diff))
        }
        // For flexion, higher is better
        return (improved: diff > 0, change: abs(diff))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                HStack {
                    Text("Progress")
                        .font(AppTypography.largeTitle)
                        .foregroundColor(AppColors.text)
                    Spacer()
                }

                // Type Toggle
                typeToggle

                // Insight Card
                if let progress = progressInfo {
                    insightCard(progress: progress)
                }

                // Chart
                AngleChart(measurements: filteredMeasurements, chartType: chartType)

                // Stats
                statsSection
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.background)
        .refreshable {
            await loadData()
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Type Toggle
    private var typeToggle: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(MeasurementType.allCases, id: \.self) { type in
                Button(action: { chartType = type }) {
                    Text(type.displayName)
                        .font(AppTypography.headline)
                        .foregroundColor(chartType == type ? AppColors.text : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(chartType == type ? AppColors.surfaceLight : Color.clear)
                        .cornerRadius(AppRadius.md)
                }
            }
        }
        .padding(AppSpacing.xs)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    // MARK: - Insight Card
    private func insightCard(progress: (improved: Bool, change: Int)) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text("LATEST CHANGE")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
                .tracking(1)

            Text("\(progress.improved ? "+" : "-")\(progress.change)°")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(progress.improved ? AppColors.success : AppColors.warning)

            Text(progress.improved ? "Great progress! Keep it up." : "Keep working on your exercises.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: AppSpacing.md) {
            StatCard(label: "Total Measurements", value: "\(filteredMeasurements.count)")

            if !filteredMeasurements.isEmpty {
                StatCard(
                    label: "Best",
                    value: "\(chartType == .extension ? filteredMeasurements.map(\.angle).min() ?? 0 : filteredMeasurements.map(\.angle).max() ?? 0)°"
                )

                StatCard(
                    label: "Latest",
                    value: "\(filteredMeasurements.last?.angle ?? 0)°"
                )
            }
        }
    }

    // MARK: - Data Loading
    private func loadData() async {
        guard let uid = authService.currentUserId else {
            isLoading = false
            return
        }

        do {
            let data = try await FirestoreService.shared.getMeasurements(uid: uid)
            await MainActor.run {
                measurements = data
                isLoading = false
            }
        } catch {
            print("Error loading measurements: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(label)
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.textSecondary)

            Text(value)
                .font(AppTypography.title2)
                .foregroundColor(AppColors.text)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }
}

#Preview {
    ProgressView()
}
