import FireWatchCore
import MapKit
import SwiftUI

/// One hotspot: severity as colour and shape, status as a badge.
struct HotspotMarker: View {
    let hotspot: Hotspot

    var body: some View {
        Image(systemName: hotspot.severity.symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(hotspot.severity.color)
            .padding(6)
            .background(.black.opacity(0.55), in: Circle())
            .overlay(alignment: .topTrailing) {
                if hotspot.status != .new {
                    Image(systemName: hotspot.status.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.blue, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .opacity(hotspot.status.isSettled ? 0.55 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityIdentifier("hotspot.\(hotspot.id)")
    }

    private var accessibilityText: String {
        String(
            localized:
                "\(String(localized: hotspot.severity.label)) hotspot, \(Int(hotspot.temperatureCelsius)) °C, \(String(localized: hotspot.status.label))"
        )
    }
}

/// Several hotspots drawn as one, coloured by the worst of them.
struct ClusterMarker: View {
    let cluster: HotspotCluster

    var body: some View {
        Text("\(cluster.count)")
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(.white)
            .frame(minWidth: 34, minHeight: 34)
            .background(cluster.severity.color.gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .accessibilityLabel(Text("\(cluster.count) hotspots, worst \(String(localized: cluster.severity.label))"))
            .accessibilityIdentifier("cluster")
    }
}

/// The fire outline, with unburned islands left open.
struct PerimeterOverlay: MapContent {
    let perimeter: FirePerimeter

    var body: some MapContent {
        ForEach(Array(perimeter.polygons.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(polygon.mkPolygon)
                .foregroundStyle(.red.opacity(0.22))
                .stroke(.red, lineWidth: 2)
        }
    }
}

/// A drone's recent track and its current position and heading.
struct DroneOverlay: MapContent {
    let drone: Drone

    var body: some MapContent {
        MapPolyline(coordinates: drone.track.map(\.coordinate.clLocation))
            .stroke(.cyan.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        Annotation(drone.name, coordinate: drone.position.coordinate.clLocation) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .rotationEffect(.degrees(drone.position.headingDegrees))
                .foregroundStyle(.white)
                .padding(6)
                .background(.cyan, in: Circle())
                .accessibilityLabel(
                    Text("Drone \(drone.name), battery \(Int(drone.position.battery * 100)) percent"))
        }
    }
}

extension FireWatchCore.Polygon {
    var mkPolygon: MKPolygon {
        let ring = { (ring: [Coordinate]) in ring.map(\.clLocation) }
        let holes = holes.map { hole in
            let points = ring(hole)
            return MKPolygon(coordinates: points, count: points.count)
        }
        let outer = ring(exterior)
        return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: holes)
    }
}
