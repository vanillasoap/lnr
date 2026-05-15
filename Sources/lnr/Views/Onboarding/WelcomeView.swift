import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "circle.circle")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.quaternary)
                )

            Text("Welcome to lnr")
                .font(.title2.bold())

            Text("Your Linear issues in the menubar.\nLightweight, native, and stays out of your way.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Get Started") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Text("Takes about a minute")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }
}
