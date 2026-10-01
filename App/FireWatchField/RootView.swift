import FireWatchCore
import SwiftUI

/// The app's four sections.
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
    @State private var selection = Section.map

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Section.allCases) { section in
                NavigationStack {
                    switch section {
                    case .map: MapScreen()
                    case .hotspots: HotspotListScreen()
                    default: placeholder(for: section).navigationTitle(section.title)
                    }
                }
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
            }
        }
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

#Preview {
    RootView()
        .environment(AppModel())
}
