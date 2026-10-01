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

    @State private var selection = Section.map

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Section.allCases) { section in
                NavigationStack {
                    ContentUnavailableView(section.title, systemImage: section.symbol)
                        .navigationTitle(section.title)
                }
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
                .accessibilityIdentifier("tab.\(section.rawValue)")
            }
        }
    }
}

#Preview {
    RootView()
}
