import Foundation

/// A line segment within one row of the commit graph, from lane `from` to lane `to`.
/// Top edges run from the row's top edge to its middle (where the dot sits);
/// bottom edges run from the middle to the row's bottom edge.
public struct GraphEdge: Equatable, Sendable, Hashable {
    public let from: Int
    public let to: Int
    public init(from: Int, to: Int) { self.from = from; self.to = to }
}

public struct GraphRow: Equatable, Sendable {
    public let column: Int
    public let laneCount: Int
    public let top: [GraphEdge]
    public let bottom: [GraphEdge]

    /// Lanes that continue below this row (used to draw through expanded content).
    public var lanesBelow: Set<Int> { Set(bottom.map(\.to)) }
}

/// Assigns lanes for commits listed in `git log --topo-order` order.
public enum GraphLayout {
    public static func layout(_ commits: [CommitEntry]) -> [GraphRow] {
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            let before = lanes
            let waiting = lanes.indices.filter { lanes[$0] == commit.hash }

            let column: Int
            if let first = waiting.first {
                column = first
            } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                column = free
            } else {
                lanes.append(nil)
                column = lanes.count - 1
            }

            var top: [GraphEdge] = []
            for i in before.indices where before[i] != nil {
                top.append(GraphEdge(from: i, to: before[i] == commit.hash ? column : i))
            }
            for i in waiting { lanes[i] = nil }

            var parentLanes: [Int] = []
            for (k, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    parentLanes.append(existing)
                } else if k == 0 {
                    lanes[column] = parent
                    parentLanes.append(column)
                } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[free] = parent
                    parentLanes.append(free)
                } else {
                    lanes.append(parent)
                    parentLanes.append(lanes.count - 1)
                }
            }

            var bottom = parentLanes.map { GraphEdge(from: column, to: $0) }
            for i in before.indices where before[i] != nil && before[i] != commit.hash {
                bottom.append(GraphEdge(from: i, to: i))
            }

            while let last = lanes.last, last == nil { lanes.removeLast() }

            let maxLane = (top + bottom).flatMap { [$0.from, $0.to] }.max() ?? 0
            rows.append(GraphRow(
                column: column,
                laneCount: max(maxLane, column) + 1,
                top: top,
                bottom: Array(Set(bottom)).sorted { ($0.from, $0.to) < ($1.from, $1.to) }
            ))
        }
        return rows
    }
}
