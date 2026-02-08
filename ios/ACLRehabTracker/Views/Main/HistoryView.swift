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
    @State private var selectedWeek: Int? = nil
    @State private var selectedPhotoUrl: String?
    @State private var isLoading = true
    @State private var showPhotoModal = false
    @State private var loadedImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?
    @State private var measurementToDelete: Measurement?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    private var availableWeeks: [Int] {
        Array(Set(measurements.map { $0.weekPostOp })).sorted()
    }

    private var filteredMeasurements: [Measurement] {
        measurements.filter { measurement in
            let typeMatch: Bool
            switch filter {
            case .all: typeMatch = true
            case .extension: typeMatch = measurement.type == .extension
            case .flexion: typeMatch = measurement.type == .flexion
            }

            let weekMatch = selectedWeek == nil || measurement.weekPostOp == selectedWeek
            return typeMatch && weekMatch
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
                .padding(.bottom, AppSpacing.sm)

            // Week Scroller
            if !availableWeeks.isEmpty {
                weekScroller
                    .padding(.bottom, AppSpacing.md)
            }

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
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
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

    // MARK: - Week Scroller
    private var weekScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                // "All" chip
                Button(action: { selectedWeek = nil }) {
                    Text("All")
                        .font(AppTypography.caption1)
                        .fontWeight(selectedWeek == nil ? .semibold : .regular)
                        .foregroundColor(selectedWeek == nil ? AppColors.text : AppColors.textSecondary)
                        .padding(.vertical, AppSpacing.xs)
                        .padding(.horizontal, AppSpacing.md)
                        .background(selectedWeek == nil ? AppColors.primary.opacity(0.3) : AppColors.surface)
                        .cornerRadius(AppRadius.full)
                }

                // Week chips
                ForEach(availableWeeks, id: \.self) { week in
                    Button(action: { selectedWeek = week }) {
                        Text("Wk \(week)")
                            .font(AppTypography.caption1)
                            .fontWeight(selectedWeek == week ? .semibold : .regular)
                            .foregroundColor(selectedWeek == week ? AppColors.text : AppColors.textSecondary)
                            .padding(.vertical, AppSpacing.xs)
                            .padding(.horizontal, AppSpacing.md)
                            .background(selectedWeek == week ? AppColors.primary.opacity(0.3) : AppColors.surface)
                            .cornerRadius(AppRadius.full)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
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
        List {
            ForEach(groupedMeasurements, id: \.date) { group in
                Section {
                    ForEach(group.items) { measurement in
                        MeasurementRow(measurement: measurement) {
                            if !measurement.photoUrl.isEmpty {
                                selectedPhotoUrl = measurement.photoUrl
                                showPhotoModal = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                measurementToDelete = measurement
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: AppSpacing.lg, bottom: 4, trailing: AppSpacing.lg))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(group.date.uppercased())
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .tracking(1)
                        .listRowInsets(EdgeInsets(top: 8, leading: AppSpacing.lg, bottom: 4, trailing: AppSpacing.lg))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await loadData()
        }
        .confirmationDialog(
            "Delete Measurement",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let measurement = measurementToDelete {
                    deleteMeasurement(measurement)
                }
            }
            Button("Cancel", role: .cancel) {
                measurementToDelete = nil
            }
        } message: {
            Text("This will permanently delete this measurement and its photo. This cannot be undone.")
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

    // MARK: - Delete
    private func deleteMeasurement(_ measurement: Measurement) {
        guard let uid = authService.currentUserId,
              let measurementId = measurement.id else { return }

        Task {
            do {
                // Delete photo from Storage if it exists
                if !measurement.photoUrl.isEmpty {
                    try? await StorageService.shared.deletePhoto(uid: uid, measurementId: measurementId)
                }

                // Delete measurement from Firestore
                try await FirestoreService.shared.deleteMeasurement(uid: uid, measurementId: measurementId)

                // Remove from local list
                await MainActor.run {
                    measurements.removeAll { $0.id == measurement.id }
                    measurementToDelete = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete measurement."
                    measurementToDelete = nil
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
                errorMessage = "Failed to load history."
                isLoading = false
            }
        }
    }
}

// MARK: - Measurement Row
struct MeasurementRow: View {
    let measurement: Measurement
    let onTap: () -> Void

    @State private var thumbnailImage: UIImage?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                // Thumbnail
                if !measurement.photoUrl.isEmpty {
                    Group {
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(AppColors.surfaceLight)
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.textTertiary))
                                        .scaleEffect(0.7)
                                )
                        }
                    }
                    .frame(width: 56, height: 56)
                    .cornerRadius(AppRadius.sm)
                    .clipped()
                } else {
                    // No photo placeholder
                    Rectangle()
                        .fill(AppColors.surfaceLight)
                        .frame(width: 56, height: 56)
                        .cornerRadius(AppRadius.sm)
                        .overlay(
                            Image(systemName: "camera.slash")
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.textTertiary)
                        )
                }

                // Type Badge + Angle + Time
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: AppSpacing.sm) {
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

                        Text("\(measurement.angle)°")
                            .font(AppTypography.title3)
                            .foregroundColor(AppColors.text)
                    }

                    Text(DateHelpers.formatTime(measurement.timestamp))
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

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
        .task(id: measurement.photoUrl) {
            guard !measurement.photoUrl.isEmpty else { return }
            do {
                let image = try await StorageService.shared.downloadImage(from: measurement.photoUrl)
                await MainActor.run { thumbnailImage = image }
            } catch {
                print("Thumbnail load failed: \(error)")
            }
        }
    }
}

#Preview {
    HistoryView()
}
