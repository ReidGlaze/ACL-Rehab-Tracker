import SwiftUI

struct HomeView: View {
    var onNavigateToMeasure: () -> Void = {}

    @StateObject private var authService = AuthService.shared
    @State private var weekPostOp = 0
    @State private var userName = ""
    @State private var latestExtension: Measurement?
    @State private var latestFlexion: Measurement?
    @State private var isLoading = true
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                header

                // Week Card
                weekCard

                // Latest Measurements Section
                measurementsSection

                // Measure Now Button
                Button(action: onNavigateToMeasure) {
                    Text("Measure Now")
                }
                .buttonStyle(PrimaryButtonStyle())

                // Last Updated
                if let timestamp = latestExtension?.timestamp ?? latestFlexion?.timestamp {
                    Text("Last updated: \(formatLastUpdate(timestamp))")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textTertiary)
                }
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

    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(userName.isEmpty ? "Today" : "Hey, \(userName)")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)

                Text(DateHelpers.todayFormatted)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Avatar
            Circle()
                .fill(AppColors.surfaceLight)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(userName.isEmpty ? "?" : String(userName.prefix(1)).uppercased())
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.text)
                )
        }
    }

    // MARK: - Week Card
    private var weekCard: some View {
        VStack(spacing: 0) {
            Text("Week")
                .font(AppTypography.body)
                .foregroundColor(AppColors.background.opacity(0.8))

            Text("\(weekPostOp)")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(AppColors.background)

            Text("Post-Op Recovery")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.background.opacity(0.9))
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColors.success)
        .cornerRadius(AppRadius.lg)
    }

    // MARK: - Measurements Section
    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Latest Measurements")
                .font(AppTypography.title3)
                .foregroundColor(AppColors.text)

            HStack(spacing: AppSpacing.md) {
                MeasurementCard(
                    label: "Extension",
                    value: latestExtension.map { "\($0.angle)°" },
                    goal: "Goal: 0°"
                )

                MeasurementCard(
                    label: "Flexion",
                    value: latestFlexion.map { "\($0.angle)°" },
                    goal: "Goal: 135°"
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
            // Get profile
            if let profile = try await FirestoreService.shared.getUserProfile(uid: uid) {
                await MainActor.run {
                    userName = profile.name
                    weekPostOp = DateHelpers.calculateWeekPostOp(from: profile.surgeryDate)
                }
            }

            // Get measurements
            let measurements = try await FirestoreService.shared.getMeasurements(uid: uid)
            await MainActor.run {
                latestExtension = measurements.first { $0.type == .extension }
                latestFlexion = measurements.first { $0.type == .flexion }
                isLoading = false
            }
        } catch {
            print("Error loading home data: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func formatLastUpdate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Measurement Card
struct MeasurementCard: View {
    let label: String
    let value: String?
    let goal: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(label.uppercased())
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
                .tracking(1)

            Text(value ?? "--")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(value != nil ? AppColors.text : AppColors.textTertiary)

            Text(goal)
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(AppRadius.lg)
    }
}

#Preview {
    HomeView(onNavigateToMeasure: {})
}
