import Foundation
import FirebaseAuth
import Combine

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = true

    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        setupAuthStateListener()
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                self?.isLoading = false
            }
        }
    }

    /// Sign in anonymously
    func signInAnonymously() async throws -> String {
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    /// Get current user ID
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    /// Check if user is signed in
    var isSignedIn: Bool {
        Auth.auth().currentUser != nil
    }

    /// Sign out
    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// Delete current user account
    func deleteUser() async throws {
        try await Auth.auth().currentUser?.delete()
    }
}
