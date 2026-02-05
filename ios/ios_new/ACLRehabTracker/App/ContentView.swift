import SwiftUI

enum NavigationPath: Hashable {
    case welcome
    case nameInput
    case injuryInfo
    case surgeryDate
    case main
}

enum MainTab: String, CaseIterable {
    case home = "Home"
    case measure = "Measure"
    case history = "History"
    case progress = "Progress"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .measure: return "plus.circle.fill"
        case .history: return "list.bullet"
        case .progress: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct ContentView: View {
    @StateObject private var authService = AuthService.shared
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("tempUserName") private var tempUserName = ""
    @AppStorage("surgeryDate") private var surgeryDateString = ""

    @State private var navigationPath: [NavigationPath] = []
    @State private var userName = ""
    @State private var injuredKnee: KneeSide = .right
    @State private var injuryType: InjuryType = .aclOnly
    @State private var surgeryDate = Date()
    @State private var selectedTab: MainTab = .home

    var body: some View {
        Group {
            if authService.isLoading {
                loadingView
            } else if !onboardingComplete {
                onboardingFlow
            } else {
                mainTabView
            }
        }
        .task {
            await ensureAuthenticated()
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
        }
    }

    // MARK: - Onboarding Flow
    private var onboardingFlow: some View {
        NavigationStack(path: $navigationPath) {
            WelcomeView {
                navigationPath.append(.nameInput)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: NavigationPath.self) { path in
                switch path {
                case .welcome:
                    WelcomeView {
                        navigationPath.append(.nameInput)
                    }
                    .navigationBarHidden(true)

                case .nameInput:
                    NameInputView(name: $userName) {
                        navigationPath.append(.injuryInfo)
                    }
                    .navigationBarHidden(true)

                case .injuryInfo:
                    InjuryInfoView(
                        injuredKnee: $injuredKnee,
                        injuryType: $injuryType
                    ) {
                        navigationPath.append(.surgeryDate)
                    }
                    .navigationBarHidden(true)

                case .surgeryDate:
                    SurgeryDateView(surgeryDate: $surgeryDate) {
                        Task {
                            await completeOnboarding()
                        }
                    }
                    .navigationBarHidden(true)

                case .main:
                    mainTabView
                        .navigationBarHidden(true)
                }
            }
        }
    }

    // MARK: - Main Tab View
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView(onNavigateToMeasure: { selectedTab = .measure })
                .tabItem {
                    Label(MainTab.home.rawValue, systemImage: MainTab.home.icon)
                }
                .tag(MainTab.home)

            MeasureView()
                .tabItem {
                    Label(MainTab.measure.rawValue, systemImage: MainTab.measure.icon)
                }
                .tag(MainTab.measure)

            HistoryView()
                .tabItem {
                    Label(MainTab.history.rawValue, systemImage: MainTab.history.icon)
                }
                .tag(MainTab.history)

            RehabProgressView()
                .tabItem {
                    Label(MainTab.progress.rawValue, systemImage: MainTab.progress.icon)
                }
                .tag(MainTab.progress)
        }
        .accentColor(AppColors.primary)
        .onAppear {
            configureTabBarAppearance()
        }
    }

    // MARK: - Authentication
    private func ensureAuthenticated() async {
        guard !authService.isAuthenticated else { return }

        do {
            _ = try await authService.signInAnonymously()
        } catch {
            print("Auth error: \(error)")
        }
    }

    // MARK: - Onboarding Completion
    private func completeOnboarding() async {
        guard let uid = authService.currentUserId else { return }

        let profile = UserProfile(
            name: userName,
            surgeryDate: surgeryDate,
            injuredKnee: injuredKnee,
            injuryType: injuryType,
            createdAt: Date()
        )

        do {
            try await FirestoreService.shared.saveUserProfile(uid: uid, profile: profile)
            await MainActor.run {
                onboardingComplete = true
            }
        } catch {
            print("Error saving profile: \(error)")
        }
    }

    // MARK: - Tab Bar Appearance
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppColors.surface)

        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(AppColors.textSecondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.textSecondary)
        ]

        // Selected state
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppColors.primary)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.primary)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
}
