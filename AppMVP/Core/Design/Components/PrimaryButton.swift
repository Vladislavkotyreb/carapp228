import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.buttonHeight)
            .background(isDisabled ? Color.gray : AppColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .disabled(isDisabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.primary)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.buttonHeight)
                .background(AppColors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}
