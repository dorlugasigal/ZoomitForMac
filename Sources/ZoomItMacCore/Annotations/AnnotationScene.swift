import Foundation

struct AnnotationSelection: Equatable {
    private(set) var elementIDs: Set<AnnotationElementID> = []

    var isEmpty: Bool {
        elementIDs.isEmpty
    }

    func contains(_ elementID: AnnotationElementID) -> Bool {
        elementIDs.contains(elementID)
    }

    mutating func replace(with elementIDs: Set<AnnotationElementID>) {
        self.elementIDs = elementIDs
    }
}

@MainActor
final class AnnotationScene {
    private struct ActiveTransaction {
        var previous: AnnotationSceneSnapshot
        var depth: Int
    }

    private(set) var elements: [AnnotationElement]
    private(set) var selection = AnnotationSelection()
    var currentTool: AnnotationTool {
        didSet { notifyChange() }
    }
    var currentStyle: AnnotationStyle {
        didSet { notifyChange() }
    }
    var onChange: (() -> Void)?
    var onElbowRoute: ((AnnotationElementID) -> Void)?

    private var history: AnnotationHistory
    private var activeTransaction: ActiveTransaction?

    init(
        elements: [AnnotationElement] = [],
        currentTool: AnnotationTool = .pen,
        currentStyle: AnnotationStyle = .default
    ) {
        self.elements = elements
        self.currentTool = currentTool
        self.currentStyle = currentStyle
        history = AnnotationHistory()
        normalizeOrdering()
        sanitizeBindings()
        refreshLinearGeometry(affectedBy: nil, previousElements: [])
    }

    var snapshot: AnnotationSceneSnapshot {
        AnnotationSceneSnapshot(elements: elements)
    }

    var canUndo: Bool {
        history.canUndo
    }

    var canRedo: Bool {
        history.canRedo
    }

    func element(withID elementID: AnnotationElementID) -> AnnotationElement? {
        elements.first { $0.id == elementID }
    }

    func reset() {
        elements.removeAll()
        selection = AnnotationSelection()
        currentTool = .pen
        currentStyle = .default
        activeTransaction = nil
        history.removeAll()
        notifyChange()
    }

    func beginTransaction() {
        if activeTransaction == nil {
            activeTransaction = ActiveTransaction(previous: snapshot, depth: 1)
        } else {
            activeTransaction?.depth += 1
        }
    }

    func commitTransaction() {
        guard var transaction = activeTransaction else { return }
        transaction.depth -= 1
        guard transaction.depth == 0 else {
            activeTransaction = transaction
            return
        }

        activeTransaction = nil
        normalizeOrdering()
        sanitizeBindings()
        sanitizeSelection()
        history.record(previous: transaction.previous, current: snapshot)
        notifyChange()
    }

    func cancelTransaction() {
        guard let transaction = activeTransaction else { return }
        activeTransaction = nil
        restore(transaction.previous)
        notifyChange()
    }

    @discardableResult
    func append(_ element: AnnotationElement) -> AnnotationElementID {
        performMutation(affectedElementIDs: [element.id]) {
            elements.append(element)
        }
        return element.id
    }

    func append(_ newElements: [AnnotationElement]) {
        let elementIDs = Set(newElements.map(\.id))
        performMutation(affectedElementIDs: elementIDs) {
            elements.append(contentsOf: newElements)
        }
    }

    @discardableResult
    func insert(_ element: AnnotationElement, at index: Int) -> AnnotationElementID {
        performMutation(affectedElementIDs: [element.id]) {
            elements.insert(element, at: min(max(index, 0), elements.count))
        }
        return element.id
    }

    func updateElement(
        withID elementID: AnnotationElementID,
        recordHistory: Bool = true,
        _ update: (inout AnnotationElement) -> Void
    ) {
        if recordHistory {
            performMutation(affectedElementIDs: [elementID]) {
                guard let index = elements.firstIndex(where: { $0.id == elementID }) else { return }
                update(&elements[index])
            }
        } else {
            let previousElements = elements
            guard let index = elements.firstIndex(where: { $0.id == elementID }) else { return }
            update(&elements[index])
            normalizeOrdering()
            sanitizeBindings()
            refreshLinearGeometry(
                affectedBy: [elementID],
                previousElements: previousElements
            )
            sanitizeSelection()
            notifyChange()
        }
    }

