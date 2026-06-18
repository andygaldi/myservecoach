import SwiftUI

struct ErrorView: View {
    let systemImage: String
    let title: String
    let message: String
    let primaryActionLabel: String
    let primaryAction: () -> Void
    var secondaryActionLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            VStack(spacing: 12) {
                Button(primaryActionLabel, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                if let label = secondaryActionLabel, let action = secondaryAction {
                    Button(label, action: action)
                        .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
