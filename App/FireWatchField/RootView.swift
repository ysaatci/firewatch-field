import FireWatchCore
import SwiftUI

/// The app's four sections, with the connection status and alerts on top.
struct RootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case map, hotspots, report, settings

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .map: "Map"
            case .hotspots: "Hotspots"
            case .report: "Report"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .map: "map"
            case .hotspots: "flame"
            case .report: "exclamationmark.bubble"
            case .settings: "gearshape"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack {
                MapScreen().withStatus(model.field)
            }
            .tabItem { Label(Section.map.title, systemImage: Section.map.symbol) }
            .tag(Section.map)

            NavigationStack(path: $router.hotspotPath) {
                HotspotListScreen().withStatus(model.field)
            }
            .tabItem { Label(Section.hotspots.title, systemImage: Section.hotspots.symbol) }
            .tag(Section.hotspots)

            ForEach([Section.report, .settings]) { section in
                NavigationStack {
                    placeholder(for: section).navigationTitle(section.title)
                }
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
            }
        }
        .overlay(alignment: .top) {
            if let alert = model.banner {
                AlertBanner(
                    alert: alert,
                    open: {
                        router.open(alert.hotspotID)
                        model.banner = nil
                    },
                    dismiss: { model.banner = nil }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: model.banner)
    }

    /// Stand-in content until each section is built; shows the live session is running.
    private func placeholder(for section: Section) -> some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.symbol)
        } description: {
            Text("\(model.field.fire.hotspots.count) hotspots · \(model.field.fire.drones.count) drones")
                .accessibilityIdentifier("summary")
        }
    }
}

extension View {
    /// Puts the feed's connection status in the navigation bar.
    func withStatus(_ field: FieldState) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionBadge(field: field) }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .environment(Router())
        .environment(LocationProvider())
}
