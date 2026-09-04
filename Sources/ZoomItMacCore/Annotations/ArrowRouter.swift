import AppKit

@MainActor
enum ArrowRouter {
    struct Obstacle: Equatable {
        var elementID: AnnotationElementID
        var bounds: CGRect
    }

    struct Diagnostics: Equatable {
        var nodeCount = 0
        var directedEdgeCount = 0
        var settledStateCount = 0
    }

    private enum Axis: Int {
        case horizontal
        case vertical
    }

    private struct SearchState: Hashable {
        var nodeIndex: Int
        var incomingAxis: Int
    }

    private struct GridCoordinate: Hashable {
        var x: Int
        var y: Int
    }

    private struct GridNode {
        var point: CGPoint
        var coordinate: GridCoordinate
    }

    private struct QueueEntry {
        var state: SearchState
        var distance: CGFloat
    }

    private struct PriorityQueue {
        private var entries: [QueueEntry] = []

        mutating func insert(_ entry: QueueEntry) {
            entries.append(entry)
            var index = entries.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard Self.precedes(entries[index], entries[parent]) else { break }
                entries.swapAt(index, parent)
                index = parent
            }
        }

        mutating func removeMinimum() -> QueueEntry? {
            guard !entries.isEmpty else { return nil }
            if entries.count == 1 {
                return entries.removeLast()
            }
            let result = entries[0]
            entries[0] = entries.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1
                guard left < entries.count else { break }
                let right = left + 1
                let child = right < entries.count && Self.precedes(entries[right], entries[left])
                    ? right
                    : left
                guard Self.precedes(entries[child], entries[index]) else { break }
                entries.swapAt(index, child)
                index = child
            }
            return result
        }

        private static func precedes(_ lhs: QueueEntry, _ rhs: QueueEntry) -> Bool {
            if abs(lhs.distance - rhs.distance) >= 0.000_001 {
                return lhs.distance < rhs.distance
            }
            if lhs.state.nodeIndex != rhs.state.nodeIndex {
                return lhs.state.nodeIndex < rhs.state.nodeIndex
            }
            return lhs.state.incomingAxis < rhs.state.incomingAxis
        }
    }

    static func route(
        from start: CGPoint,
        to end: CGPoint,
        startDirection: AnnotationEndpointDirection,
        endDirection: AnnotationEndpointDirection,
        obstacles: [Obstacle],
        clearance: CGFloat,
        diagnostics: ((Diagnostics) -> Void)? = nil
    ) -> [CGPoint] {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            diagnostics?(Diagnostics())
            return []
        }
        guard start != end else {
            diagnostics?(Diagnostics(nodeCount: 1))
            return [start]
        }

        let safeClearance = max(4, clearance)
        let expandedObstacles = obstacles.map {
            Obstacle(
                elementID: $0.elementID,
                bounds: $0.bounds.insetBy(dx: -safeClearance, dy: -safeClearance)
            )
        }
        let resolvedStart = resolvedDirection(startDirection, from: start, toward: end)
        let resolvedEnd = resolvedDirection(endDirection, from: end, toward: start)
        let startLead = start + vector(for: resolvedStart) * safeClearance
        let endLead = end + vector(for: resolvedEnd) * safeClearance

        var routeDiagnostics = Diagnostics()
        let routed = gridRoute(
            from: startLead,
            to: endLead,
            obstacles: expandedObstacles,
            bendPenalty: safeClearance * 2,
            diagnostics: &routeDiagnostics
        ) ?? fallbackRoute(from: startLead, to: endLead, obstacles: expandedObstacles)
        diagnostics?(routeDiagnostics)

        return simplify([start] + routed + [end])
    }

    static func resolvedDirection(
        _ direction: AnnotationEndpointDirection,
        from endpoint: CGPoint,
        toward other: CGPoint
    ) -> AnnotationEndpointDirection {
        guard direction == .automatic else { return direction }
        let dx = other.x - endpoint.x
        let dy = other.y - endpoint.y
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .trailing : .leading
        }
        return dy >= 0 ? .down : .up
    }

    static func vector(for direction: AnnotationEndpointDirection) -> CGPoint {
        switch direction {
        case .automatic, .trailing:
            CGPoint(x: 1, y: 0)
        case .up:
            CGPoint(x: 0, y: -1)
        case .down:
            CGPoint(x: 0, y: 1)
        case .leading:
            CGPoint(x: -1, y: 0)
        }
    }

    static func simplify(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points where point.x.isFinite && point.y.isFinite {
            if result.last == point {
                continue
            }
            if result.count >= 2 {
                let previous = result[result.count - 2]
                let current = result[result.count - 1]
                if isCollinear(previous, current, point) {
                    result[result.count - 1] = point
                    continue
                }
            }
            result.append(point)
        }
        return result
    }

    private static func gridRoute(
        from start: CGPoint,
        to end: CGPoint,
        obstacles: [Obstacle],
        bendPenalty: CGFloat,
        diagnostics: inout Diagnostics
    ) -> [CGPoint]? {
        var xValues = [start.x, end.x]
        var yValues = [start.y, end.y]
        for obstacle in obstacles {
            xValues.append(contentsOf: [obstacle.bounds.minX, obstacle.bounds.maxX])
            yValues.append(contentsOf: [obstacle.bounds.minY, obstacle.bounds.maxY])
        }
        xValues = uniqueSorted(xValues)
        yValues = uniqueSorted(yValues)

        var nodes: [GridNode] = []
        var nodeIndexByCoordinate: [GridCoordinate: Int] = [:]
        for (yIndex, y) in yValues.enumerated() {
            for (xIndex, x) in xValues.enumerated() {
                let point = CGPoint(x: x, y: y)
                if point == start || point == end || !isInsideObstacle(point, obstacles: obstacles) {
                    let coordinate = GridCoordinate(x: xIndex, y: yIndex)
                    nodeIndexByCoordinate[coordinate] = nodes.count
                    nodes.append(GridNode(point: point, coordinate: coordinate))
                }
            }
        }
        diagnostics.nodeCount = nodes.count
        guard let startIndex = nodes.firstIndex(where: { $0.point == start }),
              let endIndex = nodes.firstIndex(where: { $0.point == end }) else {
            return nil
        }

        var neighbors = Array(repeating: [(index: Int, axis: Axis, distance: CGFloat)](), count: nodes.count)
        for (nodeIndex, node) in nodes.enumerated() {
            let adjacent: [(GridCoordinate, Axis)] = [
                (GridCoordinate(x: node.coordinate.x + 1, y: node.coordinate.y), .horizontal),
                (GridCoordinate(x: node.coordinate.x, y: node.coordinate.y + 1), .vertical)
            ]
            for (coordinate, axis) in adjacent {
                guard let neighborIndex = nodeIndexByCoordinate[coordinate] else { continue }
                let neighbor = nodes[neighborIndex]
                guard segmentIsClear(
                    from: node.point,
                    to: neighbor.point,
                    obstacles: obstacles
                ) else {
                    continue
                }
                let distance = abs(node.point.x - neighbor.point.x)
                    + abs(node.point.y - neighbor.point.y)
                neighbors[nodeIndex].append((neighborIndex, axis, distance))
                neighbors[neighborIndex].append((nodeIndex, axis, distance))
                diagnostics.directedEdgeCount += 2
            }
        }

        let initial = SearchState(nodeIndex: startIndex, incomingAxis: -1)
        var distances: [SearchState: CGFloat] = [initial: 0]
        var previous: [SearchState: SearchState] = [:]
        var frontier = PriorityQueue()
        frontier.insert(QueueEntry(state: initial, distance: 0))
        var finalState: SearchState?

        while let entry = frontier.removeMinimum() {
            let current = entry.state
            let currentDistance = distances[current] ?? .infinity
            if entry.distance > currentDistance + 0.000_001 {
                continue
            }
            diagnostics.settledStateCount += 1
            if current.nodeIndex == endIndex {
                finalState = current
                break
            }
            for edge in neighbors[current.nodeIndex] {
                let next = SearchState(nodeIndex: edge.index, incomingAxis: edge.axis.rawValue)
                let turnCost = current.incomingAxis >= 0 && current.incomingAxis != edge.axis.rawValue
                    ? bendPenalty
                    : 0
                let candidate = currentDistance + edge.distance + turnCost
                if candidate + 0.000_001 < (distances[next] ?? .infinity) {
                    distances[next] = candidate
                    previous[next] = current
                    frontier.insert(QueueEntry(state: next, distance: candidate))
                }
            }
        }

        guard var state = finalState else { return nil }
        var indices = [state.nodeIndex]
        while let prior = previous[state] {
            state = prior
            indices.append(state.nodeIndex)
        }
        return simplify(indices.reversed().map { nodes[$0].point })
    }

    private static func fallbackRoute(
        from start: CGPoint,
        to end: CGPoint,
        obstacles: [Obstacle]
    ) -> [CGPoint] {
        let horizontalFirst = [start, CGPoint(x: end.x, y: start.y), end]
        let verticalFirst = [start, CGPoint(x: start.x, y: end.y), end]
        let candidates = [horizontalFirst, verticalFirst]
        return simplify(candidates.min {
            routeScore($0, obstacles: obstacles) < routeScore($1, obstacles: obstacles)
        } ?? horizontalFirst)
    }

    private static func routeScore(_ points: [CGPoint], obstacles: [Obstacle]) -> CGFloat {
        var score: CGFloat = 0
        for (start, end) in zip(points, points.dropFirst()) {
            score += abs(end.x - start.x) + abs(end.y - start.y)
            if !segmentIsClear(from: start, to: end, obstacles: obstacles) {
                score += 1_000_000
            }
        }
        return score
    }

    private static func segmentIsClear(
        from start: CGPoint,
        to end: CGPoint,
        obstacles: [Obstacle]
    ) -> Bool {
        for obstacle in obstacles {
            let bounds = obstacle.bounds
            if approximatelyEqual(start.x, end.x) {
                guard start.x > bounds.minX && start.x < bounds.maxX else { continue }
                let minimum = min(start.y, end.y)
                let maximum = max(start.y, end.y)
                if maximum > bounds.minY && minimum < bounds.maxY {
                    return false
                }
            } else if approximatelyEqual(start.y, end.y) {
                guard start.y > bounds.minY && start.y < bounds.maxY else { continue }
                let minimum = min(start.x, end.x)
                let maximum = max(start.x, end.x)
                if maximum > bounds.minX && minimum < bounds.maxX {
                    return false
                }
            }
        }
        return true
    }

    private static func isInsideObstacle(_ point: CGPoint, obstacles: [Obstacle]) -> Bool {
        obstacles.contains {
            point.x > $0.bounds.minX && point.x < $0.bounds.maxX
                && point.y > $0.bounds.minY && point.y < $0.bounds.maxY
        }
    }

    private static func uniqueSorted(_ values: [CGFloat]) -> [CGFloat] {
        values.sorted().reduce(into: []) { result, value in
            if result.last.map({ !approximatelyEqual($0, value) }) ?? true {
                result.append(value)
            }
        }
    }

    private static func isCollinear(_ first: CGPoint, _ second: CGPoint, _ third: CGPoint) -> Bool {
        (approximatelyEqual(first.x, second.x) && approximatelyEqual(second.x, third.x))
            || (approximatelyEqual(first.y, second.y) && approximatelyEqual(second.y, third.y))
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
    CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}