    func updateElements(
        withIDs elementIDs: Set<AnnotationElementID>,
        recordHistory: Bool = true,
        _ update: (inout AnnotationElement) -> Void
    ) {
        guard !elementIDs.isEmpty else { return }
        if recordHistory {
            performMutation(affectedElementIDs: elementIDs) {
                for index in elements.indices where elementIDs.contains(elements[index].id) {
                    update(&elements[index])
                }
            }
        } else {
            let previousElements = elements
            for index in elements.indices where elementIDs.contains(elements[index].id) {
                update(&elements[index])
            }
            normalizeOrdering()
            sanitizeBindings()
            refreshLinearGeometry(
                affectedBy: elementIDs,
                previousElements: previousElements
            )
            sanitizeSelection()
            notifyChange()
        }
    }

    func removeElements(withIDs elementIDs: Set<AnnotationElementID>) {
        performMutation(affectedElementIDs: elementIDs) {
            elements.removeAll { elementIDs.contains($0.id) }
        }
    }

    func clear() {
        let removedIDs = Set(elements.map(\.id))
        performMutation(affectedElementIDs: removedIDs) {
            elements.removeAll()
        }
    }

    func moveElements(withIDs elementIDs: Set<AnnotationElementID>, to index: Int) {
        performMutation(affectedElementIDs: []) {
            let moving = elements.filter { elementIDs.contains($0.id) }
            guard !moving.isEmpty else { return }
            elements.removeAll { elementIDs.contains($0.id) }
            elements.insert(contentsOf: moving, at: min(max(index, 0), elements.count))
        }
    }

    func setElementOrder(_ orderedElementIDs: [AnnotationElementID]) {
        let existingIDs = Set(elements.map(\.id))
        guard orderedElementIDs.count == elements.count,
              Set(orderedElementIDs) == existingIDs else {
            return
        }
        performMutation(affectedElementIDs: []) {
            let elementsByID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
            elements = orderedElementIDs.compactMap { elementsByID[$0] }
        }
    }

    @discardableResult
    func groupElements(withIDs elementIDs: Set<AnnotationElementID>) -> AnnotationGroupID? {
        guard elements.filter({ elementIDs.contains($0.id) }).count >= 2 else { return nil }
        let groupID = AnnotationGroupID()
        performMutation(affectedElementIDs: []) {
            for index in elements.indices where elementIDs.contains(elements[index].id) {
                elements[index].metadata.groupIDs.append(groupID)
            }
        }
        return groupID
    }

    func ungroupElements(withIDs elementIDs: Set<AnnotationElementID>, groupID: AnnotationGroupID) {
        performMutation(affectedElementIDs: []) {
            for index in elements.indices where elementIDs.contains(elements[index].id) {
                elements[index].metadata.groupIDs.removeAll { $0 == groupID }
            }
        }
    }

    func setLocked(_ isLocked: Bool, for elementIDs: Set<AnnotationElementID>) {
        performMutation(affectedElementIDs: []) {
            for index in elements.indices where elementIDs.contains(elements[index].id) {
                elements[index].metadata.isLocked = isLocked
            }
        }
    }

    func bindLinearEndpoint(
        elementID: AnnotationElementID,
        atStart: Bool,
        to binding: AnnotationBinding?
    ) {
        performMutation(affectedElementIDs: [elementID]) {
            guard let index = elements.firstIndex(where: { $0.id == elementID }),
                  case .linear(var linear) = elements[index].geometry else {
                return
            }
            if atStart {
                linear.startBinding = binding
                if let binding {
                    linear.startDirection =
                        AnnotationGeometry.routedEndpointDirection(
                            for: binding.side,
                            targetRotation: 0,
                            connectorRotation: 0,
                            fallback: .automatic
                        )
                }
            } else {
                linear.endBinding = binding
                if let binding {
                    linear.endDirection =
                        AnnotationGeometry.routedEndpointDirection(
                            for: binding.side,
                            targetRotation: 0,
                            connectorRotation: 0,
                            fallback: .automatic
                        )
                }
            }
            elements[index].geometry = .linear(linear)
        }
    }

