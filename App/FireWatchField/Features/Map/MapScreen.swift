import FireWatchCore
import MapKit
import SwiftUI

/// Hotspots, the fire perimeter and drones on a satellite map (FR-1, FR-2, FR-3).
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @State private var position = MapCameraPosition.automatic
    @State private var hasFramedFire = false
    @State private var clusterer = HotspotClusterer(cellSize: 300)
    @State private var selection: String?
    @State private var summary: Hotspot.ID?
    /// Index into the perimeter history; `nil` follows the latest.
    @State private var perimeterIndex: Int?

    private var fire: FireState { model.field.fire }

    var body: some View {
        Map(position: $position, selection: $selection) {
            if let perimeter = shownPerimeter {
                PerimeterOverlay(perimeter: perimeter)
            }
            ForEach(fire.drones.values.sorted { $0.id < $1.id }) { drone in
                DroneOverlay(drone: drone)
            }
            ForEach(clusterer.clusters(of: fire.hotspots.values)) { cluster in
                Annotation(cluster.count == 1 ? "" : "\(cluster.count)", coordinate: cluster.coordinate.clLocation) {
                    marker(for: cluster)
                }
                .annotationTitles(.hidden)
                .tag(cluster.id)
            }
            ForEach(model.field.queuedReports) { report in
                Annotation("Report waiting to send", coordinate: report.coordinate.clLocation) {
                    PendingReportMarker(report: report)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            clusterer.cellSize = HotspotClusterer.cellSize(forViewWidth: context.region.widthInMetres)
        }
        .onChange(of: fire.hotspots.isEmpty, initial: true) { frameFireOnce() }
        .onChange(of: selection) { _, selected in open(selected) }
        .safeAreaInset(edge: .bottom) {
            if fire.perimeters.count > 1 {
                PerimeterTimeline(perimeters: fire.perimeters, asOf: model.field.asOf, index: $perimeterIndex)
                    .padding()
            }
        }
        .sheet(item: $summary) { id in
            HotspotSummaryCard(hotspotID: id)
                .presentationDetents([.height(300)])
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shownPerimeter: FirePerimeter? {
        guard let index = perimeterIndex, fire.perimeters.indices.contains(index) else { return fire.latestPerimeter }
        return fire.perimeters[index]
    }

    @ViewBuilder
    private func marker(for cluster: HotspotCluster) -> some View {
        if cluster.count == 1, let hotspot = fire.hotspots[cluster.members[0]] {
            HotspotMarker(hotspot: hotspot)
        } else {
            ClusterMarker(cluster: cluster)
        }
    }

    /// A single hotspot opens its summary; a cluster zooms in on its members.
    private func open(_ selected: String?) {
        guard let selected else { return }
        defer { selection = nil }
        let cluster = clusterer.clusters(of: fire.hotspots.values).first { $0.id == selected }
        guard let cluster else { return }
        if cluster.count == 1 {
            summary = cluster.members[0]
        } else if let box = BoundingBox(enclosing: cluster.members.compactMap { fire.hotspots[$0]?.coordinate }) {
            withAnimation { position = .region(box.expanded(byMetres: 150).region) }
        }
    }

    /// Centres the camera on the fire the first time there is something to show.
    private func frameFireOnce() {
        guard !hasFramedFire else { return }
        let corners = (fire.latestPerimeter?.boundingBox).map { [$0.southWest, $0.northEast] } ?? []
        guard let box = BoundingBox(enclosing: corners + fire.hotspots.values.map(\.coordinate)) else { return }
        hasFramedFire = true
        position = .region(box.expanded(byMetres: 500).region)
    }
}

extension BoundingBox {
    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clLocation,
            span: MKCoordinateSpan(
                latitudeDelta: northEast.latitude - southWest.latitude,
                longitudeDelta: northEast.longitude - southWest.longitude))
    }
}

extension MKCoordinateRegion {
    /// Approximate width of the region on the ground.
    var widthInMetres: Double {
        span.longitudeDelta * 111_320 * cos(center.latitude * .pi / 180)
    }
}
