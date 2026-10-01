import SwiftUI

/// Shown once, at first launch: what this app is, and that the fire is simulated (FR-11).
struct IntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "flame.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange.gradient)
            Text("FireWatch Field")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 16) {
                point("map", "See hotspots that drones found, the fire's edge, and where the drones are.")
                point("flame", "Work hotspots from new to verified cold, most urgent first.")
                point("wifi.slash", "No signal? Actions and reports wait on the phone and send later.")
                point(
                    "play.circle",
                    "This is a demo: a simulated wildfire near Manavgat plays on this phone. Settings can connect to the simulator server instead."
                )
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("startButton")
        }
        .padding(28)
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .frame(width: 28)
        }
        .font(.body)
    }
}

#Preview {
    IntroSheet()
}
