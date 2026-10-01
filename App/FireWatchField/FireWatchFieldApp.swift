import SwiftUI

@main
struct FireWatchFieldApp: App {
    @State private var model = AppModel()
    @State private var location = LocationProvider()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(location)
                .task {
                    location.start()
                    await model.start()
                }
                .onChange(of: location.coordinate) { _, coordinate in
                    Task { await model.setUserLocation(coordinate) }
                }
        }
    }
}
