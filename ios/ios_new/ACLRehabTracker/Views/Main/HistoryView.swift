import SwiftUI

enum HistoryFilterType: String, CaseIterable {
    case all = "All"
    case `extension` = "Extension"
    case flexion = "Flexion"
}

struct HistoryView: View {
    @StateObject private var authService = AuthService.shared

    @State private var measurements: [Measurement] = []
    @State private var filter: HistoryFilterType = .all
    @State private var selectedPhotoUrl: String?
    @State private var isLoading = true
    @State private var showPhotoModal = false
    @State private var loadedImage: UIImage?
    @State private var isLoadingPhoto = false

    private var filteredMeasurements: [Measurement] {
        measurements.filter { measurement in
            switch filter {
            case .all: return true
            case .extension: return measurement.type == .extension
            case .flexion: return measurement.type == .flexion
            }
        }
    }

    private var groupedMeasurements: [(date: String, items: [Measurement])] {
        DateHelpers.groupByDate(filteredMeasurements) { $0.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)

            // Filter Pills
            filterPills
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                Spacer()
            } else if groupedMeasurements.isEmpty {
                emptyState
            } else {
                measurementsList
            }
        }
        .background(AppColors.background)
        .sheet(isPresented: $showPhotoModal) {
            photoModal
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Filter Pills
    private var filterPills: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(HistoryFilterType.allCases, id: \.self) { filterType in
                Button(action: { filter = filterType }) {
                    Text(filterType.rawValue)
                        .font(AppTypography.subhead)
                        .foregroundColor(filter == filterType ? AppColors.text : AppColors.textSecondary)
                        .padding(.vertical, AppSpacing.sm)
                        .padding(.horizontal, AppSpacing.md)
                        .background(filter == filterType ? AppColors.primary : AppColors.surface)
                        .cornerRadius(AppRadius.full)
                }
            }
            Spacer()
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("No measurements yet")
                .font(AppTypography.title3)
                .foregroundColor(AppColors.text)

            Text("Take your first measurement to see it here")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Measurements List
    private var measurementsList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.lg) {
                ForEach(groupedMeasurements, id: \.date) { group in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(group.date.uppercased())
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.textSecondary)
                            .tracking(1)

                        ForEach(group.items) { measurement in
                            MeasurementRow(measurement: measurement) {
                                if !measurement.photoUrl.isEmpty {
                                    selectedPhotoUrl = measurement.photoUrl
                                    showPhotoModal = true
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Photo Modal
    private var photoModal: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack {
                if isLoadingPhoto {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "photo.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Failed to load photo")
                            .font(AppTypography.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Button(action: {
                    showPhotoModal = false
                    loadedImage = nil
                }) {
                    Text("Close")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.text)
                        .padding(.vertical, AppSpacing.md)
                        .padding(.horizontal, AppSpacing.xl)
                        .background(AppColors.surface)
                        .cornerRadius(AppRadius.lg)
                }
                .padding(.bottom, AppSpacing.lg)
            }
            .padding(AppSpacing.lg)
        }
        .onAppear {
            loadPhoto()
        }
    }

    private func loadPhoto() {
        guard let urlString = selectedPhotoUrl, !urlString.isEmpty else { return }

        isLoadingPhoto = true
        loadedImage = nil

        Task {
            do {
                let image = try await StorageService.shared.downloadImage(from: urlString)
                await MainActor.run {
                    loadedImage = image
                    isLoadingPhoto = false
                }
            } catch {
                print("Error loading photo: \(error)")
                await MainActor.run {
                    isLoadingPhoto = false
                }
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

// MARK: - Measurement Row
struct MeasurementRow: View {
    let measurement: Measurement
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Type Badge
                Text(measurement.type.shortName)
                    .font(AppTypography.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.text)
                    .padding(.vertical, AppSpacing.xs)
                    .padding(.horizontal, AppSpacing.sm)
                    .background(
                        measurement.type == .extension
                            ? AppColors.success.opacity(0.3)
                            : AppColors.primary.opacity(0.3)
                    )
                    .cornerRadius(AppRadius.sm)

                // Angle and Time
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(measurement.angle)°")
                        .font(AppTypography.title3)
                        .foregroundColor(AppColors.text)

                    Text(DateHelpers.formatTime(measurement.timestamp))
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                // Photo indicator
                if !measurement.photoUrl.isEmpty {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.primary)
                }

                // Week Badge
                Text("Week \(measurement.weekPostOp)")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.vertical, AppSpacing.xs)
                    .padding(.horizontal, AppSpacing.sm)
                    .background(AppColors.surfaceLight)
                    .cornerRadius(AppRadius.sm)
            }
            .padding(AppSpacing.md)
            .background(AppColors.surface)
            .cornerRadius(AppRadius.md)
        }
    }
}

#Preview {
    HistoryView()
}
