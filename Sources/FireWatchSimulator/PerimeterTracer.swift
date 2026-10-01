import FireWatchCore
import Foundation

/// A polygon on the cell lattice: one unit is one cell width, (0, 0) the south-west grid corner.
struct LatticePolygon: Hashable, Sendable {
    var exterior: [PlanarPoint]
    var holes: [[PlanarPoint]]
}

/// Turns a mask of burned cells into polygons.
///
/// Every boundary edge between a burned and an unburned cell is walked with the burned
/// cell on its left. Outer rings come out counter-clockwise and holes clockwise, so the
/// sign of a ring's area tells them apart. Where two burned cells touch only at a corner,
/// the walk turns left, treating them as separate (4-connected) areas.
enum PerimeterTracer {
    static func polygons(of mask: Grid<Bool>, smoothing: Int = 2, minimumHoleCells: Double = 2) -> [LatticePolygon] {
        let rings = traceRings(mask)
        let exteriors = rings.filter { signedArea($0) > 0 }
        var holesByExterior = [[[PlanarPoint]]](repeating: [], count: exteriors.count)
        for hole in rings where -signedArea(hole) >= minimumHoleCells {
            if let owner = owner(of: hole, among: exteriors) {
                holesByExterior[owner].append(hole)
            }
        }
        return zip(exteriors, holesByExterior).map { exterior, holes in
            LatticePolygon(
                exterior: smooth(exterior, iterations: smoothing),
                holes: holes.map { smooth($0, iterations: smoothing) }
            )
        }
    }

    // MARK: Ring tracing

    private struct Point: Hashable, Comparable {
        var x: Int
        var y: Int
        static func < (lhs: Self, rhs: Self) -> Bool { (lhs.y, lhs.x) < (rhs.y, rhs.x) }
        func moved(_ direction: Direction) -> Point {
            let (dx, dy) = direction.step
            return Point(x: x + dx, y: y + dy)
        }
    }

    private enum Direction: Int, CaseIterable, Comparable {
        case east, north, west, south  // counter-clockwise order
        var step: (Int, Int) { [(1, 0), (0, 1), (-1, 0), (0, -1)][rawValue] }
        var left: Direction { Direction(rawValue: (rawValue + 1) % 4) ?? self }
        var right: Direction { Direction(rawValue: (rawValue + 3) % 4) ?? self }
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Edge: Hashable, Comparable {
        var start: Point
        var direction: Direction
        var end: Point { start.moved(direction) }
        static func < (lhs: Self, rhs: Self) -> Bool { (lhs.start, lhs.direction) < (rhs.start, rhs.direction) }
    }

    /// Closed rings of lattice corners, without repeated or collinear points.
    private static func traceRings(_ mask: Grid<Bool>) -> [[PlanarPoint]] {
        let edges = boundaryEdges(mask)
        var outgoing: [Point: Set<Direction>] = [:]
        for edge in edges { outgoing[edge.start, default: []].insert(edge.direction) }

        var unvisited = Set(edges)
        var rings: [[PlanarPoint]] = []
        for first in edges.sorted() where unvisited.contains(first) {
            var corners: [Point] = []
            var edge = first
            repeat {
                unvisited.remove(edge)
                let choices = outgoing[edge.end, default: []]
                let next = [edge.direction.left, edge.direction, edge.direction.right].first { choices.contains($0) }
                guard let next else { break }  // unreachable: every boundary vertex has an outgoing edge
                if next != edge.direction { corners.append(edge.end) }
                edge = Edge(start: edge.end, direction: next)
            } while edge != first
            rings.append(corners.map { PlanarPoint(x: Double($0.x), y: Double($0.y)) })
        }
        return rings
    }

