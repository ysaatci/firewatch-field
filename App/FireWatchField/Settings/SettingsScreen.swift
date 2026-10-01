import FireWatchCore
import SwiftUI

/// Data source, alerts, units and demo controls (FR-10).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    @AppStorage(AppConfiguration.Keys.useServer) private var useServer = false
    @AppStorage(AppConfiguration.Keys.serverURL) private var serverURL = "http://localhost:8080"
    @AppStorage(AppConfiguration.Keys.demoSpeed) private var demoSpeed = AppConfiguration().demoSpeed
    @AppStorage(AppConfiguration.Keys.alertRadius) private var alertRadius = AppConfiguration().alertRadiusMetres
    @AppStorage(UnitSystem.defaultsKey) private var units = UnitSystem.automatic
    @State private var token = Keychain.string(for: AppConfiguration.Keys.serverToken) ?? ""
    @State private var simulateOutage = false

    var body: some View {
        Form {
            Section {
                Picker("Data", selection: $useServer) {
                    Text("Demo on this device").tag(false)
                    Text("Simulator server").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if useServer {
                    TextField("Server address", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Access token", text: $token)
                        .textContentType(.password)
                } else {
                    LabeledContent("Replay speed", value: "\(Int(demoSpeed))×")
                    Slider(value: $demoSpeed, in: 1...300, step: 1)
                        .accessibilityLabel("Replay speed")
                }
                Button("Apply and restart") { apply() }
                    .disabled(useServer && URL(string: serverURL)?.scheme == nil)
            } header: {
                Text("Data source")
            } footer: {
                Text(
                    useServer
                        ? "Connects to the simulator server, for example one started with docker compose."
                        : "A simulated wildfire near Manavgat plays on this phone. No network needed.")
            }

            Section {
                Toggle("Simulate no signal", isOn: $simulateOutage)
                    .accessibilityIdentifier("simulateOutage")
            } footer: {
                Text(
                    "Actions and reports wait on this phone and are sent when you turn this off, just as with real loss of signal."
                )
            }

            Section("Alerts") {
                LabeledContent("Alert radius", value: Format.distance(alertRadius))
                Slider(value: $alertRadius, in: 500...10_000, step: 500)
                    .accessibilityLabel("Alert radius")
            }

            Section("Units") {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.versionDescription)
                Link("Source code", destination: URL(staticString: "https://github.com/ysaatci/firewatch-field"))
            }
        }
        .navigationTitle("Settings")
        .onAppear { simulateOutage = model.outage.isActive }
        .onChange(of: simulateOutage) { _, active in model.outage.isActive = active }
        .onChange(of: alertRadius) { _, radius in Task { await model.setAlertRadius(radius) } }
    }

    private func apply() {
        Keychain.set(useServer ? token : nil, for: AppConfiguration.Keys.serverToken)
        Task { await model.apply(.fromDefaults()) }
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

extension URL {
    /// A URL from a literal known to be valid.
    init(staticString: StaticString) {
        guard let url = URL(string: "\(staticString)") else {
            preconditionFailure("Invalid URL literal \(staticString)")
        }
        self = url
    }
}
