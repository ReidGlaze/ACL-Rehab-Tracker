import SwiftUI

struct RehabProgressView: View {
    @StateObject private var authService = AuthService.shared

    @State private var measurements: [Measurement] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var extensionMeasurements: [Measurement] {
        measurements.filter { $0.type == .extension }.sorted { $0.timestamp < $1.timestamp }
    }

    private var flexionMeasurements: [Measurement] {
        measurements.filter { $0.type == .flexion }.sorted { $0.timestamp < $1.timestamp }
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

                // Current Status Cards
                currentStatusSection

                // Dual Line Chart
                DualLineChart(measurements: measurements)

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
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Current Status Section
    private var currentStatusSection: some View {
        HStack(spacing: AppSpacing.md) {
            // Extension card
            statusCard(
                type: .extension,
                measurements: extensionMeasurements,
                color: Color(hex: "4A9EFF")
            )

            // Flexion card
            statusCard(
                type: .flexion,
                measurements: flexionMeasurements,
                color: AppColors.primary
            )
        }
    }

    private func statusCard(type: MeasurementType, measurements: [Measurement], color: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(type.displayName.uppercased())
                .font(AppTypography.caption1)
                .foregroundColor(color)
                .tracking(1)

            if let latest = measurements.last {
                Text("\(latest.angle)°")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(AppColors.text)

                Text("Goal: \(type.goalAngle)°")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textTertiary)

                // Progress indicator
                let progress = type == .extension
                    ? max(0, 1 - Double(latest.angle) / 30.0) // Extension: lower is better
                    : min(1, Double(latest.angle) / 135.0)    // Flexion: higher is better

                ProgressBar(progress: progress, color: color)
                    .frame(height: 4)
                    .padding(.top, AppSpacing.xs)
            } else {
                Text("--")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)

                Text("No data")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(spacing: AppSpacing.md) {
            // Extension stats
            if !extensionMeasurements.isEmpty {
                statsRow(
                    type: .extension,
                    measurements: extensionMeasurements,
                    color: Color(hex: "4A9EFF")
                )
            }

            // Flexion stats
            if !flexionMeasurements.isEmpty {
                statsRow(
                    type: .flexion,
                    measurements: flexionMeasurements,
                    color: AppColors.primary
                )
            }

            // Total count
            HStack {
                Text("Total Measurements")
                    .font(AppTypography.subhead)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("\(measurements.count)")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)
            }
            .padding(AppSpacing.md)
            .background(AppColors.surface)
            .cornerRadius(AppRadius.md)
        }
    }

    private func statsRow(type: MeasurementType, measurements: [Measurement], color: Color) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Label
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(type.displayName)
                .font(AppTypography.subhead)
                .foregroundColor(AppColors.text)

            Spacer()

            // Best
            VStack(alignment: .trailing, spacing: 2) {
                Text("Best")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textTertiary)
                let best = type == .extension
                    ? measurements.map(\.angle).min() ?? 0
                    : measurements.map(\.angle).max() ?? 0
                Text("\(best)°")
                    .font(AppTypography.headline)
                    .foregroundColor(color)
            }

            // Latest
            VStack(alignment: .trailing, spacing: 2) {
                Text("Latest")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textTertiary)
                Text("\(measurements.last?.angle ?? 0)°")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.text)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.md)
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
                errorMessage = "Failed to load progress data."
                isLoading = false
            }
        }
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.surfaceLight)

                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(min(1, max(0, progress))))
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
    RehabProgressView()
}