    func unbindLinearEndpoints(
        elementID: AnnotationElementID,
        start: Bool = true,
        end: Bool = true
    ) {
        performMutation(affectedElementIDs: [elementID]) {
            guard let index = elements.firstIndex(where: { $0.id == elementID }),
                  case .linear(var linear) = elements[index].geometry else {
                return
            }
            if start {
                linear.startBinding = nil
            }
            if end {
                linear.endBinding = nil
            }
            elements[index].geometry = .linear(linear)
        }
    }

    func select(_ elementIDs: Set<AnnotationElementID>) {
        let existingIDs = Set(elements.map(\.id))
        selection.replace(with: elementIDs.intersection(existingIDs))
        notifyChange()
    }

    @discardableResult
    func undo() -> Bool {
        finishActiveTransaction()
        guard let previous = history.undo(current: snapshot) else { return false }
        restore(previous)
        notifyChange()
        return true
    }

    @discardableResult
    func redo() -> Bool {
        finishActiveTransaction()
        guard let next = history.redo(current: snapshot) else { return false }
        restore(next)
        notifyChange()
        return true
    }

    private func performMutation(
        affectedElementIDs: Set<AnnotationElementID>?,
        _ mutation: () -> Void
    ) {
        let previousElements = elements
        if activeTransaction != nil {
            mutation()
            normalizeOrdering()
            sanitizeBindings()
            refreshLinearGeometry(
                affectedBy: affectedElementIDs,
                previousElements: previousElements
            )
            sanitizeSelection()
            notifyChange()
            return
        }

        let previous = snapshot
        mutation()
        normalizeOrdering()
        sanitizeBindings()
        refreshLinearGeometry(
            affectedBy: affectedElementIDs,
            previousElements: previousElements
        )
        sanitizeSelection()
        history.record(previous: previous, current: snapshot)
        notifyChange()
    }

    private func finishActiveTransaction() {
        guard activeTransaction != nil else { return }
        activeTransaction?.depth = 1
        commitTransaction()
    }

    private func restore(_ snapshot: AnnotationSceneSnapshot) {
        elements = snapshot.elements
        normalizeOrdering()
        sanitizeBindings()
        refreshLinearGeometry(affectedBy: nil, previousElements: [])
        let existingIDs = Set(elements.map(\.id))
        selection.replace(with: selection.elementIDs.intersection(existingIDs))
    }

    private func notifyChange() {
        onChange?()
    }

    private func normalizeOrdering() {
        for index in elements.indices {
            elements[index].metadata.zIndex = index
        }
    }

    private func sanitizeBindings() {
        let bindableIDs = Set(elements.compactMap { element -> AnnotationElementID? in
            guard case .shape = element.geometry else { return nil }
            return element.id
        })

        for index in elements.indices {
            guard case .linear(var linear) = elements[index].geometry else { continue }
            if let binding = linear.startBinding,
               binding.targetElementID == elements[index].id || !bindableIDs.contains(binding.targetElementID) {
                linear.startBinding = nil
            }
            if let binding = linear.endBinding,
               binding.targetElementID == elements[index].id || !bindableIDs.contains(binding.targetElementID) {
                linear.endBinding = nil
            }
            elements[index].geometry = .linear(linear)
        }
    }

