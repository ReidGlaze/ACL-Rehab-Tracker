import SwiftUI

struct NameInputView: View {
    @Binding var name: String
    var onContinue: () -> Void

    @FocusState private var isInputFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack {
            // Header Section
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("First Things First")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)

                Text("Your name")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xxl)

            // Input Section
            VStack(spacing: 0) {
                TextField("Name", text: $name)
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.text)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isInputFocused)
                    .padding(.vertical, AppSpacing.md)

                Rectangle()
                    .fill(AppColors.primary)
                    .frame(height: 2)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)

            Spacer()

            // Continue Button
            Button(action: {
                if isValid {
                    onContinue()
                }
            }) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.text)
            }
            .buttonStyle(SecondaryButtonStyle(isEnabled: isValid))
            .disabled(!isValid)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
        .background(AppColors.background)
        .onAppear {
            isInputFocused = true
        }
    }
}

#Preview {
    NameInputView(name: .constant(""), onContinue: {})
}