    /// Edges between burned and unburned cells, oriented with the burned cell on the left.
    private static func boundaryEdges(_ mask: Grid<Bool>) -> [Edge] {
        var edges: [Edge] = []
        for cell in mask.indices where mask[cell] {
            let southWest = Point(x: cell.column, y: cell.row)
            let southEast = Point(x: cell.column + 1, y: cell.row)
            let northEast = Point(x: cell.column + 1, y: cell.row + 1)
            let northWest = Point(x: cell.column, y: cell.row + 1)
            let sides: [(GridIndex, Edge)] = [
                (cell.offset(rows: -1, columns: 0), Edge(start: southWest, direction: .east)),
                (cell.offset(rows: 0, columns: 1), Edge(start: southEast, direction: .north)),
                (cell.offset(rows: 1, columns: 0), Edge(start: northEast, direction: .west)),
                (cell.offset(rows: 0, columns: -1), Edge(start: northWest, direction: .south)),
            ]
            for (neighbour, edge) in sides where mask.value(at: neighbour) != true {
                edges.append(edge)
            }
        }
        return edges
    }

    // MARK: Geometry

    /// Shoelace area: positive for counter-clockwise rings.
    static func signedArea(_ ring: [PlanarPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var twiceArea = 0.0
        for (index, point) in ring.enumerated() {
            let next = ring[(index + 1) % ring.count]
            twiceArea += point.x * next.y - next.x * point.y
        }
        return twiceArea / 2
    }

    /// The smallest exterior containing `hole`, tested at the centre of a burned cell just
    /// outside the hole, which can never lie on a ring.
    private static func owner(of hole: [PlanarPoint], among exteriors: [[PlanarPoint]]) -> Int? {
        guard hole.count >= 2 else { return nil }
        // A clockwise hole has burned cells on its left; walking a→b, left is (-dy, dx).
        let a = hole[0]
        let b = hole[1]
        let length = max(abs(b.x - a.x), abs(b.y - a.y))
        let dx = (b.x - a.x) / length
        let dy = (b.y - a.y) / length
        let probe = PlanarPoint(x: a.x + dx * 0.5 - dy * 0.5, y: a.y + dy * 0.5 + dx * 0.5)
        return exteriors.indices
            .filter { contains(exteriors[$0], probe) }
            .min { signedArea(exteriors[$0]) < signedArea(exteriors[$1]) }
    }

    private static func contains(_ ring: [PlanarPoint], _ point: PlanarPoint) -> Bool {
        var inside = false
        var previous = ring[ring.count - 1]
        for vertex in ring {
            if (vertex.y > point.y) != (previous.y > point.y),
                point.x < vertex.x + (point.y - vertex.y) / (previous.y - vertex.y) * (previous.x - vertex.x)
            {
                inside.toggle()
            }
            previous = vertex
        }
        return inside
    }

    /// Chaikin corner cutting: softens the stair-step cell outline.
    static func smooth(_ ring: [PlanarPoint], iterations: Int) -> [PlanarPoint] {
        guard iterations > 0, ring.count >= 3 else { return ring }
        var points = ring
        for _ in 0..<iterations {
            points = points.indices.flatMap { index -> [PlanarPoint] in
                let p = points[index]
                let q = points[(index + 1) % points.count]
                return [
                    PlanarPoint(x: 0.75 * p.x + 0.25 * q.x, y: 0.75 * p.y + 0.25 * q.y),
                    PlanarPoint(x: 0.25 * p.x + 0.75 * q.x, y: 0.25 * p.y + 0.75 * q.y),
                ]
            }
        }
        return points
    }
}

extension TerrainGrid {
    /// The fire perimeter for a mask of burned cells, in coordinates. `smoothing` is the
    /// number of corner-cutting passes; 0 keeps the exact cell outline.
    public func perimeter(of mask: Grid<Bool>, at time: Date, smoothing: Int = 2) -> FirePerimeter {
        let toCoordinate = { (point: PlanarPoint) in
            self.projection.unproject(
                PlanarPoint(
                    x: (point.x - Double(self.columns) / 2) * self.cellSize,
                    y: (point.y - Double(self.rows) / 2) * self.cellSize
                )
            )
        }
        let polygons = PerimeterTracer.polygons(of: mask, smoothing: smoothing).map { polygon in
            Polygon(exterior: polygon.exterior.map(toCoordinate), holes: polygon.holes.map { $0.map(toCoordinate) })
        }
        return FirePerimeter(time: time, polygons: polygons)
    }
}