    private func refreshLinearGeometry(
        affectedBy changedElementIDs: Set<AnnotationElementID>?,
        previousElements: [AnnotationElement]
    ) {
        if changedElementIDs?.isEmpty == true {
            return
        }
        let shapeElements = elements.filter {
            if case .shape = $0.geometry {
                return $0.metadata.isVisible
            }
            return false
        }
        let shapesByID = Dictionary(uniqueKeysWithValues: shapeElements.map { ($0.id, $0) })
        let previousByID = Dictionary(uniqueKeysWithValues: previousElements.map { ($0.id, $0) })
        let routingChangedIDs = changedElementIDs.map { changedIDs in
            Set(changedIDs.filter { elementID in
                routingGeometryChanged(
                    from: previousByID[elementID],
                    to: element(withID: elementID)
                )
            })
        }
        if routingChangedIDs?.isEmpty == true {
            return
        }
        let changedShapeBounds = routingChangedIDs.map { changedIDs in
            changedIDs.flatMap { elementID -> [(AnnotationElementID, CGRect)] in
                let previousBounds = routingObstacleBounds(for: previousByID[elementID])
                let currentBounds = routingObstacleBounds(for: element(withID: elementID))
                guard previousBounds != currentBounds else { return [] }
                return [previousBounds, currentBounds].compactMap { worldBounds in
                    worldBounds.map { (elementID, $0) }
                }
            }
        } ?? []

        for index in elements.indices {
            guard case .linear(var linear) = elements[index].geometry,
                  !linear.points.isEmpty else {
                continue
            }
            let elementID = elements[index].id
            let previousLinear: AnnotationLinearGeometry? = {
                guard let previous = previousByID[elementID],
                      case .linear(let geometry) = previous.geometry else {
                    return nil
                }
                return geometry
            }()
            let boundTargetIDs = Set(
                [
                    linear.startBinding?.targetElementID,
                    linear.endBinding?.targetElementID,
                    previousLinear?.startBinding?.targetElementID,
                    previousLinear?.endBinding?.targetElementID
                ].compactMap { $0 }
            )
            let refreshEndpoints = routingChangedIDs == nil
                || routingChangedIDs?.contains(elementID) == true
                || routingChangedIDs?.isDisjoint(with: boundTargetIDs) == false
            let originalPoints = linear.points
            if elements[index].metadata.rotation == 0 {
                linear.rotationPivot = nil
            } else if linear.rotationPivot == nil {
                let bounds = AnnotationGeometry.localBounds(of: elements[index])
                linear.rotationPivot = CGPoint(x: bounds.midX, y: bounds.midY)
            }
            var transformElement = elements[index]
            transformElement.geometry = .linear(linear)
            let linearTransform = AnnotationGeometry.worldTransform(for: transformElement)
            let inverseLinearTransform = linearTransform.inverted()

            if refreshEndpoints {
                if let binding = linear.startBinding,
                   let target = shapesByID[binding.targetElementID] {
                    let neighbor = linear.points.count > 1 ? linear.points[1] : linear.points[0]
                    let worldNeighbor = neighbor.applying(linearTransform)
                    if let worldPoint = AnnotationGeometry.bindingPoint(
                        for: binding,
                        on: target,
                        toward: worldNeighbor
                    ) {
                        linear.points[0] = worldPoint.applying(inverseLinearTransform)
                    }
                }
                if let binding = linear.endBinding,
                   let target = shapesByID[binding.targetElementID] {
                    let neighborIndex = max(0, linear.points.count - 2)
                    let worldNeighbor = linear.points[neighborIndex].applying(linearTransform)
                    if let worldPoint = AnnotationGeometry.bindingPoint(
                        for: binding,
                        on: target,
                        toward: worldNeighbor
                    ) {
                        linear.points[linear.points.count - 1] =
                            worldPoint.applying(inverseLinearTransform)
                    }
                }

                updateCurvedEndpointControls(
                    &linear,
                    oldStart: originalPoints.first,
                    oldEnd: originalPoints.last
                )
            }

            if linear.route == .elbow, linear.points.count > 1 {
                if linear.isElbowAutoRouted {
                    let clearance = max(12, elements[index].style.strokeWidth * 4)
                    let shouldRoute = refreshEndpoints || routeMayBeAffected(
                        linear,
                        element: elements[index],
                        changedShapeBounds: changedShapeBounds,
                        excluding: boundTargetIDs,
                        clearance: clearance
                    )
                    if shouldRoute {
                        let obstacles = shapeElements.compactMap { shape -> ArrowRouter.Obstacle? in
                            guard !boundTargetIDs.contains(shape.id) else { return nil }
                            let worldBounds = AnnotationGeometry.worldBounds(
                                of: shape,
                                includingStroke: true
                            )
                            let localCorners = AnnotationGeometry.rectCorners(worldBounds).map {
                                $0.applying(inverseLinearTransform)
                            }
                            return ArrowRouter.Obstacle(
                                elementID: shape.id,
                                bounds: bounds(of: localCorners)
                            )
                        }
                        onElbowRoute?(elementID)
                        linear.points = ArrowRouter.route(
                            from: linear.points[0],
                            to: linear.points[linear.points.count - 1],
                            startDirection: resolvedEndpointDirection(
                                stored: linear.startDirection,
                                binding: linear.startBinding,
                                targets: shapesByID,
                                connectorRotation: elements[index].metadata.rotation
                            ),
                            endDirection: resolvedEndpointDirection(
                                stored: linear.endDirection,
                                binding: linear.endBinding,
                                targets: shapesByID,
                                connectorRotation: elements[index].metadata.rotation
                            ),
                            obstacles: obstacles,
                            clearance: clearance
                        )
                    }
                } else if refreshEndpoints {
                    preserveManualElbowEndpoints(
                        &linear,
                        oldStart: originalPoints.first,
                        oldEnd: originalPoints.last
                    )
                }
            }
            elements[index].geometry = .linear(linear)
        }
    }

