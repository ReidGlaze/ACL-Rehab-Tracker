import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var injuredKnee: KneeSide = .right
    @State private var injuryType: InjuryType = .aclOnly
    @State private var surgeryDate = Date()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showPrivacyPolicy = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Avatar
                    Circle()
                        .fill(AppColors.surfaceLight)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(AppColors.text)
                        )
                        .padding(.top, AppSpacing.md)

                    if isLoading {
                        ProgressView()
                            .tint(AppColors.primary)
                    } else {
                        // Name
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Name")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.text)

                            TextField("Your name", text: $name)
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.text)
                                .padding(AppSpacing.md)
                                .background(AppColors.inputBackground)
                                .cornerRadius(AppRadius.md)
                        }

                        // Knee Selection
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Injured Knee")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.text)

                            HStack(spacing: AppSpacing.md) {
                                ForEach(KneeSide.allCases, id: \.self) { side in
                                    Button {
                                        injuredKnee = side
                                    } label: {
                                        Text(side.displayName)
                                            .font(AppTypography.headline)
                                            .foregroundColor(injuredKnee == side ? AppColors.text : AppColors.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, AppSpacing.md)
                                            .background(injuredKnee == side ? AppColors.surface : AppColors.background)
                                            .cornerRadius(AppRadius.md)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: AppRadius.md)
                                                    .stroke(injuredKnee == side ? AppColors.primary : AppColors.border, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }

                        // Injury Type
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Injury Type")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.text)

                            VStack(spacing: AppSpacing.xs) {
                                ForEach(InjuryType.allCases, id: \.self) { type in
                                    Button {
                                        injuryType = type
                                    } label: {
                                        HStack {
                                            Text(type.displayName)
                                                .font(AppTypography.body)
                                                .foregroundColor(injuryType == type ? AppColors.text : AppColors.textSecondary)

                                            Spacer()

                                            if injuryType == type {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(AppColors.success)
                                            }
                                        }
                                        .padding(AppSpacing.md)
                                        .background(injuryType == type ? AppColors.surface : AppColors.background)
                                        .cornerRadius(AppRadius.md)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppRadius.md)
                                                .stroke(injuryType == type ? AppColors.primary : AppColors.border, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }

                        // Surgery Date
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Surgery Date")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.text)

                            DatePicker(
                                "Surgery Date",
                                selection: $surgeryDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(AppColors.primary)
                        }

                        // Save Button
                        Button(action: save) {
                            if isSaving {
                                ProgressView()
                                    .tint(AppColors.text)
                            } else {
                                Text("Save Changes")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: !isSaving))
                        .disabled(isSaving)

                        // Privacy Policy Link
                        Button {
                            showPrivacyPolicy = true
                        } label: {
                            Text("Privacy Policy")
                                .font(AppTypography.footnote)
                                .foregroundColor(AppColors.textSecondary)
                                .underline()
                        }
                        .padding(.top, AppSpacing.sm)

                        // Delete Account
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Text("Delete Account")
                                .font(AppTypography.footnote)
                                .foregroundColor(.red)
                        }
                        .padding(.top, AppSpacing.lg)

                        // Version Info
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, AppSpacing.sm)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(AppColors.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .task {
                await loadProfile()
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        isDeleting = true
                        do {
                            if let uid = AuthService.shared.currentUserId {
                                try await FirestoreService.shared.deleteUserData(uid: uid)
                            }
                            try await AuthService.shared.deleteUser()
                            onboardingComplete = false
                            dismiss()
                        } catch {
                            print("Error deleting account: \(error)")
                            errorMessage = "Failed to delete account. Please try again."
                        }
                        isDeleting = false
                    }
                }
            } message: {
                Text("This will permanently delete your account and all data. This action cannot be undone.")
            }
        }
    }

    private func loadProfile() async {
        guard let uid = AuthService.shared.currentUserId else {
            isLoading = false
            return
        }
        do {
            if let profile = try await FirestoreService.shared.getUserProfile(uid: uid) {
                name = profile.name
                injuredKnee = profile.injuredKnee
                injuryType = profile.injuryType
                surgeryDate = profile.surgeryDate
            }
        } catch {
            print("Error loading profile: \(error)")
            errorMessage = "Failed to load profile."
        }
        isLoading = false
    }

    private func save() {
        guard let uid = AuthService.shared.currentUserId else { return }
        isSaving = true
        Task {
            do {
                let profile = UserProfile(
                    name: name,
                    surgeryDate: surgeryDate,
                    injuredKnee: injuredKnee,
                    injuryType: injuryType
                )
                try await FirestoreService.shared.saveUserProfile(uid: uid, profile: profile)
                dismiss()
            } catch {
                print("Error saving profile: \(error)")
                errorMessage = "Failed to save profile. Please try again."
            }
            isSaving = false
        }
    }
}

#Preview {
    ProfileView()
}
