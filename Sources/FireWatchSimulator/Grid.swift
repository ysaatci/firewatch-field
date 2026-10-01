/// A cell position in a ``Grid``. Row 0 is the southern edge, column 0 the western.
public struct GridIndex: Hashable, Comparable, Sendable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// Row-major order, matching how ``Grid`` iterates.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }

    /// The index `rows` north and `columns` east of this one.
    public func offset(rows: Int, columns: Int) -> GridIndex {
        GridIndex(row: row + rows, column: column + columns)
    }
}

/// A fixed-size 2-D array stored row-major.
public struct Grid<Value: Sendable>: Sendable {
    public let rows: Int
    public let columns: Int
    private var storage: [Value]

    public init(rows: Int, columns: Int, repeating value: Value) {
        self.rows = rows
        self.columns = columns
        storage = Array(repeating: value, count: rows * columns)
    }

    public init(rows: Int, columns: Int, _ makeValue: (GridIndex) -> Value) {
        self.rows = rows
        self.columns = columns
        storage = []
        storage.reserveCapacity(rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                storage.append(makeValue(GridIndex(row: row, column: column)))
            }
        }
    }

    public func contains(_ index: GridIndex) -> Bool {
        (0..<rows).contains(index.row) && (0..<columns).contains(index.column)
    }

    public subscript(index: GridIndex) -> Value {
        get { storage[index.row * columns + index.column] }
        set { storage[index.row * columns + index.column] = newValue }
    }

    /// The value at `index`, or `nil` outside the grid.
    public func value(at index: GridIndex) -> Value? {
        contains(index) ? self[index] : nil
    }

    /// Every index, row-major.
    public var indices: some Sequence<GridIndex> {
        (0..<rows).lazy.flatMap { row in (0..<columns).lazy.map { GridIndex(row: row, column: $0) } }
    }

    public var values: [Value] { storage }

    public func map<T>(_ transform: (Value) -> T) -> Grid<T> {
        Grid<T>(rows: rows, columns: columns) { transform(self[$0]) }
    }
}

extension Grid: Equatable where Value: Equatable {}
extension Grid: Hashable where Value: Hashable {}