    private func routingGeometryChanged(
        from previous: AnnotationElement?,
        to current: AnnotationElement?
    ) -> Bool {
        guard let previous, let current else {
            return isRoutingRelevant(previous) || isRoutingRelevant(current)
        }
        guard isRoutingRelevant(previous) || isRoutingRelevant(current) else {
            return false
        }
        if previous.metadata.rotation != current.metadata.rotation
            || previous.metadata.isVisible != current.metadata.isVisible {
            return true
        }

        switch (previous.geometry, current.geometry) {
        case (.shape(let previousShape), .shape(let currentShape)):
            return previousShape != currentShape
                || routingStyleChanged(from: previous.style, to: current.style)
        case (.linear(let previousLinear), .linear(let currentLinear)):
            return linearRoutingGeometryChanged(
                from: previousLinear,
                to: currentLinear
            )
                || (
                    isAutoRoutedElbow(previousLinear)
                        || isAutoRoutedElbow(currentLinear)
                )
                && routingStyleChanged(from: previous.style, to: current.style)
        default:
            return previous.geometry != current.geometry
        }
    }

    private func routingStyleChanged(
        from previous: AnnotationStyle,
        to current: AnnotationStyle
    ) -> Bool {
        previous.strokeWidth != current.strokeWidth
            || previous.sloppiness != current.sloppiness
    }

    private func isAutoRoutedElbow(_ linear: AnnotationLinearGeometry) -> Bool {
        linear.route == .elbow && linear.isElbowAutoRouted
    }

    private func isRoutingRelevant(_ element: AnnotationElement?) -> Bool {
        guard let element else { return false }
        return switch element.geometry {
        case .shape, .linear:
            true
        case .freehand, .text:
            false
        }
    }

    private func linearRoutingGeometryChanged(
        from previous: AnnotationLinearGeometry,
        to current: AnnotationLinearGeometry
    ) -> Bool {
        previous.points != current.points
            || previous.route != current.route
            || previous.startBinding != current.startBinding
            || previous.endBinding != current.endBinding
            || previous.startDirection != current.startDirection
            || previous.endDirection != current.endDirection
            || previous.isElbowAutoRouted != current.isElbowAutoRouted
            || previous.rotationPivot != current.rotationPivot
    }

    private func routingObstacleBounds(for element: AnnotationElement?) -> CGRect? {
        guard let element,
              element.metadata.isVisible,
              case .shape = element.geometry else {
            return nil
        }
        return AnnotationGeometry.worldBounds(of: element, includingStroke: true)
    }

    private func routeMayBeAffected(
        _ linear: AnnotationLinearGeometry,
        element: AnnotationElement,
        changedShapeBounds: [(AnnotationElementID, CGRect)],
        excluding boundTargetIDs: Set<AnnotationElementID>,
        clearance: CGFloat
    ) -> Bool {
        guard !changedShapeBounds.isEmpty,
              let first = linear.points.first,
              let last = linear.points.last else {
            return false
        }
        let routeBounds = bounds(of: linear.points)
        let endpointBounds = CGRect(
            x: min(first.x, last.x),
            y: min(first.y, last.y),
            width: abs(last.x - first.x),
            height: abs(last.y - first.y)
        )
        let influenceBounds = routeBounds.union(endpointBounds)
            .insetBy(dx: -clearance, dy: -clearance)
        let inverseTransform = AnnotationGeometry.inverseWorldTransform(for: element)

        return changedShapeBounds.contains { elementID, worldBounds in
            guard !boundTargetIDs.contains(elementID), !worldBounds.isNull else {
                return false
            }
            let localBounds = bounds(
                of: AnnotationGeometry.rectCorners(worldBounds).map {
                    $0.applying(inverseTransform)
                }
            )
            return influenceBounds.intersects(localBounds)
        }
    }

    private func updateCurvedEndpointControls(
        _ linear: inout AnnotationLinearGeometry,
        oldStart: CGPoint?,
        oldEnd: CGPoint?
    ) {
        guard linear.route == .curved,
              linear.bezierControls.count == linear.points.count - 1,
              let oldStart,
              let oldEnd,
              let newStart = linear.points.first,
              let newEnd = linear.points.last else {
            return
        }
        let startDelta = newStart - oldStart
        let endDelta = newEnd - oldEnd
        linear.bezierControls[0].start = linear.bezierControls[0].start + startDelta
        linear.bezierControls[linear.bezierControls.count - 1].end =
            linear.bezierControls[linear.bezierControls.count - 1].end + endDelta
    }

    private func preserveManualElbowEndpoints(
        _ linear: inout AnnotationLinearGeometry,
        oldStart: CGPoint?,
        oldEnd: CGPoint?
    ) {
        guard linear.points.count > 1, let oldStart, let oldEnd else { return }
        let lastIndex = linear.points.count - 1
        let startWasHorizontal = abs(originalDifference(
            linear.points[1].y,
            oldStart.y
        )) <= abs(originalDifference(linear.points[1].x, oldStart.x))
        if startWasHorizontal {
            linear.points[1].y = linear.points[0].y
        } else {
            linear.points[1].x = linear.points[0].x
        }

        let endWasHorizontal = abs(originalDifference(
            linear.points[lastIndex - 1].y,
            oldEnd.y
        )) <= abs(originalDifference(linear.points[lastIndex - 1].x, oldEnd.x))
        if endWasHorizontal {
            linear.points[lastIndex - 1].y = linear.points[lastIndex].y
        } else {
            linear.points[lastIndex - 1].x = linear.points[lastIndex].x
        }
    }

    private func resolvedEndpointDirection(
        stored: AnnotationEndpointDirection,
        binding: AnnotationBinding?,
        targets: [AnnotationElementID: AnnotationElement],
        connectorRotation: CGFloat
    ) -> AnnotationEndpointDirection {
        guard let binding,
              let target = targets[binding.targetElementID] else {
            return stored
        }
        return AnnotationGeometry.routedEndpointDirection(
            for: binding.side,
            targetRotation: target.metadata.rotation,
            connectorRotation: connectorRotation,
            fallback: stored
        )
    }

    private func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    private func originalDifference(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        lhs - rhs
    }

    private func sanitizeSelection() {
        let existingIDs = Set(elements.map(\.id))
        selection.replace(with: selection.elementIDs.intersection(existingIDs))
    }

}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}
