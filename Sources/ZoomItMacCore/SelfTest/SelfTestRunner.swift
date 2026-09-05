import AppKit

enum SelfTestError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message): message
        }
    }
}

/// A flipped (top-left origin) host view that draws a background image through
/// `BreakTimerLayout.drawBackground`, mirroring the real break timer view. Used
/// to verify images are not rendered upside down in a flipped context.
private final class FlippedBackgroundHostView: NSView {
    var image: NSImage?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        if let image {
            BreakTimerLayout.drawBackground(image, in: bounds, fraction: 1)
        }
    }
}

private final class SelfTestFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class SelfTestTimeoutState<Value: Sendable> {
    var continuation: CheckedContinuation<Value, Error>?
    var operationTask: Task<Void, Never>?
    var deadlineTask: Task<Void, Never>?

    func resolve(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        operationTask?.cancel()
        deadlineTask?.cancel()
        operationTask = nil
        deadlineTask = nil
        continuation.resume(with: result)
    }
}

@MainActor
private func withSelfTestTimeout<Value: Sendable>(
    _ description: String,
    after timeout: Duration = .seconds(2),
    operation: @escaping @MainActor () async throws -> Value
) async throws -> Value {
    let state = SelfTestTimeoutState<Value>()
    return try await withCheckedThrowingContinuation { continuation in
        state.continuation = continuation
        state.operationTask = Task { @MainActor in
            do {
                state.resolve(.success(try await operation()))
            } catch {
                state.resolve(.failure(error))
            }
        }
        state.deadlineTask = Task { @MainActor in
            do {
                try await ContinuousClock().sleep(for: timeout)
            } catch {
                return
            }
            state.resolve(
                .failure(
                    SelfTestError.failure(
                        "Timed out waiting for \(description)"
                    )
                )
            )
        }
    }
}

@MainActor
private final class SelfTestAsyncGate {
    private struct EntryWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [EntryWaiter] = []
    private(set) var entryCount = 0

    func wait() async throws {
        entryCount += 1
        resumeSatisfiedEntryWaiters()
        guard !isOpen else { return }
        try await withSelfTestTimeout("self-test gate to open") {
            await withCheckedContinuation { continuation in
                if self.isOpen {
                    continuation.resume()
                } else {
                    self.waiters.append(continuation)
                }
            }
        }
    }

    func waitUntilEntered(_ count: Int = 1) async throws {
        guard entryCount < count else { return }
        try await withSelfTestTimeout("self-test gate entry \(count)") {
            await withCheckedContinuation { continuation in
                if self.entryCount >= count {
                    continuation.resume()
                } else {
                    self.entryWaiters.append(
                        EntryWaiter(count: count, continuation: continuation)
                    )
                }
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resumeSatisfiedEntryWaiters() {
        var remaining: [EntryWaiter] = []
        for waiter in entryWaiters {
            if entryCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        entryWaiters = remaining
    }
}

@MainActor
private final class SelfTestLiveZoomActivationSession {
    private var isStopped = false
    private(set) var stopCount = 0

    func stop() async {
        guard !isStopped else { return }
        isStopped = true
        stopCount += 1
    }
}

@MainActor
public enum SelfTestRunner {
    public static func run() async throws {
        try await testAsyncWaitTimeout()
        try testAppInfoVersionResolution()
        try testViewportClampsZoom()
        try testViewportZoomAnimation()
        try testViewportSourceRect()
        try testViewportContentPointMapping()
        try testViewportContentToDestinationTransform()
        try testCaptureAccessoryCompositorGeometry()
        try testCaptureAccessoryCompositorBlendingAndShadow()
        try testDrawingAccessoryCaptureVisibilityAndSharing()
        try testZoomCanvasAccessoryCaptureIntegration()
        try testCaptureFeedbackAndRecordingDimensionPolicies()
        try testFreehandAnnotationLifecycle()
        try testShapeAnnotationEndpointReplacement()
        try testAxisAlignedShapeCreation()
        try testUndoAndClear()
        try testClearCancelsTransientAnnotationState()
        try testDrawingStyleSessionScoping()
        try testAnnotationSceneCreationAndStableIDs()
        try testAnnotationSceneTransactionalHistory()
        try testAnnotationSceneOrdering()
        try testAnnotationSceneGroupingAndLocking()
        try testAnnotationSceneBindingIntegrity()
        try testAnnotationGeometryBoundsAndTransforms()
        try testAdvancedLinearPointEditing()
        try testLinearPointEditingRevalidation()
        try testPassiveLinearPointDiscovery()
        try testBezierLinearGeometry()
        try testLinearClickConstructionLifecycle()
        try testLinearConstructionEscapeAndToolSwitch()
        try testActiveGestureExitLifecycle()
        try testLinearDragThresholdLatching()
        try testLinearConstructionRoutesAndBindings()
        try testCurvedTangentEditingAndControlPreservation()
        try testElbowRoutingAndIntersections()
        try testElbowRoutingComplexityAndRefreshBatching()
        try testMultiArrowMutationBatching()
        try testArrowheadFamiliesAndScaling()
        try testLinearArrowheadEndpointEditsPreserveOppositeEndpoints()
        try testLinearBindingLifecycle()
        try testRotatedConnectorBindingRefreshUsesStablePivot()
        try testRotatedBindingDirections()
        try testLegacyArrowGestureOrientation()
        try testLinearToolDefaultTransitionsAndApplication()
        try testAnnotationHitTestingAndSelectionDecorations()
        try testAdaptiveCurveAndArrowheadHitTesting()
        try testMixedLockSelectionHandlesMatchEditableElements()
        try testAnnotationEditorSelectionAndMarquee()
        try testSelectArrowKeyFallthrough()
        try testAnnotationEditorTransformTransactionsAndLocking()
        try testDestinationSpaceDuplicateOffset()
        try testRotatedResizeCoordinateSpaces()
        try testTextResizeUsesUniformHandlesAndScale()
        try testAnnotationEditorCommandsAndGrouping()
        try testNestedUngroupPreservesInnerGroup()
        try testAnnotationEditorStateTransitionsAndTextReselection()
        try testModeCoordinatorExistingTextEditTransition()
        try testSingleOwnerTextInsertionPlacement()
        try testLockedTextEditingBoundaries()
        try testDrawingToolbarStateMapping()
        try testLockedInspectorActionsAndDefaults()
        try testDrawingInspectorLayoutAndVisibilityPolicy()
        try testDrawingInspectorControlMappingsAndTextPresets()
        try testDrawingInspectorPreviewGeometryAndSignatures()
        try testDrawingInspectorVisualPreviewsAndWiring()
        try testDrawingPaletteVisualParity()
        try testDrawingToolShortcuts()
        try testDrawingToolbarLifecycleAndPlacement()
        try testDrawingAccessorySuppressionLifecycle()
        try testDrawingInspectorRuntimePresentationSwitch()
        try testDrawingColorPickerCoordinatorLifecycle()
        try testDrawingColorPickerPhysicalClicks()
        try testArrowheadPopoverClickLifecycle()
        try testDrawingToolbarMenuInteractionLifecycle()
        try testDrawingToolbarStyleActionsAndEraserHistory()
        try testPendingErasureRasterCompositing()
        try testReliableEraserSweepAndHitCoverage()
        try testToolScopedWidthsAndCompactToolbarGeometry()
        try testHighlighterGeometryStyleIsolation()
        try testPenOpacityScopes()
        try testPenPressureAndSelectionStyleScopes()
        try testContinuousStyleUndoAndAtomicLegacyColor()
        try testTextScopedStyleActionsInMixedSelection()
        try testActiveTextContextualStyleTransaction()
        try testFreehandSmoothingAndPressureSampling()
        try testBoundedFreehandPipelineAndRenderCache()
        try testCommittedFreehandRenderCache()
        try testImmediateFreehandPresentationAndQueueBounds()
        try testFixedStrokeVariablePressureConversion()
        try testSmartDrawClosedShapeRecognition()
        try testSmartDrawRobustGeometryFitting()
        try testSmartDrawArrowAndNegativeRecognition()
        try await testSmartDrawRecognitionBudget()
        try testSmartDrawPreviewStabilityAndHistory()
        try testTypingAnnotations()
        try testAnnotationRenderingTouchesPixels()
        try testAnnotationRenderingStylesAndFamilies()
        try testPatternFillRenderingDeterminismAndOpacity()
        try testDrawingCapturePolicies()
        try testAnnotationSloppinessDeterminismAndEndpoints()
        try testMeasuredRoughRenderingModel()
        try testRoughRasterMatrixAndSelectionClearance()
        try testAnnotationSloppinessOpacityAndFamilies()
        try testFreehandRenderingQualityAndHighlighterPreview()
        try testExplicitLegacyHighlightSemantics()
        try testHighlightZOrderRendering()
        try testHighlighterEffectiveOpacityAndHistory()
        try testSettingsRoundTrip()
        try testDrawingSettingsDefaultsAndMigration()
        try testFirstLaunchFlag()
        #if !ZOOMIT_APP_STORE
        try testDemoTypeSettingsRoundTrip()
        try testDemoTypeScriptCleaningAndTokens()
        try testDemoTypeScriptDecoding()
        try testDemoTypeTypingDelayRange()
        try testDemoTypeUserDrivenStepStopsAtEnd()
        #endif
        try testBreakTimerLayout()
        try testBreakTimerBackgroundNotFlipped()
        try testPanoramaSelectionBorderColor()
        try testPresentedWindowLifecycleOrdering()
        try testOverlayRegionSnipTeardown()
        try testPanoramaEscapeCancel()
        try testIdleSleepAssertionLifecycle()
        try testStatusMenuOrderMatchesWindows()
        try testClipTransitionUpdatesOnChange()
        try testWebcamOverlayDragOrigin()
        try testModalActivationCommandGating()
        try testExternalRegionSelectorAccessoryPolicy()
        try testModalActivationBreakAndOcrRaces()
        try await testModalActivationStaleCompletionIsolation()
        try await testLiveZoomExitDuringStartup()
        try testTrimSavePreservesOriginal()
        try testSettingsWindowStaysOnTop()
        try testZoomAndLiveZoomAreSeparateTabs()
        try testDistributionSpecificSettingsTabs()
        try testSettingsPaneSymbolsResolve()
        try testBlankScreenUsesControlKeys()
        try testTypeTabFontSampleUsesSelectedFont()
        try testMenuBarIconIsPaddedTemplate()
        try testStandardIconIsRoundedSquareWithMargin()
        try testDefaultTypingFontIsSystem20pt()
        try testStaticZoomStaysAtOneX()
        try testPanoramaStitching()
        try testPanoramaTopSeamUsesSingleFramePixels()
        try testPanoramaVerticalSeamKeepsSingleFrame()
        try testPanoramaDeferredDirectionCommit()
        try testPanoramaNoHarmonicRepeats()
        try testPanoramaFixedHeaderSuppression()
        try testPanoramaFooterDoesNotAttractSmallShift()
        try testPanoramaFixedFooterSuppression()
        try testPanoramaSkipsRepeatedCaptures()
        try testPanoramaRejectsStationaryRepaintShift()
        try testPanoramaKeepsScrollBesideStaticContent()
        try testPanoramaSparseTallContentStitches()
        try testPanoramaStartupAxisRejectsHorizontalAlias()
        try testPanoramaLockedAxisRejectsShortFallback()
    }

    private static func testAsyncWaitTimeout() async throws {
        do {
            _ = try await withSelfTestTimeout(
                "timeout self-check",
                after: .milliseconds(1)
            ) {
                try await ContinuousClock().sleep(for: .seconds(1))
            }
            throw SelfTestError.failure(
                "Expected the timeout self-check to fail"
            )
        } catch let error as SelfTestError {
            try expect(
                error.description == "Timed out waiting for timeout self-check",
                "Expected async self-test waits to fail with SelfTestError"
            )
        }
    }

    private static func testAppInfoVersionResolution() throws {
        try expect(
            AppInfo.resolveVersion(from: ["CFBundleShortVersionString": "12.2.0"]) == "12.2.0",
            "Expected the settings version to use CFBundleShortVersionString"
        )
        try expect(
            AppInfo.resolveVersion(from: ["CFBundleVersion": "42"]) == "42",
            "Expected the settings version to fall back to CFBundleVersion"
        )
        try expect(
            AppInfo.resolveVersion(from: nil) == "Development",
            "Expected an unbundled development build to identify itself as Development"
        )
    }

    private static func testViewportClampsZoom() throws {
        let controller = ZoomViewportController()

        controller.configure(for: try makeFrame(), initialZoom: 100)
        try expect(controller.zoomFactor == 32, "Expected initial zoom to clamp to 32x")

        controller.configure(for: try makeFrame(), initialZoom: 0.25)
        try expect(controller.zoomFactor == 1, "Expected initial zoom to clamp to 1x")
    }

    private static func testViewportZoomAnimation() throws {
        let controller = ZoomViewportController()
        controller.configure(for: try makeFrame(), initialZoom: 2)

        controller.beginZoomInAnimation()
        try expect(controller.zoomFactor == 1, "Expected telescope to start at 1x")
        try expect(controller.isAnimatingZoom, "Expected zoom-in to be animating")

        var steps = 0
        while controller.advanceZoomAnimation() {
            steps += 1
            try expect(steps < 1000, "Zoom-in animation did not converge")
        }
        try expect(controller.zoomFactor == 2, "Expected telescope to reach 2x, got \(controller.zoomFactor)")
        try expect(!controller.isAnimatingZoom, "Expected animation to stop at target")

        controller.animateZoom(to: 1)
        try expect(controller.isAnimatingZoom, "Expected zoom-out to be animating")
        steps = 0
        while controller.advanceZoomAnimation() {
            steps += 1
            try expect(steps < 1000, "Zoom-out animation did not converge")
        }
        try expect(controller.zoomFactor == 1, "Expected telescope to reach 1x, got \(controller.zoomFactor)")
    }

    private static func testViewportSourceRect() throws {
        let controller = ZoomViewportController()
        controller.configure(for: try makeFrame(), initialZoom: 2)

        let rect = controller.sourceRect(
            for: CGRect(x: 0, y: 0, width: 1000, height: 800),
            cursorLocation: CGPoint(x: 500, y: 400)
        )

        try expect(rect == CGRect(x: 250, y: 200, width: 500, height: 400), "Unexpected centered source rect: \(rect)")
    }

    private static func testViewportContentPointMapping() throws {
        let controller = ZoomViewportController()
        controller.configure(for: try makeFrame(), initialZoom: 2)

        let point = controller.contentPoint(
            for: CGPoint(x: 500, y: 400),
            destinationBounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
            cursorLocation: CGPoint(x: 500, y: 400)
        )

        try expect(point == CGPoint(x: 500, y: 400), "Unexpected mapped content point: \(point)")
    }

    private static func testViewportContentToDestinationTransform() throws {
        let controller = ZoomViewportController()
        let transform = controller.contentToDestinationTransform(
            source: CGRect(x: 250, y: 200, width: 500, height: 400),
            destinationBounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        try expect(CGPoint(x: 250, y: 200).applying(transform) == CGPoint(x: 0, y: 0), "Expected source origin to map to destination origin")
        try expect(CGPoint(x: 500, y: 400).applying(transform) == CGPoint(x: 500, y: 400), "Expected source center to map to destination center")
    }

    private static func testFreehandAnnotationLifecycle() throws {
        let controller = AnnotationController()

        controller.begin(at: CGPoint(x: 1, y: 2))
        controller.update(at: CGPoint(x: 3, y: 4))
        controller.update(at: CGPoint(x: 5, y: 6))
        controller.end(at: CGPoint(x: 7, y: 8))

        try expect(controller.annotationSnapshot.count == 1, "Expected one freehand annotation")
        try expect(controller.annotationSnapshot[0].tool == .pen, "Expected freehand tool to be pen")
        let points = controller.annotationSnapshot[0].points
        try expect(
            points.first == CGPoint(x: 1, y: 2)
                && points.last == CGPoint(x: 7, y: 8)
                && points.count >= 4
                && zip(points, points.dropFirst()).allSatisfy {
                    hypot($1.x - $0.x, $1.y - $0.y)
                        <= AnnotationFreehandInputResampler.screenSpacing + 0.01
                },
            "Expected uniformly resampled freehand points with an immediate trailing endpoint"
        )
    }

    private static func testShapeAnnotationEndpointReplacement() throws {
        let controller = AnnotationController()
        controller.currentTool = .rectangle

        controller.begin(at: CGPoint(x: 10, y: 20))
        controller.update(at: CGPoint(x: 30, y: 40))
        controller.update(at: CGPoint(x: 50, y: 60))
        controller.end(at: CGPoint(x: 70, y: 80))

        try expect(controller.annotationSnapshot.count == 1, "Expected one rectangle annotation")
        try expect(controller.annotationSnapshot[0].points == [CGPoint(x: 10, y: 20), CGPoint(x: 70, y: 80)], "Shape should keep start and final endpoint")
    }

    private static func testAxisAlignedShapeCreation() throws {
        let anchor = CGPoint(x: 100, y: 100)
        let endpoints = [
            CGPoint(x: 145, y: 160),
            CGPoint(x: 55, y: 160),
            CGPoint(x: 145, y: 40),
            CGPoint(x: 55, y: 40)
        ]

        for tool in [AnnotationTool.rectangle, .diamond] {
            for endpoint in endpoints {
                let controller = AnnotationController()
                controller.begin(at: anchor, tool: tool)
                controller.update(at: endpoint)
                guard let preview = controller.inProgressElementSnapshot,
                      case .shape(let previewShape) = preview.geometry else {
                    throw SelfTestError.failure("Expected an in-progress axis-aligned shape")
                }
                let expectedBounds = CGRect(
                    x: min(anchor.x, endpoint.x),
                    y: min(anchor.y, endpoint.y),
                    width: abs(endpoint.x - anchor.x),
                    height: abs(endpoint.y - anchor.y)
                )
                try expect(
                    previewShape.start == expectedBounds.origin
                        && previewShape.end == CGPoint(
                            x: expectedBounds.maxX,
                            y: expectedBounds.maxY
                        )
                        && preview.metadata.rotation == 0,
                    "Expected \(tool) preview to use canonical bounds in every drag quadrant"
                )

                controller.end(at: endpoint)
                guard let committed = controller.elementSnapshot.first,
                      case .shape(let committedShape) = committed.geometry else {
                    throw SelfTestError.failure("Expected a committed axis-aligned shape")
                }
                try expect(
                    committedShape == previewShape && committed.metadata.rotation == 0,
                    "Expected \(tool) committed geometry to exactly match its aligned preview"
                )
            }
        }

        for tool in [AnnotationTool.rectangle, .diamond] {
            for endpoint in endpoints {
                let controller = AnnotationController()
                controller.begin(at: anchor, tool: tool)
                controller.update(at: endpoint, constrainShapeAspect: true)
                guard let preview = controller.inProgressElementSnapshot,
                      case .shape(let previewShape) = preview.geometry else {
                    throw SelfTestError.failure("Expected a constrained shape preview")
                }
                let side = max(abs(endpoint.x - anchor.x), abs(endpoint.y - anchor.y))
                let constrainedEndpoint = CGPoint(
                    x: anchor.x + (endpoint.x < anchor.x ? -side : side),
                    y: anchor.y + (endpoint.y < anchor.y ? -side : side)
                )
                let expectedBounds = CGRect(
                    x: min(anchor.x, constrainedEndpoint.x),
                    y: min(anchor.y, constrainedEndpoint.y),
                    width: side,
                    height: side
                )
                try expect(
                    previewShape.bounds == expectedBounds,
                    "Expected Shift-\(tool) to preserve the anchor and drag quadrant"
                )
                controller.end(at: endpoint, constrainShapeAspect: true)
                guard let committed = controller.elementSnapshot.first,
                      case .shape(let committedShape) = committed.geometry else {
                    throw SelfTestError.failure("Expected a committed constrained shape")
                }
                try expect(
                    committedShape == previewShape
                        && committedShape.bounds.width == committedShape.bounds.height
                        && committed.metadata.rotation == 0,
                    "Expected Shift-\(tool) preview and commit to remain the same aligned square"
                )
            }
        }

        let legacyRectangle = AnnotationController()
        legacyRectangle.begin(
            at: anchor,
            tool: .rectangle,
            legacyModifierGesture: true
        )
        legacyRectangle.end(at: CGPoint(x: 42, y: 168))
        guard let legacyElement = legacyRectangle.elementSnapshot.first,
              case .shape(let legacyShape) = legacyElement.geometry else {
            throw SelfTestError.failure("Expected a legacy modifier rectangle")
        }
        try expect(
            legacyShape.bounds == CGRect(x: 42, y: 100, width: 58, height: 68)
                && legacyShape.start == legacyShape.bounds.origin
                && legacyElement.metadata.rotation == 0,
            "Expected the existing Control-drag rectangle to remain canonically axis-aligned"
        )
        try expect(
            ZoomCanvasView.gestureTool(
                control: false,
                shift: true,
                tab: false,
                selectedTool: .rectangle
            ) == nil
                && ZoomCanvasView.gestureTool(
                    control: false,
                    shift: true,
                    tab: false,
                    selectedTool: .diamond
                ) == nil,
            "Expected Shift to constrain direct rectangle and diamond tools instead of switching tools"
        )

        let rotationController = AnnotationController()
        rotationController.begin(at: CGPoint(x: 30, y: 40), tool: .rectangle)
        rotationController.end(at: CGPoint(x: 110, y: 90))
        guard let original = rotationController.elementSnapshot.first,
              case .shape(let originalShape) = original.geometry else {
            throw SelfTestError.failure("Expected an aligned rectangle before explicit rotation")
        }
        rotationController.currentTool = .select
        let selectionPoint = CGPoint(
            x: originalShape.bounds.minX,
            y: originalShape.bounds.midY
        )
        _ = rotationController.beginSelectionInteraction(
            at: selectionPoint,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        rotationController.endSelectionInteraction(at: selectionPoint, modifiers: [])
        guard let selected = rotationController.elementSnapshot.first,
              let rotationHandle = AnnotationGeometry.selectionDecoration(
                  for: selected,
                  zoomScale: 1
              )?.handles.first(where: { $0.kind == .rotation }) else {
            throw SelfTestError.failure("Expected an explicit rotation handle on the aligned shape")
        }
        _ = rotationController.beginSelectionInteraction(
            at: rotationHandle.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        rotationController.endSelectionInteraction(
            at: CGPoint(x: originalShape.bounds.maxX + 30, y: originalShape.bounds.midY),
            modifiers: []
        )
        guard let rotated = rotationController.elementSnapshot.first,
              case .shape(let rotatedShape) = rotated.geometry else {
            throw SelfTestError.failure("Expected the explicitly rotated rectangle")
        }
        try expect(
            rotated.metadata.rotation != 0 && rotatedShape == originalShape,
            "Expected later rotation-handle edits to preserve canonical shape geometry"
        )
    }

    private static func testUndoAndClear() throws {
        let controller = AnnotationController()

        controller.begin(at: .zero)
        controller.end(at: CGPoint(x: 1, y: 1))
        controller.begin(at: CGPoint(x: 2, y: 2))
        controller.end(at: CGPoint(x: 3, y: 3))

        try expect(controller.annotationSnapshot.count == 2, "Expected two annotations before undo")
        controller.undo()
        try expect(controller.annotationSnapshot.count == 1, "Expected one annotation after undo")
        try expect(controller.canRedo, "Expected undo to enable redo")
        controller.redo()
        try expect(controller.annotationSnapshot.count == 2, "Expected redo to restore the annotation")
        controller.clear()
        try expect(controller.annotationSnapshot.isEmpty, "Expected no annotations after clear")
        controller.undo()
        try expect(controller.annotationSnapshot.count == 2, "Expected undo to restore a cleared scene")
        controller.redo()
        try expect(controller.annotationSnapshot.isEmpty, "Expected redo to clear the scene again")
    }

    private static func testClearCancelsTransientAnnotationState() throws {
        let queuedController = AnnotationController()
        var smartDefaults = DrawingDefaults.default
        smartDefaults.smartDrawEnabled = true
        smartDefaults.pressureMode = .simulated
        queuedController.applyDrawingDefaults(smartDefaults, strokeWidth: 5)
        queuedController.begin(
            at: CGPoint(x: 4, y: 32),
            pressure: nil,
            timestamp: 0,
            zoomScale: 1
        )
        for index in 1...12 {
            queuedController.update(
                at: CGPoint(x: 4 + CGFloat(index * 8), y: 32),
                timestamp: Double(index) / 30,
                zoomScale: 1
            )
        }
        queuedController.enqueueFreehandInputs([
            AnnotationRawFreehandInput(
                location: CGPoint(x: 300, y: 32),
                pressure: nil,
                timestamp: 0.5
            ),
            AnnotationRawFreehandInput(
                location: CGPoint(x: 600, y: 32),
                pressure: nil,
                timestamp: 0.6
            )
        ])
        _ = queuedController.drainFreehandInput(
            zoomScale: 1,
            budget: AnnotationFreehandDrainBudget(
                maximumRawEvents: 1,
                maximumGeneratedSamples: 1
            )
        )

        let width = 128
        let height = 64
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SelfTestError.failure("Could not create clear-state render context")
        }
        queuedController.render(
            in: context,
            bounds: CGRect(x: 0, y: 0, width: width, height: height)
        )
        try expect(
            queuedController.hasPendingFreehandInput
                && queuedController.hasPendingSmartDrawRecognitionForTesting
                && queuedController.hasPendingTransientAnnotationWorkForTesting,
            "Expected queued interpolation, pressure, Smart Draw, and render cache state before clear"
        )

        queuedController.clear()
        let postClearDrain = queuedController.drainFreehandInput(zoomScale: 1)
        try expect(
            queuedController.elementSnapshot.isEmpty
                && queuedController.inProgressElementSnapshot == nil
                && queuedController.smartDrawPreviewElementSnapshot == nil
                && !queuedController.hasPendingFreehandInput
                && !queuedController.hasPendingSmartDrawRecognitionForTesting
                && !queuedController.hasPendingTransientAnnotationWorkForTesting
                && queuedController.editorStateKind == .idle
                && !queuedController.hasActiveDrawingGesture
                && postClearDrain == AnnotationFreehandDrainStats()
                && !queuedController.canUndo,
            "Expected clear to cancel every queued creation state without committing a partial stroke"
        )
        queuedController.clear()
        try expect(
            !queuedController.hasPendingTransientAnnotationWorkForTesting
                && !queuedController.canUndo,
            "Expected repeated clear cancellation to remain idempotent"
        )

        let timerController = AnnotationController()
        let timerCanvas = try makeCanvas(annotationController: timerController)
        timerController.onStateChanged = { [weak timerCanvas] in
            timerCanvas?.annotationStateDidChange()
        }
        timerCanvas.interactionMode = .drawOnly
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 4, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ), let mouseDragged = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: 100, y: 20),
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ) else {
            throw SelfTestError.failure("Could not create clear-state pointer events")
        }
        timerCanvas.mouseDown(with: mouseDown)
        timerCanvas.mouseDragged(with: mouseDragged)
        try expect(
            timerCanvas.hasActiveFreehandDrainTimerForTesting
                && timerCanvas.hasPendingAnnotationInputForTesting,
            "Expected the freehand drain timer to be active before clear"
        )
        timerController.clear()
        try expect(
            !timerController.hasPendingFreehandInput
                && !timerCanvas.hasActiveFreehandDrainTimerForTesting
                && !timerCanvas.hasPendingAnnotationInputForTesting,
            "Expected clear to stop the canvas timer and pending end state immediately"
        )
        timerCanvas.prepareForClose()

        let eraserController = AnnotationController()
        eraserController.currentTool = .rectangle
        eraserController.begin(at: CGPoint(x: 10, y: 10))
        eraserController.end(at: CGPoint(x: 50, y: 50))
        eraserController.begin(at: CGPoint(x: 70, y: 10))
        eraserController.end(at: CGPoint(x: 110, y: 50))
        eraserController.beginErasing(
            at: CGPoint(x: 10, y: 30),
            zoomScale: 1
        )
        try expect(
            eraserController.elementSnapshot.count == 2
                && eraserController.pendingErasureElementIDsForTesting.count == 1
                && eraserController.hasActiveDrawingGesture,
            "Expected eraser hits to remain staged before clear"
        )
        eraserController.clear()
        eraserController.clear()
        try expect(
            eraserController.elementSnapshot.isEmpty
                && !eraserController.hasPendingTransientAnnotationWorkForTesting,
            "Expected clear to cancel the eraser transaction before clearing the scene"
        )
        eraserController.undo()
        try expect(
            eraserController.elementSnapshot.count == 2,
            "Expected one undo to restore the complete pre-eraser scene"
        )
        eraserController.undo()
        try expect(
            eraserController.elementSnapshot.count == 1,
            "Expected normal history to continue before the clear operation"
        )
        eraserController.redo()
        eraserController.redo()
        try expect(
            eraserController.elementSnapshot.isEmpty,
            "Expected normal redo history to reapply creation and clear without a stale transaction"
        )
    }

    private static func testDrawingStyleSessionScoping() throws {
        let controller = AnnotationController()
        controller.applyDrawingDefaults(
            .default,
            strokeWidth: 7,
            highlighterWidth: 18,
            geometryWidth: 3
        )
        controller.currentTool = .pen
        controller.setStrokeColor(.palette(.green))
        controller.setOpacity(0.4)
        controller.currentTool = .highlighter
        controller.setStrokeColor(.palette(.highlighterPink))
        controller.setOpacity(0.8)

        controller.reset()
        controller.applyDrawingDefaults(
            .default,
            strokeWidth: 7,
            highlighterWidth: 18,
            geometryWidth: 3
        )
        controller.currentTool = .highlighter
        let freshHighlighterColor = controller.currentStyle.strokeColor
        let freshHighlighterWidth = controller.currentStyle.strokeWidth
        let freshHighlighterOpacity = controller.currentStyle.opacity
        controller.currentTool = .pen
        try expect(
            freshHighlighterColor == .palette(.highlighterYellow)
                && freshHighlighterWidth == 18
                && freshHighlighterOpacity == 1
                && controller.currentStyle.strokeColor == .palette(.red)
                && controller.currentStyle.strokeWidth == 7
                && controller.currentStyle.opacity == 1,
            "Expected a non-remembered overlay session to restore independent fresh colors, widths, and opacities"
        )

        var rememberedDefaults = DrawingDefaults.default
        rememberedDefaults.tool = .highlighter
        rememberedDefaults.strokeColor = .palette(.highlighterPink)
        rememberedDefaults.regularStrokeColor = .palette(.green)
        rememberedDefaults.highlighterStrokeColor = .palette(.highlighterPink)
        rememberedDefaults.penStrokeWidth = 11
        rememberedDefaults.highlighterStrokeWidth = 28
        rememberedDefaults.geometryStrokeWidth = 6
        rememberedDefaults.penOpacity = 0.4
        rememberedDefaults.geometryOpacity = 0.65
        rememberedDefaults.highlighterOpacity = 0.8
        rememberedDefaults.opacity = 0.8
        rememberedDefaults.pressureMode = .simulated
        rememberedDefaults.freehandSloppiness = .cartoonist
        rememberedDefaults.outlinedSloppiness = .architect
        rememberedDefaults.synchronizeSelectedSloppiness()
        let suiteName = "ZoomItMacSelfTest.DrawingStyleScopes.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.failure("Could not create drawing-style UserDefaults suite")
        }
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: userDefaults)
        var settings = AppSettings.defaults
        settings.rememberLastDrawingStyle = true
        settings.lastDrawingDefaults = rememberedDefaults
        store.save(settings)

        let reloaded = store.load()
        guard let persistedDefaults = reloaded.lastDrawingDefaults else {
            throw SelfTestError.failure("Expected remembered drawing defaults to persist")
        }
        controller.reset()
        controller.applyDrawingDefaults(
            persistedDefaults,
            strokeWidth: reloaded.rootPenWidth
        )
        let rememberedHighlighterColor = controller.currentStyle.strokeColor
        let rememberedHighlighterWidth = controller.currentStyle.strokeWidth
        controller.currentTool = .pen
        let rememberedRegularColor = controller.currentStyle.strokeColor
        let rememberedPenWidth = controller.currentStyle.strokeWidth
        let rememberedPenPressure = controller.currentStyle.pressureMode
        let rememberedPenSloppiness = controller.currentStyle.sloppiness
        let rememberedPenOpacity = controller.currentStyle.opacity
        controller.currentTool = .rectangle
        let rememberedOutlinedSloppiness = controller.currentStyle.sloppiness
        let rememberedGeometryOpacity = controller.currentStyle.opacity
        controller.currentTool = .highlighter
        try expect(
            reloaded.rememberLastDrawingStyle
                && rememberedHighlighterColor == .palette(.highlighterPink)
                && rememberedHighlighterWidth == 28
                && rememberedRegularColor == .palette(.green)
                && rememberedPenWidth == 11
                && rememberedPenPressure == .simulated
                && rememberedPenSloppiness == .cartoonist
                && rememberedPenOpacity == 0.4
                && rememberedOutlinedSloppiness == .architect
                && rememberedGeometryOpacity == 0.65
                && controller.currentStyle.strokeColor == .palette(.highlighterPink)
                && controller.currentStyle.strokeWidth == 28
                && controller.currentStyle.opacity == 0.8,
            "Expected remembered color, width, pressure, sloppiness, and opacity scopes to persist independently"
        )
    }

    private static func testAnnotationSceneCreationAndStableIDs() throws {
        let scene = AnnotationScene()
        let elementID = AnnotationElementID()
        let element = AnnotationElement.legacy(
            id: elementID,
            tool: .pen,
            points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)],
            style: .default
        )

        scene.append(element)
        try expect(scene.elements.count == 1, "Expected one scene element")
        try expect(scene.elements[0].id == elementID, "Expected the scene to preserve the element ID")
        guard case .freehand(let freehand) = scene.elements[0].geometry else {
            throw SelfTestError.failure("Expected typed freehand geometry")
        }
        try expect(
            freehand.samples.map(\.location) == [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)],
            "Expected freehand samples to preserve legacy points"
        )

        scene.updateElement(withID: elementID) { element in
            element.metadata.rotation = .pi / 4
        }
        try expect(scene.elements[0].id == elementID, "Expected element edits to retain the stable ID")
    }

    private static func testAnnotationSceneTransactionalHistory() throws {
        let scene = AnnotationScene()
        let first = AnnotationElement.legacy(
            tool: .line,
            points: [.zero, CGPoint(x: 10, y: 10)],
            style: .default
        )
        let second = AnnotationElement.legacy(
            tool: .ellipse,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 50)],
            style: .default
        )

        scene.beginTransaction()
        scene.append(first)
        scene.append(second)
        scene.commitTransaction()

        try expect(scene.elements.map(\.id) == [first.id, second.id], "Expected both transaction elements")
        try expect(scene.undo(), "Expected the transaction to be undoable")
        try expect(scene.elements.isEmpty, "Expected one undo to revert the entire transaction")
        try expect(scene.redo(), "Expected the transaction to be redoable")
        try expect(scene.elements.map(\.id) == [first.id, second.id], "Expected redo to restore stable IDs")

        let third = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 60, y: 60), CGPoint(x: 80, y: 80)],
            style: .default
        )
        try expect(scene.undo(), "Expected a second undo before branching history")
        scene.append(third)
        try expect(!scene.canRedo, "Expected a new mutation to discard the redo branch")
    }

    private static func testAnnotationSceneOrdering() throws {
        let scene = AnnotationScene()
        let first = AnnotationElement.legacy(tool: .pen, points: [.zero], style: .default)
        let second = AnnotationElement.legacy(tool: .line, points: [.zero], style: .default)
        let third = AnnotationElement.legacy(tool: .ellipse, points: [.zero], style: .default)
        scene.append(first)
        scene.append(second)
        scene.append(third)

        scene.moveElements(withIDs: [second.id], to: 0)
        try expect(
            scene.elements.map(\.id) == [second.id, first.id, third.id],
            "Expected scene ordering to move the requested element"
        )
        try expect(
            scene.elements.map(\.metadata.zIndex) == [0, 1, 2],
            "Expected z-order metadata to match scene order"
        )

        try expect(scene.undo(), "Expected ordering to be undoable")
        try expect(
            scene.elements.map(\.id) == [first.id, second.id, third.id],
            "Expected undo to restore the previous ordering"
        )
    }

    private static func testAnnotationSceneGroupingAndLocking() throws {
        let scene = AnnotationScene()
        let first = AnnotationElement.legacy(tool: .rectangle, points: [.zero], style: .default)
        let second = AnnotationElement.legacy(tool: .ellipse, points: [.zero], style: .default)
        let third = AnnotationElement.legacy(tool: .pen, points: [.zero], style: .default)
        scene.append(first)
        scene.append(second)
        scene.append(third)

        guard let groupID = scene.groupElements(withIDs: [first.id, second.id]) else {
            throw SelfTestError.failure("Expected two elements to form a group")
        }
        scene.setLocked(true, for: [first.id, second.id])
        scene.select([first.id, third.id, AnnotationElementID()])

        try expect(
            scene.element(withID: first.id)?.metadata.groupIDs == [groupID]
                && scene.element(withID: second.id)?.metadata.groupIDs == [groupID],
            "Expected grouped elements to share group metadata"
        )
        try expect(
            scene.element(withID: third.id)?.metadata.groupIDs.isEmpty == true,
            "Expected ungrouped elements to remain unchanged"
        )
        try expect(
            scene.element(withID: first.id)?.metadata.isLocked == true
                && scene.element(withID: second.id)?.metadata.isLocked == true,
            "Expected lock metadata on the requested elements"
        )
        try expect(
            scene.selection.contains(first.id)
                && scene.selection.contains(third.id)
                && scene.selection.elementIDs.count == 2,
            "Expected selection to retain only IDs present in the scene"
        )
    }

    private static func testAnnotationSceneBindingIntegrity() throws {
        let scene = AnnotationScene()
        let targetID = AnnotationElementID()
        let target = AnnotationElement(
            id: targetID,
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 10, y: 10),
                    end: CGPoint(x: 50, y: 50)
                )
            ),
            style: .default
        )
        let lineID = AnnotationElementID()
        let line = AnnotationElement(
            id: lineID,
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 30, y: 30), CGPoint(x: 80, y: 80)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: AnnotationBinding(targetElementID: targetID),
                    endBinding: nil
                )
            ),
            style: .default
        )
        scene.append(target)
        scene.append(line)

        guard case .linear(let boundLine) = scene.element(withID: lineID)?.geometry else {
            throw SelfTestError.failure("Expected a linear element")
        }
        try expect(boundLine.startBinding?.targetElementID == targetID, "Expected a valid binding to be retained")

        scene.removeElements(withIDs: [targetID])
        guard case .linear(let unboundLine) = scene.element(withID: lineID)?.geometry else {
            throw SelfTestError.failure("Expected the line to remain after deleting its target")
        }
        try expect(unboundLine.startBinding == nil, "Expected deletion to remove dangling bindings")

        try expect(scene.undo(), "Expected target deletion to be undoable")
        guard case .linear(let restoredLine) = scene.element(withID: lineID)?.geometry else {
            throw SelfTestError.failure("Expected the line after undo")
        }
        try expect(
            scene.element(withID: targetID) != nil && restoredLine.startBinding?.targetElementID == targetID,
            "Expected undo to restore the target and its binding"
        )
    }

    private static func testAnnotationGeometryBoundsAndTransforms() throws {
        var style = AnnotationStyle.default
        style.strokeWidth = 4
        var element = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 10, y: 20),
                    end: CGPoint(x: 50, y: 40)
                )
            ),
            style: style
        )
        element.metadata.rotation = .pi / 2

        try expect(
            AnnotationGeometry.localBounds(of: element) == CGRect(x: 10, y: 20, width: 40, height: 20),
            "Expected unrotated shape bounds to remain in content coordinates"
        )
        try expect(
            approximatelyEqual(
                AnnotationGeometry.worldBounds(of: element, includingStroke: false),
                CGRect(x: 20, y: 10, width: 20, height: 40)
            ),
            "Expected rotation-aware world bounds"
        )
        let expectedStrokeInset = style.strokeWidth / 2
            + AnnotationRoughStroke.maximumDestinationDeviation(
                for: style.sloppiness,
                strokeWidth: style.strokeWidth
            )
        try expect(
            approximatelyEqual(
                AnnotationGeometry.worldBounds(of: element),
                CGRect(x: 20, y: 10, width: 20, height: 40)
                    .insetBy(dx: -expectedStrokeInset, dy: -expectedStrokeInset)
            ),
            "Expected stroke width and rough destination deviation to expand world bounds"
        )

        let localPoint = CGPoint(x: 10, y: 20)
        let worldPoint = localPoint.applying(AnnotationGeometry.worldTransform(for: element))
        let roundTrip = worldPoint.applying(AnnotationGeometry.inverseWorldTransform(for: element))
        try expect(
            approximatelyEqual(roundTrip, localPoint),
            "Expected element transforms to round-trip between local and world space"
        )

        let arrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 30, y: 30), CGPoint(x: 70, y: 30)],
                    route: .straight,
                    startArrowhead: .arrow,
                    endArrowhead: .none,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: style
        )
        try expect(
            AnnotationGeometry.localBounds(of: arrow).height >= style.strokeWidth * 4,
            "Expected arrowhead geometry to participate in element bounds"
        )
    }

    private static func testAdvancedLinearPointEditing() throws {
        let scene = AnnotationScene()
        let line = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 0, y: 0),
                        CGPoint(x: 50, y: 0),
                        CGPoint(x: 100, y: 0)
                    ],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: AnnotationStyle(color: .red, rootWidth: 2, alpha: 1)
        )
        scene.append(line)
        scene.select([line.id])
        let editor = AnnotationEditor(scene: scene)

        try expect(
            editor.beginLinearPointEditing(),
            "Expected a selected multi-point line to enter point-edit mode"
        )
        try expect(
            editor.stateKind == .editingLinearPoints,
            "Expected an explicit linear point-edit state"
        )

        _ = editor.beginInteraction(
            at: CGPoint(x: 50, y: 0),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.updateInteraction(to: CGPoint(x: 50, y: 20), modifiers: [])
        editor.endInteraction(at: CGPoint(x: 50, y: 20), modifiers: [])
        guard case .linear(let dragged) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected dragged multi-point geometry")
        }

        try expect(
            dragged.points == [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 50, y: 20),
                CGPoint(x: 100, y: 0)
            ],
            "Expected individual point dragging to preserve the other local path points"
        )

        _ = editor.beginInteraction(
            at: CGPoint(x: 25, y: 10),
            zoomScale: 1,
            modifiers: [],
            clickCount: 2
        )
        editor.endInteraction(at: CGPoint(x: 25, y: 10), modifiers: [])
        guard case .linear(let inserted) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected point insertion geometry")
        }
        try expect(
            inserted.points.count == 4 && inserted.points[1] == CGPoint(x: 25, y: 10),
            "Expected double-clicking a segment to insert a point at the selected location"
        )

        editor.removeSelectedLinearPoints()
        guard case .linear(let removed) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected point removal geometry")
        }
        try expect(
            removed.points.count == 3,
            "Expected selected point removal while retaining a valid two-or-more-point path"
        )

        _ = editor.beginInteraction(
            at: CGPoint(x: 75, y: 10),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.updateInteraction(to: CGPoint(x: 75, y: 30), modifiers: [])
        editor.endInteraction(at: CGPoint(x: 75, y: 30), modifiers: [])
        guard case .linear(let movedSegment) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected segment drag geometry")
        }
        try expect(
            movedSegment.points[1] == CGPoint(x: 50, y: 40)
                && movedSegment.points[2] == CGPoint(x: 100, y: 20),
            "Expected segment dragging to move both adjacent points as one transaction"
        )
        try expect(scene.undo(), "Expected the segment drag to be undoable")
        try expect(
            editor.stateKind == .editingLinearPoints,
            "Expected point-edit mode to remain active after a completed point transaction"
        )
        editor.finishLinearPointEditing()
        try expect(editor.stateKind == .idle, "Expected point-edit mode to exit explicitly")
    }

    private static func testLinearPointEditingRevalidation() throws {
        func makeEditingLine() -> (
            scene: AnnotationScene,
            editor: AnnotationEditor,
            elementID: AnnotationElementID
        ) {
            let line = AnnotationElement(
                geometry: .linear(
                    AnnotationLinearGeometry(
                        points: [
                            CGPoint(x: 0, y: 0),
                            CGPoint(x: 50, y: 0),
                            CGPoint(x: 100, y: 0)
                        ],
                        route: .straight,
                        startArrowhead: .none,
                        endArrowhead: .arrow,
                        startBinding: nil,
                        endBinding: nil
                    )
                ),
                style: .default
            )
            let scene = AnnotationScene(elements: [line])
            scene.select([line.id])
            let editor = AnnotationEditor(scene: scene)
            _ = editor.beginLinearPointEditing()
            return (scene, editor, line.id)
        }

        do {
            let setup = makeEditingLine()
            setup.scene.setLocked(true, for: [setup.elementID])
            let locked = setup.scene.snapshot
            _ = setup.editor.beginInteraction(
                at: CGPoint(x: 50, y: 0),
                zoomScale: 1,
                modifiers: [],
                clickCount: 1
            )
            setup.editor.updateInteraction(to: CGPoint(x: 50, y: 30), modifiers: [])
            setup.editor.endInteraction(at: CGPoint(x: 50, y: 30), modifiers: [])
            try expect(
                setup.scene.snapshot == locked && setup.editor.stateKind == .idle,
                "Expected locked targets to block point dragging and exit point-edit mode"
            )
        }

        do {
            let setup = makeEditingLine()
            setup.scene.setLocked(true, for: [setup.elementID])
            let locked = setup.scene.snapshot
            _ = setup.editor.beginInteraction(
                at: CGPoint(x: 25, y: 0),
                zoomScale: 1,
                modifiers: [],
                clickCount: 2
            )
            try expect(
                setup.scene.snapshot == locked && setup.editor.stateKind == .idle,
                "Expected locked targets to block double-click point insertion"
            )
        }

        do {
            let setup = makeEditingLine()
            _ = setup.editor.beginInteraction(
                at: CGPoint(x: 25, y: 0),
                zoomScale: 1,
                modifiers: [],
                clickCount: 1
            )
            setup.editor.endInteraction(at: CGPoint(x: 25, y: 0), modifiers: [])
            setup.scene.setLocked(true, for: [setup.elementID])
            let locked = setup.scene.snapshot
            setup.editor.insertLinearPoint()
            try expect(
                setup.scene.snapshot == locked && setup.editor.stateKind == .idle,
                "Expected locked targets to block explicit point insertion"
            )
        }

        do {
            let setup = makeEditingLine()
            _ = setup.editor.beginInteraction(
                at: CGPoint(x: 50, y: 0),
                zoomScale: 1,
                modifiers: [],
                clickCount: 1
            )
            setup.editor.endInteraction(at: CGPoint(x: 50, y: 0), modifiers: [])
            setup.scene.setLocked(true, for: [setup.elementID])
            let locked = setup.scene.snapshot
            setup.editor.removeSelectedLinearPoints()
            try expect(
                setup.scene.snapshot == locked && setup.editor.stateKind == .idle,
                "Expected locked targets to block point removal"
            )
        }

        let controller = AnnotationController()
        controller.currentTool = .line
        controller.begin(at: CGPoint(x: 0, y: 0))
        controller.update(at: CGPoint(x: 100, y: 0))
        controller.end(at: CGPoint(x: 100, y: 0))
        controller.currentTool = .select
        if controller.isEditingLinearPoints {
            _ = controller.toggleLinearPointEditing()
        }
        controller.selectAll()
        controller.toggleSelectionLock()
        controller.toggleSelectionLock()
        try expect(
            controller.toggleLinearPointEditing(),
            "Expected the unlocked line to re-enter point-edit mode"
        )
        controller.undo()
        try expect(
            controller.elementSnapshot.first?.metadata.isLocked == true
                && !controller.isEditingLinearPoints,
            "Expected undo restoring a lock to exit point-edit mode immediately"
        )
    }

    private static func testPassiveLinearPointDiscovery() throws {
        let controller = AnnotationController()
        controller.currentTool = .line
        controller.begin(at: CGPoint(x: 16, y: 40))
        controller.update(at: CGPoint(x: 96, y: 40))
        controller.end(at: CGPoint(x: 96, y: 40))
        controller.currentTool = .select
        if controller.isEditingLinearPoints {
            _ = controller.toggleLinearPointEditing()
        }
        let passiveState = DrawingToolbarState(annotationController: controller)
        try expect(
            controller.hasSelection
                && !controller.isEditingLinearPoints
                && controller.linearPointDecorationElement != nil
                && passiveState.showsLinearPointHandles
                && !passiveState.canInsertLinearPoint
                && !passiveState.canRemoveLinearPoints
                && !passiveState.canUnbindLinearEndpoints,
            "Expected selected unbound lines to expose passive handles while disabling no-op actions "
                + "(selection \(controller.hasSelection), editing \(controller.isEditingLinearPoints), "
                + "decoration \(controller.linearPointDecorationElement != nil), "
                + "state handles \(passiveState.showsLinearPointHandles), "
                + "insert \(passiveState.canInsertLinearPoint), "
                + "remove \(passiveState.canRemoveLinearPoints), "
                + "unbind \(passiveState.canUnbindLinearEndpoints))"
        )
        let inspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        inspector.update(state: passiveState)
        _ = inspector.visibleSectionFramesForTesting()
        let inspectorButtons = descendantViews(of: NSButton.self, in: inspector.view)
        try expect(
            ["Edit Points", "Insert Point", "Remove Points", "Unbind Ends"].allSatisfy {
                label in
                !inspectorButtons.contains { $0.accessibilityLabel() == label }
            },
            "Expected point-editing actions to remain in context and overflow menus"
        )
        let decorationPixels = try renderSelectionPixels(
            annotationController: controller,
            width: 112,
            height: 80
        )
        try expect(
            hasPaintedPixel(
                decorationPixels,
                width: 112,
                height: 80,
                near: CGPoint(x: 16, y: 40),
                radius: 5
            )
                && hasPaintedPixel(
                    decorationPixels,
                    width: 112,
                    height: 80,
                    near: CGPoint(x: 96, y: 40),
                    radius: 5
                ),
            "Expected passive Select-mode endpoint dots to remain visibly rendered"
        )

        var curved = AnnotationLinearGeometry(
            points: [
                CGPoint(x: 16, y: 60),
                CGPoint(x: 56, y: 18),
                CGPoint(x: 100, y: 60)
            ],
            route: .curved,
            startArrowhead: .circleOutline,
            endArrowhead: .arrow,
            startBinding: nil,
            endBinding: nil
        )
        curved.bezierControls = AnnotationGeometry.bezierControls(for: curved)
        let curveElement = AnnotationElement(
            geometry: .linear(curved),
            style: .default
        )
        let scene = AnnotationScene(elements: [curveElement])
        scene.select([curveElement.id])
        let editor = AnnotationEditor(scene: scene)
        let controlPoint = curved.bezierControls[0].start
        _ = editor.beginInteraction(
            at: controlPoint,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(
            editor.stateKind == .editingLinearPoints
                && editor.selectedLinearControl
                    == .control(segment: 0, end: .start),
            "Expected clicking a visible Bezier control to enter point editing directly"
        )
        editor.updateInteraction(
            to: CGPoint(x: controlPoint.x + 12, y: controlPoint.y - 8),
            modifiers: []
        )
        editor.endInteraction(
            at: CGPoint(x: controlPoint.x + 12, y: controlPoint.y - 8),
            modifiers: []
        )
        guard case .linear(let editedCurve) = scene.element(
            withID: curveElement.id
        )?.geometry else {
            throw SelfTestError.failure("Expected edited curve geometry")
        }
        try expect(
            editedCurve.bezierControls[0].start != controlPoint,
            "Expected dragging a passive control dot to mutate the curve"
        )

        editor.finishLinearPointEditing()
        let endpoint = editedCurve.points[0]
        _ = editor.beginInteraction(
            at: endpoint,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(
            editor.stateKind == .editingLinearPoints
                && editor.selectedLinearPointIndices == [0],
            "Expected clicking a visible endpoint dot to enter point editing directly"
        )
    }

    private static func testBezierLinearGeometry() throws {
        let linear = AnnotationLinearGeometry(
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 50, y: 0),
                CGPoint(x: 100, y: 0)
            ],
            route: .curved,
            startArrowhead: .circle,
            endArrowhead: .triangle,
            startBinding: nil,
            endBinding: nil,
            bezierControls: [
                AnnotationBezierControl(
                    start: CGPoint(x: 0, y: 40),
                    end: CGPoint(x: 50, y: 40)
                ),
                AnnotationBezierControl(
                    start: CGPoint(x: 50, y: -40),
                    end: CGPoint(x: 100, y: -40)
                )
            ]
        )
        let displayPoints = AnnotationGeometry.linearDisplayPoints(linear, subdivisions: 16)
        try expect(
            displayPoints.count == 33
                && displayPoints.map(\.y).max()! > 20
                && displayPoints.map(\.y).min()! < -20,
            "Expected editable cubic controls to produce deterministic curved segments"
        )
        try expect(
            AnnotationGeometry.linearPath(linear).boundingBoxOfPath.height > 40,
            "Expected curved-path bounds to include Bezier extrema"
        )

        let insertion = AnnotationLinearLocation(
            segmentIndex: 0,
            parameter: 0.5,
            point: .zero,
            distance: 0
        )
        let split = AnnotationGeometry.insertingPoint(into: linear, at: insertion)
        try expect(
            split.points.count == 4
                && split.bezierControls.count == 3
                && approximatelyEqual(split.points[1], CGPoint(x: 25, y: 30)),
            "Expected de Casteljau insertion to preserve an editable Bezier curve"
        )

        let element = AnnotationElement(
            geometry: .linear(linear),
            style: AnnotationStyle(color: .blue, rootWidth: 2, alpha: 1)
        )
        try expect(
            AnnotationHitTester.contains(displayPoints[8], in: element, zoomScale: 4),
            "Expected curved linear hit testing to follow the rendered Bezier path"
        )

        let scene = AnnotationScene(elements: [element])
        scene.select([element.id])
        let editor = AnnotationEditor(scene: scene)
        try expect(editor.beginLinearPointEditing(), "Expected curved point editing")
        _ = editor.beginInteraction(
            at: CGPoint(x: 0, y: 40),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.updateInteraction(to: CGPoint(x: 10, y: 50), modifiers: [])
        editor.endInteraction(at: CGPoint(x: 10, y: 50), modifiers: [])
        guard case .linear(let editedCurve) = scene.element(withID: element.id)?.geometry else {
            throw SelfTestError.failure("Expected edited Bezier controls")
        }
        try expect(
            editedCurve.bezierControls[0].start == CGPoint(x: 10, y: 50),
            "Expected direct dragging of an editable Bezier control"
        )

        let degenerate = AnnotationLinearGeometry(
            points: [CGPoint(x: 7, y: 9)],
            route: .curved,
            startArrowhead: .diamond,
            endArrowhead: .bar,
            startBinding: nil,
            endBinding: nil
        )
        try expect(
            AnnotationGeometry.linearDisplayPoints(degenerate) == [CGPoint(x: 7, y: 9)]
                && AnnotationGeometry.closestLinearLocation(to: .zero, linear: degenerate) == nil,
            "Expected single-point curved paths to remain safe and deterministic"
        )
    }

    private static func testLinearClickConstructionLifecycle() throws {
        try expect(
            !ZoomCanvasView.shouldTreatLinearCreationAsDrag(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 13, y: 12)
            )
                && ZoomCanvasView.shouldTreatLinearCreationAsDrag(
                    from: CGPoint(x: 10, y: 10),
                    to: CGPoint(x: 15, y: 10)
                ),
            "Expected persistent line tools to distinguish a small click from a drag"
        )

        let controller = AnnotationController()
        controller.currentTool = .line
        controller.begin(at: CGPoint(x: 10, y: 10), tool: .line)
        controller.beginLinearConstructionFromClick(
            at: CGPoint(x: 10, y: 10),
            zoomScale: 1
        )
        try expect(
            controller.isConstructingLinearPath
                && controller.elementSnapshot.isEmpty
                && !controller.canUndo,
            "Expected a first click to remain pending outside scene history"
        )

        controller.updateLinearConstructionPreview(
            at: CGPoint(x: 50, y: 20),
            zoomScale: 1
        )
        try expect(
            controller.commitLinearConstructionPoint(
                at: CGPoint(x: 50, y: 20),
                zoomScale: 1
            ) && controller.canFinishLinearPath,
            "Expected a second click to commit a distinct path anchor"
        )
        _ = controller.commitLinearConstructionPoint(
            at: CGPoint(x: 90, y: 10),
            zoomScale: 1
        )
        guard case .linear(let pending) = controller.linearConstructionElementSnapshot?.geometry else {
            throw SelfTestError.failure("Expected pending multi-click line geometry")
        }
        try expect(
            pending.points == [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 50, y: 20),
                CGPoint(x: 90, y: 10)
            ],
            "Expected each straight-route click to append a polyline anchor"
        )
        try expect(
            controller.isLinearConstructionFinishHandle(
                at: CGPoint(x: 90, y: 10),
                zoomScale: 1
            ),
            "Expected the terminal anchor to expose a discoverable finish handle"
        )
        try expect(
            controller.finishLinearConstruction(commitPreview: false),
            "Expected a multi-point pending path to finish"
        )
        try expect(
            controller.elementSnapshot.count == 1 && controller.canUndo,
            "Expected the complete multi-click path to enter history as one element"
        )
        controller.undo()
        try expect(
            controller.elementSnapshot.isEmpty && controller.canRedo,
            "Expected one undo to remove the entire click-constructed path"
        )

        let cancelController = AnnotationController()
        cancelController.currentTool = .arrow
        cancelController.begin(at: CGPoint(x: 0, y: 0), tool: .arrow)
        cancelController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        cancelController.resolveLinearConstructionForExit()
        try expect(
            !cancelController.isConstructingLinearPath
                && cancelController.elementSnapshot.isEmpty
                && !cancelController.canUndo,
            "Expected Escape or tool exit to cancel a one-point path"
        )

        cancelController.begin(at: .zero, tool: .arrow)
        cancelController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        _ = cancelController.commitLinearConstructionPoint(
            at: CGPoint(x: 30, y: 0),
            zoomScale: 1
        )
        cancelController.cancelLinearConstruction()
        try expect(
            cancelController.elementSnapshot.isEmpty && !cancelController.canUndo,
            "Expected the explicit Cancel Path action to discard all pending anchors"
        )

        cancelController.begin(at: .zero, tool: .arrow)
        cancelController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        cancelController.updateLinearConstructionPreview(
            at: CGPoint(x: 60, y: 15),
            zoomScale: 1
        )
        try expect(
            cancelController.finishLinearConstruction(commitPreview: true),
            "Expected Return or Finish Path to commit the live preview endpoint"
        )
        guard let arrowElement = cancelController.elementSnapshot.first,
              case .linear(let arrow) = arrowElement.geometry else {
            throw SelfTestError.failure("Expected click-constructed arrow geometry")
        }
        try expect(
            arrow.startArrowhead == .none
                && arrow.endArrowhead == .arrow
                && arrow.points.last == CGPoint(x: 60, y: 15),
            "Expected the persistent Arrow tool to place its configured head at the final endpoint"
        )
        cancelController.currentTool = .select
        try expect(
            cancelController.isEditingLinearPoints
                && cancelController.selectedElementIDs == [arrowElement.id],
            "Expected switching to Select after Return to enter point editing on the new arrow"
        )

        let selectController = AnnotationController()
        selectController.currentTool = .line
        selectController.begin(at: .zero, tool: .line)
        selectController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        _ = selectController.commitLinearConstructionPoint(
            at: CGPoint(x: 20, y: 0),
            zoomScale: 1
        )
        selectController.currentTool = .select
        try expect(
            selectController.elementSnapshot.count == 1
                && selectController.isEditingLinearPoints
                && selectController.selectedElementIDs.count == 1,
            "Expected switching to Select to commit and immediately expose every path point"
        )
    }

    private static func testLinearConstructionEscapeAndToolSwitch() throws {
        let escapeController = AnnotationController()
        escapeController.currentTool = .line
        escapeController.begin(at: .zero, tool: .line)
        escapeController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        _ = escapeController.commitLinearConstructionPoint(
            at: CGPoint(x: 40, y: 0),
            zoomScale: 1
        )
        let canvas = try makeCanvas(annotationController: escapeController)
        canvas.toggleDrawingMode()
        guard let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else {
            throw SelfTestError.failure("Could not create an Escape key event")
        }
        canvas.keyDown(with: escape)
        canvas.prepareForClose()
        try expect(
            !escapeController.isConstructingLinearPath
                && escapeController.elementSnapshot.isEmpty,
            "Expected Escape to cancel an active click-to-place path and discard its anchors"
        )

        let toolSwitchController = AnnotationController()
        toolSwitchController.currentTool = .arrow
        toolSwitchController.begin(at: .zero, tool: .arrow)
        toolSwitchController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        _ = toolSwitchController.commitLinearConstructionPoint(
            at: CGPoint(x: 50, y: 10),
            zoomScale: 1
        )
        toolSwitchController.currentTool = .pen
        try expect(
            !toolSwitchController.isConstructingLinearPath
                && toolSwitchController.elementSnapshot.count == 1,
            "Expected tool switching to commit existing path anchors independently of Escape"
        )
    }

    private static func testActiveGestureExitLifecycle() throws {
        let creationTools: [AnnotationTool] = [
            .pen,
            .highlighter,
            .rectangle,
            .diamond,
            .ellipse,
            .line,
            .arrow
        ]
        for tool in creationTools {
            let controller = AnnotationController()
            controller.currentTool = tool
            controller.begin(
                at: CGPoint(x: 10, y: 10),
                tool: tool,
                timestamp: 0,
                zoomScale: 1
            )
            controller.update(
                at: CGPoint(x: 70, y: 50),
                timestamp: 0.1,
                zoomScale: 1
            )
            try expect(
                controller.resolveActiveGestureForExit(zoomScale: 1),
                "Expected exit to commit a visible \(tool) gesture"
            )
            try expect(
                controller.elementSnapshot.count == 1
                    && controller.inProgressElementSnapshot == nil
                    && !controller.isConstructingLinearPath
                    && controller.editorStateKind == .idle
                    && !controller.hasActiveDrawingGesture,
                "Expected \(tool) exit to clear every transient creation state"
            )
            controller.undo()
            try expect(
                controller.elementSnapshot.isEmpty && !controller.canUndo,
                "Expected one undo to remove the complete exited \(tool) gesture"
            )
            controller.redo()
            try expect(
                controller.elementSnapshot.count == 1,
                "Expected redo to restore the complete exited \(tool) gesture"
            )
        }

        for tool in [AnnotationTool.rectangle, .diamond, .ellipse, .line, .arrow] {
            let controller = AnnotationController()
            controller.currentTool = tool
            controller.begin(at: CGPoint(x: 20, y: 20), tool: tool)
            try expect(
                !controller.resolveActiveGestureForExit(zoomScale: 1)
                    && controller.elementSnapshot.isEmpty
                    && controller.inProgressElementSnapshot == nil
                    && controller.editorStateKind == .idle
                    && !controller.canUndo,
                "Expected exit to cancel a degenerate \(tool) gesture without history"
            )
        }

        let constructedController = AnnotationController()
        constructedController.currentTool = .line
        constructedController.begin(at: .zero, tool: .line)
        constructedController.beginLinearConstructionFromClick(
            at: .zero,
            zoomScale: 1
        )
        _ = constructedController.commitLinearConstructionPoint(
            at: CGPoint(x: 60, y: 20),
            zoomScale: 1
        )
        try expect(
            constructedController.resolveActiveGestureForExit(zoomScale: 1)
                && constructedController.elementSnapshot.count == 1
                && !constructedController.isConstructingLinearPath
                && constructedController.editorStateKind == .idle,
            "Expected exit to finalize a valid multi-click linear construction"
        )

        let degenerateConstructionController = AnnotationController()
        degenerateConstructionController.currentTool = .arrow
        degenerateConstructionController.begin(at: .zero, tool: .arrow)
        degenerateConstructionController.beginLinearConstructionFromClick(
            at: .zero,
            zoomScale: 1
        )
        try expect(
            !degenerateConstructionController.resolveActiveGestureForExit(
                zoomScale: 1
            )
                && degenerateConstructionController.elementSnapshot.isEmpty
                && !degenerateConstructionController.isConstructingLinearPath
                && degenerateConstructionController.editorStateKind == .idle,
            "Expected exit to cancel a one-anchor linear construction"
        )

        let eraserController = AnnotationController()
        eraserController.currentTool = .rectangle
        eraserController.begin(at: CGPoint(x: 10, y: 10))
        eraserController.end(at: CGPoint(x: 70, y: 70))
        eraserController.beginErasing(
            at: CGPoint(x: 10, y: 40),
            zoomScale: 1
        )
        eraserController.resolveActiveGestureForExit(zoomScale: 1)
        try expect(
            eraserController.elementSnapshot.count == 1
                && eraserController.pendingErasureElementIDsForTesting.isEmpty
                && eraserController.editorStateKind == .idle
                && !eraserController.hasActiveDrawingGesture,
            "Expected exit to cancel staged erasure without deleting content"
        )
        eraserController.undo()
        try expect(
            eraserController.elementSnapshot.isEmpty,
            "Expected eraser exit to add no history beyond the original annotation"
        )

        let selectionController = AnnotationController()
        selectionController.currentTool = .rectangle
        selectionController.begin(at: CGPoint(x: 10, y: 10))
        selectionController.end(at: CGPoint(x: 70, y: 70))
        let originalElement = selectionController.elementSnapshot[0]
        selectionController.currentTool = .select
        _ = selectionController.beginSelectionInteraction(
            at: CGPoint(x: 10, y: 40),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        selectionController.updateSelectionInteraction(
            to: CGPoint(x: 35, y: 40),
            modifiers: []
        )
        selectionController.resolveActiveGestureForExit(zoomScale: 1)
        try expect(
            selectionController.elementSnapshot[0] == originalElement
                && selectionController.editorStateKind == .idle
                && !selectionController.hasActiveDrawingGesture,
            "Expected exit to cancel an active editor drag and restore its transaction"
        )

        func makeActiveCanvas(
            tool: AnnotationTool
        ) throws -> (AnnotationController, ZoomCanvasView) {
            let controller = AnnotationController()
            let canvas = try makeCanvas(annotationController: controller)
            canvas.interactionMode = .drawOnly
            controller.currentTool = tool
            controller.begin(
                at: CGPoint(x: 12, y: 16),
                tool: tool,
                timestamp: 0,
                zoomScale: 1
            )
            controller.update(
                at: CGPoint(x: 84, y: 58),
                timestamp: 0.1,
                zoomScale: 1
            )
            return (controller, canvas)
        }

        let (toggleController, toggleCanvas) = try makeActiveCanvas(tool: .pen)
        toggleCanvas.toggleDrawingMode()
        try expect(
            toggleController.elementSnapshot.count == 1
                && !toggleController.hasActiveDrawingGesture,
            "Expected the external drawing toggle to resolve an active pen"
        )
        toggleCanvas.prepareForClose()

        let (typingController, typingCanvas) = try makeActiveCanvas(
            tool: .highlighter
        )
        typingCanvas.interactionMode = .typing
        try expect(
            typingController.elementSnapshot.count == 1
                && !typingController.hasActiveDrawingGesture,
            "Expected typing entry to resolve an active highlighter"
        )
        typingCanvas.prepareForClose()

        let escapeController = AnnotationController()
        let escapeCanvas = try makeCanvas(annotationController: escapeController)
        escapeCanvas.interactionMode = .liveZoom
        escapeCanvas.toggleDrawingMode()
        escapeController.currentTool = .rectangle
        escapeController.begin(
            at: CGPoint(x: 12, y: 16),
            tool: .rectangle,
            timestamp: 0,
            zoomScale: 1
        )
        escapeController.update(
            at: CGPoint(x: 84, y: 58),
            timestamp: 0.1,
            zoomScale: 1
        )
        guard let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else {
            throw SelfTestError.failure("Could not create an active-gesture Escape event")
        }
        escapeCanvas.keyDown(with: escape)
        try expect(
            escapeController.elementSnapshot.count == 1
                && !escapeController.hasActiveDrawingGesture,
            "Expected Escape to resolve an active shape before leaving drawing"
        )
        escapeCanvas.prepareForClose()

        let (rightClickController, rightClickCanvas) = try makeActiveCanvas(
            tool: .line
        )
        guard let rightClick = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: CGPoint(x: 84, y: 58),
            modifierFlags: [],
            timestamp: 0.2,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) else {
            throw SelfTestError.failure("Could not create an active-gesture right click")
        }
        rightClickCanvas.rightMouseDown(with: rightClick)
        try expect(
            rightClickController.elementSnapshot.count == 1
                && !rightClickController.hasActiveDrawingGesture,
            "Expected right click to resolve an active dragged line"
        )
        rightClickCanvas.prepareForClose()

        let (closeController, closeCanvas) = try makeActiveCanvas(tool: .ellipse)
        closeCanvas.prepareForClose()
        try expect(
            closeController.elementSnapshot.count == 1
                && !closeController.hasActiveDrawingGesture,
            "Expected overlay close to resolve an active shape"
        )
    }

    private static func testFixedStrokeVariablePressureConversion() throws {
        let controller = AnnotationController()
        controller.currentStyle.sloppiness = .architect
        controller.currentStyle.smoothingEnabled = false
        controller.currentStyle.strokeWidth = 14
        controller.currentStyle.pressureMode = .fixed
        controller.begin(
            at: CGPoint(x: 12, y: 40),
            tool: .pen,
            timestamp: 0,
            zoomScale: 1
        )
        controller.update(
            at: CGPoint(x: 24, y: 40),
            timestamp: 0.2,
            zoomScale: 1
        )
        controller.update(
            at: CGPoint(x: 96, y: 40),
            timestamp: 0.24,
            zoomScale: 1
        )
        controller.end(
            at: CGPoint(x: 116, y: 40),
            timestamp: 0.5,
            zoomScale: 1
        )
        controller.currentTool = .select
        controller.selectAll()

        guard let fixedElement = controller.selectedElementSnapshot.first,
              case .freehand(let fixedFreehand) = fixedElement.geometry else {
            throw SelfTestError.failure("Expected a selected fixed freehand stroke")
        }
        try expect(
            fixedElement.style.pressureMode == .fixed
                && fixedFreehand.samples.allSatisfy {
                    $0.pressure == nil && $0.timestamp != nil
                },
            "Expected fixed strokes to retain timing metadata without claiming pressure"
        )
        let renderer = AnnotationRenderer()
        let fixedPixels = try renderPixels(
            elements: [fixedElement],
            renderer: renderer,
            width: 128,
            height: 80
        )

        controller.setPressureMode(.simulated)
        guard let variableElement = controller.selectedElementSnapshot.first,
              case .freehand(let variableFreehand) = variableElement.geometry else {
            throw SelfTestError.failure("Expected a selected variable freehand stroke")
        }
        let variablePressures = variableFreehand.samples.compactMap(\.pressure)
        let variablePixels = try renderPixels(
            elements: [variableElement],
            renderer: renderer,
            width: 128,
            height: 80
        )
        let variableSpans = stride(from: 16, through: 112, by: 4).map {
            paintedVerticalSpan(
                variablePixels,
                width: 128,
                height: 80,
                x: $0
            )
        }
        try expect(
            variableElement.style.pressureMode == .simulated
                && DrawingToolbarState(annotationController: controller)
                    .pressureOption == .value(.variable)
                && variablePressures.count == variableFreehand.samples.count
                && (variablePressures.max() ?? 0)
                    - (variablePressures.min() ?? 0) > 0.15
                && (variableSpans.max() ?? 0) - (variableSpans.min() ?? 0) >= 3
                && pixelDifferenceCount(fixedPixels, variablePixels) > 0,
            "Expected fixed-to-variable conversion to backfill pressure and visibly vary width"
        )

        controller.undo()
        guard let undoneElement = controller.selectedElementSnapshot.first,
              case .freehand(let undoneFreehand) = undoneElement.geometry else {
            throw SelfTestError.failure("Expected undo to restore the fixed stroke")
        }
        let undonePixels = try renderPixels(
            elements: [undoneElement],
            renderer: renderer,
            width: 128,
            height: 80
        )
        try expect(
            undoneElement.style.pressureMode == .fixed
                && undoneFreehand.samples == fixedFreehand.samples
                && DrawingToolbarState(annotationController: controller)
                    .pressureOption == .value(.constant)
                && undonePixels == fixedPixels,
            "Expected one undo to restore pressure metadata, rendering, and inspector state"
        )

        controller.redo()
        guard let redoneElement = controller.selectedElementSnapshot.first,
              case .freehand(let redoneFreehand) = redoneElement.geometry else {
            throw SelfTestError.failure("Expected redo to restore the variable stroke")
        }
        try expect(
            redoneElement.style.pressureMode == .simulated
                && redoneFreehand.samples == variableFreehand.samples
                && DrawingToolbarState(annotationController: controller)
                    .pressureOption == .value(.variable),
            "Expected one redo to restore pressure samples and inspector state"
        )

        let highlighterController = AnnotationController()
        highlighterController.currentTool = .highlighter
        highlighterController.currentStyle.pressureMode = .fixed
        highlighterController.begin(
            at: CGPoint(x: 10, y: 20),
            tool: .highlighter,
            timestamp: 0,
            zoomScale: 1
        )
        highlighterController.update(
            at: CGPoint(x: 50, y: 20),
            timestamp: 0.08,
            zoomScale: 1
        )
        highlighterController.end(
            at: CGPoint(x: 100, y: 20),
            timestamp: 0.2,
            zoomScale: 1
        )
        highlighterController.currentTool = .select
        highlighterController.selectAll()
        highlighterController.setPressureMode(.tablet)
        guard let highlighter = highlighterController.selectedElementSnapshot.first,
              case .freehand(let highlighterFreehand) = highlighter.geometry else {
            throw SelfTestError.failure("Expected a selected highlighter stroke")
        }
        try expect(
            highlighter.style.pressureMode == .fixed
                && highlighterFreehand.samples.allSatisfy { $0.pressure == nil }
                && DrawingToolbarState(annotationController: highlighterController)
                    .pressureOption == .value(.constant)
                && !DrawingToolbarState(annotationController: highlighterController)
                    .visibleInspectorSections.contains(.pressure),
            "Expected Highlighter selection to reject hidden variable-pressure mutations"
        )

        let legacySamples = [
            AnnotationPointSample(
                location: CGPoint(x: 12, y: 34),
                pressure: nil
            ),
            AnnotationPointSample(
                location: CGPoint(x: 36, y: 34),
                pressure: nil
            ),
            AnnotationPointSample(
                location: CGPoint(x: 68, y: 34),
                pressure: nil
            ),
            AnnotationPointSample(
                location: CGPoint(x: 116, y: 34),
                pressure: nil
            )
        ]
        let firstLegacyBackfill = AnnotationPressureBackfill.simulatedSamples(
            from: legacySamples
        )
        let repeatedLegacyBackfill = AnnotationPressureBackfill.simulatedSamples(
            from: legacySamples
        )
        let legacyPressures = firstLegacyBackfill.compactMap(\.pressure)
        try expect(
            firstLegacyBackfill == repeatedLegacyBackfill
                && firstLegacyBackfill.allSatisfy { $0.timestamp == nil }
                && legacyPressures.count == legacySamples.count
                && (legacyPressures.max() ?? 0)
                    - (legacyPressures.min() ?? 0) > 0.15,
            "Expected timestamp-less legacy strokes to use a stable distance profile"
        )

        var legacyStyle = AnnotationStyle(
            color: .blue,
            rootWidth: 14,
            alpha: 1
        )
        legacyStyle.sloppiness = .architect
        legacyStyle.smoothingEnabled = false
        legacyStyle.pressureMode = .fixed
        let legacyID = AnnotationElementID()
        let fixedLegacyElement = AnnotationElement(
            id: legacyID,
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: legacySamples,
                    isHighlighter: false
                )
            ),
            style: legacyStyle
        )
        legacyStyle.pressureMode = .simulated
        let variableLegacyElement = AnnotationElement(
            id: legacyID,
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: firstLegacyBackfill,
                    isHighlighter: false
                )
            ),
            style: legacyStyle
        )
        let fixedLegacyPixels = try renderPixels(
            elements: [fixedLegacyElement],
            renderer: renderer,
            width: 128,
            height: 72
        )
        let variableLegacyPixels = try renderPixels(
            elements: [variableLegacyElement],
            renderer: renderer,
            width: 128,
            height: 72
        )
        try expect(
            pixelDifferenceCount(fixedLegacyPixels, variableLegacyPixels) > 0
                && paintedVerticalSpan(
                    variableLegacyPixels,
                    width: 128,
                    height: 72,
                    x: 68
                ) > paintedVerticalSpan(
                    variableLegacyPixels,
                    width: 128,
                    height: 72,
                    x: 12
                ),
            "Expected the legacy fallback profile to produce visible variable width"
        )
    }

    private static func testLinearDragThresholdLatching() throws {
        let origin = CGPoint(x: 20, y: 20)
        let exceeded = ZoomCanvasView.linearDragThresholdExceeded(
            previouslyExceeded: false,
            from: origin,
            to: CGPoint(x: 30, y: 20)
        )
        let remainedExceeded = ZoomCanvasView.linearDragThresholdExceeded(
            previouslyExceeded: exceeded,
            from: origin,
            to: CGPoint(x: 21, y: 20)
        )
        try expect(
            exceeded && remainedExceeded,
            "Expected a line or arrow drag to stay classified as a drag after returning near its origin"
        )
    }

    private static func testLinearConstructionRoutesAndBindings() throws {
        let elbowController = AnnotationController()
        elbowController.currentTool = .line
        elbowController.setLinearRoute(.elbow)
        elbowController.begin(at: .zero, tool: .line)
        elbowController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        _ = elbowController.commitLinearConstructionPoint(
            at: CGPoint(x: 40, y: 30),
            zoomScale: 1
        )
        _ = elbowController.commitLinearConstructionPoint(
            at: CGPoint(x: 80, y: 60),
            zoomScale: 1
        )
        _ = elbowController.finishLinearConstruction(commitPreview: false)
        guard case .linear(let elbow) = elbowController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected manual elbow construction geometry")
        }
        try expect(
            !elbow.isElbowAutoRouted
                && elbow.points == [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 40, y: 0),
                    CGPoint(x: 40, y: 30),
                    CGPoint(x: 80, y: 30),
                    CGPoint(x: 80, y: 60)
                ]
                && zip(elbow.points, elbow.points.dropFirst()).allSatisfy {
                    approximatelyEqual($0.x, $1.x) || approximatelyEqual($0.y, $1.y)
                }
                && elbow.points.last == CGPoint(x: 80, y: 60),
            "Expected elbow clicks to preserve manual orthogonal waypoints without auto-routing"
        )

        let curvedController = AnnotationController()
        curvedController.currentTool = .line
        curvedController.setLinearRoute(.curved)
        curvedController.begin(at: .zero, tool: .line)
        curvedController.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        _ = curvedController.commitLinearConstructionPoint(
            at: CGPoint(x: 40, y: 30),
            zoomScale: 1
        )
        _ = curvedController.commitLinearConstructionPoint(
            at: CGPoint(x: 90, y: 0),
            zoomScale: 1
        )
        _ = curvedController.finishLinearConstruction(commitPreview: false)
        guard case .linear(let curved) = curvedController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected curved click construction geometry")
        }
        try expect(
            curved.bezierControls.count == curved.points.count - 1
                && curved.bezierControls == AnnotationGeometry.bezierControls(for: curved),
            "Expected curved construction to commit explicit editable Bezier controls"
        )

        let bindingController = AnnotationController()
        bindingController.currentTool = .rectangle
        bindingController.begin(at: CGPoint(x: 40, y: 40), tool: .rectangle)
        bindingController.end(at: CGPoint(x: 100, y: 100))
        bindingController.currentTool = .arrow
        bindingController.begin(at: CGPoint(x: 40, y: 70), tool: .arrow)
        bindingController.beginLinearConstructionFromClick(
            at: CGPoint(x: 40, y: 70),
            zoomScale: 1
        )
        _ = bindingController.commitLinearConstructionPoint(
            at: CGPoint(x: 100, y: 70),
            zoomScale: 1
        )
        _ = bindingController.finishLinearConstruction(commitPreview: false)
        guard bindingController.elementSnapshot.count == 2,
              case .linear(let bound) = bindingController.elementSnapshot[1].geometry else {
            throw SelfTestError.failure("Expected a shape-bound click-constructed arrow")
        }
        try expect(
            bound.startBinding?.targetElementID == bindingController.elementSnapshot[0].id
                && bound.endBinding?.targetElementID == bindingController.elementSnapshot[0].id,
            "Expected final click-construction endpoints to evaluate shape binding"
        )
        bindingController.currentTool = .select
        try expect(
            DrawingToolbarState(annotationController: bindingController)
                .canUnbindLinearEndpoints,
            "Expected Unbind Ends to enable only for a selected bound connector"
        )
        bindingController.undo()
        try expect(
            bindingController.elementSnapshot.count == 1,
            "Expected the bound multi-click arrow to remain a single undo step"
        )
    }

    private static func testCurvedTangentEditingAndControlPreservation() throws {
        let curve = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 0, y: 0),
                        CGPoint(x: 50, y: 0),
                        CGPoint(x: 100, y: 0)
                    ],
                    route: .curved,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil,
                    bezierControls: [
                        AnnotationBezierControl(
                            start: CGPoint(x: 10, y: 0),
                            end: CGPoint(x: 40, y: 0)
                        ),
                        AnnotationBezierControl(
                            start: CGPoint(x: 60, y: 0),
                            end: CGPoint(x: 90, y: 0)
                        )
                    ]
                )
            ),
            style: .default
        )
        let scene = AnnotationScene(elements: [curve])
        scene.select([curve.id])
        let editor = AnnotationEditor(scene: scene)
        try expect(editor.beginLinearPointEditing(), "Expected curved tangent point editing")

        _ = editor.beginInteraction(
            at: CGPoint(x: 40, y: 0),
            zoomScale: 1,
            modifiers: [.command],
            clickCount: 1
        )
        editor.updateInteraction(
            to: CGPoint(x: 40, y: 20),
            modifiers: [.command]
        )
        editor.endInteraction(
            at: CGPoint(x: 40, y: 20),
            modifiers: [.command]
        )
        guard case .linear(let mirrored) = scene.element(withID: curve.id)?.geometry else {
            throw SelfTestError.failure("Expected mirrored curved controls")
        }
        try expect(
            mirrored.bezierControls[0].end == CGPoint(x: 40, y: 20)
                && mirrored.bezierControls[1].start == CGPoint(x: 60, y: -20),
            "Expected Command-drag to mirror the opposite tangent with equal length"
        )

        _ = editor.beginInteraction(
            at: CGPoint(x: 40, y: 20),
            zoomScale: 1,
            modifiers: [.option],
            clickCount: 1
        )
        editor.updateInteraction(
            to: CGPoint(x: 35, y: 30),
            modifiers: [.option]
        )
        editor.endInteraction(
            at: CGPoint(x: 35, y: 30),
            modifiers: [.option]
        )
        guard case .linear(let broken) = scene.element(withID: curve.id)?.geometry else {
            throw SelfTestError.failure("Expected independently edited curved controls")
        }
        try expect(
            broken.bezierControls[0].end == CGPoint(x: 35, y: 30)
                && broken.bezierControls[1].start == CGPoint(x: 60, y: -20),
            "Expected Option-drag to break tangents while retaining the opposite explicit control"
        )

        let reduced = AnnotationGeometry.removingLinearPoints([1], from: broken)
        try expect(
            reduced.points == [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
                && reduced.bezierControls == [
                    AnnotationBezierControl(
                        start: broken.bezierControls[0].start,
                        end: broken.bezierControls[1].end
                    )
                ],
            "Expected point removal to preserve explicit controls on the surviving curve"
        )
    }

    private static func testElbowRoutingAndIntersections() throws {
        let obstacle = ArrowRouter.Obstacle(
            elementID: AnnotationElementID(),
            bounds: CGRect(x: 40, y: -10, width: 20, height: 20)
        )
        let first = ArrowRouter.route(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            startDirection: .trailing,
            endDirection: .leading,
            obstacles: [obstacle],
            clearance: 10
        )
        let second = ArrowRouter.route(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            startDirection: .trailing,
            endDirection: .leading,
            obstacles: [obstacle],
            clearance: 10
        )
        try expect(first == second, "Expected elbow routing to remain stable for identical inputs")
        try expect(
            first.count >= 4
                && first[1].x > first[0].x
                && first[first.count - 2].x < first[first.count - 1].x,
            "Expected stable requested directions at both elbow endpoints"
        )
        try expect(
            zip(first, first.dropFirst()).allSatisfy { start, end in
                approximatelyEqual(start.x, end.x) || approximatelyEqual(start.y, end.y)
            },
            "Expected elbow routes to contain only orthogonal segments"
        )
        try expect(
            zip(first, first.dropFirst()).allSatisfy { start, end in
                let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                return !obstacle.bounds.contains(midpoint)
            },
            "Expected practical elbow routing to avoid the supplied obstacle"
        )
        try expect(
            ArrowRouter.route(
                from: CGPoint(x: 5, y: 5),
                to: CGPoint(x: 5, y: 5),
                startDirection: .automatic,
                endDirection: .automatic,
                obstacles: [],
                clearance: 10
            ) == [CGPoint(x: 5, y: 5)],
            "Expected degenerate elbow endpoints to produce one safe point"
        )

        let crossing = AnnotationGeometry.segmentIntersection(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 20, y: 20),
            with: CGPoint(x: 0, y: 20),
            to: CGPoint(x: 20, y: 0)
        )
        try expect(
            crossing.map { approximatelyEqual($0, CGPoint(x: 10, y: 10)) } == true,
            "Expected robust segment intersection for crossing lines"
        )
        try expect(
            AnnotationGeometry.segmentIntersection(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 20, y: 0),
                with: CGPoint(x: 0, y: 5),
                to: CGPoint(x: 20, y: 5)
            ) == nil,
            "Expected parallel separated segments not to intersect"
        )
    }

    private static func testElbowRoutingComplexityAndRefreshBatching() throws {
        let obstacles = (0..<24).map { index in
            ArrowRouter.Obstacle(
                elementID: AnnotationElementID(),
                bounds: CGRect(
                    x: 40 + CGFloat(index % 8) * 35,
                    y: -70 + CGFloat(index / 8) * 55,
                    width: 14,
                    height: 18
                )
            )
        }
        var diagnostics = ArrowRouter.Diagnostics()
        let route = ArrowRouter.route(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 360, y: 0),
            startDirection: .trailing,
            endDirection: .leading,
            obstacles: obstacles,
            clearance: 8,
            diagnostics: { diagnostics = $0 }
        )
        try expect(!route.isEmpty, "Expected a route through the sparse obstacle grid")
        try expect(
            diagnostics.nodeCount > 0
                && diagnostics.directedEdgeCount <= diagnostics.nodeCount * 4
                && diagnostics.settledStateCount <= diagnostics.nodeCount * 3,
            "Expected adjacent grid edges and bounded priority-queue search, got \(diagnostics)"
        )

        var style = AnnotationStyle.default
        style.fillStyle = .solid
        let firstShape = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 40, y: -10), CGPoint(x: 60, y: 10)],
            style: style
        )
        let secondShape = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 70, y: 30), CGPoint(x: 90, y: 50)],
            style: style
        )
        let nearArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0)],
                    route: .elbow,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        let farArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 500, y: 500), CGPoint(x: 620, y: 500)],
                    route: .elbow,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        let scene = AnnotationScene(elements: [firstShape, secondShape, nearArrow, farArrow])
        let editor = AnnotationEditor(scene: scene)
        scene.select([firstShape.id, secondShape.id])
        var routedIDs: [AnnotationElementID] = []
        scene.onElbowRoute = { routedIDs.append($0) }

        _ = editor.beginInteraction(
            at: CGPoint(x: 50, y: 0),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.updateInteraction(to: CGPoint(x: 55, y: 5), modifiers: [])
        editor.endInteraction(at: CGPoint(x: 55, y: 5), modifiers: [])

        try expect(
            routedIDs == [nearArrow.id],
            "Expected one batched refresh for only the affected elbow arrow"
        )

        routedIDs.removeAll()
        scene.updateElement(withID: firstShape.id) { element in
            element.style.fillStyle = .crossHatch
            element.style.strokeColor = .palette(.blue)
            element.style.opacity = 0.65
            element.style.strokePattern = .dashed
        }
        scene.beginTransaction()
        scene.updateElement(withID: nearArrow.id) { element in
            element.style.opacity = 0.7
        }
        scene.updateElement(withID: nearArrow.id) { element in
            element.style.opacity = 0.4
        }
        scene.commitTransaction()
        scene.updateElement(withID: nearArrow.id) { element in
            guard case .linear(var linear) = element.geometry else { return }
            linear.startArrowhead = .circleOutline
            linear.endArrowhead = .diamond
            element.geometry = .linear(linear)
        }
        try expect(
            routedIDs.isEmpty,
            "Expected color, opacity, pattern, fill, and arrowhead-only edits to avoid router work"
        )

        scene.updateElement(withID: firstShape.id) { element in
            element.style.strokeWidth = 9
        }
        try expect(
            routedIDs == [nearArrow.id],
            "Expected obstacle stroke-width changes to reroute nearby auto-routed arrows"
        )

        routedIDs.removeAll()
        scene.updateElement(withID: firstShape.id) { element in
            element.style.sloppiness = .cartoonist
        }
        try expect(
            routedIDs == [nearArrow.id],
            "Expected obstacle sloppiness changes to reroute nearby auto-routed arrows"
        )

        routedIDs.removeAll()
        scene.updateElement(withID: nearArrow.id) { element in
            element.style.strokeWidth = 8
        }
        try expect(
            routedIDs == [nearArrow.id],
            "Expected auto-routed arrow stroke-width changes to refresh routing clearance"
        )

        routedIDs.removeAll()
        scene.updateElement(withID: nearArrow.id) { element in
            element.style.sloppiness = .architect
        }
        try expect(
            routedIDs == [nearArrow.id],
            "Expected auto-routed arrow sloppiness changes to refresh its route"
        )

        routedIDs.removeAll()
        scene.updateElement(withID: firstShape.id) { element in
            guard case .shape(var shape) = element.geometry else { return }
            shape.start.x += 4
            shape.end.x += 4
            element.geometry = .shape(shape)
        }
        try expect(
            routedIDs == [nearArrow.id],
            "Expected an obstacle geometry change to invoke the elbow router"
        )
    }

    private static func testMultiArrowMutationBatching() throws {
        let firstTarget = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)],
            style: .default
        )
        let secondTarget = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 10, y: 70), CGPoint(x: 40, y: 100)],
            style: .default
        )
        let firstArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 40, y: 25), CGPoint(x: 140, y: 25)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: AnnotationBinding(
                        targetElementID: firstTarget.id,
                        side: .trailing
                    ),
                    endBinding: nil
                )
            ),
            style: .default
        )
        let secondArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 40, y: 85), CGPoint(x: 140, y: 85)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: AnnotationBinding(
                        targetElementID: secondTarget.id,
                        side: .trailing
                    ),
                    endBinding: nil
                )
            ),
            style: .default
        )
        let scene = AnnotationScene(
            elements: [firstTarget, secondTarget, firstArrow, secondArrow]
        )
        let editor = AnnotationEditor(scene: scene)
        let arrowIDs: Set<AnnotationElementID> = [firstArrow.id, secondArrow.id]
        scene.select(arrowIDs)

        var notificationCount = 0
        var routedIDs: [AnnotationElementID] = []
        scene.onChange = { notificationCount += 1 }
        scene.onElbowRoute = { routedIDs.append($0) }

        editor.setLinearRoute(.elbow)
        try expect(
            notificationCount == 1
                && routedIDs.count == arrowIDs.count
                && Set(routedIDs) == arrowIDs,
            "Expected one scene notification and one route per arrow for a batched route edit"
        )

        notificationCount = 0
        routedIDs.removeAll()
        editor.setLinearArrowheads(start: .circleOutline, end: .diamond)
        try expect(
            notificationCount == 1 && routedIDs.isEmpty,
            "Expected combined arrowhead edits to use one scene pass without rerouting"
        )

        notificationCount = 0
        editor.setLinearStartArrowhead(.bar)
        try expect(
            notificationCount == 1 && routedIDs.isEmpty,
            "Expected start-arrowhead edits to use one scene notification"
        )

        notificationCount = 0
        editor.setLinearEndArrowhead(.triangleOutline)
        try expect(
            notificationCount == 1 && routedIDs.isEmpty,
            "Expected end-arrowhead edits to use one scene notification"
        )

        notificationCount = 0
        routedIDs.removeAll()
        editor.unbindLinearEndpoints()
        try expect(
            notificationCount == 1
                && routedIDs.count == arrowIDs.count
                && Set(routedIDs) == arrowIDs,
            "Expected batched endpoint unbinding to notify once and reroute each arrow once"
        )
        try expect(
            arrowIDs.allSatisfy { elementID in
                guard case .linear(let linear) = scene.element(withID: elementID)?.geometry else {
                    return false
                }
                return linear.startBinding == nil && linear.endBinding == nil
            },
            "Expected endpoint unbinding to update every selected arrow"
        )
    }

    private static func testArrowheadFamiliesAndScaling() throws {
        let allHeads = DrawingInspectorControlMapping.arrowheads
        for size in AnnotationArrowheadSize.allCases {
            for arrowhead in allHeads {
                let path = AnnotationGeometry.arrowheadPath(
                    arrowhead,
                    tip: CGPoint(x: 40, y: 40),
                    adjacent: CGPoint(x: 10, y: 40),
                    strokeWidth: 3,
                    size: size
                )
                if arrowhead == .none {
                    try expect(
                        path == nil,
                        "Expected the none arrowhead to produce no geometry"
                    )
                } else {
                    try expect(
                        path != nil && !path!.boundingBoxOfPath.isNull,
                        "Expected \(size) \(arrowhead) arrowhead geometry"
                    )
                }
            }
        }

        let thin = AnnotationGeometry.arrowheadMetrics(strokeWidth: 0.5)
        let thick = AnnotationGeometry.arrowheadMetrics(strokeWidth: 8)
        let medium = AnnotationGeometry.arrowheadMetrics(
            strokeWidth: 3,
            size: .medium
        )
        let large = AnnotationGeometry.arrowheadMetrics(
            strokeWidth: 3,
            size: .large
        )
        try expect(
            thin.length >= 23
                && thin.halfWidth >= 13.5
                && thick.length > thin.length
                && thick.halfWidth > thin.halfWidth
                && abs(medium.length / AnnotationGeometry.arrowheadMetrics(
                    strokeWidth: 3,
                    size: .small
                ).length - 1.35) < 0.001
                && abs(large.length / medium.length - 1.75 / 1.35) < 0.001,
            "Expected arrowheads to scale by stroke width and the exact S/M/L factors"
        )

        let rasterTargets: [
            (size: AnnotationArrowheadSize, width: CGFloat, height: CGFloat)
        ] = [
            (.small, 22, 26),
            (.medium, 30, 35),
            (.large, 39, 46)
        ]
        for target in rasterTargets {
            let pixels = try renderArrowheadPixels(
                .arrow,
                size: target.size,
                strokeWidth: 3
            )
            guard let bounds = paintedBounds(
                pixels,
                width: 128,
                height: 128
            ) else {
                throw SelfTestError.failure(
                    "Expected a rasterized \(target.size) open arrowhead"
                )
            }
            try expect(
                bounds.width >= target.width
                    && bounds.height >= target.height
                    && bounds.minX > 1
                    && bounds.minY > 1
                    && bounds.maxX < 126
                    && bounds.maxY < 126,
                "Expected \(target.size) open arrow raster at least "
                    + "\(target.width)x\(target.height) without clipping, got "
                    + "\(bounds.width)x\(bounds.height) in \(bounds)"
            )
        }

        for size in AnnotationArrowheadSize.allCases {
            for arrowhead in allHeads where arrowhead != .none {
                let pixels = try renderArrowheadPixels(
                    arrowhead,
                    size: size,
                    strokeWidth: 3
                )
                guard let bounds = paintedBounds(
                    pixels,
                    width: 128,
                    height: 128
                ) else {
                    throw SelfTestError.failure(
                        "Expected rasterized \(size) \(arrowhead) geometry"
                    )
                }
                try expect(
                    bounds.minX > 1
                        && bounds.minY > 1
                        && bounds.maxX < 126
                        && bounds.maxY < 126,
                    "Expected \(size) \(arrowhead) raster to avoid clipping: \(bounds)"
                )
            }
        }

        let line = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 80)],
                    route: .straight,
                    startArrowhead: .diamond,
                    endArrowhead: .circle,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: AnnotationStyle(color: .green, rootWidth: 8, alpha: 1)
        )
        let bounds = AnnotationGeometry.localBounds(of: line)
        guard case .linear(let linearGeometry) = line.geometry else {
            throw SelfTestError.failure("Expected arrowhead test line")
        }
        let shaftBounds = AnnotationGeometry.linearPath(linearGeometry).boundingBoxOfPath
        try expect(
            bounds.width > shaftBounds.width || bounds.height > shaftBounds.height,
            "Expected independently configured start and end arrowheads in path bounds"
        )

        let insetLinear = AnnotationLinearGeometry(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            route: .straight,
            startArrowhead: .circleOutline,
            endArrowhead: .triangleOutline,
            startBinding: nil,
            endBinding: nil
        )
        let insetShaft = AnnotationGeometry.linearShaftGeometry(
            insetLinear,
            strokeWidth: 5
        )
        try expect(
            insetShaft.points[0].x > insetLinear.points[0].x
                && insetShaft.points[1].x < insetLinear.points[1].x,
            "Expected outlined endpoint shapes to trim the shaft instead of drawing through them"
        )

        var curved = insetLinear
        curved.route = .curved
        curved.points = [
            CGPoint(x: 0, y: 20),
            CGPoint(x: 50, y: 70),
            CGPoint(x: 100, y: 20)
        ]
        curved.bezierControls = AnnotationGeometry.bezierControls(for: curved)
        let originalControls = curved.bezierControls
        let curvedShaft = AnnotationGeometry.linearShaftGeometry(curved, strokeWidth: 5)
        try expect(
            curvedShaft.points.first != curved.points.first
                && curvedShaft.points.last != curved.points.last
                && curvedShaft.bezierControls.first?.start
                    != originalControls.first?.start
                && curvedShaft.bezierControls.last?.end
                    != originalControls.last?.end,
            "Expected curved shaft trimming to preserve endpoint tangent attachment"
        )

        let short = AnnotationLinearGeometry(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 18, y: 10)],
            route: .straight,
            startArrowhead: .diamondOutline,
            endArrowhead: .diamondOutline,
            startBinding: nil,
            endBinding: nil
        )
        let shortShaft = AnnotationGeometry.linearShaftGeometry(short, strokeWidth: 8)
        try expect(
            shortShaft.points[0].x <= shortShaft.points[1].x,
            "Expected arrowhead insets to clamp before reversing a short shaft"
        )

        let insetHeads: [AnnotationArrowhead] = [
            .triangleOutline,
            .triangle,
            .circleOutline,
            .circle,
            .diamondOutline,
            .diamond,
            .oneOrMany,
            .zeroOrOne,
            .zeroOrMany
        ]
        for route in [
            AnnotationLinearRoute.straight,
            .curved,
            .elbow
        ] {
            for head in insetHeads {
                var shortEndpoints = AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 10, y: 20),
                        CGPoint(x: 13, y: 21),
                        CGPoint(x: 86, y: 62),
                        CGPoint(x: 90, y: 64)
                    ],
                    route: route,
                    startArrowhead: head,
                    endArrowhead: head,
                    startBinding: nil,
                    endBinding: nil,
                    isElbowAutoRouted: false
                )
                if route == .curved {
                    shortEndpoints.bezierControls =
                        AnnotationGeometry.bezierControls(for: shortEndpoints)
                }
                let shaft = AnnotationGeometry.linearShaftGeometry(
                    shortEndpoints,
                    strokeWidth: 8
                )
                let originalStartOffset = CGPoint(
                    x: shortEndpoints.points[1].x - shortEndpoints.points[0].x,
                    y: shortEndpoints.points[1].y - shortEndpoints.points[0].y
                )
                let trimmedStartOffset = CGPoint(
                    x: shaft.points[1].x - shaft.points[0].x,
                    y: shaft.points[1].y - shaft.points[0].y
                )
                let originalEndOffset = CGPoint(
                    x: shortEndpoints.points[shortEndpoints.points.count - 2].x
                        - shortEndpoints.points[shortEndpoints.points.count - 1].x,
                    y: shortEndpoints.points[shortEndpoints.points.count - 2].y
                        - shortEndpoints.points[shortEndpoints.points.count - 1].y
                )
                let trimmedEndOffset = CGPoint(
                    x: shaft.points[shaft.points.count - 2].x
                        - shaft.points[shaft.points.count - 1].x,
                    y: shaft.points[shaft.points.count - 2].y
                        - shaft.points[shaft.points.count - 1].y
                )
                let startDot = originalStartOffset.x * trimmedStartOffset.x
                    + originalStartOffset.y * trimmedStartOffset.y
                let endDot = originalEndOffset.x * trimmedEndOffset.x
                    + originalEndOffset.y * trimmedEndOffset.y
                try expect(
                    startDot >= -0.000_001 && endDot >= -0.000_001,
                    "Expected short \(route) endpoint segments to avoid reversing for \(head)"
                )
            }
        }

        for route in [
            AnnotationLinearRoute.straight,
            .curved,
            .elbow
        ] {
            for size in AnnotationArrowheadSize.allCases {
                for head in allHeads {
                    var linear = AnnotationLinearGeometry(
                        points: [
                            CGPoint(x: 20, y: 30),
                            CGPoint(x: 70, y: 70),
                            CGPoint(x: 130, y: 34)
                        ],
                        route: route,
                        startArrowhead: head,
                        endArrowhead: head,
                        arrowheadSize: size,
                        startBinding: nil,
                        endBinding: nil,
                        isElbowAutoRouted: false
                    )
                    if route == .curved {
                        linear.bezierControls =
                            AnnotationGeometry.bezierControls(for: linear)
                    }
                    let shaft = AnnotationGeometry.linearShaftGeometry(
                        linear,
                        strokeWidth: 3
                    )
                    let element = AnnotationElement(
                        geometry: .linear(linear),
                        style: AnnotationStyle(
                            color: .blue,
                            rootWidth: 3,
                            alpha: 1
                        )
                    )
                    let bounds = AnnotationGeometry.localBounds(of: element)
                    let startPath = AnnotationGeometry.arrowheadPath(
                        head,
                        tip: linear.points[0],
                        adjacent: AnnotationGeometry.endpointAdjacentPoint(
                            in: linear,
                            atStart: true
                        ) ?? linear.points[1],
                        strokeWidth: 3,
                        size: size
                    )
                    let endPath = AnnotationGeometry.arrowheadPath(
                        head,
                        tip: linear.points.last!,
                        adjacent: AnnotationGeometry.endpointAdjacentPoint(
                            in: linear,
                            atStart: false
                        ) ?? linear.points[linear.points.count - 2],
                        strokeWidth: 3,
                        size: size
                    )
                    try expect(
                        shaft.points.count == linear.points.count
                            && (startPath == nil
                                || bounds.contains(
                                    startPath!.boundingBoxOfPath
                                ))
                            && (endPath == nil
                                || bounds.contains(
                                    endPath!.boundingBoxOfPath
                                )),
                        "Expected \(head) \(size) heads, shaft trim, and bounds for \(route)"
                    )
                }
            }
        }

        let editController = AnnotationController()
        editController.currentTool = .arrow
        editController.begin(at: CGPoint(x: 20, y: 20), tool: .arrow)
        editController.end(at: CGPoint(x: 120, y: 70))
        editController.currentTool = .select
        editController.selectAll()
        editController.setLinearArrowheadSize(.large)
        try expect(
            editController.selectedElementSnapshot.allSatisfy {
                guard case .linear(let linear) = $0.geometry else {
                    return false
                }
                return linear.arrowheadSize == .large
            },
            "Expected unlocked selected linears to accept arrowhead-size edits"
        )
        editController.undo()
        try expect(
            editController.selectedElementSnapshot.allSatisfy {
                guard case .linear(let linear) = $0.geometry else {
                    return false
                }
                return linear.arrowheadSize == .medium
            },
            "Expected one undo to restore the selected arrowhead size"
        )

        for route in [
            AnnotationLinearRoute.straight,
            .curved,
            .elbow
        ] {
            for width in [CGFloat(1), 8] {
                for sloppiness in [
                    AnnotationSloppiness.architect,
                    .cartoonist
                ] {
                    let points: [CGPoint] = route == .elbow
                        ? [
                            CGPoint(x: 12, y: 20),
                            CGPoint(x: 56, y: 20),
                            CGPoint(x: 56, y: 76),
                            CGPoint(x: 112, y: 76)
                        ]
                        : [CGPoint(x: 12, y: 20), CGPoint(x: 112, y: 76)]
                    var style = AnnotationStyle(
                        color: .blue,
                        rootWidth: width,
                        alpha: 1,
                        sloppiness: sloppiness
                    )
                    style.lineCap = .round
                    let geometry = AnnotationLinearGeometry(
                        points: points,
                        route: route,
                        startArrowhead: .zeroOrMany,
                        endArrowhead: .triangleOutline,
                        startBinding: nil,
                        endBinding: nil,
                        isElbowAutoRouted: false
                    )
                    let element = AnnotationElement(
                        geometry: .linear(geometry),
                        style: style
                    )
                    let firstRender = try renderPixels(
                        elements: [element],
                        renderer: AnnotationRenderer(),
                        width: 128,
                        height: 96
                    )
                    let secondRender = try renderPixels(
                        elements: [element],
                        renderer: AnnotationRenderer(),
                        width: 128,
                        height: 96
                    )
                    try expect(
                        firstRender == secondRender
                            && hasPaintedPixel(
                                firstRender,
                                width: 128,
                                height: 96,
                                near: CGPoint(x: 12, y: 20),
                                radius: max(4, Int(width * 2))
                            )
                            && hasPaintedPixel(
                                firstRender,
                                width: 128,
                                height: 96,
                                near: CGPoint(x: 112, y: 76),
                                radius: max(4, Int(width * 2))
                            ),
                        "Expected clean deterministic \(route) arrowhead attachment at width "
                            + "\(width) and \(sloppiness)"
                    )
                }
            }
        }

    }

    private static func testLinearArrowheadEndpointEditsPreserveOppositeEndpoints() throws {
        let first = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .circle,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        let second = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 0, y: 30), CGPoint(x: 80, y: 30)],
                    route: .straight,
                    startArrowhead: .triangle,
                    endArrowhead: .diamond,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        let scene = AnnotationScene(elements: [first, second])
        scene.select([first.id, second.id])
        let editor = AnnotationEditor(scene: scene)

        editor.setLinearStartArrowhead(.bar)
        guard case .linear(let firstStartEdited) = scene.element(withID: first.id)?.geometry,
              case .linear(let secondStartEdited) = scene.element(withID: second.id)?.geometry else {
            throw SelfTestError.failure("Expected two selected linear elements")
        }
        try expect(
            firstStartEdited.startArrowhead == .bar
                && firstStartEdited.endArrowhead == .circle
                && secondStartEdited.startArrowhead == .bar
                && secondStartEdited.endArrowhead == .diamond,
            "Expected a start-arrowhead edit to preserve each selected line's distinct end arrowhead"
        )

        scene.updateElement(withID: first.id) { element in
            guard case .linear(var linear) = element.geometry else { return }
            linear.startArrowhead = .circle
            element.geometry = .linear(linear)
        }
        scene.updateElement(withID: second.id) { element in
            guard case .linear(var linear) = element.geometry else { return }
            linear.startArrowhead = .diamond
            element.geometry = .linear(linear)
        }
        editor.setLinearEndArrowhead(.arrow)
        guard case .linear(let firstEndEdited) = scene.element(withID: first.id)?.geometry,
              case .linear(let secondEndEdited) = scene.element(withID: second.id)?.geometry else {
            throw SelfTestError.failure("Expected endpoint-edited linear elements")
        }
        try expect(
            firstEndEdited.startArrowhead == .circle
                && firstEndEdited.endArrowhead == .arrow
                && secondEndEdited.startArrowhead == .diamond
                && secondEndEdited.endArrowhead == .arrow,
            "Expected an end-arrowhead edit to preserve each selected line's distinct start arrowhead"
        )

        let transitionController = AnnotationController()
        transitionController.currentTool = .line
        transitionController.begin(at: CGPoint(x: 10, y: 10))
        transitionController.end(at: CGPoint(x: 90, y: 10))
        transitionController.currentTool = .select
        transitionController.selectAll()
        transitionController.setLinearStartArrowhead(.bar)
        transitionController.setLinearStartArrowhead(.none)
        guard case .linear(let headless) =
            transitionController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a selected headless linear element")
        }
        let headlessState = DrawingToolbarState(
            annotationController: transitionController
        )
        try expect(
            headless.startArrowhead == .none
                && headless.endArrowhead == .none
                && headlessState.visibleInspectorSections.contains(.edges)
                && headlessState.visibleInspectorSections.contains(.arrowheads)
                && headlessState.visibleInspectorSections.contains(.arrowheadSize),
            "Expected a selected headless linear element to retain endpoint controls"
        )
        transitionController.setLinearEndArrowhead(.triangleOutline)
        guard case .linear(let transitioned) =
            transitionController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a headless-to-ended arrow transition")
        }
        try expect(
            transitioned.endArrowhead == .triangleOutline,
            "Expected a selected headless line to accept a new end arrowhead"
        )
        transitionController.undo()
        guard case .linear(let undoneTransition) =
            transitionController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected an undoable selected arrowhead update")
        }
        transitionController.redo()
        guard case .linear(let redoneTransition) =
            transitionController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a redoable selected arrowhead update")
        }
        try expect(
            undoneTransition.endArrowhead == .none
                && redoneTransition.endArrowhead == .triangleOutline,
            "Expected selected arrowhead updates to undo and redo atomically"
        )

        let immediateController = AnnotationController()
        immediateController.currentTool = .arrow
        immediateController.setLinearArrowheads(
            start: .circle,
            end: .diamond
        )
        immediateController.begin(at: CGPoint(x: 10, y: 80))
        immediateController.end(at: CGPoint(x: 110, y: 80))
        immediateController.currentTool = .select
        immediateController.selectAll()
        immediateController.setLinearStartArrowhead(.bar)
        guard case .linear(let immediateEdit) =
            immediateController.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure(
                "Expected an immediately edited selected arrow"
            )
        }
        try expect(
            immediateEdit.startArrowhead == .bar
                && immediateEdit.endArrowhead == .diamond,
            "Expected a selected start-head edit to apply immediately and preserve the opposite endpoint"
        )
        immediateController.undo()
        guard case .linear(let undoneImmediateEdit) =
            immediateController.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure(
                "Expected one undo to restore the selected arrowhead family"
            )
        }
        try expect(
            undoneImmediateEdit.startArrowhead == .circle
                && undoneImmediateEdit.endArrowhead == .diamond,
            "Expected one undo to restore only the edited arrowhead family"
        )
        immediateController.redo()
        immediateController.setLinearArrowheadSize(.large)
        guard case .linear(let resizedImmediateEdit) =
            immediateController.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure(
                "Expected an immediately resized selected arrowhead"
            )
        }
        try expect(
            resizedImmediateEdit.startArrowhead == .bar
                && resizedImmediateEdit.endArrowhead == .diamond
                && resizedImmediateEdit.arrowheadSize == .large,
            "Expected selected arrowhead size changes to apply immediately without changing either family"
        )
        immediateController.undo()
        guard case .linear(let undoneImmediateResize) =
            immediateController.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure(
                "Expected one undo to restore the selected arrowhead size"
            )
        }
        try expect(
            undoneImmediateResize.arrowheadSize == .medium
                && undoneImmediateResize.startArrowhead == .bar
                && undoneImmediateResize.endArrowhead == .diamond,
            "Expected one undo to restore only the arrowhead size"
        )

        let lockController = AnnotationController()
        lockController.currentTool = .arrow
        lockController.begin(at: CGPoint(x: 10, y: 20))
        lockController.end(at: CGPoint(x: 90, y: 20))
        lockController.currentTool = .select
        lockController.selectAll()
        lockController.toggleSelectionLock()
        let lockedState = DrawingToolbarState(annotationController: lockController)
        let defaultsBeforeLockedCommand = (
            lockController.currentStartArrowhead,
            lockController.currentEndArrowhead
        )
        guard case .linear(let lockedBefore) =
            lockController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a locked selected arrow")
        }
        lockController.setLinearStartArrowhead(.diamond)
        guard case .linear(let lockedAfter) =
            lockController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected the locked arrow to remain present")
        }
        try expect(
            lockedState.startArrowhead == .unavailable
                && lockedState.endArrowhead == .unavailable
                && lockedState.visibleInspectorSections.contains(.arrowheads)
                && lockedAfter == lockedBefore
                && lockController.currentStartArrowhead
                    == defaultsBeforeLockedCommand.0
                && lockController.currentEndArrowhead
                    == defaultsBeforeLockedCommand.1,
            "Expected locked-only arrowhead controls to disable without mutating defaults"
        )

        lockController.currentTool = .arrow
        lockController.begin(at: CGPoint(x: 10, y: 50))
        lockController.end(at: CGPoint(x: 90, y: 50))
        lockController.currentTool = .select
        lockController.selectAll()
        let mixedLockState = DrawingToolbarState(annotationController: lockController)
        lockController.setLinearEndArrowhead(.circleOutline)
        let lockedLinear = lockController.elementSnapshot.first {
            $0.metadata.isLocked
        }
        let editableLinear = lockController.elementSnapshot.first {
            !$0.metadata.isLocked
        }
        guard case .linear(let lockedGeometry) = lockedLinear?.geometry,
              case .linear(let editableGeometry) = editableLinear?.geometry else {
            throw SelfTestError.failure("Expected locked and editable selected arrows")
        }
        try expect(
            mixedLockState.arrowheadChangesApplyToEditableOnly
                && lockedGeometry.endArrowhead == .arrow
                && editableGeometry.endArrowhead == .circleOutline,
            "Expected mixed locked/unlocked arrow commands to apply only to editable elements"
        )

        var undoLockedElement = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        undoLockedElement.metadata.isLocked = true
        let undoLockedScene = AnnotationScene(elements: [undoLockedElement])
        undoLockedScene.select([undoLockedElement.id])
        undoLockedScene.setLocked(false, for: [undoLockedElement.id])
        let undoLockedEditor = AnnotationEditor(scene: undoLockedScene)
        try expect(
            undoLockedEditor.beginLinearPointEditing(),
            "Expected the temporarily unlocked arrow to enter point-edit mode"
        )
        try expect(
            undoLockedScene.undo(),
            "Expected undo to restore the arrow's locked state"
        )
        undoLockedEditor.setLinearStartArrowhead(.bar)
        guard case .linear(let undoLockedGeometry) =
            undoLockedScene.element(withID: undoLockedElement.id)?.geometry else {
            throw SelfTestError.failure("Expected the undo-restored locked arrow")
        }
        try expect(
            undoLockedScene.element(withID: undoLockedElement.id)?.metadata.isLocked == true
                && undoLockedGeometry.startArrowhead == .none,
            "Expected point-edit mutations to revalidate selection and lock state after undo"
        )
    }

    private static func testLinearBindingLifecycle() throws {
        let scene = AnnotationScene()
        let shape = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 40, y: 40),
                    end: CGPoint(x: 100, y: 100)
                )
            ),
            style: .default
        )
        let line = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 0, y: 70), CGPoint(x: 100, y: 70)],
                    route: .curved,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        scene.append(shape)
        scene.append(line)
        guard let binding = AnnotationGeometry.binding(
            to: shape,
            near: CGPoint(x: 100, y: 70)
        ) else {
            throw SelfTestError.failure("Expected a shape-edge binding")
        }
        scene.bindLinearEndpoint(elementID: line.id, atStart: false, to: binding)

        guard case .linear(let initiallyBound) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected bound linear geometry")
        }
        try expect(
            initiallyBound.endBinding?.targetElementID == shape.id
                && approximatelyEqual(initiallyBound.points.last!, CGPoint(x: 100, y: 70)),
            "Expected the endpoint to bind to the nearest shape edge"
        )

        scene.select([line.id])
        let editor = AnnotationEditor(scene: scene)
        try expect(editor.beginLinearPointEditing(), "Expected bound endpoint point editing")
        _ = editor.beginInteraction(
            at: initiallyBound.points.last!,
            zoomScale: 1,
            modifiers: [.option],
            clickCount: 1
        )
        editor.updateInteraction(
            to: CGPoint(x: 125, y: 70),
            modifiers: [.option]
        )
        editor.endInteraction(
            at: CGPoint(x: 125, y: 70),
            modifiers: [.option]
        )
        guard case .linear(let optionUnbound) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected Option-dragged endpoint")
        }
        try expect(
            optionUnbound.endBinding == nil
                && approximatelyEqual(optionUnbound.points.last!, CGPoint(x: 125, y: 70)),
            "Expected Option-drag to explicitly unbind and move a bound endpoint"
        )
        scene.bindLinearEndpoint(elementID: line.id, atStart: false, to: binding)
        editor.finishLinearPointEditing()

        scene.updateElement(withID: shape.id) { element in
            guard case .shape(var geometry) = element.geometry else { return }
            geometry.start.x += 20
            geometry.end.x += 20
            element.geometry = .shape(geometry)
        }
        guard case .linear(let movedBinding) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected binding after target movement")
        }
        try expect(
            approximatelyEqual(movedBinding.points.last!, CGPoint(x: 120, y: 70)),
            "Expected bound endpoints to update live when the shape moves"
        )

        scene.updateElement(withID: shape.id) { element in
            guard case .shape(var geometry) = element.geometry else { return }
            geometry.end.x = 160
            element.geometry = .shape(geometry)
        }
        guard case .linear(let resizedBinding) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected binding after target resize")
        }
        try expect(
            approximatelyEqual(resizedBinding.points.last!, CGPoint(x: 160, y: 70)),
            "Expected bound endpoints to update live when the shape resizes"
        )

        scene.updateElement(withID: shape.id) { element in
            element.metadata.rotation = .pi / 2
        }
        guard case .linear(let rotatedBinding) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected binding after target rotation")
        }
        try expect(
            approximatelyEqual(rotatedBinding.points.last!, CGPoint(x: 110, y: 120)),
            "Expected bound endpoints to follow rotated shape edges"
        )

        scene.unbindLinearEndpoints(elementID: line.id, start: false, end: true)
        guard case .linear(let unbound) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected explicitly unbound geometry")
        }
        let preservedEndpoint = unbound.points.last!
        try expect(unbound.endBinding == nil, "Expected explicit endpoint unbinding")
        scene.updateElement(withID: shape.id) { element in
            guard case .shape(var geometry) = element.geometry else { return }
            geometry.start.y += 50
            geometry.end.y += 50
            element.geometry = .shape(geometry)
        }
        guard case .linear(let afterUnboundMove) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected line after moving an unbound target")
        }
        try expect(
            approximatelyEqual(afterUnboundMove.points.last!, preservedEndpoint),
            "Expected unbinding to preserve the endpoint and stop live target updates"
        )

        guard let rebound = AnnotationGeometry.binding(
            to: scene.element(withID: shape.id)!,
            near: CGPoint(x: 110, y: 170)
        ) else {
            throw SelfTestError.failure("Expected rebinding before deletion")
        }
        scene.bindLinearEndpoint(elementID: line.id, atStart: false, to: rebound)
        guard case .linear(let beforeDeletion) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected rebound line before deletion")
        }
        let deletionEndpoint = beforeDeletion.points.last!
        scene.removeElements(withIDs: [shape.id])
        guard case .linear(let afterDeletion) = scene.element(withID: line.id)?.geometry else {
            throw SelfTestError.failure("Expected bound line to survive target deletion")
        }
        try expect(
            afterDeletion.endBinding == nil
                && approximatelyEqual(afterDeletion.points.last!, deletionEndpoint),
            "Expected safe target deletion to clear binding without moving or deleting the line"
        )
    }

    private static func testRotatedConnectorBindingRefreshUsesStablePivot() throws {
        let target = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 200, y: 100),
                    end: CGPoint(x: 260, y: 160)
                )
            ),
            style: .default
        )
        let binding = AnnotationBinding(
            targetElementID: target.id,
            normalizedAnchor: CGPoint(x: 0, y: 0.5),
            focus: 0,
            side: .leading
        )
        var connector = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 40, y: 130), CGPoint(x: 180, y: 130)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: binding
                )
            ),
            style: .default
        )
        connector.metadata.rotation = .pi / 4
        let scene = AnnotationScene(elements: [target, connector])

        func expectBoundEndpointAtDesiredWorldPoint(_ message: String) throws {
            guard let currentTarget = scene.element(withID: target.id),
                  let currentConnector = scene.element(withID: connector.id),
                  case .linear(let linear) = currentConnector.geometry,
                  let endpoint = linear.points.last,
                  linear.points.count >= 2,
                  let currentBinding = linear.endBinding else {
                throw SelfTestError.failure("Expected a rotated bound connector")
            }
            let transform = AnnotationGeometry.worldTransform(for: currentConnector)
            let actualWorldPoint = endpoint.applying(transform)
            let neighborWorldPoint = linear.points[linear.points.count - 2].applying(transform)
            guard let desiredWorldPoint = AnnotationGeometry.bindingPoint(
                for: currentBinding,
                on: currentTarget,
                toward: neighborWorldPoint
            ) else {
                throw SelfTestError.failure("Expected a desired world-space binding point")
            }
            try expect(
                approximatelyEqual(actualWorldPoint, desiredWorldPoint),
                "\(message): expected \(desiredWorldPoint), got \(actualWorldPoint)"
            )
            try expect(
                linear.rotationPivot != nil,
                "Expected rotated connectors to retain a stable local rotation pivot"
            )
        }

        try expectBoundEndpointAtDesiredWorldPoint(
            "Expected initial rotated connector binding to land exactly"
        )
        scene.updateElement(withID: target.id) { element in
            guard case .shape(var shape) = element.geometry else { return }
            shape.start.x += 45
            shape.end.x += 45
            shape.start.y += 20
            shape.end.y += 20
            element.geometry = .shape(shape)
        }
        try expectBoundEndpointAtDesiredWorldPoint(
            "Expected rotated connector refresh to avoid pivot drift after target movement"
        )
    }

    private static func testRotatedBindingDirections() throws {
        let cases: [(
            targetRotation: CGFloat,
            connectorRotation: CGFloat,
            expected: [AnnotationEndpointDirection]
        )] = [
            (
                .pi / 2,
                0,
                [
                    .trailing,
                    .down,
                    .leading,
                    .up
                ]
            ),
            (
                0,
                .pi / 2,
                [
                    .leading,
                    .up,
                    .trailing,
                    .down
                ]
            ),
            (
                .pi / 2,
                -.pi / 2,
                [
                    .down,
                    .leading,
                    .up,
                    .trailing
                ]
            )
        ]

        for testCase in cases {
            let sides = [
                AnnotationBindingSide.top,
                .trailing,
                .bottom,
                .leading
            ]
            for (side, expected) in zip(sides, testCase.expected) {
                try expect(
                    AnnotationGeometry.routedEndpointDirection(
                        for: side,
                        targetRotation: testCase.targetRotation,
                        connectorRotation: testCase.connectorRotation,
                        fallback: .automatic
                    ) == expected,
                    "Expected \(side) binding direction to transform from target-local "
                        + "through world into connector-local space"
                )
            }
        }
        try expect(
            AnnotationGeometry.routedEndpointDirection(
                for: .automatic,
                targetRotation: .pi / 2,
                connectorRotation: -.pi / 2,
                fallback: .leading
            ) == .leading,
            "Expected automatic binding sides to retain the stored direction"
        )
    }

    private static func testLegacyArrowGestureOrientation() throws {
        try expect(
            ZoomCanvasView.gestureTool(control: true, shift: true, tab: false) == .arrow
                && ZoomCanvasView.gestureTool(control: true, shift: false, tab: false) == .rectangle
                && ZoomCanvasView.gestureTool(control: false, shift: true, tab: false) == .line
                && ZoomCanvasView.gestureTool(control: false, shift: false, tab: true) == .ellipse,
            "Expected the existing modifier gestures, including Control+Shift arrow, to remain unchanged"
        )

        let controller = AnnotationController()
        controller.begin(
            at: CGPoint(x: 10, y: 20),
            tool: .arrow,
            legacyModifierGesture: true
        )
        controller.end(at: CGPoint(x: 100, y: 20))
        guard case .linear(let arrow) = controller.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected legacy arrow geometry")
        }
        try expect(
            arrow.points == [CGPoint(x: 10, y: 20), CGPoint(x: 100, y: 20)]
                && arrow.startArrowhead == .arrow
                && arrow.endArrowhead == .none
                && arrow.arrowheadSize == .small,
            "Expected the drag origin to remain the legacy arrow tip"
        )
        guard let arrowhead = AnnotationGeometry.arrowheadPath(
            arrow.startArrowhead,
            tip: arrow.points[0],
            adjacent: arrow.points[1],
            strokeWidth: controller.currentStyle.strokeWidth
        ) else {
            throw SelfTestError.failure("Expected legacy arrowhead geometry")
        }
        try expect(
            arrowhead.boundingBoxOfPath.maxX > arrow.points[0].x,
            "Expected the legacy arrowhead to point back toward the Control+Shift drag origin"
        )

        let persistentController = AnnotationController()
        persistentController.setLinearRoute(.elbow)
        persistentController.setLinearArrowheads(start: .circle, end: .diamond)
        persistentController.begin(
            at: CGPoint(x: 10, y: 40),
            tool: .line,
            legacyModifierGesture: true
        )
        persistentController.end(at: CGPoint(x: 100, y: 40))
        persistentController.begin(
            at: CGPoint(x: 10, y: 70),
            tool: .arrow,
            legacyModifierGesture: true
        )
        persistentController.end(at: CGPoint(x: 100, y: 70))
        guard persistentController.elementSnapshot.count == 2,
              case .linear(let shiftLine) = persistentController.elementSnapshot[0].geometry,
              case .linear(let controlShiftArrow) = persistentController.elementSnapshot[1].geometry else {
            throw SelfTestError.failure("Expected modifier gesture linear elements")
        }
        try expect(
            shiftLine.route == .straight
                && shiftLine.startArrowhead == .none
                && shiftLine.endArrowhead == .none
                && shiftLine.arrowheadSize == .small,
            "Expected Shift-drag to remain a straight headless legacy line"
        )
        try expect(
            controlShiftArrow.route == .straight
                && controlShiftArrow.startArrowhead == .arrow
                && controlShiftArrow.endArrowhead == .none
                && controlShiftArrow.arrowheadSize == .small,
            "Expected Control+Shift-drag to retain the straight legacy start arrow"
        )
    }

    private static func testLinearToolDefaultTransitionsAndApplication() throws {
        var implicitDefaults = DrawingDefaults.default
        try expect(
            implicitDefaults.lineRoute == .straight
                && implicitDefaults.arrowRoute == .curved
                && implicitDefaults.arrowheadSize == .medium,
            "Expected fresh Line and Arrow route scopes plus medium arrowheads"
        )
        implicitDefaults.selectTool(.line)
        try expect(
            implicitDefaults.tool == .line
                && implicitDefaults.startArrowhead == .none
                && implicitDefaults.endArrowhead == .none,
            "Expected Line to discard the implicit forward Arrow default"
        )
        implicitDefaults.selectTool(.arrow)
        try expect(
            implicitDefaults.startArrowhead == .none
                && implicitDefaults.endArrowhead == .arrow,
            "Expected Arrow to default to a forward end arrowhead"
        )

        var customDefaults = DrawingDefaults.default
        customDefaults.startArrowhead = .circle
        customDefaults.endArrowhead = .diamond
        customDefaults.selectTool(.line)
        try expect(
            customDefaults.startArrowhead == .circle
                && customDefaults.endArrowhead == .diamond,
            "Expected Line tool transitions to preserve explicit custom arrowheads"
        )

        let transitionController = AnnotationController()
        transitionController.setLinearArrowheads(start: .none, end: .none)
        transitionController.currentTool = .arrow
        try expect(
            transitionController.currentStartArrowhead == .none
                && transitionController.currentEndArrowhead == .arrow
                && transitionController.currentLinearRoute == .curved,
            "Expected runtime Arrow selection to create only a forward end arrowhead"
        )
        transitionController.setLinearArrowheads(start: .none, end: .none)
        transitionController.begin(at: CGPoint(x: 10, y: 10), tool: .arrow)
        transitionController.end(at: CGPoint(x: 90, y: 40))
        guard case .linear(let headlessArrow) =
            transitionController.elementSnapshot.last?.geometry else {
            throw SelfTestError.failure(
                "Expected a headless nonlegacy Arrow creation"
            )
        }
        try expect(
            headlessArrow.startArrowhead == .none
                && headlessArrow.endArrowhead == .none,
            "Expected nonlegacy Arrow creation to assign both current none endpoints"
        )
        transitionController.setLinearRoute(.elbow)
        transitionController.currentTool = .line
        try expect(
            transitionController.currentStartArrowhead == .none
                && transitionController.currentEndArrowhead == .none
                && transitionController.currentLinearRoute == .straight,
            "Expected Line to restore its independent straight route scope"
        )
        transitionController.setLinearRoute(.curved)
        transitionController.currentTool = .arrow
        try expect(
            transitionController.currentLinearRoute == .elbow,
            "Expected Arrow to restore its independently edited route scope"
        )

        var explicitLine = DrawingDefaults.default
        explicitLine.tool = .line
        explicitLine.startArrowhead = .none
        explicitLine.endArrowhead = .arrow
        explicitLine.linearRoute = .curved
        let appliedController = AnnotationController()
        appliedController.applyDrawingDefaults(explicitLine, strokeWidth: 7)
        try expect(
            appliedController.currentTool == .line
                && appliedController.currentLinearRoute == .curved
                && appliedController.currentStartArrowhead == .none
                && appliedController.currentEndArrowhead == .arrow
                && appliedController.currentStyle.strokeWidth == 7,
            "Expected loading explicitly stored line heads to bypass implicit tool transitions"
        )
    }

    private static func testAnnotationHitTestingAndSelectionDecorations() throws {
        var filledStyle = AnnotationStyle.default
        filledStyle.strokeWidth = 2
        filledStyle.fillStyle = .solid
        filledStyle.sloppiness = .architect
        let diamond = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .diamond,
                    start: CGPoint(x: 20, y: 20),
                    end: CGPoint(x: 60, y: 60)
                )
            ),
            style: filledStyle
        )
        try expect(
            AnnotationHitTester.contains(CGPoint(x: 40, y: 40), in: diamond, zoomScale: 1),
            "Expected filled diamond hit testing to include its interior"
        )
        for fillStyle in [AnnotationFillStyle.hachure, .crossHatch] {
            var patternedStyle = filledStyle
            patternedStyle.fillStyle = fillStyle
            for kind in [
                AnnotationShapeKind.rectangle,
                .diamond,
                .ellipse
            ] {
                let patternedShape = AnnotationElement(
                    geometry: .shape(
                        AnnotationShapeGeometry(
                            kind: kind,
                            start: CGPoint(x: 20, y: 20),
                            end: CGPoint(x: 60, y: 60)
                        )
                    ),
                    style: patternedStyle
                )
                try expect(
                    AnnotationHitTester.contains(
                        CGPoint(x: 40, y: 40),
                        in: patternedShape,
                        zoomScale: 1
                    ),
                    "Expected \(fillStyle) \(kind) hit testing to include its visible interior"
                )
            }
        }
        try expect(
            !AnnotationHitTester.contains(CGPoint(x: 20, y: 20), in: diamond, zoomScale: 4),
            "Expected diamond hit testing to reject points outside its rotated edges"
        )

        var roundedStyle = filledStyle
        roundedStyle.roundness = 50
        let roundedRectangle = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: .zero,
                    end: CGPoint(x: 100, y: 100)
                )
            ),
            style: roundedStyle
        )
        let roundedDiamond = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .diamond,
                    start: .zero,
                    end: CGPoint(x: 100, y: 100)
                )
            ),
            style: roundedStyle
        )
        try expect(
            AnnotationHitTester.hitTest(
                point: .zero,
                elements: [roundedRectangle],
                zoomScale: 1
            ) == nil
                && AnnotationHitTester.hitTest(
                    point: CGPoint(x: 50, y: 50),
                    elements: [roundedRectangle],
                    zoomScale: 1
                ) == AnnotationHitTester.Hit(
                    elementID: roundedRectangle.id,
                    part: .body
                )
                && !AnnotationHitTester.contains(
                    .zero,
                    in: roundedDiamond,
                    zoomScale: 1
                ),
            "Expected rounded rectangle and diamond hit testing to follow their rendered paths"
        )

        var transparentFillStyle = roundedStyle
        transparentFillStyle.fillColor = .rgba(
            red: 1,
            green: 0,
            blue: 0,
            alpha: 0
        )
        let transparentFilledRectangle = AnnotationElement(
            geometry: roundedRectangle.geometry,
            style: transparentFillStyle
        )
        try expect(
            !AnnotationHitTester.contains(
                CGPoint(x: 50, y: 50),
                in: transparentFilledRectangle,
                zoomScale: 1
            ),
            "Expected a fully transparent solid fill not to create an interior hit"
        )

        var roundedOutlineStyle = roundedStyle
        roundedOutlineStyle.fillStyle = .none
        let roundedOutline = AnnotationElement(
            geometry: roundedRectangle.geometry,
            style: roundedOutlineStyle
        )
        try expect(
            AnnotationHitTester.contains(
                CGPoint(x: 50, y: -6),
                in: roundedOutline,
                zoomScale: 1
            ),
            "Expected rounded shape outlines to include destination-space hit tolerance"
        )

        var sharpOutlineStyle = roundedOutlineStyle
        sharpOutlineStyle.roundness = nil
        let sharpOutline = AnnotationElement(
            geometry: roundedRectangle.geometry,
            style: sharpOutlineStyle
        )
        try expect(
            !AnnotationHitTester.contains(
                CGPoint(x: -6, y: -6),
                in: sharpOutline,
                zoomScale: 1
            ),
            "Expected sharp outlines not to inherit phantom corners from expanded bounds"
        )

        let ellipseOutline = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .ellipse,
                    start: .zero,
                    end: CGPoint(x: 100, y: 50)
                )
            ),
            style: roundedOutlineStyle
        )
        try expect(
            AnnotationHitTester.contains(
                CGPoint(x: 50, y: -6),
                in: ellipseOutline,
                zoomScale: 1
            )
                && !AnnotationHitTester.contains(
                    .zero,
                    in: ellipseOutline,
                    zoomScale: 1
                ),
            "Expected ellipse outlines to preserve curved-edge hit behavior"
        )

        var roughOutlineStyle = roundedOutlineStyle
        roughOutlineStyle.roundness = nil
        roughOutlineStyle.strokeWidth = 3
        roughOutlineStyle.sloppiness = .cartoonist
        let roughOutline = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 200, y: 0),
                    end: CGPoint(x: 300, y: 100)
                )
            ),
            style: roughOutlineStyle
        )
        try expect(
            AnnotationHitTester.contains(
                CGPoint(x: 190, y: 50),
                in: roughOutline,
                zoomScale: 1
            ),
            "Expected rough shape hit testing to include maximum rendered displacement"
        )

        var rotated = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 70, y: 20),
                    end: CGPoint(x: 110, y: 40)
                )
            ),
            style: roundedStyle
        )
        rotated.metadata.rotation = .pi / 2
        try expect(
            AnnotationHitTester.contains(CGPoint(x: 90, y: 45), in: rotated, zoomScale: 1),
            "Expected rounded shape hit testing to invert element rotation"
        )

        let roundedCornerEraserHits = AnnotationHitTester.bodyHits(
            point: .zero,
            elements: [roundedRectangle],
            zoomScale: 1
        )
        let roundedInteriorEraserHits = AnnotationHitTester.bodyHits(
            point: CGPoint(x: 50, y: 50),
            elements: [roundedRectangle],
            zoomScale: 1
        )
        try expect(
            roundedCornerEraserHits.elementIDs.isEmpty
                && roundedCornerEraserHits.testedElementCount == 1
                && roundedInteriorEraserHits.elementIDs == [roundedRectangle.id]
                && roundedInteriorEraserHits.testedElementCount == 1,
            "Expected eraser hit testing to share rounded shape path semantics"
        )

        for kind in [
            AnnotationShapeKind.rectangle,
            .diamond,
            .ellipse
        ] {
            var tinyStyle = roundedOutlineStyle
            tinyStyle.strokeWidth = 2
            tinyStyle.roundness = kind == .ellipse ? nil : 6
            let tiny = AnnotationElement(
                geometry: .shape(
                    AnnotationShapeGeometry(
                        kind: kind,
                        start: .zero,
                        end: CGPoint(x: 8, y: 6)
                    )
                ),
                style: tinyStyle
            )
            try expect(
                AnnotationHitTester.contains(
                    CGPoint(x: 4, y: 3),
                    in: tiny,
                    zoomScale: 1
                ),
                "Expected oversized low-zoom \(kind) hit tolerance to fall back "
                    + "to canonical boundary distance"
            )
            if kind == .rectangle {
                try expect(
                    !AnnotationHitTester.contains(
                        CGPoint(x: -6, y: -6),
                        in: tiny,
                        zoomScale: 1
                    ),
                    "Expected rounded empty corners to remain outside the "
                        + "canonical boundary tolerance"
                )
            }
        }

        let line = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 10, y: 90), CGPoint(x: 110, y: 90)],
            style: AnnotationStyle(color: .red, rootWidth: 2, alpha: 1)
        )
        let nearLine = CGPoint(x: 50, y: 95)
        try expect(
            AnnotationHitTester.contains(nearLine, in: line, zoomScale: 1),
            "Expected screen-space hit tolerance at 1x"
        )
        try expect(
            !AnnotationHitTester.contains(nearLine, in: line, zoomScale: 4),
            "Expected hit tolerance to shrink in content space when zoomed"
        )

        guard let oneX = AnnotationGeometry.selectionDecoration(for: rotated, zoomScale: 1),
              let threeX = AnnotationGeometry.selectionDecoration(for: rotated, zoomScale: 3),
              let rotationHandle = oneX.handles.first(where: { $0.kind == .rotation }) else {
            throw SelfTestError.failure("Expected reusable selection decoration geometry")
        }
        try expect(
            approximatelyEqual(oneX.handles[0].bounds.width, threeX.handles[0].bounds.width * 3),
            "Expected selection handles to retain a fixed destination-space size"
        )
        let handleHit = AnnotationHitTester.hitTest(
            point: rotationHandle.center,
            elements: [rotated],
            selection: [rotated.id],
            zoomScale: 1
        )
        try expect(
            handleHit == AnnotationHitTester.Hit(elementID: rotated.id, part: .handle(.rotation)),
            "Expected selected-element handles to take precedence over body hits"
        )
    }

    private static func testAdaptiveCurveAndArrowheadHitTesting() throws {
        var thinStyle = AnnotationStyle.default
        thinStyle.strokeWidth = 1
        thinStyle.sloppiness = .architect
        let extremeCurve = AnnotationLinearGeometry(
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0)
            ],
            route: .curved,
            startArrowhead: .none,
            endArrowhead: .none,
            startBinding: nil,
            endBinding: nil,
            bezierControls: [
                AnnotationBezierControl(
                    start: CGPoint(x: 0, y: 100_000),
                    end: CGPoint(x: 120, y: -100_000)
                )
            ]
        )
        let extremeElement = AnnotationElement(
            geometry: .linear(extremeCurve),
            style: thinStyle
        )
        let renderedCenterlinePoint = AnnotationGeometry.linearDisplayPoints(
            extremeCurve,
            subdivisions: 4_096
        )[557]
        let approximation = AnnotationGeometry.linearApproximation(
            extremeCurve,
            maximumError: 0.15
        )
        let selectionHit = AnnotationHitTester.hitTest(
            point: renderedCenterlinePoint,
            elements: [extremeElement],
            zoomScale: 200
        )
        let eraserHits = AnnotationHitTester.bodyHits(
            point: renderedCenterlinePoint,
            elements: [extremeElement],
            zoomScale: 200
        )
        try expect(
            selectionHit == AnnotationHitTester.Hit(
                elementID: extremeElement.id,
                part: .body
            )
                && eraserHits.elementIDs == [extremeElement.id]
                && eraserHits.testedElementCount == 1
                && approximation.segments.count > 16
                && approximation.segments.count
                    <= AnnotationGeometry.maximumAdaptiveCubicSegmentsPerCurve
                && approximation.operationCount
                    <= AnnotationGeometry.maximumAdaptiveCubicSegmentsPerCurve * 2 - 1,
            "Expected selection and eraser hit testing to follow extreme cubic "
                + "centerlines at high zoom with a bounded adaptive workload"
        )

        func arrowheadElement(
            _ arrowhead: AnnotationArrowhead,
            size: AnnotationArrowheadSize = .large
        ) -> AnnotationElement {
            var style = AnnotationStyle.default
            style.strokeWidth = 2
            style.sloppiness = .architect
            return AnnotationElement(
                geometry: .linear(
                    AnnotationLinearGeometry(
                        points: [
                            CGPoint(x: 0, y: 0),
                            CGPoint(x: 100, y: 0)
                        ],
                        route: .straight,
                        startArrowhead: .none,
                        endArrowhead: arrowhead,
                        arrowheadSize: size,
                        startBinding: nil,
                        endBinding: nil
                    )
                ),
                style: style
            )
        }

        let metrics = AnnotationGeometry.arrowheadMetrics(
            strokeWidth: 2,
            size: .large
        )
        let circleCenter = CGPoint(
            x: 100 - metrics.halfWidth,
            y: 0
        )
        let circleCorner = CGPoint(
            x: 100 - metrics.halfWidth * 2 + 1.25,
            y: -metrics.halfWidth + 1.25
        )
        let circleEdge = CGPoint(
            x: circleCenter.x,
            y: -metrics.halfWidth
        )
        let outlinedCircle = arrowheadElement(.circleOutline)
        let filledCircle = arrowheadElement(.circle)
        try expect(
            !AnnotationHitTester.contains(
                circleCorner,
                in: outlinedCircle,
                zoomScale: 20
            )
                && AnnotationHitTester.contains(
                    circleEdge,
                    in: outlinedCircle,
                    zoomScale: 20
                )
                && !AnnotationHitTester.contains(
                    circleCorner,
                    in: filledCircle,
                    zoomScale: 20
                )
                && AnnotationHitTester.contains(
                    circleCenter,
                    in: filledCircle,
                    zoomScale: 20
                ),
            "Expected large circle heads to use their exact fill or stroked edge, "
                + "not an expanded bounding-box corner"
        )

        let outlinedTriangle = arrowheadElement(.triangleOutline)
        let triangleInterior = CGPoint(x: 88, y: 0)
        let triangleEdge = CGPoint(
            x: 100 - metrics.length / 2,
            y: metrics.halfWidth / 2
        )
        let bar = arrowheadElement(.bar)
        let barCorner = CGPoint(
            x: 101.2,
            y: metrics.halfWidth + 1.2
        )
        let crowFoot = arrowheadElement(.crowFoot)
        let crowInterior = CGPoint(x: 90, y: 4.2)
        let zeroOrOne = arrowheadElement(.zeroOrOne)
        let compoundCorner = CGPoint(x: 99, y: 12)
        try expect(
            !AnnotationHitTester.contains(
                triangleInterior,
                in: outlinedTriangle,
                zoomScale: 20
            )
                && AnnotationHitTester.contains(
                    triangleEdge,
                    in: outlinedTriangle,
                    zoomScale: 20
                )
                && !AnnotationHitTester.contains(
                    barCorner,
                    in: bar,
                    zoomScale: 20
                )
                && !AnnotationHitTester.contains(
                    crowInterior,
                    in: crowFoot,
                    zoomScale: 20
                )
                && !AnnotationHitTester.contains(
                    compoundCorner,
                    in: zeroOrOne,
                    zoomScale: 20
                ),
            "Expected outlined, bar, crow-foot, and compound arrowheads to hit "
                + "only their stroked paths within destination-space tolerance"
        )
    }

    private static func testMixedLockSelectionHandlesMatchEditableElements() throws {
        let editable = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 10, y: 30), CGPoint(x: 50, y: 70)],
            style: .default
        )
        var locked = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 150, y: 30), CGPoint(x: 210, y: 90)],
            style: .default
        )
        locked.metadata.isLocked = true
        let elements = [editable, locked]
        let selection: Set<AnnotationElementID> = [editable.id, locked.id]

        let presented = AnnotationSelectionPresentation.editableElements(
            from: elements,
            selectedElementIDs: selection
        )
        try expect(
            presented.map(\.id) == [editable.id],
            "Expected mixed selection decorations to describe only editable elements"
        )

        guard let editableDecoration = AnnotationGeometry.selectionDecoration(
            for: editable,
            zoomScale: 1
        ),
        let editableResizeHandle = editableDecoration.handles.first(where: {
            $0.kind == .bottomTrailing
        }),
        let mixedDecoration = AnnotationGeometry.selectionDecoration(
            for: elements,
            zoomScale: 1
        ),
        let staleMixedHandle = mixedDecoration.handles.first(where: {
            $0.kind == .top
        }),
        let lockedDecoration = AnnotationGeometry.selectionDecoration(
            for: locked,
            zoomScale: 1
        ),
        let lockedRotationHandle = lockedDecoration.handles.first(where: {
            $0.kind == .rotation
        }) else {
            throw SelfTestError.failure("Expected selection handles for mixed-lock regression setup")
        }

        try expect(
            AnnotationHitTester.hitTest(
                point: staleMixedHandle.center,
                elements: elements,
                selection: selection,
                zoomScale: 1
            ) == nil,
            "Expected handles from locked-inclusive bounds to be non-interactive"
        )
        try expect(
            AnnotationHitTester.hitTest(
                point: editableResizeHandle.center,
                elements: elements,
                selection: selection,
                zoomScale: 1
            ) == AnnotationHitTester.Hit(
                elementID: editable.id,
                part: .handle(.bottomTrailing)
            ),
            "Expected mixed selection handles to align with the editable transform bounds"
        )

        try expect(
            AnnotationHitTester.hitTest(
                point: lockedRotationHandle.center,
                elements: elements,
                selection: selection,
                zoomScale: 1
            ) == nil,
            "Expected selected locked elements not to expose inferred handles"
        )
        let lockedHandleScene = AnnotationScene(elements: elements)
        lockedHandleScene.select(selection)
        let lockedHandleEditor = AnnotationEditor(scene: lockedHandleScene)
        let editableBeforeLockedHandle =
            lockedHandleScene.element(withID: editable.id)
        let lockedBeforeLockedHandle =
            lockedHandleScene.element(withID: locked.id)
        _ = lockedHandleEditor.beginInteraction(
            at: lockedRotationHandle.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        lockedHandleEditor.updateInteraction(
            to: CGPoint(
                x: lockedRotationHandle.center.x + 20,
                y: lockedRotationHandle.center.y + 15
            ),
            modifiers: []
        )
        lockedHandleEditor.endInteraction(
            at: CGPoint(
                x: lockedRotationHandle.center.x + 20,
                y: lockedRotationHandle.center.y + 15
            ),
            modifiers: []
        )
        try expect(
            lockedHandleScene.element(withID: editable.id)
                == editableBeforeLockedHandle
                && lockedHandleScene.element(withID: locked.id)
                    == lockedBeforeLockedHandle,
            "Expected clicking a locked element's inferred handle not to transform "
                + "the editable selection"
        )

        let scene = AnnotationScene(elements: elements)
        scene.select(selection)
        let editor = AnnotationEditor(scene: scene)
        let lockedBefore = scene.element(withID: locked.id)
        _ = editor.beginInteraction(
            at: editableResizeHandle.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.endInteraction(
            at: CGPoint(
                x: editableResizeHandle.center.x + 20,
                y: editableResizeHandle.center.y + 15
            ),
            modifiers: []
        )
        try expect(
            scene.element(withID: locked.id) == lockedBefore,
            "Expected a mixed-selection resize to leave locked elements unchanged"
        )
    }

    private static func testAnnotationEditorSelectionAndMarquee() throws {
        var style = AnnotationStyle.default
        style.fillStyle = .solid
        let scene = AnnotationScene()
        let back = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 40, y: 40)
                )
            ),
            style: style
        )
        let front = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .ellipse,
                    start: CGPoint(x: 10, y: 10),
                    end: CGPoint(x: 50, y: 50)
                )
            ),
            style: style
        )
        scene.append(back)
        scene.append(front)
        let editor = AnnotationEditor(scene: scene)
        let overlap = CGPoint(x: 20, y: 20)

        _ = editor.beginInteraction(
            at: overlap,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.endInteraction(at: overlap, modifiers: [])
        try expect(
            editor.selectedElementIDs == [front.id],
            "Expected click selection to choose the topmost overlapping element"
        )

        _ = editor.beginInteraction(
            at: CGPoint(x: 2, y: 2),
            zoomScale: 1,
            modifiers: [.shift],
            clickCount: 1
        )
        editor.endInteraction(at: CGPoint(x: 2, y: 2), modifiers: [.shift])
        try expect(
            editor.selectedElementIDs == [back.id, front.id],
            "Expected Shift-click to add an element to the selection"
        )

        _ = editor.beginInteraction(
            at: overlap,
            zoomScale: 1,
            modifiers: [.command],
            clickCount: 1
        )
        editor.endInteraction(at: overlap, modifiers: [.command])
        try expect(
            editor.selectedElementIDs == [back.id],
            "Expected Command-click to toggle the clicked element"
        )

        _ = editor.beginInteraction(
            at: CGPoint(x: -30, y: -30),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(
            editor.stateKind == .marqueeSelecting,
            "Expected empty-space dragging to enter marquee selection"
        )
        editor.updateInteraction(to: CGPoint(x: 60, y: 60), modifiers: [])
        try expect(
            editor.selectedElementIDs == [back.id, front.id],
            "Expected marquee selection to include intersecting visible elements"
        )
        editor.endInteraction(at: CGPoint(x: 60, y: 60), modifiers: [])
        try expect(editor.stateKind == .idle, "Expected marquee mouse-up to return to idle")
    }

    private static func testSelectArrowKeyFallthrough() throws {
        try expect(
            ZoomCanvasView.selectionNudge(
                keyCode: 126,
                shift: false,
                hasMovableSelection: false
            ) == nil,
            "Expected Select-mode Up to fall through to zoom when nothing can move"
        )
        try expect(
            ZoomCanvasView.selectionNudge(
                keyCode: 125,
                shift: true,
                hasMovableSelection: true
            ) == CGPoint(x: 0, y: 10),
            "Expected a movable selection to retain Shift-arrow ten-point nudging"
        )

        let scene = AnnotationScene()
        var locked = AnnotationElement.legacy(
            tool: .rectangle,
            points: [.zero, CGPoint(x: 20, y: 20)],
            style: .default
        )
        locked.metadata.isLocked = true
        scene.append(locked)
        scene.select([locked.id])
        let editor = AnnotationEditor(scene: scene)
        try expect(
            !editor.hasMovableSelection,
            "Expected a locked-only selection not to consume Select-mode arrow keys"
        )
    }

    private static func testAnnotationEditorTransformTransactionsAndLocking() throws {
        var style = AnnotationStyle.default
        style.fillStyle = .solid
        let scene = AnnotationScene()
        let shape = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 10, y: 10),
                    end: CGPoint(x: 50, y: 40)
                )
            ),
            style: style
        )
        scene.append(shape)
        let editor = AnnotationEditor(scene: scene)
        scene.select([shape.id])

        let beforeMove = scene.snapshot
        _ = editor.beginInteraction(
            at: CGPoint(x: 20, y: 20),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(editor.stateKind == .moving, "Expected selected body drag to enter moving")
        editor.updateInteraction(to: CGPoint(x: 25, y: 30), modifiers: [])
        editor.updateInteraction(to: CGPoint(x: 40, y: 50), modifiers: [])
        editor.endInteraction(at: CGPoint(x: 40, y: 50), modifiers: [])
        guard case .shape(let movedShape) = scene.element(withID: shape.id)?.geometry else {
            throw SelfTestError.failure("Expected moved shape geometry")
        }
        try expect(
            movedShape.start == CGPoint(x: 30, y: 40)
                && movedShape.end == CGPoint(x: 70, y: 70),
            "Expected move drag to apply the final total delta"
        )
        try expect(scene.undo(), "Expected move drag to be undoable")
        try expect(
            scene.snapshot == beforeMove,
            "Expected one undo to revert every update in a move drag"
        )
        try expect(scene.redo(), "Expected move drag redo")

        guard let movedElement = scene.element(withID: shape.id),
              let resizeHandle = AnnotationGeometry.selectionDecoration(
                  for: movedElement,
                  zoomScale: 1
              )?.handles.first(where: { $0.kind == .bottomTrailing }) else {
            throw SelfTestError.failure("Expected a resize handle")
        }
        let beforeResize = scene.snapshot
        _ = editor.beginInteraction(
            at: resizeHandle.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(editor.stateKind == .resizing, "Expected handle drag to enter resizing")
        editor.updateInteraction(
            to: CGPoint(x: resizeHandle.center.x + 10, y: resizeHandle.center.y + 5),
            modifiers: []
        )
        editor.updateInteraction(
            to: CGPoint(x: resizeHandle.center.x + 20, y: resizeHandle.center.y + 15),
            modifiers: []
        )
        editor.endInteraction(
            at: CGPoint(x: resizeHandle.center.x + 20, y: resizeHandle.center.y + 15),
            modifiers: []
        )
        guard let resizedElement = scene.element(withID: shape.id) else {
            throw SelfTestError.failure("Expected resized element")
        }
        try expect(
            AnnotationGeometry.localBounds(of: resizedElement).width
                > AnnotationGeometry.localBounds(of: movedElement).width,
            "Expected resize drag to enlarge the selected shape"
        )
        try expect(scene.undo(), "Expected resize drag to be undoable")
        try expect(
            scene.snapshot == beforeResize,
            "Expected one undo to revert every update in a resize drag"
        )

        guard let rotationElement = scene.element(withID: shape.id),
              let rotationHandle = AnnotationGeometry.selectionDecoration(
                  for: rotationElement,
                  zoomScale: 1
              )?.handles.first(where: { $0.kind == .rotation }) else {
            throw SelfTestError.failure("Expected a rotation handle")
        }
        let rotationBounds = AnnotationGeometry.worldBounds(
            of: rotationElement,
            includingStroke: false
        )
        let beforeRotate = scene.snapshot
        _ = editor.beginInteraction(
            at: rotationHandle.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(editor.stateKind == .rotating, "Expected rotation handle drag to enter rotating")
        editor.endInteraction(
            at: CGPoint(x: rotationBounds.maxX + 30, y: rotationBounds.midY),
            modifiers: [.shift]
        )
        try expect(
            scene.element(withID: shape.id)?.metadata.rotation != 0,
            "Expected rotation drag to update element rotation"
        )
        try expect(scene.undo(), "Expected rotation drag to be undoable")
        try expect(
            scene.snapshot == beforeRotate,
            "Expected one undo to revert the complete rotation drag"
        )

        let beforeOptionDuplicate = scene.snapshot
        _ = editor.beginInteraction(
            at: CGPoint(x: 40, y: 50),
            zoomScale: 1,
            modifiers: [.option],
            clickCount: 1
        )
        editor.updateInteraction(to: CGPoint(x: 45, y: 55), modifiers: [.option])
        editor.endInteraction(at: CGPoint(x: 60, y: 70), modifiers: [.option])
        try expect(
            scene.elements.count == 2
                && editor.selectedElementIDs.count == 1
                && !editor.selectedElementIDs.contains(shape.id),
            "Expected Option-drag to duplicate and select the moved copy"
        )
        try expect(scene.undo(), "Expected Option-drag duplication to be undoable")
        try expect(
            scene.snapshot == beforeOptionDuplicate,
            "Expected one undo to remove the duplicate and its complete drag"
        )

        scene.select([shape.id])
        editor.toggleSelectionLock()
        let lockedSnapshot = scene.snapshot
        _ = editor.beginInteraction(
            at: CGPoint(x: 40, y: 50),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.endInteraction(at: CGPoint(x: 80, y: 90), modifiers: [])
        editor.deleteSelection()
        try expect(
            scene.snapshot == lockedSnapshot && scene.element(withID: shape.id) != nil,
            "Expected locked elements to ignore transforms and deletion"
        )
    }

    private static func testDestinationSpaceDuplicateOffset() throws {
        let destinationOffset = AppCommand.defaultDuplicateDestinationOffset
        for zoomScale in [CGFloat(1), 2, 4, 8] {
            let contentOffset = ZoomCanvasView.annotationContentOffset(
                forDestinationOffset: destinationOffset,
                zoomScale: zoomScale
            )
            try expect(
                approximatelyEqual(
                    CGPoint(
                        x: contentOffset.x * zoomScale,
                        y: contentOffset.y * zoomScale
                    ),
                    destinationOffset
                ),
                "Expected duplicate actions to retain a 10-point destination-space offset at \(zoomScale)x"
            )
        }
    }

    private static func testTextResizeUsesUniformHandlesAndScale() throws {
        let text = AnnotationElement(
            geometry: .text(
                AnnotationTextGeometry(
                    origin: CGPoint(x: 20, y: 20),
                    bounds: nil,
                    text: "Resize me",
                    fontSize: 20,
                    fontName: "",
                    alignment: .left,
                    isEditing: false
                )
            ),
            style: AnnotationStyle.default
        )
        let scene = AnnotationScene(elements: [text])
        let editor = AnnotationEditor(scene: scene)
        scene.select([text.id])
        guard let before = AnnotationGeometry.selectionDecoration(for: text, zoomScale: 1),
              let dragged = before.handles.first(where: { $0.kind == .bottomTrailing }),
              let fixed = before.handles.first(where: { $0.kind == .topLeading }) else {
            throw SelfTestError.failure("Expected text resize handles")
        }
        try expect(
            before.handles.map(\.kind) == [
                .topLeading,
                .topTrailing,
                .bottomTrailing,
                .bottomLeading,
                .rotation
            ],
            "Expected text selection to expose only uniform corner resize handles"
        )

        let target = CGPoint(
            x: fixed.center.x + (dragged.center.x - fixed.center.x) * 1.5,
            y: fixed.center.y + (dragged.center.y - fixed.center.y) * 1.5
        )
        _ = editor.beginInteraction(
            at: dragged.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        editor.endInteraction(at: target, modifiers: [])

        guard let resized = scene.element(withID: text.id),
              case .text(let resizedText) = resized.geometry,
              let after = AnnotationGeometry.selectionDecoration(for: resized, zoomScale: 1),
              let draggedAfter = after.handles.first(where: { $0.kind == .bottomTrailing }),
              let fixedAfter = after.handles.first(where: { $0.kind == .topLeading }) else {
            throw SelfTestError.failure("Expected uniformly resized text")
        }
        try expect(
            approximatelyEqual(fixedAfter.center, fixed.center)
                && approximatelyEqual(draggedAfter.center, target, tolerance: 0.05),
            "Expected text selection bounds to land on the requested uniform resize handle"
        )
        try expect(
            approximatelyEqual(resizedText.fontSize, 30, tolerance: 0.05)
                && approximatelyEqual(resizedText.bounds ?? .zero, CGRect(
                    x: fixed.center.x,
                    y: fixed.center.y,
                    width: target.x - fixed.center.x,
                    height: target.y - fixed.center.y
                ), tolerance: 0.05),
            "Expected text resize to scale the font consistently into the requested bounds"
        )

        let resizedBounds = AnnotationGeometry.worldBounds(
            of: resized,
            includingStroke: false
        )
        let outcome = editor.beginInteraction(
            at: CGPoint(x: resizedBounds.midX, y: resizedBounds.midY),
            zoomScale: 1,
            modifiers: [],
            clickCount: 2
        )
        try expect(
            outcome == .beginTextEditing(text.id),
            "Expected resized text to remain editable by double-clicking"
        )
    }

    private static func testRotatedResizeCoordinateSpaces() throws {
        var style = AnnotationStyle.default
        style.fillStyle = .solid
        var rotated = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 50)],
            style: style
        )
        rotated.metadata.rotation = .pi / 4
        let singleScene = AnnotationScene(elements: [rotated])
        let singleEditor = AnnotationEditor(scene: singleScene)
        singleScene.select([rotated.id])
        guard let singleBefore = AnnotationGeometry.selectionDecoration(
            for: rotated,
            zoomScale: 1
        ),
        let draggedHandle = singleBefore.handles.first(where: { $0.kind == .bottomTrailing }),
        let fixedHandle = singleBefore.handles.first(where: { $0.kind == .topLeading }) else {
            throw SelfTestError.failure("Expected rotated single-selection resize handles")
        }

        _ = singleEditor.beginInteraction(
            at: draggedHandle.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        singleEditor.endInteraction(
            at: CGPoint(x: draggedHandle.center.x + 24, y: draggedHandle.center.y + 18),
            modifiers: []
        )
        guard let resizedSingle = singleScene.element(withID: rotated.id),
              let singleAfter = AnnotationGeometry.selectionDecoration(
                  for: resizedSingle,
                  zoomScale: 1
              ),
              let fixedAfter = singleAfter.handles.first(where: { $0.kind == .topLeading }) else {
            throw SelfTestError.failure("Expected resized rotated single selection")
        }
        try expect(
            approximatelyEqual(fixedAfter.center, fixedHandle.center),
            "Expected inverse/forward rotation composition to keep the opposite single handle fixed"
        )

        var first = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 90), CGPoint(x: 70, y: 120)],
            style: style
        )
        first.metadata.rotation = .pi / 6
        var second = AnnotationElement.legacy(
            tool: .ellipse,
            points: [CGPoint(x: 110, y: 80), CGPoint(x: 160, y: 130)],
            style: style
        )
        second.metadata.rotation = -.pi / 5
        let multiScene = AnnotationScene(elements: [first, second])
        let multiEditor = AnnotationEditor(scene: multiScene)
        multiScene.select([first.id, second.id])
        guard let multiBefore = AnnotationGeometry.selectionDecoration(
            for: [first, second],
            zoomScale: 1
        ),
        let multiDragged = multiBefore.handles.first(where: { $0.kind == .bottomTrailing }),
        let multiFixed = multiBefore.handles.first(where: { $0.kind == .topLeading }) else {
            throw SelfTestError.failure("Expected rotated multi-selection resize handles")
        }

        _ = multiEditor.beginInteraction(
            at: multiDragged.center,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        multiEditor.endInteraction(
            at: CGPoint(x: multiDragged.center.x + 35, y: multiDragged.center.y + 25),
            modifiers: []
        )
        let resizedMulti = multiScene.elements.filter {
            [first.id, second.id].contains($0.id)
        }
        guard let multiAfter = AnnotationGeometry.selectionDecoration(
            for: resizedMulti,
            zoomScale: 1
        ),
        let multiFixedAfter = multiAfter.handles.first(where: { $0.kind == .topLeading }) else {
            throw SelfTestError.failure("Expected resized rotated multi selection")
        }
        try expect(
            approximatelyEqual(multiFixedAfter.center, multiFixed.center),
            "Expected rotated multi-selection resize to keep the opposite group handle fixed"
        )
    }

    private static func testAnnotationEditorCommandsAndGrouping() throws {
        var style = AnnotationStyle.default
        style.fillStyle = .solid
        let scene = AnnotationScene()
        let first = AnnotationElement.legacy(
            tool: .rectangle,
            points: [.zero, CGPoint(x: 20, y: 20)],
            style: style
        )
        let second = AnnotationElement.legacy(
            tool: .ellipse,
            points: [CGPoint(x: 30, y: 0), CGPoint(x: 50, y: 20)],
            style: style
        )
        let third = AnnotationElement.legacy(
            tool: .diamond,
            points: [CGPoint(x: 60, y: 0), CGPoint(x: 80, y: 20)],
            style: style
        )
        scene.append(first)
        scene.append(second)
        scene.append(third)
        let editor = AnnotationEditor(scene: scene)
        scene.select([first.id, second.id])

        editor.groupSelection()
        guard let sourceGroup = scene.element(withID: first.id)?.metadata.groupIDs.last else {
            throw SelfTestError.failure("Expected group command to assign group metadata")
        }
        try expect(
            scene.element(withID: second.id)?.metadata.groupIDs.last == sourceGroup,
            "Expected grouped selection to share a group ID"
        )

        editor.duplicateSelection(offset: CGPoint(x: 10, y: 10))
        try expect(scene.elements.count == 5, "Expected duplicate to copy every selected element")
        let duplicateIDs = editor.selectedElementIDs
        let duplicateGroups = Set(
            scene.elements
                .filter { duplicateIDs.contains($0.id) }
                .flatMap(\.metadata.groupIDs)
        )
        try expect(
            duplicateIDs.count == 2
                && duplicateGroups.count == 1
                && !duplicateGroups.contains(sourceGroup),
            "Expected duplicated groups to retain grouping without sharing the source group ID"
        )

        editor.ungroupSelection()
        try expect(
            scene.elements
                .filter { duplicateIDs.contains($0.id) }
                .allSatisfy(\.metadata.groupIDs.isEmpty),
            "Expected ungroup to remove group metadata from the selection"
        )

        editor.toggleSelectionLock()
        try expect(
            scene.elements
                .filter { duplicateIDs.contains($0.id) }
                .allSatisfy(\.metadata.isLocked),
            "Expected lock command to lock the selection"
        )
        editor.toggleSelectionLock()

        scene.select([first.id])
        editor.arrangeSelection(.bringToFront)
        try expect(
            scene.elements.last?.id == first.id,
            "Expected bring-to-front to move selection to the top of z-order"
        )
        editor.arrangeSelection(.sendToBack)
        try expect(
            scene.elements.first?.id == first.id,
            "Expected send-to-back to move selection to the bottom of z-order"
        )

        scene.select(duplicateIDs)
        editor.deleteSelection()
        try expect(scene.elements.count == 3, "Expected delete to remove unlocked selected elements")
        try expect(scene.undo(), "Expected delete command to be undoable")
        try expect(scene.elements.count == 5, "Expected undo to restore deleted duplicates")
    }

    private static func testNestedUngroupPreservesInnerGroup() throws {
        let scene = AnnotationScene()
        let first = AnnotationElement.legacy(
            tool: .rectangle,
            points: [.zero, CGPoint(x: 20, y: 20)],
            style: .default
        )
        let second = AnnotationElement.legacy(
            tool: .ellipse,
            points: [CGPoint(x: 30, y: 0), CGPoint(x: 50, y: 20)],
            style: .default
        )
        let third = AnnotationElement.legacy(
            tool: .diamond,
            points: [CGPoint(x: 60, y: 0), CGPoint(x: 80, y: 20)],
            style: .default
        )
        scene.append([first, second, third])
        guard let innerGroup = scene.groupElements(withIDs: [first.id, second.id]),
              let outerGroup = scene.groupElements(withIDs: [first.id, second.id, third.id]) else {
            throw SelfTestError.failure("Expected nested group setup")
        }
        scene.select([first.id, second.id, third.id])
        let editor = AnnotationEditor(scene: scene)
        editor.ungroupSelection()

        try expect(
            scene.element(withID: first.id)?.metadata.groupIDs == [innerGroup]
                && scene.element(withID: second.id)?.metadata.groupIDs == [innerGroup]
                && scene.element(withID: third.id)?.metadata.groupIDs.isEmpty == true,
            "Expected ungroup to remove only the active common outer group"
        )
        try expect(
            scene.elements.allSatisfy { !$0.metadata.groupIDs.contains(outerGroup) },
            "Expected the active outer group ID to be removed from the full selection"
        )
    }

    private static func testAnnotationEditorStateTransitionsAndTextReselection() throws {
        let scene = AnnotationScene()
        let editor = AnnotationEditor(scene: scene)
        editor.beginCreating(tool: .pen)
        try expect(editor.stateKind == .creating, "Expected creation to have an explicit editor state")
        editor.finishCreating()
        try expect(editor.stateKind == .idle, "Expected completing creation to return to idle")

        _ = editor.beginInteraction(
            at: .zero,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        try expect(editor.stateKind == .marqueeSelecting, "Expected marquee state transition")
        editor.cancelInteraction()
        try expect(editor.stateKind == .idle, "Expected cancelling an interaction to return to idle")

        let controller = AnnotationController()
        controller.setInsertionPoint(CGPoint(x: 20, y: 30))
        controller.beginTypingSession(rightAligned: false)
        var observedActiveInsertionDuringStateChange = false
        controller.onStateChanged = {
            observedActiveInsertionDuringStateChange =
                observedActiveInsertionDuringStateChange || controller.isTypingLocked
        }
        controller.insertText("A")
        try expect(
            observedActiveInsertionDuringStateChange,
            "Expected the first text state change to expose the active insertion caret "
                + "so the native I-beam can be hidden immediately"
        )
        controller.finishTypingSession()
        guard let textID = controller.elementSnapshot.first?.id else {
            throw SelfTestError.failure("Expected a committed text element")
        }

        try expect(
            controller.beginEditingText(elementID: textID),
            "Expected an existing text element to re-enter typing"
        )
        try expect(
            controller.editorStateKind == .editingText,
            "Expected text re-selection to enter the editing-text state"
        )
        controller.insertText("B")
        controller.finishTypingSession()
        try expect(
            controller.annotationSnapshot.first?.text == "AB",
            "Expected re-selected text to append through the existing typing path"
        )
        controller.undo()
        try expect(
            controller.annotationSnapshot.first?.text == "A",
            "Expected one undo to revert the complete text re-edit transaction"
        )

        controller.setInsertionPoint(CGPoint(x: 80, y: 30))
        controller.beginTypingSession(rightAligned: true)
        controller.insertText("R")
        controller.finishTypingSession()
        guard case .text(let rightAlignedText) = controller.elementSnapshot.last?.geometry else {
            throw SelfTestError.failure("Expected Shift+T-compatible text geometry")
        }
        try expect(
            rightAlignedText.alignment == .right && rightAlignedText.text == "R",
            "Expected right-aligned typing sessions to retain Shift+T behavior"
        )
    }

    private static func testModeCoordinatorExistingTextEditTransition() throws {
        let defaultsName = "ZoomItMacSelfTest.TextEdit.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw SelfTestError.failure("Could not create text-edit test defaults")
        }
        defaults.removePersistentDomain(forName: defaultsName)

        let settingsStore = UserDefaultsSettingsStore(defaults: defaults)
        let resourceAccess = UserDefaultsUserSelectedResourceAccess(defaults: defaults)
        let annotationController = AnnotationController()
        annotationController.setInsertionPoint(CGPoint(x: 40, y: 50))
        annotationController.beginTypingSession(rightAligned: false)
        annotationController.insertText("A")
        annotationController.finishTypingSession()
        guard let textID = annotationController.elementSnapshot.first?.id else {
            throw SelfTestError.failure("Expected coordinator text-edit setup")
        }
        annotationController.currentTool = .select

        let frame = try makeFrame()
        let viewportController = ZoomViewportController()
        viewportController.configure(for: frame, initialZoom: 1)
        let overlayController = OverlayWindowController(
            userSelectedResourceAccess: resourceAccess
        )
        var modeCoordinator: ModeCoordinator?
        overlayController.show(
            frame: frame,
            viewportController: viewportController,
            annotationController: annotationController,
            smoothImage: true,
            drawingToolbarNormalizedPosition: nil,
            drawingToolbarPlacementDidChange: { _ in },
            commandSink: { command in
                modeCoordinator?.handle(command)
            }
        )
        defer {
            overlayController.close()
            defaults.removePersistentDomain(forName: defaultsName)
        }

        guard let canvas = overlayController.canvasViewForTesting else {
            throw SelfTestError.failure("Expected coordinator test canvas")
        }
        canvas.interactionMode = .drawOnly

        let displayManager = SystemDisplayManager()
        modeCoordinator = ModeCoordinator(
            settingsStore: settingsStore,
            permissionService: SystemPermissionService(),
            displayManager: displayManager,
            captureService: ScreenCaptureKitCaptureService(
                displayManager: displayManager
            ),
            overlayController: overlayController,
            annotationController: annotationController,
            viewportController: viewportController,
            userSelectedResourceAccess: resourceAccess,
            initialMode: .drawOnly
        )
        guard let modeCoordinator else {
            throw SelfTestError.failure("Expected coordinator test instance")
        }

        let insertionWritesBeforeExistingEdit =
            annotationController.insertionPointWriteCountForTesting
        modeCoordinator.handle(.editText(textID))
        try expect(
            modeCoordinator.mode == .typing
                && canvas.interactionMode == .typing
                && annotationController.isTypingLocked
                && annotationController.editorStateKind == .editingText
                && annotationController.elementSnapshot.count == 1
                && overlayController.drawingToolbarIsVisibleForTesting
                && overlayController.drawingInspectorIsVisibleForTesting
                && annotationController.insertionPointWriteCountForTesting
                    == insertionWritesBeforeExistingEdit,
            "Expected drawing-to-typing to retain the existing text target, "
                + "toolbar, inspector, single active caret, and no fresh placement write"
        )

        annotationController.insertText("B")
        guard let click = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 60, y: 60),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvas.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) else {
            throw SelfTestError.failure("Could not create text-edit commit click")
        }
        canvas.mouseDown(with: click)
        try expect(
            modeCoordinator.mode == .drawOnly
                && canvas.interactionMode == .drawOnly
                && annotationController.elementSnapshot.count == 1
                && annotationController.annotationSnapshot.first?.text == "AB"
                && overlayController.drawingToolbarIsVisibleForTesting
                && overlayController.drawingInspectorIsVisibleForTesting,
            "Expected a click to commit the existing text transaction without "
                + "creating a second element or hiding drawing accessories"
        )

        modeCoordinator.handle(.undo)
        try expect(
            annotationController.elementSnapshot.count == 1
                && annotationController.annotationSnapshot.first?.text == "A",
            "Expected one undo to revert the coordinator-driven text edit"
        )
        modeCoordinator.handle(.redo)
        try expect(
            annotationController.elementSnapshot.count == 1
                && annotationController.annotationSnapshot.first?.text == "AB",
            "Expected redo to restore the coordinator-driven text edit"
        )

        modeCoordinator.handle(.editText(textID))
        annotationController.insertText("C")
        guard let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvas.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else {
            throw SelfTestError.failure("Could not create text-edit Escape event")
        }
        canvas.keyDown(with: escape)
        try expect(
            modeCoordinator.mode == .drawOnly
                && annotationController.elementSnapshot.count == 1
                && annotationController.annotationSnapshot.first?.text == "ABC",
            "Expected Escape to commit the existing text transaction"
        )

        let freshInsertionPoint = CGPoint(x: 146.5, y: 212.25)
        let writesBeforeFreshTyping =
            annotationController.insertionPointWriteCountForTesting
        modeCoordinator.handle(
            .toggleTyping(
                rightAligned: false,
                insertionPoint: freshInsertionPoint
            )
        )
        try expect(
            modeCoordinator.mode == .typing
                && !annotationController.isTypingLocked
                && annotationController.typingCaret()?.origin
                    == freshInsertionPoint
                && annotationController.insertionPointWriteCountForTesting
                    == writesBeforeFreshTyping + 1,
            "Expected the fresh T flow to write its explicit insertion point "
                + "exactly once before publishing typing mode"
        )
        annotationController.insertText("N")
        canvas.keyDown(with: escape)
        try expect(
            annotationController.elementSnapshot.count == 2
                && annotationController.annotationSnapshot.first?.text == "ABC"
                && annotationController.annotationSnapshot.last?.text == "N"
                && annotationController.annotationSnapshot.last?.points
                    == [freshInsertionPoint],
            "Expected fresh T typing to keep creating a new text element"
        )

        modeCoordinator.handle(.editText(AnnotationElementID()))
        try expect(
            modeCoordinator.mode == .drawOnly
                && canvas.interactionMode == .drawOnly
                && overlayController.drawingToolbarIsVisibleForTesting,
            "Expected a failed existing-text edit to restore the prior canvas and mode"
        )
    }

    private static func testSingleOwnerTextInsertionPlacement() throws {
        let displayOrigins = [
            CGPoint(x: 420, y: 180),
            CGPoint(x: -1_440, y: -760)
        ]
        let modes: [AppMode] = [.staticZoom, .liveZoom, .drawOnly]
        let clickPoint = CGPoint(x: 112.25, y: 86.75)

        for mode in modes {
            for zoom in [CGFloat(1), 2, 4] {
                for backingScale in [CGFloat(1), 2] {
                    for displayOrigin in displayOrigins {
                        let displayFrame = CGRect(
                            origin: displayOrigin,
                            size: CGSize(width: 320, height: 240)
                        )
                        let frame = try makeFrame(
                            displayFrame: displayFrame,
                            scaleFactor: backingScale
                        )
                        let viewportController = ZoomViewportController()
                        viewportController.configure(
                            for: frame,
                            initialZoom: zoom
                        )
                        let annotationController = AnnotationController()
                        annotationController.currentTool = .text
                        var receivedCommand: AppCommand?
                        var canvasReference: ZoomCanvasView?
                        let canvas = ZoomCanvasView(
                            frame: CGRect(origin: .zero, size: displayFrame.size),
                            capturedFrame: frame,
                            viewportController: viewportController,
                            annotationController: annotationController,
                            smoothImage: true,
                            userSelectedResourceAccess:
                                UserDefaultsUserSelectedResourceAccess(),
                            commandSink: { command in
                                receivedCommand = command
                                guard case .toggleTyping(
                                    let rightAligned,
                                    let insertionPoint?
                                ) = command else {
                                    return
                                }
                                annotationController.setInsertionPoint(
                                    insertionPoint
                                )
                                annotationController.beginTypingSession(
                                    rightAligned: rightAligned
                                )
                                canvasReference?.interactionMode = .typing
                            }
                        )
                        canvasReference = canvas
                        let host = NSWindow(
                            contentRect: displayFrame,
                            styleMask: [.borderless],
                            backing: .buffered,
                            defer: false
                        )
                        host.contentView = canvas
                        host.orderFront(nil)
                        host.makeFirstResponder(canvas)
                        canvas.interactionMode = mode
                        if mode != .drawOnly {
                            canvas.toggleDrawingMode()
                        }

                        let pointerScreenLocation = CGPoint(
                            x: displayFrame.minX + clickPoint.x,
                            y: displayFrame.maxY - clickPoint.y
                        )
                        canvas.setPointerForTesting(
                            viewPoint: clickPoint,
                            screenLocation: pointerScreenLocation
                        )
                        let expectedInsertion = viewportController.contentPoint(
                            for: clickPoint,
                            destinationBounds: canvas.bounds,
                            cursorLocation: pointerScreenLocation
                        )
                        let eventLocation = canvas.convert(clickPoint, to: nil)
                        guard let click = NSEvent.mouseEvent(
                            with: .leftMouseDown,
                            location: eventLocation,
                            modifierFlags: [],
                            timestamp: 0,
                            windowNumber: host.windowNumber,
                            context: nil,
                            eventNumber: 1,
                            clickCount: 1,
                            pressure: 0
                        ) else {
                            host.orderOut(nil)
                            throw SelfTestError.failure(
                                "Could not synthesize exact Text placement click"
                            )
                        }
                        canvas.mouseDown(with: click)
                        annotationController.insertText("X")
                        defer { host.orderOut(nil) }

                        guard case .toggleTyping(
                            rightAligned: false,
                            insertionPoint: let commandInsertion?
                        ) = receivedCommand else {
                            throw SelfTestError.failure(
                                "Expected Text click to carry an explicit insertion point"
                            )
                        }
                        let placedOrigin =
                            annotationController.annotationSnapshot.last?.points.first
                        let context = "\(mode), zoom \(zoom), backing "
                            + "\(backingScale), display \(displayOrigin)"
                        try expect(
                            canvas.isFlipped
                                && approximatelyEqual(
                                    commandInsertion,
                                    expectedInsertion,
                                    tolerance: 0.000_001
                                )
                                && placedOrigin.map {
                                    approximatelyEqual(
                                        $0,
                                        expectedInsertion,
                                        tolerance: 0.000_001
                                    )
                                } == true
                                && annotationController
                                    .insertionPointWriteCountForTesting == 1
                                && canvas.interactionMode == .typing
                                && host.firstResponder === canvas,
                            "Expected one-owner exact Text insertion for \(context)"
                        )
                    }
                }
            }
        }

        guard let keyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ) else {
            throw SelfTestError.failure(
                "Could not synthesize the typing shortcut event"
            )
        }
        for mode in [AppMode.drawOnly, .liveZoom] {
            for zoom in [CGFloat(1), 4] {
                for displayOrigin in displayOrigins {
                    let keyboardDisplayFrame = CGRect(
                        origin: displayOrigin,
                        size: CGSize(width: 320, height: 240)
                    )
                    let keyboardFrame = try makeFrame(
                        displayFrame: keyboardDisplayFrame,
                        scaleFactor: 2
                    )
                    let keyboardViewport = ZoomViewportController()
                    keyboardViewport.configure(
                        for: keyboardFrame,
                        initialZoom: zoom
                    )
                    let keyboardController = AnnotationController()
                    var keyboardCommand: AppCommand?
                    let keyboardCanvas = ZoomCanvasView(
                        frame: CGRect(
                            origin: .zero,
                            size: keyboardDisplayFrame.size
                        ),
                        capturedFrame: keyboardFrame,
                        viewportController: keyboardViewport,
                        annotationController: keyboardController,
                        smoothImage: true,
                        userSelectedResourceAccess:
                            UserDefaultsUserSelectedResourceAccess(),
                        commandSink: { keyboardCommand = $0 }
                    )
                    let host = NSWindow(
                        contentRect: keyboardDisplayFrame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    host.contentView = keyboardCanvas
                    host.orderFront(nil)
                    defer { host.orderOut(nil) }

                    let frozenZoomAnchor = CGPoint(
                        x: keyboardDisplayFrame.minX + 48,
                        y: keyboardDisplayFrame.maxY - 38
                    )
                    keyboardCanvas.setPointerForTesting(
                        viewPoint: .zero,
                        screenLocation: frozenZoomAnchor
                    )
                    let activationViewPoint = CGPoint(x: 91.5, y: 74.25)
                    let activationScreenPoint = CGPoint(
                        x: keyboardDisplayFrame.minX + activationViewPoint.x,
                        y: keyboardDisplayFrame.maxY - activationViewPoint.y
                    )
                    keyboardCanvas.setMouseLocationForTesting(
                        activationScreenPoint
                    )
                    keyboardCanvas.interactionMode = mode
                    if mode == .liveZoom {
                        keyboardCanvas.toggleDrawingMode()
                    }
                    try expect(
                        approximatelyEqual(
                            keyboardCanvas.pointerViewPointForTesting,
                            activationViewPoint,
                            tolerance: 0.000_001
                        ),
                        "Expected \(mode) drawing activation to synchronize the "
                            + "nonzero global cursor for display \(displayOrigin)"
                    )

                    let movedViewPoint = CGPoint(x: 236.75, y: 168.5)
                    let movedScreenPoint = CGPoint(
                        x: keyboardDisplayFrame.minX + movedViewPoint.x,
                        y: keyboardDisplayFrame.maxY - movedViewPoint.y
                    )
                    keyboardCanvas.setMouseLocationForTesting(movedScreenPoint)
                    let expectedKeyboardInsertion =
                        keyboardViewport.contentPoint(
                            for: movedViewPoint,
                            destinationBounds: keyboardCanvas.bounds,
                            cursorLocation: frozenZoomAnchor
                        )
                    keyboardCanvas.keyDown(with: keyEvent)
                    guard case .toggleTyping(
                        rightAligned: false,
                        insertionPoint: let keyboardInsertion?
                    ) = keyboardCommand else {
                        throw SelfTestError.failure(
                            "Expected T to carry one resolved pointer insertion"
                        )
                    }
                    try expect(
                        approximatelyEqual(
                            keyboardInsertion,
                            expectedKeyboardInsertion,
                            tolerance: 0.000_001
                        ),
                        "Expected keyboard T after \(mode) activation to use the "
                            + "moved global cursor without changing the frozen "
                            + "zoom anchor at \(zoom)x on display \(displayOrigin)"
                    )
                }
            }
        }
    }

    private static func testLockedTextEditingBoundaries() throws {
        var lockedText = AnnotationElement.legacy(
            tool: .text,
            points: [CGPoint(x: 20, y: 30)],
            style: .default,
            text: "Locked",
            fontSize: 24
        )
        lockedText.metadata.isLocked = true
        let scene = AnnotationScene(elements: [lockedText])
        let editor = AnnotationEditor(scene: scene)
        let bounds = AnnotationGeometry.localBounds(of: lockedText)
        let textPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let outcome = editor.beginInteraction(
            at: textPoint,
            zoomScale: 1,
            modifiers: [],
            clickCount: 2
        )
        try expect(
            outcome == .none && editor.stateKind != .editingText,
            "Expected the editor boundary to reject double-click editing for locked text"
        )
        editor.beginTextEditing(elementID: lockedText.id)
        try expect(
            editor.stateKind != .editingText,
            "Expected direct editor text-edit entry to reject locked text"
        )

        let controller = AnnotationController()
        controller.setInsertionPoint(CGPoint(x: 40, y: 40))
        controller.beginTypingSession(rightAligned: false)
        controller.insertText("Locked")
        controller.finishTypingSession()
        guard let textID = controller.elementSnapshot.first?.id else {
            throw SelfTestError.failure("Expected controller locked-text setup")
        }
        controller.currentTool = .select
        _ = controller.beginSelectionInteraction(
            at: CGPoint(x: 45, y: 45),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        controller.endSelectionInteraction(at: CGPoint(x: 45, y: 45), modifiers: [])
        controller.toggleSelectionLock()
        try expect(
            controller.elementSnapshot.first?.metadata.isLocked == true
                && !controller.beginEditingText(elementID: textID),
            "Expected the controller boundary to reject locked text editing"
        )
    }

    private static func testDrawingToolbarStateMapping() throws {
        let controller = AnnotationController()
        controller.currentTool = .rectangle
        controller.setStrokeColor(.palette(.blue))
        controller.setFillStyle(.solid)
        controller.setFillColor(.palette(.yellow))
        controller.setStrokeWidth(6)
        controller.setSloppiness(.cartoonist)

        let idle = DrawingToolbarState(annotationController: controller)
        try expect(idle.currentTool == .rectangle, "Expected toolbar to mirror the current tool")
        try expect(idle.strokeColor == .value(.palette(.blue)), "Expected toolbar to mirror stroke color")
        try expect(idle.fillStyle == .value(.solid), "Expected toolbar to mirror fill mode")
        try expect(idle.strokeWidth == .value(6), "Expected toolbar to mirror stroke width")
        try expect(
            idle.sloppiness == .value(.cartoonist),
            "Expected toolbar to mirror the current sloppiness"
        )
        try expect(idle.supportsFill && idle.supportsRoundness, "Expected rectangle style capabilities")
        try expect(
            idle.visibleInspectorSections == [
                .strokeColor,
                .background,
                .fill,
                .strokeWidth,
                .strokeStyle,
                .sloppiness,
                .edges,
                .opacity,
                .layers
            ],
            "Expected a filled rectangle to insert Fill after Background"
        )

        let matrixController = AnnotationController()
        matrixController.setShapeBackground(nil)
        let exactToolMatrices: [(AnnotationTool, [DrawingInspectorSection])] = [
            (.hand, []),
            (.select, []),
            (
                .rectangle,
                [
                    .strokeColor, .background, .strokeWidth, .strokeStyle,
                    .sloppiness, .edges, .opacity, .layers
                ]
            ),
            (
                .diamond,
                [
                    .strokeColor, .background, .strokeWidth, .strokeStyle,
                    .sloppiness, .edges, .opacity, .layers
                ]
            ),
            (
                .ellipse,
                [
                    .strokeColor, .background, .strokeWidth, .strokeStyle,
                    .sloppiness, .opacity, .layers
                ]
            ),
            (
                .arrow,
                [
                    .strokeColor, .strokeWidth, .strokeStyle, .sloppiness,
                    .arrowType, .arrowheads, .arrowheadSize, .opacity, .layers
                ]
            ),
            (
                .line,
                [
                    .strokeColor, .strokeWidth, .strokeStyle, .edges,
                    .opacity, .layers
                ]
            ),
            (.pen, [.strokeColor, .strokeWidth, .smartDraw, .pressure, .opacity]),
            (.highlighter, [.strokeColor, .strokeWidth, .opacity]),
            (
                .text,
                [.strokeColor, .textFont, .textSize, .textAlignment, .opacity, .layers]
            ),
            (.eraser, [])
        ]
        for (tool, expectedSections) in exactToolMatrices {
            matrixController.currentTool = tool
            try expect(
                DrawingToolbarState(annotationController: matrixController)
                    .visibleInspectorSections == expectedSections,
                "Expected exact compact inspector matrix for \(tool)"
            )
        }
        matrixController.currentTool = .rectangle
        matrixController.setShapeBackground(.palette(.pink))
        try expect(
            matrixController.currentStyle.fillColor == .palette(.pink)
                && matrixController.currentStyle.fillStyle == .hachure,
            "Expected a nontransparent Background choice to become immediately visible"
        )
        matrixController.setShapeBackground(nil)
        try expect(
            matrixController.currentStyle.fillStyle == .none,
            "Expected Transparent Background to hide shape fill"
        )
        matrixController.currentTool = .diamond
        matrixController.setEdgeStyle(.round)
        try expect(
            matrixController.currentStyle.roundness == 20
                && DrawingToolbarState(annotationController: matrixController).edgeStyle
                    == .value(.round),
            "Expected Round edges to affect rectangle and diamond geometry"
        )
        let lineEdgeController = AnnotationController()
        lineEdgeController.currentTool = .line
        lineEdgeController.setEdgeStyle(.round)
        try expect(
            lineEdgeController.currentLinearRoute == .curved
                && lineEdgeController.currentStyle.roundness == nil
                && DrawingToolbarState(annotationController: lineEdgeController).edgeStyle
                    == .value(.round),
            "Expected Line Round edges to map to the supported curved linear behavior"
        )

        controller.currentTool = .pen
        controller.setPressureMode(.simulated)
        controller.setSmartDrawEnabled(true)
        try expect(
            DrawingToolbarState(annotationController: controller).visibleInspectorSections
                == [
                    .strokeColor,
                    .strokeWidth,
                    .smartDraw,
                    .opacity
                ],
            "Expected Smart Draw to replace Pressure with the Pen wand control"
        )
        try expect(
            DrawingToolbarState(annotationController: controller).smartDrawEnabled
                && DrawingToolbarState(annotationController: controller).supportsSmartDraw
                && DrawingToolbarState(annotationController: controller).pressureMode
                    == .value(.fixed)
                && DrawingToolbarState(annotationController: controller)
                    .preferredVariablePressureMode == .simulated
                && DrawingToolbarState(annotationController: controller).smartDrawStatusText
                    == "Ready for a shape",
            "Expected Smart Draw to expose an on-state while preserving the prior pressure mode"
        )
        controller.begin(
            at: CGPoint(x: 10, y: 10),
            pressure: 0.8,
            timestamp: 0,
            zoomScale: 1
        )
        guard case .freehand(let smartFreehand) =
            controller.inProgressElementSnapshot?.geometry else {
            throw SelfTestError.failure("Expected an active Smart Draw Pen stroke")
        }
        try expect(
            smartFreehand.samples.allSatisfy { $0.pressure == nil },
            "Expected Smart Draw to expose fixed-pressure samples even for tablet input"
        )
        controller.clear()
        controller.setSmartDrawEnabled(false)
        try expect(
            DrawingToolbarState(annotationController: controller).visibleInspectorSections
                == [.strokeColor, .strokeWidth, .smartDraw, .pressure, .opacity]
                && controller.currentStyle.pressureMode == .simulated,
            "Expected disabling Smart Draw to restore Pen pressure and its inspector section"
        )
        controller.currentTool = .line
        let lineToolState = DrawingToolbarState(annotationController: controller)
        try expect(
            lineToolState.visibleInspectorSections == [
                .strokeColor,
                .strokeWidth,
                .strokeStyle,
                .edges,
                .opacity,
                .layers
            ],
            "Expected Line to expose supported open-linear controls without fill"
        )
        controller.begin(at: .zero, tool: .line)
        controller.beginLinearConstructionFromClick(at: .zero, zoomScale: 1)
        let pendingLineState = DrawingToolbarState(annotationController: controller)
        _ = controller.commitLinearConstructionPoint(
            at: CGPoint(x: 40, y: 0),
            zoomScale: 1
        )
        let finishableLineState = DrawingToolbarState(annotationController: controller)
        try expect(
            pendingLineState.isConstructingLinearPath
                && !pendingLineState.canFinishLinearPath
                && finishableLineState.canFinishLinearPath,
            "Expected toolbar state to expose Finish Path and Cancel Path during construction"
        )
        controller.cancelLinearConstruction()
        let sizeStateController = AnnotationController()
        sizeStateController.currentTool = .line
        sizeStateController.setLinearArrowheadSize(.small)
        sizeStateController.begin(at: CGPoint(x: 0, y: 0), tool: .line)
        sizeStateController.end(at: CGPoint(x: 60, y: 0))
        sizeStateController.setLinearArrowheadSize(.large)
        sizeStateController.begin(at: CGPoint(x: 0, y: 20), tool: .line)
        sizeStateController.end(at: CGPoint(x: 60, y: 20))
        sizeStateController.currentTool = .select
        sizeStateController.selectAll()
        let mixedSizeState = DrawingToolbarState(
            annotationController: sizeStateController
        )
        try expect(
            mixedSizeState.arrowheadSize == .mixed
                && mixedSizeState.visibleInspectorSections.contains(.edges)
                && mixedSizeState.visibleInspectorSections.contains(.arrowheads)
                && mixedSizeState.visibleInspectorSections.contains(.arrowheadSize),
            "Expected selected Line elements to retain route and endpoint controls"
        )
        sizeStateController.toggleSelectionLock()
        try expect(
            DrawingToolbarState(annotationController: sizeStateController)
                .arrowheadSize == .unavailable,
            "Expected arrowhead size to become unavailable for a fully locked selection"
        )
        let mixedLine = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [.zero, CGPoint(x: 80, y: 0)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .none,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        let mixedArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 0, y: 20),
                        CGPoint(x: 80, y: 20)
                    ],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        var lockedArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 0, y: 40),
                        CGPoint(x: 80, y: 40)
                    ],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .triangle,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: .default
        )
        lockedArrow.metadata.isLocked = true
        let mixedLinearController = AnnotationController(
            elements: [mixedLine, mixedArrow, lockedArrow]
        )
        mixedLinearController.currentTool = .select
        mixedLinearController.selectAll()
        let mixedLinearState = DrawingToolbarState(
            annotationController: mixedLinearController
        )
        try expect(
            mixedLinearState.visibleInspectorSections == [
                .strokeColor,
                .strokeWidth,
                .strokeStyle,
                .arrowType,
                .arrowheads,
                .arrowheadSize,
                .opacity,
                .layers
            ]
                && !mixedLinearState.visibleInspectorSections.contains(.edges)
                && mixedLinearState.visibleInspectorSections.contains(.arrowheads)
                && mixedLinearState.visibleInspectorSections.contains(.arrowheadSize),
            "Expected mixed Line and Arrow selections to expose their shared route "
                + "and endpoint controls"
        )
        mixedLinearController.setLinearRoute(.curved)
        let mixedLineRoute: AnnotationLinearRoute? =
            mixedLinearController.elementSnapshot.first {
            $0.id == mixedLine.id
        }.flatMap {
            guard case .linear(let linear) = $0.geometry else { return nil }
            return linear.route
        }
        let mixedArrowRoute: AnnotationLinearRoute? =
            mixedLinearController.elementSnapshot.first {
            $0.id == mixedArrow.id
        }.flatMap {
            guard case .linear(let linear) = $0.geometry else { return nil }
            return linear.route
        }
        let lockedArrowRoute: AnnotationLinearRoute? =
            mixedLinearController.elementSnapshot.first {
            $0.id == lockedArrow.id
        }.flatMap {
            guard case .linear(let linear) = $0.geometry else { return nil }
            return linear.route
        }
        try expect(
            mixedLineRoute == .curved
                && mixedArrowRoute == .curved
                && lockedArrowRoute == .straight,
            "Expected shared route edits to update every unlocked selected linear "
                + "while preserving locked elements"
        )
        controller.currentTool = .text
        let textToolState = DrawingToolbarState(annotationController: controller)
        try expect(
            textToolState.visibleInspectorSections == [
                .strokeColor,
                .textFont,
                .textSize,
                .textAlignment,
                .opacity,
                .layers
            ]
                && textToolState.textFontSize == .value(controller.typingFontSize)
                && textToolState.textAlignment == .value(.left),
            "Expected the text tool to expose only text-specific properties"
        )
        let inspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        let inspectorViewIdentity = ObjectIdentifier(inspector.view)
        let compactRectangleController = AnnotationController()
        compactRectangleController.currentTool = .rectangle
        compactRectangleController.setShapeBackground(nil)
        inspector.update(
            state: DrawingToolbarState(annotationController: compactRectangleController)
        )
        let rectangleInspectorHeight = inspector.preferredContentSize.height
        let rectangleFittingHeight = ceil(inspector.view.fittingSize.height)
        inspector.update(state: lineToolState)
        let lineInspectorHeight = inspector.preferredContentSize.height
        let lineFittingHeight = ceil(inspector.view.fittingSize.height)
        try expect(
            ObjectIdentifier(inspector.view) == inspectorViewIdentity
                && rectangleInspectorHeight == rectangleFittingHeight
                && lineInspectorHeight == lineFittingHeight,
            "Expected the inspector to resize live without rebuilding its interaction view "
                + "while the attached panel hugs its content "
                + "(rectangle \(rectangleInspectorHeight), line \(lineInspectorHeight))"
        )
        controller.currentTool = .select
        try expect(
            DrawingToolbarState(annotationController: controller).visibleInspectorSections.isEmpty,
            "Expected an empty selection inspector to avoid unrelated property sections"
        )

        let mixedController = AnnotationController()
        mixedController.currentTool = .rectangle
        mixedController.setStrokeColor(.palette(.red))
        mixedController.setStrokeWidth(3)
        mixedController.setSloppiness(.architect)
        mixedController.begin(at: CGPoint(x: 10, y: 10))
        mixedController.end(at: CGPoint(x: 40, y: 40))
        mixedController.setStrokeColor(.palette(.green))
        mixedController.setStrokeWidth(10)
        mixedController.setSloppiness(.cartoonist)
        mixedController.begin(at: CGPoint(x: 50, y: 10))
        mixedController.end(at: CGPoint(x: 80, y: 40))
        mixedController.currentTool = .select
        _ = mixedController.beginSelectionInteraction(
            at: CGPoint(x: 12, y: 25),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        mixedController.endSelectionInteraction(at: CGPoint(x: 12, y: 25), modifiers: [])
        _ = mixedController.beginSelectionInteraction(
            at: CGPoint(x: 52, y: 25),
            zoomScale: 1,
            modifiers: [.shift],
            clickCount: 1
        )
        mixedController.endSelectionInteraction(
            at: CGPoint(x: 52, y: 25),
            modifiers: [.shift]
        )
        let mixed = DrawingToolbarState(annotationController: mixedController)
        try expect(mixed.strokeColor == .mixed, "Expected mixed stroke colors for multi-selection")
        try expect(mixed.strokeWidth == .mixed, "Expected mixed stroke widths for multi-selection")
        try expect(mixed.sloppiness == .mixed, "Expected mixed sloppiness for multi-selection")
        try expect(mixed.canGroupSelection, "Expected toolbar grouping state for multi-selection")
        try expect(
            mixed.visibleInspectorSections
                == [
                    .strokeColor,
                    .background,
                    .strokeWidth,
                    .strokeStyle,
                    .sloppiness,
                    .edges,
                    .opacity,
                    .layers
                ],
            "Expected same-type multi-selection to retain the exact rectangle matrix"
        )
        let mixedInspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        mixedInspector.update(state: mixed)
        let mixedGroups = descendantViews(
            of: DrawingMixedIndicatorStackView.self,
            in: mixedInspector.view
        ).filter(\.isMixed)
        let perOptionMixedButtons = descendantViews(
            of: DrawingAppearanceButton.self,
            in: mixedInspector.view
        ).filter(\.isMixed)
        try expect(
            mixedGroups.count >= 3 && perOptionMixedButtons.isEmpty,
            "Expected mixed values to use one capsule per option group, not mark every tile"
        )
        mixedController.setSloppiness(.artist)
        try expect(
            mixedController.selectedElementSnapshot.allSatisfy {
                $0.style.sloppiness == .artist
            },
            "Expected one mixed-selection command to update every applicable element"
        )
        mixedController.undo()
        try expect(
            DrawingToolbarState(annotationController: mixedController).sloppiness == .mixed,
            "Expected one undo to restore all mixed sloppiness values"
        )

        let textController = AnnotationController()
        textController.currentTool = .text
        textController.setInsertionPoint(CGPoint(x: 20, y: 20))
        textController.beginTypingSession(rightAligned: false)
        textController.insertText("Text")
        textController.finishTypingSession()
        textController.currentTool = .select
        _ = textController.beginSelectionInteraction(
            at: CGPoint(x: 22, y: 28),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        textController.endSelectionInteraction(
            at: CGPoint(x: 22, y: 28),
            modifiers: []
        )
        textController.setTextFontSize(42)
        textController.setTextAlignment(.center)
        let selectedText = DrawingToolbarState(annotationController: textController)
        try expect(
            selectedText.visibleInspectorSections == [
                .strokeColor,
                .textFont,
                .textSize,
                .textAlignment,
                .opacity,
                .layers
            ]
                && selectedText.textFontSize == .value(42)
                && selectedText.textAlignment == .value(.center),
            "Expected selected text properties and focused text commands to stay in sync"
        )
    }

    private static func testLockedInspectorActionsAndDefaults() throws {
        let lockedShapeController = AnnotationController()
        lockedShapeController.currentTool = .rectangle
        lockedShapeController.setStrokeColor(.palette(.blue))
        lockedShapeController.setShapeBackground(.palette(.yellow))
        lockedShapeController.setFillStyle(.solid)
        lockedShapeController.setStrokeWidth(6)
        lockedShapeController.setStrokePattern(.dashed)
        lockedShapeController.setSloppiness(.cartoonist)
        lockedShapeController.setOpacity(0.75)
        lockedShapeController.setEdgeStyle(.round)
        lockedShapeController.begin(at: CGPoint(x: 10, y: 10))
        lockedShapeController.end(at: CGPoint(x: 70, y: 70))
        lockedShapeController.currentTool = .select
        lockedShapeController.selectAll()
        lockedShapeController.toggleSelectionLock()

        let lockedShapeState = DrawingToolbarState(
            annotationController: lockedShapeController
        )
        try expect(
            lockedShapeState.selectionIsFullyLocked
                && lockedShapeState.selectionLock == .value(true)
                && lockedShapeState.strokeColor == .unavailable
                && lockedShapeState.fillColor == .unavailable
                && lockedShapeState.fillStyle == .unavailable
                && lockedShapeState.strokeWidth == .unavailable
                && lockedShapeState.strokePattern == .unavailable
                && lockedShapeState.sloppiness == .unavailable
                && lockedShapeState.opacity == .unavailable
                && lockedShapeState.roundness == .unavailable
                && lockedShapeState.edgeStyle == .unavailable
                && lockedShapeState.visibleInspectorSections.contains(.fill)
                && !lockedShapeState.supportsStrokeOptions
                && !lockedShapeState.supportsFill
                && !lockedShapeState.supportsSloppiness
                && !lockedShapeState.supportsRoundness,
            "Expected locked-only shapes to expose unavailable property state"
        )
        let lockedInspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        lockedInspector.update(state: lockedShapeState)
        try expect(
            descendantViews(of: NSButton.self, in: lockedInspector.view)
                .allSatisfy { !$0.isEnabled }
                && descendantViews(of: NSSlider.self, in: lockedInspector.view)
                    .allSatisfy { !$0.isEnabled }
                && descendantViews(of: NSColorWell.self, in: lockedInspector.view)
                    .allSatisfy { !$0.isEnabled },
            "Expected locked-only inspector controls to be disabled"
        )

        guard let lockedShapeBefore = lockedShapeController.elementSnapshot.first else {
            throw SelfTestError.failure("Expected a locked shape")
        }
        let lockedShapeDefaultStyle = lockedShapeController.currentStyle
        let lockedShapeDefaultRoute = lockedShapeController.currentLinearRoute
        let lockedShapeDefaultStart = lockedShapeController.currentStartArrowhead
        let lockedShapeDefaultEnd = lockedShapeController.currentEndArrowhead
        let lockedShapeTypingSize = lockedShapeController.typingFontSize
        let lockedShapeTypingPreset = lockedShapeController.typingFontPreset
        let lockedShapeTypingName = lockedShapeController.typingFontName
        let lockedShapeTypingAlignment = lockedShapeController.typingTextAlignment

        lockedShapeController.setStrokeColor(.palette(.orange))
        lockedShapeController.setShapeBackground(.palette(.pink))
        lockedShapeController.setFillStyle(.crossHatch)
        lockedShapeController.setStrokeWidth(14)
        lockedShapeController.setStrokePattern(.dotted)
        lockedShapeController.setSloppiness(.artist)
        lockedShapeController.setOpacity(0.35)
        lockedShapeController.setRoundness(nil)
        lockedShapeController.setEdgeStyle(.sharp)
        lockedShapeController.setLinearRoute(.elbow)
        lockedShapeController.setLinearArrowheads(start: .circle, end: .diamond)
        lockedShapeController.setTextColor(.palette(.green))
        lockedShapeController.setTextOpacity(0.4)
        lockedShapeController.setTextFontPreset(.rounded)
        lockedShapeController.setTextFontName("Menlo")
        lockedShapeController.setTextFontSize(48)
        lockedShapeController.setTextAlignment(.right)

        try expect(
            lockedShapeController.elementSnapshot.first == lockedShapeBefore
                && lockedShapeController.currentStyle == lockedShapeDefaultStyle
                && lockedShapeController.currentLinearRoute == lockedShapeDefaultRoute
                && lockedShapeController.currentStartArrowhead == lockedShapeDefaultStart
                && lockedShapeController.currentEndArrowhead == lockedShapeDefaultEnd
                && lockedShapeController.typingFontSize == lockedShapeTypingSize
                && lockedShapeController.typingFontPreset == lockedShapeTypingPreset
                && lockedShapeController.typingFontName == lockedShapeTypingName
                && lockedShapeController.typingTextAlignment == lockedShapeTypingAlignment,
            "Expected locked-only and incompatible mutations to preserve elements and defaults"
        )

        let mixedController = AnnotationController()
        mixedController.currentTool = .rectangle
        mixedController.setStrokeColor(.palette(.red))
        mixedController.setShapeBackground(.palette(.pink))
        mixedController.setFillStyle(.hachure)
        mixedController.setStrokeWidth(1)
        mixedController.setStrokePattern(.dashed)
        mixedController.setSloppiness(.architect)
        mixedController.begin(at: CGPoint(x: 10, y: 10))
        mixedController.end(at: CGPoint(x: 60, y: 60))
        mixedController.setStrokeColor(.palette(.green))
        mixedController.setShapeBackground(.palette(.yellow))
        mixedController.setFillStyle(.solid)
        mixedController.setStrokeWidth(6)
        mixedController.setStrokePattern(.dotted)
        mixedController.setSloppiness(.cartoonist)
        mixedController.setEdgeStyle(.round)
        mixedController.begin(at: CGPoint(x: 90, y: 10))
        mixedController.end(at: CGPoint(x: 140, y: 60))
        mixedController.currentTool = .select
        _ = mixedController.beginSelectionInteraction(
            at: CGPoint(x: 12, y: 35),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        mixedController.endSelectionInteraction(
            at: CGPoint(x: 12, y: 35),
            modifiers: []
        )
        mixedController.toggleSelectionLock()
        mixedController.selectAll()

        let editableCommonState = DrawingToolbarState(
            annotationController: mixedController
        )
        try expect(
            editableCommonState.selectionLock == .mixed
                && editableCommonState.strokeColor == .value(.palette(.green))
                && editableCommonState.fillColor == .value(.palette(.yellow))
                && editableCommonState.fillStyle == .value(.solid)
                && editableCommonState.strokeWidth == .value(6)
                && editableCommonState.strokePattern == .value(.dotted)
                && editableCommonState.sloppiness == .value(.cartoonist)
                && editableCommonState.edgeStyle == .value(.round)
                && editableCommonState.supportsStrokeOptions
                && editableCommonState.supportsFill
                && editableCommonState.supportsSloppiness
                && editableCommonState.supportsRoundness,
            "Expected mixed lock selections to resolve properties from unlocked elements only"
        )
        guard let lockedMixedBefore = mixedController.elementSnapshot.first(where: {
            $0.metadata.isLocked
        }) else {
            throw SelfTestError.failure("Expected one locked shape in the mixed selection")
        }

        mixedController.setStrokeColor(.palette(.orange))
        mixedController.setShapeBackground(.palette(.blue))
        mixedController.setFillStyle(.crossHatch)
        mixedController.setStrokeWidth(3)
        mixedController.setStrokePattern(.solid)
        mixedController.setSloppiness(.artist)
        mixedController.setOpacity(0.55)
        mixedController.setEdgeStyle(.sharp)

        guard let lockedMixedAfter = mixedController.elementSnapshot.first(where: {
            $0.metadata.isLocked
        }),
        let editableMixedAfter = mixedController.elementSnapshot.first(where: {
            !$0.metadata.isLocked
        }) else {
            throw SelfTestError.failure("Expected locked and editable mixed-selection shapes")
        }
        try expect(
            lockedMixedAfter == lockedMixedBefore
                && editableMixedAfter.style.strokeColor == .palette(.orange)
                && editableMixedAfter.style.fillColor == .palette(.blue)
                && editableMixedAfter.style.fillStyle == .crossHatch
                && editableMixedAfter.style.strokeWidth == 3
                && editableMixedAfter.style.strokePattern == .solid
                && editableMixedAfter.style.sloppiness == .artist
                && editableMixedAfter.style.opacity == 0.55
                && editableMixedAfter.style.roundness == nil,
            "Expected mixed lock mutations to update only unlocked compatible elements"
        )

        mixedController.currentTool = .rectangle
        mixedController.setStrokeColor(.palette(.blue))
        mixedController.setStrokeWidth(10)
        mixedController.begin(at: CGPoint(x: 170, y: 10))
        mixedController.end(at: CGPoint(x: 220, y: 60))
        mixedController.currentTool = .select
        mixedController.selectAll()
        let editableMixedState = DrawingToolbarState(
            annotationController: mixedController
        )
        try expect(
            editableMixedState.strokeColor == .mixed
                && editableMixedState.strokeWidth == .mixed
                && editableMixedState.selectionLock == .mixed,
            "Expected differing unlocked values to remain visibly mixed while ignoring locked values"
        )

        let textController = AnnotationController()
        textController.currentTool = .text
        textController.setInsertionPoint(CGPoint(x: 20, y: 20))
        textController.beginTypingSession(rightAligned: false)
        textController.insertText("Locked")
        textController.finishTypingSession()
        textController.currentTool = .select
        textController.selectAll()
        guard let unlockedTextBefore = textController.elementSnapshot.first else {
            throw SelfTestError.failure("Expected an unlocked text element")
        }
        let incompatibleStyleBefore = textController.currentStyle
        let incompatibleRouteBefore = textController.currentLinearRoute
        let incompatibleStartBefore = textController.currentStartArrowhead
        let incompatibleEndBefore = textController.currentEndArrowhead
        textController.setFillColor(.palette(.yellow))
        textController.setFillStyle(.solid)
        textController.setStrokeWidth(12)
        textController.setStrokePattern(.dashed)
        textController.setSloppiness(.artist)
        textController.setRoundness(20)
        textController.setEdgeStyle(.round)
        textController.setLinearRoute(.curved)
        textController.setLinearArrowheads(start: .circle, end: .triangle)
        try expect(
            textController.elementSnapshot.first == unlockedTextBefore
                && textController.currentStyle == incompatibleStyleBefore
                && textController.currentLinearRoute == incompatibleRouteBefore
                && textController.currentStartArrowhead == incompatibleStartBefore
                && textController.currentEndArrowhead == incompatibleEndBefore,
            "Expected an unlocked but incompatible selection to preserve unrelated defaults"
        )

        textController.toggleSelectionLock()
        let lockedTextState = DrawingToolbarState(annotationController: textController)
        try expect(
            lockedTextState.strokeColor == .unavailable
                && lockedTextState.opacity == .unavailable
                && lockedTextState.textColor == .unavailable
                && lockedTextState.textOpacity == .unavailable
                && lockedTextState.textFontPreset == .unavailable
                && lockedTextState.textFontName == .unavailable
                && lockedTextState.textFontSize == .unavailable
                && lockedTextState.textAlignment == .unavailable
                && !lockedTextState.supportsTextOptions,
            "Expected locked-only text properties to be unavailable"
        )
        let lockedTextBefore = textController.elementSnapshot.first
        let lockedTextStyleBefore = textController.currentStyle
        let lockedTypingSize = textController.typingFontSize
        let lockedTypingPreset = textController.typingFontPreset
        let lockedTypingName = textController.typingFontName
        let lockedTypingAlignment = textController.typingTextAlignment
        textController.setTextColor(.palette(.green))
        textController.setTextOpacity(0.3)
        textController.setTextFontPreset(.monospaced)
        textController.setTextFontName("Courier")
        textController.setTextFontSize(72)
        textController.setTextAlignment(.right)
        try expect(
            textController.elementSnapshot.first == lockedTextBefore
                && textController.currentStyle == lockedTextStyleBefore
                && textController.typingFontSize == lockedTypingSize
                && textController.typingFontPreset == lockedTypingPreset
                && textController.typingFontName == lockedTypingName
                && textController.typingTextAlignment == lockedTypingAlignment,
            "Expected locked-only text commands to preserve typing defaults"
        )

        let lockedLinearController = AnnotationController()
        lockedLinearController.currentTool = .arrow
        lockedLinearController.setLinearRoute(.curved)
        lockedLinearController.setLinearArrowheads(start: .circle, end: .triangle)
        lockedLinearController.begin(at: CGPoint(x: 10, y: 20))
        lockedLinearController.update(at: CGPoint(x: 120, y: 20))
        lockedLinearController.end(at: CGPoint(x: 120, y: 20))
        lockedLinearController.currentTool = .select
        lockedLinearController.selectAll()
        lockedLinearController.toggleSelectionLock()
        let lockedLinearState = DrawingToolbarState(
            annotationController: lockedLinearController
        )
        let lockedLinearAvailability =
            DrawingToolbarOverflowActionAvailability.enabledStates(
                for: lockedLinearState
            )
        try expect(
            lockedLinearState.linearRoute == .unavailable
                && lockedLinearState.startArrowhead == .unavailable
                && lockedLinearState.endArrowhead == .unavailable
                && !lockedLinearState.supportsLinearOptions
                && !lockedLinearState.canEditLinearPoints
                && !lockedLinearState.canInsertLinearPoint
                && !lockedLinearState.canRemoveLinearPoints
                && !lockedLinearState.canUnbindLinearEndpoints
                && lockedLinearAvailability[DrawingToolbarOverflowActionTitle.editPoints]
                    == false
                && lockedLinearAvailability[DrawingToolbarOverflowActionTitle.insertPoint]
                    == false
                && lockedLinearAvailability[DrawingToolbarOverflowActionTitle.removePoints]
                    == false
                && lockedLinearAvailability[
                    DrawingToolbarOverflowActionTitle.unbindEndpoints
                ] == false,
            "Expected locked-only linear state and overflow actions to be disabled"
        )
        let lockedLinearBefore = lockedLinearController.elementSnapshot.first
        let lockedRouteBefore = lockedLinearController.currentLinearRoute
        let lockedStartBefore = lockedLinearController.currentStartArrowhead
        let lockedEndBefore = lockedLinearController.currentEndArrowhead
        lockedLinearController.setLinearRoute(.elbow)
        lockedLinearController.setLinearArrowheads(start: .bar, end: .diamond)
        try expect(
            lockedLinearController.elementSnapshot.first == lockedLinearBefore
                && lockedLinearController.currentLinearRoute == lockedRouteBefore
                && lockedLinearController.currentStartArrowhead == lockedStartBefore
                && lockedLinearController.currentEndArrowhead == lockedEndBefore,
            "Expected locked-only linear commands to preserve route and arrowhead defaults"
        )

        let editingLinearController = AnnotationController()
        editingLinearController.currentTool = .line
        editingLinearController.begin(at: CGPoint(x: 10, y: 20))
        editingLinearController.update(at: CGPoint(x: 120, y: 20))
        editingLinearController.end(at: CGPoint(x: 120, y: 20))
        editingLinearController.currentTool = .select
        let editingLinearState = DrawingToolbarState(
            annotationController: editingLinearController
        )
        let editingAvailability =
            DrawingToolbarOverflowActionAvailability.enabledStates(
                for: editingLinearState
            )
        try expect(
            editingLinearState.isEditingLinearPoints
                && editingLinearState.canEditLinearPoints
                && !editingLinearState.canInsertLinearPoint
                && !editingLinearState.canRemoveLinearPoints
                && editingAvailability[
                    DrawingToolbarOverflowActionTitle.finishPointEditing
                ] == true
                && editingAvailability[DrawingToolbarOverflowActionTitle.insertPoint]
                    == false
                && editingAvailability[DrawingToolbarOverflowActionTitle.removePoints]
                    == false,
            "Expected overflow point actions to use exact capabilities, not editing state"
        )
        _ = editingLinearController.toggleLinearPointEditing()
        let passiveLinearState = DrawingToolbarState(
            annotationController: editingLinearController
        )
        let passiveAvailability =
            DrawingToolbarOverflowActionAvailability.enabledStates(
                for: passiveLinearState
            )
        try expect(
            passiveLinearState.canEditLinearPoints
                && passiveLinearState.supportsLinearOptions
                && passiveLinearState.hasSelection
                && passiveAvailability[DrawingToolbarOverflowActionTitle.editPoints] == true
                && passiveAvailability[DrawingToolbarOverflowActionTitle.insertPoint] == false
                && passiveAvailability[DrawingToolbarOverflowActionTitle.removePoints] == false
                && passiveAvailability[
                    DrawingToolbarOverflowActionTitle.unbindEndpoints
                ] == false,
            "Expected passive linear overflow actions to reject insert, remove, and unbind no-ops"
        )

        let defaultsController = AnnotationController()
        defaultsController.currentTool = .rectangle
        defaultsController.setStrokeColor(.palette(.orange))
        defaultsController.setShapeBackground(.palette(.pink))
        defaultsController.setFillStyle(.solid)
        defaultsController.setStrokeWidth(14)
        defaultsController.setStrokePattern(.dotted)
        defaultsController.setSloppiness(.artist)
        defaultsController.setOpacity(0.45)
        defaultsController.setEdgeStyle(.round)
        defaultsController.setLinearRoute(.elbow)
        defaultsController.setLinearArrowheads(start: .circle, end: .diamond)
        defaultsController.setTextFontName("Menlo")
        defaultsController.setTextFontSize(48)
        defaultsController.setTextAlignment(.right)
        try expect(
            defaultsController.currentStyle.strokeColor == .palette(.orange)
                && defaultsController.currentStyle.fillColor == .palette(.pink)
                && defaultsController.currentStyle.fillStyle == .solid
                && defaultsController.currentStyle.strokeWidth == 14
                && defaultsController.currentStyle.strokePattern == .dotted
                && defaultsController.currentStyle.sloppiness == .artist
                && defaultsController.currentStyle.opacity == 0.45
                && defaultsController.currentStyle.roundness == 20
                && defaultsController.currentLinearRoute == .elbow
                && defaultsController.currentStartArrowhead == .circle
                && defaultsController.currentEndArrowhead == .diamond
                && defaultsController.typingFontPreset == .typeSetting
                && defaultsController.typingFontName == "Menlo"
                && defaultsController.typingFontSize == 48
                && defaultsController.typingTextAlignment == .right,
            "Expected no-selection commands to continue updating drawing and typing defaults"
        )

        let scopedController = AnnotationController()
        scopedController.currentTool = .rectangle
        scopedController.setStrokeColor(.palette(.orange))
        scopedController.setStrokePattern(.dotted)
        scopedController.currentTool = .pen
        let penState = DrawingToolbarState(annotationController: scopedController)
        scopedController.begin(at: CGPoint(x: 0, y: 0))
        scopedController.end(at: CGPoint(x: 20, y: 0))
        guard let pen = scopedController.elementSnapshot.last else {
            throw SelfTestError.failure("Expected scoped Pen stroke")
        }
        scopedController.currentTool = .highlighter
        let initialHighlighterColor = scopedController.currentStyle.strokeColor
        scopedController.setStrokeColor(.palette(.highlighterPink))
        scopedController.currentStyle.pressureMode = .simulated
        scopedController.begin(at: CGPoint(x: 0, y: 10))
        scopedController.end(at: CGPoint(x: 20, y: 10))
        guard let highlighter = scopedController.elementSnapshot.last else {
            throw SelfTestError.failure("Expected scoped Highlighter stroke")
        }
        scopedController.currentTool = .rectangle
        let restoredRectangleStyle = scopedController.currentStyle
        scopedController.currentTool = .highlighter
        try expect(
            penState.strokePattern == .unavailable
                && pen.style.strokePattern == .solid
                && initialHighlighterColor == .palette(.highlighterYellow)
                && highlighter.style.strokePattern == .solid
                && highlighter.style.pressureMode == .fixed
                && restoredRectangleStyle.strokeColor == .palette(.orange)
                && restoredRectangleStyle.strokePattern == .dotted
                && scopedController.currentStyle.strokeColor
                    == .palette(.highlighterPink),
            "Expected freehand pattern/pressure isolation and independent Highlighter color scope"
        )
    }

    private static func testDrawingInspectorLayoutAndVisibilityPolicy() throws {
        let emptyController = AnnotationController()
        emptyController.currentTool = .select
        let emptyState = DrawingToolbarState(annotationController: emptyController)
        try expect(
            !emptyState.hasInspectorContent
                && !DrawingInspectorPresentationPolicy.shouldShow(
                    hasContent: emptyState.hasInspectorContent
                )
                && DrawingInspectorPresentationPolicy.shouldShow(
                    hasContent: true
                ),
            "Expected inspector visibility to follow property availability only"
        )
        for tool in [AnnotationTool.hand, .eraser] {
            emptyController.currentTool = tool
            try expect(
                !DrawingToolbarState(annotationController: emptyController).hasInspectorContent,
                "Expected \(tool) to omit an empty inspector"
            )
        }

        emptyController.currentTool = .pen
        let penState = DrawingToolbarState(annotationController: emptyController)
        try expect(
            penState.hasInspectorContent
                && DrawingInspectorPresentationPolicy.shouldShow(
                    hasContent: penState.hasInspectorContent
                ),
            "Expected the inspector to reappear when a property-bearing tool becomes active"
        )

        let firstContext = emptyState.inspectorContext
        try expect(
            DrawingInspectorPresentationPolicy.shouldResetScroll(
                from: firstContext,
                to: penState.inspectorContext
            )
                && !DrawingInspectorPresentationPolicy.shouldResetScroll(
                    from: penState.inspectorContext,
                    to: penState.inspectorContext
                ),
            "Expected tool changes to reset inspector scrolling while same-context updates retain it"
        )
        try expect(
            DrawingInspectorDocumentLayout.documentSize(
                contentSize: CGSize(width: 900, height: 280),
                viewportSize: CGSize(width: 208, height: 520)
            ) == CGSize(width: 208, height: 280),
            "Expected inspector documents to remain no wider than the viewport "
                + "without stretching their height"
        )
        try expect(
            DrawingInspectorDocumentLayout.clampedScrollOrigin(
                CGPoint(x: 12, y: 900),
                documentSize: CGSize(width: 900, height: 90),
                viewportSize: CGSize(width: 520, height: 90),
                resetsToOrigin: false
            ) == .zero
                && DrawingInspectorDocumentLayout.clampedScrollOrigin(
                    CGPoint(x: 200, y: 0),
                    documentSize: CGSize(width: 900, height: 90),
                    viewportSize: CGSize(width: 520, height: 90),
                    resetsToOrigin: true
                ) == .zero,
            "Expected attached inspector documents to stay pinned to the viewport origin"
        )
        try expect(
            DrawingInspectorDocumentLayout.clampedScrollOrigin(
                CGPoint(x: 40, y: 900),
                documentSize: CGSize(width: 208, height: 600),
                viewportSize: CGSize(width: 208, height: 200),
                resetsToOrigin: false
            ) == CGPoint(x: 0, y: 400)
                && DrawingInspectorDocumentLayout.clampedScrollOrigin(
                    CGPoint(x: 0, y: -20),
                    documentSize: CGSize(width: 208, height: 600),
                    viewportSize: CGSize(width: 208, height: 200),
                    resetsToOrigin: false
                ) == .zero,
            "Expected vertical inspector scrolling to clamp within the document"
        )

        let inspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        inspector.update(state: penState)
        let frames = inspector.visibleSectionFramesForTesting()
        let penLayout = DrawingInspectorSectionMatrix
            .DrawingToolbarHorizontalSectionPacker.layout(
                sections: penState.visibleInspectorSections,
                availableWidth:
                    DrawingInspectorVisualMetrics.attachedMaximumWidth
                        - DrawingInspectorVisualMetrics.attachedHorizontalChrome
            )
        try expect(
            Set(frames.keys) == Set(penState.visibleInspectorSections),
            "Expected hidden inspector sections to detach completely "
                + "(actual \(Array(frames.keys)), expected \(penState.visibleInspectorSections))"
        )
        try expect(
            frames.values.allSatisfy { $0.height > 0 }
                && penLayout.rows.count <= 2,
            "Expected attached Pen sections to occupy at most two compact rows: \(frames)"
        )

        func verifyTitleLayout(
            availableWidth: CGFloat,
            expectedRows: Int
        ) throws {
            inspector.setAvailableHorizontalWidth(availableWidth)
            inspector.update(state: penState)
            let layout = DrawingInspectorSectionMatrix
                .DrawingToolbarHorizontalSectionPacker.layout(
                    sections: penState.visibleInspectorSections,
                    availableWidth: availableWidth
                )
            guard let title = descendantViews(
                of: NSTextField.self,
                in: inspector.view
            ).first(where: { $0.stringValue == DrawingInspectorSection.opacity.title }) else {
                throw SelfTestError.failure("Expected the Opacity section title")
            }
            title.layoutSubtreeIfNeeded()
            guard let representation = title.bitmapImageRepForCachingDisplay(
                in: title.bounds
            ) else {
                throw SelfTestError.failure("Could not rasterize the Opacity title")
            }
            title.cacheDisplay(in: title.bounds, to: representation)
            let paintedRows = (0..<representation.pixelsHigh).filter { y in
                (0..<representation.pixelsWide).contains { x in
                    (representation.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
                }
            }
            guard let firstPaintedRow = paintedRows.first,
                  let lastPaintedRow = paintedRows.last else {
                throw SelfTestError.failure("Expected rendered Opacity title pixels")
            }
            let scale = CGFloat(representation.pixelsHigh) / title.bounds.height
            let baseline = title.isFlipped
                ? title.firstBaselineOffsetFromTop * scale
                : title.lastBaselineOffsetFromBottom * scale
            let hasDescenderPixels = title.isFlipped
                ? CGFloat(lastPaintedRow) > baseline
                : CGFloat(firstPaintedRow) < baseline
            try expect(
                layout.rows.count == expectedRows
                    && inspector.preferredContentSize.height
                        == ceil(inspector.view.fittingSize.height)
                    && title.intrinsicContentSize.height >= 14
                    && title.frame.height >= 14
                    && title.firstBaselineOffsetFromTop > 0
                    && title.lastBaselineOffsetFromBottom > 0
                    && firstPaintedRow > 0
                    && lastPaintedRow < representation.pixelsHigh - 1
                    && hasDescenderPixels,
                "Expected \(expectedRows)-row titles to preserve intrinsic height, "
                    + "baseline, and rendered descenders without clipping"
            )
        }
        try verifyTitleLayout(availableWidth: 900, expectedRows: 1)
        try verifyTitleLayout(availableWidth: 420, expectedRows: 2)

        let layoutWidths: [CGFloat] = [1_440, 1_280, 1_024, 800, 600]
        let matrixTools: [AnnotationTool] = [
            AnnotationTool.rectangle, .diamond, .ellipse, .arrow, .line, .pen, .text
        ] + [.highlighter]
        for screenWidth in layoutWidths {
            let panelWidth = min(
                DrawingInspectorVisualMetrics.attachedMaximumWidth,
                screenWidth - DrawingAttachedInspectorPlacement.screenMargin * 2
            )
            let availableWidth = panelWidth
                - DrawingInspectorVisualMetrics.attachedHorizontalChrome
            for tool in matrixTools {
                try autoreleasepool {
                    let matrixInspector = DrawingPropertiesController(
                        commandSink: { _ in },
                        colorPanelActivityChanged: { _ in }
                    )
                    let fillVariants = [.rectangle, .diamond, .ellipse].contains(tool)
                        ? [false, true, false]
                        : [false]
                    var transitionHeights: [CGFloat] = []
                    var transitionLayouts:
                        [DrawingInspectorSectionMatrix.DrawingToolbarHorizontalSectionLayout] = []
                    for showsFill in fillVariants {
                        let controller = AnnotationController()
                        controller.currentTool = tool
                        controller.setShapeBackground(
                            showsFill ? .palette(.backgroundRed) : nil
                        )
                        let state = DrawingToolbarState(annotationController: controller)
                        matrixInspector.setAvailableHorizontalWidth(availableWidth)
                        matrixInspector.update(state: state)
                        let frames = matrixInspector.visibleSectionFramesForTesting()
                        transitionHeights.append(matrixInspector.preferredContentSize.height)
                        let layout = matrixInspector.sectionLayoutForTesting
                        transitionLayouts.append(layout)
                        let frameValues = Array(frames.values)
                        let rootBounds = matrixInspector.view.bounds.insetBy(
                            dx: -0.5,
                            dy: -0.5
                        )
                        let sectionsDoNotOverlap = frameValues.indices.allSatisfy { index in
                            frameValues.indices.dropFirst(index + 1).allSatisfy {
                                !frameValues[index].intersects(frameValues[$0])
                            }
                        }
                        let visibleDescendants = descendantViews(
                            of: NSView.self,
                            in: matrixInspector.view
                        ).filter {
                            $0 !== matrixInspector.view
                                && !($0.superview is NSTextField)
                                && !$0.isHidden
                                && !$0.frame.isEmpty
                        }
                        let descendantsFit = visibleDescendants.allSatisfy {
                            rootBounds.contains(
                                frame($0, convertedTo: matrixInspector.view)
                            )
                        }
                        let clippedDescendants = visibleDescendants.compactMap {
                            view -> String? in
                            let frame = frame(
                                view,
                                convertedTo: matrixInspector.view
                            )
                            return rootBounds.contains(frame)
                                ? nil
                                : "\(type(of: view)) \(frame)"
                        }

                        let card = DrawingInspectorView(propertiesView: matrixInspector.view)
                        card.frame = CGRect(
                            origin: .zero,
                            size: CGSize(
                                width: matrixInspector.preferredContentSize.width
                                    + DrawingInspectorVisualMetrics.attachedHorizontalChrome,
                                height: matrixInspector.preferredContentSize.height
                                    + DrawingInspectorVisualMetrics.attachedVerticalInset * 2
                            )
                        )
                        card.update(
                            state: state,
                            contentSize: matrixInspector.preferredContentSize
                        )
                        card.layoutSubtreeIfNeeded()

                        try expect(
                            layout.rows.count >= 1
                                && layout.rows.count <= 3
                                && layout.rows.flatMap { $0 }
                                    == state.visibleInspectorSections
                                && layout.documentWidth <= availableWidth
                                && layout.rowWidths.allSatisfy {
                                    $0 <= availableWidth + 0.5
                                }
                                && matrixInspector.preferredContentSize.width
                                    == layout.documentWidth
                                && matrixInspector.preferredContentSize.height.isFinite
                                && matrixInspector.preferredContentSize.height
                                    == ceil(matrixInspector.view.fittingSize.height)
                                && Set(frames.keys) == Set(state.visibleInspectorSections)
                                && frameValues.allSatisfy {
                                    !$0.isEmpty && rootBounds.contains($0)
                                }
                                && sectionsDoNotOverlap
                                && descendantsFit
                                && card.frame.width <= panelWidth + 0.5
                                && !card.hasHorizontalScrollerForTesting
                                && card.documentSizeForTesting.width
                                    <= card.viewportSizeForTesting.width + 0.5,
                            "Expected \(tool) at \(Int(screenWidth)) px with Fill "
                                + "\(showsFill ? "visible" : "hidden") to fit in 1-3 "
                                + "ordered rows without clipping, overlap, or horizontal scrolling "
                                + "(layout \(layout), frames \(frames), root \(rootBounds), "
                                + "clipped \(clippedDescendants), preferred "
                                + "\(matrixInspector.preferredContentSize), fitting "
                                + "\(matrixInspector.view.fittingSize), document "
                                + "\(card.documentSizeForTesting), viewport "
                                + "\(card.viewportSizeForTesting), scroller "
                                + "\(card.hasHorizontalScrollerForTesting))"
                        )
                        if [.rectangle, .diamond].contains(tool), showsFill {
                            try expect(
                                state.visibleInspectorSections == [
                                    .strokeColor,
                                    .background,
                                    .fill,
                                    .strokeWidth,
                                    .strokeStyle,
                                    .sloppiness,
                                    .edges,
                                    .opacity,
                                    .layers
                                ],
                                "Expected the full shape matrix to preserve section order"
                            )
                        }
                    }
                    if transitionHeights.count == 3 {
                        try expect(
                            transitionHeights[0] == transitionHeights[2],
                            "Expected Fill off/on/off to restore the exact original inspector height "
                                + "for \(tool) at \(Int(screenWidth)) px: \(transitionHeights), "
                                + "layouts \(transitionLayouts)"
                        )
                    }
                }
            }
        }

        emptyController.currentTool = .rectangle
        emptyController.setStrokeColor(.palette(.red))
        inspector.update(state: DrawingToolbarState(annotationController: emptyController))
        _ = inspector.visibleSectionFramesForTesting()
        let colorButtons = descendantViews(of: NSButton.self, in: inspector.view).filter {
            $0.accessibilityLabel()?.hasPrefix("Stroke ") == true
        }
        let backgroundButtons = descendantViews(of: NSButton.self, in: inspector.view).filter {
            $0.accessibilityLabel()?.hasPrefix("Background ") == true
        }
        let customColorWells = descendantViews(of: NSColorWell.self, in: inspector.view)
        let initialColorFrames = colorButtons.map(\.frame)
        emptyController.setStrokeColor(.palette(.blue))
        inspector.update(state: DrawingToolbarState(annotationController: emptyController))
        _ = inspector.visibleSectionFramesForTesting()
        try expect(
            colorButtons.count == 5
                && backgroundButtons.count == 5
                && customColorWells.count == 2
                && colorButtons.allSatisfy {
                    abs($0.frame.width - DrawingInspectorVisualMetrics.colorTileSide) < 0.01
                        && abs(
                            $0.frame.height - DrawingInspectorVisualMetrics.colorTileSide
                        ) < 0.01
                        && $0.superview?.bounds.contains($0.frame) == true
                }
                && colorButtons.map(\.frame) == initialColorFrames,
            "Expected exactly five preset colors plus one separated custom/current tile"
        )

        emptyController.setShapeBackground(nil)
        let transparentRectangle = DrawingToolbarState(annotationController: emptyController)
        emptyController.setShapeBackground(.palette(.pink))
        let filledRectangle = DrawingToolbarState(annotationController: emptyController)
        emptyController.setFillColor(.rgba(red: 1, green: 0, blue: 0, alpha: 0))
        let alphaTransparentRectangle = DrawingToolbarState(
            annotationController: emptyController
        )
        try expect(
            !transparentRectangle.visibleInspectorSections.contains(.fill)
                && filledRectangle.visibleInspectorSections.firstIndex(of: .fill)
                    == filledRectangle.visibleInspectorSections.firstIndex(of: .background)
                        .map { $0 + 1 }
                && !alphaTransparentRectangle.visibleInspectorSections.contains(.fill),
            "Expected Fill to appear directly after a nontransparent Background only"
        )

        let toolbar = DrawingToolbarView(
            commandSink: { _ in },
            showOverflow: { _ in }
        )
        toolbar.update(
            state: emptyState,
            transientTool: nil
        )
        toolbar.update(
            state: penState,
            transientTool: nil
        )
        let primaryLabels = descendantViews(
            of: NSButton.self,
            in: toolbar
        ).compactMap { $0.accessibilityLabel() }
        try expect(
            !primaryLabels.contains("Open Drawing Inspector")
                && !primaryLabels.contains("Close Drawing Inspector")
                && !primaryLabels.contains("Attach Inspector to Toolbar")
                && !primaryLabels.contains("Dock Inspector to Side"),
            "Expected inspector visibility, pinning, and presentation controls to stay in overflow"
        )
    }

    private static func testDrawingInspectorControlMappingsAndTextPresets() throws {
        try expect(
            DrawingInspectorControlMapping.fillStyles
                == [.hachure, .crossHatch, .solid]
                && DrawingInspectorControlMapping.strokeWidths.count == 3
                && DrawingInspectorControlMapping.strokePatterns.count == 3
                && DrawingInspectorControlMapping.sloppiness.count == 3
                && DrawingInspectorControlMapping.edgeStyles.count == 2
                && DrawingInspectorControlMapping.linearRoutes
                    == [.straight, .curved]
                && SettingsWindowController.drawingLinearRouteOptionsForTesting
                    == ["Straight", "Curved"]
                && DrawingInspectorControlMapping.arrowheadSizes
                    == [.small, .medium, .large]
                && DrawingInspectorControlMapping.layerActions.map(\.action)
                    == [.sendToBack, .sendBackward, .bringForward, .bringToFront]
                && DrawingInspectorControlMapping.pressureOptions.count == 2
                && DrawingInspectorControlMapping.textFontPresets.count == 3
                && DrawingInspectorControlMapping.textSizes.count == 4
                && DrawingInspectorControlMapping.textAlignments.count == 3
                && DrawingInspectorControlMapping.strokeColors.count == 5
                && DrawingInspectorControlMapping.highlighterColors.count == 5
                && DrawingInspectorControlMapping.backgroundColors.count == 4,
            "Expected exact compact option and preset-color counts"
        )
        try expect(
            AnnotationLinearRoute.route(forOptionShortcut: "1") == .straight
                && AnnotationLinearRoute.route(forOptionShortcut: "2") == .curved
                && AnnotationLinearRoute.route(forOptionShortcut: "3") == nil,
            "Expected only Option+1 and Option+2 to expose user-selectable routes"
        )
        let expectedHighlighterRGB: [(AnnotationColor, (Int, Int, Int))] = [
            (.highlighterYellow, (255, 244, 92)),
            (.highlighterCyan, (50, 215, 255)),
            (.highlighterPink, (255, 92, 173)),
            (.highlighterGreen, (102, 242, 111)),
            (.highlighterOrange, (255, 159, 67))
        ]
        try expect(
            zip(
                DrawingInspectorControlMapping.highlighterColors,
                expectedHighlighterRGB
            ).allSatisfy { actual, expected in
                guard actual == expected.0,
                      let color = actual.nsColor.usingColorSpace(.sRGB) else {
                    return false
                }
                return Int((color.redComponent * 255).rounded()) == expected.1.0
                    && Int((color.greenComponent * 255).rounded()) == expected.1.1
                    && Int((color.blueComponent * 255).rounded()) == expected.1.2
            },
            "Expected the exact neon sRGB Highlighter palette"
        )
        try expect(
            DrawingInspectorControlMapping.fillStyleCommand(at: 0) == .setFillStyle(.hachure)
                && DrawingInspectorControlMapping.fillStyleCommand(at: 1)
                    == .setFillStyle(.crossHatch)
                && DrawingInspectorControlMapping.fillStyleCommand(at: 2)
                    == .setFillStyle(.solid)
                && DrawingInspectorControlMapping.fillStyleCommand(at: -1) == nil,
            "Expected fill palette indices to map to typed commands"
        )
        try expect(
            DrawingInspectorSection.allCases.map(\.title) == [
                "Stroke",
                "Background",
                "Fill",
                "Stroke width",
                "Stroke style",
                "Sloppiness",
                "Edges",
                "Arrow type",
                "Arrowheads",
                "Arrowhead size",
                "Smart Draw",
                "Pressure",
                "Font family",
                "Font size",
                "Text align",
                "Opacity",
                "Layers"
            ],
            "Expected exact compact inspector section titles"
        )
        for (index, arrowhead) in DrawingInspectorControlMapping.arrowheads.enumerated() {
            try expect(
                DrawingInspectorControlMapping.startArrowheadCommand(at: index)
                    == .setLinearStartArrowhead(arrowhead)
                    && DrawingInspectorControlMapping.endArrowheadCommand(at: index)
                        == .setLinearEndArrowhead(arrowhead),
                "Expected arrowhead palette index \(index) to preserve endpoint direction"
            )
        }

        try expect(
            DrawingInspectorControlMapping.startArrowheadCommand(
                at: DrawingInspectorControlMapping.arrowheads.count
            ) == nil,
            "Expected out-of-range arrowhead palette commands to be rejected"
        )
        for (index, preset) in DrawingInspectorControlMapping.textFontPresets.enumerated() {
            try expect(
                DrawingInspectorControlMapping.textFontPresetCommand(at: index)
                    == .setTextFontPreset(preset),
                "Expected font palette index \(index) to map to a typed preset command"
            )
        }
        try expect(
            DrawingInspectorControlMapping.textSizeCommand(at: 3) == .setTextFontSize(72),
            "Expected Very large text to map to the 72 point preset"
        )
        let pressureController = AnnotationController()
        try expect(
            DrawingToolbarState(annotationController: pressureController)
                .preferredVariablePressureMode == .simulated,
            "Expected Variable pressure to use mouse-speed input without a tablet"
        )
        pressureController.noteTabletInputAvailable()
        try expect(
            DrawingToolbarState(annotationController: pressureController)
                .preferredVariablePressureMode == .tablet,
            "Expected Variable pressure to prefer an observed tablet input"
        )

        let controller = AnnotationController()
        controller.typingFontName = "Helvetica"
        controller.setTextFontPreset(.typeSetting)
        controller.currentTool = .text
        controller.setInsertionPoint(CGPoint(x: 20, y: 20))
        controller.beginTypingSession(rightAligned: false)
        controller.insertText("Custom")
        controller.finishTypingSession()
        controller.setTextFontPreset(.system)
        controller.setInsertionPoint(CGPoint(x: 20, y: 60))
        controller.beginTypingSession(rightAligned: false)
        controller.insertText("System")
        controller.finishTypingSession()
        let originalFontNames: [String] = controller.elementSnapshot.compactMap {
            element -> String? in
            guard case .text(let text) = element.geometry else { return nil }
            return text.fontName
        }

        controller.currentTool = .select
        controller.selectAll()
        controller.setTextFontPreset(.serif)
        try expect(
            controller.selectedElementSnapshot.allSatisfy {
                guard case .text(let text) = $0.geometry else { return false }
                return text.fontName == AnnotationTextFontPreset.serifStorageName
            },
            "Expected one font preset command to update every editable selected text element"
        )
        controller.undo()
        let restoredFontNames: [String] = controller.elementSnapshot.compactMap {
            element -> String? in
            guard case .text(let text) = element.geometry else { return nil }
            return text.fontName
        }
        try expect(
            restoredFontNames == originalFontNames,
            "Expected one undo to restore the complete text font preset mutation"
        )
        try expect(
            controller.typingFontName == "Helvetica",
            "Expected native preset changes to preserve the custom Type settings font"
        )
        controller.setTextFontName("Courier")
        try expect(
            controller.typingFontPreset == .system
                && controller.typingFontName == "Helvetica"
                && controller.selectedElementSnapshot.allSatisfy {
                    guard case .text(let text) = $0.geometry else { return false }
                    return text.fontName == "Courier"
                },
            "Expected the compact font picker to update selected text without "
                + "overwriting text creation defaults"
        )

        let presetNames = [
            AnnotationTextFontPreset.roundedStorageName,
            AnnotationTextFontPreset.serifStorageName,
            AnnotationTextFontPreset.monospacedStorageName
        ]
        try expect(
            presetNames.allSatisfy {
                AnnotationController.typingFont(named: $0, size: 24).pointSize == 24
            },
            "Expected every safe native font preset to resolve at the requested size"
        )
        let handDrawnFont = AnnotationController.typingFont(
            named: AnnotationTextFontPreset.roundedStorageName,
            size: 24
        )
        let normalFont = AnnotationController.typingFont(named: "", size: 24)
        let codeFont = AnnotationController.typingFont(
            named: AnnotationTextFontPreset.monospacedStorageName,
            size: 24
        )
        let fontPreviewSignatures = try [
            AnnotationTextFontPreset.rounded,
            .system,
            .monospaced
        ].map {
            try previewAlphaSignature(
                .textFont($0, customFontName: nil)
            )
        }
        try expect(
            Set([
                handDrawnFont.fontName,
                normalFont.fontName,
                codeFont.fontName
            ]).count == 3
                && handDrawnFont.fontName != normalFont.fontName
                && codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace)
                && Set(fontPreviewSignatures).count == 3,
            "Expected visibly distinct Hand-drawn, Normal sans, and Code mono fonts/previews"
        )
    }

    private static func testDrawingInspectorVisualPreviewsAndWiring() throws {
        try expect(
            DrawingInspectorVisualMetrics.contentWidth == 261
                && DrawingInspectorVisualMetrics.tileSide == 32
                && DrawingInspectorVisualMetrics.colorTileSide == 38
                && DrawingInspectorVisualMetrics.customColorTileSide == 26
                && DrawingInspectorVisualMetrics.customColorCornerRadius == 5
                && DrawingInspectorVisualMetrics.tileSpacing == 8
                && DrawingInspectorVisualMetrics.swatchSpacing == 7
                && DrawingInspectorVisualMetrics.sectionSpacing == 16
                && DrawingInspectorVisualMetrics.attachedHorizontalChrome == 24,
            "Expected the audited compact inspector geometry"
        )
        let lightAppearance = NSAppearance(named: .aqua)
        let darkAppearance = NSAppearance(named: .darkAqua)
        let lightIdle = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(),
            appearance: lightAppearance
        )
        let lightHover = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isHovered: true),
            appearance: lightAppearance
        )
        let lightPressed = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isPressed: true),
            appearance: lightAppearance
        )
        let lightSelected = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isSelected: true),
            appearance: lightAppearance
        )
        let lightMixed = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isMixed: true),
            appearance: lightAppearance
        )
        let lightFocused = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isFocused: true),
            appearance: lightAppearance
        )
        let lightDisabled = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isEnabled: false),
            appearance: lightAppearance
        )
        let darkIdle = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(),
            appearance: darkAppearance
        )
        let darkHover = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isHovered: true),
            appearance: darkAppearance
        )
        let darkPressed = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isPressed: true),
            appearance: darkAppearance
        )
        let darkSelected = DrawingControlAppearanceResolver.resolve(
            DrawingControlVisualState(isSelected: true),
            appearance: darkAppearance
        )
        try expect(
            lightIdle.background.alpha == 0
                && lightIdle.border.alpha == 0
                && lightHover.background == DrawingControlColor(
                    red: 0xF1 / 255,
                    green: 0xF0 / 255,
                    blue: 1
                )
                && lightPressed.background == DrawingControlColor(
                    red: 0xEC / 255,
                    green: 0xEB / 255,
                    blue: 1
                )
                && lightPressed.border.alpha == 0
                && lightSelected.background == DrawingControlColor(
                    red: 0xE0 / 255,
                    green: 0xDF / 255,
                    blue: 1
                )
                && lightSelected.border.alpha == 0
                && lightSelected.content == DrawingControlColor(
                    red: 0x03 / 255,
                    green: 0,
                    blue: 0x64 / 255
                )
                && lightMixed.showsMixedIndicator
                && lightFocused.border == lightSelected.border
                && lightDisabled.contentOpacity == 0.38
                && lightDisabled.fillOpacity == 0.55,
            "Expected exact light idle, hover, pressed, selected, mixed, focused, and disabled states"
        )
        try expect(
            darkIdle.background.alpha == 0
                && darkIdle.border.alpha == 0
                && darkHover.background == DrawingControlColor(
                    red: 0x2E / 255,
                    green: 0x2D / 255,
                    blue: 0x39 / 255
                )
                && darkPressed.background == DrawingControlColor(
                    red: 0x40 / 255,
                    green: 0x3B / 255,
                    blue: 0x5F / 255
                )
                && darkPressed.border.alpha == 0
                && darkSelected.background == DrawingControlColor(
                    red: 0x40 / 255,
                    green: 0x3E / 255,
                    blue: 0x6A / 255
                )
                && darkSelected.border.alpha == 0
                && darkSelected.content == DrawingControlColor(
                    red: 0xE0 / 255,
                    green: 0xDF / 255,
                    blue: 1
                ),
            "Expected exact dark control-state equivalents"
        )
        let previewFamilies: [[DrawingInspectorPreview]] = [
            DrawingInspectorControlMapping.strokeWidths.map(DrawingInspectorPreview.strokeWidth),
            DrawingInspectorControlMapping.strokePatterns.map(
                DrawingInspectorPreview.strokePattern
            ),
            DrawingInspectorControlMapping.sloppiness.map(
                DrawingInspectorPreview.sloppiness
            ),
            DrawingInspectorControlMapping.fillStyles.map(DrawingInspectorPreview.fillStyle),
            DrawingInspectorControlMapping.edgeStyles.map(DrawingInspectorPreview.edges),
            DrawingInspectorControlMapping.linearRoutes.map(
                DrawingInspectorPreview.linearRoute
            ),
            [
                .textFont(.rounded, customFontName: "Helvetica"),
                .textFont(.system, customFontName: "Helvetica"),
                .textFont(.monospaced, customFontName: "Helvetica")
            ],
            DrawingInspectorControlMapping.textAlignments.map(
                DrawingInspectorPreview.textAlignment
            ),
            DrawingInspectorControlMapping.arrowheads.map {
                .arrowhead($0, pointsRight: true)
            },
            DrawingInspectorControlMapping.arrowheadSizes.map(
                DrawingInspectorPreview.arrowheadSize
            ),
            DrawingInspectorControlMapping.pressureOptions.map(
                DrawingInspectorPreview.pressure
            ),
            DrawingInspectorControlMapping.layerActions.map {
                .layer($0.action)
            },
            [.smartDraw]
        ]
        for (index, family) in previewFamilies.enumerated() {
            let signatures = family.compactMap { $0.image.tiffRepresentation }
            try expect(
                signatures.count == family.count
                    && Set(signatures).count == family.count,
                "Expected inspector preview family \(index) to draw distinct actual effects"
            )
        }

        var commands: [AppCommand] = []
        let inspector = DrawingPropertiesController(
            commandSink: { commands.append($0) },
            colorPanelActivityChanged: { _ in }
        )
        let root = inspector.view
        let expectedButtonCommands: [(String, AppCommand)] = [
            ("Hachure", .setFillStyle(.hachure)),
            ("Bold", .setStrokeWidth(6)),
            ("Dashed", .setStrokePattern(.dashed)),
            ("Cartoonist", .setSloppiness(.cartoonist)),
            ("Variable", .setPressureMode(.simulated)),
            ("Round", .setEdgeStyle(.round)),
            ("Curved arrow", .setLinearRoute(.curved)),
            ("Large", .setLinearArrowheadSize(.large)),
            ("Hand-drawn", .setTextFontPreset(.rounded)),
            ("Very large", .setTextFontSize(72)),
            ("Center", .setTextAlignment(.center)),
            ("Send to back", .arrangeSelection(.sendToBack)),
            ("Send backward", .arrangeSelection(.sendBackward)),
            ("Bring forward", .arrangeSelection(.bringForward)),
            ("Bring to front", .arrangeSelection(.bringToFront))
        ]
        let buttons = descendantViews(of: NSButton.self, in: root)
        let exactOptionTitles = [
            "Thin", "Medium", "Bold",
            "Solid", "Dashed", "Dotted",
            "Architect", "Artist", "Cartoonist",
            "Sharp", "Round",
            "Sharp arrow (straight)", "Curved arrow",
            "Constant", "Variable",
            "Smart Draw: Off",
            "Hand-drawn", "Normal", "Code",
            "Small", "Medium", "Large", "Very large",
            "Left", "Center", "Right",
            "Send to back", "Send backward", "Bring forward", "Bring to front"
        ]
        try expect(
            exactOptionTitles.allSatisfy { title in
                buttons.contains { $0.accessibilityLabel() == title }
            }
                && [
                    "10 point stroke",
                    "Soft edges",
                    "Rounded edges",
                    "Fixed",
                    "Tablet",
                    "Mouse speed",
                    "Serif",
                    "Mono",
                    "Type",
                    "Raw freehand stroke",
                    "Smoothed freehand stroke",
                    "Smart Draw on",
                    "Smart Draw off"
                ].allSatisfy { title in
                    !buttons.contains { $0.accessibilityLabel() == title }
                },
            "Expected exact compact option titles on programmatic preview controls"
        )
        for (label, expectedCommand) in expectedButtonCommands {
            guard let button = buttons.first(where: { $0.accessibilityLabel() == label }) else {
                throw SelfTestError.failure("Expected inspector button labeled \(label)")
            }
            commands.removeAll()
            button.performClick(nil)
            try expect(
                commands == [expectedCommand],
                "Expected \(label) to dispatch \(expectedCommand), got \(commands)"
            )
        }

        let colorButtonCommands: [(String, AppCommand)] = [
            ("Stroke Coral", .setStrokeColor(.palette(.strokeCoral))),
            ("Background Transparent", .setShapeBackground(nil)),
            (
                "Background Muted Red",
                .setShapeBackground(.palette(.backgroundRed))
            )
        ]
        for (label, expectedCommand) in colorButtonCommands {
            guard let button = buttons.first(where: { $0.accessibilityLabel() == label }) else {
                throw SelfTestError.failure("Expected color button labeled \(label)")
            }
            commands.removeAll()
            button.performClick(nil)
            try expect(
                commands == [expectedCommand],
                "Expected \(label) to dispatch its scoped color command"
            )
        }

        let penController = AnnotationController()
        penController.currentTool = .pen
        inspector.update(
            state: DrawingToolbarState(annotationController: penController)
        )
        guard let smartDrawButton = buttons.first(where: {
            $0.accessibilityLabel() == "Smart Draw: Off"
        }) else {
            throw SelfTestError.failure("Expected the Pen Smart Draw wand button")
        }
        commands.removeAll()
        smartDrawButton.performClick(nil)
        try expect(
            commands == [.setSmartDrawEnabled(true)],
            "Expected the Pen wand button to dispatch one clear Smart Draw toggle"
        )
        penController.setSmartDrawEnabled(true)
        inspector.update(
            state: DrawingToolbarState(annotationController: penController)
        )
        try expect(
            smartDrawButton.accessibilityLabel() == "Smart Draw: On"
                && smartDrawButton.accessibilityValue() as? String == "Selected",
            "Expected the Smart Draw wand to expose clear on/off selected state"
        )
        let restoredInspectorController = AnnotationController()
        restoredInspectorController.currentTool = .rectangle
        inspector.update(
            state: DrawingToolbarState(
                annotationController: restoredInspectorController
            )
        )

        let relocatedLabels = [
            "Edit Points",
            "Insert Point",
            "Remove Points",
            "Unbind Ends",
            "Group",
            "Ungroup",
            "Lock Selection",
            "Duplicate Selection",
            "Delete Selection",
            "Smart Draw on",
            "Raw freehand stroke"
        ]
        try expect(
            descendantViews(of: NSStepper.self, in: root).isEmpty
                && relocatedLabels.allSatisfy { label in
                    !buttons.contains { $0.accessibilityLabel() == label }
                }
                && DrawingToolbarOverflowActionTitle.relocatedSelectionActions == [
                    "Duplicate",
                    "Delete",
                    "Bring to Front",
                    "Bring Forward",
                    "Send Backward",
                    "Send to Back",
                    "Group",
                    "Ungroup",
                    "Lock Selection"
                ],
            "Expected fine adjustments and generic actions to stay outside the compact inspector"
        )

        let sliders = descendantViews(of: NSSlider.self, in: root)
        guard sliders.count == 1,
              let opacity = sliders.first(where: {
                  $0.accessibilityLabel() == "Opacity"
              }) else {
            throw SelfTestError.failure("Expected one shared compact opacity slider")
        }
        opacity.doubleValue = 0.4
        commands.removeAll()
        _ = opacity.sendAction(opacity.action, to: opacity.target)
        try expect(
            commands == [.setOpacity(0.4)],
            "Expected opacity slider changes to dispatch immediately"
        )

        let colorWells = descendantViews(of: NSColorWell.self, in: root)
        let customColor = NSColor(
            srgbRed: 0.25,
            green: 0.5,
            blue: 0.75,
            alpha: 1
        )
        let colorWellCommands: [(String, AppCommand)] = [
            (
                "Custom stroke color",
                .setStrokeColor(.rgba(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
            ),
            (
                "Custom background color",
                .setShapeBackground(
                    .rgba(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
                )
            )
        ]
        for (label, expectedCommand) in colorWellCommands {
            guard let colorWell = colorWells.first(where: {
                $0.accessibilityLabel() == label
            }) else {
                throw SelfTestError.failure("Expected color well labeled \(label)")
            }
            colorWell.color = customColor
            commands.removeAll()
            _ = colorWell.sendAction(colorWell.action, to: colorWell.target)
            try expect(
                commands == [expectedCommand],
                "Expected \(label) to dispatch its scoped custom color command"
            )
        }

        let arrowInspectorController = AnnotationController()
        arrowInspectorController.currentTool = .arrow
        inspector.update(
            state: DrawingToolbarState(
                annotationController: arrowInspectorController
            )
        )
        let arrowheadPickers = descendantViews(
            of: DrawingInspectorArrowheadPicker.self,
            in: root
        )
        guard let startPicker = arrowheadPickers.first(where: {
            $0.accessibilityLabel() == "Start arrowhead"
        }),
        let endPicker = arrowheadPickers.first(where: {
            $0.accessibilityLabel() == "End arrowhead"
        }) else {
            throw SelfTestError.failure("Expected visual start and end arrowhead pickers")
        }
        startPicker.update(.value(.circleOutline))
        guard let startTrigger = descendantViews(
            of: NSButton.self,
            in: startPicker
        ).first else {
            throw SelfTestError.failure("Expected an arrowhead picker trigger")
        }
        try expect(
            startTrigger.accessibilityValue() as? String == "Not selected",
            "Expected picker triggers to show the value without persistent selected styling"
        )
        commands.removeAll()
        startPicker.selectForTesting(.zeroOrMany)
        endPicker.selectForTesting(.triangleOutline)
        try expect(
            commands == [
                .setLinearStartArrowhead(.zeroOrMany),
                .setLinearEndArrowhead(.triangleOutline)
            ],
            "Expected visual arrowhead palette choices to dispatch endpoint-specific commands"
        )

        arrowInspectorController.currentTool = .text
        inspector.update(
            state: DrawingToolbarState(
                annotationController: arrowInspectorController
            )
        )
        guard let fontPicker = descendantViews(
            of: DrawingInspectorFontPicker.self,
            in: root
        ).first else {
            throw SelfTestError.failure("Expected the fourth font-family picker button")
        }
        commands.removeAll()
        fontPicker.selectForTesting("Helvetica")
        try expect(
            commands == [.setTextFontName("Helvetica")],
            "Expected the compact font-picker button to dispatch the selected family"
        )
    }

    private static func testDrawingPaletteVisualParity() throws {
        let lightAppearance = NSAppearance(named: .aqua)
        let darkAppearance = NSAppearance(named: .darkAqua)

        func cachedCenterColor(of view: NSView) throws -> NSColor {
            view.layoutSubtreeIfNeeded()
            guard let representation = view.bitmapImageRepForCachingDisplay(
                in: view.bounds
            ) else {
                throw SelfTestError.failure(
                    "Could not cache palette preview"
                )
            }
            view.cacheDisplay(in: view.bounds, to: representation)
            guard let color = representation.colorAt(
                x: representation.pixelsWide / 2,
                y: representation.pixelsHigh / 2
            )?.usingColorSpace(.sRGB) else {
                throw SelfTestError.failure(
                    "Could not sample palette preview"
                )
            }
            return color
        }

        func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
            let left = lhs.usingColorSpace(.sRGB) ?? lhs
            let right = rhs.usingColorSpace(.sRGB) ?? rhs
            return max(
                abs(left.redComponent - right.redComponent),
                abs(left.greenComponent - right.greenComponent),
                abs(left.blueComponent - right.blueComponent)
            )
        }

        let expectedStrokeLight: [(AnnotationColor, UInt32)] = [
            (.strokeNeutral, 0x1B1B1F),
            (.strokeCoral, 0xE03131),
            (.strokeGreen, 0x2F9E44),
            (.strokeBlue, 0x1971C2),
            (.strokeOrange, 0xE8590C)
        ]
        let expectedStrokeDark: [(AnnotationColor, UInt32)] = [
            (.strokeNeutral, 0xE9ECEF),
            (.strokeCoral, 0xFF8787),
            (.strokeGreen, 0x69DB7C),
            (.strokeBlue, 0x74C0FC),
            (.strokeOrange, 0xFFA94D)
        ]
        let expectedBackgroundLight: [(AnnotationColor, UInt32)] = [
            (.backgroundRed, 0xFFC9C9),
            (.backgroundGreen, 0xB2F2BB),
            (.backgroundBlue, 0xA5D8FF),
            (.backgroundYellow, 0xFFEC99)
        ]
        let expectedBackgroundDark: [(AnnotationColor, UInt32)] = [
            (.backgroundRed, 0x5C2B2B),
            (.backgroundGreen, 0x244A31),
            (.backgroundBlue, 0x243F5A),
            (.backgroundYellow, 0x5A4A22)
        ]

        func rgb(_ color: NSColor) -> UInt32 {
            let resolved = color.usingColorSpace(.sRGB) ?? color
            return UInt32((resolved.redComponent * 255).rounded()) << 16
                | UInt32((resolved.greenComponent * 255).rounded()) << 8
                | UInt32((resolved.blueComponent * 255).rounded())
        }

        try expect(
            DrawingInspectorControlMapping.strokeColors
                == expectedStrokeLight.map(\.0)
                && DrawingInspectorControlMapping.backgroundColors
                    == expectedBackgroundLight.map(\.0)
                && expectedStrokeLight.allSatisfy {
                    rgb($0.0.resolvedNSColor(for: lightAppearance)) == $0.1
                }
                && expectedStrokeDark.allSatisfy {
                    rgb($0.0.resolvedNSColor(for: darkAppearance)) == $0.1
                }
                && expectedBackgroundLight.allSatisfy {
                    rgb($0.0.resolvedNSColor(for: lightAppearance)) == $0.1
                }
                && expectedBackgroundDark.allSatisfy {
                    rgb($0.0.resolvedNSColor(for: darkAppearance)) == $0.1
                },
            "Expected exact ordered light/dark Excalidraw stroke and background palettes"
        )

        let geometry = DrawingColorSwatchGeometry(
            bounds: CGRect(
                origin: .zero,
                size: CGSize(
                    width: DrawingInspectorVisualMetrics.colorTileSide,
                    height: DrawingInspectorVisualMetrics.colorTileSide
                )
            )
        )
        let selectedLightRing = DrawingColorSwatchAppearance.ringColor(
            isSelected: true,
            isHovered: false,
            appearance: lightAppearance
        )
        let selectedDarkRing = DrawingColorSwatchAppearance.ringColor(
            isSelected: true,
            isHovered: false,
            appearance: darkAppearance
        )
        let hoverDarkRing = DrawingColorSwatchAppearance.ringColor(
            isSelected: false,
            isHovered: true,
            appearance: darkAppearance
        )
        try expect(
            geometry.swatchRect.size == CGSize(width: 35, height: 35)
                && geometry.ringRect.size == CGSize(width: 37, height: 37)
                && DrawingColorSwatchGeometry.cornerRadius == 6
                && DrawingColorSwatchGeometry.ringCornerRadius == 7
                && rgb(selectedLightRing ?? .clear) == 0x5E59D6
                && rgb(selectedDarkRing ?? .clear) == 0xA8A3FF
                && hoverDarkRing?.alphaComponent == 0.9
                && DrawingColorSwatchAppearance.ringColor(
                    isSelected: false,
                    isHovered: false,
                    appearance: darkAppearance
                ) == nil,
            "Expected fixed square geometry plus selected and hover rings without layout changes"
        )

        let annotationController = AnnotationController()
        annotationController.currentTool = .rectangle
        annotationController.setStrokeColor(.palette(.strokeBlue))
        annotationController.setShapeBackground(.palette(.backgroundBlue))
        annotationController.setFillStyle(.solid)
        let inspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        inspector.update(
            state: DrawingToolbarState(annotationController: annotationController)
        )
        let host = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.appearance = darkAppearance
        host.contentView = inspector.view
        host.orderFront(nil)
        inspector.view.layoutSubtreeIfNeeded()

        let strokeButtons = descendantViews(
            of: NSButton.self,
            in: inspector.view
        ).filter { $0.accessibilityLabel()?.hasPrefix("Stroke ") == true }
        let backgroundButtons = descendantViews(
            of: NSButton.self,
            in: inspector.view
        ).filter { $0.accessibilityLabel()?.hasPrefix("Background ") == true }
        let customWells = descendantViews(of: NSColorWell.self, in: inspector.view)
        let dividers = descendantViews(
            of: DrawingColorPaletteDivider.self,
            in: inspector.view
        )
        let strokeFrames = strokeButtons.map {
            $0.convert($0.bounds, to: inspector.view)
        }.sorted { $0.minX < $1.minX }
        let strokeGaps = zip(strokeFrames, strokeFrames.dropFirst()).map {
            $1.minX - $0.maxX
        }
        try expect(
            strokeButtons.count == 5
                && backgroundButtons.count == 5
                && customWells.count == 2
                && dividers.count == 2
                && strokeFrames.allSatisfy {
                    abs($0.width - 38) < 0.01
                        && abs($0.height - 38) < 0.01
                }
                && strokeGaps.allSatisfy { abs($0 - 7) < 0.01 }
                && customWells.allSatisfy {
                    abs($0.frame.width - 26) < 0.01
                        && abs($0.frame.height - 26) < 0.01
                        && $0.layer?.cornerRadius == 5
                        && $0.layer?.borderWidth == 0
                }
                && dividers.allSatisfy {
                    abs($0.frame.width - 1) < 0.01
                        && abs($0.frame.height - 24) < 0.01
                        && ($0.superview as? NSStackView)?.spacing == 8
                }
                && strokeButtons.allSatisfy {
                    $0.layer?.borderWidth == 0
                        && ($0.layer?.backgroundColor?.alpha ?? 0) == 0
                }
                && strokeButtons.filter {
                    $0.accessibilityValue() as? String == "Selected"
                }.map { $0.accessibilityLabel() } == ["Stroke Light Blue"]
                && backgroundButtons.filter {
                    $0.accessibilityValue() as? String == "Selected"
                }.map { $0.accessibilityLabel() } == ["Background Muted Blue"],
            "Expected five square presets, separated custom wells, exact gaps/dividers, "
                + "and ring-only selected states"
        )

        guard let strokeBlueButton = strokeButtons.first(where: {
            $0.accessibilityLabel() == "Stroke Light Blue"
        }),
        let backgroundBlueButton = backgroundButtons.first(where: {
            $0.accessibilityLabel() == "Background Muted Blue"
        }),
        let transparentButton = backgroundButtons.first(where: {
            $0.accessibilityLabel() == "Background Transparent"
        }) else {
            throw SelfTestError.failure("Expected semantic palette buttons")
        }
        let cachedStrokePreview = try cachedCenterColor(of: strokeBlueButton)
        let cachedBackgroundPreview = try cachedCenterColor(of: backgroundBlueButton)
        let panelBackground = DrawingColorSwatchAppearance.panelBackground(
            for: darkAppearance
        )
        let strokePreview = DrawingColorSwatchAppearance.previewColor(
            .palette(.strokeBlue),
            opacity: 1,
            appearance: darkAppearance
        )
        let backgroundPreview = DrawingColorSwatchAppearance.previewColor(
            .palette(.backgroundBlue),
            opacity: 1,
            appearance: darkAppearance
        )

        var lineStyle = AnnotationStyle(
            color: .strokeBlue,
            rootWidth: 6,
            alpha: 1,
            sloppiness: .architect
        )
        lineStyle.strokeColor = .palette(.strokeBlue)
        let line = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 12, y: 32), CGPoint(x: 84, y: 32)],
            style: lineStyle
        )
        var fillStyle = lineStyle
        fillStyle.fillColor = .palette(.backgroundBlue)
        fillStyle.fillStyle = .solid
        let rectangle = AnnotationElement.legacy(
            tool: .rectangle,
            points: [CGPoint(x: 16, y: 16), CGPoint(x: 80, y: 56)],
            style: fillStyle
        )
        var linePixels: [UInt8]?
        var rectanglePixels: [UInt8]?
        var renderError: Error?
        darkAppearance?.performAsCurrentDrawingAppearance {
            do {
                linePixels = try renderPixels(
                    elements: [line],
                    renderer: AnnotationRenderer(),
                    width: 96,
                    height: 64,
                    backgroundColor: panelBackground
                )
                rectanglePixels = try renderPixels(
                    elements: [rectangle],
                    renderer: AnnotationRenderer(),
                    width: 96,
                    height: 72,
                    backgroundColor: panelBackground
                )
            } catch {
                renderError = error
            }
        }
        if let renderError { throw renderError }
        guard let linePixels, let rectanglePixels else {
            throw SelfTestError.failure("Expected dark palette render pixels")
        }
        let linePixel = pixel(linePixels, width: 96, x: 48, y: 32)
        let fillPixel = pixel(rectanglePixels, width: 96, x: 48, y: 36)
        let lineColor = NSColor(
            srgbRed: CGFloat(linePixel.red) / 255,
            green: CGFloat(linePixel.green) / 255,
            blue: CGFloat(linePixel.blue) / 255,
            alpha: 1
        )
        let fillColor = NSColor(
            srgbRed: CGFloat(fillPixel.red) / 255,
            green: CGFloat(fillPixel.green) / 255,
            blue: CGFloat(fillPixel.blue) / 255,
            alpha: 1
        )
        try expect(
            colorDistance(strokePreview, lineColor) < 0.04
                && colorDistance(backgroundPreview, fillColor) < 0.04
                && colorDistance(cachedStrokePreview, panelBackground) > 0.1
                && colorDistance(cachedBackgroundPreview, panelBackground) > 0.05,
            "Expected dark semantic swatch previews to match rendered stroke/fill colors "
                + "(stroke preview \(strokePreview), cached \(cachedStrokePreview), "
                + "render \(lineColor), background preview \(backgroundPreview), "
                + "cached \(cachedBackgroundPreview), render \(fillColor))"
        )

        annotationController.setShapeBackground(nil)
        inspector.update(
            state: DrawingToolbarState(annotationController: annotationController)
        )
        try expect(
            transparentButton.accessibilityValue() as? String == "Selected"
                && DrawingColorSwatchAppearance.ringColor(
                    isSelected: true,
                    isHovered: false,
                    appearance: darkAppearance
                ) != nil,
            "Expected the checkerboard Transparent swatch to retain an obvious selected ring"
        )

        annotationController.currentTool = .highlighter
        inspector.update(
            state: DrawingToolbarState(annotationController: annotationController)
        )
        let highlighterLabels = strokeButtons.sorted {
            $0.frame.minX < $1.frame.minX
        }.compactMap { $0.accessibilityLabel() }
        try expect(
            highlighterLabels == [
                "Stroke Light Yellow",
                "Stroke Cyan",
                "Stroke Pink",
                "Stroke Green",
                "Stroke Orange"
            ]
                && strokeButtons.allSatisfy {
                    abs($0.frame.width - 38) < 0.01
                        && abs($0.frame.height - 38) < 0.01
                        && $0.layer?.borderWidth == 0
                        && ($0.layer?.backgroundColor?.alpha ?? 0) == 0
                },
            "Expected the dedicated neon Highlighter palette to reuse the same square/ring layout"
        )
        host.close()
    }

    private static func testDrawingInspectorPreviewGeometryAndSignatures() throws {
        let previewRect = CGRect(x: 2, y: 2, width: 28, height: 28)
        let straight = DrawingInspectorPreview.linearRouteGeometry(.straight, in: previewRect)
        let curved = DrawingInspectorPreview.linearRouteGeometry(.curved, in: previewRect)
        let elbow = DrawingInspectorPreview.linearRouteGeometry(.elbow, in: previewRect)

        try expect(
            straight.points.count == 2 && straight.bezierControls.isEmpty,
            "Expected the Straight inspector preview to remain a direct two-point segment"
        )
        guard curved.points.count == 2, curved.bezierControls.count == 1 else {
            throw SelfTestError.failure(
                "Expected the Curved inspector preview to use one explicit cubic Bezier segment"
            )
        }
        let chord = CGPoint(
            x: curved.points[1].x - curved.points[0].x,
            y: curved.points[1].y - curved.points[0].y
        )
        let firstControlOffset = CGPoint(
            x: curved.bezierControls[0].start.x - curved.points[0].x,
            y: curved.bezierControls[0].start.y - curved.points[0].y
        )
        let controlCrossProduct =
            chord.x * firstControlOffset.y - chord.y * firstControlOffset.x
        try expect(
            abs(controlCrossProduct) > 1,
            "Expected the Curved inspector preview controls to be visibly non-collinear"
        )
        try expect(
            elbow.points.count == 4
                && zip(elbow.points, elbow.points.dropFirst()).allSatisfy {
                    $0.x == $1.x || $0.y == $1.y
                },
            "Expected the Elbow inspector preview to remain an orthogonal route"
        )

        let sharpEdge = DrawingInspectorPreview.edgePreviewGeometry(
            .sharp,
            in: previewRect
        )
        let roundEdge = DrawingInspectorPreview.edgePreviewGeometry(
            .round,
            in: previewRect
        )
        let sharpPoints = AnnotationRoughStroke.sampledPoints(
            on: sharpEdge.solidPath
        )
        let dottedPoints = AnnotationRoughStroke.sampledPoints(
            on: sharpEdge.dottedPath
        )
        try expect(
            sharpEdge.bounds.size == CGSize(width: 16, height: 16)
                && sharpEdge.bounds.midX == previewRect.midX
                && sharpEdge.bounds.midY == previewRect.midY
                && sharpPoints == [
                    CGPoint(x: sharpEdge.bounds.maxX, y: sharpEdge.bounds.minY),
                    CGPoint(x: sharpEdge.bounds.minX, y: sharpEdge.bounds.minY),
                    CGPoint(x: sharpEdge.bounds.minX, y: sharpEdge.bounds.maxY)
                ]
                && dottedPoints == [
                    CGPoint(x: sharpEdge.bounds.maxX, y: sharpEdge.bounds.minY),
                    CGPoint(x: sharpEdge.bounds.maxX, y: sharpEdge.bounds.maxY),
                    CGPoint(x: sharpEdge.bounds.minX, y: sharpEdge.bounds.maxY)
                ]
                && AnnotationRoughStroke.pathElementCount(
                    roundEdge.solidPath
                ) == 2,
            "Expected centered 16-point Sharp/Round corner previews with dotted right/bottom edges"
        )

        let routeSignatures = try DrawingInspectorControlMapping.linearRoutes.map {
            try previewAlphaSignature(.linearRoute($0))
        }
        try expect(
            Set(routeSignatures).count == routeSignatures.count,
            "Expected Straight and Curved inspector previews to have distinct images"
        )

        for arrowhead in DrawingInspectorControlMapping.arrowheads {
            let startPreview = DrawingInspectorPreview.arrowhead(
                arrowhead,
                pointsRight: false
            )
            let endPreview = DrawingInspectorPreview.arrowhead(
                arrowhead,
                pointsRight: true
            )
            let startGeometry = DrawingInspectorPreview.arrowheadGeometry(
                arrowhead,
                pointsRight: false,
                in: previewRect
            )
            let endGeometry = DrawingInspectorPreview.arrowheadGeometry(
                arrowhead,
                pointsRight: true,
                in: previewRect
            )

            try expect(
                startGeometry.linear.points == endGeometry.linear.points
                    && startGeometry.linear.points[0].x < startGeometry.linear.points[1].x,
                "Expected \(arrowhead) preview shafts to consistently run left to right"
            )
            try expect(
                startGeometry.tip == startGeometry.linear.points[0]
                    && startGeometry.adjacent == startGeometry.linear.points[1]
                    && startGeometry.linear.startArrowhead == arrowhead
                    && startGeometry.linear.endArrowhead == .none,
                "Expected \(arrowhead) Start preview to attach at and face outward from the left endpoint"
            )
            try expect(
                endGeometry.tip == endGeometry.linear.points[1]
                    && endGeometry.adjacent == endGeometry.linear.points[0]
                    && endGeometry.linear.startArrowhead == .none
                    && endGeometry.linear.endArrowhead == arrowhead,
                "Expected \(arrowhead) End preview to attach at and face outward from the right endpoint"
            )

            let startSignature = try previewAlphaSignature(startPreview)
            let endSignature = try previewAlphaSignature(endPreview)
            try expect(
                startSignature.horizontallyMirrored() == endSignature,
                "Expected \(arrowhead) Start and End preview images to face in opposite directions"
            )
            if arrowhead != .none {
                try expect(
                    startSignature.painted.contains(true)
                        && endSignature.painted.contains(true),
                    "Expected normalized \(arrowhead) previews to remain visible without clipping"
                )
            }
        }

        let layerActions = DrawingInspectorControlMapping.layerActions
        try expect(
            layerActions.map(\.label) == [
                "Send to back",
                "Send backward",
                "Bring forward",
                "Bring to front"
            ]
                && layerActions.map(\.toolTip) == [
                    "Send to back — Cmd+Option+[",
                    "Send backward — Cmd+[",
                    "Bring forward — Cmd+]",
                    "Bring to front — Cmd+Option+]"
                ],
            "Expected exact Layers order, labels, and Option terminal shortcuts"
        )
        let layerPaths = layerActions.map {
            DrawingInspectorPreview.layerActionPath($0.action, in: previewRect)
        }
        try expect(
            layerPaths.allSatisfy {
                let bounds = $0.boundingBoxOfPath
                return bounds.width <= 16.001
                    && bounds.height <= 16.001
                    && abs(bounds.midX - previewRect.midX) < 0.001
            },
            "Expected every Layers glyph to fit its centered 16-point model"
        )
        let sendBackwardPoints = AnnotationRoughStroke.sampledPoints(
            on: layerPaths[1]
        )
        let bringForwardPoints = AnnotationRoughStroke.sampledPoints(
            on: layerPaths[2]
        )
        let sendToBackPoints = AnnotationRoughStroke.sampledPoints(
            on: layerPaths[0]
        )
        let bringToFrontPoints = AnnotationRoughStroke.sampledPoints(
            on: layerPaths[3]
        )
        try expect(
            zip(sendBackwardPoints, bringForwardPoints).allSatisfy {
                abs($0.x - $1.x) < 0.001
                    && abs(($0.y + $1.y) - previewRect.midY * 2) < 0.001
            }
                && zip(sendToBackPoints, bringToFrontPoints).allSatisfy {
                    abs($0.x - $1.x) < 0.001
                        && abs(($0.y + $1.y) - previewRect.midY * 2) < 0.001
                }
                && bringForwardPoints.contains(
                    CGPoint(x: previewRect.midX, y: previewRect.midY - 4.7)
                )
                && bringToFrontPoints.contains(
                    CGPoint(x: previewRect.midX, y: previewRect.midY - 1.3)
                ),
            "Expected exact vertically mirrored one-step and terminal arrow geometry"
        )

        let sloppinessPaths = AnnotationSloppiness.allCases.map {
            DrawingInspectorPreview.sloppinessPreviewPaths($0, in: previewRect)
        }
        try expect(
            sloppinessPaths.map(\.count) == [1, 2, 2]
                && Set(
                    try AnnotationSloppiness.allCases.map {
                        try previewAlphaSignature(.sloppiness($0))
                    }
                ).count == 3,
            "Expected fixed one-pass, subtle two-pass, and clearly rough two-pass previews"
        )

        let lightAuditedIdle =
            DrawingControlAppearanceResolver.resolveAuditedPropertyTile(
                DrawingControlVisualState(),
                appearance: NSAppearance(named: .aqua)
            )
        let lightAuditedSelected =
            DrawingControlAppearanceResolver.resolveAuditedPropertyTile(
                DrawingControlVisualState(isSelected: true),
                appearance: NSAppearance(named: .aqua)
            )
        let darkAuditedIdle =
            DrawingControlAppearanceResolver.resolveAuditedPropertyTile(
                DrawingControlVisualState(),
                appearance: NSAppearance(named: .darkAqua)
            )
        let darkAuditedSelected =
            DrawingControlAppearanceResolver.resolveAuditedPropertyTile(
                DrawingControlVisualState(isSelected: true),
                appearance: NSAppearance(named: .darkAqua)
            )
        try expect(
            lightAuditedIdle.background == DrawingControlColor(
                red: 0xF6 / 255,
                green: 0xF6 / 255,
                blue: 0xF9 / 255
            )
                && lightAuditedIdle.content == DrawingControlColor(
                    red: 0x1B / 255,
                    green: 0x1B / 255,
                    blue: 0x1F / 255
                )
                && lightAuditedSelected.background == DrawingControlColor(
                    red: 0xE0 / 255,
                    green: 0xDF / 255,
                    blue: 1
                )
                && lightAuditedSelected.content == DrawingControlColor(
                    red: 0x03 / 255,
                    green: 0,
                    blue: 0x64 / 255
                )
                && darkAuditedIdle.background == DrawingControlColor(
                    red: 0x2E / 255,
                    green: 0x2D / 255,
                    blue: 0x39 / 255
                )
                && darkAuditedIdle.content == DrawingControlColor(
                    red: 0xE3 / 255,
                    green: 0xE3 / 255,
                    blue: 0xE8 / 255
                )
                && darkAuditedSelected.background == DrawingControlColor(
                    red: 0x40 / 255,
                    green: 0x3E / 255,
                    blue: 0x6A / 255
                )
                && darkAuditedSelected.content == DrawingControlColor(
                    red: 0xE0 / 255,
                    green: 0xDF / 255,
                    blue: 1
                ),
            "Expected exact audited Layers and Sloppiness idle/selected colors"
        )
    }

    private static func testDrawingToolShortcuts() throws {
        try expect(
            DrawingToolbarVisualMetrics.shellHeight == 54
                && DrawingToolbarVisualMetrics.desktopWidth == 648
                && DrawingToolbarVisualMetrics.shellInset == 5
                && DrawingToolbarVisualMetrics.shellCornerRadius == 15
                && DrawingToolbarVisualMetrics.buttonSide == 44
                && DrawingToolbarVisualMetrics.dragHandleWidth == 24
                && DrawingToolbarVisualMetrics.buttonCornerRadius == 10
                && (19...21).contains(
                    DrawingToolbarVisualMetrics.iconPointSize
                )
                && DrawingToolbarVisualMetrics.numericHintFontSize == 11
                && DrawingToolbarVisualMetrics.numericHintFontDesign
                    == "system-regular"
                && DrawingToolShortcuts.DrawingToolbarStructure.orderedGroups
                    == [.hand, .mainTools, .overflow],
            "Expected larger toolbar tiles and legible Excalidraw-style numeric hints"
        )
        let expectedNumericTools: [(String, UInt16, AnnotationTool)] = [
            ("1", 18, .select),
            ("2", 19, .rectangle),
            ("3", 20, .diamond),
            ("4", 21, .ellipse),
            ("5", 23, .arrow),
            ("6", 22, .line),
            ("7", 26, .pen),
            ("8", 28, .text),
            ("0", 29, .eraser)
        ]
        for (key, keyCode, tool) in expectedNumericTools {
            try expect(
                DrawingToolShortcuts.numericCommand(
                    characters: key,
                    keyCode: keyCode,
                    modifierFlags: [],
                    isDrawingMode: true,
                    isTyping: false
                ) == .setTool(tool),
                "Expected \(key) to select \(tool)"
            )
        }
        try expect(
            DrawingToolShortcuts.numericCommand(
                characters: "9",
                keyCode: 25,
                modifierFlags: [],
                isDrawingMode: true,
                isTyping: false
            ) == nil,
            "Expected 9 to remain unassigned while image insertion is unsupported"
        )
        try expect(
            DrawingToolShortcuts.numericCommand(
                characters: "1",
                keyCode: 83,
                modifierFlags: [.numericPad],
                isDrawingMode: true,
                isTyping: false
            ) == .setTool(.select),
            "Expected numeric-pad characters to use the same numeric mapping"
        )
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            try expect(
                DrawingToolShortcuts.numericCommand(
                    characters: "2",
                    keyCode: 19,
                    modifierFlags: modifier,
                    isDrawingMode: true,
                    isTyping: false
                ) == nil,
                "Expected Command, Control, and Option number keys to preserve existing shortcuts"
            )
        }
        try expect(
            DrawingToolShortcuts.numericCommand(
                characters: "1",
                keyCode: 18,
                modifierFlags: [.shift],
                isDrawingMode: true,
                isTyping: false
            ) == .setTool(.select)
                && DrawingToolShortcuts.numericCommand(
                    characters: "!",
                    keyCode: 19,
                    modifierFlags: [.shift],
                    isDrawingMode: true,
                    isTyping: false
                ) == .setTool(.rectangle),
            "Expected shifted physical number-row keys to resolve by ANSI keyCode"
        )
        try expect(
            DrawingToolShortcuts.numericCommand(
                characters: "8",
                keyCode: 28,
                modifierFlags: [],
                isDrawingMode: true,
                isTyping: true
            ) == nil,
            "Expected number keys to remain text input while typing"
        )
        try expect(
            DrawingToolShortcuts.numericCommand(
                characters: "8",
                keyCode: 28,
                modifierFlags: [],
                isDrawingMode: false,
                isTyping: false
            ) == nil,
            "Expected numeric tool shortcuts to apply only while drawing"
        )

        let expectedLegacyCommands: [(String, Bool, AppCommand)] = [
            ("v", false, .setTool(.select)),
            (" ", false, .setTool(.hand)),
            ("f", false, .setTool(.pen)),
            ("l", false, .setTool(.line)),
            ("a", false, .setTool(.arrow)),
            ("e", true, .setTool(.eraser)),
            ("h", false, .setTool(.highlighter)),
            ("t", false, .toggleTyping(rightAligned: false)),
            ("t", true, .toggleTyping(rightAligned: true))
        ]
        for (key, shift, command) in expectedLegacyCommands {
            try expect(
                DrawingToolShortcuts.legacyCommand(
                    characters: key,
                    shift: shift
                ) == command,
                "Expected legacy drawing shortcut \(key) to remain compatible"
            )
        }
        try expect(
            DrawingToolShortcuts.legacyCommand(characters: "e", shift: false) == nil,
            "Expected plain E to remain the clear command rather than selecting Eraser"
        )
        try expect(
            DrawingToolShortcuts.metadata(for: .highlighter)?.numericHint == nil
                && DrawingToolShortcuts.metadata(for: .highlighter)?.legacyHint
                    == "H",
            "Expected visible Highlighter to remain unnumbered while advertising H"
        )

        let visibleNumericHints = DrawingToolShortcuts.toolbarMetadata.compactMap(\.numericHint)
        try expect(
            visibleNumericHints.count == expectedNumericTools.count
                && expectedNumericTools.allSatisfy {
                    DrawingToolShortcuts.metadata(for: $0.2)?.numericHint == $0.0
                }
                && !visibleNumericHints.contains("9"),
            "Expected toolbar numeric hints to match the supported tool mapping"
        )
        try expect(
            DrawingToolShortcuts.reservedNumericHints == ["9"],
            "Expected unsupported Image to reserve 9 without rendering a misleading tool"
        )
        try expect(
            DrawingSelectionShortcut.arrangeAction(
                key: "[",
                command: true,
                option: true,
                shift: false
            ) == .sendToBack
                && DrawingSelectionShortcut.arrangeAction(
                    key: "[",
                    command: true,
                    option: false,
                    shift: false
                ) == .sendBackward
                && DrawingSelectionShortcut.arrangeAction(
                    key: "]",
                    command: true,
                    option: false,
                    shift: false
                ) == .bringForward
                && DrawingSelectionShortcut.arrangeAction(
                    key: "]",
                    command: true,
                    option: true,
                    shift: false
                ) == .bringToFront
                && DrawingSelectionShortcut.arrangeAction(
                    key: "]",
                    command: true,
                    option: false,
                    shift: true
                ) == .bringToFront,
            "Expected Command+Option terminal layer shortcuts with Shift compatibility"
        )
        try expect(
            DrawingToolShortcuts.metadata(for: .select)?.toolTip(label: "Select")
                == "Select (1, V)"
                && DrawingToolShortcuts.metadata(for: .rectangle)?.toolTip(
                    label: "Rectangle"
                ) == "Rectangle (2, Control-drag)"
                && DrawingToolShortcuts.metadata(for: .diamond)?.toolTip(label: "Diamond")
                    == "Diamond (3)"
                && DrawingToolShortcuts.metadata(for: .highlighter)?.toolTip(
                    label: "Highlighter"
                ) == "Highlighter (H)",
            "Expected tooltips to include numeric and legacy shortcuts where applicable"
        )
    }

    private static func testDrawingToolbarLifecycleAndPlacement() throws {
        try expect(
            DrawingToolbarLifecycle.shouldShow(
                isOverlayPresented: true,
                isDrawingAccessoryActive: true
            ),
            "Expected toolbar to show while a drawing accessory session is active"
        )
        try expect(
            !DrawingToolbarLifecycle.shouldShow(
                isOverlayPresented: true,
                isDrawingAccessoryActive: false
            )
                && !DrawingToolbarLifecycle.shouldShow(
                    isOverlayPresented: false,
                    isDrawingAccessoryActive: true
                ),
            "Expected toolbar lifecycle to hide outside drawing accessory sessions"
        )
        var activeControlInteraction = DrawingAccessoryInteractionState()
        activeControlInteraction.controlTracking = true
        try expect(
                DrawingToolbarLifecycle.shouldShow(
                    isOverlayPresented: true,
                    isDrawingAccessoryActive: false,
                    interactionState: activeControlInteraction
                ),
                "Expected an active inspector control to prevent lifecycle hide"
        )
        try expect(
            DrawingAccessoryLifecycle.isActive(
                interactionMode: .staticZoom,
                isDrawingMode: true,
                resumesDrawingAfterTyping: false
            )
                && DrawingAccessoryLifecycle.isActive(
                    interactionMode: .typing,
                    isDrawingMode: false,
                    resumesDrawingAfterTyping: true
                )
                && !DrawingAccessoryLifecycle.isActive(
                    interactionMode: .typing,
                    isDrawingMode: false,
                    resumesDrawingAfterTyping: false
                ),
            "Expected drawing-originated typing to remain in the drawing accessory lifecycle"
        )

        let visibleFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let panelSize = CGSize(width: 300, height: 50)
        let dragged = DrawingToolbarPlacement.draggedOrigin(
            initialOrigin: CGPoint(x: 250, y: 400),
            initialPointerScreenLocation: CGPoint(x: 500, y: 600),
            currentPointerScreenLocation: CGPoint(x: 440, y: 675)
        )
        try expect(
            dragged == CGPoint(x: 190, y: 475),
            "Expected toolbar dragging to apply global pointer deltas to the initial frame"
        )
        let clamped = DrawingToolbarPlacement.clampedOrigin(
            CGPoint(x: -1_000, y: 10_000),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        try expect(
            clamped.x >= visibleFrame.minX
                && clamped.y >= visibleFrame.minY
                && clamped.x + panelSize.width <= visibleFrame.maxX
                && clamped.y + panelSize.height <= visibleFrame.maxY,
            "Expected toolbar origin to clamp to the active display"
        )

        let original = CGPoint(x: 360, y: 520)
        let normalized = DrawingToolbarPlacement.normalizedPosition(
            origin: original,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        let restored = DrawingToolbarPlacement.origin(
            normalizedPosition: normalized,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        try expect(
            abs(restored.x - original.x) < 0.001 && abs(restored.y - original.y) < 0.001,
            "Expected normalized toolbar positioning to round-trip"
        )
        let defaultToolbarOrigin = DrawingToolbarPlacement.defaultOrigin(
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        try expect(
            abs(defaultToolbarOrigin.x - (visibleFrame.midX - panelSize.width / 2)) < 0.001
                && defaultToolbarOrigin.y > visibleFrame.midY,
            "Expected the horizontal toolbar to default near the top center"
        )
        let compactToolbarSize = DrawingToolbarLayout.preferredSize(
            mainContentSize: CGSize(width: 720, height: 30),
            pathActionsSize: CGSize(width: 63, height: 30),
            maximumWidth: 520
        )
        let compactToolbarFrames = DrawingToolbarLayout.frames(
            in: CGRect(origin: .zero, size: compactToolbarSize),
            pathActionsSize: CGSize(width: 63, height: 30)
        )
        try expect(
            compactToolbarSize.width == 520
                && compactToolbarSize.height < 60
                && compactToolbarFrames.scrollFrame.height > 0
                && compactToolbarFrames.pathActionsFrame.minX
                    >= compactToolbarFrames.scrollFrame.maxX,
            "Expected compact path actions to remain beside a horizontal scrolling tool strip"
        )

        for tool in [
            AnnotationTool.rectangle,
            .diamond,
            .ellipse,
            .arrow,
            .line,
            .pen,
            .highlighter,
            .text
        ] {
            let sections = DrawingInspectorSectionMatrix.sections(for: tool)
            let layout = DrawingInspectorSectionMatrix
                .DrawingToolbarHorizontalSectionPacker.layout(
                    sections: sections,
                    availableWidth: 552
                )
            try expect(
                layout.rows.count <= 3
                    && layout.rows.flatMap { $0 } == sections,
                "Expected \(tool) attached properties to preserve exact section order "
                    + "in at most three rows on a 600-point display"
            )
        }

        let narrowAttachedLayout = DrawingInspectorSectionMatrix
            .DrawingToolbarHorizontalSectionPacker.layout(
                sections: DrawingInspectorSectionMatrix.sections(for: .rectangle),
                availableWidth: 220
            )
        try expect(
            narrowAttachedLayout.rows.flatMap { $0 }
                == DrawingInspectorSectionMatrix.sections(for: .rectangle)
                && narrowAttachedLayout.documentWidth <= 220
                && narrowAttachedLayout.rowWidths.allSatisfy { $0 <= 220 },
            "Expected narrow attached layouts to add rows instead of widening the document"
        )

        let attachedToolbar = CGRect(x: 300, y: 650, width: 300, height: 50)
        let attached = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: attachedToolbar,
            contentSize: CGSize(width: 208, height: 200),
            visibleFrame: visibleFrame
        )
        let attachedAfterContentChange = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: attachedToolbar,
            contentSize: CGSize(width: 208, height: 100),
            visibleFrame: visibleFrame,
            previousAlignment: .below
        )
        try expect(
            attached.width == 232
                && attached.minX == attachedToolbar.minX
                && attached.maxY == attachedToolbar.minY
                    - DrawingAttachedInspectorPlacement.gap
                && attachedAfterContentChange.maxY == attached.maxY
                && attachedToolbar == CGRect(x: 300, y: 650, width: 300, height: 50),
            "Expected attached content height changes to leave the toolbar frame stable"
        )
        let attachedAbove = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: CGRect(x: 300, y: 220, width: 300, height: 50),
            contentSize: CGSize(width: 208, height: 200),
            visibleFrame: visibleFrame
        )
        let attachedClampedRight = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: CGRect(x: 800, y: 650, width: 200, height: 50),
            contentSize: CGSize(width: 208, height: 200),
            visibleFrame: visibleFrame
        )
        let attachedAlignedRight = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: CGRect(x: 600, y: 650, width: 200, height: 50),
            contentSize: CGSize(width: 208, height: 200),
            visibleFrame: visibleFrame
        )
        try expect(
            attachedAbove.minY == 276
                && attachedClampedRight.maxX
                    == visibleFrame.maxX
                        - DrawingAttachedInspectorPlacement.screenMargin
                && attachedAlignedRight.maxX == 800
                && visibleFrame.contains(attachedAbove)
                && visibleFrame.contains(attachedClampedRight),
            "Expected attached mode to flip above when needed and remain screen-clamped"
        )
        let hysteresisContent = CGSize(
            width: 600,
            height: 100
        )
        let hysteresisThresholdY = visibleFrame.minY
            + DrawingAttachedInspectorPlacement.screenMargin
            + DrawingAttachedInspectorPlacement.gap
            + hysteresisContent.height
            + DrawingInspectorVisualMetrics.attachedVerticalInset * 2
        let hysteresisFrame = CGRect(
            x: 300,
            y: hysteresisThresholdY,
            width: 300,
            height: 50
        )
        let retainedBelow = DrawingAttachedInspectorPlacement.result(
            toolbarFrame: hysteresisFrame,
            contentSize: hysteresisContent,
            visibleFrame: visibleFrame,
            previousAlignment: .below
        )
        let flippedAbove = DrawingAttachedInspectorPlacement.result(
            toolbarFrame: CGRect(
                x: 300,
                y: hysteresisThresholdY - 1,
                width: 300,
                height: 50
            ),
            contentSize: hysteresisContent,
            visibleFrame: visibleFrame,
            previousAlignment: .below
        )
        try expect(
            retainedBelow.alignment == .below
                && flippedAbove.alignment == .above
                && [retainedBelow.alignment, flippedAbove.alignment].allSatisfy {
                    $0 == .below || $0 == .above
                },
            "Expected attached mode to remain vertically attached across the flip threshold"
        )

        struct TestScreen: Equatable {
            let name: String
            let frame: CGRect
            let visibleFrame: CGRect
        }
        let secondaryScreen = TestScreen(
            name: "secondary",
            frame: CGRect(x: 1_200, y: 0, width: 1_000, height: 700),
            visibleFrame: CGRect(x: 1_200, y: 0, width: 1_000, height: 676)
        )
        let secondaryToolbar = CGRect(x: 1_520, y: 590, width: 360, height: 50)

        let secondaryAttached = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: secondaryToolbar,
            contentSize: CGSize(width: 208, height: 180),
            visibleFrame: secondaryScreen.visibleFrame
        )
        let secondaryAttachedAfterHeightChange = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: secondaryToolbar,
            contentSize: CGSize(width: 208, height: 240),
            visibleFrame: secondaryScreen.visibleFrame,
            previousAlignment: .below
        )
        let lowerSecondaryToolbar = CGRect(x: 2_050, y: 18, width: 260, height: 50)
        let secondaryAttachedAbove = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: lowerSecondaryToolbar,
            contentSize: CGSize(width: 208, height: 180),
            visibleFrame: secondaryScreen.visibleFrame
        )
        try expect(
            secondaryAttached.maxY
                == secondaryToolbar.minY - DrawingAttachedInspectorPlacement.gap
                && secondaryAttachedAfterHeightChange.maxY == secondaryAttached.maxY
                && secondaryAttachedAbove.minY
                    == lowerSecondaryToolbar.maxY + DrawingAttachedInspectorPlacement.gap
                && secondaryAttachedAbove.maxX
                    == secondaryScreen.visibleFrame.maxX
                        - DrawingAttachedInspectorPlacement.screenMargin
                && secondaryScreen.visibleFrame.contains(secondaryAttached)
                && secondaryScreen.visibleFrame.contains(secondaryAttachedAfterHeightChange)
                && secondaryScreen.visibleFrame.contains(secondaryAttachedAbove),
            "Expected attached inspector height updates, flipping, and clamping to use the "
                + "toolbar's secondary display"
        )

        let initialToolbarFrame = CGRect(
            x: 300,
            y: 620,
            width: 698,
            height: 54
        )
        let initialInspectorFrame = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: initialToolbarFrame,
            contentSize: CGSize(width: 669, height: 66),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let inspectorOffset = CGPoint(
            x: initialInspectorFrame.minX - initialToolbarFrame.minX,
            y: initialInspectorFrame.minY - initialToolbarFrame.minY
        )
        let dragSamples = stride(from: 0, through: 240, by: 8).map {
            CGPoint(
                x: initialToolbarFrame.minX + CGFloat($0),
                y: initialToolbarFrame.minY - CGFloat($0) * 0.45
            )
        }
        try expect(
            dragSamples.allSatisfy { proposed in
                let toolbarOrigin = DrawingAttachedInspectorDragLock
                    .clampedToolbarOrigin(
                        proposed,
                        toolbarSize: initialToolbarFrame.size,
                        inspectorOffset: inspectorOffset,
                        inspectorSize: initialInspectorFrame.size,
                        visibleFrame: CGRect(
                            x: 0,
                            y: 0,
                            width: 1_440,
                            height: 900
                        )
                    )
                let inspectorOrigin = DrawingAttachedInspectorDragLock
                    .inspectorOrigin(
                        toolbarOrigin: toolbarOrigin,
                        inspectorOffset: inspectorOffset
                    )
                return inspectorOrigin.x - toolbarOrigin.x == inspectorOffset.x
                    && inspectorOrigin.y - toolbarOrigin.y == inspectorOffset.y
            },
            "Expected toolbar and inspector relative offsets to remain exactly invariant at every drag sample"
        )

        let portraitVisibleFrame = CGRect(
            x: 1_440,
            y: 0,
            width: 430,
            height: 800
        )
        let destinationMaximumWidth = portraitVisibleFrame.width
            - DrawingToolbarLayout.screenMargin * 2
        let destinationToolbarSize = DrawingToolbarLayout.preferredSize(
            mainContentSize: CGSize(width: 720, height: 44),
            pathActionsSize: CGSize(width: 63, height: 30),
            maximumWidth: destinationMaximumWidth
        )
        let destinationToolbarOrigin = DrawingToolbarPlacement.clampedOrigin(
            CGPoint(x: 1_700, y: 690),
            panelSize: destinationToolbarSize,
            visibleFrame: portraitVisibleFrame
        )
        let destinationToolbarFrame = CGRect(
            origin: destinationToolbarOrigin,
            size: destinationToolbarSize
        )
        let destinationToolbarFrames = DrawingToolbarLayout.frames(
            in: CGRect(origin: .zero, size: destinationToolbarSize),
            pathActionsSize: CGSize(width: 63, height: 30)
        )
        let destinationInspectorFrame = DrawingAttachedInspectorPlacement.frame(
            toolbarFrame: destinationToolbarFrame,
            contentSize: CGSize(width: 669, height: 66),
            visibleFrame: portraitVisibleFrame
        )
        let persistedDestinationPosition = DrawingToolbarPlacement.normalizedPosition(
            origin: destinationToolbarFrame.origin,
            panelSize: destinationToolbarFrame.size,
            visibleFrame: portraitVisibleFrame
        )
        let restoredDestinationOrigin = DrawingToolbarPlacement.origin(
            normalizedPosition: persistedDestinationPosition,
            panelSize: destinationToolbarFrame.size,
            visibleFrame: portraitVisibleFrame
        )
        let inspectorRemainsAttached =
            destinationInspectorFrame.maxY
                == destinationToolbarFrame.minY - DrawingAttachedInspectorPlacement.gap
            || destinationInspectorFrame.minY
                == destinationToolbarFrame.maxY + DrawingAttachedInspectorPlacement.gap
        try expect(
            destinationToolbarSize.width == destinationMaximumWidth
                && destinationToolbarSize.width < initialToolbarFrame.width
                && destinationToolbarFrames.scrollFrame.width > 0
                && destinationToolbarFrames.pathActionsFrame.maxX
                    <= destinationToolbarSize.width
                && portraitVisibleFrame.contains(destinationToolbarFrame)
                && portraitVisibleFrame.contains(destinationInspectorFrame)
                && inspectorRemainsAttached
                && abs(restoredDestinationOrigin.x - destinationToolbarOrigin.x) < 0.001
                && abs(restoredDestinationOrigin.y - destinationToolbarOrigin.y) < 0.001,
            "Expected a cross-display drag to reflow toolbar controls and attached inspector "
                + "before persisting on a narrower portrait display"
        )
        try expect(
            DrawingAccessoryEventDispatch.bracketsControlTracking(.leftMouseDown)
                && DrawingAccessoryEventDispatch.bracketsControlTracking(.rightMouseDown)
                && DrawingAccessoryEventDispatch.bracketsControlTracking(.otherMouseDown)
                && !DrawingAccessoryEventDispatch.bracketsControlTracking(.leftMouseUp)
                && !DrawingAccessoryEventDispatch.bracketsControlTracking(.scrollWheel),
            "Expected mouse-down dispatch to bracket accessory control tracking"
        )
        var selectedCommand: AppCommand?
        let toolbarView = DrawingToolbarView(
            commandSink: { selectedCommand = $0 },
            showOverflow: { _ in }
        )
        toolbarView.activateTool(.ellipse)
        guard case .setTool(.ellipse)? = selectedCommand else {
            throw SelfTestError.failure(
                "Expected the first toolbar click to dispatch the selected tool"
            )
        }
        try expect(
            toolbarView.isToolSelected(.ellipse),
            "Expected toolbar selection state to update synchronously on the first click"
        )

        let pendingController = AnnotationController()
        pendingController.currentTool = .line
        pendingController.begin(at: CGPoint(x: 10, y: 10), tool: .line)
        pendingController.beginLinearConstructionFromClick(
            at: CGPoint(x: 10, y: 10),
            zoomScale: 1
        )
        _ = pendingController.commitLinearConstructionPoint(
            at: CGPoint(x: 80, y: 50),
            zoomScale: 1
        )
        var typingWasResolved = false
        ModeCoordinator.applyDrawingToolSelection(
            .rectangle,
            annotationController: pendingController,
            finishTypingIfNeeded: {
                typingWasResolved = true
            }
        )
        try expect(
            typingWasResolved
                && pendingController.currentTool == .rectangle
                && !pendingController.isConstructingLinearPath
                && pendingController.elementSnapshot.count == 1,
            "Expected tool switching to finish typing, resolve a pending path, and keep the click"
        )

        try expect(
            DrawingCursorPolicy.presentation(
                interactionMode: .typing,
                isDrawingMode: false,
                tool: .text,
                isAccessoryInteractionActive: false,
                isHandPanning: false,
                isLiveZoomInteractive: false
            ) == .iBeam,
            "Expected pre-placement typing to use the native I-beam"
        )
        try expect(
            !DrawingTextCaretPolicy.shouldDrawInsertionCaret(
                interactionMode: .typing,
                isTextInsertionActive: false,
                isAccessoryInteractionActive: false
            )
                && DrawingCursorPolicy.presentation(
                    interactionMode: .typing,
                    isDrawingMode: false,
                    tool: .text,
                    isAccessoryInteractionActive: false,
                    isHandPanning: false,
                    isLiveZoomInteractive: false,
                    isTextInsertionActive: true
                ) == .hidden
                && DrawingTextCaretPolicy.shouldDrawInsertionCaret(
                    interactionMode: .typing,
                    isTextInsertionActive: true,
                    isAccessoryInteractionActive: false
                ),
            "Expected exactly one text indicator: native I-beam before placement, "
                + "then only the insertion caret while editing"
        )
        try expect(
            DrawingCursorPolicy.presentation(
                interactionMode: .typing,
                isDrawingMode: false,
                tool: .text,
                isAccessoryInteractionActive: true,
                isHandPanning: false,
                isLiveZoomInteractive: false,
                isTextInsertionActive: true
            ) == .arrow
                && !DrawingTextCaretPolicy.shouldDrawInsertionCaret(
                    interactionMode: .typing,
                    isTextInsertionActive: true,
                    isAccessoryInteractionActive: true
                ),
            "Expected inspector interaction to show only its native pointer, not a second canvas caret"
        )
        try expect(
            DrawingCursorPolicy.presentation(
                interactionMode: .staticZoom,
                isDrawingMode: true,
                tool: .text,
                isAccessoryInteractionActive: false,
                isHandPanning: false,
                isLiveZoomInteractive: false
            ) == .iBeam
                && DrawingCursorPolicy.presentation(
                    interactionMode: .staticZoom,
                    isDrawingMode: true,
                    tool: .select,
                    isAccessoryInteractionActive: false,
                    isHandPanning: false,
                    isLiveZoomInteractive: false
                ) == .arrow
                && DrawingCursorPolicy.presentation(
                    interactionMode: .staticZoom,
                    isDrawingMode: true,
                    tool: .hand,
                    isAccessoryInteractionActive: false,
                    isHandPanning: true,
                    isLiveZoomInteractive: false
                ) == .closedHand,
            "Expected text, select, and hand tools to use visible system cursors"
        )
        try expect(
            DrawingCursorPolicy.presentation(
                interactionMode: .staticZoom,
                isDrawingMode: true,
                tool: .pen,
                isAccessoryInteractionActive: true,
                isHandPanning: false,
                isLiveZoomInteractive: false
            ) == .arrow
                && DrawingCursorPolicy.presentation(
                    interactionMode: .staticZoom,
                    isDrawingMode: true,
                    tool: .pen,
                    isAccessoryInteractionActive: false,
                    isHandPanning: false,
                    isLiveZoomInteractive: false
                ) == .hidden,
            "Expected toolbar interaction to show an arrow and pen drawing to restore its indicator cursor"
        )
    }

    private static func testDrawingToolbarMenuInteractionLifecycle() throws {
        var state = DrawingAccessoryInteractionState()
        try expect(
            !state.isActive,
            "Expected drawing accessory interaction to start inactive"
        )
        state.menuOpen = true
        try expect(
            state.isActive,
            "Expected overflow-menu tracking to keep drawing accessory interaction active"
        )
        state.menuOpen = false
        try expect(
            !state.isActive,
            "Expected drawing accessory interaction to restore after the menu closes"
        )
        state.popoverOpen = true
        try expect(
            state.isActive && state.preventsLifecycleHide,
            "Expected a separate arrowhead popover window to preserve accessory focus"
        )
        state.popoverOpen = false
        state.pointerOverToolbar = true
        state.menuOpen = true
        state.menuOpen = false
        try expect(
            state.isActive,
            "Expected closing the menu to preserve another active toolbar interaction"
        )
        state.pointerOverToolbar = false
        state.pointerOverInspector = true
        try expect(
            state.isActive && state.preventsLifecycleHide,
            "Expected inspector-window pointer state to cover the full drawing accessory"
        )
        state.pointerOverInspector = false
        state.controlTracking = true
        try expect(
            state.isActive && state.preventsLifecycleHide,
            "Expected inspector controls to prevent lifecycle hide until tracking ends"
        )
        state.controlTracking = false
        state.colorPanelOpen = true
        try expect(
            state.isActive,
            "Expected an active color panel to preserve drawing accessory interaction"
        )
        state.controlTracking = true
        state.menuOpen = true
        state.toolbarDragActive = true
        state.controlTracking = false
        try expect(
            state.colorPanelOpen && state.menuOpen && state.toolbarDragActive && state.isActive,
            "Expected control tracking to remain independent from color, menu, and drag state"
        )
        state.colorPanelOpen = false
        state.menuOpen = false
        state.toolbarDragActive = false
        state.popoverOpen = true
        try expect(
            state.isActive && state.preventsLifecycleHide,
            "Expected an open arrowhead popover to retain drawing accessory focus"
        )
        state.popoverOpen = false
        try expect(
            !state.isActive,
            "Expected drawing accessory focus to release after the final popover closes"
        )
    }

    private static func testArrowheadPopoverClickLifecycle() throws {
        let controller = AnnotationController()
        controller.currentTool = .arrow
        controller.begin(at: CGPoint(x: 20, y: 20), tool: .arrow)
        controller.end(at: CGPoint(x: 120, y: 70))
        controller.currentTool = .select
        controller.selectAll()

        var commands: [AppCommand] = []
        var interactionStates: [DrawingAccessoryInteractionState] = []
        var focusRestoreCount = 0
        let focusView = SelfTestFocusView(
            frame: CGRect(x: 0, y: 0, width: 480, height: 320)
        )
        let host = NSWindow(
            contentRect: focusView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.contentView = focusView
        host.orderFront(nil)
        host.makeFirstResponder(focusView)

        let toolbar = DrawingToolbarController(
            parentWindow: host,
            annotationController: controller,
            toolbarNormalizedPosition: nil,
            commandSink: { command in
                commands.append(command)
                switch command {
                case .setLinearStartArrowhead(let arrowhead):
                    controller.setLinearStartArrowhead(arrowhead)
                case .setLinearEndArrowhead(let arrowhead):
                    controller.setLinearEndArrowhead(arrowhead)
                case .setLinearArrowheadSize(let size):
                    controller.setLinearArrowheadSize(size)
                default:
                    break
                }
            },
            restoreCanvasFocus: {
                focusRestoreCount += 1
                host.makeFirstResponder(focusView)
            },
            toolbarPlacementDidChange: { _ in },
            pointerInteractionChanged: {
                interactionStates.append($0)
            }
        )
        toolbar.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let appWasActive = NSApp.isActive
        NSApp.deactivate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        defer {
            toolbar.close()
            host.orderOut(nil)
            if appWasActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        func physicallySelect(
            _ arrowhead: AnnotationArrowhead,
            with picker: DrawingInspectorArrowheadPicker
        ) throws {
            try dispatchPhysicalClick(on: picker.triggerButtonForTesting)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            guard let palettePanel = picker.palettePanelForTesting,
                  palettePanel.isVisible,
                  let paletteView = palettePanel.contentViewController?.view,
                  let button = descendantViews(
                    of: NSButton.self,
                    in: paletteView
                  ).first(where: {
                      $0.accessibilityLabel() == arrowhead.displayName
                  }) else {
                throw SelfTestError.failure(
                    "Expected a nontransient arrowhead palette and "
                        + "\(arrowhead.displayName) button"
                )
            }
            try expect(
                interactionStates.last?.popoverOpen == true
                    && palettePanel.sharingType == .none
                    && controller.selectedElementSnapshot.count == 1,
                "Expected the arrowhead palette to retain accessory interaction "
                    + "and selection while remaining non-shareable"
            )
            try dispatchPhysicalClick(on: button)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        try expect(
            !NSApp.isActive,
            "Expected the physical arrowhead click test to begin with the app inactive"
        )

        let endPicker = toolbar.endArrowheadPickerForTesting
        commands.removeAll()
        try physicallySelect(.none, with: endPicker)
        guard case .linear(let headless) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a selected headless linear element")
        }
        let headlessState = DrawingToolbarState(annotationController: controller)
        try expect(
            commands == [.setLinearEndArrowhead(.none)]
                && headless.startArrowhead == .none
                && headless.endArrowhead == .none
                && endPicker.palettePanelForTesting == nil
                && controller.currentTool == .select
                && controller.selectedElementSnapshot.count == 1
                && headlessState.visibleInspectorSections.contains(.arrowheads)
                && headlessState.visibleInspectorSections.contains(.arrowheadSize)
                && endPicker.triggerButtonForTesting.superview != nil
                && endPicker.triggerButtonForTesting.window
                    === toolbar.inspectorWindowForTesting
                && endPicker.triggerButtonForTesting.isEnabled,
            "Expected removing the last head to close the palette while retaining "
                + "selection, inspector sections, and enabled attached triggers"
        )
        commands.removeAll()
        try physicallySelect(.diamond, with: endPicker)
        guard case .linear(let restoredHead) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a selected restored arrowhead")
        }
        try expect(
            commands == [.setLinearEndArrowhead(.diamond)]
                && restoredHead.endArrowhead == .diamond
                && endPicker.palettePanelForTesting == nil,
            "Expected the retained trigger to reopen and select a new arrowhead"
        )
        controller.undo()
        guard case .linear(let restoredHeadUndone) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected the restored arrowhead undo target")
        }
        try expect(
            restoredHeadUndone.endArrowhead == .none
                && controller.selectedElementSnapshot.count == 1,
            "Expected one undo to revert the reopened arrowhead selection"
        )
        toolbar.updateState(DrawingToolbarState(annotationController: controller))

        let startPicker = toolbar.startArrowheadPickerForTesting
        commands.removeAll()
        let startFocusRestoreCount = focusRestoreCount
        try physicallySelect(.triangle, with: startPicker)
        guard case .linear(let startEdited) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a selected start-edited arrow")
        }
        try expect(
            commands == [.setLinearStartArrowhead(.triangle)]
                && startEdited.startArrowhead == .triangle
                && controller.selectedElementSnapshot.count == 1
                && controller.currentTool == .select
                && !controller.canRedo
                && startPicker.palettePanelForTesting == nil
                && focusRestoreCount == startFocusRestoreCount + 1
                && host.firstResponder === focusView,
            "Expected one inactive-app physical start-family command, retained "
                + "selection/edit mode, closed palette, and restored canvas focus"
        )
        controller.undo()
        guard case .linear(let startUndone) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected start-arrowhead undo target")
        }
        try expect(
            startUndone.startArrowhead == .none
                && controller.elementSnapshot.count == 1,
            "Expected one undo to revert only the physical start-family command"
        )
        toolbar.updateState(DrawingToolbarState(annotationController: controller))

        commands.removeAll()
        try physicallySelect(.diamond, with: endPicker)
        guard case .linear(let endEdited) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a selected end-edited arrow")
        }
        try expect(
            commands == [.setLinearEndArrowhead(.diamond)]
                && endEdited.endArrowhead == .diamond
                && endPicker.palettePanelForTesting == nil
                && controller.currentTool == .select
                && controller.selectedElementSnapshot.count == 1,
            "Expected one inactive-app physical end-family command with retained "
                + "selection and edit mode"
        )
        controller.undo()
        guard case .linear(let endUndone) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected end-arrowhead undo target")
        }
        try expect(
            endUndone.endArrowhead == .none,
            "Expected one undo to revert only the physical end-family command"
        )
        toolbar.updateState(DrawingToolbarState(annotationController: controller))

        guard let largeSizeButton = descendantViews(
            of: NSButton.self,
            in: toolbar.inspectorWindowForTesting.contentView ?? NSView()
        ).first(where: {
            $0.accessibilityLabel() == AnnotationArrowheadSize.large.displayName
        }) else {
            throw SelfTestError.failure("Expected the Arrow size palette")
        }
        commands.removeAll()
        try dispatchPhysicalClick(on: largeSizeButton)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard case .linear(let resized) =
            controller.selectedElementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a resized selected arrow")
        }
        try expect(
            commands == [.setLinearArrowheadSize(.large)]
                && resized.arrowheadSize == .large,
            "Expected the existing Arrow size palette to remain first-click interactive"
        )

        try dispatchPhysicalClick(on: startPicker.triggerButtonForTesting)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        guard let escapePanel = startPicker.palettePanelForTesting,
              let escape = NSEvent.keyEvent(
                  with: .keyDown,
                  location: .zero,
                  modifierFlags: [],
                  timestamp: 0,
                  windowNumber: escapePanel.windowNumber,
                  context: nil,
                  characters: "\u{1b}",
                  charactersIgnoringModifiers: "\u{1b}",
                  isARepeat: false,
                  keyCode: 53
              ) else {
            throw SelfTestError.failure(
                "Expected an Arrow palette for Escape dismissal"
            )
        }
        escapePanel.sendEvent(escape)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        try expect(
            startPicker.palettePanelForTesting == nil,
            "Expected Escape to close the Arrow palette"
        )

    }

    private static func testDrawingAccessorySuppressionLifecycle() throws {
        var lifecycle = DrawingAccessorySuppressionLifecycle()
        let selector = lifecycle.begin()
        let nestedModal = lifecycle.begin()
        try expect(
            lifecycle.isSuppressed,
            "Expected external selector and nested modal suppression to hide drawing accessories"
        )
        try expect(
            lifecycle.finish(selector) && lifecycle.isSuppressed,
            "Expected finishing one nested suppression not to restore drawing accessories"
        )
        try expect(
            !lifecycle.finish(selector) && lifecycle.isSuppressed,
            "Expected duplicate selector teardown to be idempotent"
        )
        try expect(
            lifecycle.finish(nestedModal) && !lifecycle.isSuppressed,
            "Expected drawing accessories to restore after the final suppression finishes"
        )

        let staleSelector = lifecycle.begin()
        lifecycle.reset()
        let currentSelector = lifecycle.begin()
        try expect(
            !lifecycle.finish(staleSelector) && lifecycle.isSuppressed,
            "Expected stale selector teardown not to release a newer suppression generation"
        )
        try expect(
            lifecycle.finish(currentSelector) && !lifecycle.isSuppressed,
            "Expected the current selector teardown to release its own suppression"
        )
    }

    private static func testDrawingInspectorRuntimePresentationSwitch() throws {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let availableFrame = visibleFrame.insetBy(
            dx: DrawingAttachedInspectorPlacement.screenMargin,
            dy: DrawingAttachedInspectorPlacement.screenMargin
        )
        let parent = NSWindow(
            contentRect: visibleFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        parent.level = .screenSaver

        let annotationController = AnnotationController()
        annotationController.currentTool = .hand
        var persistedToolbarPosition: CGPoint?
        let controller = DrawingToolbarController(
            parentWindow: parent,
            annotationController: annotationController,
            toolbarNormalizedPosition: nil,
            commandSink: { _ in },
            restoreCanvasFocus: {},
            toolbarPlacementDidChange: {
                persistedToolbarPosition = $0
            },
            pointerInteractionChanged: { _ in }
        )
        controller.show()
        controller.inspectorWindowForTesting.setFrame(.zero, display: false)
        try expect(
            !controller.inspectorIsVisibleForTesting,
            "Expected propertyless Hand to start with a hidden inspector"
        )
        try expect(
            controller.inspectorFrameForTesting == .zero,
            "Expected the initial hidden-inspector drag regression to use a zero frame"
        )
        try expect(
            !controller.inspectorHasChromeForTesting
                && controller.toolbarWindowForTesting.delegate == nil,
            "Expected a chrome-free inspector and delegate-free toolbar window"
        )

        controller.applyDragSampleForTesting(
            proposedOrigin: CGPoint(
                x: visibleFrame.maxX + 1_000,
                y: visibleFrame.minY - 1_000
            ),
            visibleFrame: visibleFrame
        )
        let handEdgeToolbarFrame = controller.toolbarFrameForTesting
        try expect(
            abs(handEdgeToolbarFrame.maxX - availableFrame.maxX) < 0.001
                && abs(handEdgeToolbarFrame.minY - availableFrame.minY) < 0.001
                && controller.inspectorFrameForTesting == .zero,
            "Expected Hand edge dragging to clamp only the toolbar and ignore a zero inspector frame"
        )

        annotationController.currentTool = .rectangle
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        try expect(
            controller.inspectorIsVisibleForTesting
                && controller.toolbarFrameForTesting == handEdgeToolbarFrame
                && controller.inspectorWindowForTesting.parent
                    === controller.toolbarWindowForTesting
                && availableFrame.contains(controller.inspectorFrameForTesting),
            "Expected showing the attached inspector after edge placement to leave the toolbar fixed"
        )

        annotationController.currentTool = .select
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let staleSelectInspectorFrame = controller.inspectorFrameForTesting
        try expect(
            !controller.inspectorIsVisibleForTesting
                && staleSelectInspectorFrame.width > 0
                && staleSelectInspectorFrame.height > 0,
            "Expected empty Select to hide the inspector without depending on frame reset"
        )
        controller.applyDragSampleForTesting(
            proposedOrigin: CGPoint(
                x: visibleFrame.minX - 1_000,
                y: visibleFrame.minY - 1_000
            ),
            visibleFrame: visibleFrame
        )
        let selectEdgeToolbarFrame = controller.toolbarFrameForTesting
        try expect(
            abs(selectEdgeToolbarFrame.minX - availableFrame.minX) < 0.001
                && abs(selectEdgeToolbarFrame.minY - availableFrame.minY) < 0.001
                && controller.inspectorFrameForTesting == staleSelectInspectorFrame,
            "Expected empty Select edge dragging to ignore the hidden inspector's stale frame"
        )

        annotationController.currentTool = .rectangle
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let toolbarFrameBeforeHeightTransitions = controller.toolbarFrameForTesting
        annotationController.setShapeBackground(nil)
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let fillOffFrame = controller.inspectorFrameForTesting
        annotationController.setShapeBackground(.palette(.backgroundRed))
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let fillOnFrame = controller.inspectorFrameForTesting
        annotationController.setShapeBackground(nil)
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let fillOffAgainFrame = controller.inspectorFrameForTesting

        func inspectorHugsCurrentContent(_ frame: CGRect) -> Bool {
            abs(
                frame.height
                    - controller.propertiesContentSizeForTesting.height
                    - DrawingInspectorVisualMetrics.attachedVerticalInset * 2
            ) <= 1
                && controller.propertiesContentSizeForTesting.height
                    == controller.propertiesFittingHeightForTesting
                && abs(
                    controller.inspectorDocumentSizeForTesting.height
                        - controller.inspectorViewportSizeForTesting.height
                ) <= 1
                && !controller.inspectorHasHorizontalScrollerForTesting
        }

        try expect(
            controller.toolbarFrameForTesting == toolbarFrameBeforeHeightTransitions
                && fillOnFrame.height > fillOffFrame.height
                && fillOffAgainFrame.height == fillOffFrame.height
                && inspectorHugsCurrentContent(fillOffAgainFrame)
                && availableFrame.contains(fillOffFrame)
                && availableFrame.contains(fillOnFrame)
                && availableFrame.contains(fillOffAgainFrame),
            "Expected Fill off/on/off to grow and shrink the attached inspector exactly "
                + "without moving the toolbar or leaving scrollable empty space"
        )

        annotationController.setShapeBackground(.palette(.backgroundRed))
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let tallFrame = controller.inspectorFrameForTesting
        annotationController.currentTool = .highlighter
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let shortFrame = controller.inspectorFrameForTesting
        annotationController.currentTool = .rectangle
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let tallAgainFrame = controller.inspectorFrameForTesting
        try expect(
            controller.toolbarFrameForTesting == toolbarFrameBeforeHeightTransitions
                && tallFrame.height > shortFrame.height
                && tallAgainFrame.height == tallFrame.height
                && inspectorHugsCurrentContent(tallAgainFrame)
                && availableFrame.contains(tallFrame)
                && availableFrame.contains(shortFrame)
                && availableFrame.contains(tallAgainFrame),
            "Expected tall-to-short-to-tall tool transitions to restore the exact fitting height "
                + "while preserving the adjoining toolbar edge"
        )

        annotationController.setShapeBackground(nil)
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        try expect(
            controller.inspectorIsVisibleForTesting
                && controller.toolbarFrameForTesting == selectEdgeToolbarFrame,
            "Expected a hidden-to-visible tool transition to place the inspector around the current toolbar"
        )

        annotationController.currentTool = .eraser
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let staleEraserInspectorFrame = controller.inspectorFrameForTesting
        controller.applyDragSampleForTesting(
            proposedOrigin: CGPoint(
                x: visibleFrame.maxX + 1_000,
                y: visibleFrame.maxY + 1_000
            ),
            visibleFrame: visibleFrame
        )
        let eraserEdgeToolbarFrame = controller.toolbarFrameForTesting
        try expect(
            !controller.inspectorIsVisibleForTesting
                && abs(eraserEdgeToolbarFrame.maxX - availableFrame.maxX) < 0.001
                && abs(eraserEdgeToolbarFrame.maxY - availableFrame.maxY) < 0.001
                && controller.inspectorFrameForTesting == staleEraserInspectorFrame,
            "Expected Eraser edge dragging to clamp only the toolbar despite stale inspector geometry"
        )

        annotationController.currentTool = .rectangle
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let toolbarFrame = controller.toolbarFrameForTesting
        let inspectorFrame = controller.inspectorFrameForTesting
        let offset = CGPoint(
            x: inspectorFrame.minX - toolbarFrame.minX,
            y: inspectorFrame.minY - toolbarFrame.minY
        )
        controller.applyDragSampleForTesting(
            proposedOrigin: CGPoint(
                x: visibleFrame.minX - 1_000,
                y: visibleFrame.minY - 1_000
            ),
            visibleFrame: visibleFrame
        )
        let clampedToolbarFrame = controller.toolbarFrameForTesting
        let clampedInspectorFrame = controller.inspectorFrameForTesting
        controller.persistCurrentToolbarPositionForTesting(
            visibleFrame: visibleFrame
        )
        let expectedPersistedPosition = DrawingToolbarPlacement
            .normalizedPosition(
                origin: clampedToolbarFrame.origin,
                panelSize: clampedToolbarFrame.size,
                visibleFrame: visibleFrame
            )
        try expect(
            controller.inspectorIsVisibleForTesting
                && clampedInspectorFrame.minX - clampedToolbarFrame.minX == offset.x
                && clampedInspectorFrame.minY - clampedToolbarFrame.minY == offset.y
                && availableFrame.contains(
                    clampedToolbarFrame.union(clampedInspectorFrame)
                ),
            "Expected visible combined dragging to preserve the exact inspector offset and clamp both frames"
        )
        try expect(
            persistedToolbarPosition == expectedPersistedPosition,
            "Expected a completed grip drag to persist the clamped toolbar position"
        )

        controller.close()
        parent.close()
    }

    private static func testDrawingColorPickerCoordinatorLifecycle() throws {
        var state = DrawingColorPickerCoordinatorState()
        try expect(
            state.activate(.stroke) == .started
                && state.transactionActive
                && state.activeChannel == .stroke
                && state.activate(.stroke) == .unchanged
                && state.activate(.background) == .switched
                && state.activeChannel == .background
                && !state.deactivate(.stroke)
                && state.activate(.text) == .switched
                && state.activeChannel == .text
                && state.close()
                && !state.transactionActive
                && state.activeChannel == nil
                && !state.close(),
            "Expected one picker transaction while channels switch without duplicate close events"
        )

        var commands: [AppCommand] = []
        var activityChanges: [Bool] = []
        let inspector = DrawingPropertiesController(
            commandSink: { commands.append($0) },
            colorPanelActivityChanged: { activityChanges.append($0) }
        )
        let annotationController = AnnotationController()
        annotationController.currentTool = .rectangle
        annotationController.setStrokeColor(
            .rgba(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        )
        inspector.update(state: DrawingToolbarState(annotationController: annotationController))

        let host = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 216, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.contentView = inspector.view
        host.orderFront(nil)
        inspector.view.layoutSubtreeIfNeeded()

        let colorWells = descendantViews(of: NSColorWell.self, in: inspector.view)
        guard let strokeWell = colorWells.first(where: {
            $0.accessibilityLabel() == "Custom stroke color"
        }),
        let backgroundWell = colorWells.first(where: {
            $0.accessibilityLabel() == "Custom background color"
        }) else {
            throw SelfTestError.failure("Expected coordinated stroke and background wells")
        }
        let selectedAppearance = strokeWell.accessibilityValue() as? String
        let sharedPanel = NSColorPanel.shared
        let originalParent = sharedPanel.parent
        let originalLevel = sharedPanel.level
        let originalSharingType = sharedPanel.sharingType
        let originalVisibility = sharedPanel.isVisible

        strokeWell.activate(true)
        try expect(
            commands == [.beginContinuousStyleEdit(.colorPicker)]
                && activityChanges == [true]
                && inspector.colorPickerStateForTesting.activeChannel == .stroke
                && inspector.colorPickerStateForTesting.transactionActive
                && colorsMatch(sharedPanel.color, strokeWell.color)
                && strokeWell.accessibilityValue() as? String == "Selected",
            "Expected repeated Stroke activation to open one picker transaction "
                + "(commands \(commands), activity \(activityChanges), channel "
                + "\(String(describing: inspector.colorPickerStateForTesting.activeChannel)), "
                + "transaction \(inspector.colorPickerStateForTesting.transactionActive), "
                + "panel synchronized \(colorsMatch(sharedPanel.color, strokeWell.color)), "
                + "value \(String(describing: strokeWell.accessibilityValue())))"
        )

        let textColor = AnnotationColorValue.rgba(
            red: 0.16,
            green: 0.68,
            blue: 0.42,
            alpha: 1
        )
        annotationController.setTextColor(textColor)
        annotationController.currentTool = .text
        inspector.update(state: DrawingToolbarState(annotationController: annotationController))
        try expect(
            inspector.colorPickerStateForTesting.activeChannel == .text
                && colorsMatch(sharedPanel.color, textColor.nsColor),
            "Expected an open picker to switch to the Text channel and refresh its color"
        )

        annotationController.currentTool = .rectangle
        inspector.update(state: DrawingToolbarState(annotationController: annotationController))
        guard let coralButton = descendantViews(
            of: NSButton.self,
            in: inspector.view
        ).first(where: { $0.accessibilityLabel() == "Stroke Coral" }) else {
            throw SelfTestError.failure("Expected Stroke Coral preset")
        }
        coralButton.performClick(nil)
        NotificationCenter.default.post(
            name: NSColorPanel.colorDidChangeNotification,
            object: sharedPanel
        )
        let adjustedStrokeColor = AnnotationColorValue.rgba(
            red: 0.31,
            green: 0.52,
            blue: 0.73,
            alpha: 0.88
        )
        sharedPanel.color = adjustedStrokeColor.nsColor
        NotificationCenter.default.post(
            name: NSColorPanel.colorDidChangeNotification,
            object: sharedPanel
        )
        try expect(
            commands == [
                .beginContinuousStyleEdit(.colorPicker),
                .setStrokeColor(.palette(.strokeCoral)),
                .setStrokeColor(adjustedStrokeColor)
            ]
                && colorsMatch(strokeWell.color, adjustedStrokeColor.nsColor),
            "Expected a preset to synchronize the open panel without a stale duplicate "
                + "and the next adjustment to continue from that selection "
                + "(commands \(commands), panel \(sharedPanel.color), well \(strokeWell.color))"
        )

        backgroundWell.activate(true)
        let visiblePickerWindows = NSApp.windows.filter {
            guard $0.isVisible else { return false }
            return $0 === sharedPanel
                || String(describing: type(of: $0)).contains("Popover")
        }
        try expect(
            commands == [
                .beginContinuousStyleEdit(.colorPicker),
                .setStrokeColor(.palette(.strokeCoral)),
                .setStrokeColor(adjustedStrokeColor)
            ]
                && activityChanges == [true]
                && inspector.colorPickerStateForTesting.activeChannel == .background
                && colorWells.filter(\.isActive).count == 1
                && visiblePickerWindows.count == 1
                && sharedPanel.parent === host
                && sharedPanel.level.rawValue == host.level.rawValue + 1
                && sharedPanel.sharingType == .none
                && colorsMatch(sharedPanel.color, backgroundWell.color)
                && sharedPanel.isVisible,
            "Expected channel switching to retain one shared color panel "
                + "(active wells \(colorWells.filter(\.isActive).count), "
                + "visible picker windows \(visiblePickerWindows.count), "
                + "parent attached \(sharedPanel.parent === host), "
                + "level elevated \(sharedPanel.level.rawValue == host.level.rawValue + 1), "
                + "sharing disabled \(sharedPanel.sharingType == .none), "
                + "panel synchronized \(colorsMatch(sharedPanel.color, backgroundWell.color)), "
                + "visibility \(sharedPanel.isVisible)/\(originalVisibility))"
        )

        inspector.dismissColorPanel()
        inspector.dismissColorPanel()
        try expect(
            commands == [
                .beginContinuousStyleEdit(.colorPicker),
                .setStrokeColor(.palette(.strokeCoral)),
                .setStrokeColor(adjustedStrokeColor),
                .endContinuousStyleEdit(.colorPicker)
            ]
                && activityChanges == [true, false]
                && !inspector.colorPickerStateForTesting.transactionActive
                && inspector.colorPickerStateForTesting.activeChannel == nil
                && sharedPanel.parent === originalParent
                && sharedPanel.level == originalLevel
                && sharedPanel.sharingType == originalSharingType
                && sharedPanel.isVisible == originalVisibility
                && strokeWell.accessibilityValue() as? String == selectedAppearance,
            "Expected one close, one matching transaction end, and stable custom-tile selection"
        )

        annotationController.currentTool = .select
        inspector.update(state: DrawingToolbarState(annotationController: annotationController))
        try expect(
            !strokeWell.isEnabled
                && strokeWell.toolTip == "Choose a custom stroke color",
            "Expected unavailable custom wells to disable and reset their tooltip"
        )
        annotationController.currentTool = .rectangle
        inspector.update(state: DrawingToolbarState(annotationController: annotationController))
        try expect(
            strokeWell.isEnabled
                && strokeWell.toolTip == "Choose a custom stroke color",
            "Expected custom wells to restore their normal tooltip when available"
        )

        strokeWell.activate(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        try expect(
            colorsMatch(sharedPanel.color, strokeWell.color)
                && commands == [
                    .beginContinuousStyleEdit(.colorPicker),
                    .setStrokeColor(.palette(.strokeCoral)),
                    .setStrokeColor(adjustedStrokeColor),
                    .endContinuousStyleEdit(.colorPicker),
                    .beginContinuousStyleEdit(.colorPicker)
                ]
                && activityChanges == [true, false, true],
            "Expected close and reopen to seed the shared panel from the current Stroke color"
        )
        inspector.dismissColorPanel()

        host.contentView = nil
        host.orderOut(nil)
    }

    private static func testDrawingColorPickerPhysicalClicks() throws {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let host = NSWindow(
            contentRect: visibleFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.level = .screenSaver
        host.orderFront(nil)

        let annotationController = AnnotationController()
        annotationController.currentTool = .rectangle
        var commands: [AppCommand] = []
        let controller = DrawingToolbarController(
            parentWindow: host,
            annotationController: annotationController,
            toolbarNormalizedPosition: nil,
            commandSink: { command in
                commands.append(command)
                switch command {
                case .beginContinuousStyleEdit(let owner):
                    annotationController.beginContinuousStyleEdit(owner: owner)
                case .endContinuousStyleEdit(let owner):
                    _ = annotationController.endContinuousStyleEdit(owner: owner)
                case .setStrokeColor(let color):
                    annotationController.setStrokeColor(color)
                case .setTextColor(let color):
                    annotationController.setTextColor(color)
                case .setShapeBackground(let color):
                    annotationController.setShapeBackground(color)
                default:
                    break
                }
            },
            restoreCanvasFocus: {},
            toolbarPlacementDidChange: { _ in },
            pointerInteractionChanged: { _ in }
        )
        controller.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let originalPolicy = NSApp.activationPolicy()
        let appWasActive = NSApp.isActive
        _ = NSApp.setActivationPolicy(.accessory)
        let sharedPanel = NSColorPanel.shared
        let originalSharedParent = sharedPanel.parent
        let originalSharedLevel = sharedPanel.level
        let originalSharedSharingType = sharedPanel.sharingType
        let originalSharedVisibility = sharedPanel.isVisible
        defer {
            controller.close()
            host.orderOut(nil)
            sharedPanel.level = originalSharedLevel
            sharedPanel.sharingType = originalSharedSharingType
            if let originalSharedParent {
                originalSharedParent.addChildWindow(sharedPanel, ordered: .above)
            } else {
                sharedPanel.parent?.removeChildWindow(sharedPanel)
            }
            if originalSharedVisibility {
                sharedPanel.orderFront(nil)
            } else {
                sharedPanel.orderOut(nil)
            }
            _ = NSApp.setActivationPolicy(originalPolicy)
            if appWasActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        func visibleColorPickerWindows() -> [NSWindow] {
            NSApp.windows.filter {
                guard $0.isVisible else { return false }
                return $0 === sharedPanel
                    || String(describing: type(of: $0)).contains("Popover")
            }
        }

        func customWell(label: String) throws -> NSColorWell {
            guard let contentView = controller.inspectorWindowForTesting.contentView,
                  let well = descendantViews(
                    of: NSColorWell.self,
                    in: contentView
                  ).first(where: { $0.accessibilityLabel() == label }) else {
                throw SelfTestError.failure("Expected \(label)")
            }
            return well
        }

        func exercise(
            tool: AnnotationTool,
            label: String,
            channel: DrawingColorPickerChannel,
            color: AnnotationColorValue,
            expectedColorCommand: AppCommand,
            closeUsingPanel: Bool = false,
            modelMatches: () -> Bool
        ) throws {
            controller.dismissTransientUI()
            annotationController.currentTool = tool
            if channel == .background {
                annotationController.setShapeBackground(.palette(.backgroundRed))
            }
            controller.updateState(
                DrawingToolbarState(annotationController: annotationController)
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let well = try customWell(label: label)
            let toolbarFrame = controller.toolbarFrameForTesting
            let events = try physicalClickEvents(in: well)
            guard let contentView = controller.inspectorWindowForTesting.contentView else {
                throw SelfTestError.failure("Expected attached inspector content")
            }
            let hitPoint = contentView.convert(events.mouseDown.locationInWindow, from: nil)

            commands.removeAll()
            NSApp.deactivate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            try expect(
                !NSApp.isActive
                    && NSApp.activationPolicy() == .accessory
                    && well.isEnabled
                    && well.acceptsFirstMouse(for: events.mouseDown)
                    && contentView.hitTest(hitPoint) === well
                    && well.mouseDownCanMoveWindow == false
                    && well.colorWellStyle != .minimal
                    && visibleColorPickerWindows().isEmpty,
                "Expected the inactive \(channel) custom tile to own its first mouse event "
                    + "without entering toolbar drag handling"
            )

            try dispatchPhysicalMouseClick(in: well)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            try expect(
                NSApp.activationPolicy() == .accessory
                    && controller.toolbarFrameForTesting == toolbarFrame
                    && controller.colorPickerStateForTesting.activeChannel == channel
                    && controller.colorPickerStateForTesting.transactionActive
                    && well.isActive
                    && visibleColorPickerWindows().count == 1
                    && commands == [.beginContinuousStyleEdit(.colorPicker)]
                    && colorsMatch(sharedPanel.color, well.color)
                    && sharedPanel.parent === controller.inspectorWindowForTesting
                    && sharedPanel.level.rawValue
                        == controller.inspectorWindowForTesting.level.rawValue + 1
                    && sharedPanel.sharingType == .none
                    && sharedPanel.isVisible,
                "Expected one shared picker and one transaction for the inactive \(channel) tile "
                    + "(app active \(NSApp.isActive), policy \(NSApp.activationPolicy()), "
                    + "toolbar stable \(controller.toolbarFrameForTesting == toolbarFrame), "
                    + "channel \(String(describing: controller.colorPickerStateForTesting.activeChannel)), "
                    + "transaction \(controller.colorPickerStateForTesting.transactionActive), "
                    + "well active \(well.isActive), windows "
                    + "\(visibleColorPickerWindows().map { String(describing: type(of: $0)) }), "
                    + "commands \(commands), shared visible \(sharedPanel.isVisible))"
            )

            sharedPanel.color = color.nsColor
            NotificationCenter.default.post(
                name: NSColorPanel.colorDidChangeNotification,
                object: sharedPanel
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            try expect(
                commands == [
                    .beginContinuousStyleEdit(.colorPicker),
                    expectedColorCommand
                ]
                    && modelMatches(),
                "Expected the \(channel) picker to dispatch exactly one channel-specific color change "
                    + "(commands \(commands), expected \(expectedColorCommand), "
                    + "model matches \(modelMatches()))"
            )

            if closeUsingPanel {
                sharedPanel.close()
            } else {
                controller.dismissTransientUI()
            }
            controller.dismissTransientUI()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            try expect(
                commands == [
                    .beginContinuousStyleEdit(.colorPicker),
                    expectedColorCommand,
                    .endContinuousStyleEdit(.colorPicker)
                ]
                    && !controller.colorPickerStateForTesting.transactionActive
                    && controller.colorPickerStateForTesting.activeChannel == nil
                    && visibleColorPickerWindows().isEmpty
                    && sharedPanel.parent === originalSharedParent
                    && sharedPanel.level == originalSharedLevel
                    && sharedPanel.sharingType == originalSharedSharingType
                    && sharedPanel.isVisible == originalSharedVisibility,
                "Expected one close and one matching transaction end for the \(channel) picker"
            )
        }

        let strokeColor = AnnotationColorValue.rgba(
            red: 0.12,
            green: 0.34,
            blue: 0.56,
            alpha: 1
        )
        try exercise(
            tool: .rectangle,
            label: "Custom stroke color",
            channel: .stroke,
            color: strokeColor,
            expectedColorCommand: .setStrokeColor(strokeColor),
            modelMatches: {
                annotationController.currentStyle.strokeColor == strokeColor
            }
        )

        let backgroundColor = AnnotationColorValue.rgba(
            red: 0.68,
            green: 0.24,
            blue: 0.42,
            alpha: 0.9
        )
        try exercise(
            tool: .rectangle,
            label: "Custom background color",
            channel: .background,
            color: backgroundColor,
            expectedColorCommand: .setShapeBackground(backgroundColor),
            modelMatches: {
                annotationController.currentStyle.fillColor == backgroundColor
                    && annotationController.currentStyle.fillStyle != .none
            }
        )

        let textColor = AnnotationColorValue.rgba(
            red: 0.22,
            green: 0.72,
            blue: 0.38,
            alpha: 1
        )
        try exercise(
            tool: .text,
            label: "Custom stroke color",
            channel: .text,
            color: textColor,
            expectedColorCommand: .setTextColor(textColor),
            closeUsingPanel: true,
            modelMatches: {
                annotationController.currentStyle.strokeColor == textColor
            }
        )

        let highlighterColor = AnnotationColorValue.rgba(
            red: 0.92,
            green: 0.54,
            blue: 0.16,
            alpha: 0.7
        )
        try exercise(
            tool: .highlighter,
            label: "Custom stroke color",
            channel: .stroke,
            color: highlighterColor,
            expectedColorCommand: .setStrokeColor(highlighterColor),
            modelMatches: {
                annotationController.currentStyle.strokeColor == highlighterColor
            }
        )
    }

    private static func testDrawingToolbarStyleActionsAndEraserHistory() throws {
        let controller = AnnotationController()
        controller.currentTool = .rectangle
        controller.begin(at: CGPoint(x: 10, y: 10))
        controller.end(at: CGPoint(x: 80, y: 80))
        controller.currentTool = .select
        _ = controller.beginSelectionInteraction(
            at: CGPoint(x: 12, y: 40),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        controller.endSelectionInteraction(at: CGPoint(x: 12, y: 40), modifiers: [])

        controller.setStrokeColor(.palette(.green))
        controller.setFillColor(.palette(.yellow))
        controller.setFillStyle(.solid)
        controller.setStrokePattern(.dashed)
        controller.setStrokeWidth(8)
        controller.setSloppiness(.cartoonist)
        controller.setOpacity(0.4)
        controller.setRoundness(12)

        guard let styled = controller.selectedElementSnapshot.first else {
            throw SelfTestError.failure("Expected selected element after toolbar style actions")
        }
        try expect(
            styled.style.strokeColor == .palette(.green)
                && styled.style.fillColor == .palette(.yellow)
                && styled.style.fillStyle == .solid
                && styled.style.strokePattern == .dashed
                && styled.style.strokeWidth == 8
                && styled.style.sloppiness == .cartoonist
                && styled.style.opacity == 0.4
                && styled.style.roundness == 12,
            "Expected toolbar style actions to update selection through the editor boundary"
        )

        controller.currentTool = .eraser
        let committedPixels = try renderControllerPixels(
            controller,
            freehandPresentationOwner: .canonicalRenderer,
            width: 96,
            height: 96
        )
        controller.beginErasing(at: CGPoint(x: 40, y: 40), zoomScale: 1)
        let pendingPixels = try renderControllerPixels(
            controller,
            freehandPresentationOwner: .canonicalRenderer,
            width: 96,
            height: 96
        )
        let capturePixels = try renderControllerPixels(
            controller,
            freehandPresentationOwner: .canonicalRenderer,
            includeTransientEraserFeedback: false,
            width: 96,
            height: 96
        )
        let committedAlpha = alpha(committedPixels, width: 96, x: 40, y: 40)
        let pendingAlpha = alpha(pendingPixels, width: 96, x: 40, y: 40)
        try expect(
            controller.elementSnapshot.count == 1
                && controller.pendingErasureElementIDsForTesting.count == 1
                && pendingAlpha > 0
                && abs(CGFloat(pendingAlpha) / CGFloat(committedAlpha) - 0.28) < 0.08
                && alpha(capturePixels, width: 96, x: 40, y: 40)
                    == committedAlpha,
            "Expected staged erasure to fade only the on-screen presentation"
        )
        controller.cancelErasing()
        try expect(
            controller.elementSnapshot.count == 1
                && controller.pendingErasureElementIDsForTesting.isEmpty,
            "Expected eraser cancellation to restore full presentation without history"
        )
        controller.beginErasing(at: CGPoint(x: 40, y: 40), zoomScale: 1)
        var releaseNotificationCount = 0
        controller.onStateChanged = { releaseNotificationCount += 1 }
        controller.endErasing()
        try expect(
            controller.elementSnapshot.isEmpty
                && releaseNotificationCount == 1,
            "Expected eraser release to remove the staged annotation with one "
                + "scene notification"
        )
        controller.onStateChanged = nil
        controller.undo()
        try expect(controller.elementSnapshot.count == 1, "Expected eraser gesture to undo as one transaction")
        controller.redo()
        try expect(controller.elementSnapshot.isEmpty, "Expected erased annotation to redo")

        controller.undo()
        let beforeZeroHitUndo = controller.elementSnapshot[0].style
        controller.beginErasing(at: CGPoint(x: 200, y: 200), zoomScale: 1)
        controller.endErasing()
        controller.undo()
        try expect(
            controller.elementSnapshot.count == 1
                && controller.elementSnapshot[0].style != beforeZeroHitUndo,
            "Expected a zero-hit eraser release to add no history step"
        )

        let overlapController = AnnotationController()
        overlapController.currentTool = .rectangle
        overlapController.begin(at: CGPoint(x: 10, y: 10))
        overlapController.end(at: CGPoint(x: 70, y: 70))
        overlapController.begin(at: CGPoint(x: 14, y: 14))
        overlapController.end(at: CGPoint(x: 74, y: 74))
        let originalOrder = overlapController.elementSnapshot.map(\.id)
        overlapController.beginErasing(
            at: CGPoint(x: 14, y: 40),
            zoomScale: 1
        )
        try expect(
            overlapController.pendingErasureElementIDsForTesting.count == 2
                && overlapController.elementSnapshot.map(\.id) == originalOrder,
            "Expected one eraser sample to collect every stacked hit without changing z-order"
        )
        let overlapHitTestCount = overlapController.eraserHitTestCountForTesting
        overlapController.continueErasing(
            at: CGPoint(x: 14, y: 40),
            zoomScale: 1
        )
        try expect(
            overlapController.pendingErasureElementIDsForTesting.count == 2
                && overlapController.eraserHitTestCountForTesting
                    == overlapHitTestCount,
            "Expected repeated samples to avoid duplicate hit tests after all stacked elements are pending"
        )
        overlapController.cancelErasing()
    }

    private static func testPendingErasureRasterCompositing() throws {
        var roughShapeStyle = AnnotationStyle(
            color: .blue,
            rootWidth: 4,
            alpha: 0.82,
            fillColor: .rgba(red: 1, green: 0.5, blue: 0, alpha: 0.9),
            fillStyle: .hachure,
            sloppiness: .artist
        )
        roughShapeStyle.strokePattern = .dashed
        let roughShape = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 14, y: 14),
                    end: CGPoint(x: 72, y: 64)
                )
            ),
            style: roughShapeStyle
        )

        var crossHatchStyle = roughShapeStyle
        crossHatchStyle.fillStyle = .crossHatch
        crossHatchStyle.sloppiness = .cartoonist
        let crossHatch = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .diamond,
                    start: CGPoint(x: 22, y: 12),
                    end: CGPoint(x: 82, y: 70)
                )
            ),
            style: crossHatchStyle
        )

        var solidStyle = roughShapeStyle
        solidStyle.fillStyle = .solid
        solidStyle.strokePattern = .solid
        let fillAndStroke = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .ellipse,
                    start: CGPoint(x: 18, y: 14),
                    end: CGPoint(x: 88, y: 70)
                )
            ),
            style: solidStyle
        )

        var pressureStyle = AnnotationStyle(
            color: .black,
            rootWidth: 14,
            alpha: 0.74,
            sloppiness: .artist
        )
        pressureStyle.pressureEnabled = true
        let pressure = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(
                            location: CGPoint(x: 10, y: 42),
                            pressure: 0.2
                        ),
                        AnnotationPointSample(
                            location: CGPoint(x: 42, y: 24),
                            pressure: 0.65
                        ),
                        AnnotationPointSample(
                            location: CGPoint(x: 92, y: 50),
                            pressure: 1
                        )
                    ],
                    isHighlighter: false
                )
            ),
            style: pressureStyle
        )

        var highlighterStyle = AnnotationStyle(
            color: .highlighterYellow,
            rootWidth: 18,
            alpha: 0.8,
            sloppiness: .architect
        )
        highlighterStyle.pressureEnabled = false
        let highlighter = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(
                            location: CGPoint(x: 10, y: 42),
                            pressure: nil
                        ),
                        AnnotationPointSample(
                            location: CGPoint(x: 94, y: 42),
                            pressure: nil
                        )
                    ],
                    isHighlighter: true
                )
            ),
            style: highlighterStyle
        )

        var arrowStyle = AnnotationStyle(
            color: .pink,
            rootWidth: 5,
            alpha: 0.88,
            sloppiness: .artist
        )
        arrowStyle.strokePattern = .dotted
        let compoundArrow = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 12, y: 58),
                        CGPoint(x: 52, y: 18),
                        CGPoint(x: 104, y: 52)
                    ],
                    route: .curved,
                    startArrowhead: .triangle,
                    endArrowhead: .zeroOrMany,
                    arrowheadSize: .large,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: arrowStyle
        )

        let text = AnnotationElement(
            geometry: .text(
                AnnotationTextGeometry(
                    origin: CGPoint(x: 14, y: 18),
                    bounds: nil,
                    text: "Fade",
                    fontSize: 32,
                    fontName: "",
                    alignment: .left,
                    isEditing: false
                )
            ),
            style: AnnotationStyle(
                color: .white,
                rootWidth: 2,
                alpha: 0.76
            )
        )

        let headlessLine = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 12, y: 28),
                        CGPoint(x: 98, y: 54)
                    ],
                    route: .curved,
                    startArrowhead: .none,
                    endArrowhead: .none,
                    startBinding: nil,
                    endBinding: nil,
                    bezierControls: [
                        AnnotationBezierControl(
                            start: CGPoint(x: 38, y: 4),
                            end: CGPoint(x: 74, y: 76)
                        )
                    ]
                )
            ),
            style: AnnotationStyle(
                color: .green,
                rootWidth: 6,
                alpha: 0.7,
                sloppiness: .cartoonist
            )
        )

        var stackStyle = solidStyle
        stackStyle.opacity = 1
        let stackedBottom = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 24, y: 20),
                    end: CGPoint(x: 82, y: 68)
                )
            ),
            style: stackStyle
        )
        var stackedTop = stackedBottom
        stackedTop = AnnotationElement(
            geometry: stackedTop.geometry,
            style: stackStyle
        )

        let families: [(String, [AnnotationElement])] = [
            ("rough hachure", [roughShape]),
            ("rough cross-hatch", [crossHatch]),
            ("solid fill plus stroke", [fillAndStroke]),
            ("pressure freehand", [pressure]),
            ("highlighter", [highlighter]),
            ("filled and compound arrowheads", [compoundArrow]),
            ("text", [text]),
            ("headless line", [headlessLine]),
            ("stacked pending run", [stackedBottom, stackedTop])
        ]

        for destinationScale in [CGFloat(1), 2, 4] {
            for (label, elements) in families {
                let normal = try renderPixels(
                    elements: elements,
                    renderer: AnnotationRenderer(),
                    width: 120,
                    height: 88,
                    destinationPointScale: destinationScale
                )
                let pending = try renderPixels(
                    elements: elements,
                    renderer: AnnotationRenderer(),
                    pendingErasureElementIDs: Set(elements.map(\.id)),
                    width: 120,
                    height: 88,
                    destinationPointScale: destinationScale
                )
                try expectRaster(
                    pending,
                    uniformlyScaling: normal,
                    by: 0.28,
                    context: "\(label) at \(destinationScale)x"
                )
            }
        }
    }

    private static func testReliableEraserSweepAndHitCoverage() throws {
        let controller = AnnotationController()

        controller.currentTool = .pen
        controller.begin(at: CGPoint(x: 20, y: 28))
        controller.end(at: CGPoint(x: 20, y: 52))

        controller.currentTool = .highlighter
        controller.begin(at: CGPoint(x: 42, y: 28))
        controller.end(at: CGPoint(x: 42, y: 52))

        controller.currentTool = .rectangle
        controller.begin(at: CGPoint(x: 58, y: 30))
        controller.end(at: CGPoint(x: 72, y: 50))

        controller.setFillColor(.palette(.yellow))
        controller.setFillStyle(.solid)
        controller.currentTool = .ellipse
        controller.begin(at: CGPoint(x: 78, y: 30))
        controller.end(at: CGPoint(x: 92, y: 50))

        controller.currentTool = .arrow
        controller.begin(at: CGPoint(x: 108, y: 28))
        controller.end(at: CGPoint(x: 108, y: 52))

        controller.setInsertionPoint(CGPoint(x: 124, y: 30))
        controller.beginTypingSession(rightAligned: false)
        controller.insertText("Text")
        controller.finishTypingSession()

        let expectedIDs = Set(controller.elementSnapshot.map(\.id))
        controller.currentTool = .eraser
        var notificationCount = 0
        controller.onStateChanged = { notificationCount += 1 }
        controller.beginErasing(at: CGPoint(x: -40, y: 40), zoomScale: 1)
        let pendingAfterBegin = controller.pendingErasureElementIDsForTesting.count
        let notificationsAfterBegin = notificationCount
        controller.continueErasing(at: CGPoint(x: 180, y: 40), zoomScale: 1)
        let sampleCount = controller.eraserSweepSampleCountForTesting
        let hitTestCount = controller.eraserHitTestCountForTesting
        try expect(
            controller.pendingErasureElementIDsForTesting == expectedIDs
                && pendingAfterBegin == 0
                && notificationsAfterBegin == 0
                && notificationCount == 1
                && sampleCount <= 38
                && hitTestCount <= sampleCount * expectedIDs.count,
            "Expected one fast eraser sweep to stage every crossed annotation family once "
                + "with one candidate evaluation per sample and one redraw: pending="
                + "\(controller.pendingErasureElementIDsForTesting.count)/\(expectedIDs.count), "
                + "beginPending=\(pendingAfterBegin), beginNotifications="
                + "\(notificationsAfterBegin), notifications=\(notificationCount), "
                + "samples=\(sampleCount), "
                + "hitTests=\(hitTestCount)"
        )
        controller.continueErasing(at: CGPoint(x: 180, y: 40), zoomScale: 1)
        try expect(
            controller.pendingErasureElementIDsForTesting == expectedIDs
                && notificationCount == 1,
            "Expected duplicate eraser samples to leave the pending union and redraw count unchanged"
        )
        controller.cancelErasing()
        try expect(
            controller.elementSnapshot.count == expectedIDs.count
                && controller.pendingErasureElementIDsForTesting.isEmpty
                && notificationCount == 2,
            "Expected cancellation to restore the full staged sweep with one redraw and no deletion"
        )

        var cartoonistStyle = AnnotationStyle.default
        cartoonistStyle.strokeWidth = 3
        cartoonistStyle.sloppiness = .cartoonist
        let displacedRectangle = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 200, y: 20),
                    end: CGPoint(x: 240, y: 60)
                )
            ),
            style: cartoonistStyle
        )
        var fillStyle = AnnotationStyle.default
        fillStyle.fillStyle = .solid
        let filledEllipse = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .ellipse,
                    start: CGPoint(x: 260, y: 20),
                    end: CGPoint(x: 300, y: 60)
                )
            ),
            style: fillStyle
        )
        let curvedGeometry = AnnotationLinearGeometry(
            points: [CGPoint(x: 320, y: 60), CGPoint(x: 380, y: 20)],
            route: .curved,
            startArrowhead: .none,
            endArrowhead: .none,
            startBinding: nil,
            endBinding: nil,
            bezierControls: [
                AnnotationBezierControl(
                    start: CGPoint(x: 330, y: 10),
                    end: CGPoint(x: 370, y: 70)
                )
            ]
        )
        let curved = AnnotationElement(
            geometry: .linear(curvedGeometry),
            style: .default
        )
        let arrowGeometry = AnnotationLinearGeometry(
            points: [CGPoint(x: 400, y: 40), CGPoint(x: 460, y: 40)],
            route: .straight,
            startArrowhead: .none,
            endArrowhead: .arrow,
            startBinding: nil,
            endBinding: nil
        )
        let arrow = AnnotationElement(
            geometry: .linear(arrowGeometry),
            style: .default
        )
        let text = AnnotationElement(
            geometry: .text(
                AnnotationTextGeometry(
                    origin: CGPoint(x: 480, y: 20),
                    bounds: CGRect(x: 480, y: 20, width: 60, height: 30),
                    text: "Text",
                    fontSize: 20,
                    fontName: "",
                    alignment: .left,
                    isEditing: false
                )
            ),
            style: .default
        )
        let curvedHitPoint = AnnotationGeometry.linearDisplayPoints(
            curvedGeometry,
            subdivisions: 32
        )[16]
        let arrowMetrics = AnnotationGeometry.arrowheadMetrics(strokeWidth: 3)
        let arrowheadHitPoint = CGPoint(
            x: 460 - arrowMetrics.length,
            y: 40 + arrowMetrics.halfWidth
        )
        try expect(
            AnnotationHitTester.contains(
                CGPoint(x: 190, y: 40),
                in: displacedRectangle,
                zoomScale: 1
            )
                && AnnotationHitTester.contains(
                    CGPoint(x: 280, y: 40),
                    in: filledEllipse,
                    zoomScale: 1
                )
                && AnnotationHitTester.contains(
                    curvedHitPoint,
                    in: curved,
                    zoomScale: 1
                )
                && AnnotationHitTester.contains(
                    arrowheadHitPoint,
                    in: arrow,
                    zoomScale: 1
                )
                && AnnotationHitTester.contains(
                    CGPoint(x: 510, y: 35),
                    in: text,
                    zoomScale: 1
                ),
            "Expected expanded eraser hit coverage for Cartoonist displacement, shape fill, curves, arrowheads, and text"
        )

        var stackedStyle = AnnotationStyle.default
        stackedStyle.fillStyle = .solid
        let stackedElements = (0..<10_000).map { _ in
            AnnotationElement(
                geometry: .shape(
                    AnnotationShapeGeometry(
                        kind: .rectangle,
                        start: CGPoint(x: 600, y: 20),
                        end: CGPoint(x: 640, y: 60)
                    )
                ),
                style: stackedStyle
            )
        }
        let stackedController = AnnotationController(elements: stackedElements)
        stackedController.beginErasing(
            at: CGPoint(x: 620, y: 40),
            zoomScale: 1
        )
        try expect(
            stackedController.pendingErasureElementIDsForTesting.count == 10_000
                && stackedController.eraserSweepSampleCountForTesting == 1
                && stackedController.eraserHitTestCountForTesting == 10_000,
            "Expected one eraser sample over 10k stacked elements to perform "
                + "exactly one linear candidate scan"
        )
        stackedController.continueErasing(
            at: CGPoint(x: 620, y: 40),
            zoomScale: 1
        )
        try expect(
            stackedController.eraserHitTestCountForTesting == 10_000,
            "Expected staged 10k elements to be excluded once without rescanning "
                + "or compacting the candidate array"
        )
        stackedController.cancelErasing()
    }

    private static func testContinuousStyleUndoAndAtomicLegacyColor() throws {
        let controller = AnnotationController()
        controller.currentTool = .rectangle
        controller.begin(at: CGPoint(x: 10, y: 10))
        controller.end(at: CGPoint(x: 70, y: 70))
        controller.currentTool = .select
        _ = controller.beginSelectionInteraction(
            at: CGPoint(x: 12, y: 40),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        controller.endSelectionInteraction(at: CGPoint(x: 12, y: 40), modifiers: [])

        let originalStyle = controller.selectedElementSnapshot[0].style
        controller.beginContinuousStyleEdit(owner: .opacitySlider)
        controller.setOpacity(0.8)
        controller.setOpacity(0.6)
        controller.setOpacity(0.4)
        controller.endContinuousStyleEdit(owner: .opacitySlider)
        try expect(
            controller.selectedElementSnapshot[0].style.opacity == 0.4,
            "Expected continuous opacity updates to reach the final slider value"
        )
        controller.undo()
        try expect(
            controller.selectedElementSnapshot[0].style == originalStyle,
            "Expected one undo to revert the complete continuous opacity edit"
        )
        controller.redo()

        let beforeOverlappingEdit = controller.selectedElementSnapshot[0].style
        controller.beginContinuousStyleEdit(owner: .colorPicker)
        controller.setStrokeColor(.palette(.green))
        controller.beginContinuousStyleEdit(owner: .opacitySlider)
        controller.setOpacity(0.7)
        try expect(
            !controller.endContinuousStyleEdit(owner: .colorPicker)
                && controller.hasActiveContinuousStyleEdit
                && !controller.endContinuousStyleEdit(owner: .colorPicker),
            "Expected closing the color owner to leave an overlapping opacity edit active"
        )
        try expect(
            controller.endContinuousStyleEdit(owner: .opacitySlider)
                && !controller.hasActiveContinuousStyleEdit
                && controller.selectedElementSnapshot[0].style.strokeColor
                    == .palette(.green)
                && controller.selectedElementSnapshot[0].style.opacity == 0.7,
            "Expected the final owner to commit the combined continuous style edit once"
        )
        controller.undo()
        try expect(
            controller.selectedElementSnapshot[0].style == beforeOverlappingEdit,
            "Expected one undo to revert overlapping picker and slider edits atomically"
        )
        controller.redo()

        let beforeHighlightShortcut = controller.selectedElementSnapshot[0].style
        controller.setLegacyColor(.yellow, highlighted: true)
        let highlighted = controller.selectedElementSnapshot[0].style
        try expect(
            highlighted.strokeColor == .palette(.yellow)
                && highlighted.opacity == AnnotationStyle.highlightAlpha
                && highlighted.usesLegacyHighlightCompositing,
            "Expected legacy highlight color and opacity to update atomically"
        )
        controller.undo()
        try expect(
            controller.selectedElementSnapshot[0].style == beforeHighlightShortcut,
            "Expected one undo to restore color, opacity, and highlight semantics together"
        )
    }

    private static func testActiveTextContextualStyleTransaction() throws {
        let controller = AnnotationController()
        controller.currentTool = .text
        controller.setInsertionPoint(CGPoint(x: 8, y: 12))
        controller.beginTypingSession(rightAligned: false)
        controller.insertText("Old")
        controller.finishTypingSession()
        guard let oldTextID = controller.elementSnapshot.first?.id,
              let oldTextStyle = controller.elementSnapshot.first?.style else {
            throw SelfTestError.failure("Expected prior text selection setup")
        }
        controller.currentTool = .select
        controller.selectAll()

        controller.setInsertionPoint(CGPoint(x: 24, y: 36))
        controller.beginTypingSession(rightAligned: false)
        let newTypingState = DrawingToolbarState(annotationController: controller)
        try expect(
            controller.currentTool == .text
                && controller.selectedElementSnapshot.isEmpty
                && newTypingState.currentTool == .text
                && newTypingState.visibleInspectorSections == [
                    .strokeColor,
                    .textFont,
                    .textSize,
                    .textAlignment,
                    .opacity,
                    .layers
                ],
            "Expected a fresh typing session to clear the old selection and "
                + "activate only the Text toolbar and inspector context"
        )
        controller.setTextColor(.palette(.green))
        controller.setOpacity(0.4)
        controller.insertText("Styled")

        controller.beginContinuousStyleEdit(owner: .colorPicker)
        controller.setTextColor(.palette(.blue))
        controller.setOpacity(0.35)
        controller.endContinuousStyleEdit(owner: .colorPicker)

        guard let activeText = controller.elementSnapshot.first(where: {
            $0.id != oldTextID
        }) else {
            throw SelfTestError.failure("Expected an active text element")
        }
        try expect(
            activeText.style.strokeColor == .palette(.blue)
                && activeText.style.opacity == 0.35
                && controller.elementSnapshot.first(where: {
                    $0.id == oldTextID
                })?.style == oldTextStyle,
            "Expected typing-time styles to update the active/new text without "
                + "mutating the previously selected text"
        )

        controller.finishTypingSession()
        controller.undo()
        try expect(
            controller.elementSnapshot.count == 1
                && controller.elementSnapshot.first?.id == oldTextID
                && controller.elementSnapshot.first?.style == oldTextStyle,
            "Expected active text style edits to remain inside the new typing transaction"
        )
        controller.redo()
        try expect(
            controller.elementSnapshot.first(where: {
                $0.id != oldTextID
            })?.style.strokeColor == .palette(.blue)
                && controller.elementSnapshot.first(where: {
                    $0.id != oldTextID
                })?.style.opacity == 0.35,
            "Expected redo to restore text and its contextual style as one transaction"
        )
    }

    private static func testTextScopedStyleActionsInMixedSelection() throws {
        let controller = AnnotationController()
        controller.currentTool = .rectangle
        controller.begin(at: CGPoint(x: 10, y: 10))
        controller.end(at: CGPoint(x: 60, y: 60))

        controller.setStrokeColor(.palette(.blue))
        controller.setOpacity(0.8)
        controller.currentTool = .text
        controller.setInsertionPoint(CGPoint(x: 90, y: 20))
        controller.beginTypingSession(rightAligned: false)
        controller.insertText("Text")
        controller.finishTypingSession()

        controller.currentTool = .select
        _ = controller.beginSelectionInteraction(
            at: CGPoint(x: 12, y: 35),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        controller.endSelectionInteraction(at: CGPoint(x: 12, y: 35), modifiers: [])
        _ = controller.beginSelectionInteraction(
            at: CGPoint(x: 92, y: 28),
            zoomScale: 1,
            modifiers: [.shift],
            clickCount: 1
        )
        controller.endSelectionInteraction(
            at: CGPoint(x: 92, y: 28),
            modifiers: [.shift]
        )

        let mixedState = DrawingToolbarState(annotationController: controller)
        try expect(
            controller.selectedElementSnapshot.count == 2
                && mixedState.opacity == .mixed
                && mixedState.textColor == .value(.palette(.blue))
                && mixedState.textOpacity == .value(0.8)
                && mixedState.visibleInspectorSections == [
                    .strokeColor,
                    .opacity,
                    .layers
                ],
            "Expected mixed element types to expose only shared, effectful sections"
        )

        controller.setTextColor(.palette(.green))
        controller.setTextOpacity(0.35)
        guard let shape = controller.elementSnapshot.first(where: {
            if case .shape = $0.geometry { return true }
            return false
        }),
        let text = controller.elementSnapshot.first(where: {
            if case .text = $0.geometry { return true }
            return false
        }) else {
            throw SelfTestError.failure("Expected shape and text elements in mixed selection")
        }
        try expect(
            shape.style.strokeColor == .palette(.red)
                && shape.style.opacity == 1
                && text.style.strokeColor == .palette(.green)
                && text.style.opacity == 0.35,
            "Expected Text color and opacity controls to leave mixed-selection shapes unchanged"
        )

        controller.setStrokeColor(.palette(.yellow))
        controller.setOpacity(0.6)
        try expect(
            controller.elementSnapshot.allSatisfy {
                $0.style.strokeColor == .palette(.yellow) && $0.style.opacity == 0.6
            },
            "Expected general Stroke color and opacity controls to remain global"
        )
    }

    private static func testToolScopedWidthsAndCompactToolbarGeometry() throws {
        let controller = AnnotationController()
        controller.applyDrawingDefaults(
            .default,
            strokeWidth: AnnotationStrokeWidthDefaults.pen,
            highlighterWidth: AnnotationStrokeWidthDefaults.highlighter,
            geometryWidth: AnnotationStrokeWidthDefaults.geometry
        )
        try expect(
            controller.currentTool == .pen
                && controller.currentStyle.strokeWidth == 7,
            "Expected the default Pen width to be 7 points"
        )
        controller.setStrokeWidth(11)
        controller.setStrokeColor(.palette(.blue))
        controller.currentTool = .rectangle
        try expect(
            controller.currentStyle.strokeWidth == 3,
            "Expected geometry to retain an independent default width"
        )
        controller.setStrokeWidth(6)
        controller.setStrokePattern(.dotted)
        controller.currentTool = .highlighter
        try expect(
            controller.currentStyle.strokeWidth == 18
                && controller.currentStyle.strokeColor
                    == .palette(.highlighterYellow)
                && controller.currentStyle.strokePattern == .solid
                && controller.currentStyle.pressureMode == .fixed,
            "Expected Highlighter to restore its dedicated width, color, and fixed solid marker style"
        )
        controller.setStrokeWidth(28)
        controller.setStrokeColor(.palette(.highlighterPink))
        controller.currentTool = .pen
        try expect(
            controller.currentStyle.strokeWidth == 11
                && controller.currentStyle.strokeColor == .palette(.blue)
                && controller.currentStyle.strokePattern == .solid,
            "Expected Pen to restore its independent width/color scope without geometry patterns"
        )
        controller.currentTool = .rectangle
        try expect(
            controller.currentStyle.strokeWidth == 6
                && controller.currentStyle.strokePattern == .dotted,
            "Expected geometry width and dotted style to survive freehand tool switches"
        )
        controller.currentTool = .highlighter
        try expect(
            controller.currentStyle.strokeWidth == 28
                && controller.currentStyle.strokeColor
                    == .palette(.highlighterPink),
            "Expected Highlighter width and color to persist independently"
        )

        let penState: DrawingToolbarState = {
            controller.currentTool = .pen
            return DrawingToolbarState(annotationController: controller)
        }()
        let highlighterState: DrawingToolbarState = {
            controller.currentTool = .highlighter
            return DrawingToolbarState(annotationController: controller)
        }()
        let geometryState: DrawingToolbarState = {
            controller.currentTool = .rectangle
            return DrawingToolbarState(annotationController: controller)
        }()
        try expect(
            penState.strokeWidthOptions == [3, 7, 11]
                && highlighterState.strokeWidthOptions == [10, 18, 28]
                && geometryState.strokeWidthOptions == [1, 3, 6]
                && DrawingInspectorSectionMatrix.sections(for: .highlighter)
                    == [.strokeColor, .strokeWidth, .opacity],
            "Expected exact per-tool width choices and Highlighter sections"
        )

        var toolbarCommands: [AppCommand] = []
        var dragEventTypes: [NSEvent.EventType] = []
        let toolbar = DrawingToolbarView(
            commandSink: { toolbarCommands.append($0) },
            showOverflow: { _ in },
            beginDragging: { dragEventTypes.append($0.type) }
        )
        toolbar.update(state: geometryState, transientTool: nil)
        let preferredSize = toolbar.preferredContentSize()
        toolbar.frame = CGRect(origin: .zero, size: preferredSize)
        toolbar.layoutSubtreeIfNeeded()
        let frames = toolbar.buttonFramesForTesting
        let itemOrder = toolbar.primaryItemOrderForTesting
        let buttonVisuals = toolbar.primaryButtonVisualsForTesting
        let shadowMetrics = toolbar.shellShadowMetricsForTesting
        let labels = descendantViews(
            of: NSButton.self,
            in: toolbar
        ).compactMap { $0.accessibilityLabel() }
        let selectedFilledButtons = buttonVisuals.filter {
            $0.value.isSelected && $0.value.backgroundAlpha > 0.99
        }.map(\.key)
        let idleButtonsAreClear = buttonVisuals.allSatisfy {
            $0.value.isSelected
                || (
                    $0.value.backgroundAlpha == 0
                        && $0.value.borderWidth == 0
                )
        }
        let flippedHintOrigin = DrawingToolbarVisualMetrics.numericHintOrigin(
            in: CGRect(x: 0, y: 0, width: 44, height: 44),
            textSize: CGSize(width: 5, height: 10),
            isFlipped: true
        )
        let backgroundHit = toolbar.hitTest(CGPoint(x: 1, y: 1))
        let rectangleHitPoint = toolbar.buttonHitPointsForTesting["rectangle"]
            ?? .zero
        let rectangleHit = toolbar.hitTest(
            rectangleHitPoint
        )
        let dragHandleFrame = toolbar.dragHandleFrameForTesting
        let dragHandleHitPoint = CGPoint(
            x: dragHandleFrame.midX,
            y: dragHandleFrame.midY
        )
        let dragHandleAccessibility =
            toolbar.dragHandleAccessibilityForTesting
        guard let highlighterButton = descendantViews(
            of: NSButton.self,
            in: toolbar
        ).first(where: {
            $0.accessibilityLabel() == "Highlighter"
        }), let dragMouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: dragHandleHitPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) else {
            throw SelfTestError.failure(
                "Expected visible Highlighter and drag-handle test controls"
            )
        }
        highlighterButton.performClick(nil)
        let controlClickAvoidedDrag = dragEventTypes.isEmpty
        toolbar.beginDragFromHandleForTesting(with: dragMouseDown)
        let expectedItemOrder = [
            "Move Drawing Toolbar",
            "separator",
            "Hand",
            "Select",
            "Rectangle",
            "Diamond",
            "Ellipse",
            "Arrow",
            "Line",
            "Pen",
            "Highlighter",
            "Text",
            "Eraser",
            "separator",
            "More Drawing Actions"
        ]
        let dragHandleIsValid =
            dragHandleFrame.size == CGSize(width: 24, height: 44)
                && toolbar.isDragHandleHitForTesting(at: dragHandleHitPoint)
                && dragHandleAccessibility.label == "Move Drawing Toolbar"
                && dragHandleAccessibility.help
                    == "Drag to move the drawing toolbar and attached inspector"
                && controlClickAvoidedDrag
                && dragEventTypes == [.leftMouseDown]
        let highlighterIsValid =
            highlighterButton.image != nil
                && highlighterButton.toolTip == "Highlighter (H)"
                && highlighterButton.accessibilityHelp() == "Highlighter (H)"
                && toolbarCommands == [.setTool(.highlighter)]
                && toolbar.isToolSelected(.highlighter)
        try expect(
            preferredSize.height == 54
                && preferredSize.width == 648
                && frames.count == 11
                && DrawingToolbarVisualMetrics.buttonSide == 44
                && itemOrder == expectedItemOrder
                && selectedFilledButtons == ["Rectangle"]
                && idleButtonsAreClear
                && toolbar.backgroundDragEnabledForTesting
                && backgroundHit === toolbar
                && rectangleHit !== toolbar
                && dragHandleIsValid
                && highlighterIsValid
                && toolbar.layer?.borderWidth == 0
                && toolbar.layer?.cornerRadius == 15
                && toolbar.shellShadowLayerCountForTesting == 3
                && shadowMetrics == [
                    DrawingToolbarShadowMetric(
                        opacity: 0.17,
                        blurRadius: 1,
                        offset: .zero
                    ),
                    DrawingToolbarShadowMetric(
                        opacity: 0.08,
                        blurRadius: 3,
                        offset: .zero
                    ),
                    DrawingToolbarShadowMetric(
                        opacity: 0.05,
                        blurRadius: 14,
                        offset: CGSize(width: 0, height: 7)
                    )
                ]
                && flippedHintOrigin == CGPoint(x: 35, y: 30)
                && labels.contains("Hand")
                && labels.contains("Highlighter")
                && labels.contains("More Drawing Actions")
                && !labels.contains("Toggle Drawing Inspector"),
            "Expected the polished primary toolbar with visible Highlighter, exact order, "
                + "accessible grip dragging, control-safe hit testing, transparent idle tiles, "
                + "one selected fill, and lower-right numeric hints"
        )
        controller.currentTool = .pen
        controller.begin(at: CGPoint(x: 0, y: 0))
        controller.end(at: CGPoint(x: 20, y: 20))
        try expect(
            controller.currentTool == .pen,
            "Expected drawing tools to remain selected after use without a toolbar lock mode"
        )
    }

    private static func testPenPressureAndSelectionStyleScopes() throws {
        let pressureController = AnnotationController()
        pressureController.currentTool = .pen
        pressureController.setPressureMode(.simulated)
        pressureController.currentTool = .highlighter
        try expect(
            pressureController.currentStyle.pressureMode == .fixed,
            "Expected Highlighter creation to retain fixed pressure"
        )
        pressureController.currentTool = .pen
        try expect(
            pressureController.currentStyle.pressureMode == .simulated
                && pressureController.preferredVariablePressureMode == .simulated,
            "Expected Pen to restore its mouse-speed pressure choice after Highlighter"
        )
        pressureController.setPressureMode(.tablet)
        pressureController.currentTool = .highlighter
        pressureController.currentStyle.pressureMode = .simulated
        pressureController.currentTool = .pen
        try expect(
            pressureController.currentStyle.pressureMode == .tablet
                && pressureController.preferredVariablePressureMode == .tablet,
            "Expected Highlighter normalization not to overwrite Pen tablet pressure"
        )

        pressureController.currentTool = .highlighter
        let rememberedPressure = DrawingDefaults(
            tool: pressureController.currentTool,
            style: pressureController.drawingDefaultsStyle,
            smartDrawEnabled: false,
            linearRoute: .straight,
            startArrowhead: .none,
            endArrowhead: .arrow,
            regularStrokeColor: pressureController
                .drawingDefaultsRegularStrokeColor,
            highlighterStrokeColor: pressureController
                .drawingDefaultsHighlighterStrokeColor,
            penStrokeWidth: pressureController.drawingDefaultsPenStrokeWidth,
            highlighterStrokeWidth: pressureController
                .drawingDefaultsHighlighterStrokeWidth,
            geometryStrokeWidth: pressureController
                .drawingDefaultsGeometryStrokeWidth,
            freehandSloppiness: pressureController
                .drawingDefaultsFreehandSloppiness,
            outlinedSloppiness: pressureController
                .drawingDefaultsOutlinedSloppiness
        )
        let restoredPressureController = AnnotationController()
        restoredPressureController.applyDrawingDefaults(
            rememberedPressure,
            strokeWidth: 7
        )
        try expect(
            restoredPressureController.currentStyle.pressureMode == .fixed,
            "Expected remembered Highlighter presentation to remain fixed"
        )
        restoredPressureController.currentTool = .pen
        try expect(
            restoredPressureController.currentStyle.pressureMode == .tablet,
            "Expected remembered Pen pressure to survive a Highlighter last-tool state"
        )

        let selectionController = AnnotationController()
        selectionController.currentTool = .pen
        selectionController.setStrokeColor(.palette(.blue))
        selectionController.currentTool = .highlighter
        selectionController.setStrokeColor(.palette(.highlighterOrange))
        selectionController.begin(at: CGPoint(x: 12, y: 36))
        selectionController.end(at: CGPoint(x: 84, y: 36))
        selectionController.currentTool = .select
        selectionController.selectAll()
        selectionController.setStrokeColor(.palette(.highlighterPink))
        try expect(
            selectionController.selectedElementSnapshot.first?.style.strokeColor
                == .palette(.highlighterPink),
            "Expected selected Highlighter color edits to update the element"
        )
        selectionController.currentTool = .pen
        let penColor = selectionController.currentStyle.strokeColor
        selectionController.currentTool = .rectangle
        let shapeColor = selectionController.currentStyle.strokeColor
        selectionController.currentTool = .highlighter
        try expect(
            penColor == .palette(.blue)
                && shapeColor == .palette(.blue)
                && selectionController.currentStyle.strokeColor
                    == .palette(.highlighterOrange),
            "Expected selection-only Highlighter edits not to corrupt Pen, shape, "
                + "or Highlighter creation color scopes"
        )
    }

    private static func testPenOpacityScopes() throws {
        let controller = AnnotationController()
        controller.currentTool = .pen
        controller.setOpacity(0.4)
        controller.currentTool = .highlighter
        controller.setOpacity(0.8)
        controller.currentTool = .pen
        try expect(
            controller.currentStyle.opacity == 0.4,
            "Expected Pen 0.4 -> Highlighter 0.8 -> Pen to restore 0.4"
        )

        controller.currentTool = .rectangle
        controller.setOpacity(0.65)
        controller.currentTool = .pen
        try expect(
            controller.currentStyle.opacity == 0.4,
            "Expected Pen opacity to survive a Rectangle 0.65 roundtrip"
        )
        controller.currentTool = .rectangle
        try expect(
            controller.currentStyle.opacity == 0.65,
            "Expected geometry opacity to remain independent from Pen"
        )
        controller.currentTool = .highlighter
        try expect(
            controller.currentStyle.opacity == 0.8,
            "Expected Highlighter opacity to remain independent from Pen and geometry"
        )

        controller.begin(at: CGPoint(x: 10, y: 10))
        controller.end(at: CGPoint(x: 80, y: 10))
        controller.currentTool = .select
        controller.selectAll()
        controller.setOpacity(0.25)
        controller.currentTool = .pen
        let penOpacityAfterSelectionEdit = controller.currentStyle.opacity
        controller.currentTool = .rectangle
        let geometryOpacityAfterSelectionEdit = controller.currentStyle.opacity
        controller.currentTool = .highlighter
        try expect(
            penOpacityAfterSelectionEdit == 0.4
                && geometryOpacityAfterSelectionEdit == 0.65
                && controller.currentStyle.opacity == 0.8,
            "Expected selection-only opacity edits not to corrupt creation scopes"
        )

        let rememberedDefaults = DrawingDefaults(
            tool: .highlighter,
            style: controller.drawingDefaultsStyle,
            smartDrawEnabled: false,
            linearRoute: .straight,
            startArrowhead: .none,
            endArrowhead: .arrow,
            regularStrokeColor: controller.drawingDefaultsRegularStrokeColor,
            highlighterStrokeColor:
                controller.drawingDefaultsHighlighterStrokeColor,
            penStrokeWidth: controller.drawingDefaultsPenStrokeWidth,
            highlighterStrokeWidth:
                controller.drawingDefaultsHighlighterStrokeWidth,
            geometryStrokeWidth:
                controller.drawingDefaultsGeometryStrokeWidth,
            penOpacity: controller.drawingDefaultsPenOpacity,
            geometryOpacity: controller.drawingDefaultsGeometryOpacity,
            highlighterOpacity: controller.drawingDefaultsHighlighterOpacity,
            freehandSloppiness:
                controller.drawingDefaultsFreehandSloppiness,
            outlinedSloppiness:
                controller.drawingDefaultsOutlinedSloppiness
        )
        let restored = AnnotationController()
        restored.applyDrawingDefaults(rememberedDefaults, strokeWidth: 7)
        restored.currentTool = .pen
        let restoredPenOpacity = restored.currentStyle.opacity
        restored.currentTool = .rectangle
        let restoredGeometryOpacity = restored.currentStyle.opacity
        restored.currentTool = .highlighter
        try expect(
            restoredPenOpacity == 0.4
                && restoredGeometryOpacity == 0.65
                && restored.currentStyle.opacity == 0.8,
            "Expected remembered opacity scopes to restore independently"
        )

        let reset = AnnotationController()
        reset.currentTool = .pen
        reset.setOpacity(0.4)
        reset.reset()
        try expect(
            reset.currentTool == .pen
                && reset.currentStyle.opacity == 1
                && reset.drawingDefaultsPenOpacity == 1,
            "Expected a nonremembered session to reset Pen opacity to defaults"
        )
    }

    private static func testHighlighterGeometryStyleIsolation() throws {
        let geometryTools: [AnnotationTool] = [
            .line, .arrow, .rectangle, .diamond, .ellipse
        ]

        func expectGeometryStyle(
            _ style: AnnotationStyle,
            strokeColor: AnnotationColorValue,
            width: CGFloat,
            pattern: AnnotationStrokePattern,
            sloppiness: AnnotationSloppiness,
            opacity: CGFloat,
            fillColor: AnnotationColorValue,
            fillStyle: AnnotationFillStyle,
            context: String
        ) throws {
            try expect(
                style.strokeColor == strokeColor
                    && style.strokeWidth == width
                    && style.strokePattern == pattern
                    && style.sloppiness == sloppiness
                    && style.opacity == opacity
                    && style.fillColor == fillColor
                    && style.fillStyle == fillStyle
                    && style.lineCap == .round
                    && style.lineJoin == .round
                    && style.pressureMode == .fixed
                    && !style.usesLegacyHighlightCompositing,
                context
            )
        }

        for tool in geometryTools {
            let controller = AnnotationController()
            controller.currentTool = .highlighter
            controller.setStrokeColor(.palette(.highlighterPink))
            controller.setStrokeWidth(28)
            controller.setOpacity(0.35)
            controller.currentTool = tool
            try expectGeometryStyle(
                controller.currentStyle,
                strokeColor: .palette(.red),
                width: AnnotationStrokeWidthDefaults.geometry,
                pattern: .solid,
                sloppiness: tool == .line ? .architect : .artist,
                opacity: 1,
                fillColor: .palette(.red),
                fillStyle: .none,
                context: "Expected \(tool) selection after Highlighter to restore complete geometry defaults"
            )
        }

        let roundTripController = AnnotationController()
        roundTripController.currentTool = .rectangle
        roundTripController.setStrokeColor(.palette(.blue))
        roundTripController.setStrokeWidth(6)
        roundTripController.setStrokePattern(.dotted)
        roundTripController.setSloppiness(.cartoonist)
        roundTripController.setShapeBackground(.palette(.orange))
        roundTripController.setFillStyle(.solid)
        roundTripController.setOpacity(0.65)
        let geometryStyle = roundTripController.currentStyle

        roundTripController.currentTool = .highlighter
        roundTripController.setStrokeColor(.palette(.highlighterGreen))
        roundTripController.setStrokeWidth(28)
        roundTripController.setOpacity(0.4)
        let highlighterStyle = roundTripController.currentStyle

        for tool in geometryTools {
            roundTripController.currentTool = tool
            try expectGeometryStyle(
                roundTripController.currentStyle,
                strokeColor: geometryStyle.strokeColor,
                width: geometryStyle.strokeWidth,
                pattern: geometryStyle.strokePattern,
                sloppiness: tool == .line
                    ? .architect
                    : geometryStyle.sloppiness,
                opacity: geometryStyle.opacity,
                fillColor: geometryStyle.fillColor,
                fillStyle: geometryStyle.fillStyle,
                context: "Expected \(tool) to restore the pre-Highlighter geometry scope"
            )
            roundTripController.currentTool = .highlighter
            try expect(
                roundTripController.currentStyle == highlighterStyle,
                "Expected Highlighter presentation to survive a \(tool) roundtrip"
            )
        }

        let rememberedDefaults = DrawingDefaults(
            tool: roundTripController.currentTool,
            style: roundTripController.drawingDefaultsStyle,
            smartDrawEnabled: false,
            linearRoute: .straight,
            startArrowhead: .none,
            endArrowhead: .arrow,
            regularStrokeColor: roundTripController
                .drawingDefaultsRegularStrokeColor,
            highlighterStrokeColor: roundTripController
                .drawingDefaultsHighlighterStrokeColor,
            penStrokeWidth: roundTripController.drawingDefaultsPenStrokeWidth,
            highlighterStrokeWidth: roundTripController
                .drawingDefaultsHighlighterStrokeWidth,
            geometryStrokeWidth: roundTripController
                .drawingDefaultsGeometryStrokeWidth,
            geometryOpacity: roundTripController
                .drawingDefaultsGeometryOpacity,
            highlighterOpacity: roundTripController
                .drawingDefaultsHighlighterOpacity,
            freehandSloppiness: roundTripController
                .drawingDefaultsFreehandSloppiness,
            outlinedSloppiness: roundTripController
                .drawingDefaultsOutlinedSloppiness
        )
        let restoredController = AnnotationController()
        restoredController.applyDrawingDefaults(
            rememberedDefaults,
            strokeWidth: AnnotationStrokeWidthDefaults.pen
        )
        try expect(
            restoredController.currentStyle == highlighterStyle,
            "Expected persisted Highlighter scope to restore independently"
        )
        restoredController.currentTool = .rectangle
        try expectGeometryStyle(
            restoredController.currentStyle,
            strokeColor: geometryStyle.strokeColor,
            width: geometryStyle.strokeWidth,
            pattern: geometryStyle.strokePattern,
            sloppiness: geometryStyle.sloppiness,
            opacity: geometryStyle.opacity,
            fillColor: geometryStyle.fillColor,
            fillStyle: geometryStyle.fillStyle,
            context: "Expected persisted geometry scope to survive a Highlighter last-tool state"
        )

        let gestureController = AnnotationController()
        gestureController.currentTool = .rectangle
        gestureController.setStrokeColor(.palette(.green))
        gestureController.setStrokeWidth(6)
        gestureController.setStrokePattern(.dashed)
        gestureController.setSloppiness(.cartoonist)
        gestureController.setShapeBackground(.palette(.yellow))
        gestureController.setFillStyle(.solid)
        gestureController.setOpacity(0.7)
        gestureController.currentTool = .highlighter
        gestureController.setStrokeColor(.palette(.highlighterOrange))
        gestureController.setStrokeWidth(28)
        gestureController.setOpacity(0.3)
        let preservedHighlighterStyle = gestureController.currentStyle
        let gestures: [(
            control: Bool,
            shift: Bool,
            tab: Bool,
            tool: AnnotationTool
        )] = [
            (false, true, false, .line),
            (true, false, false, .rectangle),
            (true, true, false, .arrow),
            (false, false, true, .ellipse)
        ]

        for (index, gesture) in gestures.enumerated() {
            guard let tool = ZoomCanvasView.gestureTool(
                control: gesture.control,
                shift: gesture.shift,
                tab: gesture.tab,
                selectedTool: .highlighter
            ), tool == gesture.tool else {
                throw SelfTestError.failure(
                    "Expected modifier gesture to resolve \(gesture.tool)"
                )
            }
            let y = CGFloat(index * 20)
            gestureController.begin(
                at: CGPoint(x: 10, y: y),
                tool: tool,
                legacyModifierGesture: tool == .line || tool == .arrow
            )
            gestureController.end(at: CGPoint(x: 80, y: y + 10))
            guard let element = gestureController.elementSnapshot.last else {
                throw SelfTestError.failure(
                    "Expected modifier gesture to create \(tool)"
                )
            }
            try expectGeometryStyle(
                element.style,
                strokeColor: .palette(.green),
                width: 6,
                pattern: .dashed,
                sloppiness: tool == .line ? .architect : .cartoonist,
                opacity: 0.7,
                fillColor: .palette(.yellow),
                fillStyle: .solid,
                context: "Expected \(tool) modifier gesture to use the isolated geometry scope"
            )
            try expect(
                gestureController.currentTool == .highlighter
                    && gestureController.currentStyle == preservedHighlighterStyle,
                "Expected transient \(tool) gesture to preserve the selected Highlighter scope"
            )
        }
    }

    private static func testFreehandSmoothingAndPressureSampling() throws {
        let raw = [
            AnnotationPointSample(location: CGPoint(x: 5, y: 5), pressure: 0.2),
            AnnotationPointSample(location: CGPoint(x: 20, y: 15), pressure: 0.5),
            AnnotationPointSample(location: CGPoint(x: 35, y: 5), pressure: 1)
        ]
        let smoothed = AnnotationGeometry.smoothedFreehandSamples(raw, subdivisions: 4)
        try expect(smoothed.first == raw.first, "Expected smoothing to preserve the first sample")
        try expect(smoothed.last == raw.last, "Expected smoothing to preserve the final sample")
        try expect(smoothed.count == 9, "Expected deterministic smoothing subdivisions")
        try expect(
            smoothed.allSatisfy { $0.pressure == nil || (0...1).contains($0.pressure!) },
            "Expected smoothing to interpolate normalized pressure"
        )

        let currentInput = AnnotationRawFreehandInput(
            location: CGPoint(x: 36, y: 8),
            pressure: 0.9,
            timestamp: 0.03
        )
        let orderedInputs = ZoomCanvasView.orderedUniqueFreehandInputs(
            coalesced: [
                AnnotationRawFreehandInput(
                    location: CGPoint(x: 12, y: 2),
                    pressure: 0.3,
                    timestamp: 0.01
                ),
                AnnotationRawFreehandInput(
                    location: CGPoint(x: 24, y: 4),
                    pressure: 0.6,
                    timestamp: 0.02
                ),
                AnnotationRawFreehandInput(
                    location: currentInput.location,
                    pressure: 0.7,
                    timestamp: currentInput.timestamp
                )
            ],
            current: currentInput
        )
        try expect(
            orderedInputs.map(\.timestamp) == [0.01, 0.02, 0.03]
                && orderedInputs.map(\.location) == [
                    CGPoint(x: 12, y: 2),
                    CGPoint(x: 24, y: 4),
                    CGPoint(x: 36, y: 8)
                ]
                && orderedInputs.last?.pressure == 0.9,
            "Expected ordered freehand input to avoid sorting, deduplicate the current event, and preserve pressure"
        )

        let batchedController = AnnotationController()
        batchedController.currentStyle.pressureMode = .tablet
        batchedController.begin(
            at: .zero,
            pressure: 0.1,
            timestamp: 0,
            zoomScale: 1
        )
        batchedController.updateFreehand(inputs: orderedInputs, zoomScale: 1)
        guard let batchedElement = batchedController.inProgressElementSnapshot,
              case .freehand(let batchedFreehand) = batchedElement.geometry else {
            throw SelfTestError.failure("Expected batched coalesced freehand geometry")
        }
        try expect(
            orderedInputs.allSatisfy { input in
                batchedFreehand.samples.contains {
                    $0.location == input.location
                        && $0.timestamp == input.timestamp
                        && $0.pressure == input.pressure
                }
            },
            "Expected one batched freehand update to preserve each coalesced location, timestamp, and pressure"
        )

        let mouseController = AnnotationController()
        mouseController.currentStyle.pressureMode = .tablet
        mouseController.begin(at: CGPoint(x: 1, y: 1))
        mouseController.update(at: CGPoint(x: 2, y: 2))
        mouseController.end(at: CGPoint(x: 3, y: 3))
        guard case .freehand(let mouseStroke) = mouseController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a mouse freehand element")
        }
        try expect(
            mouseStroke.samples.allSatisfy { $0.pressure == nil },
            "Expected mouse-only strokes to retain deterministic constant-width samples"
        )

        let pressureController = AnnotationController()
        pressureController.currentStyle.pressureMode = .tablet
        pressureController.begin(at: CGPoint(x: 1, y: 1), pressure: 0.2)
        pressureController.update(at: CGPoint(x: 2, y: 2), pressure: 0.6)
        pressureController.end(at: CGPoint(x: 3, y: 3), pressure: 1.4)
        guard case .freehand(let pressureStroke) = pressureController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected a pressure-aware freehand element")
        }
        let tabletPressures = pressureStroke.samples.compactMap(\.pressure)
        try expect(
            tabletPressures.first == 0.2
                && tabletPressures.last == 1
                && tabletPressures.allSatisfy { (0...1).contains($0) }
                && zip(
                    pressureStroke.samples,
                    pressureStroke.samples.dropFirst()
                ).allSatisfy {
                    hypot(
                        $1.location.x - $0.location.x,
                        $1.location.y - $0.location.y
                    ) <= AnnotationFreehandInputResampler.screenSpacing + 0.01
                },
            "Expected tablet pressure to remain clamped while centerline samples are resampled"
        )

        var slowTracker = AnnotationSimulatedPressureTracker()
        _ = slowTracker.begin(at: .zero, timestamp: 0)
        let slowPressure = slowTracker.sample(
            at: CGPoint(x: 2, y: 0),
            timestamp: 0.1,
            zoomScale: 1
        )
        var fastTracker = AnnotationSimulatedPressureTracker()
        _ = fastTracker.begin(at: .zero, timestamp: 0)
        let fastPressure = fastTracker.sample(
            at: CGPoint(x: 120, y: 0),
            timestamp: 0.1,
            zoomScale: 1
        )
        try expect(
            slowPressure > fastPressure
                && (AnnotationSimulatedPressureTracker.minimumPressure...1)
                    .contains(slowPressure)
                && (AnnotationSimulatedPressureTracker.minimumPressure...1)
                    .contains(fastPressure),
            "Expected slower mouse movement to produce thicker deterministic simulated pressure"
        )
        var seededTracker = AnnotationSimulatedPressureTracker()
        _ = seededTracker.begin(at: .zero, timestamp: 0)
        _ = seededTracker.resampledSamples(
            at: CGPoint(x: 10, y: 0),
            timestamp: 0.1,
            zoomScale: 1
        )
        try expect(
            abs((seededTracker.filteredSpeed ?? 0) - 100) < 0.001
                && abs(
                    (seededTracker.smoothedPressure ?? 0)
                        - AnnotationSimulatedPressureTracker.pressure(forSpeed: 100)
                ) < 0.001,
            "Expected the first measured segment to seed speed and pressure filters"
        )
        var hugeGapTracker = AnnotationSimulatedPressureTracker()
        _ = hugeGapTracker.begin(at: .zero, timestamp: 0)
        let hugeGapPressureSamples = hugeGapTracker.resampledSamples(
            at: CGPoint(x: 1_000, y: 0),
            timestamp: 0.1,
            zoomScale: 2
        )
        let hugeGapLocations = [CGPoint.zero]
            + hugeGapPressureSamples.map(\.location)
        try expect(
            hugeGapPressureSamples.count
                == AnnotationSimulatedPressureTracker.maximumSamplesPerEvent
                && hugeGapPressureSamples.last?.location
                    == CGPoint(x: 1_000, y: 0)
                && zip(
                    hugeGapLocations,
                    hugeGapLocations.dropFirst()
                ).allSatisfy {
                    $1.x > $0.x
                }
                && zip(
                    hugeGapPressureSamples.compactMap(\.timestamp),
                    hugeGapPressureSamples.compactMap(\.timestamp).dropFirst()
                ).allSatisfy { $0 <= $1 },
            "Expected simulated pressure to adaptively cover huge gaps within its per-event work cap"
        )
        let calibrationSpeeds: [CGFloat] = [
            40, 50, 100, 150, 300, 500, 700, 1_000, 1_500, 1_800
        ]
        let expectedCalibration: [CGFloat] = [
            0.98, 0.979, 0.971, 0.958, 0.898, 0.796, 0.684, 0.524, 0.336, 0.3
        ]
        let speedResponse = calibrationSpeeds.map(
            AnnotationSimulatedPressureTracker.pressure
        )
        try expect(
            zip(speedResponse, expectedCalibration).allSatisfy {
                abs($0 - $1) <= 0.01
            }
                && zip(speedResponse, speedResponse.dropFirst()).allSatisfy {
                    $0 > $1
                },
            "Expected the calibrated velocity-pressure response within ±0.01 "
                + "(actual \(speedResponse))"
        )

        func trackedPressures(
            _ events: [(CGPoint, TimeInterval)],
            zoomScale: CGFloat = 1
        ) -> [CGFloat] {
            var tracker = AnnotationSimulatedPressureTracker()
            var result = [tracker.begin(at: .zero, timestamp: 0)]
            for (point, timestamp) in events {
                result.append(
                    contentsOf: tracker.resampledSamples(
                        at: point,
                        timestamp: timestamp,
                        zoomScale: zoomScale
                    ).compactMap(\.pressure)
                )
            }
            return result
        }

        let uniformTiming = trackedPressures(
            stride(from: 1, through: 10, by: 1).map {
                (CGPoint(x: CGFloat($0) * 6, y: 0), Double($0) * 0.02)
            }
        )
        let irregularTiming = trackedPressures([
            (CGPoint(x: 3, y: 0), 0.01),
            (CGPoint(x: 18, y: 0), 0.06),
            (CGPoint(x: 24, y: 0), 0.08),
            (CGPoint(x: 48, y: 0), 0.16),
            (CGPoint(x: 60, y: 0), 0.20)
        ])
        try expect(
            abs((uniformTiming.last ?? 0) - (irregularTiming.last ?? 0)) < 0.035,
            "Expected distance/time resampling to stabilize irregular mouse event timing"
        )

        func finalBatchedSimulatedPressure(
            _ inputs: [AnnotationRawFreehandInput]
        ) throws -> CGFloat {
            let controller = AnnotationController()
            controller.currentStyle.pressureMode = .simulated
            controller.begin(
                at: .zero,
                pressure: nil,
                timestamp: 0,
                zoomScale: 1
            )
            controller.updateFreehand(inputs: inputs, zoomScale: 1)
            guard let element = controller.inProgressElementSnapshot,
                  case .freehand(let freehand) = element.geometry,
                  let pressure = freehand.samples.last?.pressure else {
                throw SelfTestError.failure(
                    "Expected batched simulated-pressure geometry"
                )
            }
            return pressure
        }
        let densePressure = try finalBatchedSimulatedPressure(
            (1...20).map { index in
                AnnotationRawFreehandInput(
                    location: CGPoint(x: CGFloat(index) * 5, y: 0),
                    pressure: nil,
                    timestamp: Double(index) * 0.005
                )
            }
        )
        let sparsePressure = try finalBatchedSimulatedPressure([
            AnnotationRawFreehandInput(
                location: CGPoint(x: 50, y: 0),
                pressure: nil,
                timestamp: 0.05
            ),
            AnnotationRawFreehandInput(
                location: CGPoint(x: 100, y: 0),
                pressure: nil,
                timestamp: 0.1
            )
        ])
        try expect(
            abs(densePressure - sparsePressure) <= 0.045,
            "Expected dense and sparse samples with equal timestamped velocity to resolve comparable pressure "
                + "(dense \(densePressure), sparse \(sparsePressure))"
        )

        let zoomOne = trackedPressures([
            (CGPoint(x: 12, y: 0), 0.04),
            (CGPoint(x: 24, y: 0), 0.08),
            (CGPoint(x: 36, y: 0), 0.12)
        ])
        let zoomTwo = trackedPressures(
            [
                (CGPoint(x: 6, y: 0), 0.04),
                (CGPoint(x: 12, y: 0), 0.08),
                (CGPoint(x: 18, y: 0), 0.12)
            ],
            zoomScale: 2
        )
        try expect(
            zoomOne == zoomTwo,
            "Expected equivalent screen-space motion to produce equal pressure across zoom levels"
        )

        let interpolatedPressure = AnnotationGeometry.pressureInterpolatedFreehandSamples(
            [
                AnnotationPointSample(location: .zero, pressure: 0.2),
                AnnotationPointSample(location: CGPoint(x: 24, y: 0), pressure: 1)
            ]
        )
        try expect(
            interpolatedPressure.count > 2
                && zip(interpolatedPressure, interpolatedPressure.dropFirst()).allSatisfy {
                    pair in
                    let pressureDelta = abs(
                        (pair.1.pressure ?? 1) - (pair.0.pressure ?? 1)
                    )
                    let distance = hypot(
                        pair.1.location.x - pair.0.location.x,
                        pair.1.location.y - pair.0.location.y
                    )
                    return pressureDelta <= 0.061 && distance <= 4.001
                },
            "Expected rendering interpolation to avoid abrupt per-segment width jumps"
        )

        var taperSamples = [
            AnnotationPointSample(location: CGPoint(x: 0, y: 0), pressure: 0.8),
            AnnotationPointSample(location: CGPoint(x: 12, y: 0), pressure: 0.8),
            AnnotationPointSample(location: CGPoint(x: 24, y: 0), pressure: 0.8)
        ]
        AnnotationSimulatedPressureTracker.applyEndTaper(
            to: &taperSamples,
            zoomScale: 1
        )
        let taperPressures = taperSamples.compactMap(\.pressure)
        try expect(
            abs((taperPressures.first ?? 0) - 0.8) < 0.001
                && abs(taperPressures[1] - 0.52) < 0.001
                && abs((taperPressures.last ?? 0) - 0.3) < 0.001,
            "Expected the final taper to preserve the readable pressure floor"
        )

        func simulatedStrokePressures() throws -> [CGFloat?] {
            let controller = AnnotationController()
            controller.currentStyle.pressureMode = .simulated
            controller.currentStyle.strokeWidth = 12
            controller.begin(
                at: .zero,
                pressure: nil,
                timestamp: 0,
                zoomScale: 1
            )
            controller.update(
                at: CGPoint(x: 2, y: 0),
                timestamp: 0.1,
                zoomScale: 1
            )
            controller.update(
                at: CGPoint(x: 122, y: 0),
                timestamp: 0.2,
                zoomScale: 1
            )
            controller.end(
                at: CGPoint(x: 124, y: 0),
                timestamp: 0.3,
                zoomScale: 1
            )
            guard let element = controller.elementSnapshot.first,
                  case .freehand(let freehand) = element.geometry else {
                throw SelfTestError.failure("Expected simulated-pressure freehand geometry")
            }
            try expect(
                AnnotationGeometry.maximumStrokeWidth(for: element) == 12,
                "Expected simulated pressure to leave canonical hit bounds at root width"
            )
            return freehand.samples.map(\.pressure)
        }
        let firstSimulated = try simulatedStrokePressures()
        let repeatedSimulated = try simulatedStrokePressures()
        let resolvedSimulated = firstSimulated.compactMap { $0 }
        let maximumSimulatedDelta = zip(
            resolvedSimulated,
            resolvedSimulated.dropFirst()
        ).map { abs($1 - $0) }.max() ?? 0
        try expect(
            firstSimulated == repeatedSimulated
                && resolvedSimulated.count > 12
                && (resolvedSimulated.max() ?? 0) - (resolvedSimulated.min() ?? 0) > 0.15
                && (resolvedSimulated.first ?? 1) < (resolvedSimulated.max() ?? 0)
                && (resolvedSimulated.last ?? 1) < (resolvedSimulated.max() ?? 0),
            "Expected deterministic resampling and calibrated start/end envelopes"
                + " (count \(resolvedSimulated.count), max delta "
                + "\(maximumSimulatedDelta), range "
                + "\((resolvedSimulated.max() ?? 0) - (resolvedSimulated.min() ?? 0)), "
                + "first \(resolvedSimulated.first ?? -1), "
                + "last \(resolvedSimulated.last ?? -1))"
        )

        let outlierPressures = trackedPressures([
            (CGPoint(x: 3, y: 0), 0.02),
            (CGPoint(x: 6, y: 0), 0.04),
            (CGPoint(x: 180, y: 0), 0.041),
            (CGPoint(x: 183, y: 0), 0.08),
            (CGPoint(x: 186, y: 0), 0.12)
        ])
        try expect(
            outlierPressures.allSatisfy {
                (AnnotationSimulatedPressureTracker.minimumPressure...0.98).contains($0)
            }
                && (outlierPressures.min() ?? 1) < (outlierPressures.max() ?? 0),
            "Expected asymmetric speed and pressure filters to keep outlier response bounded"
        )

        func meanTurn(_ points: [CGPoint]) -> CGFloat {
            guard points.count > 2 else { return 0 }
            let turns = (1..<(points.count - 1)).map { index -> CGFloat in
                let first = CGPoint(
                    x: points[index].x - points[index - 1].x,
                    y: points[index].y - points[index - 1].y
                )
                let second = CGPoint(
                    x: points[index + 1].x - points[index].x,
                    y: points[index + 1].y - points[index].y
                )
                let firstLength = hypot(first.x, first.y)
                let secondLength = hypot(second.x, second.y)
                guard firstLength > 0.0001, secondLength > 0.0001 else { return 0 }
                let cosine = min(
                    1,
                    max(
                        -1,
                        (first.x * second.x + first.y * second.y)
                            / (firstLength * secondLength)
                    )
                )
                return acos(cosine)
            }
            return turns.reduce(0, +) / CGFloat(turns.count)
        }

        let jitterEvents = (0...40).map {
            CGPoint(
                x: CGFloat($0) * 1.2,
                y: $0.isMultiple(of: 2) ? 0.7 : -0.7
            )
        }
        var centerlineResampler = AnnotationFreehandInputResampler()
        let initialJitterSample = AnnotationPointSample(
            location: jitterEvents[0],
            pressure: nil
        )
        centerlineResampler.begin(with: initialJitterSample)
        var resampledCenterline = [initialJitterSample]
        for point in jitterEvents.dropFirst() {
            let result = centerlineResampler.append(
                AnnotationPointSample(location: point, pressure: nil),
                zoomScale: 1
            )
            if result.removesTrailingPreview {
                resampledCenterline.removeLast()
            }
            resampledCenterline.append(contentsOf: result.samples)
            try expect(
                resampledCenterline.last?.location == point,
                "Expected active freehand rendering to reach the current pointer without lag"
            )
        }
        let smoothedCenterline = AnnotationGeometry.smoothedFreehandSamples(
            resampledCenterline,
            subdivisions: 4
        )
        try expect(
            zip(resampledCenterline, resampledCenterline.dropFirst()).allSatisfy {
                hypot(
                    $1.location.x - $0.location.x,
                    $1.location.y - $0.location.y
                ) <= AnnotationFreehandInputResampler.screenSpacing + 0.01
            }
                && meanTurn(smoothedCenterline.map(\.location))
                    < meanTurn(jitterEvents) * 0.55,
            "Expected uniform resampling and corner-aware splines to reduce angular jitter"
        )

        var cornerResampler = AnnotationFreehandInputResampler()
        let cornerStart = AnnotationPointSample(location: .zero, pressure: nil)
        cornerResampler.begin(with: cornerStart)
        var cornerSamples = [cornerStart]
        for point in [CGPoint(x: 8, y: 0), CGPoint(x: 8, y: 8)] {
            let result = cornerResampler.append(
                AnnotationPointSample(location: point, pressure: nil),
                zoomScale: 1
            )
            if result.removesTrailingPreview {
                cornerSamples.removeLast()
            }
            cornerSamples.append(contentsOf: result.samples)
        }
        let boundedJump = cornerResampler.append(
            AnnotationPointSample(
                location: CGPoint(x: 10_000, y: 8),
                pressure: nil,
                timestamp: 1
            ),
            zoomScale: 1
        )
        let jumpAnchor = AnnotationPointSample(
            location: CGPoint(x: 8, y: 8),
            pressure: nil,
            timestamp: 0
        )
        let expectedJumpCount = AnnotationFreehandInputResampler.interpolationStepCount(
            from: jumpAnchor,
            to: AnnotationPointSample(
                location: CGPoint(x: 10_000, y: 8),
                pressure: nil,
                timestamp: 1
            ),
            zoomScale: 1
        )
        var jumpBatches = [boundedJump]
        while cornerResampler.hasPendingSamples {
            jumpBatches.append(cornerResampler.drainPending())
        }
        let drainedJumpSamples = jumpBatches.flatMap(\.samples)
        let jumpSamples = [jumpAnchor] + drainedJumpSamples
        try expect(
            cornerSamples.contains { $0.location == CGPoint(x: 8, y: 0) }
                && jumpBatches.allSatisfy {
                    $0.samples.count
                        <= AnnotationFreehandInputResampler.maximumGeneratedSamplesPerDrain
                }
                && drainedJumpSamples.count == expectedJumpCount
                && drainedJumpSamples.last?.location
                    == CGPoint(x: 10_000, y: 8)
                && zip(jumpSamples, jumpSamples.dropFirst()).allSatisfy {
                    $1.location.x > $0.location.x
                }
                && zip(
                    drainedJumpSamples.compactMap(\.timestamp),
                    drainedJumpSamples.compactMap(\.timestamp).dropFirst()
                ).allSatisfy { $0 <= $1 },
            "Expected intentional corners and timestamps to survive multi-frame bounded resampling"
        )
        try expect(
            drainedJumpSamples.first?.timestamp ?? 0 > 0
                && drainedJumpSamples.last?.timestamp == 1,
            "Expected reconstructed samples to interpolate event timestamps through the full segment"
        )

        let renderInterpolationStress =
            AnnotationGeometry.pressureInterpolatedFreehandSamples(
                [
                    AnnotationPointSample(
                        location: .zero,
                        pressure: AnnotationSimulatedPressureTracker.minimumPressure
                    ),
                    AnnotationPointSample(
                        location: CGPoint(x: 100_000, y: 0),
                        pressure: 0.98
                    )
                ]
            )
        try expect(
            renderInterpolationStress.count
                <= AnnotationGeometry.maximumPressureInterpolationStepsPerSegment + 1
                && renderInterpolationStress.last?.location
                    == CGPoint(x: 100_000, y: 0),
            "Expected render interpolation to cap per-segment work without losing the endpoint"
        )

        let highlighterPressureController = AnnotationController()
        highlighterPressureController.currentTool = .highlighter
        highlighterPressureController.currentStyle.pressureMode = .simulated
        highlighterPressureController.begin(
            at: .zero,
            tool: .highlighter,
            timestamp: 0,
            zoomScale: 1
        )
        highlighterPressureController.update(
            at: CGPoint(x: 100, y: 0),
            timestamp: 0.1,
            zoomScale: 1
        )
        highlighterPressureController.end(
            at: CGPoint(x: 200, y: 0),
            timestamp: 0.2,
            zoomScale: 1
        )
        guard case .freehand(let highlighterPressureStroke) =
                highlighterPressureController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected simulated-pressure highlighter geometry")
        }
        try expect(
            highlighterPressureController.elementSnapshot[0].style.pressureMode == .fixed
                && highlighterPressureStroke.samples.allSatisfy {
                    $0.pressure == nil
                },
            "Expected Highlighter to stay constant-width and ignore hidden pressure state"
        )

        var zoomAwareResampler = AnnotationFreehandInputResampler()
        let zoomAwareStart = AnnotationPointSample(
            location: .zero,
            pressure: nil,
            timestamp: 0
        )
        zoomAwareResampler.begin(with: zoomAwareStart)
        let zoomAware = zoomAwareResampler.append(
            AnnotationPointSample(
                location: CGPoint(x: 10, y: 0),
                pressure: nil,
                timestamp: 0.01
            ),
            zoomScale: 2
        )
        try expect(
            zoomAware.samples.count == 8
                && zip(
                    [zoomAwareStart] + zoomAware.samples,
                    ([zoomAwareStart] + zoomAware.samples).dropFirst()
                ).allSatisfy {
                    hypot(
                        $1.location.x - $0.location.x,
                        $1.location.y - $0.location.y
                    ) * 2 <= AnnotationFreehandInputResampler.screenSpacing + 0.001
                },
            "Expected freehand spacing to remain constant in destination pixels across zoom"
        )

        let sparseEvents: [(CGPoint, TimeInterval)] = [
            (CGPoint(x: 8, y: 20), 0),
            (CGPoint(x: 82, y: 20), 0.008),
            (CGPoint(x: 136, y: 52), 0.016),
            (CGPoint(x: 82, y: 84), 0.024),
            (CGPoint(x: 8, y: 84), 0.032)
        ]
        let sparseController = AnnotationController()
        sparseController.currentStyle.sloppiness = .architect
        sparseController.currentStyle.smoothingEnabled = true
        sparseController.begin(
            at: sparseEvents[0].0,
            pressure: nil,
            timestamp: sparseEvents[0].1,
            zoomScale: 1
        )
        for event in sparseEvents.dropFirst().dropLast() {
            sparseController.update(
                at: event.0,
                timestamp: event.1,
                zoomScale: 1
            )
        }
        let lastSparseEvent = sparseEvents[sparseEvents.count - 1]
        sparseController.end(
            at: lastSparseEvent.0,
            timestamp: lastSparseEvent.1,
            zoomScale: 1
        )
        guard let sparseElement = sparseController.elementSnapshot.first,
              case .freehand(let sparseFreehand) = sparseElement.geometry else {
            throw SelfTestError.failure("Expected sparse high-speed freehand geometry")
        }
        let sparseLocations = sparseFreehand.samples.map(\.location)
        let sparseTimestamps = sparseFreehand.samples.compactMap(\.timestamp)
        let smoothedSparse = AnnotationGeometry.smoothedFreehandSamples(
            sparseFreehand.samples,
            subdivisions: 3
        )
        let smoothedPath = AnnotationGeometry.smoothedFreehandPath(
            sparseFreehand.samples
        )
        let expectedSparseMaximum = zip(
            sparseEvents,
            sparseEvents.dropFirst()
        ).reduce(1) { count, events in
            count + AnnotationFreehandInputResampler.interpolationStepCount(
                from: AnnotationPointSample(
                    location: events.0.0,
                    pressure: nil,
                    timestamp: events.0.1
                ),
                to: AnnotationPointSample(
                    location: events.1.0,
                    pressure: nil,
                    timestamp: events.1.1
                ),
                zoomScale: 1
            )
        }
        try expect(
            sparseEvents.allSatisfy { event in
                sparseFreehand.samples.contains {
                    $0.location == event.0 && $0.timestamp == event.1
                }
            }
                && sparseLocations.first == sparseEvents.first?.0
                && sparseLocations.last == sparseEvents.last?.0
                && zip(sparseLocations, sparseLocations.dropFirst()).allSatisfy {
                    hypot($1.x - $0.x, $1.y - $0.y)
                        <= AnnotationFreehandInputResampler.screenSpacing + 0.001
                }
                && sparseTimestamps.count == sparseFreehand.samples.count
                && zip(sparseTimestamps, sparseTimestamps.dropFirst()).allSatisfy {
                    $0 <= $1
                }
                && sparseFreehand.samples.count <= expectedSparseMaximum
                && smoothedSparse.allSatisfy {
                    AnnotationGeometry.distance(
                        from: $0.location,
                        toPolyline: sparseLocations
                    ) <= 1
                }
                && AnnotationRoughStroke.pathElementCount(smoothedPath)
                    <= sparseFreehand.samples.count,
            "Expected sparse high-speed events to produce a timestamped, bounded, loop-safe stroke"
        )

        let fastLoopEvents = (0...8).map { index -> (CGPoint, TimeInterval) in
            let angle = CGFloat(index) * 2 * .pi / 8
            return (
                CGPoint(
                    x: 180 + cos(angle) * 54,
                    y: 80 + sin(angle) * 34
                ),
                Double(index) * 0.006
            )
        }
        let loopController = AnnotationController()
        loopController.currentStyle.sloppiness = .architect
        loopController.begin(
            at: fastLoopEvents[0].0,
            pressure: nil,
            timestamp: fastLoopEvents[0].1,
            zoomScale: 1
        )
        for event in fastLoopEvents.dropFirst().dropLast() {
            loopController.update(
                at: event.0,
                timestamp: event.1,
                zoomScale: 1
            )
        }
        let loopEnd = fastLoopEvents[fastLoopEvents.count - 1]
        loopController.end(
            at: loopEnd.0,
            timestamp: loopEnd.1,
            zoomScale: 1
        )
        guard let loopElement = loopController.elementSnapshot.first,
              case .freehand(let loopFreehand) = loopElement.geometry else {
            throw SelfTestError.failure("Expected fast loop freehand geometry")
        }
        let smoothLoop = AnnotationGeometry.smoothedFreehandSamples(
            loopFreehand.samples,
            subdivisions: 3
        ).map(\.location)
        try expect(
            smoothLoop.allSatisfy {
                (124...236).contains($0.x)
                    && (44...116).contains($0.y)
            }
                && zip(smoothLoop, smoothLoop.dropFirst()).allSatisfy {
                    hypot($1.x - $0.x, $1.y - $0.y)
                        <= AnnotationFreehandInputResampler.screenSpacing + 0.5
                },
            "Expected a sparse fast loop to stay inside its local envelope without giant spline loops"
        )

        func properIntersectionCount(_ points: [CGPoint]) -> Int {
            guard points.count > 3 else { return 0 }
            func cross(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
                first.x * second.y - first.y * second.x
            }
            func vector(from start: CGPoint, to end: CGPoint) -> CGPoint {
                CGPoint(x: end.x - start.x, y: end.y - start.y)
            }
            var count = 0
            for firstIndex in 0..<(points.count - 1) {
                let firstStart = points[firstIndex]
                let firstEnd = points[firstIndex + 1]
                guard firstIndex + 2 < points.count - 1 else { continue }
                for secondIndex in (firstIndex + 2)..<(points.count - 1) {
                    let secondStart = points[secondIndex]
                    let secondEnd = points[secondIndex + 1]
                    if firstStart == secondStart
                        || firstStart == secondEnd
                        || firstEnd == secondStart
                        || firstEnd == secondEnd {
                        continue
                    }
                    let firstVector = vector(from: firstStart, to: firstEnd)
                    let secondVector = vector(from: secondStart, to: secondEnd)
                    let firstSide = cross(
                        firstVector,
                        vector(from: firstStart, to: secondStart)
                    )
                    let secondSide = cross(
                        firstVector,
                        vector(from: firstStart, to: secondEnd)
                    )
                    let thirdSide = cross(
                        secondVector,
                        vector(from: secondStart, to: firstStart)
                    )
                    let fourthSide = cross(
                        secondVector,
                        vector(from: secondStart, to: firstEnd)
                    )
                    if firstSide * secondSide < -0.000_1
                        && thirdSide * fourthSide < -0.000_1 {
                        count += 1
                    }
                }
            }
            return count
        }

        let figureEightEvents: [(CGPoint, TimeInterval)] = [
            (CGPoint(x: 300, y: 80), 0),
            (CGPoint(x: 270, y: 48), 0.006),
            (CGPoint(x: 238, y: 80), 0.012),
            (CGPoint(x: 270, y: 112), 0.018),
            (CGPoint(x: 300, y: 80), 0.024),
            (CGPoint(x: 330, y: 48), 0.030),
            (CGPoint(x: 362, y: 80), 0.036),
            (CGPoint(x: 330, y: 112), 0.042),
            (CGPoint(x: 300, y: 80), 0.048)
        ]
        let figureEightController = AnnotationController()
        figureEightController.currentStyle.sloppiness = .architect
        figureEightController.begin(
            at: figureEightEvents[0].0,
            pressure: nil,
            timestamp: figureEightEvents[0].1,
            zoomScale: 1
        )
        figureEightController.updateFreehand(
            inputs: figureEightEvents.dropFirst().map {
                AnnotationRawFreehandInput(
                    location: $0.0,
                    pressure: nil,
                    timestamp: $0.1
                )
            },
            zoomScale: 1
        )
        guard let figureEightElement =
                figureEightController.inProgressElementSnapshot,
              case .freehand(let figureEight) = figureEightElement.geometry else {
            throw SelfTestError.failure("Expected figure-eight freehand geometry")
        }
        let smoothFigureEight = AnnotationGeometry.smoothedFreehandSamples(
            figureEight.samples,
            subdivisions: 2
        ).map(\.location)
        let sampledFigureEight = stride(
            from: 0,
            to: smoothFigureEight.count,
            by: 2
        ).map { smoothFigureEight[$0] }
        try expect(
            properIntersectionCount(sampledFigureEight)
                <= properIntersectionCount(figureEightEvents.map(\.0)),
            "Expected loop-safe smoothing not to add intersections to a sparse figure-eight"
        )
    }

    private static func testBoundedFreehandPipelineAndRenderCache() throws {
        let controller = AnnotationController()
        controller.currentStyle.sloppiness = .architect
        controller.currentStyle.smoothingEnabled = false
        controller.begin(at: .zero, pressure: nil, timestamp: 0, zoomScale: 1)
        let inputs = (1...1_000).map { index in
            AnnotationRawFreehandInput(
                location: CGPoint(x: CGFloat(index) * 10, y: 0),
                pressure: nil,
                timestamp: Double(index) / 240
            )
        }
        controller.enqueueFreehandInputs(inputs)
        var drainCount = 0
        while controller.hasPendingFreehandInput {
            let stats = controller.drainFreehandInput(zoomScale: 1)
            drainCount += 1
            try expect(
                stats.rawEvents <= AnnotationFreehandDrainBudget.frame.maximumRawEvents
                    && stats.generatedSamples
                        <= AnnotationFreehandDrainBudget.frame.maximumGeneratedSamples,
                "Expected every freehand drain to remain inside raw-event and sample budgets"
            )
            guard drainCount < 10_000 else {
                throw SelfTestError.failure("Bounded freehand input did not eventually drain")
            }
        }
        guard let active = controller.inProgressElementSnapshot,
              case .freehand(let drained) = active.geometry else {
            throw SelfTestError.failure("Expected a drained active freehand stroke")
        }
        try expect(
            drained.samples.last?.location == inputs.last?.location
                && zip(drained.samples, drained.samples.dropFirst()).allSatisfy {
                    hypot(
                        $1.location.x - $0.location.x,
                        $1.location.y - $0.location.y
                    ) <= AnnotationFreehandInputResampler.screenSpacing + 0.001
                },
            "Expected 1,000 raw events and 10,000 pixels to drain to the reference trajectory"
        )

        var frameState = DrawingFreehandFrameInvalidationState()
        for _ in 0..<60 {
            for _ in 0..<4 {
                frameState.noteInput()
            }
            try expect(
                frameState.beginFrame() && !frameState.beginFrame(),
                "Expected at most one display invalidation in each 60 Hz frame"
            )
        }
        try expect(
            frameState.invalidationCount == 60
                && ZoomCanvasView.maximumFreehandEventsPerUpdate <= 8,
            "Expected 240 Hz input to coalesce to 60 invalidations"
        )

        var lastRecognitionTime: TimeInterval?
        var lastRecognizedSampleCount = 0
        var recognitionSubmissions = 0
        for sampleCount in 1...240 {
            let timestamp = Double(sampleCount) / 240
            if SmartDrawRecognitionBudget.shouldRecognizePreview(
                lastRecognitionTime: lastRecognitionTime,
                lastRecognizedSampleCount: lastRecognizedSampleCount,
                timestamp: timestamp,
                sampleCount: sampleCount
            ) {
                recognitionSubmissions += 1
                lastRecognitionTime = timestamp
                lastRecognizedSampleCount = sampleCount
            }
        }
        var generations = SmartDrawRecognitionGenerationState()
        generations.beginStroke()
        let staleRequest = generations.submit()
        let currentRequest = generations.submit()
        try expect(
            recognitionSubmissions <= 25
                && !generations.accepts(staleRequest)
                && generations.accepts(currentRequest),
            "Expected bounded recognizer cadence and latest-generation stale-result rejection"
        )

        let renderer = AnnotationRenderer()
        let samples = (0..<10_000).map { index in
            AnnotationPointSample(
                location: CGPoint(
                    x: 8 + CGFloat(index) * 0.004,
                    y: 32 + sin(CGFloat(index) * 0.01)
                ),
                pressure: nil
            )
        }
        var style = AnnotationStyle(color: .blue, rootWidth: 3, alpha: 1)
        style.sloppiness = .architect
        style.smoothingEnabled = false
        var activeStroke = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: samples,
                    isHighlighter: false
                )
            ),
            style: style
        )
        _ = try renderPixels(
            elements: [],
            renderer: renderer,
            activeElement: activeStroke,
            width: 64,
            height: 64
        )
        let initialRebuilds = renderer.activeStrokeCacheCountersForTesting.rebuiltChunks
        guard case .freehand(var appended) = activeStroke.geometry else {
            throw SelfTestError.failure("Expected active cache freehand geometry")
        }
        appended.samples.append(
            AnnotationPointSample(location: CGPoint(x: 48.004, y: 32), pressure: nil)
        )
        activeStroke.geometry = .freehand(appended)
        _ = try renderPixels(
            elements: [],
            renderer: renderer,
            activeElement: activeStroke,
            width: 64,
            height: 64
        )
        let appendRebuilds =
            renderer.activeStrokeCacheCountersForTesting.rebuiltChunks - initialRebuilds
        let beforeUnchanged =
            renderer.activeStrokeCacheCountersForTesting.rebuiltChunks
        _ = try renderPixels(
            elements: [],
            renderer: renderer,
            activeElement: activeStroke,
            width: 64,
            height: 64
        )
        try expect(
            appendRebuilds <= 2
                && renderer.activeStrokeCacheCountersForTesting.rebuiltChunks
                    == beforeUnchanged,
            "Expected a 10k-stroke append to rebuild at most two chunks and unchanged redraw to rebuild none"
        )
    }

    private static func testCommittedFreehandRenderCache() throws {
        func penStroke(
            index: Int,
            sampleCount: Int = 1_000,
            pressureEnabled: Bool = false,
            sloppiness: AnnotationSloppiness = .artist
        ) -> AnnotationElement {
            var style = AnnotationStyle(
                color: index.isMultiple(of: 2) ? .blue : .red,
                rootWidth: 5,
                alpha: 0.9
            )
            style.sloppiness = sloppiness
            style.smoothingEnabled = true
            style.pressureMode = pressureEnabled ? .tablet : .fixed
            let samples = (0..<sampleCount).map { sampleIndex in
                AnnotationPointSample(
                    location: CGPoint(
                        x: 8 + CGFloat(sampleIndex) * 0.075,
                        y: 10 + CGFloat(index) * 7
                            + sin(CGFloat(sampleIndex) * 0.035) * 2
                    ),
                    pressure: pressureEnabled
                        ? 0.25 + CGFloat(sampleIndex % 80) / 120
                        : nil
                )
            }
            return AnnotationElement(
                geometry: .freehand(
                    AnnotationFreehandGeometry(
                        samples: samples,
                        isHighlighter: false
                    )
                ),
                style: style
            )
        }

        let renderer = AnnotationRenderer()
        var strokes = (0..<10).map { penStroke(index: $0) }
        _ = try renderPixels(
            elements: strokes,
            renderer: renderer,
            width: 96,
            height: 88
        )
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements == 10,
            "Expected the first 10x1000 Artist-stroke render to build ten committed cache entries"
        )
        let buildsBeforeUnchanged =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(
            elements: strokes,
            renderer: renderer,
            width: 96,
            height: 88
        )
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                == buildsBeforeUnchanged,
            "Expected unchanged committed freehand redraw to rebuild zero elements"
        )

        strokes.append(penStroke(index: 10, sampleCount: 300))
        var buildsBeforeMutation =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(
            elements: strokes,
            renderer: renderer,
            width: 96,
            height: 96
        )
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                - buildsBeforeMutation == 1,
            "Expected appending a committed stroke to build only the new element"
        )

        strokes[2].style.strokeWidth += 2
        buildsBeforeMutation =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(elements: strokes, renderer: renderer)
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                - buildsBeforeMutation == 1,
            "Expected a style edit to rebuild only the affected freehand element"
        )

        strokes[3].style.sloppiness = .cartoonist
        buildsBeforeMutation =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(elements: strokes, renderer: renderer)
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                - buildsBeforeMutation == 1,
            "Expected a sloppiness edit to rebuild only the affected freehand element"
        )

        guard case .freehand(var pressureGeometry) = strokes[4].geometry else {
            throw SelfTestError.failure("Expected pressure-cache freehand geometry")
        }
        strokes[4].style.pressureMode = .tablet
        pressureGeometry.samples[100].pressure = 0.35
        strokes[4].geometry = .freehand(pressureGeometry)
        buildsBeforeMutation =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(elements: strokes, renderer: renderer)
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                - buildsBeforeMutation == 1,
            "Expected a pressure edit to rebuild only the affected freehand element"
        )

        strokes[5].metadata.rotation = .pi / 8
        buildsBeforeMutation =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(elements: strokes, renderer: renderer)
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                - buildsBeforeMutation == 1,
            "Expected a transform edit to rebuild only the affected freehand element"
        )

        strokes[6].style.strokeColor = .palette(.green)
        buildsBeforeMutation =
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(elements: strokes, renderer: renderer)
        try expect(
            renderer.committedStrokeCacheCountersForTesting.rebuiltElements
                - buildsBeforeMutation == 1,
            "Expected a color edit to invalidate only the affected freehand element"
        )

        let scaleRenderer = AnnotationRenderer()
        let scaleStroke = penStroke(
            index: 0,
            sampleCount: 220,
            sloppiness: .cartoonist
        )
        _ = try renderPixels(
            elements: [scaleStroke],
            renderer: scaleRenderer,
            destinationPointScale: 1
        )
        _ = try renderPixels(
            elements: [scaleStroke],
            renderer: scaleRenderer,
            destinationPointScale: 2
        )
        let buildsBeforeScaleReuse =
            scaleRenderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(
            elements: [scaleStroke],
            renderer: scaleRenderer,
            destinationPointScale: 1
        )
        _ = try renderPixels(
            elements: [scaleStroke],
            renderer: scaleRenderer,
            destinationPointScale: 3
        )
        try expect(
            buildsBeforeScaleReuse == 2
                && scaleRenderer.committedStrokeCacheCountersForTesting.rebuiltElements
                    == 3
                && scaleRenderer.committedStrokeCacheScaleVariantCountForTesting(
                    elementID: scaleStroke.id
                ) == 2,
            "Expected scale-specific reuse with at most two recent variants per element"
        )

        var highlighterStyle = AnnotationStyle(
            color: .highlighterYellow,
            rootWidth: 18,
            alpha: 0.8,
            sloppiness: .architect
        )
        highlighterStyle.smoothingEnabled = true
        let highlighter = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(
                            location: CGPoint(x: 12, y: 48),
                            pressure: nil
                        ),
                        AnnotationPointSample(
                            location: CGPoint(x: 84, y: 48),
                            pressure: nil
                        )
                    ],
                    isHighlighter: true
                )
            ),
            style: highlighterStyle
        )
        let highlighterRenderer = AnnotationRenderer()
        let yellowPixels = try renderPixels(
            elements: [highlighter],
            renderer: highlighterRenderer
        )
        let highlighterBuilds =
            highlighterRenderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(
            elements: [highlighter],
            renderer: highlighterRenderer
        )
        var editedHighlighter = highlighter
        editedHighlighter.style.strokeColor = .palette(.highlighterPink)
        editedHighlighter.style.opacity = 0.35
        let pinkPixels = try renderPixels(
            elements: [editedHighlighter],
            renderer: highlighterRenderer
        )
        let yellowPixel = pixel(yellowPixels, width: 96, x: 48, y: 48)
        let pinkPixel = pixel(pinkPixels, width: 96, x: 48, y: 48)
        try expect(
            highlighterBuilds == 1
                && highlighterRenderer.committedStrokeCacheCountersForTesting.rebuiltElements
                    == highlighterBuilds + 1
                && pinkPixel.alpha < yellowPixel.alpha
                && pinkPixel.red > pinkPixel.green,
            "Expected cached Highlighter paths to preserve updated color and effective opacity"
        )

        let activeRenderer = AnnotationRenderer()
        let promotableStroke = penStroke(
            index: 0,
            sampleCount: 64,
            sloppiness: .architect
        )
        _ = try renderPixels(
            elements: [],
            renderer: activeRenderer,
            activeElement: promotableStroke
        )
        try expect(
            activeRenderer.committedStrokeCacheEntryCountForTesting == 0,
            "Expected active/immediate presentation to stay out of the committed cache"
        )
        activeRenderer.promoteActiveStrokeCache(
            for: promotableStroke,
            destinationPointScale: 1
        )
        _ = try renderPixels(
            elements: [promotableStroke],
            renderer: activeRenderer
        )
        try expect(
            activeRenderer.committedStrokeCacheCountersForTesting.promotedElements == 1
                && activeRenderer.committedStrokeCacheCountersForTesting.rebuiltElements == 0,
            "Expected an exact finalized active chunk to promote without committed reconstruction"
        )

        let promotionController = AnnotationController()
        promotionController.currentStyle.sloppiness = .architect
        promotionController.currentStyle.smoothingEnabled = false
        promotionController.begin(
            at: CGPoint(x: 12, y: 32),
            pressure: nil,
            timestamp: 0,
            zoomScale: 1
        )
        for index in 1...20 {
            promotionController.update(
                at: CGPoint(x: 12 + CGFloat(index) * 2, y: 32),
                pressure: nil,
                timestamp: Double(index) / 120,
                zoomScale: 1
            )
        }
        _ = try renderControllerPixels(
            promotionController,
            freehandPresentationOwner: .immediateLayers,
            width: 64,
            height: 64
        )
        try expect(
            promotionController.committedStrokeCacheEntryCountForTesting == 0,
            "Expected the immediate-layer owner not to leak active geometry into committed entries"
        )
        _ = try renderControllerPixels(
            promotionController,
            freehandPresentationOwner: .canonicalRenderer,
            width: 64,
            height: 64
        )
        promotionController.end(
            at: CGPoint(x: 52, y: 32),
            pressure: nil,
            timestamp: 21.0 / 120,
            zoomScale: 1
        )
        _ = try renderControllerPixels(
            promotionController,
            freehandPresentationOwner: .canonicalRenderer,
            width: 64,
            height: 64
        )
        try expect(
            promotionController.committedStrokeCacheCountersForTesting.promotedElements
                == 1
                && promotionController.committedStrokeCacheCountersForTesting.rebuiltElements
                    == 0,
            "Expected controller commit to promote a finalized active cache entry"
        )

        let historyRenderer = AnnotationRenderer()
        let scene = AnnotationScene()
        let historyStroke = penStroke(index: 0, sampleCount: 180)
        scene.append(historyStroke)
        _ = try renderPixels(
            elements: scene.elements,
            renderer: historyRenderer
        )
        scene.removeElements(withIDs: [historyStroke.id])
        _ = try renderPixels(elements: scene.elements, renderer: historyRenderer)
        try expect(
            !historyRenderer.hasCommittedStrokeCacheForTesting(
                elementID: historyStroke.id
            ),
            "Expected deletion to evict the removed committed stroke"
        )
        try expect(scene.undo(), "Expected undo to restore the deleted stroke")
        let buildsBeforeUndoRestore =
            historyRenderer.committedStrokeCacheCountersForTesting.rebuiltElements
        _ = try renderPixels(elements: scene.elements, renderer: historyRenderer)
        try expect(
            historyRenderer.committedStrokeCacheCountersForTesting.rebuiltElements
                == buildsBeforeUndoRestore + 1
                && historyRenderer.hasCommittedStrokeCacheForTesting(
                    elementID: historyStroke.id
                ),
            "Expected undo to rebuild the restored stable-ID cache entry"
        )
        try expect(scene.redo(), "Expected redo to delete the restored stroke")
        _ = try renderPixels(elements: scene.elements, renderer: historyRenderer)
        try expect(
            historyRenderer.committedStrokeCacheEntryCountForTesting == 0,
            "Expected redo deletion to evict the restored cache entry"
        )
        scene.undo()
        _ = try renderPixels(elements: scene.elements, renderer: historyRenderer)
        scene.clear()
        _ = try renderPixels(elements: scene.elements, renderer: historyRenderer)
        try expect(
            historyRenderer.committedStrokeCacheEntryCountForTesting == 0,
            "Expected clear to evict all committed freehand cache entries"
        )

        let boundedRenderer = AnnotationRenderer(
            committedStrokeCacheCostLimit: 1_000_000,
            committedStrokeCacheEntryLimit: 3
        )
        let boundedStrokes = (0..<8).map { penStroke(index: $0) }
        _ = try renderPixels(
            elements: boundedStrokes,
            renderer: boundedRenderer,
            width: 96,
            height: 72
        )
        try expect(
            boundedRenderer.committedStrokeCacheEntryCountForTesting <= 3
                && boundedRenderer.committedStrokeCacheEstimatedCostForTesting
                    <= 1_000_000
                && boundedRenderer.committedStrokeCacheCountersForTesting.evictedEntries
                    >= 5,
            "Expected committed stroke cache LRU limits to bound entries and estimated memory"
        )
    }

    private static func testImmediateFreehandPresentationAndQueueBounds() throws {
        for rate in [125, 240, 500, 1_000] {
            var visualLane = DrawingLatestRawPointerLane()
            let controller = AnnotationController()
            controller.currentStyle.sloppiness = .architect
            controller.currentStyle.smoothingEnabled = false
            controller.begin(
                at: .zero,
                pressure: nil,
                timestamp: 0,
                zoomScale: 1
            )
            let eventCount = rate * 10
            let eventsPerFrame = max(1, Int(ceil(Double(rate) / 60)))
            var latest = AnnotationRawFreehandInput(
                location: .zero,
                pressure: nil,
                timestamp: 0
            )
            var maximumQueueCount = 0
            var maximumQueueAge = TimeInterval.zero
            for index in 1...eventCount {
                latest = AnnotationRawFreehandInput(
                    location: CGPoint(
                        x: CGFloat(index) * 0.4,
                        y: sin(CGFloat(index) * 0.018) * 14
                    ),
                    pressure: index.isMultiple(of: 97)
                        ? 1
                        : 0.35 + CGFloat(index % 11) * 0.04,
                    timestamp: Double(index) / Double(rate)
                )
                visualLane.update(latest)
                controller.enqueueFreehandInputs([latest])
                maximumQueueCount = max(
                    maximumQueueCount,
                    controller.pendingRawFreehandInputCountForTesting
                )
                maximumQueueAge = max(
                    maximumQueueAge,
                    controller.pendingRawFreehandInputAgeForTesting
                )
                if index.isMultiple(of: eventsPerFrame) {
                    let stats = controller.drainFreehandInput(
                        zoomScale: 1,
                        budget: AnnotationFreehandDrainBudget(
                            maximumRawEvents: 12,
                            maximumGeneratedSamples: 96,
                            spacingScale: controller
                                .pendingRawFreehandInputCountForTesting > 20
                                ? 2
                                : 1
                        )
                    )
                    try expect(
                        stats.rawEvents <= 12
                            && stats.generatedSamples <= 96,
                        "Expected strict per-frame freehand work budgets at \(rate) Hz"
                    )
                }
                try expect(
                    visualLane.latestRawPointer == latest
                        && visualLane.recentSamples.last == latest,
                    "Expected the replace-only visual lane to expose the newest \(rate) Hz event immediately"
                )
            }
            _ = controller.finishQueuedFreehandBounded(
                endingPressure: latest.pressure,
                timestamp: latest.timestamp,
                zoomScale: 1
            )
            guard let element = controller.elementSnapshot.last,
                  case .freehand(let freehand) = element.geometry else {
                throw SelfTestError.failure(
                    "Expected finalized sustained \(rate) Hz freehand geometry"
                )
            }
            try expect(
                maximumQueueCount <= AnnotationRawFreehandInputBuffer.defaultCapacity
                    && maximumQueueAge
                        <= AnnotationRawFreehandInputBuffer.maximumBufferedDuration
                            + 1 / Double(rate) + 0.001
                    && visualLane.recentSamples.count
                        <= DrawingLatestRawPointerLane.maximumSampleCount
                    && (visualLane.recentSamples.last!.timestamp
                        - visualLane.recentSamples.first!.timestamp)
                        <= DrawingLatestRawPointerLane.maximumDuration + 0.001
                    && freehand.samples.last?.location == latest.location
                    && !controller.hasPendingFreehandInput
                    && zip(
                        freehand.samples.map(\.location),
                        freehand.samples.map(\.location).dropFirst()
                    ).allSatisfy { $0.x <= $1.x },
                "Expected bounded \(rate) Hz queues, an immediate latest endpoint, and loop-safe finalization"
            )
        }

        var buffer = AnnotationRawFreehandInputBuffer(capacity: 8)
        let corner = AnnotationRawFreehandInput(
            location: CGPoint(x: 10, y: 0),
            pressure: 0.5,
            timestamp: 0.005
        )
        let pressureMinimum = AnnotationRawFreehandInput(
            location: CGPoint(x: 20, y: 10),
            pressure: 0.2,
            timestamp: 0.015
        )
        let pressureMaximum = AnnotationRawFreehandInput(
            location: CGPoint(x: 30, y: 10),
            pressure: 0.95,
            timestamp: 0.02
        )
        [
            AnnotationRawFreehandInput(
                location: .zero,
                pressure: 0.5,
                timestamp: 0
            ),
            corner,
            AnnotationRawFreehandInput(
                location: CGPoint(x: 10, y: 10),
                pressure: 0.5,
                timestamp: 0.01
            ),
            pressureMinimum,
            pressureMaximum,
            AnnotationRawFreehandInput(
                location: CGPoint(x: 40, y: 10),
                pressure: 0.5,
                timestamp: 0.025
            )
        ].forEach { buffer.append($0) }
        var retained: [AnnotationRawFreehandInput] = []
        while let input = buffer.popFirst() {
            retained.append(input)
        }
        try expect(
            retained.contains(corner)
                && retained.contains(pressureMinimum)
                && retained.contains(pressureMaximum),
            "Expected queue compaction to preserve endpoints, significant turns, and pressure extrema"
        )

        let source = CGRect(x: 120, y: 80, width: 640, height: 360)
        let destination = CGRect(x: 0, y: 0, width: 1_280, height: 720)
        let cursor = CGPoint(x: 913.25, y: 421.5)
        let content = DrawingImmediateFreehandPresentationPolicy.contentPoint(
            forViewPoint: cursor,
            source: source,
            destinationBounds: destination
        )
        let projected = DrawingImmediateFreehandPresentationPolicy.viewPoint(
            forContentPoint: content,
            source: source,
            destinationBounds: destination
        )
        let movingPointerVisible =
            DrawingImmediateFreehandPresentationPolicy.showsStandalonePointer(
                hasMoved: true,
                tailPointCount: 3
            )
        try expect(
            hypot(projected.x - cursor.x, projected.y - cursor.y) < 0.001
                && !movingPointerVisible
                && DrawingImmediateFreehandPresentationPolicy
                    .immediateTipComponentCount(
                        tailPointCount: 3,
                        showsStandalonePointer: movingPointerVisible
                    ) == 1
                && DrawingImmediateFreehandPresentationPolicy
                    .immediateTipComponentCount(
                        tailPointCount: 1,
                        showsStandalonePointer:
                            DrawingImmediateFreehandPresentationPolicy
                                .showsStandalonePointer(
                                    hasMoved: false,
                                    tailPointCount: 1
                                )
                    ) == 1,
            "Expected the moving tail endpoint to coincide with the cursor and render exactly one nib component"
        )

        for scale in [1, 2] {
            let logicalWidth = 64
            let logicalHeight = 48
            let width = logicalWidth * scale
            let height = logicalHeight * scale
            var layerPixels = [UInt8](repeating: 0, count: width * height * 4)
            try layerPixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    throw SelfTestError.failure(
                        "Could not create immediate-layer raster bitmap"
                    )
                }
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                let parent = CALayer()
                parent.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: logicalWidth,
                    height: logicalHeight
                )
                parent.isGeometryFlipped = true
                let child = CAShapeLayer()
                child.frame = parent.bounds
                child.contentsScale = CGFloat(scale)
                ZoomCanvasView.configureImmediateFreehandLayerGeometry(child)
                let asymmetric = CGMutablePath()
                asymmetric.move(to: CGPoint(x: 6, y: 5))
                asymmetric.addLine(to: CGPoint(x: 24, y: 14))
                asymmetric.addLine(to: CGPoint(x: 50, y: 36))
                child.path = asymmetric
                child.strokeColor = NSColor.white.cgColor
                child.fillColor = nil
                child.lineWidth = 2
                child.lineCap = .round
                parent.addSublayer(child)
                parent.render(in: context)
                context.flush()
            }
            let endpointAlpha = alpha(
                layerPixels,
                width: width,
                x: 50 * scale,
                y: 36 * scale
            )
            let reflectedAlpha = alpha(
                layerPixels,
                width: width,
                x: 50 * scale,
                y: (logicalHeight - 36) * scale
            )
            try expect(
                endpointAlpha > 0 && reflectedAlpha == 0,
                "Expected the \(scale)x immediate CAShapeLayer endpoint at the raw cursor, not reflected"
            )
        }

        let stampController = AnnotationController()
        stampController.currentTool = .highlighter
        stampController.setOpacity(1)
        stampController.begin(at: CGPoint(x: 48, y: 32))
        let canonicalStamp = try renderControllerPixels(
            stampController,
            freehandPresentationOwner: .canonicalRenderer,
            width: 96,
            height: 64
        )
        let immediateOwnedStamp = try renderControllerPixels(
            stampController,
            freehandPresentationOwner: .immediateLayers,
            width: 96,
            height: 64
        )
        let configuredStampAlpha = alpha(
            canonicalStamp,
            width: 96,
            x: 48,
            y: 32
        )
        try expect(
            (120...135).contains(configuredStampAlpha)
                && alpha(immediateOwnedStamp, width: 96, x: 48, y: 32) == 0,
            "Expected a single Highlighter press to have one configured-opacity owner, "
                + "not a canonical-plus-overlay 75% composite"
        )

        let tailController = AnnotationController()
        tailController.currentTool = .highlighter
        tailController.currentStyle.smoothingEnabled = false
        tailController.begin(
            at: CGPoint(x: 12, y: 32),
            pressure: nil,
            timestamp: 0,
            zoomScale: 1
        )
        tailController.update(
            at: CGPoint(x: 40, y: 32),
            timestamp: 0.1,
            zoomScale: 1
        )
        tailController.enqueueFreehandInputs([
            AnnotationRawFreehandInput(
                location: CGPoint(x: 84, y: 32),
                pressure: nil,
                timestamp: 0.2
            )
        ])
        let canonicalTail = try renderControllerPixels(
            tailController,
            freehandPresentationOwner: .canonicalRenderer,
            width: 96,
            height: 64
        )
        let immediateOwnedTail = try renderControllerPixels(
            tailController,
            freehandPresentationOwner: .immediateLayers,
            width: 96,
            height: 64
        )
        try expect(
            alpha(canonicalTail, width: 96, x: 70, y: 32) > 0
                && alpha(immediateOwnedTail, width: 96, x: 24, y: 32) > 0
                && alpha(immediateOwnedTail, width: 96, x: 70, y: 32) == 0,
            "Expected the canonical renderer to retain committed freehand content "
                + "while immediate layers exclusively own the queued straight tail"
        )
    }

    private static func testSmartDrawClosedShapeRecognition() throws {
        let circle = noisyEllipsePoints(
            center: CGPoint(x: 120, y: 100),
            radiusX: 58,
            radiusY: 57,
            rotation: 0,
            count: 64
        )
        try expect(
            SmartDrawRecognizer.recognize(points: circle, duration: 0.8, zoomScale: 1)?.kind
                == .circle,
            "Expected a noisy closed round gesture to classify as a circle"
        )

        let ellipse = noisyEllipsePoints(
            center: CGPoint(x: 140, y: 120),
            radiusX: 82,
            radiusY: 39,
            rotation: 0.22,
            count: 64
        )
        try expect(
            SmartDrawRecognizer.recognize(points: ellipse, duration: 0.9, zoomScale: 1)?.kind
                == .ellipse,
            "Expected an elongated noisy round gesture to classify as an ellipse"
        )

        let square = noisyPolygonPoints(
            corners: [
                CGPoint(x: 40, y: 40),
                CGPoint(x: 140, y: 40),
                CGPoint(x: 140, y: 140),
                CGPoint(x: 40, y: 140)
            ],
            samplesPerEdge: 12
        )
        try expect(
            SmartDrawRecognizer.recognize(points: square, duration: 0.75, zoomScale: 1)?.kind
                == .square,
            "Expected square-vs-rectangle recognition to preserve a square"
        )

        let rectangle = noisyPolygonPoints(
            corners: [
                CGPoint(x: 30, y: 55),
                CGPoint(x: 190, y: 55),
                CGPoint(x: 190, y: 125),
                CGPoint(x: 30, y: 125)
            ],
            samplesPerEdge: 12
        )
        try expect(
            SmartDrawRecognizer.recognize(points: rectangle, duration: 0.8, zoomScale: 1)?.kind
                == .rectangle,
            "Expected square-vs-rectangle recognition to preserve an elongated rectangle"
        )

        let diamond = noisyPolygonPoints(
            corners: [
                CGPoint(x: 120, y: 28),
                CGPoint(x: 192, y: 100),
                CGPoint(x: 120, y: 172),
                CGPoint(x: 48, y: 100)
            ],
            samplesPerEdge: 12
        )
        guard let diamondCandidate = SmartDrawRecognizer.recognize(
            points: diamond,
            duration: 0.8,
            zoomScale: 1
        ) else {
            throw SelfTestError.failure("Expected a rotated square gesture to produce a candidate")
        }
        try expect(
            diamondCandidate.kind == .diamond,
            "Expected a rotated square to classify as a diamond"
        )
        guard case .shape(let diamondGeometry) = diamondCandidate.geometry else {
            throw SelfTestError.failure("Expected diamond recognition to return typed shape geometry")
        }
        try expect(
            diamondGeometry.kind == .diamond
                && diamondCandidate.rotation == 0
                && distance(
                    CGPoint(x: diamondGeometry.bounds.midX, y: diamondGeometry.bounds.midY),
                    CGPoint(x: 120, y: 100)
                ) < 4
                && abs(diamondGeometry.bounds.width - 144) < 10
                && abs(diamondGeometry.bounds.height - 144) < 10,
            "Expected diamond recognition to emit aligned cardinal vertices with zero rotation"
        )
    }

    private static func testSmartDrawRobustGeometryFitting() throws {
        let circleCenter = CGPoint(x: 145, y: 112)
        var circle = noisyEllipsePoints(
            center: circleCenter,
            radiusX: 62,
            radiusY: 58,
            rotation: 0.28,
            count: 84
        )
        circle.insert(CGPoint(x: 330, y: -75), at: 37)
        circle = [
            CGPoint(x: 224, y: 91),
            CGPoint(x: 216, y: 103)
        ] + circle + [
            CGPoint(x: 216, y: 121),
            CGPoint(x: 226, y: 132)
        ]
        guard let circleCandidate = SmartDrawRecognizer.recognize(
            points: circle,
            duration: 1.1,
            zoomScale: 1
        ), circleCandidate.kind == .circle,
        case .shape(let circleGeometry) = circleCandidate.geometry else {
            throw SelfTestError.failure(
                "Expected a near-circular overshooting gesture with one outlier to fit a circle"
            )
        }
        let fittedCircleCenter = CGPoint(
            x: circleGeometry.bounds.midX,
            y: circleGeometry.bounds.midY
        )
        try expect(
            abs(circleGeometry.bounds.width - circleGeometry.bounds.height) < 0.001
                && distance(fittedCircleCenter, circleCenter) < 5
                && abs(circleGeometry.bounds.width - 120) < 12,
            "Expected circle snapping to preserve the robust center and overall footprint, "
                + "got \(circleGeometry.bounds)"
        )

        let ellipseCenter = CGPoint(x: 210, y: 165)
        let ellipseRotation: CGFloat = 0.43
        var incompleteEllipse = imperfectEllipsePoints(
            center: ellipseCenter,
            radiusX: 92,
            radiusY: 43,
            rotation: ellipseRotation,
            startAngle: 0.24,
            endAngle: 2 * .pi - 0.42,
            count: 91,
            unevenPower: 1.45
        )
        incompleteEllipse.insert(CGPoint(x: 410, y: 350), at: 51)
        guard let ellipseCandidate = SmartDrawRecognizer.recognize(
            points: incompleteEllipse,
            duration: 1.25,
            zoomScale: 1
        ), ellipseCandidate.kind == .ellipse,
        case .shape(let ellipseGeometry) = ellipseCandidate.geometry else {
            throw SelfTestError.failure(
                "Expected an incomplete, unevenly sampled rotated ellipse to be recognized"
            )
        }
        let fittedEllipseCenter = CGPoint(
            x: ellipseGeometry.bounds.midX,
            y: ellipseGeometry.bounds.midY
        )
        try expect(
            distance(fittedEllipseCenter, ellipseCenter) < 7
                && abs(ellipseGeometry.bounds.width - 184) < 16
                && abs(ellipseGeometry.bounds.height - 86) < 13
                && angleDifferenceModulo(
                    ellipseCandidate.rotation,
                    ellipseRotation,
                    period: .pi
                ) < 0.12,
            "Expected robust ellipse center, radii, and orientation, got bounds "
                + "\(ellipseGeometry.bounds) at \(ellipseCandidate.rotation)"
        )

        let rectangleCenter = CGPoint(x: 190, y: 150)
        let rectangleRotation: CGFloat = 0.31
        let rectangleCorners = rotatedRectangleCorners(
            center: rectangleCenter,
            width: 174,
            height: 78,
            rotation: rectangleRotation
        )
        var rectangle = unevenPolygonPoints(
            corners: rectangleCorners,
            samplesPerEdge: [9, 24, 12, 19],
            close: true
        )
        rectangle.insert(CGPoint(x: -120, y: 380), at: 28)
        rectangle = [
            CGPoint(
                x: rectangleCorners[0].x - 7,
                y: rectangleCorners[0].y + 5
            )
        ] + rectangle + [
            CGPoint(
                x: rectangleCorners[0].x + 9,
                y: rectangleCorners[0].y - 6
            )
        ]
        guard let rectangleCandidate = SmartDrawRecognizer.recognize(
            points: rectangle,
            duration: 1.05,
            zoomScale: 1
        ), rectangleCandidate.kind == .rectangle,
        case .shape(let rectangleGeometry) = rectangleCandidate.geometry else {
            throw SelfTestError.failure(
                "Expected a noisy rotated rectangle with closure overshoot to be recognized"
            )
        }
        let fittedRectangleCenter = CGPoint(
            x: rectangleGeometry.bounds.midX,
            y: rectangleGeometry.bounds.midY
        )
        let expectedAxisWidth = abs(174 * cos(rectangleRotation))
            + abs(78 * sin(rectangleRotation))
        let expectedAxisHeight = abs(174 * sin(rectangleRotation))
            + abs(78 * cos(rectangleRotation))
        try expect(
            distance(fittedRectangleCenter, rectangleCenter) < 7
                && abs(rectangleGeometry.bounds.width - expectedAxisWidth) < 18
                && abs(rectangleGeometry.bounds.height - expectedAxisHeight) < 16
                && rectangleCandidate.rotation == 0,
            "Expected noisy rotated rectangle fitting to preserve its robust screen footprint "
                + "while emitting horizontal/vertical edges, got "
                + "\(rectangleGeometry.bounds) at \(rectangleCandidate.rotation)"
        )

        let nearSquareCorners = rotatedRectangleCorners(
            center: CGPoint(x: 120, y: 120),
            width: 106,
            height: 98,
            rotation: 0.19
        )
        guard let squareCandidate = SmartDrawRecognizer.recognize(
            points: unevenPolygonPoints(
                corners: nearSquareCorners,
                samplesPerEdge: [10, 17, 12, 20],
                close: false
            ),
            duration: 0.9,
            zoomScale: 1
        ), squareCandidate.kind == .square,
        case .shape(let squareGeometry) = squareCandidate.geometry else {
            throw SelfTestError.failure(
                "Expected a nearly equal-sided rotated box to snap to a square"
            )
        }
        try expect(
            abs(squareGeometry.bounds.width - squareGeometry.bounds.height) < 0.001
                && distance(
                    CGPoint(x: squareGeometry.bounds.midX, y: squareGeometry.bounds.midY),
                    CGPoint(x: 120, y: 120)
                ) < 6
                && squareCandidate.rotation == 0,
            "Expected near-square fitting to snap equal axis-aligned sides around the fitted center"
        )

        let robustDiamondCenter = CGPoint(x: 205, y: 138)
        let robustDiamond = unevenPolygonPoints(
            corners: [
                CGPoint(x: robustDiamondCenter.x, y: robustDiamondCenter.y - 74),
                CGPoint(x: robustDiamondCenter.x + 66, y: robustDiamondCenter.y),
                CGPoint(x: robustDiamondCenter.x, y: robustDiamondCenter.y + 74),
                CGPoint(x: robustDiamondCenter.x - 66, y: robustDiamondCenter.y)
            ],
            samplesPerEdge: [11, 23, 14, 19],
            close: true
        )
        guard let robustDiamondCandidate = SmartDrawRecognizer.recognize(
            points: robustDiamond,
            duration: 0.95,
            zoomScale: 1
        ), robustDiamondCandidate.kind == .diamond,
        case .shape(let robustDiamondGeometry) = robustDiamondCandidate.geometry else {
            throw SelfTestError.failure("Expected an uneven noisy diamond gesture to be recognized")
        }
        try expect(
            robustDiamondCandidate.rotation == 0
                && distance(
                    CGPoint(
                        x: robustDiamondGeometry.bounds.midX,
                        y: robustDiamondGeometry.bounds.midY
                    ),
                    robustDiamondCenter
                ) < 6
                && abs(robustDiamondGeometry.bounds.width - 132) < 14
                && abs(robustDiamondGeometry.bounds.height - 148) < 14,
            "Expected robust diamond fitting to preserve cardinal footprint with zero rotation"
        )

        let doubleLoop = noisyEllipsePoints(
            center: CGPoint(x: 120, y: 100),
            radiusX: 58,
            radiusY: 56,
            rotation: 0,
            count: 52
        )
        try expect(
            SmartDrawRecognizer.recognize(
                points: doubleLoop + Array(doubleLoop.dropFirst()),
                duration: 1.8,
                zoomScale: 1
            ) == nil,
            "Expected an overtraced double-loop scribble to remain freehand"
        )
    }

    private static func testSmartDrawArrowAndNegativeRecognition() throws {
        let tail = CGPoint(x: 30, y: 110)
        let tip = CGPoint(x: 205, y: 62)
        let arrow = interpolatedPoints(from: tail, to: tip, count: 18)
            + interpolatedPoints(
                from: tip,
                to: CGPoint(x: 166, y: 50),
                count: 6,
                droppingFirst: true
            )
            + interpolatedPoints(
                from: CGPoint(x: 166, y: 50),
                to: tip,
                count: 6,
                droppingFirst: true
            )
            + interpolatedPoints(
                from: tip,
                to: CGPoint(x: 180, y: 94),
                count: 6,
                droppingFirst: true
            )
        guard let arrowCandidate = SmartDrawRecognizer.recognize(
            points: arrow,
            duration: 0.7,
            zoomScale: 1
        ) else {
            throw SelfTestError.failure("Expected a shaft-and-head gesture to classify as an arrow")
        }
        try expect(arrowCandidate.kind == .arrow, "Expected arrow candidate kind")
        guard case .linear(let arrowGeometry) = arrowCandidate.geometry else {
            throw SelfTestError.failure("Expected arrow recognition to return linear geometry")
        }
        try expect(
            arrowGeometry.points.first == tail
                && distance(arrowGeometry.points.last ?? .zero, tip) < 2
                && arrowGeometry.startArrowhead == .none
                && arrowGeometry.endArrowhead == .arrow,
            "Expected arrow direction and head endpoint to follow the drawn shaft"
        )
        guard let reversedArrow = SmartDrawRecognizer.recognize(
            points: Array(arrow.reversed()),
            duration: 0.7,
            zoomScale: 1
        ), case .linear(let reversedGeometry) = reversedArrow.geometry else {
            throw SelfTestError.failure("Expected a head-first arrow gesture to be recognized")
        }
        try expect(
            reversedArrow.kind == .arrow
                && distance(reversedGeometry.points.first ?? .zero, tail) < 2
                && distance(reversedGeometry.points.last ?? .zero, tip) < 2
                && reversedGeometry.endArrowhead == .arrow,
            "Expected arrow direction detection to find the converging head at either stroke endpoint"
        )

        let scribble = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: 180, y: 160),
            CGPoint(x: 30, y: 150),
            CGPoint(x: 170, y: 30),
            CGPoint(x: 45, y: 35),
            CGPoint(x: 165, y: 145),
            CGPoint(x: 25, y: 90),
            CGPoint(x: 175, y: 92),
            CGPoint(x: 22, y: 22)
        ]
        try expect(
            SmartDrawRecognizer.recognize(points: scribble, duration: 1.4, zoomScale: 1) == nil,
            "Expected an intersecting scribble to be rejected"
        )
        try expect(
            SmartDrawRecognizer.recognize(
                points: noisyEllipsePoints(
                    center: CGPoint(x: 5, y: 5),
                    radiusX: 4,
                    radiusY: 4,
                    rotation: 0,
                    count: 24
                ),
                duration: 0.4,
                zoomScale: 1
            ) == nil,
            "Expected tiny gestures to be rejected at the current zoom"
        )
        let zoomScaledCircle = (0..<32).map { index in
            let angle = CGFloat(index) * 2 * .pi / 31
            return CGPoint(
                x: 30 + cos(angle) * 10,
                y: 30 + sin(angle) * 10
            )
        }
        let zoomOneCandidate = SmartDrawRecognizer.recognize(
            points: zoomScaledCircle,
            duration: 0.45,
            zoomScale: 1
        )
        let zoomTwoCandidate = SmartDrawRecognizer.recognize(
            points: zoomScaledCircle,
            duration: 0.45,
            zoomScale: 2
        )
        try expect(
            zoomOneCandidate == nil && zoomTwoCandidate?.kind == .circle,
            "Expected minimum recognition distances to scale with the current zoom "
                + "(1x: \(String(describing: zoomOneCandidate)), "
                + "2x: \(String(describing: zoomTwoCandidate)))"
        )
        try expect(
            SmartDrawRecognizer.recognize(
                points: scribble,
                duration: 6,
                zoomScale: 1
            ) == nil,
            "Expected slow scribbles to be rejected"
        )

        let noisyTail = CGPoint(x: 24, y: 158)
        let noisyTip = CGPoint(x: 218, y: 68)
        let shaftVector = CGPoint(
            x: noisyTip.x - noisyTail.x,
            y: noisyTip.y - noisyTail.y
        )
        let shaftLength = hypot(shaftVector.x, shaftVector.y)
        let shaftNormal = CGPoint(
            x: -shaftVector.y / shaftLength,
            y: shaftVector.x / shaftLength
        )
        let noisyShaft = (0..<31).map { index -> CGPoint in
            let fraction = CGFloat(index) / 30
            let noise = sin(CGFloat(index) * 1.19) * 1.4
            return CGPoint(
                x: noisyTail.x + shaftVector.x * fraction + shaftNormal.x * noise,
                y: noisyTail.y + shaftVector.y * fraction + shaftNormal.y * noise
            )
        }
        let noisyArrow = noisyShaft
            + interpolatedPoints(
                from: noisyTip,
                to: CGPoint(x: 169, y: 55),
                count: 8,
                droppingFirst: true
            )
            + interpolatedPoints(
                from: CGPoint(x: 169, y: 55),
                to: CGPoint(x: 217, y: 69),
                count: 7,
                droppingFirst: true
            )
            + interpolatedPoints(
                from: CGPoint(x: 217, y: 69),
                to: CGPoint(x: 183, y: 113),
                count: 9,
                droppingFirst: true
            )
        guard let noisyArrowCandidate = SmartDrawRecognizer.recognize(
            points: noisyArrow,
            duration: 1.0,
            zoomScale: 1
        ), noisyArrowCandidate.kind == .arrow,
        case .linear(let noisyArrowGeometry) = noisyArrowCandidate.geometry else {
            throw SelfTestError.failure(
                "Expected a noisy, unevenly sampled shaft-and-head gesture to fit an arrow"
            )
        }
        try expect(
            distance(noisyArrowGeometry.points[0], noisyTail) < 5
                && distance(noisyArrowGeometry.points[1], noisyTip) < 5,
            "Expected arrow fitting to preserve the intended shaft endpoints, got "
                + "\(noisyArrowGeometry.points)"
        )
    }

    private static func testSmartDrawRecognitionBudget() async throws {
        try expect(
            SmartDrawRecognitionBudget.shouldRecognizePreview(
                lastRecognitionTime: nil,
                lastRecognizedSampleCount: 0,
                timestamp: 10,
                sampleCount: SmartDrawRecognitionBudget.minimumPointCount
            ),
            "Expected the first viable Smart Draw preview analysis to run"
        )
        try expect(
            !SmartDrawRecognitionBudget.shouldRecognizePreview(
                lastRecognitionTime: 10,
                lastRecognizedSampleCount: 6,
                timestamp: 10 + SmartDrawRecognitionBudget.minimumPreviewInterval / 2,
                sampleCount: 12
            )
                && SmartDrawRecognitionBudget.shouldRecognizePreview(
                    lastRecognitionTime: 10,
                    lastRecognizedSampleCount: 6,
                    timestamp: 10 + SmartDrawRecognitionBudget.minimumPreviewInterval * 2,
                    sampleCount: 14
                )
                && !SmartDrawRecognitionBudget.shouldRecognizePreview(
                    lastRecognitionTime: 10,
                    lastRecognizedSampleCount: 12,
                    timestamp: 11,
                    sampleCount: 12
                ),
            "Expected drag recognition to be throttled by deterministic timestamps "
                + "and new-sample progress"
        )
        try expect(
            SmartDrawRecognitionBudget.minimumPreviewInterval >= 1.0 / 30.0
                && SmartDrawRecognitionBudget.minimumPreviewInterval <= 1.0 / 20.0
                && SmartDrawRecognitionBudget.minimumPointCount <= 5
                && SmartDrawRecognitionBudget.minimumAdditionalPointCount == 4,
            "Expected an early bounded 20-30 Hz Smart Draw preview cadence"
        )

        let denseCircle = noisyEllipsePoints(
            center: CGPoint(x: 160, y: 140),
            radiusX: 90,
            radiusY: 88,
            rotation: 0.08,
            count: 12_000
        )
        let prepared = SmartDrawRecognizer.preparedPointsForTesting(
            denseCircle,
            zoomScale: 1
        )
        try expect(
            prepared.count <= SmartDrawRecognitionBudget.maximumInputPointCount
                && prepared.first == denseCircle.first
                && prepared.last == denseCircle.last,
            "Expected Smart Draw input to be deterministically resampled before "
                + "higher-cost recognition passes"
        )
        let controllerPrepared = AnnotationController.boundedSmartDrawLocations(
            from: denseCircle.map {
                AnnotationPointSample(location: $0, pressure: nil)
            },
            maximumCount: SmartDrawRecognitionBudget.previewInputPointCount
        )
        try expect(
            controllerPrepared.count
                == SmartDrawRecognitionBudget.previewInputPointCount
                && controllerPrepared.first == denseCircle.first
                && controllerPrepared.last == denseCircle.last,
            "Expected controller-side Smart Draw preparation to cap each recognition frame before scanning"
        )
        let denseCandidate = SmartDrawRecognizer.recognize(
            points: denseCircle,
            duration: 1,
            zoomScale: 1
        )
        let preparedCandidate = SmartDrawRecognizer.recognize(
            points: prepared,
            duration: 1,
            zoomScale: 1
        )
        try expect(
            denseCandidate == preparedCandidate && denseCandidate != nil,
            "Expected bounded Smart Draw input to preserve deterministic recognition output"
        )

        let queueController = AnnotationController()
        queueController.setSmartDrawEnabled(true)
        let queuePoints = noisyEllipsePoints(
            center: CGPoint(x: 120, y: 100),
            radiusX: 60,
            radiusY: 58,
            rotation: 0.05,
            count: 80
        )
        queueController.begin(
            at: queuePoints[0],
            pressure: 0.9,
            timestamp: 20,
            zoomScale: 1
        )
        for (index, point) in queuePoints.dropFirst().enumerated() {
            queueController.update(
                at: point,
                pressure: 0.9,
                timestamp: 20 + Double(index + 1) * 0.04,
                zoomScale: 1
            )
        }
        try expect(
            queueController.smartDrawRecognitionSubmissionCountForTesting == 1
                && queueController.hasPendingSmartDrawRecognitionForTesting
                && queueController
                    .smartDrawMaximumConcurrentRecognitionCountForTesting == 1,
            "Expected one in-flight recognition with one replaceable latest pending snapshot"
        )
        for _ in 0..<500
            where queueController.hasPendingSmartDrawRecognitionForTesting {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(1))
        }
        try expect(
            !queueController.hasPendingSmartDrawRecognitionForTesting
                && queueController.smartDrawRecognitionSubmissionCountForTesting == 2
                && queueController
                    .smartDrawMaximumConcurrentRecognitionCountForTesting == 1
                && queueController.smartDrawRejectedRecognitionCountForTesting == 0,
            "Expected the in-flight result to deliver before the latest pending snapshot"
        )
        queueController.clear()
    }

    private static func testSmartDrawPreviewStabilityAndHistory() throws {
        let geometry = AnnotationElementGeometry.shape(
            AnnotationShapeGeometry(
                kind: .ellipse,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 100, y: 100)
            )
        )
        let circle = SmartDrawCandidate(
            kind: .circle,
            geometry: geometry,
            rotation: 0,
            confidence: SmartDrawStabilityTracker.previewThreshold + 0.01
        )
        let ellipse = SmartDrawCandidate(
            kind: .ellipse,
            geometry: geometry,
            rotation: 0,
            confidence: SmartDrawStabilityTracker.previewThreshold + 0.02
        )
        var immediateTracker = SmartDrawStabilityTracker()
        immediateTracker.update(
            SmartDrawCandidate(
                kind: .circle,
                geometry: geometry,
                rotation: 0,
                confidence: SmartDrawStabilityTracker.immediatePreviewThreshold
            )
        )
        try expect(
            immediateTracker.previewCandidate?.kind == .circle,
            "Expected a high-confidence candidate to preview on its first useful update"
        )
        var tracker = SmartDrawStabilityTracker()
        tracker.update(circle)
        try expect(
            tracker.previewCandidate == nil
                && tracker.displayCandidate?.kind == .circle,
            "Expected a faint provisional candidate before stable preview confirmation"
        )
        tracker.update(circle)
        try expect(
            tracker.previewCandidate?.kind == .circle,
            "Expected a stable candidate to appear at the preview threshold"
        )
        let shiftedCircle = SmartDrawCandidate(
            kind: .circle,
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .ellipse,
                    start: CGPoint(x: 40, y: 20),
                    end: CGPoint(x: 140, y: 120)
                )
            ),
            rotation: 0,
            confidence: SmartDrawStabilityTracker.immediatePreviewThreshold
        )
        tracker.update(shiftedCircle)
        guard case .shape(let smoothedPreviewGeometry) =
            tracker.previewCandidate?.geometry else {
            throw SelfTestError.failure("Expected a smoothed Smart Draw preview geometry")
        }
        try expect(
            smoothedPreviewGeometry.bounds.minX > 0
                && smoothedPreviewGeometry.bounds.minX < 40
                && smoothedPreviewGeometry.bounds.minY > 0
                && smoothedPreviewGeometry.bounds.minY < 20,
            "Expected same-class preview geometry to move smoothly instead of jumping"
        )
        tracker.update(ellipse)
        try expect(
            tracker.previewCandidate?.kind == .circle,
            "Expected one competing update not to flicker the preview class"
        )
        let belowCommit = SmartDrawCandidate(
            kind: .circle,
            geometry: geometry,
            rotation: 0,
            confidence: SmartDrawStabilityTracker.mediumConfidenceCommitThreshold - 0.01
        )
        try expect(
            tracker.commitCandidate(final: belowCommit) == nil,
            "Expected commit to reject candidates below the medium-confidence floor"
        )
        let mediumConfidenceFinal = SmartDrawCandidate(
            kind: .circle,
            geometry: geometry,
            rotation: 0,
            confidence: SmartDrawStabilityTracker.mediumConfidenceCommitThreshold
        )
        try expect(
            tracker.commitCandidate(final: mediumConfidenceFinal)?.kind == .circle,
            "Expected a medium-confidence final fit to commit after a stable same-class preview"
        )
        let highConfidenceFinal = SmartDrawCandidate(
            kind: .circle,
            geometry: geometry,
            rotation: 0,
            confidence: SmartDrawStabilityTracker.highConfidenceCommitThreshold
        )
        let finalOnlyTracker = SmartDrawStabilityTracker()
        try expect(
            finalOnlyTracker.commitCandidate(final: highConfidenceFinal)?.kind == .circle,
            "Expected a throttled stroke to commit from its deterministic final analysis "
                + "even if no preview interval elapsed"
        )

        let controller = AnnotationController()
        controller.setSmartDrawEnabled(true)
        controller.currentStyle.pressureEnabled = true
        controller.currentStyle.sloppiness = .cartoonist
        let points = noisyEllipsePoints(
            center: CGPoint(x: 110, y: 95),
            radiusX: 55,
            radiusY: 54,
            rotation: 0,
            count: 64
        )
        controller.begin(
            at: points[0],
            pressure: 0.25,
            timestamp: 10,
            zoomScale: 2
        )
        try expect(
            controller.smartDrawStatusText == "Analyzing stroke...",
            "Expected optional inspector feedback while Smart Draw is evaluating a stroke"
        )
        for (index, point) in points.dropFirst().enumerated() {
            controller.update(
                at: point,
                pressure: 0.25 + CGFloat(index) / 100,
                timestamp: 10 + Double(index + 1) * 0.01,
                zoomScale: 2
            )
        }
        controller.update(
            at: points[0],
            pressure: 0.9,
            timestamp: 10.7,
            zoomScale: 2
        )
        try expect(
            controller.smartDrawRecognitionSubmissionCountForTesting > 0
                && controller.elementSnapshot.isEmpty,
            "Expected preview recognition to run off-main while remaining absent from scene history"
        )
        try expect(
            controller.smartDrawStatusText == "Analyzing stroke..."
                || controller.smartDrawStatusText?.hasPrefix("Circle · ") == true,
            "Expected inspector feedback while asynchronous preview recognition is pending or ready"
        )
        controller.end(
            at: points[0],
            pressure: 1,
            timestamp: 10.72,
            zoomScale: 2
        )
        try expect(
            controller.elementSnapshot.count == 1
                && controller.elementSnapshot[0].style.sloppiness == .cartoonist
                && controller.elementSnapshot[0].metadata.wasSmartDrawRecognized,
            "Expected one committed smart-draw element with the current sloppiness"
        )
        guard case .shape(let committedShape) = controller.elementSnapshot[0].geometry else {
            throw SelfTestError.failure("Expected the raw pen stroke to be replaced by a typed shape")
        }
        try expect(
            committedShape.kind == .ellipse,
            "Expected smart circle geometry to use the native ellipse shape family"
        )
        controller.currentTool = .select
        let selectionPoint = CGPoint(
            x: committedShape.bounds.minX,
            y: committedShape.bounds.midY
        )
        _ = controller.beginSelectionInteraction(
            at: selectionPoint,
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        controller.endSelectionInteraction(at: selectionPoint, modifiers: [])
        let recognizedState = DrawingToolbarState(annotationController: controller)
        try expect(
            recognizedState.smartDrawStatusText == nil
                && !recognizedState.supportsSmartDraw
                && recognizedState.visibleInspectorSections == [
                    .strokeColor,
                    .background,
                    .strokeWidth,
                    .strokeStyle,
                    .sloppiness,
                    .opacity,
                    .layers
                ],
            "Expected a selected Smart Draw result to use only its recognized shape matrix"
        )
        controller.undo()
        try expect(
            controller.elementSnapshot.isEmpty,
            "Expected recognized replacement to undo in one history step"
        )

        let previewParityController = AnnotationController()
        previewParityController.setSmartDrawEnabled(true)
        let previewParityPoints = noisyPolygonPoints(
            corners: rotatedRectangleCorners(
                center: CGPoint(x: 180, y: 140),
                width: 164,
                height: 76,
                rotation: 0.27
            ),
            samplesPerEdge: 16
        )
        previewParityController.begin(
            at: previewParityPoints[0],
            pressure: nil,
            timestamp: 40,
            zoomScale: 1
        )
        for (index, point) in previewParityPoints.dropFirst().enumerated() {
            previewParityController.update(
                at: point,
                timestamp: 40 + Double(index + 1) * 0.02,
                zoomScale: 1
            )
        }
        previewParityController.end(
            at: previewParityPoints[previewParityPoints.count - 1],
            timestamp: 41.5,
            zoomScale: 1
        )
        guard let alignedCommit = previewParityController.elementSnapshot.first,
              case .shape(let alignedCommitShape) = alignedCommit.geometry else {
            throw SelfTestError.failure("Expected the Smart Draw rectangle ghost to commit")
        }
        try expect(
            alignedCommitShape.kind == .rectangle
                && alignedCommit.metadata.rotation == 0,
            "Expected final Smart Draw geometry to preserve the aligned rectangle contract"
        )

        let fallback = AnnotationController()
        fallback.setSmartDrawEnabled(true)
        fallback.currentStyle.pressureEnabled = true
        fallback.begin(at: CGPoint(x: 10, y: 10), pressure: 0.2, timestamp: 20)
        fallback.update(at: CGPoint(x: 35, y: 24), pressure: 0.5, timestamp: 20.1)
        fallback.update(at: CGPoint(x: 62, y: 12), pressure: 0.8, timestamp: 20.2)
        fallback.end(at: CGPoint(x: 85, y: 28), pressure: 1, timestamp: 20.3)
        guard case .freehand(let fallbackStroke) = fallback.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure("Expected an ambiguous gesture to keep the pen stroke")
        }
        let fallbackPressures = fallbackStroke.samples.compactMap(\.pressure)
        try expect(
            fallbackPressures.isEmpty
                && fallbackStroke.samples.count > 4,
            "Expected Smart Draw fallback ink to remain fixed-pressure"
        )
        fallback.setSmartDrawEnabled(false)
        try expect(
            fallback.currentStyle.pressureMode == .tablet,
            "Expected Smart Draw fallback to restore the saved Pen pressure mode"
        )

        let finalOnlyController = AnnotationController()
        finalOnlyController.setSmartDrawEnabled(true)
        let finalOnlyPoints = noisyEllipsePoints(
            center: CGPoint(x: 150, y: 130),
            radiusX: 66,
            radiusY: 64,
            rotation: 0,
            count: 48
        )
        finalOnlyController.begin(
            at: finalOnlyPoints[0],
            pressure: nil,
            timestamp: 30,
            zoomScale: 1
        )
        for point in finalOnlyPoints.dropFirst().dropLast() {
            finalOnlyController.update(
                at: point,
                timestamp: 30,
                zoomScale: 1
            )
        }
        try expect(
            finalOnlyController.smartDrawPreviewElementSnapshot == nil,
            "Expected preview throttling to be independent from final recognition"
        )
        finalOnlyController.end(
            at: finalOnlyPoints[finalOnlyPoints.count - 1],
            timestamp: 30,
            zoomScale: 1
        )
        guard case .shape = finalOnlyController.elementSnapshot.first?.geometry else {
            throw SelfTestError.failure(
                "Expected pointer release to run a full-quality fit even without a preview"
            )
        }
    }

    private static func testTypingAnnotations() throws {
        let controller = AnnotationController()
        controller.setInsertionPoint(CGPoint(x: 20, y: 30))

        controller.insertText("H")
        controller.insertText("i")

        try expect(controller.annotationSnapshot.count == 1, "Expected one text annotation")
        try expect(controller.annotationSnapshot[0].tool == .text, "Expected text annotation tool")
        try expect(controller.annotationSnapshot[0].points == [CGPoint(x: 20, y: 30)], "Unexpected text insertion point")
        try expect(controller.annotationSnapshot[0].text == "Hi", "Expected text to append")

        controller.deleteBackward()

        try expect(controller.annotationSnapshot[0].text == "H", "Expected deleteBackward to remove one character")
        controller.undo()
        try expect(controller.annotationSnapshot.isEmpty, "Expected undo to remove the active text annotation")
        controller.redo()
        try expect(controller.annotationSnapshot[0].text == "H", "Expected redo to restore the latest typed text")
        let textPixels = try renderPixels(
            elements: controller.elementSnapshot,
            renderer: AnnotationRenderer()
        )
        guard let glyphBounds = paintedBounds(
            textPixels,
            width: 96,
            height: 96
        ) else {
            throw SelfTestError.failure("Expected native text glyph ink")
        }
        try expect(
            glyphBounds.minY > 30 && glyphBounds.minY < 45,
            "Expected native glyph ink to keep its normal baseline inset "
                + "separate from the exact text origin"
        )
    }

    private static func testAnnotationRenderingTouchesPixels() throws {
        let width = 64
        let height = 64
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SelfTestError.failure("Could not create render test context")
        }

        let controller = AnnotationController()
        controller.currentStyle = AnnotationStyle(color: .red, rootWidth: 8, alpha: 1)
        controller.begin(at: CGPoint(x: 8, y: 32))
        controller.update(at: CGPoint(x: 56, y: 32))
        controller.end(at: CGPoint(x: 56, y: 32))
        controller.render(in: context, bounds: CGRect(x: 0, y: 0, width: width, height: height))

        let touchedPixel = pixels.chunked(into: bytesPerPixel).contains { pixel in
            pixel[0] > 0 || pixel[1] > 0 || pixel[2] > 0 || pixel[3] > 0
        }

        try expect(touchedPixel, "Expected annotation rendering to modify offscreen bitmap pixels")
    }

    private static func testAnnotationRenderingStylesAndFamilies() throws {
        let renderer = AnnotationRenderer()

        var shapeStyle = AnnotationStyle(
            color: .blue,
            rootWidth: 4,
            alpha: 1,
            fillColor: .rgba(red: 1, green: 0, blue: 0, alpha: 1),
            fillStyle: .solid,
            sloppiness: .architect
        )
        shapeStyle.strokeColor = .rgba(red: 0, green: 0, blue: 1, alpha: 1)
        let rectangle = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 8, y: 8),
                    end: CGPoint(x: 32, y: 32)
                )
            ),
            style: shapeStyle
        )
        let rectanglePixels = try renderPixels(elements: [rectangle], renderer: renderer)
        let rectangleCenter = pixel(rectanglePixels, width: 96, x: 20, y: 20)
        let rectangleBorder = pixel(rectanglePixels, width: 96, x: 8, y: 20)
        try expect(
            rectangleCenter.red > rectangleCenter.blue && rectangleBorder.blue > rectangleBorder.red,
            "Expected shape fill and stroke colors to render independently; center \(rectangleCenter), border \(rectangleBorder), painted \(String(describing: paintedBounds(rectanglePixels, width: 96, height: 96)))"
        )

        let diamond = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .diamond,
                    start: CGPoint(x: 40, y: 8),
                    end: CGPoint(x: 72, y: 40)
                )
            ),
            style: shapeStyle
        )
        let ellipse = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .ellipse,
                    start: CGPoint(x: 8, y: 48),
                    end: CGPoint(x: 40, y: 80)
                )
            ),
            style: shapeStyle
        )
        let shapePixels = try renderPixels(elements: [diamond, ellipse], renderer: renderer)
        try expect(
            alpha(shapePixels, width: 96, x: 56, y: 24) > 0
                && alpha(shapePixels, width: 96, x: 24, y: 64) > 0
                && alpha(shapePixels, width: 96, x: 40, y: 8) == 0,
            "Expected diamond and ellipse paths to render their distinct filled geometry"
        )

        var dashedStyle = AnnotationStyle(color: .red, rootWidth: 4, alpha: 1)
        dashedStyle.sloppiness = .architect
        dashedStyle.strokePattern = .dashed
        let dashed = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 8, y: 16), CGPoint(x: 80, y: 16)],
            style: dashedStyle
        )
        var dottedStyle = dashedStyle
        dottedStyle.strokePattern = .dotted
        let dotted = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 8, y: 32), CGPoint(x: 80, y: 32)],
            style: dottedStyle
        )
        let patternPixels = try renderPixels(elements: [dashed, dotted], renderer: renderer)
        let dashedPaintedCount = (8..<81).filter {
            alpha(patternPixels, width: 96, x: $0, y: 16) > 0
        }.count
        try expect(
            dashedPaintedCount > 0
                && dashedPaintedCount < 73
                && paintedRuns(patternPixels, width: 96, y: 16, xRange: 8..<81) >= 2,
            "Expected dashed strokes to contain deterministic painted and empty runs"
        )
        try expect(
            paintedRuns(patternPixels, width: 96, y: 32, xRange: 8..<81) >= 5,
            "Expected dotted strokes to render repeated round marks"
        )

        let pen = AnnotationElement.legacy(
            tool: .pen,
            points: [
                CGPoint(x: 8, y: 48),
                CGPoint(x: 28, y: 42),
                CGPoint(x: 48, y: 52),
                CGPoint(x: 80, y: 48)
            ],
            style: AnnotationStyle(
                color: .green,
                rootWidth: 5,
                alpha: 1,
                sloppiness: .architect
            )
        )
        let arrow = AnnotationElement.legacy(
            tool: .arrow,
            points: [CGPoint(x: 80, y: 72), CGPoint(x: 12, y: 72)],
            style: AnnotationStyle(
                color: .blue,
                rootWidth: 4,
                alpha: 1,
                sloppiness: .architect
            )
        )
        let linearPixels = try renderPixels(elements: [pen, arrow], renderer: renderer)
        try expect(
            alpha(linearPixels, width: 96, x: 40, y: 48) > 0
                && alpha(linearPixels, width: 96, x: 78, y: 72) > 0
                && alpha(linearPixels, width: 96, x: 36, y: 72) > 0,
            "Expected smoothed pen and legacy start-anchored arrow output"
        )

        var translucentStyle = AnnotationStyle(color: .orange, rootWidth: 2, alpha: 0.25)
        translucentStyle.fillStyle = .solid
        let translucent = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 8, y: 8),
                    end: CGPoint(x: 32, y: 32)
                )
            ),
            style: translucentStyle
        )
        let translucentPixels = try renderPixels(elements: [translucent], renderer: renderer)
        let translucentAlpha = alpha(translucentPixels, width: 96, x: 20, y: 20)
        try expect(
            (55...70).contains(translucentAlpha),
            "Expected style opacity to apply to filled geometry, got alpha \(translucentAlpha)"
        )

        var rotatedStyle = AnnotationStyle(color: .pink, rootWidth: 2, alpha: 1)
        rotatedStyle.fillStyle = .solid
        var rotated = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 20, y: 28),
                    end: CGPoint(x: 44, y: 36)
                )
            ),
            style: rotatedStyle
        )
        rotated.metadata.rotation = .pi / 2
        let rotatedPixels = try renderPixels(elements: [rotated], renderer: renderer)
        try expect(
            alpha(rotatedPixels, width: 96, x: 32, y: 22) > 0
                && alpha(rotatedPixels, width: 96, x: 22, y: 32) == 0,
            "Expected renderer transforms to rotate shape pixels around their center"
        )

        var highlighterStyle = AnnotationStyle(color: .yellow, rootWidth: 12, alpha: 1)
        highlighterStyle.sloppiness = .architect
        highlighterStyle.pressureEnabled = false
        let highlight = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(location: CGPoint(x: 8, y: 48), pressure: nil),
                        AnnotationPointSample(location: CGPoint(x: 80, y: 48), pressure: nil)
                    ],
                    isHighlighter: true
                )
            ),
            style: highlighterStyle
        )
        let highlightPixels = try renderPixels(elements: [highlight, highlight], renderer: renderer)
        let highlightAlpha = alpha(highlightPixels, width: 96, x: 40, y: 48)
        try expect(
            (120...135).contains(highlightAlpha),
            "Expected overlapping highlighter output to composite once, got alpha \(highlightAlpha)"
        )

        var pressureStyle = AnnotationStyle(color: .black, rootWidth: 12, alpha: 1)
        pressureStyle.sloppiness = .architect
        pressureStyle.pressureEnabled = true
        let pressureStroke = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(location: CGPoint(x: 16, y: 72), pressure: 0.2),
                        AnnotationPointSample(location: CGPoint(x: 80, y: 72), pressure: 1)
                    ],
                    isHighlighter: false
                )
            ),
            style: pressureStyle
        )
        let pressurePixels = try renderPixels(elements: [pressureStroke], renderer: renderer)
        try expect(
            paintedVerticalSpan(pressurePixels, width: 96, height: 96, x: 75)
                > paintedVerticalSpan(pressurePixels, width: 96, height: 96, x: 20),
            "Expected pressure samples to widen the rendered freehand stroke"
        )

        let text = AnnotationElement(
            geometry: .text(
                AnnotationTextGeometry(
                    origin: CGPoint(x: 8, y: 8),
                    bounds: nil,
                    text: "T",
                    fontSize: 28,
                    fontName: "",
                    alignment: .left,
                    isEditing: false
                )
            ),
            style: AnnotationStyle(color: .white, rootWidth: 2, alpha: 1)
        )
        let textPixels = try renderPixels(elements: [text], renderer: renderer)
        try expect(
            textPixels.enumerated().contains { index, value in index % 4 == 3 && value > 0 },
            "Expected text rendering to modify the offscreen bitmap"
        )

        let decorationPixels = try renderPixels(
            elements: [],
            renderer: renderer,
            decorationElements: [rectangle],
            selectedElementIDs: [rectangle.id],
            zoomScale: 2
        )
        try expect(
            decorationPixels.enumerated().contains { index, value in index % 4 == 3 && value > 0 },
            "Expected selection decoration primitives to render independently from scene content"
        )
    }

    private static func testFreehandRenderingQualityAndHighlighterPreview() throws {
        let renderer = AnnotationRenderer()
        var markerStyle = AnnotationStyle(
            color: .highlighterYellow,
            rootWidth: 20,
            alpha: 1
        )
        markerStyle.strokePattern = .dotted
        markerStyle.sloppiness = .cartoonist
        markerStyle.pressureMode = .simulated
        let markerStamp = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(
                            location: CGPoint(x: 48, y: 32),
                            pressure: 0.2
                        )
                    ],
                    isHighlighter: true
                )
            ),
            style: markerStyle
        )
        let stampPixels = try renderPixels(
            elements: [markerStamp],
            renderer: renderer,
            width: 96,
            height: 64
        )
        guard let stampBounds = paintedBounds(
            stampPixels,
            width: 96,
            height: 64
        ) else {
            throw SelfTestError.failure("Expected a Highlighter marker stamp")
        }
        let markerLine = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(location: CGPoint(x: 20, y: 32), pressure: 0.2),
                        AnnotationPointSample(location: CGPoint(x: 76, y: 32), pressure: 1)
                    ],
                    isHighlighter: true
                )
            ),
            style: markerStyle
        )
        let markerPixels = try renderPixels(
            elements: [markerLine],
            renderer: renderer,
            width: 96,
            height: 64
        )
        try expect(
            stampBounds.height > stampBounds.width + 4
                && AnnotationHighlighterGeometry.stampRect(
                    center: .zero,
                    strokeWidth: 20
                ).width < 20
                && alpha(markerPixels, width: 96, x: 18, y: 32) == 0
                && alpha(markerPixels, width: 96, x: 20, y: 32) > 0
                && alpha(markerPixels, width: 96, x: 75, y: 32) > 0
                && alpha(markerPixels, width: 96, x: 78, y: 32) == 0,
            "Expected a rectangular stamp and clean flat/butt Highlighter nib"
        )

        var pressureStyle = AnnotationStyle(color: .blue, rootWidth: 12, alpha: 1)
        pressureStyle.sloppiness = .architect
        pressureStyle.pressureMode = .tablet
        pressureStyle.smoothingEnabled = true
        let pressureSamples = (0...20).map { index in
            AnnotationPointSample(
                location: CGPoint(x: 12 + CGFloat(index) * 3.5, y: 28),
                pressure: 0.2 + CGFloat(index) * 0.04
            )
        }
        let pressureStroke = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: pressureSamples,
                    isHighlighter: false
                )
            ),
            style: pressureStyle
        )
        let pressurePixels = try renderPixels(
            elements: [pressureStroke],
            renderer: renderer,
            width: 96,
            height: 64
        )
        let spans = stride(from: 14, through: 80, by: 2).map {
            paintedVerticalSpan(
                pressurePixels,
                width: 96,
                height: 64,
                x: $0
            )
        }
        try expect(
            spans.allSatisfy { $0 > 0 }
                && zip(spans, spans.dropFirst()).allSatisfy {
                    abs($1 - $0) <= 4
                },
            "Expected interpolated variable-width outlines without gaps, pinching, or spikes"
        )

        let penController = AnnotationController()
        penController.currentStyle.sloppiness = .architect
        penController.currentStyle.strokeWidth = 6
        penController.begin(at: CGPoint(x: 8, y: 32))
        for index in 1...85 {
            penController.update(
                at: CGPoint(
                    x: 8 + CGFloat(index) * 1.25,
                    y: 32 + sin(CGFloat(index) * 0.72) * 0.8
                ),
                zoomScale: 1
            )
        }
        penController.end(at: CGPoint(x: 116, y: 32), zoomScale: 1)
        let penPixels = try renderPixels(
            elements: penController.elementSnapshot,
            renderer: renderer,
            width: 128,
            height: 64
        )
        try expect(
            stride(from: 10, through: 114, by: 2).allSatisfy {
                hasPaintedPixel(
                    penPixels,
                    width: 128,
                    height: 64,
                    near: CGPoint(x: $0, y: 32),
                    radius: 4
                )
            },
            "Expected a fluid smoothed pen centerline with no rendered gaps"
        )

        func cachedCenterColor(of view: NSView) throws -> NSColor {
            view.layoutSubtreeIfNeeded()
            guard let representation = view.bitmapImageRepForCachingDisplay(
                in: view.bounds
            ) else {
                throw SelfTestError.failure("Could not cache inspector color preview")
            }
            view.cacheDisplay(in: view.bounds, to: representation)
            guard let color = representation.colorAt(
                x: representation.pixelsWide / 2,
                y: representation.pixelsHigh / 2
            )?.usingColorSpace(.sRGB) else {
                throw SelfTestError.failure("Could not sample inspector color preview")
            }
            return color
        }

        func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
            let left = lhs.usingColorSpace(.sRGB) ?? lhs
            let right = rhs.usingColorSpace(.sRGB) ?? rhs
            return max(
                abs(left.redComponent - right.redComponent),
                abs(left.greenComponent - right.greenComponent),
                abs(left.blueComponent - right.blueComponent)
            )
        }

        let highlighterController = AnnotationController()
        highlighterController.currentTool = .highlighter
        highlighterController.currentStyle.sloppiness = .architect
        highlighterController.currentStyle.strokeWidth = 14
        highlighterController.setStrokeColor(.palette(.highlighterOrange))
        highlighterController.setOpacity(0.8)
        let inspector = DrawingPropertiesController(
            commandSink: { _ in },
            colorPanelActivityChanged: { _ in }
        )
        inspector.update(
            state: DrawingToolbarState(annotationController: highlighterController)
        )
        _ = inspector.visibleSectionFramesForTesting()
        guard let orangeButton = descendantViews(
            of: NSButton.self,
            in: inspector.view
        ).first(where: { $0.accessibilityLabel() == "Stroke Orange" }) else {
            throw SelfTestError.failure("Expected the highlighter orange stroke swatch")
        }
        let presetPreview = try cachedCenterColor(of: orangeButton)
        let panelBackground = DrawingColorSwatchAppearance.panelBackground(
            for: orangeButton.effectiveAppearance
        )
        let expectedPreset = AnnotationColorResolver.compositedColor(
            .palette(.highlighterOrange),
            opacity: 0.8,
            highlightMultiplier: AnnotationStyle.highlightAlpha,
            over: panelBackground
        )
        highlighterController.begin(at: CGPoint(x: 12, y: 32))
        highlighterController.end(at: CGPoint(x: 84, y: 32))
        let presetCanvasPixels = try renderPixels(
            elements: highlighterController.elementSnapshot,
            renderer: renderer,
            width: 96,
            height: 64,
            backgroundColor: panelBackground
        )
        let presetCanvasPixel = pixel(
            presetCanvasPixels,
            width: 96,
            x: 48,
            y: 32
        )
        let presetCanvasColor = NSColor(
            srgbRed: CGFloat(presetCanvasPixel.red) / 255,
            green: CGFloat(presetCanvasPixel.green) / 255,
            blue: CGFloat(presetCanvasPixel.blue) / 255,
            alpha: 1
        )
        try expect(
            colorDistance(presetPreview, expectedPreset) < 0.09
                && colorDistance(presetCanvasColor, expectedPreset) < 0.09
                && orangeButton.accessibilityValue() as? String == "Selected"
                && orangeButton.layer?.borderWidth == 0,
            "Expected the selected preset swatch and canvas highlighter to share one effective color"
        )

        let customColor = AnnotationColorValue.rgba(
            red: 0.2,
            green: 0.6,
            blue: 1,
            alpha: 0.6
        )
        highlighterController.reset()
        highlighterController.currentTool = .highlighter
        highlighterController.currentStyle.sloppiness = .architect
        highlighterController.currentStyle.strokeWidth = 14
        highlighterController.setStrokeColor(customColor)
        highlighterController.setOpacity(0.8)
        inspector.update(
            state: DrawingToolbarState(annotationController: highlighterController)
        )
        _ = inspector.visibleSectionFramesForTesting()
        guard let customWell = descendantViews(
            of: NSColorWell.self,
            in: inspector.view
        ).first(where: { $0.accessibilityLabel() == "Custom stroke color" }) else {
            throw SelfTestError.failure("Expected the highlighter custom stroke tile")
        }
        let customPreview = try cachedCenterColor(of: customWell)
        let expectedCustom = AnnotationColorResolver.compositedColor(
            customColor,
            opacity: 0.8,
            highlightMultiplier: AnnotationStyle.highlightAlpha,
            over: panelBackground
        )
        let resolvedCustom = AnnotationColorResolver.resolved(
            customColor,
            opacity: 0.8,
            highlightMultiplier: AnnotationStyle.highlightAlpha
        )
        highlighterController.begin(at: CGPoint(x: 12, y: 32))
        highlighterController.end(at: CGPoint(x: 84, y: 32))
        let customCanvasPixels = try renderPixels(
            elements: highlighterController.elementSnapshot,
            renderer: renderer,
            width: 96,
            height: 64,
            backgroundColor: panelBackground
        )
        let customCanvasPixel = pixel(
            customCanvasPixels,
            width: 96,
            x: 48,
            y: 32
        )
        let customCanvasColor = NSColor(
            srgbRed: CGFloat(customCanvasPixel.red) / 255,
            green: CGFloat(customCanvasPixel.green) / 255,
            blue: CGFloat(customCanvasPixel.blue) / 255,
            alpha: 1
        )
        try expect(
            abs(resolvedCustom.alpha - 0.24) < 0.001
                && colorDistance(customPreview, expectedCustom) < 0.09
                && colorDistance(customCanvasColor, expectedCustom) < 0.09
                && customWell.accessibilityValue() as? String == "Not selected",
            "Expected custom sRGB alpha, style opacity, and highlight opacity to apply once"
        )
    }

    private static func testPatternFillRenderingDeterminismAndOpacity() throws {
        guard let uuid = UUID(uuidString: "4A66FA7B-BB0A-4E80-9B5A-49EE9EC9BB45") else {
            throw SelfTestError.failure("Could not create deterministic pattern fill UUID")
        }

        var style = AnnotationStyle(
            color: .black,
            rootWidth: 4,
            alpha: 0.4,
            fillColor: .palette(.blue),
            fillStyle: .hachure,
            sloppiness: .architect
        )
        style.strokeColor = .rgba(red: 0, green: 0, blue: 0, alpha: 0)
        let hachure = AnnotationElement(
            id: AnnotationElementID(uuid),
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 12, y: 12),
                    end: CGPoint(x: 84, y: 84)
                )
            ),
            style: style
        )
        let renderer = AnnotationRenderer()
        let first = try renderPixels(elements: [hachure], renderer: renderer)
        let second = try renderPixels(elements: [hachure], renderer: renderer)
        try expect(
            first == second,
            "Expected seeded hachure rendering to be byte-identical across redraws"
        )

        let hachureInterior = (16..<80).flatMap { y in
            (16..<80).map { x in Int(alpha(first, width: 96, x: x, y: y)) }
        }
        let hachurePainted = hachureInterior.filter { $0 > 0 }
        try expect(
            !hachurePainted.isEmpty
                && hachurePainted.allSatisfy { (95...110).contains($0) }
                && hachureInterior.contains(0)
                && alpha(first, width: 96, x: 6, y: 6) == 0,
            "Expected clipped hachure lines to apply one consistent 40% opacity"
        )

        var roughHachure = hachure
        roughHachure.style.sloppiness = .cartoonist
        let roughHachurePixels = try renderPixels(
            elements: [roughHachure],
            renderer: renderer
        )
        let repeatedRoughHachurePixels = try renderPixels(
            elements: [roughHachure],
            renderer: renderer
        )
        let roughHachureAlpha = stride(
            from: 3,
            to: roughHachurePixels.count,
            by: 4
        ).map { roughHachurePixels[$0] }.filter { $0 > 0 }
        try expect(
            roughHachurePixels == repeatedRoughHachurePixels
                && pixelDifferenceCount(first, roughHachurePixels) >= 80
                && roughHachureAlpha.allSatisfy { (95...110).contains(Int($0)) },
            "Expected hachure strokes to use deterministic rough passes without opacity buildup"
        )

        var crossHatch = hachure
        crossHatch.style.fillStyle = .crossHatch
        let crossPixels = try renderPixels(elements: [crossHatch], renderer: renderer)
        let repeatedCrossPixels = try renderPixels(elements: [crossHatch], renderer: renderer)
        let crossInterior = (16..<80).flatMap { y in
            (16..<80).map { x in Int(alpha(crossPixels, width: 96, x: x, y: y)) }
        }
        let crossPainted = crossInterior.filter { $0 > 0 }
        try expect(
            crossPixels == repeatedCrossPixels
                && crossPixels != first
                && crossPainted.count > hachurePainted.count
                && crossPainted.allSatisfy { (95...110).contains($0) },
            "Expected cross-hatch to add a deterministic second pass without darkening intersections"
        )
    }

    private static func testDrawingCapturePolicies() throws {
        try expect(
            !ZoomCanvasCapturePolicy.stillImage.includesInProgressAnnotations
                && !ZoomCanvasCapturePolicy.stillImage.includesSmartDrawPreview
                && !ZoomCanvasCapturePolicy.stillImage.includesEditorChrome
                && !ZoomCanvasCapturePolicy.stillImage
                    .includesTransientEraserFeedback
                && ZoomCanvasCapturePolicy.stillImage.freehandPresentationOwner
                    == .canonicalRenderer
                && !ZoomCanvasCapturePolicy.stillImage
                    .includesImmediateFreehandLayers
                && ZoomCanvasCapturePolicy.recording.includesInProgressAnnotations
                && ZoomCanvasCapturePolicy.recording.includesSmartDrawPreview
                && !ZoomCanvasCapturePolicy.recording.includesEditorChrome
                && !ZoomCanvasCapturePolicy.recording
                    .includesTransientEraserFeedback
                && ZoomCanvasCapturePolicy.recording.freehandPresentationOwner
                    == .canonicalRenderer
                && !ZoomCanvasCapturePolicy.recording
                    .includesImmediateFreehandLayers,
            "Expected captures to omit editor/eraser presentation while recordings "
                + "preserve canonical active drawing without presentation layers"
        )

        for tool in [AnnotationTool.pen, .rectangle] {
            let controller = AnnotationController()
            controller.currentTool = tool
            controller.begin(at: CGPoint(x: 12, y: 14), tool: tool)
            controller.update(at: CGPoint(x: 54, y: 58))
            guard let activeElement = controller.inProgressElementSnapshot else {
                throw SelfTestError.failure(
                    "Expected an in-progress capture-policy \(tool)"
                )
            }
            let stillPixels = try renderPixels(
                elements: controller.elementSnapshot,
                renderer: AnnotationRenderer(),
                activeElement: ZoomCanvasCapturePolicy.stillImage
                    .includesInProgressAnnotations ? activeElement : nil,
                width: 72,
                height: 72
            )
            let recordingPixels = try renderPixels(
                elements: controller.elementSnapshot,
                renderer: AnnotationRenderer(),
                activeElement: ZoomCanvasCapturePolicy.recording
                    .includesInProgressAnnotations ? activeElement : nil,
                width: 72,
                height: 72
            )
            try expect(
                !stillPixels.contains(where: { $0 != 0 })
                    && recordingPixels.contains(where: { $0 != 0 }),
                "Expected recording policy to render active \(tool) content "
                    + "while still-image policy omits it"
            )
        }
    }

    private static func testCaptureAccessoryCompositorGeometry() throws {
        let display = CGRect(x: -200, y: 500, width: 100, height: 80)
        let localAccessory = CGRect(x: 10, y: 20, width: 20, height: 10)
        func globalFrame(
            displayFrame: CGRect,
            localTopLeftFrame: CGRect
        ) -> CGRect {
            CGRect(
                x: displayFrame.minX + localTopLeftFrame.minX,
                y: displayFrame.maxY - localTopLeftFrame.maxY,
                width: localTopLeftFrame.width,
                height: localTopLeftFrame.height
            )
        }

        let accessory = globalFrame(
            displayFrame: display,
            localTopLeftFrame: localAccessory
        )
        let oneX = CaptureAccessoryCompositor.placement(
            accessoryFrame: accessory,
            displayFrame: display,
            sourceRegion: CGRect(x: 0, y: 0, width: 100, height: 80),
            outputPixelSize: CGSize(width: 100, height: 80)
        )
        let twoX = CaptureAccessoryCompositor.placement(
            accessoryFrame: accessory,
            displayFrame: display,
            sourceRegion: CGRect(x: 0, y: 0, width: 100, height: 80),
            outputPixelSize: CGSize(width: 200, height: 160)
        )
        try expect(
            oneX == CaptureAccessoryPlacement(
                drawRect: CGRect(x: 10, y: 50, width: 20, height: 10),
                clipRect: CGRect(x: 10, y: 50, width: 20, height: 10)
            )
                && twoX == CaptureAccessoryPlacement(
                    drawRect: CGRect(x: 20, y: 100, width: 40, height: 20),
                    clipRect: CGRect(x: 20, y: 100, width: 40, height: 20)
                ),
            "Expected accessory placement to use output/source scale at 1x and 2x"
        )

        let aboveDisplay = CGRect(x: -200, y: 1_200, width: 100, height: 80)
        let belowDisplay = CGRect(x: -200, y: -600, width: 100, height: 80)
        for shiftedDisplay in [aboveDisplay, belowDisplay] {
            let shiftedAccessory = globalFrame(
                displayFrame: shiftedDisplay,
                localTopLeftFrame: localAccessory
            )
            try expect(
                CaptureAccessoryCompositor.placement(
                    accessoryFrame: shiftedAccessory,
                    displayFrame: shiftedDisplay,
                    sourceRegion: CGRect(
                        x: 0,
                        y: 0,
                        width: 100,
                        height: 80
                    ),
                    outputPixelSize: CGSize(width: 100, height: 80)
                ) == oneX,
                "Expected display origins above and below the primary display "
                    + "to preserve display-local top-left placement"
            )
        }

        let mixedScaleRegion = CaptureAccessoryCompositor.placement(
            accessoryFrame: accessory,
            displayFrame: display,
            sourceRegion: CGRect(x: 5, y: 15, width: 40, height: 30),
            outputPixelSize: CGSize(width: 80, height: 90)
        )
        try expect(
            mixedScaleRegion == CaptureAccessoryPlacement(
                drawRect: CGRect(x: 10, y: 45, width: 40, height: 30),
                clipRect: CGRect(x: 10, y: 45, width: 40, height: 30)
            ),
            "Expected region placement to use independent mixed X/Y output scales"
        )

        let partiallyVisible = globalFrame(
            displayFrame: display,
            localTopLeftFrame: CGRect(
                x: -4.5,
                y: 12.25,
                width: 12,
                height: 8.5
            )
        )
        let partialPlacement = CaptureAccessoryCompositor.placement(
            accessoryFrame: partiallyVisible,
            displayFrame: display,
            sourceRegion: CGRect(x: 0, y: 10, width: 30, height: 20),
            outputPixelSize: CGSize(width: 75, height: 30)
        )
        try expect(
            partialPlacement == CaptureAccessoryPlacement(
                drawRect: CGRect(
                    x: -11.25,
                    y: 13.875,
                    width: 30,
                    height: 12.75
                ),
                clipRect: CGRect(
                    x: 0,
                    y: 13.875,
                    width: 18.75,
                    height: 12.75
                )
            ),
            "Expected fractional panels to clip against both the display and "
                + "top-left recording region without integral rounding"
        )
    }

    private static func testCaptureAccessoryCompositorBlendingAndShadow() throws {
        let display = CGRect(x: 0, y: 0, width: 40, height: 30)
        let base = try makeSolidImage(
            width: 40,
            height: 30,
            color: .white
        )
        let red = try makeSolidImage(
            width: 20,
            height: 10,
            color: .red
        )
        let blue = try makeSolidImage(
            width: 20,
            height: 10,
            color: .blue
        )
        let translucent = try makeSolidImage(
            width: 6,
            height: 6,
            color: NSColor.red.withAlphaComponent(0.5)
        )
        func globalFrame(_ localTopLeftFrame: CGRect) -> CGRect {
            CGRect(
                x: localTopLeftFrame.minX,
                y: display.maxY - localTopLeftFrame.maxY,
                width: localTopLeftFrame.width,
                height: localTopLeftFrame.height
            )
        }

        guard let composed = CaptureAccessoryCompositor.compose(
            baseImage: base,
            displayFrame: display,
            sourceRegion: CGRect(origin: .zero, size: display.size),
            outputPixelSize: display.size,
            accessories: [
                CaptureAccessorySnapshot(
                    globalFrame: globalFrame(
                        CGRect(x: 4, y: 4, width: 20, height: 10)
                    ),
                    image: red
                ),
                CaptureAccessorySnapshot(
                    globalFrame: globalFrame(
                        CGRect(x: 9, y: 7, width: 20, height: 10)
                    ),
                    image: blue
                ),
                CaptureAccessorySnapshot(
                    globalFrame: globalFrame(
                        CGRect(x: 31, y: 3, width: 6, height: 6)
                    ),
                    image: translucent
                )
            ]
        ) else {
            throw SelfTestError.failure(
                "Could not create synthetic accessory composition"
            )
        }
        let representation = NSBitmapImageRep(cgImage: composed)
        guard let outside = representation.colorAt(x: 1, y: 1)?
                  .usingColorSpace(.sRGB),
              let toolbarOnly = representation.colorAt(x: 6, y: 6)?
                  .usingColorSpace(.sRGB),
              let overlap = representation.colorAt(x: 12, y: 9)?
                  .usingColorSpace(.sRGB),
              let alphaBlend = representation.colorAt(x: 33, y: 5)?
                  .usingColorSpace(.sRGB) else {
            throw SelfTestError.failure(
                "Could not sample synthetic accessory composition"
            )
        }
        try expect(
            outside.redComponent > 0.95
                && outside.greenComponent > 0.95
                && outside.blueComponent > 0.95
                && toolbarOnly.redComponent > 0.9
                && toolbarOnly.greenComponent < 0.1
                && overlap.blueComponent > 0.9
                && overlap.redComponent < 0.1
                && alphaBlend.redComponent > 0.9
                && (0.4...0.6).contains(alphaBlend.greenComponent)
                && (0.4...0.6).contains(alphaBlend.blueComponent),
            "Expected base -> toolbar -> inspector alpha blending in stable z-order"
        )

        let shadowContent = try makeSolidImage(
            width: 12,
            height: 12,
            color: .black
        )
        guard let shadowSnapshot = CaptureAccessorySnapshotRenderer.snapshot(
            contentImage: shadowContent,
            globalFrame: CGRect(x: 10, y: 10, width: 12, height: 12),
            scaleX: 2,
            scaleY: 2,
            shadow: .inspector
        ) else {
            throw SelfTestError.failure(
                "Could not create inspector shadow snapshot"
            )
        }
        let shadowRepresentation = NSBitmapImageRep(
            cgImage: shadowSnapshot.image
        )
        let padding = Int(CaptureAccessoryShadowStyle.inspector.padding * 2)
        var shadowPixelFound = false
        for y in 0..<shadowRepresentation.pixelsHigh {
            for x in 0..<shadowRepresentation.pixelsWide {
                let insideContent = x >= padding
                    && x < padding + 24
                    && y >= padding
                    && y < padding + 24
                if !insideContent,
                   (shadowRepresentation.colorAt(x: x, y: y)?
                       .alphaComponent ?? 0) > 0.01 {
                    shadowPixelFound = true
                    break
                }
            }
            if shadowPixelFound { break }
        }
        try expect(
            shadowSnapshot.globalFrame
                == CGRect(x: -6, y: -6, width: 44, height: 44)
                && shadowSnapshot.image.width == 88
                && shadowSnapshot.image.height == 88
                && shadowPixelFound,
            "Expected inspector snapshots to include deterministic alpha shadow padding"
        )
    }

    private static func testDrawingAccessoryCaptureVisibilityAndSharing() throws {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let parent = NSWindow(
            contentRect: visibleFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        parent.level = .screenSaver
        parent.isReleasedWhenClosed = false
        parent.orderFront(nil)

        let annotationController = AnnotationController()
        annotationController.currentTool = .hand
        let controller = DrawingToolbarController(
            parentWindow: parent,
            annotationController: annotationController,
            toolbarNormalizedPosition: nil,
            commandSink: { _ in },
            restoreCanvasFocus: {},
            toolbarPlacementDidChange: { _ in },
            pointerInteractionChanged: { _ in }
        )
        defer {
            controller.close()
            parent.orderOut(nil)
        }

        try expect(
            controller.captureAccessorySnapshots(
                scaleX: 1,
                scaleY: 1
            ).isEmpty,
            "Expected inactive drawing controls to produce no capture snapshots"
        )
        controller.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        let handSnapshots = controller.captureAccessorySnapshots(
            scaleX: 1,
            scaleY: 1
        )
        try expect(
            handSnapshots.count == 1
                && handSnapshots[0].globalFrame
                    == controller.toolbarFrameForTesting
                && controller.toolbarWindowForTesting.sharingType == .readOnly
                && controller.inspectorWindowForTesting.sharingType == .readOnly
                && controller.toolbarWindowForTesting.level.rawValue
                    >= parent.level.rawValue
                && controller.inspectorWindowForTesting.level.rawValue
                    >= controller.toolbarWindowForTesting.level.rawValue
                && controller.toolbarWindowForTesting.parent === parent,
            "Expected the visible stable toolbar to be externally shareable "
                + "without a propertyless inspector (snapshots "
                + "\(handSnapshots.count), toolbar sharing "
                + "\(controller.toolbarWindowForTesting.sharingType.rawValue), "
                + "inspector sharing "
                + "\(controller.inspectorWindowForTesting.sharingType.rawValue), "
                + "levels \(controller.toolbarWindowForTesting.level.rawValue)/"
                + "\(controller.inspectorWindowForTesting.level.rawValue)/"
                + "\(parent.level.rawValue), frame "
                + "\(handSnapshots.first?.globalFrame == controller.toolbarFrameForTesting), "
                + "parents "
                + "\(controller.toolbarWindowForTesting.parent === parent)/"
                + "\(controller.inspectorWindowForTesting.parent === controller.toolbarWindowForTesting))"
        )

        annotationController.currentTool = .rectangle
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let rectangleSnapshots = controller.captureAccessorySnapshots(
            scaleX: 2,
            scaleY: 2
        )
        try expect(
            rectangleSnapshots.count == 2
                && rectangleSnapshots[0].globalFrame
                    == controller.toolbarFrameForTesting
                && rectangleSnapshots[1].globalFrame.contains(
                    controller.inspectorFrameForTesting
                )
                && controller.inspectorWindowForTesting.parent
                    === controller.toolbarWindowForTesting,
            "Expected ordered toolbar then inspector snapshots only while both "
                + "stable controls are truly shown"
        )

        annotationController.currentTool = .eraser
        controller.updateState(
            DrawingToolbarState(annotationController: annotationController)
        )
        let staleInspectorFrame = controller.inspectorFrameForTesting
        try expect(
            staleInspectorFrame.width > 0
                && controller.captureAccessorySnapshots(
                    scaleX: 1,
                    scaleY: 1
                ).count == 1,
            "Expected a hidden propertyless inspector to stay excluded despite "
                + "its stale nonzero frame"
        )

        controller.hide()
        try expect(
            controller.captureAccessorySnapshots(
                scaleX: 1,
                scaleY: 1
            ).isEmpty,
            "Expected suppressed or hidden stable controls to produce no snapshots"
        )
    }

    private static func testZoomCanvasAccessoryCaptureIntegration() throws {
        let displayFrame = CGRect(x: -120, y: 450, width: 40, height: 30)
        let baseImage = try makeSolidImage(
            width: 80,
            height: 60,
            color: NSColor(
                calibratedRed: 0.1,
                green: 0.35,
                blue: 0.15,
                alpha: 1
            )
        )
        let accessoryImage = try makeSolidImage(
            width: 16,
            height: 12,
            color: .magenta
        )
        let capturedFrame = CapturedFrame(
            image: baseImage,
            display: DisplayDescriptor(
                id: 77,
                frame: displayFrame,
                scaleFactor: 2
            ),
            pixelSize: CGSize(width: 80, height: 60),
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let viewportController = ZoomViewportController()
        viewportController.configure(for: capturedFrame, initialZoom: 1)
        var controlsVisible = true
        let accessoryFrame = CGRect(
            x: displayFrame.minX + 4,
            y: displayFrame.maxY - 3 - 6,
            width: 8,
            height: 6
        )
        let canvas = ZoomCanvasView(
            frame: CGRect(origin: .zero, size: displayFrame.size),
            capturedFrame: capturedFrame,
            viewportController: viewportController,
            annotationController: AnnotationController(),
            smoothImage: true,
            userSelectedResourceAccess:
                UserDefaultsUserSelectedResourceAccess(),
            commandSink: { _ in },
            captureCompositor: {
                baseImage,
                displayFrame,
                sourceRegion,
                outputPixelSize in
                CaptureAccessoryCompositor.compose(
                    baseImage: baseImage,
                    displayFrame: displayFrame,
                    sourceRegion: sourceRegion,
                    outputPixelSize: outputPixelSize,
                    accessories: controlsVisible
                        ? [
                            CaptureAccessorySnapshot(
                                globalFrame: accessoryFrame,
                                image: accessoryImage
                            )
                        ]
                        : []
                )
            }
        )

        func containsMagenta(_ image: CGImage) -> Bool {
            let representation = NSBitmapImageRep(cgImage: image)
            for y in 0..<representation.pixelsHigh {
                for x in 0..<representation.pixelsWide {
                    guard let color = representation.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB) else {
                        continue
                    }
                    if color.redComponent > 0.8
                        && color.blueComponent > 0.8
                        && color.greenComponent < 0.2 {
                        return true
                    }
                }
            }
            return false
        }

        guard let wholeStill = canvas.captureImageForTesting(
            policy: .stillImage,
            sourceRect: nil,
            outputPixelSize: nil
        ), let fullRecording = canvas.captureImageForTesting(
            policy: .recording,
            sourceRect: nil,
            outputPixelSize: CGSize(width: 83, height: 61)
        ), let regionRecording = canvas.captureImageForTesting(
            policy: .recording,
            sourceRect: CGRect(x: 2, y: 1, width: 12, height: 10),
            outputPixelSize: CGSize(width: 25, height: 21)
        ), let regionWithoutControls = canvas.captureImageForTesting(
            policy: .recording,
            sourceRect: CGRect(x: 20, y: 15, width: 10, height: 10),
            outputPixelSize: CGSize(width: 23, height: 19)
        ) else {
            throw SelfTestError.failure(
                "Could not render integrated canvas capture paths"
            )
        }
        try expect(
            containsMagenta(wholeStill)
                && fullRecording.width == 83
                && fullRecording.height == 61
                && containsMagenta(fullRecording)
                && regionRecording.width == 25
                && regionRecording.height == 21
                && containsMagenta(regionRecording)
                && regionWithoutControls.width == 23
                && regionWithoutControls.height == 19
                && !containsMagenta(regionWithoutControls),
            "Expected whole Copy/Save and exact full/region recording outputs "
                + "to include only intersecting visible stable controls"
        )

        controlsVisible = false
        guard let suppressedSnip = canvas.captureImageForTesting(
            policy: .stillImage,
            sourceRect: CGRect(x: 2, y: 1, width: 12, height: 10),
            outputPixelSize: CGSize(width: 24, height: 20)
        ) else {
            throw SelfTestError.failure(
                "Could not render suppressed in-overlay snip capture"
            )
        }
        try expect(
            !containsMagenta(suppressedSnip),
            "Expected region-selection suppression to omit stable controls from "
                + "the final snip"
        )
    }

    private static func testCaptureFeedbackAndRecordingDimensionPolicies() throws {
        try expect(
            OverlayWindowSharingPolicy.sharingType(
                for: .standardWindow
            ) == .readWrite
                && OverlayWindowSharingPolicy.sharingType(
                    for: .staticOverlay
                ) == .readOnly
                && OverlayWindowSharingPolicy.sharingType(
                    for: .liveOverlay
                ) == .readOnly
                && OverlayWindowSharingPolicy.isVisibleToExternalCapture(
                    context: .standardWindow
                )
                && OverlayWindowSharingPolicy.isVisibleToExternalCapture(
                    context: .staticOverlay
                )
                && OverlayWindowSharingPolicy.isVisibleToExternalCapture(
                    context: .liveOverlay
                )
                && LiveCaptureFeedbackPolicy.excludesApplication(
                processID: 42,
                ownProcessID: 42
            )
                && !LiveCaptureFeedbackPolicy.excludesApplication(
                    processID: 41,
                    ownProcessID: 42
                )
                && RecordingFrameReplacementPolicy.source(
                    hasOverlaySnapshot: true
                ) == .overlaySnapshot
                && RecordingFrameReplacementPolicy.source(
                    hasOverlaySnapshot: false
                ) == .screenStream,
            "Expected standard, static, and live windows to remain externally "
                + "capturable, live capture to exclude the whole ZoomIt process, "
                + "and recording to choose exactly one frame source"
        )

        let display = DisplayDescriptor(
            id: 12,
            frame: CGRect(x: -400, y: 900, width: 100, height: 80),
            scaleFactor: 2
        )
        try expect(
            RecordingController.outputPixelSize(
                display: display,
                sourceRect: nil
            ) == CGSize(width: 200, height: 160)
                && RecordingController.outputPixelSize(
                    display: display,
                    sourceRect: CGRect(
                        x: 3.25,
                        y: 4.5,
                        width: 12.75,
                        height: 9.25
                    )
                ) == CGSize(width: 25, height: 18),
            "Expected recording output dimensions to match ScreenCaptureKit's "
                + "full and fractional region pixel sizes exactly"
        )
    }

    private static func testAnnotationSloppinessDeterminismAndEndpoints() throws {
        guard let uuid = UUID(uuidString: "2F3D3E7A-18A7-4F65-9E50-5B17C2AA0031") else {
            throw SelfTestError.failure("Could not create deterministic sloppiness test UUID")
        }
        let elementID = AnnotationElementID(uuid)
        let straight = CGMutablePath()
        straight.move(to: CGPoint(x: 8, y: 20))
        straight.addLine(to: CGPoint(x: 88, y: 34))

        for sloppiness in [AnnotationSloppiness.artist, .cartoonist] {
            let first = AnnotationRoughStroke.paths(
                for: straight,
                sloppiness: sloppiness,
                elementID: elementID,
                strokeWidth: 5
            )
            let second = AnnotationRoughStroke.paths(
                for: straight,
                sloppiness: sloppiness,
                elementID: elementID,
                strokeWidth: 5
            )
            try expect(
                first.count == 2
                    && second.count == 2
                    && zip(first, second).allSatisfy { $0 == $1 },
                "Expected seeded sloppiness paths to be identical across redraws"
            )
            let endpoints = first.compactMap(AnnotationRoughStroke.endpoints)
            try expect(
                endpoints.count == 2
                    && !approximatelyEqual(endpoints[0].start, endpoints[1].start)
                    && !approximatelyEqual(endpoints[0].end, endpoints[1].end),
                "Expected unbound rough line passes to remain independently separated at endpoints"
            )
            let pinned = AnnotationRoughStroke.paths(
                for: straight,
                sloppiness: sloppiness,
                elementID: elementID,
                strokeWidth: 5,
                pinnedPoints: [CGPoint(x: 8, y: 20), CGPoint(x: 88, y: 34)]
            )
            try expect(
                pinned.allSatisfy {
                    AnnotationRoughStroke.endpoints(of: $0)?.start == CGPoint(x: 8, y: 20)
                        && AnnotationRoughStroke.endpoints(of: $0)?.end == CGPoint(x: 88, y: 34)
                },
                "Expected explicitly pinned bindings and arrow tips to remain canonical"
            )
        }

        let precise = AnnotationRoughStroke.paths(
            for: straight,
            sloppiness: .architect,
            elementID: elementID,
            strokeWidth: 5
        )
        try expect(
            precise.count == 1 && precise[0] == straight,
            "Expected Architect sloppiness to preserve one precise path"
        )

        var style = AnnotationStyle(
            color: .blue,
            rootWidth: 5,
            alpha: 1,
            sloppiness: .cartoonist
        )
        style.lineCap = .butt
        let element = AnnotationElement(
            id: elementID,
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 8, y: 20), CGPoint(x: 88, y: 34)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .arrow,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: style
        )
        let firstPixels = try renderPixels(
            elements: [element],
            renderer: AnnotationRenderer()
        )
        let secondPixels = try renderPixels(
            elements: [element],
            renderer: AnnotationRenderer()
        )
        try expect(
            firstPixels == secondPixels,
            "Expected seeded rough rendering to remain deterministic across capture redraws"
        )
        try expect(
            AnnotationHitTester.contains(
                CGPoint(x: 48, y: 27),
                in: element,
                zoomScale: 1
            ),
            "Expected rough rendering to keep canonical hit testing"
        )
    }

    private static func testMeasuredRoughRenderingModel() throws {
        try expect(
            AnnotationRoughStroke.maximumDestinationDeviation(for: .architect) == 0
                && AnnotationRoughStroke.maximumDestinationDeviation(for: .artist) == 5.5
                && AnnotationRoughStroke.maximumDestinationDeviation(for: .cartoonist) == 11,
            "Expected rough-stroke deviation caps to remain defined in destination pixels"
        )
        let elementID = AnnotationElementID(
            UUID(uuidString: "6E470104-94ED-401E-A78A-FF74BE313A69")!
        )
        let duplicateID = AnnotationElementID(
            UUID(uuidString: "C140D863-BB53-4D02-B849-E79B7EEC1678")!
        )
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 20, y: 40))
        line.addLine(to: CGPoint(x: 200, y: 40))

        let artist = AnnotationRoughStroke.paths(
            for: line,
            sloppiness: .artist,
            elementID: elementID,
            strokeWidth: 2
        )
        let cartoonist = AnnotationRoughStroke.paths(
            for: line,
            sloppiness: .cartoonist,
            elementID: elementID,
            strokeWidth: 2
        )
        let artistDeviation = meanHorizontalWaviness(artist)
        let cartoonistDeviation = meanHorizontalWaviness(cartoonist)
        let artistSeparation = meanPathSeparation(artist[0], artist[1])
        let cartoonistSeparation = meanPathSeparation(cartoonist[0], cartoonist[1])
        let artistMaximum = maximumHorizontalDeviation(artist, canonicalY: 40)
        let cartoonistMaximum = maximumHorizontalDeviation(cartoonist, canonicalY: 40)
        try expect(
            (1.4...1.9).contains(artistDeviation)
                && (2.3...3.1).contains(artistSeparation)
                && (1.6...2.5).contains(artistMaximum),
            "Expected audited 180px/2px Artist calibration (waviness "
                + "\(artistDeviation), separation \(artistSeparation), max "
                + "\(artistMaximum))"
        )
        try expect(
            cartoonistDeviation >= artistDeviation * 1.7,
            "Expected Cartoonist line deviation to be at least 1.7x Artist "
                + "(artist \(artistDeviation), cartoonist \(cartoonistDeviation))"
        )
        try expect(
            cartoonistSeparation >= artistSeparation * 1.6,
            "Expected Cartoonist pass separation to be at least 1.6x Artist "
                + "(artist \(artistSeparation), cartoonist \(cartoonistSeparation))"
        )
        try expect(
            artistMaximum
                <= AnnotationRoughStroke.maximumDestinationDeviation(
                    for: .artist,
                    strokeWidth: 2
                ) + 0.01
                && cartoonistMaximum
                    <= AnnotationRoughStroke.maximumDestinationDeviation(
                        for: .cartoonist,
                        strokeWidth: 2
                    ) + 0.01,
            "Expected measured rough lines to honor width-aware destination caps "
                + "(artist \(artistMaximum), cartoonist \(cartoonistMaximum))"
        )

        for strokeWidth in [CGFloat(1), 3] {
            let thinCartoonist = AnnotationRoughStroke.paths(
                for: line,
                sloppiness: .cartoonist,
                elementID: elementID,
                strokeWidth: strokeWidth
            )
            let firstPoints = AnnotationRoughStroke.sampledPoints(
                on: thinCartoonist[0],
                curveSubdivisions: 48
            )
            let secondPoints = AnnotationRoughStroke.sampledPoints(
                on: thinCartoonist[1],
                curveSubdivisions: 48
            )
            let separations = zip(firstPoints, secondPoints).map {
                hypot($0.x - $1.x, $0.y - $1.y)
            }
            let visiblySeparatedFraction = CGFloat(
                separations.filter { $0 >= 2 }.count
            ) / CGFloat(max(1, separations.count))
            let endpoints = thinCartoonist.compactMap(
                AnnotationRoughStroke.endpoints
            )
            try expect(
                visiblySeparatedFraction >= 0.35
                    && (separations.max() ?? 0) >= 4
                    && endpoints.count == 2
                    && endpoints.allSatisfy {
                        $0.start.x <= 16.1 && $0.end.x >= 203.9
                    },
                "Expected thin/normal Cartoonist traces to diverge over substantial edge portions "
                    + "with 4px+ independent overruns (width \(strokeWidth), fraction "
                    + "\(visiblySeparatedFraction), max \(separations.max() ?? 0), "
                    + "endpoints \(endpoints))"
            )
        }

        let zoomedArtist = AnnotationRoughStroke.paths(
            for: line,
            sloppiness: .artist,
            elementID: elementID,
            strokeWidth: 2,
            destinationScale: 2
        )
        let zoomedScreenDeviation = meanHorizontalDeviation(
            zoomedArtist,
            canonicalY: 40
        ) * 2
        let unzoomedScreenDeviation = meanHorizontalDeviation(
            artist,
            canonicalY: 40
        )
        try expect(
            abs(zoomedScreenDeviation - unzoomedScreenDeviation) <= 0.08,
            "Expected roughness to remain stable in destination pixels across content zoom "
                + "(1x \(unzoomedScreenDeviation), 2x \(zoomedScreenDeviation))"
        )

        let duplicate = AnnotationRoughStroke.paths(
            for: line,
            sloppiness: .artist,
            elementID: duplicateID,
            strokeWidth: 2
        )
        try expect(
            AnnotationRoughStroke.roughSeed(for: elementID)
                != AnnotationRoughStroke.roughSeed(for: duplicateID)
                && duplicate != artist,
            "Expected duplicated elements to derive distinct stable rough seeds"
        )

        let solidArtist = AnnotationStyle(
            color: .black,
            rootWidth: 2,
            alpha: 1,
            sloppiness: .artist
        )
        var dashedArtist = solidArtist
        dashedArtist.strokePattern = .dashed
        var dottedCartoonist = solidArtist
        dottedCartoonist.sloppiness = .cartoonist
        dottedCartoonist.strokePattern = .dotted
        var architect = solidArtist
        architect.sloppiness = .architect
        try expect(
            AnnotationRenderer.strokePassCount(for: architect) == 1
                && AnnotationRenderer.strokePassCount(for: solidArtist) == 2
                && AnnotationRenderer.strokePassCount(for: dashedArtist) == 2
                && AnnotationRenderer.strokePassCount(for: dottedCartoonist) == 2
                && AnnotationRenderer.strokeWidthCompensation(for: dashedArtist) == 1,
            "Expected patterned rough strokes to keep independent passes without widening"
        )

        let rectangle = CGMutablePath()
        rectangle.addRect(CGRect(x: 20, y: 20, width: 180, height: 60))
        let artistRectangle = AnnotationRoughStroke.paths(
            for: rectangle,
            sloppiness: .artist,
            elementID: elementID,
            strokeWidth: 2,
            independentClosedCorners: true
        )
        let cartoonistRectangle = AnnotationRoughStroke.paths(
            for: rectangle,
            sloppiness: .cartoonist,
            elementID: elementID,
            strokeWidth: 2,
            independentClosedCorners: true
        )
        try expect(
            artistRectangle.allSatisfy {
                AnnotationRoughStroke.pathMoveCount($0) == 4
            }
                && cartoonistRectangle.allSatisfy {
                    AnnotationRoughStroke.pathMoveCount($0) == 4
                }
                && artistRectangle[0] != artistRectangle[1]
                && cartoonistRectangle[0] != cartoonistRectangle[1],
            "Expected Artist and Cartoonist sides and passes to sample independent corners"
        )

        let crossingCount = (0..<12).filter { salt in
            let independentPaths = AnnotationRoughStroke.paths(
                for: line,
                sloppiness: .cartoonist,
                elementID: elementID,
                strokeWidth: 2,
                salt: UInt64(salt)
            )
            let differences = zip(
                AnnotationRoughStroke.sampledPoints(
                    on: independentPaths[0],
                    curveSubdivisions: 24
                ),
                AnnotationRoughStroke.sampledPoints(
                    on: independentPaths[1],
                    curveSubdivisions: 24
                )
            ).map { $0.y - $1.y }
            return differences.contains { $0 > 0.1 }
                && differences.contains { $0 < -0.1 }
        }.count
        try expect(
            crossingCount >= 4,
            "Expected independently seeded Cartoonist passes to cross instead of forming systematic rails"
        )

        for length in [CGFloat(60), 180, 400] {
            let calibrationLine = CGMutablePath()
            calibrationLine.move(to: CGPoint(x: 20, y: 40))
            calibrationLine.addLine(to: CGPoint(x: 20 + length, y: 40))
            let paths = AnnotationRoughStroke.paths(
                for: calibrationLine,
                sloppiness: .cartoonist,
                elementID: elementID,
                strokeWidth: 2
            )
            let firstPoints = AnnotationRoughStroke.sampledPoints(
                on: paths[0],
                curveSubdivisions: 48
            )
            let secondPoints = AnnotationRoughStroke.sampledPoints(
                on: paths[1],
                curveSubdivisions: 48
            )
            let separations = zip(firstPoints, secondPoints).map {
                hypot($0.x - $1.x, $0.y - $1.y)
            }
            let resolvedSeparations = separations.filter { $0 >= 2.25 }
            let resolvedFraction = CGFloat(
                resolvedSeparations.count
            ) / CGFloat(max(1, separations.count))
            let separation = resolvedSeparations.isEmpty
                ? separations.max() ?? 0
                : resolvedSeparations.reduce(0, +)
                    / CGFloat(resolvedSeparations.count)
            let waviness = meanHorizontalDeviation(paths, canonicalY: 40)
            try expect(
                resolvedFraction >= 0.55
                    && (2.5...10).contains(separation)
                    && (1.2...8).contains(waviness),
                "Expected deliberately strong Cartoonist variation across substantial portions at "
                    + "\(length)px (fraction \(resolvedFraction), separation "
                    + "\(separation), waviness \(waviness))"
            )
        }

        let smallEllipse = CGRect(x: 10, y: 10, width: 60, height: 60)
        let wideEllipse = CGRect(x: 10, y: 10, width: 400, height: 60)
        let ellipsePaths = AnnotationRoughStroke.ellipsePaths(
            in: smallEllipse,
            sloppiness: .cartoonist,
            elementID: elementID,
            strokeWidth: 2
        )
        let smallSampleCount = AnnotationRoughStroke.ellipseSampleCount(
            in: smallEllipse,
            destinationScale: 1
        )
        let wideSampleCount = AnnotationRoughStroke.ellipseSampleCount(
            in: wideEllipse,
            destinationScale: 1
        )
        try expect(
            ellipsePaths.count == 2
                && smallSampleCount >= 9
                && wideSampleCount > smallSampleCount
                && ellipsePaths.allSatisfy {
                    AnnotationRoughStroke.pathElementCount($0) >= smallSampleCount + 2
                },
            "Expected adaptively sampled rough ellipses with at least nine perimeter samples"
        )

        let pressureSamples = (0..<1_200).map { index in
            AnnotationPointSample(
                location: CGPoint(
                    x: CGFloat(index) * 0.35,
                    y: 80 + sin(CGFloat(index) * 0.025) * 8
                ),
                pressure: 0.25 + CGFloat(index % 17) / 24
            )
        }
        let pressurePaths = AnnotationRoughStroke.pressurePaths(
            samples: pressureSamples,
            baseWidth: 8,
            sloppiness: .cartoonist,
            elementID: elementID,
            salt: 0x5052_4553_5355_5245,
            destinationScale: 1
        )
        try expect(
            pressurePaths.count == 2
                && pressurePaths.allSatisfy {
                    AnnotationRoughStroke.pathElementCount($0)
                        <= pressureSamples.count * 2 + 5
                },
            "Expected pressure rendering to stay O(n) with two bounded fill operations"
        )

        let pressurePrefix = Array(pressureSamples.prefix(320))
        let pressureExtended = Array(pressureSamples.prefix(760))
        let prefixPaths = AnnotationRoughStroke.pressurePaths(
            samples: pressurePrefix,
            baseWidth: 8,
            sloppiness: .artist,
            elementID: elementID,
            salt: 0x5052_4546_4958_5354,
            destinationScale: 1
        )
        let extendedPaths = AnnotationRoughStroke.pressurePaths(
            samples: pressureExtended,
            baseWidth: 8,
            sloppiness: .artist,
            elementID: elementID,
            salt: 0x5052_4546_4958_5354,
            destinationScale: 1
        )
        let stablePrefixCount = pressurePrefix.count - 2
        try expect(
            zip(prefixPaths, extendedPaths).allSatisfy { pair in
                let prefixPoints = AnnotationRoughStroke.sampledPoints(
                    on: pair.0,
                    curveSubdivisions: 2
                )
                let extendedPoints = AnnotationRoughStroke.sampledPoints(
                    on: pair.1,
                    curveSubdivisions: 2
                )
                return zip(
                    prefixPoints.prefix(stablePrefixCount),
                    extendedPoints.prefix(stablePrefixCount)
                ).allSatisfy {
                    hypot($1.x - $0.x, $1.y - $0.y) <= 0.000_001
                }
            },
            "Expected absolute-arc-length roughness to keep finalized pressure-stroke prefixes stable"
        )

        var arrowStyle = AnnotationStyle(
            color: .black,
            rootWidth: 4,
            alpha: 1,
            strokePattern: .dashed,
            sloppiness: .cartoonist
        )
        arrowStyle.lineCap = .butt
        let arrow = AnnotationElement(
            id: elementID,
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [CGPoint(x: 12, y: 48), CGPoint(x: 84, y: 48)],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .triangle,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: arrowStyle
        )
        var preciseArrow = arrow
        preciseArrow.style.sloppiness = .architect
        let roughArrowPixels = try renderPixels(
            elements: [arrow],
            renderer: AnnotationRenderer()
        )
        let preciseArrowPixels = try renderPixels(
            elements: [preciseArrow],
            renderer: AnnotationRenderer()
        )
        let headDifference = pixelDifferenceCount(
            roughArrowPixels,
            preciseArrowPixels,
            width: 96,
            xRange: 68..<92,
            yRange: 34..<63
        )
        let roughArrowCenterAlpha = alpha(
            roughArrowPixels,
            width: 96,
            x: 76,
            y: 48
        )
        let roughArrowHasTip = hasPaintedPixel(
            roughArrowPixels,
            width: 96,
            height: 96,
            near: CGPoint(x: 84, y: 48),
            radius: 1
        )
        try expect(
            headDifference >= 20
                && roughArrowCenterAlpha > 0
                && roughArrowHasTip,
            "Expected capped rough arrowhead variation, a solid filled head, and a preserved tip"
                + " (difference \(headDifference), center alpha "
                + "\(roughArrowCenterAlpha), tip \(roughArrowHasTip))"
        )
    }

    private static func testRoughRasterMatrixAndSelectionClearance() throws {
        let elementID = AnnotationElementID(
            UUID(uuidString: "E03C4804-BC51-4F0A-9BED-8E14C1B2F2A7")!
        )
        let patterns: [AnnotationStrokePattern] = [.solid, .dashed, .dotted]
        let sloppinessValues: [AnnotationSloppiness] = [
            .architect, .artist, .cartoonist
        ]

        for strokeWidth in [CGFloat(1), 3, 6] {
            for pattern in patterns {
                var normalizedBoundsBySloppiness:
                    [AnnotationSloppiness: CGRect] = [:]
                for backingScale in [1, 2] {
                    var pixelsBySloppiness:
                        [AnnotationSloppiness: [UInt8]] = [:]
                    var comparisonPixelsBySloppiness:
                        [AnnotationSloppiness: [UInt8]] = [:]
                    var boundsBySloppiness:
                        [AnnotationSloppiness: CGRect] = [:]
                    for sloppiness in sloppinessValues {
                        var style = AnnotationStyle(
                            color: .black,
                            rootWidth: strokeWidth,
                            alpha: 1,
                            strokePattern: pattern,
                            sloppiness: sloppiness
                        )
                        style.lineCap = .butt
                        style.lineJoin = .miter
                        let element = AnnotationElement(
                            id: elementID,
                            geometry: .shape(
                                AnnotationShapeGeometry(
                                    kind: .rectangle,
                                    start: CGPoint(x: 20, y: 20),
                                    end: CGPoint(x: 76, y: 60)
                                )
                            ),
                            style: style
                        )
                        let pixels = try renderPixels(
                            elements: [element],
                            renderer: AnnotationRenderer(),
                            width: 96,
                            height: 80,
                            backingScale: backingScale
                        )
                        guard let bounds = paintedBounds(
                            pixels,
                            width: 96 * backingScale,
                            height: 80 * backingScale
                        ) else {
                            throw SelfTestError.failure(
                                "Expected \(sloppiness) \(pattern) raster at width \(strokeWidth)"
                            )
                        }
                        pixelsBySloppiness[sloppiness] = pixels
                        var comparisonElement = element
                        comparisonElement.geometry = .shape(
                            AnnotationShapeGeometry(
                                kind: .rectangle,
                                start: CGPoint(x: 40, y: 34),
                                end: CGPoint(x: 56, y: 46)
                            )
                        )
                        comparisonElement.style.fillStyle = .solid
                        comparisonElement.style.fillColor = .palette(.black)
                        comparisonElement.style.strokePattern = .solid
                        comparisonElement.style.strokeWidth = 1
                        comparisonPixelsBySloppiness[sloppiness] =
                            try renderPixels(
                                elements: [comparisonElement],
                                renderer: AnnotationRenderer(),
                                width: 96,
                                height: 80,
                                backingScale: backingScale
                            )
                        boundsBySloppiness[sloppiness] = bounds
                        let normalized = CGRect(
                            x: bounds.minX / CGFloat(backingScale),
                            y: bounds.minY / CGFloat(backingScale),
                            width: bounds.width / CGFloat(backingScale),
                            height: bounds.height / CGFloat(backingScale)
                        )
                        if backingScale == 1 {
                            normalizedBoundsBySloppiness[sloppiness] = normalized
                        } else if let reference = normalizedBoundsBySloppiness[sloppiness] {
                            try expect(
                                abs(normalized.minX - reference.minX) <= 6
                                    && abs(normalized.minY - reference.minY) <= 6
                                    && abs(normalized.width - reference.width) <= 6
                                    && abs(normalized.height - reference.height) <= 6,
                                "Expected logical rough silhouettes to remain stable at 1x/2x backing scale "
                                    + "(\(pattern), \(sloppiness), width \(strokeWidth), "
                                    + "1x \(reference), 2x \(normalized))"
                            )
                        }

                        let selectedPixels = try renderPixels(
                            elements: [element],
                            renderer: AnnotationRenderer(),
                            decorationElements: [element],
                            selectedElementIDs: [element.id],
                            zoomScale: 1,
                            width: 96,
                            height: 80,
                            backingScale: backingScale
                        )
                        try expect(
                            paintedPixelCount(selectedPixels)
                                >= paintedPixelCount(pixels),
                            "Expected selection chrome not to mask \(sloppiness) rough pixels"
                        )

                        guard let decoration = AnnotationGeometry.selectionDecoration(
                            for: element,
                            zoomScale: 1
                        ) else {
                            throw SelfTestError.failure(
                                "Expected selection decoration for rough raster matrix"
                            )
                        }
                        let outlineBounds = CGRect(
                            origin: CGPoint(
                                x: decoration.outline.map(\.x).min() ?? 0,
                                y: decoration.outline.map(\.y).min() ?? 0
                            ),
                            size: CGSize(
                                width: (decoration.outline.map(\.x).max() ?? 0)
                                    - (decoration.outline.map(\.x).min() ?? 0),
                                height: (decoration.outline.map(\.y).max() ?? 0)
                                    - (decoration.outline.map(\.y).min() ?? 0)
                            )
                        )
                        let requiredClearance = strokeWidth / 2
                            + AnnotationRoughStroke.maximumDestinationDeviation(
                                for: sloppiness,
                                strokeWidth: strokeWidth
                            )
                        try expect(
                            outlineBounds.minX
                                <= 20 - requiredClearance - 1.9
                                && outlineBounds.maxX
                                    >= 76 + requiredClearance + 1.9,
                            "Expected selection chrome outside stroke and maximum rough deviation"
                        )
                    }

                    guard let architectBounds = boundsBySloppiness[.architect],
                          let artistBounds = boundsBySloppiness[.artist],
                          let cartoonistBounds = boundsBySloppiness[.cartoonist],
                          let architectPixels =
                            comparisonPixelsBySloppiness[.architect],
                          let comparisonArtistPixels =
                            comparisonPixelsBySloppiness[.artist],
                          let comparisonCartoonistPixels =
                            comparisonPixelsBySloppiness[.cartoonist],
                          let cartoonistPixels = pixelsBySloppiness[.cartoonist] else {
                        throw SelfTestError.failure(
                            "Expected complete rough raster matrix"
                        )
                    }
                    let artistDifferenceRatio = alphaMaskSymmetricDifferenceRatio(
                        architectPixels,
                        comparisonArtistPixels
                    )
                    let cartoonistDifferenceRatio =
                        alphaMaskSymmetricDifferenceRatio(
                            architectPixels,
                            comparisonCartoonistPixels
                        )
                    let calibrationContext =
                        "\(pattern), width \(strokeWidth), backing "
                        + "\(backingScale)x, artist \(artistDifferenceRatio), "
                        + "cartoonist \(cartoonistDifferenceRatio), bounds "
                        + "\(architectBounds)/\(artistBounds)/\(cartoonistBounds)"
                    try expect(
                        (0.08...0.35).contains(artistDifferenceRatio)
                            && cartoonistDifferenceRatio
                                >= artistDifferenceRatio * 1.5,
                        "Expected calibrated Artist/Cartoonist alpha-mask separation "
                            + "(\(calibrationContext))"
                    )

                    if pattern != .solid {
                        let physicalWidth = 96 * backingScale
                        let maximumRuns = (10 * backingScale..<70 * backingScale)
                            .map {
                                paintedRuns(
                                    cartoonistPixels,
                                    width: physicalWidth,
                                    y: $0,
                                    xRange: 8 * backingScale..<88 * backingScale
                                )
                            }
                            .max() ?? 0
                        try expect(
                            maximumRuns >= 2,
                            "Expected patterned rough strokes to retain visible dash/dot separation "
                                + "(\(pattern), width \(strokeWidth), scale \(backingScale), "
                                + "runs \(maximumRuns))"
                        )
                    }
                }
            }
        }

        for route in [AnnotationLinearRoute.straight, .curved] {
            let geometry = AnnotationLinearGeometry(
                points: [
                    CGPoint(x: 16, y: 40),
                    CGPoint(x: 204, y: 40)
                ],
                route: route,
                startArrowhead: .none,
                endArrowhead: .none,
                startBinding: nil,
                endBinding: nil,
                bezierControls: route == .curved
                    ? [
                        AnnotationBezierControl(
                            start: CGPoint(x: 70, y: 12),
                            end: CGPoint(x: 150, y: 68)
                        )
                    ]
                    : []
            )
            for backingScale in [1, 2] {
                var renders: [AnnotationSloppiness: [UInt8]] = [:]
                for sloppiness in sloppinessValues {
                    var style = AnnotationStyle(
                        color: .black,
                        rootWidth: 3,
                        alpha: 1,
                        sloppiness: sloppiness
                    )
                    style.lineCap = .round
                    let element = AnnotationElement(
                        id: elementID,
                        geometry: .linear(geometry),
                        style: style
                    )
                    renders[sloppiness] = try renderPixels(
                        elements: [element],
                        renderer: AnnotationRenderer(),
                        width: 220,
                        height: 80,
                        backingScale: backingScale
                    )
                }
                try expect(
                    renders[.architect] == renders[.artist]
                        && renders[.architect] == renders[.cartoonist],
                    "Expected \(route) headless Line raster bytes to ignore stored "
                        + "sloppiness at backing \(backingScale)x"
                )
            }
        }

        let lineController = AnnotationController()
        lineController.currentTool = .rectangle
        lineController.setSloppiness(.cartoonist)
        lineController.currentTool = .line
        lineController.setSloppiness(.artist)
        try expect(
            lineController.currentStyle.sloppiness == .architect
                && lineController.drawingDefaultsOutlinedSloppiness
                    == .cartoonist,
            "Expected active Line defaults to ignore sloppiness changes without "
                + "overwriting the shared shape/Arrow scope"
        )

        var storedRoughStyle = AnnotationStyle.default
        storedRoughStyle.sloppiness = .cartoonist
        let storedHeadless = AnnotationElement(
            geometry: .linear(
                AnnotationLinearGeometry(
                    points: [
                        CGPoint(x: 16, y: 40),
                        CGPoint(x: 92, y: 40)
                    ],
                    route: .straight,
                    startArrowhead: .none,
                    endArrowhead: .none,
                    startBinding: nil,
                    endBinding: nil
                )
            ),
            style: storedRoughStyle
        )
        let selectedLineController = AnnotationController(
            elements: [storedHeadless]
        )
        selectedLineController.currentTool = .select
        selectedLineController.selectAll()
        let selectedLineState = DrawingToolbarState(
            annotationController: selectedLineController
        )
        selectedLineController.setSloppiness(.artist)
        try expect(
            selectedLineState.sloppiness == .unavailable
                && !selectedLineState.supportsSloppiness
                && !selectedLineState.visibleInspectorSections.contains(
                    .sloppiness
                )
                && selectedLineController.elementSnapshot[0].style.sloppiness
                    == .cartoonist,
            "Expected selected headless Lines to hide and reject sloppiness "
                + "mutations while preserving legacy stored values"
        )
        selectedLineController.setLinearEndArrowhead(.triangle)
        let selectedArrowState = DrawingToolbarState(
            annotationController: selectedLineController
        )
        selectedLineController.setSloppiness(.artist)
        var preciseArrow = selectedLineController.elementSnapshot[0]
        preciseArrow.style.sloppiness = .architect
        let restoredRoughArrow = selectedLineController.elementSnapshot[0]
        let roughArrowPixels = try renderPixels(
            elements: [restoredRoughArrow],
            renderer: AnnotationRenderer()
        )
        let preciseArrowPixels = try renderPixels(
            elements: [preciseArrow],
            renderer: AnnotationRenderer()
        )
        try expect(
            selectedArrowState.supportsSloppiness
                && selectedArrowState.visibleInspectorSections.contains(
                    .sloppiness
                )
                && restoredRoughArrow.style.sloppiness == .artist
                && roughArrowPixels != preciseArrowPixels,
            "Expected adding an arrowhead to restore Arrow roughness scope"
        )

        var lineDefaults = DrawingDefaults.default
        lineDefaults.selectTool(.line)
        lineDefaults.setSloppinessForSelectedTool(.cartoonist)
        try expect(
            lineDefaults.sloppiness == .architect
                && lineDefaults.outlinedSloppiness == .artist,
            "Expected default Line settings to stay Architect without mutating "
                + "shape/Arrow sloppiness"
        )
    }

    private static func testAnnotationSloppinessOpacityAndFamilies() throws {
        guard let uuid = UUID(uuidString: "E4EB5377-5E30-43ED-B058-B56EE5400E92") else {
            throw SelfTestError.failure("Could not create sloppiness family test UUID")
        }
        let elementID = AnnotationElementID(uuid)
        var baseStyle = AnnotationStyle(
            color: .black,
            rootWidth: 4,
            alpha: 1,
            sloppiness: .artist
        )
        baseStyle.lineCap = .butt

        let families: [AnnotationElement] = [
            AnnotationElement(
                id: elementID,
                geometry: .shape(
                    AnnotationShapeGeometry(
                        kind: .rectangle,
                        start: CGPoint(x: 8, y: 8),
                        end: CGPoint(x: 38, y: 30)
                    )
                ),
                style: baseStyle
            ),
            AnnotationElement(
                id: AnnotationElementID(
                    UUID(uuidString: "C9EA20A1-D484-4964-B119-A8C5575F351E")!
                ),
                geometry: .shape(
                    AnnotationShapeGeometry(
                        kind: .diamond,
                        start: CGPoint(x: 48, y: 8),
                        end: CGPoint(x: 78, y: 34)
                    )
                ),
                style: baseStyle
            ),
            AnnotationElement(
                id: AnnotationElementID(
                    UUID(uuidString: "A4569306-4F90-459B-886C-10AE4B2A255B")!
                ),
                geometry: .shape(
                    AnnotationShapeGeometry(
                        kind: .ellipse,
                        start: CGPoint(x: 88, y: 8),
                        end: CGPoint(x: 120, y: 34)
                    )
                ),
                style: baseStyle
            ),
            AnnotationElement.legacy(
                id: AnnotationElementID(
                    UUID(uuidString: "A77953DA-0121-496D-B272-F127DCD362DA")!
                ),
                tool: .pen,
                points: [
                    CGPoint(x: 8, y: 52),
                    CGPoint(x: 34, y: 44),
                    CGPoint(x: 62, y: 56)
                ],
                style: baseStyle
            ),
            AnnotationElement(
                id: AnnotationElementID(
                    UUID(uuidString: "52C568B1-7650-4860-BAAE-72339D888981")!
                ),
                geometry: .linear(
                    AnnotationLinearGeometry(
                        points: [
                            CGPoint(x: 72, y: 50),
                            CGPoint(x: 96, y: 42),
                            CGPoint(x: 120, y: 56)
                        ],
                        route: .curved,
                        startArrowhead: .none,
                        endArrowhead: .arrow,
                        startBinding: nil,
                        endBinding: nil
                    )
                ),
                style: baseStyle
            ),
            AnnotationElement(
                id: AnnotationElementID(
                    UUID(uuidString: "A9B01865-1F8E-4090-9FD7-BBC540B8C985")!
                ),
                geometry: .linear(
                    AnnotationLinearGeometry(
                        points: [
                            CGPoint(x: 8, y: 82),
                            CGPoint(x: 38, y: 82),
                            CGPoint(x: 38, y: 110),
                            CGPoint(x: 68, y: 110)
                        ],
                        route: .elbow,
                        startArrowhead: .none,
                        endArrowhead: .none,
                        startBinding: nil,
                        endBinding: nil,
                        isElbowAutoRouted: false
                    )
                ),
                style: baseStyle
            )
        ]

        let renderer = AnnotationRenderer()
        let artistPixels = try renderPixels(
            elements: families,
            renderer: renderer,
            width: 128,
            height: 128
        )
        let repeatedArtistPixels = try renderPixels(
            elements: families,
            renderer: renderer,
            width: 128,
            height: 128
        )
        let architectPixels = try renderPixels(
            elements: families.map {
                var element = $0
                element.style.sloppiness = .architect
                return element
            },
            renderer: renderer,
            width: 128,
            height: 128
        )
        let cartoonistPixels = try renderPixels(
            elements: families.map {
                var element = $0
                element.style.sloppiness = .cartoonist
                return element
            },
            renderer: renderer,
            width: 128,
            height: 128
        )
        try expect(
            artistPixels == repeatedArtistPixels
                && architectPixels != artistPixels
                && artistPixels != cartoonistPixels,
            "Expected Architect, Artist, and Cartoonist to render stable, visibly distinct paths "
                + "across shapes, freehand, curves, elbows, and arrows"
        )

        let calibrationID = AnnotationElementID(
            UUID(uuidString: "EB9579CB-F84E-42B5-B64D-EEBB8E3715DE")!
        )
        let calibrationShape = AnnotationShapeGeometry(
            kind: .rectangle,
            start: CGPoint(x: 24, y: 24),
            end: CGPoint(x: 72, y: 72)
        )
        func calibrationElement(_ sloppiness: AnnotationSloppiness) -> AnnotationElement {
            AnnotationElement(
                id: calibrationID,
                geometry: .shape(calibrationShape),
                style: AnnotationStyle(
                    color: .black,
                    rootWidth: 3,
                    alpha: 1,
                    sloppiness: sloppiness
                )
            )
        }
        let calibrationArchitect = try renderPixels(
            elements: [calibrationElement(.architect)],
            renderer: renderer
        )
        let calibrationArtist = try renderPixels(
            elements: [calibrationElement(.artist)],
            renderer: renderer
        )
        let calibrationCartoonist = try renderPixels(
            elements: [calibrationElement(.cartoonist)],
            renderer: renderer
        )
        let artistDifference = pixelDifferenceCount(
            calibrationArchitect,
            calibrationArtist
        )
        let cartoonistDifference = pixelDifferenceCount(
            calibrationArchitect,
            calibrationCartoonist
        )
        guard let cartoonistBounds = paintedBounds(
            calibrationCartoonist,
            width: 96,
            height: 96
        ) else {
            throw SelfTestError.failure("Expected calibrated Cartoonist shape pixels")
        }
        try expect(
            cartoonistDifference >= 80
                && cartoonistDifference > artistDifference
                && cartoonistBounds.minX >= 14
                && cartoonistBounds.minY >= 14
                && cartoonistBounds.maxX <= 82
                && cartoonistBounds.maxY <= 82,
            "Expected clearly separated Artist/Cartoonist shape strokes without excessive overshoot "
                + "(artist \(artistDifference), cartoonist \(cartoonistDifference), "
                + "bounds \(cartoonistBounds))"
        )

        var translucentStyle = baseStyle
        translucentStyle.opacity = 0.25
        let translucentLine = AnnotationElement.legacy(
            id: AnnotationElementID(
                UUID(uuidString: "11B42796-8E2D-410B-BE5C-3DB4C34FABE0")!
            ),
            tool: .line,
            points: [CGPoint(x: 8, y: 24), CGPoint(x: 88, y: 24)],
            style: translucentStyle
        )
        let translucentPixels = try renderPixels(
            elements: [translucentLine],
            renderer: renderer
        )
        let maximumAlpha = stride(from: 3, to: translucentPixels.count, by: 4)
            .map { translucentPixels[$0] }
            .max() ?? 0
        try expect(
            (55...70).contains(maximumAlpha),
            "Expected rough double strokes to apply opacity once, got alpha \(maximumAlpha)"
        )

        var highlighterStyle = baseStyle
        highlighterStyle.strokeWidth = 14
        highlighterStyle.sloppiness = .cartoonist
        let highlighter = AnnotationElement(
            id: AnnotationElementID(
                UUID(uuidString: "9ED05BC7-E650-467D-AF79-C21EB7DBB88B")!
            ),
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(
                            location: CGPoint(x: 8, y: 56),
                            pressure: nil
                        ),
                        AnnotationPointSample(
                            location: CGPoint(x: 88, y: 56),
                            pressure: nil
                        )
                    ],
                    isHighlighter: true
                )
            ),
            style: highlighterStyle
        )
        let highlighterPixels = try renderPixels(
            elements: [highlighter, highlighter],
            renderer: renderer
        )
        try expect(
            (120...135).contains(alpha(highlighterPixels, width: 96, x: 48, y: 56)),
            "Expected rough legacy highlighter passes to retain non-darkening compositing"
        )
    }

    private static func testExplicitLegacyHighlightSemantics() throws {
        var ordinaryStyle = AnnotationStyle(color: .orange, rootWidth: 4, alpha: 0.5)
        ordinaryStyle.sloppiness = .architect
        ordinaryStyle.fillStyle = .none
        let ordinaryShape = AnnotationElement(
            geometry: .shape(
                AnnotationShapeGeometry(
                    kind: .rectangle,
                    start: CGPoint(x: 12, y: 12),
                    end: CGPoint(x: 52, y: 52)
                )
            ),
            style: ordinaryStyle
        )
        let ordinaryPixels = try renderPixels(
            elements: [ordinaryShape],
            renderer: AnnotationRenderer()
        )
        try expect(
            alpha(ordinaryPixels, width: 96, x: 32, y: 32) == 0
                && !AnnotationHitTester.contains(
                    CGPoint(x: 32, y: 32),
                    in: ordinaryShape,
                    zoomScale: 1
                ),
            "Expected ordinary 50% opacity to remain an outlined, normally hit-tested shape"
        )

        var legacyStyle = ordinaryStyle
        legacyStyle.usesLegacyHighlightCompositing = true
        let legacyShape = AnnotationElement(
            geometry: ordinaryShape.geometry,
            style: legacyStyle
        )
        let legacyPixels = try renderPixels(
            elements: [legacyShape],
            renderer: AnnotationRenderer()
        )
        try expect(
            (120...135).contains(alpha(legacyPixels, width: 96, x: 32, y: 32))
                && AnnotationHitTester.contains(
                    CGPoint(x: 32, y: 32),
                    in: legacyShape,
                    zoomScale: 1
                ),
            "Expected only explicitly marked legacy highlights to force fill and non-darkening compositing"
        )

        var blueStyle = AnnotationStyle(color: .blue, rootWidth: 12, alpha: 1)
        blueStyle.sloppiness = .architect
        blueStyle.lineCap = .butt
        var redStyle = AnnotationStyle(color: .red, rootWidth: 12, alpha: 0.5)
        redStyle.sloppiness = .architect
        redStyle.lineCap = .butt
        let blueLine = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 48, y: 16), CGPoint(x: 48, y: 80)],
            style: blueStyle
        )
        let redLine = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 16, y: 48), CGPoint(x: 80, y: 48)],
            style: redStyle
        )
        let orderedPixels = try renderPixels(
            elements: [blueLine, redLine],
            renderer: AnnotationRenderer()
        )
        let crossing = pixel(orderedPixels, width: 96, x: 48, y: 48)
        try expect(
            crossing.red > 100 && crossing.blue > 100,
            "Expected ordinary translucent elements to preserve scene z-order, got \(crossing)"
        )
    }

    private static func testHighlightZOrderRendering() throws {
        var highlightStyle = AnnotationStyle(color: .yellow, rootWidth: 20, alpha: 1)
        highlightStyle.sloppiness = .architect
        highlightStyle.pressureEnabled = false
        let highlight = AnnotationElement(
            geometry: .freehand(
                AnnotationFreehandGeometry(
                    samples: [
                        AnnotationPointSample(location: CGPoint(x: 12, y: 48), pressure: nil),
                        AnnotationPointSample(location: CGPoint(x: 84, y: 48), pressure: nil)
                    ],
                    isHighlighter: true
                )
            ),
            style: highlightStyle
        )
        var solidStyle = AnnotationStyle(color: .blue, rootWidth: 20, alpha: 1)
        solidStyle.sloppiness = .architect
        solidStyle.lineCap = .butt
        let solid = AnnotationElement.legacy(
            tool: .line,
            points: [CGPoint(x: 48, y: 12), CGPoint(x: 48, y: 84)],
            style: solidStyle
        )
        let scene = AnnotationScene(elements: [highlight, solid])
        let editor = AnnotationEditor(scene: scene)
        let renderer = AnnotationRenderer()

        let behindPixels = try renderPixels(elements: scene.elements, renderer: renderer)
        let behind = pixel(behindPixels, width: 96, x: 48, y: 48)
        scene.select([highlight.id])
        editor.arrangeSelection(.bringToFront)
        let frontPixels = try renderPixels(elements: scene.elements, renderer: renderer)
        let front = pixel(frontPixels, width: 96, x: 48, y: 48)
        try expect(
            behind.blue > 200 && behind.red < 30
                && front.red > behind.red + 80
                && front.green > behind.green,
            "Expected bring-to-front to visibly move a highlighter above solid ink"
        )

        editor.arrangeSelection(.sendToBack)
        let sentBackPixels = try renderPixels(elements: scene.elements, renderer: renderer)
        try expect(
            pixel(sentBackPixels, width: 96, x: 48, y: 48).blue == behind.blue,
            "Expected send-to-back to restore the highlighter beneath solid ink"
        )

        let overlappingHighlights = try renderPixels(
            elements: [highlight, highlight],
            renderer: renderer
        )
        try expect(
            (120...135).contains(alpha(overlappingHighlights, width: 96, x: 48, y: 48)),
            "Expected contiguous highlighter runs to retain non-darkening overlap semantics"
        )
    }

    private static func testHighlighterEffectiveOpacityAndHistory() throws {
        func highlighter(
            from start: CGPoint,
            to end: CGPoint,
            color: AnnotationColorValue,
            opacity: CGFloat
        ) -> AnnotationElement {
            var style = AnnotationStyle(
                color: .yellow,
                rootWidth: 18,
                alpha: opacity,
                sloppiness: .architect
            )
            style.strokeColor = color
            return AnnotationElement(
                geometry: .freehand(
                    AnnotationFreehandGeometry(
                        samples: [
                            AnnotationPointSample(location: start, pressure: nil),
                            AnnotationPointSample(location: end, pressure: nil)
                        ],
                        isHighlighter: true
                    )
                ),
                style: style
            )
        }

        let horizontal = highlighter(
            from: CGPoint(x: 12, y: 48),
            to: CGPoint(x: 84, y: 48),
            color: .rgba(red: 1, green: 1, blue: 0, alpha: 1),
            opacity: 0.5
        )
        let verticalSameOpacity = highlighter(
            from: CGPoint(x: 48, y: 12),
            to: CGPoint(x: 48, y: 84),
            color: .rgba(red: 1, green: 0, blue: 0, alpha: 0.5),
            opacity: 1
        )
        let renderer = AnnotationRenderer()
        let sameOpacityPixels = try renderPixels(
            elements: [horizontal, verticalSameOpacity],
            renderer: renderer
        )
        let horizontalAlpha = alpha(sameOpacityPixels, width: 96, x: 24, y: 48)
        let crossingAlpha = alpha(sameOpacityPixels, width: 96, x: 48, y: 48)
        try expect(
            abs(Int(crossingAlpha) - Int(horizontalAlpha)) <= 2
                && (55...70).contains(crossingAlpha),
            "Expected equal effective highlighter opacity, including custom color alpha, "
                + "to composite once without overlap darkening"
        )

        let horizontalStrong = highlighter(
            from: CGPoint(x: 12, y: 48),
            to: CGPoint(x: 84, y: 48),
            color: .rgba(red: 1, green: 1, blue: 0, alpha: 1),
            opacity: 1
        )
        let verticalWeak = highlighter(
            from: CGPoint(x: 48, y: 12),
            to: CGPoint(x: 48, y: 84),
            color: .rgba(red: 1, green: 0, blue: 0, alpha: 1),
            opacity: 0.5
        )
        let mixedOpacityPixels = try renderPixels(
            elements: [horizontalStrong, verticalWeak],
            renderer: renderer
        )
        let reversedOpacityPixels = try renderPixels(
            elements: [verticalWeak, horizontalStrong],
            renderer: renderer
        )
        let mixedCrossing = pixel(mixedOpacityPixels, width: 96, x: 48, y: 48)
        let reversedCrossing = pixel(reversedOpacityPixels, width: 96, x: 48, y: 48)
        try expect(
            mixedCrossing.alpha > 145
                && mixedCrossing.green < reversedCrossing.green,
            "Expected mixed-opacity highlighter runs to composite separately in scene order"
        )

        let controller = AnnotationController()
        controller.currentTool = .highlighter
        controller.currentStyle.sloppiness = .architect
        controller.begin(at: CGPoint(x: 12, y: 48))
        controller.end(at: CGPoint(x: 84, y: 48))
        let beforeEdit = try renderPixels(
            elements: controller.elementSnapshot,
            renderer: renderer
        )
        controller.currentTool = .select
        _ = controller.beginSelectionInteraction(
            at: CGPoint(x: 48, y: 48),
            zoomScale: 1,
            modifiers: [],
            clickCount: 1
        )
        controller.endSelectionInteraction(
            at: CGPoint(x: 48, y: 48),
            modifiers: []
        )
        controller.beginContinuousStyleEdit(owner: .opacitySlider)
        controller.setOpacity(0.4)
        controller.endContinuousStyleEdit(owner: .opacitySlider)
        let afterEdit = try renderPixels(
            elements: controller.elementSnapshot,
            renderer: renderer
        )
        try expect(
            alpha(afterEdit, width: 96, x: 48, y: 48)
                < alpha(beforeEdit, width: 96, x: 48, y: 48) - 50,
            "Expected the inspector opacity control to visibly change highlighter output"
        )
        controller.undo()
        let afterUndo = try renderPixels(
            elements: controller.elementSnapshot,
            renderer: renderer
        )
        try expect(
            afterUndo == beforeEdit,
            "Expected one inspector-history undo to restore the visible highlighter opacity"
        )
    }

    private static func testSettingsRoundTrip() throws {
        let suiteName = "ZoomItMacSelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.failure("Could not create test UserDefaults suite")
        }
        let store = UserDefaultsSettingsStore(defaults: defaults)

        // An unset store returns the documented options-dialog defaults.
        try expect(store.load() == AppSettings.defaults, "Expected unset store to return default settings")

        var settings = AppSettings.defaults
        settings.defaultZoomFactor = 4
        settings.animateZoom = false
        settings.smoothImage = false
        settings.rootPenWidth = 12
        settings.highlighterWidth = 27
        settings.drawingToolbarNormalizedPosition = CGPoint(x: 0.2, y: 0.8)
        settings.defaultDrawingDefaults = DrawingDefaults(
            tool: .arrow,
            strokeColor: .rgba(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9),
            regularStrokeColor: .rgba(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9),
            highlighterStrokeColor: .palette(.highlighterCyan),
            penStrokeWidth: 9,
            highlighterStrokeWidth: 24,
            geometryStrokeWidth: 5,
            penOpacity: 0.55,
            geometryOpacity: 0.65,
            highlighterOpacity: 0.45,
            fillColor: .palette(.yellow),
            fillStyle: .crossHatch,
            strokePattern: .dashed,
            sloppiness: .cartoonist,
            freehandSloppiness: .artist,
            outlinedSloppiness: .cartoonist,
            opacity: 0.65,
            pressureMode: .simulated,
            smoothingEnabled: false,
            smartDrawEnabled: true,
            roundness: 14,
            linearRoute: .curved,
            lineRoute: .straight,
            arrowRoute: .curved,
            startArrowhead: .circle,
            endArrowhead: .triangle,
            arrowheadSize: .large,
            usesLegacyHighlightCompositing: true
        )
        settings.rememberLastDrawingStyle = true
        settings.lastDrawingDefaults = DrawingDefaults(
            tool: .rectangle,
            strokeColor: .palette(.green),
            regularStrokeColor: .palette(.green),
            highlighterStrokeColor: .palette(.highlighterPink),
            penStrokeWidth: 11,
            highlighterStrokeWidth: 28,
            geometryStrokeWidth: 6,
            penOpacity: 0.4,
            geometryOpacity: 0.4,
            highlighterOpacity: 0.3,
            fillColor: .rgba(red: 0.8, green: 0.7, blue: 0.6, alpha: 1),
            fillStyle: .hachure,
            strokePattern: .dotted,
            sloppiness: .architect,
            freehandSloppiness: .cartoonist,
            outlinedSloppiness: .architect,
            opacity: 0.4,
            pressureMode: .tablet,
            smoothingEnabled: true,
            smartDrawEnabled: false,
            roundness: 20,
            linearRoute: .curved,
            lineRoute: .curved,
            arrowRoute: .straight,
            startArrowhead: .bar,
            endArrowhead: .diamond,
            arrowheadSize: .medium
        )
        settings.typingFontName = "Helvetica"
        settings.typingFontPreset = .typeSetting
        settings.typingFontSize = 48
        settings.hotKeyCode = 19
        settings.hotKeyModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        settings.drawHotKeyCode = 20
        settings.drawHotKeyModifiers = NSEvent.ModifierFlags([.control, .option]).rawValue
        settings.liveHotKeyCode = 23
        settings.liveHotKeyModifiers = NSEvent.ModifierFlags([.control, .shift]).rawValue
        settings.snipHotKeyCode = 22
        settings.snipHotKeyModifiers = NSEvent.ModifierFlags([.control, .option]).rawValue
        settings.recordHotKeyCode = 23
        settings.recordHotKeyModifiers = NSEvent.ModifierFlags([.control, .command]).rawValue
        settings.panoramaHotKeyCode = 28
        settings.panoramaHotKeyModifiers = NSEvent.ModifierFlags([.control, .shift]).rawValue
        settings.breakHotKeyCode = 20
        settings.breakHotKeyModifiers = NSEvent.ModifierFlags([.command, .option]).rawValue
        settings.breakDurationMinutes = 25
        settings.breakTextColorRGB = 0x00FF00
        settings.breakBackgroundColorRGB = 0x000000
        settings.breakTimerPosition = 8
        settings.breakOpacity = 70
        settings.breakShowExpiredTime = false
        settings.breakPlaySound = true
        settings.breakSoundFile = "/tmp/break.wav"
        settings.breakBackgroundMode = 2
        settings.breakBackgroundStretch = true
        settings.breakBackgroundFile = "/tmp/break.png"
        settings.recordSystemAudio = true
        settings.recordMicrophone = true
        settings.microphoneDeviceID = "test-mic-id"
        settings.webcamEnabled = true
        settings.webcamDeviceID = "test-cam-id"
        settings.webcamPosition = 1
        settings.webcamSize = 2
        settings.webcamShape = 3
        store.save(settings)

        try expect(store.load() == settings, "Expected saved settings to round-trip through the store")

        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func testDrawingSettingsDefaultsAndMigration() throws {
        try expect(
            AppSettings.defaults.drawingToolbarNormalizedPosition == nil,
            "Expected a fresh install to use the native default toolbar placement"
        )
        try expect(
            AppSettings.defaults.defaultDrawingDefaults == .default
                && AppSettings.defaults.rootPenWidth == 7
                && AppSettings.defaults.highlighterWidth == 18
                && AppSettings.defaults.defaultDrawingDefaults.tool == .pen
                && AppSettings.defaults.defaultDrawingDefaults.startArrowhead == .none
                && AppSettings.defaults.defaultDrawingDefaults.endArrowhead == .arrow
                && AppSettings.defaults.defaultDrawingDefaults.lineRoute == .straight
                && AppSettings.defaults.defaultDrawingDefaults.arrowRoute == .curved
                && AppSettings.defaults.defaultDrawingDefaults.arrowheadSize == .medium
                && AppSettings.defaults.defaultDrawingDefaults.sloppiness == .artist
                && AppSettings.defaults.defaultDrawingDefaults.freehandSloppiness
                    == .artist
                && AppSettings.defaults.defaultDrawingDefaults.outlinedSloppiness
                    == .artist
                && !AppSettings.defaults.defaultDrawingDefaults.smartDrawEnabled,
            "Expected the legacy pen workflow, forward Arrow defaults, and opt-in Smart Draw "
                + "behavior to remain the defaults"
        )
        try expect(
            !AppSettings.defaults.rememberLastDrawingStyle
                && AppSettings.defaults.lastDrawingDefaults == nil
                && AppSettings.defaults.defaultDrawingDefaults.regularStrokeColor == nil
                && AppSettings.defaults.defaultDrawingDefaults.highlighterStrokeColor == nil,
            "Expected remembering the last style to remain opt-in"
        )

        let suiteName = "ZoomItMacSelfTest.DrawingMigration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.failure("Could not create drawing migration UserDefaults suite")
        }
        defaults.set(9.5, forKey: "rootPenWidth")
        defaults.set("Helvetica", forKey: "typingFontName")
        defaults.set(36.0, forKey: "typingFontSize")
        defaults.set(19, forKey: "drawHotKeyCode")
        defaults.set(1 << 18, forKey: "drawHotKeyModifiers")

        let migrated = UserDefaultsSettingsStore(defaults: defaults).load()
        try expect(
            migrated.rootPenWidth == 9.5
                && migrated.highlighterWidth == 18
                && migrated.typingFontName == "Helvetica"
                && migrated.typingFontPreset == .typeSetting
                && migrated.typingFontSize == 36,
            "Expected legacy pen width and typing defaults to survive migration"
        )
        try expect(
            migrated.drawHotKeyCode == 19
                && migrated.drawHotKeyModifiers == UInt(1 << 18),
            "Expected the legacy draw shortcut to survive migration"
        )
        try expect(
            migrated.defaultDrawingDefaults == .default
                && !migrated.defaultDrawingDefaults.smartDrawEnabled
                && !migrated.rememberLastDrawingStyle,
            "Expected released settings to receive the current drawing defaults"
        )

        defaults.set(
            ["x": -0.25, "y": 1.75],
            forKey: "drawingToolbarNormalizedPosition"
        )
        defaults.set(
            [
                "schemaVersion": 1,
                "tool": "unsupported",
                "strokeColor": ["palette": "green"],
                "fillStyle": "solid",
                "strokePattern": "dotted",
                "sloppiness": 99,
                "freehandSloppiness": AnnotationSloppiness.cartoonist.rawValue,
                "outlinedSloppiness": AnnotationSloppiness.architect.rawValue,
                "opacity": 4.0,
                "penStrokeWidth": -4.0,
                "highlighterStrokeWidth": 400.0,
                "geometryStrokeWidth": Double.nan,
                "lineRoute": "elbow",
                "arrowRoute": "elbow",
                "arrowheadSize": "unsupported",
                "endArrowhead": "triangle"
            ],
            forKey: "defaultDrawingDefaults"
        )
        let normalized = UserDefaultsSettingsStore(defaults: defaults).load()
        try expect(
            normalized.drawingToolbarNormalizedPosition == CGPoint(x: 0, y: 1),
            "Expected stored toolbar coordinates to normalize into the display-relative range"
        )
        try expect(
            normalized.defaultDrawingDefaults.tool == .pen
                && normalized.defaultDrawingDefaults.strokeColor == .palette(.green)
                && normalized.defaultDrawingDefaults.fillStyle == .solid
                && normalized.defaultDrawingDefaults.strokePattern == .dotted
                && normalized.defaultDrawingDefaults.sloppiness == .cartoonist
                && normalized.defaultDrawingDefaults.freehandSloppiness == .cartoonist
                && normalized.defaultDrawingDefaults.outlinedSloppiness == .architect
                && normalized.defaultDrawingDefaults.opacity == 1
                && normalized.defaultDrawingDefaults.penStrokeWidth == 1
                && normalized.defaultDrawingDefaults.highlighterStrokeWidth == 64
                && normalized.defaultDrawingDefaults.geometryStrokeWidth == nil
                && normalized.defaultDrawingDefaults.lineRoute == .straight
                && normalized.defaultDrawingDefaults.arrowRoute == .curved
                && normalized.defaultDrawingDefaults.arrowheadSize == .medium
                && normalized.defaultDrawingDefaults.endArrowhead == .triangle,
            "Expected the current drawing schema to clamp finite values and reject malformed fields"
        )

        defaults.set(
            [
                "schemaVersion": 99,
                "tool": "arrow",
                "startArrowhead": "circle",
                "endArrowhead": "diamond"
            ],
            forKey: "defaultDrawingDefaults"
        )
        let unsupportedSchema =
            UserDefaultsSettingsStore(defaults: defaults).load()
        try expect(
            unsupportedSchema.defaultDrawingDefaults == .default,
            "Expected unknown drawing schemas to fall back instead of running unreleased migrations"
        )

        var persistedElbowDefaults = AppSettings.defaults
        persistedElbowDefaults.defaultDrawingDefaults.lineRoute = .elbow
        persistedElbowDefaults.defaultDrawingDefaults.arrowRoute = .elbow
        persistedElbowDefaults.rememberLastDrawingStyle = true
        persistedElbowDefaults.lastDrawingDefaults =
            persistedElbowDefaults.defaultDrawingDefaults
        UserDefaultsSettingsStore(defaults: defaults).save(
            persistedElbowDefaults
        )
        let normalizedPersistedElbows =
            UserDefaultsSettingsStore(defaults: defaults).load()
        try expect(
            normalizedPersistedElbows.defaultDrawingDefaults.lineRoute
                == .straight
                && normalizedPersistedElbows.defaultDrawingDefaults.arrowRoute
                    == .curved
                && normalizedPersistedElbows.lastDrawingDefaults?.lineRoute
                    == .straight
                && normalizedPersistedElbows.lastDrawingDefaults?.arrowRoute
                    == .curved,
            "Expected persisted default and remembered Elbow values to normalize to supported routes"
        )

        let arrowheads = DrawingInspectorControlMapping.arrowheads
        let store = UserDefaultsSettingsStore(defaults: defaults)
        for startArrowhead in arrowheads {
            for endArrowhead in arrowheads {
                var settings = AppSettings.defaults
                settings.defaultDrawingDefaults.tool = .arrow
                settings.defaultDrawingDefaults.startArrowhead = startArrowhead
                settings.defaultDrawingDefaults.endArrowhead = endArrowhead
                settings.rememberLastDrawingStyle = true
                settings.lastDrawingDefaults = settings.defaultDrawingDefaults
                store.save(settings)

                let reloaded = store.load()
                try expect(
                    reloaded.defaultDrawingDefaults.startArrowhead == startArrowhead
                        && reloaded.defaultDrawingDefaults.endArrowhead == endArrowhead
                        && reloaded.lastDrawingDefaults?.startArrowhead == startArrowhead
                        && reloaded.lastDrawingDefaults?.endArrowhead == endArrowhead,
                    "Expected versioned drawing and remembered defaults to round-trip "
                        + "\(startArrowhead)/\(endArrowhead) arrowheads exactly"
                )
                try expect(
                    (defaults.dictionary(forKey: "defaultDrawingDefaults")?["schemaVersion"]
                        as? NSNumber)?.intValue == 1
                        && (defaults.dictionary(forKey: "lastDrawingDefaults")?["schemaVersion"]
                            as? NSNumber)?.intValue == 1,
                    "Expected saved drawing defaults to include the current schema version"
                )
            }
        }

        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func testFirstLaunchFlag() throws {
        let suiteName = "ZoomItMacSelfTest.FirstLaunch.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.failure("Could not create test UserDefaults suite")
        }
        let store = UserDefaultsSettingsStore(defaults: defaults)

        // A fresh store reports first launch so the app opens Settings (issue #21).
        try expect(!store.hasCompletedFirstLaunch, "Expected fresh store to report first launch not completed")

        store.markFirstLaunchCompleted()
        try expect(store.hasCompletedFirstLaunch, "Expected first launch to be marked completed")

        // The flag must persist so subsequent launches do not reopen Settings.
        let reloaded = UserDefaultsSettingsStore(defaults: defaults)
        try expect(reloaded.hasCompletedFirstLaunch, "Expected first-launch completion to persist across store instances")

        defaults.removePersistentDomain(forName: suiteName)

        // Migration: a user upgrading from a build without the flag but with prior
        // ZoomIt preferences must be treated as returning, not a fresh install.
        let legacySuite = "ZoomItMacSelfTest.FirstLaunchLegacy.\(UUID().uuidString)"
        guard let legacyDefaults = UserDefaults(suiteName: legacySuite) else {
            throw SelfTestError.failure("Could not create legacy test UserDefaults suite")
        }
        legacyDefaults.set(11281, forKey: "NSStatusItem Preferred Position com.sysinternals.ZoomIt.statusItem")
        let legacyStore = UserDefaultsSettingsStore(defaults: legacyDefaults)
        try expect(legacyStore.hasCompletedFirstLaunch, "Expected prior status-item position default to count as a completed first launch")
        legacyDefaults.removePersistentDomain(forName: legacySuite)
    }

    #if !ZOOMIT_APP_STORE
    private static func testDemoTypeSettingsRoundTrip() throws {
        let suiteName = "ZoomItMacSelfTest.DemoType.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.failure("Could not create DemoType test UserDefaults suite")
        }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = AppSettings.defaults
        settings.demoTypeHotKeyCode = 15
        settings.demoTypeHotKeyModifiers = NSEvent.ModifierFlags([.control, .option]).rawValue
        settings.demoTypeFile = "/tmp/demo-type.txt"
        settings.demoTypeSpeed = 84
        settings.demoTypeUserDriven = true
        store.save(settings)

        let loaded = store.load()
        try expect(loaded.demoTypeHotKeyCode == 15, "Expected DemoType hotkey code to round-trip")
        try expect(loaded.demoTypeHotKeyModifiers == settings.demoTypeHotKeyModifiers, "Expected DemoType hotkey modifiers to round-trip")
        try expect(loaded.demoTypeFile == "/tmp/demo-type.txt", "Expected DemoType file to round-trip")
        try expect(loaded.demoTypeSpeed == 84, "Expected DemoType speed to round-trip")
        try expect(loaded.demoTypeUserDriven, "Expected DemoType user-driven setting to round-trip")

        defaults.set(250, forKey: "demoTypeSpeed")
        try expect(store.load().demoTypeSpeed == 100, "Expected DemoType speed to clamp to the Windows slider maximum")

        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func testDemoTypeScriptCleaningAndTokens() throws {
        let cleaned = DemoTypeController.cleanForTesting("\u{0001}\nhello\n[end]\nworld\n[paste]\nchunk\n[/paste]\n[end]\n   ")
        try expect(cleaned == "hello[end]world\n[paste]chunk[/paste][end]", "Unexpected DemoType cleaned script: \(cleaned)")

        let tokens = DemoTypeController.tokensForTesting("a[pause:2][enter][up][down][left][right][paste]hi[/paste][end]")
        try expect(tokens == [
            .text("a"),
            .pause(2),
            .key("enter"),
            .key("up"),
            .key("down"),
            .key("left"),
            .key("right"),
            .paste("hi"),
            .end
        ], "Unexpected DemoType tokens: \(tokens)")
    }

    private static func testDemoTypeScriptDecoding() throws {
        try expect(DemoTypeController.decodeForTesting(Data([0xEF, 0xBB, 0xBF]) + Data("utf8".utf8)) == "utf8", "Expected UTF-8 BOM DemoType text")
        try expect(DemoTypeController.decodeForTesting(Data([0xFF, 0xFE, 0x6C, 0x00, 0x65, 0x00])) == "le", "Expected UTF-16LE DemoType text")
        try expect(DemoTypeController.decodeForTesting(Data([0xFE, 0xFF, 0x00, 0x62, 0x00, 0x65])) == "be", "Expected UTF-16BE DemoType text")
    }

    private static func testDemoTypeTypingDelayRange() throws {
        try expect(DemoTypeController.typingDelayRangeForTesting(slider: 55) == 1...110, "Expected midpoint DemoType delay to match Windows speed +/- speed")
        try expect(DemoTypeController.typingDelayRangeForTesting(slider: 100) == 1...20, "Expected fastest DemoType delay range")
        try expect(DemoTypeController.typingDelayRangeForTesting(slider: 10) == 1...200, "Expected slowest DemoType delay range")
    }

    private static func testDemoTypeUserDrivenStepStopsAtEnd() throws {
        let script = "ab[end]cd[end]"
        let first = DemoTypeController.userDrivenStepForTesting(script, offset: 0)
        try expect(first == DemoTypeController.UserDrivenStepResult(token: .text("a"), ended: false, nextOffset: 1), "Expected one user key to emit one DemoType token")

        let end = DemoTypeController.userDrivenStepForTesting(script, offset: 2)
        try expect(end == DemoTypeController.UserDrivenStepResult(token: .end, ended: true, nextOffset: 7), "Expected [end] to stop the active user-driven DemoType entry")

        try expect(DemoTypeController.completedUserDrivenEntryOffsetForTesting(script, startOffset: 7) == script.count, "Expected final [end] to leave DemoType at EOF instead of wrapping in the active entry")
        try expect(DemoTypeController.completedUserDrivenEntryOffsetForTesting("abc", startOffset: 0) == 0, "Expected scripts without [end] to wrap after EOF")
    }
    #endif

    private static func testStaticZoomStaysAtOneX() throws {
        // Windows ZoomIt keeps static zoom active when the user zooms all the
        // way out to 1x; only Esc/right-click exits. Live zoom still exits at
        // the floor.
        try expect(ModeCoordinator.exitsOnZoomOutFloor(mode: .staticZoom) == false,
                   "Expected static zoom to stay active at 1x instead of exiting")
        try expect(ModeCoordinator.exitsOnZoomOutFloor(mode: .liveZoom),
                   "Expected live zoom to exit when zoomed out to 1x")
        try expect(ModeCoordinator.exitsOnZoomOutFloor(mode: .typing),
                   "Expected typing (live zoom sub-mode) to exit when zoomed out to 1x")
    }

    /// The break timer view uses a flipped coordinate system. Drawing a
    /// background image there without flip awareness renders it upside down.
    /// Verify BreakTimerLayout.drawBackground keeps a vertically asymmetric
    /// image right-side up when drawn through a real flipped view.
    private static func testBreakTimerBackgroundNotFlipped() throws {
        let dim = 16
        // Source image: top half red, bottom half blue in its natural (image)
        // orientation. NSImage.lockFocus uses a bottom-left origin, so the red
        // upper half is filled at the higher y range.
        let source = NSImage(size: NSSize(width: dim, height: dim))
        source.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: dim / 2, width: dim, height: dim / 2).fill()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: dim, height: dim / 2).fill()
        source.unlockFocus()

        let host = FlippedBackgroundHostView(frame: NSRect(x: 0, y: 0, width: dim, height: dim))
        host.image = source
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SelfTestError.failure("Could not create caching bitmap for flipped host view")
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        // Sample in the rep's real pixel space (it may be Retina 2x). Row 0 is
        // the top of the rendered view. With flip-aware drawing the top of the
        // image (red) must appear at the top; a regression would show blue there.
        let midX = rep.pixelsWide / 2
        guard let top = rep.colorAt(x: midX, y: 1),
              let bottom = rep.colorAt(x: midX, y: rep.pixelsHigh - 2) else {
            throw SelfTestError.failure("Could not sample break timer background pixels")
        }
        try expect(top.redComponent > 0.5 && top.blueComponent < 0.5,
                   "Expected break timer background top to stay red (right-side up), got \(top)")
        try expect(bottom.blueComponent > 0.5 && bottom.redComponent < 0.5,
                   "Expected break timer background bottom to stay blue (right-side up), got \(bottom)")
    }

    /// The panorama region rectangle is drawn in blue to stay distinct from the
    /// orange screen-recording border. The shared selection view defaults to
    /// white (snip/record) but the panorama selector requests blue; verify the
    /// requested border colour is actually rendered.
    private static func testPanoramaSelectionBorderColor() throws {
        let dim = 40
        // A solid grey backing image for the selector.
        guard let context = CGContext(
            data: nil, width: dim, height: dim, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SelfTestError.failure("Could not create selector backing context")
        }
        context.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: dim, height: dim))
        guard let image = context.makeImage() else {
            throw SelfTestError.failure("Could not create selector backing image")
        }

        let selection = CGRect(x: 8, y: 8, width: 24, height: 24)

        func borderIsBlue(_ view: SnipSelectionView) throws -> Bool {
            guard let rep = view.renderForTesting(selection: selection) else {
                throw SelfTestError.failure("Selector render returned no bitmap")
            }
            let scaleX = rep.pixelsWide / dim
            let scaleY = rep.pixelsHigh / dim
            // Sample the middle of the top border edge of the selection rect.
            let px = Int(selection.midX) * scaleX
            let py = Int(selection.minY) * scaleY
            guard let c = rep.colorAt(x: px, y: py) else {
                throw SelfTestError.failure("Could not sample selector border pixel")
            }
            return c.blueComponent > 0.5 && c.redComponent < 0.4
        }

        let blueView = SnipSelectionView(frame: CGRect(x: 0, y: 0, width: dim, height: dim), image: image, borderColor: .systemBlue)
        try expect(try borderIsBlue(blueView), "Expected panorama selection border to render blue")

        let whiteView = SnipSelectionView(frame: CGRect(x: 0, y: 0, width: dim, height: dim), image: image)
        try expect(try !borderIsBlue(whiteView), "Expected default snip selection border to remain non-blue (white)")
    }

    private static func testPresentedWindowLifecycleOrdering() throws {
        var events: [String] = []
        OverlayPresentedWindowLifecycle.perform(
            prepareAccessories: {
                events.append("suppress accessories")
                events.append("lower overlay")
            },
            showSystemCursor: {
                events.append("show cursor")
            },
            present: {
                events.append("present")
            },
            restoreAccessories: {
                events.append("restore overlay")
                events.append("restore accessories")
            },
            reapplyCursorPolicy: {
                events.append("reapply cursor policy")
            }
        )
        try expect(
            events == [
                "suppress accessories",
                "lower overlay",
                "show cursor",
                "present",
                "restore overlay",
                "restore accessories",
                "reapply cursor policy"
            ],
            "Expected save presentation to show the cursor only after suppressing accessories, "
                + "then restore accessories before reapplying cursor policy"
        )
    }

    private static func testOverlayRegionSnipTeardown() throws {
        let canvas = try makeCanvas(annotationController: AnnotationController())
        var completionCount = 0
        canvas.beginRegionSnip(action: .copyImage) {
            completionCount += 1
        }
        canvas.prepareForClose()
        canvas.prepareForClose()
        try expect(
            completionCount == 1,
            "Expected overlay close preparation to finish an active region snip exactly once"
        )

        canvas.beginRegionSnip(action: .saveImage) {
            completionCount += 1
        }
        canvas.prepareForClose()
        try expect(
            completionCount == 2,
            "Expected region snip state to clear so a later snip can finish independently"
        )
    }

    /// Escape during the scrolling panorama capture must cancel the run, but
    /// only while it is actively capturing, and repeated Escapes are ignored.
    private static func testPanoramaEscapeCancel() throws {
        try expect(PanoramaController.shouldCancelOnEscape(isCapturing: true, alreadyCancelled: false),
                   "Expected Escape to cancel an active panorama capture")
        try expect(PanoramaController.shouldCancelOnEscape(isCapturing: false, alreadyCancelled: false) == false,
                   "Expected Escape to be ignored when not capturing")
        try expect(PanoramaController.shouldCancelOnEscape(isCapturing: true, alreadyCancelled: true) == false,
                   "Expected a repeated Escape to be ignored once already cancelled")
    }

    /// The break timer suppresses the screen saver by holding a display-sleep
    /// assertion. Verify the assertion is acquired once on begin, released on
    /// end, and that both operations are idempotent.
    private static func testIdleSleepAssertionLifecycle() throws {
        var created = 0
        var released = 0
        let assertion = IdleSleepAssertion(
            create: { _ in created += 1; return IOPMAssertionID(created) },
            release: { _ in released += 1 }
        )

        try expect(assertion.isActive == false, "Expected assertion to start inactive")

        assertion.begin(reason: "test")
        try expect(assertion.isActive, "Expected assertion active after begin")
        try expect(created == 1, "Expected exactly one assertion created")

        // begin is idempotent: a second begin must not create another.
        assertion.begin(reason: "test")
        try expect(created == 1, "Expected begin to be idempotent (no second create)")

        assertion.end()
        try expect(assertion.isActive == false, "Expected assertion inactive after end")
        try expect(released == 1, "Expected exactly one assertion released")

        // end is idempotent: a second end must not release again.
        assertion.end()
        try expect(released == 1, "Expected end to be idempotent (no second release)")
    }

    /// The menu-bar menu broadly follows the Windows ZoomIt tray order (Options
    /// first, modes, then Check Permissions and Quit), with Panorama as a
    /// macOS-only extra after Record and the Break Timer placed below Panorama
    /// Capture.
    private static func testStatusMenuOrderMatchesWindows() throws {
        let titles = AppDelegate.statusMenuEntries()
            .filter { !$0.isSeparator }
            .map(\.title)

        // Confirm the items appear in the expected relative order.
        let expectedOrder = [
            "Settings…",        // Options
            "Draw",
            "Static Zoom",      // Zoom
            "Live Zoom",
            "Record Screen",    // Record
            "Panorama Capture", // macOS-only, after Record
            "Break Timer",      // moved below Panorama Capture
            "Check Permissions",
            "Quit"
        ]

        let positions = expectedOrder.map { titles.firstIndex(of: $0) }
        for (label, index) in zip(expectedOrder, positions) {
            try expect(index != nil, "Expected status menu to contain '\(label)'")
        }
        let resolved = positions.compactMap { $0 }
        try expect(resolved == resolved.sorted(),
                   "Expected status menu items to follow the expected order, got \(titles)")

        // Break Timer must come after Panorama Capture.
        if let breakIndex = titles.firstIndex(of: "Break Timer"),
           let panoramaIndex = titles.firstIndex(of: "Panorama Capture") {
            try expect(breakIndex > panoramaIndex,
                       "Expected Break Timer to be below Panorama Capture, got \(titles)")
        } else {
            throw SelfTestError.failure("Expected both Break Timer and Panorama Capture menu items")
        }

        // Options must be first and Quit last, as on Windows.
        try expect(titles.first == "Settings…", "Expected Options/Settings to be the first menu item")
        try expect(titles.last == "Quit", "Expected Quit to be the last menu item")
    }

    /// Changing the clip transition popup from Fade to Black to Fade to White
    /// must update the existing append boundary (previously it stayed black
    /// because the transition was captured only at append time). Delete-seam
    /// joins keep their own transition.
    private static func testClipTransitionUpdatesOnChange() throws {
        typealias Transition = VideoClipEditorController.Transition

        // One append boundary starting as Fade to Black; switch to Fade to White.
        let updated = VideoClipEditorController.updatedJoinTransitions(
            current: [.fadeBlack],
            isAppendJoin: [true],
            newTransition: .fadeWhite
        )
        try expect(updated == [.fadeWhite], "Expected append boundary to switch to Fade to White, got \(updated)")

        // Mixed: an append boundary adopts the new transition, a delete seam
        // (not an append) keeps its existing value.
        let mixed = VideoClipEditorController.updatedJoinTransitions(
            current: [.fadeBlack, Transition.none],
            isAppendJoin: [true, false],
            newTransition: .fadeWhite
        )
        try expect(mixed == [.fadeWhite, Transition.none],
                   "Expected only the append boundary to change, got \(mixed)")
    }

    /// Dragging the webcam picture-in-picture must keep the grabbed point under
    /// the cursor: the new window origin is the cursor position minus the grab
    /// offset within the window.
    private static func testWebcamOverlayDragOrigin() throws {
        // Window was at origin (100, 200) with size 160x120; the user grabbed a
        // point 40,30 inside it, so grabOffset = (40, 30). Grab point on screen
        // was (140, 230).
        let grabOffset = CGSize(width: 40, height: 30)

        // No movement: cursor still at the original grab point -> origin unchanged.
        let unchanged = WebcamOverlayController.draggedWindowOrigin(mouseOnScreen: CGPoint(x: 140, y: 230), grabOffset: grabOffset)
        try expect(unchanged == CGPoint(x: 100, y: 200), "Expected unchanged origin when cursor hasn't moved, got \(unchanged)")

        // Move the cursor by (+50, -70); the window origin should move the same.
        let moved = WebcamOverlayController.draggedWindowOrigin(mouseOnScreen: CGPoint(x: 190, y: 160), grabOffset: grabOffset)
        try expect(moved == CGPoint(x: 150, y: 130), "Expected dragged origin to track the cursor, got \(moved)")
    }

    /// Trimming an existing video and saving under a new name must NOT delete
    /// the user's original file (it did, because the source was moved). When no
    /// edits were made the editor returns the original URL and we copy it;
    /// otherwise it returns an exported temp file that we move.
    private static func testTrimSavePreservesOriginal() throws {
        let original = URL(fileURLWithPath: "/tmp/original.mp4")

        // No edits: editor hands back the original URL -> copy (preserve source).
        try expect(RecordingController.trimSaveAction(editedURL: original, originalURL: original) == .copy,
                   "Expected an unedited trim save to copy the original, preserving it")

        // Edited: editor exported a temp file -> move it (original untouched).
        let exported = URL(fileURLWithPath: "/tmp/ZoomIt-edit-1234.mp4")
        try expect(RecordingController.trimSaveAction(editedURL: exported, originalURL: original) == .move,
                   "Expected an edited trim save to move the exported temp file")
    }

    /// The Settings dialog must stay on top like the Windows Options dialog so
    /// it can't get hidden behind other windows (which would leave ZoomIt's
    /// hotkeys suspended and the app apparently unresponsive).
    private static func testSettingsWindowStaysOnTop() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        // Sanity: a normal window is at the normal level and hides on deactivate
        // is off by default; ensure our configuration changes the level.
        SettingsWindowController.configureAlwaysOnTop(window)
        try expect(window.level == .floating, "Expected settings window to float above other windows")
        try expect(window.hidesOnDeactivate == false, "Expected settings window not to hide when the app deactivates")
    }

    /// The Options dialog lists its panes in a sidebar, which needs a
    /// resolvable SF Symbol per pane. A typo'd symbol name yields a nil image
    /// and a silently blank icon, so check every pane.
    private static func testSettingsPaneSymbolsResolve() throws {
        for title in SettingsWindowController.settingsTabTitles {
            let symbol = SettingsWindowController.paneSymbolName(for: title)
            try expect(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "Expected settings pane \"\(title)\" to have a resolvable SF Symbol, got \"\(symbol)\""
            )
        }
    }

    /// Windows keeps static-zoom and live-zoom settings on separate tabs (the
    /// Zoom tab is static-only). Verify the Mac Options dialog exposes a
    /// distinct "Live Zoom" tab immediately after "Zoom".
    private static func testZoomAndLiveZoomAreSeparateTabs() throws {
        let titles = SettingsWindowController.settingsTabTitles
        guard let zoomIndex = titles.firstIndex(of: "Zoom") else {
            throw SelfTestError.failure("Expected a Zoom tab in the Options dialog")
        }
        try expect(titles.contains("Live Zoom"), "Expected a separate Live Zoom tab")
        try expect(titles.firstIndex(of: "Live Zoom") == zoomIndex + 1,
                   "Expected Live Zoom to be its own tab right after Zoom, got \(titles)")
    }

    private static func testDistributionSpecificSettingsTabs() throws {
        let hasDemoType = SettingsWindowController.settingsTabTitles.contains("DemoType")
        try expect(
            hasDemoType != DistributionChannel.isAppStore,
            "Expected DemoType to be present only in the Homebrew settings surface"
        )
    }

    private static func testModalActivationCommandGating() throws {
        let coordinator = ModeActivationCoordinator()
        guard let activation = coordinator.reserve(
            .liveZoom,
            expecting: .idle,
            currentMode: .idle
        ) else {
            throw SelfTestError.failure(
                "Expected Live Zoom startup to reserve modal ownership"
            )
        }

        let blockedCommands: [AppCommand] = [
            .activateStaticZoom,
            .activateLiveZoom,
            .activateDrawWithoutZoom,
            .snipRegion(save: false),
            .snipRegion(save: true),
            .snipOcr,
            .toggleBreakTimer,
            .startPanorama(save: false),
            .toggleDemoMirror(scope: .screen),
            .zoomIn,
            .zoomOutOrExit,
            .toggleTyping(rightAligned: false)
        ]
        for command in blockedCommands {
            try expect(
                coordinator.disposition(
                    for: command,
                    recordingIsActive: false
                ) == .block,
                "Expected \(command) to be blocked during Live Zoom startup"
            )
        }
        try expect(
            coordinator.disposition(
                for: .toggleRecording(region: false),
                recordingIsActive: false
            ) == .block,
            "Expected a new recording startup to be blocked while modal ownership is reserved"
        )
        try expect(
            coordinator.disposition(
                for: .toggleRecording(region: false),
                recordingIsActive: true
            ) == .allow,
            "Expected stopping an active recording to remain available during cancellable startup"
        )
        try expect(
            coordinator.disposition(
                for: .clear,
                recordingIsActive: false
            ) == .allow,
            "Expected non-activation drawing commands to remain independent"
        )
        try expect(
            coordinator.disposition(
                for: .exit,
                recordingIsActive: false
            ) == .cancelCurrent,
            "Expected Escape to invalidate cancellable Live Zoom startup"
        )
        try expect(
            coordinator.updateExpectedMode(
                for: activation,
                currentMode: .idle,
                to: .liveZoom
            )
                && coordinator.owns(activation, currentMode: .liveZoom)
                && coordinator.disposition(
                    for: .toggleBreakTimer,
                    recordingIsActive: false
                ) == .block,
            "Expected Live Zoom to retain activation ownership after presenting its startup overlay"
        )
    }

    private static func testExternalRegionSelectorAccessoryPolicy() throws {
        for flow in ExternalRegionSelectorFlow.allCases {
            try expect(
                ExternalRegionSelectorAccessoryPolicy.shouldRestore(
                    flow: flow,
                    expectedMode: .drawOnly,
                    currentMode: .drawOnly,
                    isOverlayPresented: true
                ),
                "Expected \(flow) completion and cancellation to restore active drawing accessories"
            )
            try expect(
                ExternalRegionSelectorAccessoryPolicy.shouldRestore(
                    flow: flow,
                    expectedMode: .staticZoom,
                    currentMode: .staticZoom,
                    isOverlayPresented: true
                ),
                "Expected stale \(flow) selector teardown to restore when the overlay generation remains active"
            )
            try expect(
                !ExternalRegionSelectorAccessoryPolicy.shouldRestore(
                    flow: flow,
                    expectedMode: .drawOnly,
                    currentMode: .idle,
                    isOverlayPresented: false
                ),
                "Expected \(flow) teardown not to restore after the overlay exits"
            )
            try expect(
                !ExternalRegionSelectorAccessoryPolicy.shouldRestore(
                    flow: flow,
                    expectedMode: .drawOnly,
                    currentMode: .staticZoom,
                    isOverlayPresented: true
                ),
                "Expected \(flow) stale completion not to restore after a mode change"
            )
        }
    }

    private static func testModalActivationBreakAndOcrRaces() throws {
        let coordinator = ModeActivationCoordinator()
        guard let liveActivation = coordinator.reserve(
            .liveZoom,
            expecting: .idle,
            currentMode: .idle
        ) else {
            throw SelfTestError.failure("Expected Live Zoom reservation")
        }
        try expect(
            coordinator.reserve(
                .breakTimer,
                expecting: .idle,
                currentMode: .idle
            ) == nil
                && coordinator.disposition(
                    for: .toggleBreakTimer,
                    recordingIsActive: false
                ) == .block,
            "Expected Break Timer to lose deterministically to in-flight Live Zoom"
        )

        _ = coordinator.cancelCurrent()
        guard let breakActivation = coordinator.reserve(
            .breakTimer,
            expecting: .idle,
            currentMode: .idle
        ) else {
            throw SelfTestError.failure(
                "Expected Break Timer to reserve after Live Zoom cancellation"
            )
        }
        var presentedMode = AppMode.idle
        guard coordinator.updateExpectedMode(
            for: breakActivation,
            currentMode: presentedMode,
            to: .breakTimer
        ) else {
            throw SelfTestError.failure(
                "Expected Break Timer to retain ownership through presentation"
            )
        }
        presentedMode = .breakTimer
        if coordinator.owns(liveActivation, currentMode: presentedMode) {
            presentedMode = .liveZoom
        }
        try expect(
            !coordinator.owns(liveActivation, currentMode: .idle)
                && coordinator.finish(liveActivation) == nil
                && coordinator.owns(
                    breakActivation,
                    currentMode: presentedMode
                )
                && presentedMode == .breakTimer,
            "Expected stale Live Zoom completion not to release or overwrite the presented Break Timer mode"
        )
        _ = coordinator.cancelCurrent()

        guard let firstSnip = coordinator.reserve(
            .snip,
            expecting: .idle,
            currentMode: .idle
        ) else {
            throw SelfTestError.failure("Expected OCR snip reservation")
        }
        try expect(
            coordinator.disposition(
                for: .snipRegion(save: false),
                recordingIsActive: false
            ) == .block
                && coordinator.disposition(
                    for: .snipOcr,
                    recordingIsActive: false
                ) == .block,
            "Expected region and OCR snip commands to share one activation gate"
        )
        _ = coordinator.cancelCurrent()
        guard let currentSnip = coordinator.reserve(
            .snip,
            expecting: .idle,
            currentMode: .idle
        ) else {
            throw SelfTestError.failure("Expected replacement OCR snip reservation")
        }
        try expect(
            coordinator.finish(firstSnip) == nil
                && coordinator.owns(currentSnip, currentMode: .idle),
            "Expected stale OCR capture completion not to clear a newer snip reservation"
        )
        _ = coordinator.finish(currentSnip)
    }

    private static func testModalActivationStaleCompletionIsolation() async throws {
        let coordinator = ModeActivationCoordinator()
        let resources = LiveZoomActivationResources<
            ModeActivationCoordinator.Token,
            SelfTestLiveZoomActivationSession
        >()
        let staleSuccessGate = SelfTestAsyncGate()
        let staleSession = SelfTestLiveZoomActivationSession()
        guard let staleActivation = coordinator.reserve(
            .liveZoom,
            expecting: .idle,
            currentMode: .idle
        ), resources.begin(staleActivation) else {
            throw SelfTestError.failure(
                "Expected a stale Live Zoom activation reservation"
            )
        }
        try expect(
            resources.markOverlayPresented(for: staleActivation)
                && resources.attach(staleSession, to: staleActivation),
            "Expected the first activation to own its startup resources"
        )
        let staleSuccessTask = Task { @MainActor in
            try await staleSuccessGate.wait()
            let committed = coordinator.owns(
                staleActivation,
                currentMode: .idle
            ) && resources.commit(staleSession, for: staleActivation)
            if !committed {
                await staleSession.stop()
            }
            return committed
        }
        try await staleSuccessGate.waitUntilEntered()

        _ = coordinator.cancelCurrent()
        guard let staleCleanup = resources.finish(staleActivation) else {
            throw SelfTestError.failure(
                "Expected cancellation to detach stale Live Zoom resources"
            )
        }
        if let session = staleCleanup.session {
            await session.stop()
        }

        let currentSession = SelfTestLiveZoomActivationSession()
        guard let currentActivation = coordinator.reserve(
            .liveZoom,
            expecting: .idle,
            currentMode: .idle
        ), resources.begin(currentActivation) else {
            throw SelfTestError.failure(
                "Expected a newer Live Zoom activation after cancellation"
            )
        }
        _ = resources.markOverlayPresented(for: currentActivation)
        _ = resources.attach(currentSession, to: currentActivation)

        staleSuccessGate.open()
        let staleCommitted = try await withSelfTestTimeout(
            "stale Live Zoom completion"
        ) {
            try await staleSuccessTask.value
        }
        try expect(
            !staleCommitted
                && coordinator.owns(currentActivation, currentMode: .idle)
                && resources.isCurrent(currentActivation)
                && resources.session === currentSession
                && staleSession.stopCount >= 1
                && currentSession.stopCount == 0,
            "Expected stale completion to clean only its local session and preserve the newer owner"
        )
        _ = coordinator.finish(currentActivation)
        if let session = resources.cancel()?.session {
            await session.stop()
        }
    }

    private static func testLiveZoomExitDuringStartup() async throws {
        let coordinator = ModeActivationCoordinator()
        let resources = LiveZoomActivationResources<
            ModeActivationCoordinator.Token,
            SelfTestLiveZoomActivationSession
        >()
        let startupGate = SelfTestAsyncGate()
        let session = SelfTestLiveZoomActivationSession()
        guard let activation = coordinator.reserve(
            .liveZoom,
            expecting: .idle,
            currentMode: .idle
        ), resources.begin(activation) else {
            throw SelfTestError.failure(
                "Expected an exit-during-startup reservation"
            )
        }
        _ = resources.markOverlayPresented(for: activation)
        _ = resources.attach(session, to: activation)
        let startupTask = Task { @MainActor in
            try await startupGate.wait()
            return coordinator.owns(
                activation,
                currentMode: .idle
            ) && resources.commit(session, for: activation)
        }
        try await startupGate.waitUntilEntered()

        try expect(
            coordinator.disposition(
                for: .exit,
                recordingIsActive: false
            ) == .cancelCurrent,
            "Expected Exit to cancel Live Zoom startup ownership"
        )
        _ = coordinator.cancelCurrent()
        guard let cancellation = resources.finish(activation) else {
            throw SelfTestError.failure(
                "Expected exit to detach the in-flight Live Zoom resources"
            )
        }
        if let ownedSession = cancellation.session {
            await ownedSession.stop()
        }

        try expect(
            cancellation.overlayPresented
                && !cancellation.wasActive
                && !resources.isStarting
                && !resources.isCurrent(activation)
                && resources.session == nil
                && session.stopCount == 1,
            "Expected exit during startup to invalidate ownership and stop its pending session"
        )

        startupGate.open()
        let startupCommitted = try await withSelfTestTimeout(
            "cancelled Live Zoom startup"
        ) {
            try await startupTask.value
        }
        try expect(
            !startupCommitted && session.stopCount == 1,
            "Expected cancelled startup completion not to publish or touch another mode"
        )
    }

    /// The blank-screen sketch pad is triggered with Ctrl+W / Ctrl+K while
    /// drawing (matching the corrected Draw-tab help), leaving plain W/K for the
    /// white/black pen and Shift+W/K for the highlighter.
    private static func testBlankScreenUsesControlKeys() throws {
        typealias Action = ZoomCanvasView.WhiteBlackKeyAction
        try expect(ZoomCanvasView.whiteBlackKeyAction(control: true, shift: false, isDrawingMode: true) == .blankScreen,
                   "Expected Ctrl+W/Ctrl+K to blank the screen while drawing")
        try expect(ZoomCanvasView.whiteBlackKeyAction(control: false, shift: false, isDrawingMode: true) == .penColor,
                   "Expected plain W/K to select the pen colour, not blank the screen")
        try expect(ZoomCanvasView.whiteBlackKeyAction(control: false, shift: true, isDrawingMode: true) == .highlightColor,
                   "Expected Shift+W/K to select the highlighter")
        try expect(ZoomCanvasView.whiteBlackKeyAction(control: true, shift: false, isDrawingMode: false) == .penColor,
                   "Expected Ctrl+W/K outside drawing mode to fall back to the pen colour")
    }

    /// The Type tab's "Sample" preview must render in the selected typing font
    /// (it previously always used the system font, so font changes weren't
    /// visible). Also verify the preview size is clamped to a legible range.
    private static func testTypeTabFontSampleUsesSelectedFont() throws {
        // A concrete named font should be reflected in the preview font.
        let courier = SettingsWindowController.fontSamplePreviewFont(name: "Courier", size: 24)
        try expect(courier.fontName.lowercased().contains("courier"),
                   "Expected the font sample preview to use the selected font, got \(courier.fontName)")

        // Preview size clamps: very large selections shrink to <= 36pt, very
        // small ones grow to >= 12pt, so the sample stays legible.
        let big = SettingsWindowController.fontSamplePreviewFont(name: "Courier", size: 200)
        try expect(big.pointSize <= 36, "Expected large font preview to clamp to 36pt, got \(big.pointSize)")
        let small = SettingsWindowController.fontSamplePreviewFont(name: "Courier", size: 4)
        try expect(small.pointSize >= 12, "Expected small font preview to clamp to 12pt, got \(small.pointSize)")
    }

    /// The menu-bar icon was a full-bleed image, making it look larger than and
    /// misaligned with system icons. It must now render into a padded, square
    /// template image so the glyph carries interior padding and stays centered.
    private static func testMenuBarIconIsPaddedTemplate() throws {
        // A fully-filled opaque source glyph (edge to edge).
        let dim = 32
        let source = NSImage(size: NSSize(width: dim, height: dim))
        source.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: dim, height: dim).fill()
        source.unlockFocus()

        let icon = AppDelegate.menuBarImage(from: source)
        try expect(icon.isTemplate, "Expected the menu-bar icon to be a template image so it tints with the menu bar")
        try expect(icon.size == NSSize(width: AppDelegate.menuBarIconCanvas, height: AppDelegate.menuBarIconCanvas),
                   "Expected the menu-bar icon to use the padded canvas size, got \(icon.size)")
        // The glyph must be inset (smaller than the canvas), giving it padding.
        try expect(AppDelegate.menuBarIconGlyph < AppDelegate.menuBarIconCanvas,
                   "Expected the glyph to be inset within the canvas for padding")

        // The canvas corners should be transparent padding even though the
        // source filled its bounds edge to edge.
        guard let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw SelfTestError.failure("Could not rasterize menu-bar icon")
        }
        let corner = rep.colorAt(x: 0, y: 0)
        try expect((corner?.alphaComponent ?? 1) < 0.01,
                   "Expected the menu-bar icon corner to be transparent padding, got alpha \(corner?.alphaComponent ?? -1)")
        // The centre should carry the glyph (opaque).
        let center = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)
        try expect((center?.alphaComponent ?? 0) > 0.5,
                   "Expected the menu-bar icon centre to contain the glyph, got alpha \(center?.alphaComponent ?? -1)")
    }

    /// The permissions-dialog / picker icon must be a standard macOS-style
    /// rounded square with a margin (the raw artwork is full-bleed edge to
    /// edge, which looks oversized and misaligns the dialog text). Verify the
    /// produced icon is square, has transparent margin/corners, and an opaque
    /// centre.
    private static func testStandardIconIsRoundedSquareWithMargin() throws {
        let size: CGFloat = 128
        guard let icon = ZoomItAppIcon.standardIcon(size: size) else {
            throw SelfTestError.failure("Expected a standard icon to be produced")
        }
        try expect(icon.size == NSSize(width: size, height: size),
                   "Expected a square standard icon of \(size)pt, got \(icon.size)")

        guard let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw SelfTestError.failure("Could not rasterize standard icon")
        }
        // Corner should be transparent (rounded + margin), unlike the full-bleed
        // source artwork which reaches every edge.
        let corner = rep.colorAt(x: 0, y: 0)
        try expect((corner?.alphaComponent ?? 1) < 0.01,
                   "Expected standard icon corner to be transparent margin, got alpha \(corner?.alphaComponent ?? -1)")
        // The centre must carry the artwork.
        let center = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)
        try expect((center?.alphaComponent ?? 0) > 0.5,
                   "Expected standard icon centre to contain artwork, got alpha \(center?.alphaComponent ?? -1)")
    }

    /// The default typing font should be the default Mac font (an empty font
    /// name resolves to the system font) at 20pt.
    private static func testDefaultTypingFontIsSystem20pt() throws {
        try expect(AppSettings.defaults.typingFontName.isEmpty,
                   "Expected the default typing font name to be empty (the default Mac system font)")
        try expect(
            AppSettings.defaults.typingFontPreset == .system,
            "Expected the default typing font preset to use the native system font"
        )
        try expect(AppSettings.defaults.typingFontSize == 20,
                   "Expected the default typing font size to be 20pt, got \(AppSettings.defaults.typingFontSize)")
        try expect(AnnotationController.defaultFontSize == 20,
                   "Expected the annotation controller default font size to be 20pt")

        // An empty name resolves to the system font at the requested size.
        let resolved = AnnotationController.typingFont(named: "", size: 20)
        let system = NSFont.systemFont(ofSize: 20, weight: .regular)
        try expect(resolved.fontName == system.fontName,
                   "Expected the default typing font to resolve to the regular (non-bold) system font, got \(resolved.fontName)")
        try expect(resolved.pointSize == 20, "Expected the default typing font to be 20pt, got \(resolved.pointSize)")
    }

    private static func testBreakTimerLayout() throws {
        try expect(BreakTimerLayout.timerText(for: 601) == "10:01", "Expected positive break timer text to format as minutes and seconds")
        try expect(BreakTimerLayout.timerText(for: 0) == "0:00", "Expected zero break timer text")
        try expect(BreakTimerLayout.timerText(for: -3) == "0:00", "Expected expired break timer main text to stay at zero")
        try expect(BreakTimerLayout.expiredText(for: -75) == "(- 1:15)", "Expected expired break timer overrun text")

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let textSize = CGSize(width: 200, height: 100)
        let expiredSize = CGSize(width: 120, height: 60)
        try expect(BreakTimerLayout.timerOrigin(textSize: textSize, expiredSize: .zero, bounds: bounds, position: 0) == CGPoint(x: 50, y: 50), "Expected top-left break timer placement")
        try expect(BreakTimerLayout.timerOrigin(textSize: textSize, expiredSize: .zero, bounds: bounds, position: 4) == CGPoint(x: 400, y: 350), "Expected centered break timer placement")
        try expect(BreakTimerLayout.timerOrigin(textSize: textSize, expiredSize: expiredSize, bounds: bounds, position: 8) == CGPoint(x: 750, y: 580), "Expected bottom-right placement to reserve expired-time height")
    }

    /// Synthesize a tall "document" with structured rows, slice overlapping
    /// frames that scroll down by a known amount, and verify the stitcher
    /// reconstructs a panorama taller than a single frame with the document's
    /// content aligned. Exercises the same alignment path used at runtime.
    private static func testPanoramaStitching() throws {
        let width = 320
        let frameHeight = 240
        let scrollPerFrame = 40
        let frameCount = 8
        let documentHeight = frameHeight + scrollPerFrame * (frameCount - 1)

        // Build a deterministic document: each row has a distinctive horizontal
        // pattern derived from its y so alignment has structure to lock onto.
        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let stripe = ((y / 7) % 2 == 0) ? 40 : 210
            let edge = ((x + y) % 23 < 3) ? 255 : 0
            let r = UInt8(clamping: stripe ^ (y & 0x3F))
            let g = UInt8(clamping: (x * 13 + y * 7) & 0xFF)
            let b = UInt8(clamping: edge)
            return (r, g, b)
        }

        func makeSliceFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                let docY = topRow + y
                for x in 0..<width {
                    let (r, g, b) = documentPixel(x: x, y: docY)
                    let i = (y * width + x) * 4
                    pixels[i] = r
                    pixels[i + 1] = g
                    pixels[i + 2] = b
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        var frames: [PanoramaStitcher.Frame] = []
        for f in 0..<frameCount {
            frames.append(makeSliceFrame(topRow: f * scrollPerFrame))
        }

        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Panorama stitching returned no image")
        }

        try expect(stitched.width == width, "Expected stitched width \(width), got \(stitched.width)")
        // The stitched height should reconstruct close to the full document
        // height (allow a few px of alignment slack).
        try expect(abs(stitched.height - documentHeight) <= 4,
                   "Expected stitched height ~\(documentHeight), got \(stitched.height)")

        // Spot-check that a sample of stitched pixels matches the source
        // document, confirming the frames were aligned (not merely concatenated).
        func stitchedPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * stitched.width + x) * 4
            return (stitched.pixels[i], stitched.pixels[i + 1], stitched.pixels[i + 2])
        }

        var mismatches = 0
        let samples = [(20, 10), (100, 90), (200, 180), (300, 260), (50, documentHeight - 20)]
        for (x, y) in samples where y < stitched.height && x < stitched.width {
            let expected = documentPixel(x: x, y: y)
            let actual = stitchedPixel(x: x, y: y)
            let close = abs(Int(expected.0) - Int(actual.0)) <= 6 &&
                        abs(Int(expected.1) - Int(actual.1)) <= 6 &&
                        abs(Int(expected.2) - Int(actual.2)) <= 6
            if !close { mismatches += 1 }
        }
        try expect(mismatches <= 1, "Expected stitched content to align with the document, \(mismatches) sample mismatches")
    }

    /// The top of a panorama is overlapped by many frames. Early frames are
    /// often motion-blurred (still settling); later frames of the same region
    /// are sharp. The compositor must show the LATEST capture of each pixel so
    /// the top is sharp, not the first blurry one.
    private static func testPanoramaTopSeamUsesSingleFramePixels() throws {
        let width = 160
        let frameHeight = 240
        let scrollPerFrame = 40
        let frameCount = 6
        let documentHeight = frameHeight + scrollPerFrame * (frameCount - 1)

        func sharpPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            var hash = UInt32(x) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ 97
            hash = ((hash >> ((hash >> 28) + 4)) ^ hash) &* 277_803_737
            hash = (hash >> 22) ^ hash
            let edge = (x + y * 3) % 17 < 5 ? 70 : 0
            return (UInt8(30 + Int((hash >> 16) & 0x7F) / 2 + edge),
                    UInt8(40 + Int((hash >> 8) & 0x7F) / 2 + edge),
                    UInt8(50 + Int(hash & 0x7F) / 2 + edge))
        }

        // Earlier frames are blurry (tinted) for the same document position;
        // the last frame to cover a row is the sharp one. variant 0 == sharp.
        func makeFrame(topRow: Int, blur: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let p = sharpPixel(x: x, y: topRow + y)
                    let i = (y * width + x) * 4
                    pixels[i] = UInt8(clamping: Int(p.0) + blur)
                    pixels[i + 1] = UInt8(clamping: Int(p.1) + blur)
                    pixels[i + 2] = UInt8(clamping: Int(p.2) + blur)
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        // First frame establishes the top; later frames only add new content
        // below. Keep-first must preserve frame0's pixels (no tiling/overwrite).
        var frames = [makeFrame(topRow: 0, blur: 0)]
        for f in 1..<frameCount { frames.append(makeFrame(topRow: f * scrollPerFrame, blur: 0)) }
        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Top-blur panorama stitching returned no image")
        }
        try expect(abs(stitched.height - documentHeight) <= 8,
                   "Expected top-blur stitched height ~\(documentHeight), got \(stitched.height)")

        func stitchedPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * stitched.width + x) * 4
            return (stitched.pixels[i], stitched.pixels[i + 1], stitched.pixels[i + 2])
        }

        var blurryTop = 0
        var checked = 0
        for y in stride(from: 2, to: frameHeight, by: 8) {
            var x = 8
            while x < width - 8 {
                let actual = stitchedPixel(x: x, y: y)
                let sharp = sharpPixel(x: x, y: y)
                if abs(Int(actual.0) - Int(sharp.0)) > 5 { blurryTop += 1 }
                checked += 1
                x += 11
            }
        }
        try expect(blurryTop == 0,
                   "Expected sharp top from single frame; \(blurryTop)/\(checked) off")
    }

    /// Vertical seams must use keep-first (a single source frame per canvas
    /// pixel), never an overlap blend. A feather blend ghosts slightly-
    /// misaligned text into a dark band -- the strikethrough artifact seen on
    /// real captures. This drives content whose flat background brightness is
    /// unique per frame, then asserts the stitched output only ever contains
    /// exact source values, never an averaged (blended) intermediate.
    private static func testPanoramaVerticalSeamKeepsSingleFrame() throws {
        let width = 140
        let frameHeight = 220
        let scrollPerFrame = 44
        let frameCount = 4
        let documentHeight = frameHeight + scrollPerFrame * (frameCount - 1)

        // Per-frame background brightness, spaced by 10 so an averaged blend of
        // any two adjacent frames (e.g. 217) is never itself a valid source.
        let backgrounds = [UInt8](arrayLiteral: 222, 212, 202, 192)
        let bandShade: UInt8 = 24

        func isBand(_ docY: Int) -> Bool {
            var hash = UInt32(truncatingIfNeeded: docY) &* 2_654_435_761
            hash ^= hash >> 15
            return (hash & 0xFF) < 22
        }

        func makeFrame(index: Int) -> PanoramaStitcher.Frame {
            let background = backgrounds[index]
            let topRow = index * scrollPerFrame
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                let docY = topRow + y
                let shade: UInt8 = isBand(docY) ? bandShade : background
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    pixels[i] = shade
                    pixels[i + 1] = shade
                    pixels[i + 2] = shade
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Vertical-seam panorama stitching returned no image")
        }
        try expect(abs(stitched.height - documentHeight) <= 6,
                   "Expected vertical-seam stitched height ~\(documentHeight), got \(stitched.height)")

        let allowed: Set<Int> = [Int(bandShade), 222, 212, 202, 192]
        var blendedPixels = 0
        var checked = 0
        let sampleX = width / 2
        for y in 0..<stitched.height {
            let value = Int(stitched.pixels[(y * stitched.width + sampleX) * 4])
            if !allowed.contains(value) { blendedPixels += 1 }
            checked += 1
        }
        try expect(blendedPixels == 0,
                   "Expected keep-first vertical seams (no blended intermediates); \(blendedPixels)/\(checked) blended")
    }

    /// Captures often start before scrolling: a tiny pre-scroll jitter (mouse
    /// move, caret) can look like a small upward shift, then the page scrolls
    /// down for real. The stitcher must not commit to the wrong direction and
    /// stitch a segment that is later reversed — that corrupts the very top.
    private static func testPanoramaDeferredDirectionCommit() throws {
        let width = 160
        let frameHeight = 240
        let scrollPerFrame = 40
        let realFrames = 6
        let documentHeight = frameHeight + scrollPerFrame * (realFrames - 1)

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            var hash = UInt32(x) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ 97
            hash = ((hash >> ((hash >> 28) + 4)) ^ hash) &* 277_803_737
            hash = (hash >> 22) ^ hash
            let line = y % 19 < 4 || (x + y * 5) % 53 < 7
            return (UInt8(30 + Int((hash >> 16) & 0x7F) / 2 + (line ? 80 : 0)),
                    UInt8(40 + Int((hash >> 8) & 0x7F) / 2 + (line ? 60 : 0)),
                    UInt8(50 + Int(hash & 0x7F) / 2 + (line ? 50 : 0)))
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let p = documentPixel(x: x, y: topRow + y)
                    let i = (y * width + x) * 4
                    pixels[i] = p.0; pixels[i + 1] = p.1; pixels[i + 2] = p.2; pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        // A reverse jitter first, then a steady downward scroll.
        var frames = [makeFrame(topRow: 16)]
        for f in 0..<realFrames { frames.append(makeFrame(topRow: f * scrollPerFrame)) }
        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Deferred-direction stitching returned no image")
        }
        try expect(abs(stitched.height - documentHeight) <= 8,
                   "Expected deferred-direction height ~\(documentHeight), got \(stitched.height)")

        func stitchedPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * stitched.width + x) * 4
            return (stitched.pixels[i], stitched.pixels[i + 1], stitched.pixels[i + 2])
        }
        var mismatches = 0, checked = 0
        for y in stride(from: 4, to: documentHeight - 4, by: 16) {
            var x = 8
            while x < width - 8 {
                let e = documentPixel(x: x, y: y)
                let a = stitchedPixel(x: x, y: y)
                if abs(Int(e.0) - Int(a.0)) > 6 { mismatches += 1 }
                checked += 1
                x += 17
            }
        }
        try expect(mismatches * 20 < checked, "Expected aligned document after jitter; \(mismatches)/\(checked) off")
    }

    /// Repeated content (e.g. code with similar indentation) tempts the matcher
    /// into tiny harmonic shifts, tiling the same band over and over. The accept
    /// loop must reject sub-progress and spike steps so output height ≈ document.
    private static func testPanoramaNoHarmonicRepeats() throws {
        let width = 200
        let frameHeight = 240
        let step = 40
        let frameCount = 8
        let documentHeight = frameHeight + step * (frameCount - 1)

        func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            // Strong horizontal periodicity (lines every 16px) to bait harmonics.
            let line = y % 16 < 6
            var hash = UInt32(x) &* 2_654_435_761 &+ UInt32(y / 16) &* 40_503
            hash ^= hash >> 13
            return (line ? 30 : 200, line ? 40 : 205, UInt8(Int(hash & 0x3F) + 180))
        }
        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var px = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight { for x in 0..<width {
                let p = pixel(x: x, y: topRow + y); let i = (y * width + x) * 4
                px[i] = p.0; px[i+1] = p.1; px[i+2] = p.2; px[i+3] = 255
            } }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: px)
        }
        let frames = (0..<frameCount).map { makeFrame(topRow: $0 * step) }
        guard let s = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Harmonic-repeat stitch returned nil")
        }
        try expect(s.height <= documentHeight + 16,
                   "Expected no tiling; height \(s.height) vs doc \(documentHeight)")
    }

    /// Sticky app/browser headers remain fixed at local y=0 while the document
    /// underneath scrolls. The stitcher should keep that header from the first
    /// frame only; otherwise it gets stamped repeatedly down the panorama.
    private static func testPanoramaFixedHeaderSuppression() throws {
        let width = 320
        let frameHeight = 240
        let headerHeight = 42
        let scrollPerFrame = 40
        let frameCount = 8
        let documentHeight = frameHeight - headerHeight + scrollPerFrame * (frameCount - 1)
        let expectedHeight = headerHeight + documentHeight

        func headerPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            if y == headerHeight - 1 { return (20, 20, 20) }
            if x % 53 < 18 || y % 17 < 4 { return (230, 32, 190) }
            return (32, 34, 40)
        }

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            var hash = UInt32(x / 4) &* 1_103_515_245 &+ UInt32(y) &* 2_654_435_761 &+ 12_345
            hash ^= hash >> 16
            hash &*= 2_246_822_519
            hash ^= hash >> 13
            let textLine = y % 19 < 3 || (x + y * 7) % 47 < 6
            let r = UInt8((hash >> 16) & 0x7F) &+ (textLine ? 80 : 25)
            let g = UInt8((hash >> 8) & 0x7F) &+ (textLine ? 70 : 35)
            let b = UInt8(hash & 0x7F) &+ (textLine ? 60 : 45)
            return (r, g, b)
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let pixel = y < headerHeight
                        ? headerPixel(x: x, y: y)
                        : documentPixel(x: x, y: topRow + y - headerHeight)
                    let i = (y * width + x) * 4
                    pixels[i] = pixel.0
                    pixels[i + 1] = pixel.1
                    pixels[i + 2] = pixel.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let frames = (0..<frameCount).map { makeFrame(topRow: $0 * scrollPerFrame) }
        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Panorama fixed-header stitching returned no image")
        }

        try expect(stitched.width == width, "Expected fixed-header stitched width \(width), got \(stitched.width)")
        try expect(abs(stitched.height - expectedHeight) <= 4,
                   "Expected fixed-header stitched height ~\(expectedHeight), got \(stitched.height)")

        func stitchedPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * stitched.width + x) * 4
            return (stitched.pixels[i], stitched.pixels[i + 1], stitched.pixels[i + 2])
        }

        var repeatedHeaderPixels = 0
        var sampledPixels = 0
        for y in headerHeight..<stitched.height {
            var x = 0
            while x < width {
                let pixel = stitchedPixel(x: x, y: y)
                if pixel.0 > 210 && pixel.1 < 60 && pixel.2 > 160 {
                    repeatedHeaderPixels += 1
                }
                sampledPixels += 1
                x += 8
            }
        }
        try expect(repeatedHeaderPixels * 100 < max(1, sampledPixels),
                   "Expected fixed header not to repeat below the top; saw \(repeatedHeaderPixels) repeated header samples")

        var mismatches = 0
        let samples = [(24, headerHeight + 5), (120, headerHeight + 90), (260, headerHeight + 180), (80, expectedHeight - 24)]
        for (x, y) in samples where y < stitched.height && x < stitched.width {
            let expected = documentPixel(x: x, y: y - headerHeight)
            let actual = stitchedPixel(x: x, y: y)
            let close = abs(Int(expected.0) - Int(actual.0)) <= 8 &&
                        abs(Int(expected.1) - Int(actual.1)) <= 8 &&
                        abs(Int(expected.2) - Int(actual.2)) <= 8
            if !close { mismatches += 1 }
        }
        try expect(mismatches <= 1, "Expected fixed-header stitched content to align, \(mismatches) sample mismatches")
    }

    /// A sticky bottom toolbar can dominate the overlap if it is left in the
    /// matcher: tiny shifts preserve the toolbar while the true scroll step
    /// moves it out of the overlap. The stitcher must ignore that fixed footer
    /// and recover the actual document motion.
    private static func testPanoramaFooterDoesNotAttractSmallShift() throws {
        let width = 320
        let frameHeight = 240
        let footerHeight = 56
        let scrollPerFrame = 64

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let band = y / 17
            var hash = UInt32(band) &* 1_664_525 &+ 1_013_904_223
            hash ^= UInt32(y) &* 2_246_822_519
            let left = 18 + Int(hash % 72)
            let textWidth = 70 + Int((hash >> 9) % 180)
            let rowPhase = Int((hash >> 17) % 11)
            let onText = ((y + rowPhase) % 17) < 4 && (hash & 0x7) != 0
            let inRun = x >= left && x < min(width - 18, left + textWidth) && ((x * 7 + y * 5 + Int(hash & 0x1F)) % 23) < 14
            if onText && inRun {
                let shade = UInt8(32 + Int((hash >> 24) & 0x1F) + ((x * 7 + y * 11) & 0x1F))
                return (shade, shade, shade)
            }
            return (247, 247, 247)
        }

        func footerPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            if y == 0 { return (40, 40, 40) }
            if (x / 9 + y / 5).isMultiple(of: 2) { return (18, 92, 180) }
            if x % 47 < 15 { return (238, 238, 238) }
            return (34, 36, 42)
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let pixel = y >= frameHeight - footerHeight
                        ? footerPixel(x: x, y: y - (frameHeight - footerHeight))
                        : documentPixel(x: x, y: topRow + y)
                    let i = (y * width + x) * 4
                    pixels[i] = pixel.0
                    pixels[i + 1] = pixel.1
                    pixels[i + 2] = pixel.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let first = makeFrame(topRow: 0)
        let second = makeFrame(topRow: scrollPerFrame)
        let firstLuma = PanoramaStitcher.luma(first)
        let secondLuma = PanoramaStitcher.luma(second)
        let detectedTopRows = PanoramaStitcher.stationaryTopRows(firstLuma, secondLuma, width, frameHeight)
        let detectedBottomRows = PanoramaStitcher.stationaryBottomRows(firstLuma, secondLuma, width, frameHeight)
        try expect(detectedTopRows == 0,
                   "Sparse document whitespace should not be treated as a fixed header; detected \(detectedTopRows) rows")
        try expect(detectedBottomRows >= footerHeight,
                   "Expected sticky footer rows to be detected before matching")
        guard let shift = PanoramaStitcher.findShift(prevLuma: firstLuma,
                                                     curLuma: secondLuma,
                                                     w: width, h: frameHeight,
                                                     expected: nil, axis: nil) else {
            throw SelfTestError.failure("Footer-distracted panorama shift returned no result")
        }
        try expect(shift.axis == .vertical, "Expected footer-distracted shift to stay vertical, got \(shift.axis)")
        try expect(abs(shift.dy - scrollPerFrame) <= 2,
                   "Expected fixed footer to be ignored by matcher; got dy=\(shift.dy), expected \(scrollPerFrame)")
    }

    /// Sticky bottom controls should be locked to the final viewport only. If
    /// earlier frame footers are composited, their toolbar pixels appear as
    /// repeated bands through the document body.
    private static func testPanoramaFixedFooterSuppression() throws {
        let width = 320
        let frameHeight = 240
        let footerHeight = 48
        let scrollPerFrame = 44
        let frameCount = 8
        let documentHeight = frameHeight - footerHeight + scrollPerFrame * (frameCount - 1)
        let expectedHeight = documentHeight + footerHeight

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            var hash = UInt32(x / 3) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ 97
            hash = ((hash >> ((hash >> 28) + 4)) ^ hash) &* 277_803_737
            hash = (hash >> 22) ^ hash
            let line = y % 23 < 4 || (x + y * 5) % 61 < 7
            return (
                UInt8((hash >> 16) & 0x7F) &+ (line ? 90 : 30),
                UInt8((hash >> 8) & 0x7F) &+ (line ? 70 : 35),
                UInt8(hash & 0x7F) &+ (line ? 55 : 40)
            )
        }

        func footerPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            if y == 0 { return (12, 12, 12) }
            if x % 59 < 20 || y % 13 < 4 { return (18, 108, 235) }
            return (24, 26, 34)
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let pixel = y >= frameHeight - footerHeight
                        ? footerPixel(x: x, y: y - (frameHeight - footerHeight))
                        : documentPixel(x: x, y: topRow + y)
                    let i = (y * width + x) * 4
                    pixels[i] = pixel.0
                    pixels[i + 1] = pixel.1
                    pixels[i + 2] = pixel.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let frames = (0..<frameCount).map { makeFrame(topRow: $0 * scrollPerFrame) }
        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Panorama fixed-footer stitching returned no image")
        }

        try expect(stitched.width == width, "Expected fixed-footer stitched width \(width), got \(stitched.width)")
        try expect(abs(stitched.height - expectedHeight) <= 4,
                   "Expected fixed-footer stitched height ~\(expectedHeight), got \(stitched.height)")

        func stitchedPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * stitched.width + x) * 4
            return (stitched.pixels[i], stitched.pixels[i + 1], stitched.pixels[i + 2])
        }

        var repeatedFooterPixels = 0
        var sampledPixels = 0
        for y in 0..<max(0, stitched.height - footerHeight) {
            var x = 0
            while x < width {
                let pixel = stitchedPixel(x: x, y: y)
                if pixel.0 < 45 && pixel.1 > 80 && pixel.2 > 180 {
                    repeatedFooterPixels += 1
                }
                sampledPixels += 1
                x += 8
            }
        }
        try expect(repeatedFooterPixels * 100 < max(1, sampledPixels),
                   "Expected fixed footer not to repeat above the bottom; saw \(repeatedFooterPixels) repeated footer samples")

        var footerMatches = 0
        var footerSamples = 0
        let footerTop = stitched.height - footerHeight
        for y in footerTop..<stitched.height {
            var x = 0
            while x < width {
                let expected = footerPixel(x: x, y: y - footerTop)
                let actual = stitchedPixel(x: x, y: y)
                if abs(Int(expected.0) - Int(actual.0)) <= 4 &&
                   abs(Int(expected.1) - Int(actual.1)) <= 4 &&
                   abs(Int(expected.2) - Int(actual.2)) <= 4 {
                    footerMatches += 1
                }
                footerSamples += 1
                x += 8
            }
        }
        try expect(footerMatches * 100 >= footerSamples * 95,
                   "Expected final footer to be locked at bottom; matched \(footerMatches)/\(footerSamples) samples")
    }

    /// Capture can produce several frames from the same scroll position with a
    /// tiny dynamic change (caret blink, hover repaint, loading spinner). Those
    /// frames must not be forced into non-zero shifts and stamped repeatedly.
    private static func testPanoramaSkipsRepeatedCaptures() throws {
        let width = 320
        let frameHeight = 240
        let scrollPerFrame = 40
        let scrollPositions = [0, 40, 80, 120, 160, 200, 240]
        let documentHeight = frameHeight + scrollPerFrame * (scrollPositions.count - 1)

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            var hash = UInt32(x) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ 97
            hash = ((hash >> ((hash >> 28) + 4)) ^ hash) &* 277_803_737
            hash = (hash >> 22) ^ hash
            let line = y % 23 < 4 || (x + y * 5) % 61 < 7
            return (
                UInt8((hash >> 16) & 0x7F) &+ (line ? 90 : 30),
                UInt8((hash >> 8) & 0x7F) &+ (line ? 70 : 35),
                UInt8(hash & 0x7F) &+ (line ? 55 : 40)
            )
        }

        func makeFrame(topRow: Int, variant: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                let docY = topRow + y
                for x in 0..<width {
                    var pixel = documentPixel(x: x, y: docY)
                    if variant > 0 && x >= 260 && x < 292 && y >= 32 && y < 56 {
                        pixel = variant.isMultiple(of: 2) ? (250, 20, 20) : (20, 180, 250)
                    }
                    let i = (y * width + x) * 4
                    pixels[i] = pixel.0
                    pixels[i + 1] = pixel.1
                    pixels[i + 2] = pixel.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        var frames: [PanoramaStitcher.Frame] = []
        for (index, topRow) in scrollPositions.enumerated() {
            frames.append(makeFrame(topRow: topRow, variant: 0))
            if index < scrollPositions.count - 1 {
                frames.append(makeFrame(topRow: topRow, variant: index + 1))
                frames.append(makeFrame(topRow: topRow, variant: index + 2))
            }
        }

        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Panorama repeated-capture stitching returned no image")
        }

        try expect(stitched.width == width, "Expected repeated-capture stitched width \(width), got \(stitched.width)")
        try expect(abs(stitched.height - documentHeight) <= 4,
                   "Expected repeated-capture stitched height ~\(documentHeight), got \(stitched.height)")
    }

    private static func testPanoramaRejectsStationaryRepaintShift() throws {
        let width = 320
        let frameHeight = 240

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let line = y % 17 < 4 || (x + y * 3) % 47 < 9
            var hash = UInt32(x) &* 1_664_525 &+ UInt32(y) &* 1_013_904_223
            hash ^= hash >> 13
            let shade = UInt8((hash & 0x3F) + (line ? 34 : 160))
            return (shade, shade, UInt8(clamping: Int(shade) + (line ? 30 : 0)))
        }

        func makeFrame(repaintVariant: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    var pixel = documentPixel(x: x, y: y)
                    if repaintVariant > 0 && x >= 210 && x < 302 && y >= 36 && y < 92 {
                        pixel = repaintVariant.isMultiple(of: 2) ? (240, 32, 32) : (32, 160, 240)
                    }
                    let i = (y * width + x) * 4
                    pixels[i] = pixel.0
                    pixels[i + 1] = pixel.1
                    pixels[i + 2] = pixel.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let first = makeFrame(repaintVariant: 0)
        let repaint = makeFrame(repaintVariant: 1)
        let firstLuma = PanoramaStitcher.luma(first)
        let repaintLuma = PanoramaStitcher.luma(repaint)
        let shift = PanoramaStitcher.findShift(prevLuma: firstLuma,
                                               curLuma: repaintLuma,
                                               w: width, h: frameHeight,
                                               expected: (dx: 0, dy: 40), axis: .vertical)
        try expect(shift == nil,
                   "Expected stationary repaint not to be forced into a panorama shift, got \(String(describing: shift))")
    }

    private static func testPanoramaKeepsScrollBesideStaticContent() throws {
        let width = 840
        let frameHeight = 360
        let movingWidth = 310
        let scrollPerFrame = 90

        func movingPixel(x: Int, y: Int) -> UInt8 {
            let card = y / 74
            let line = y % 74
            let left = 24 + (card % 3) * 9
            let textWidth = 150 + (card * 31 % 104)
            let onText = (12...15).contains(line) || (28...31).contains(line) || (44...47).contains(line)
            let glyph = onText && x >= left && x < min(movingWidth - 18, left + textWidth) && ((x * 5 + y * 7) % 19) < 12
            if glyph { return UInt8(36 + ((x * 3 + y * 5) & 0x1F)) }
            if line >= 3 && line <= 56 && x >= 12 && x < movingWidth - 12 { return 238 }
            return 248
        }

        func staticPixel(x: Int, y: Int) -> UInt8 {
            let localX = x - movingWidth
            let block = (localX / 96 + y / 88) % 4
            let bevel = abs((localX % 96) - 48) / 5 + abs((y % 88) - 44) / 6
            let shade = 205 - block * 18 - min(36, bevel)
            return UInt8(max(116, min(232, shade)))
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let shade = x < movingWidth ? movingPixel(x: x, y: topRow + y) : staticPixel(x: x, y: y)
                    let i = (y * width + x) * 4
                    pixels[i] = shade
                    pixels[i + 1] = shade
                    pixels[i + 2] = shade
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let first = makeFrame(topRow: 0)
        let second = makeFrame(topRow: scrollPerFrame)
        let firstLuma = PanoramaStitcher.luma(first)
        let secondLuma = PanoramaStitcher.luma(second)
        let shift = PanoramaStitcher.findShift(prevLuma: firstLuma,
                               curLuma: secondLuma,
                                               w: width, h: frameHeight,
                                               expected: (dx: 0, dy: scrollPerFrame), axis: .vertical)
        try expect(abs((shift?.dy ?? 0) - scrollPerFrame) <= 4,
               "Expected scroll beside static content to keep dy ~\(scrollPerFrame), got \(String(describing: shift))")
    }

    /// Real chat/document captures can be mostly white space with sparse text.
    /// Raw pixel-change fractions stay low even while the document scrolls a
    /// long way, so duplicate filtering must not collapse the panorama to the
    /// first viewport.
    private static func testPanoramaSparseTallContentStitches() throws {
        let width = 360
        let frameHeight = 260
        let scrollPerFrame = 80
        let frameCount = 7
        let documentHeight = frameHeight + scrollPerFrame * (frameCount - 1)

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let paragraph = y / 53
            let lineInParagraph = y % 53
            let left = 28 + (paragraph % 3) * 12
            let textWidth = 120 + (paragraph * 37 % 110)
            let onTextLine = (6...8).contains(lineInParagraph) ||
                             (18...20).contains(lineInParagraph) ||
                             (30...31).contains(lineInParagraph)
            let inTextRun = x >= left && x < min(width - 24, left + textWidth) && ((x + y * 3) % 17) < 10
            if onTextLine && inTextRun {
                let shade = UInt8(38 + ((x * 5 + y * 7) & 0x1F))
                return (shade, shade, shade)
            }
            if lineInParagraph == 0 && x >= left && x < left + 46 {
                return (88, 88, 88)
            }
            return (248, 248, 248)
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                let docY = topRow + y
                for x in 0..<width {
                    let pixel = documentPixel(x: x, y: docY)
                    let i = (y * width + x) * 4
                    pixels[i] = pixel.0
                    pixels[i + 1] = pixel.1
                    pixels[i + 2] = pixel.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let frames = (0..<frameCount).map { makeFrame(topRow: $0 * scrollPerFrame) }
        try expect(!PanoramaStitcher.isNearDuplicate(frames[0], frames[1]),
                   "Sparse real-scroll frames should not be filtered as duplicates during capture")

        var captureFilteredFrames: [PanoramaStitcher.Frame] = []
        for frame in frames {
            if captureFilteredFrames.isEmpty || !PanoramaStitcher.isNearDuplicate(captureFilteredFrames[captureFilteredFrames.count - 1], frame) {
                captureFilteredFrames.append(frame)
            }
        }
        try expect(captureFilteredFrames.count == frameCount,
                   "Expected capture duplicate filter to keep all sparse scroll frames, kept \(captureFilteredFrames.count)/\(frameCount)")

        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Sparse panorama stitching returned no image")
        }

        try expect(stitched.width == width, "Expected sparse stitched width \(width), got \(stitched.width)")
        try expect(abs(stitched.height - documentHeight) <= 8,
                   "Expected sparse stitched height ~\(documentHeight), got \(stitched.height)")
    }

    /// Tall captures of text-heavy content can produce deceptively good
    /// horizontal matches from repeated glyph/column structure. Startup axis
    /// detection should keep those ambiguous portrait captures vertical so the
    /// panorama grows down instead of smearing sideways.
    private static func testPanoramaStartupAxisRejectsHorizontalAlias() throws {
        let width = 140
        let frameHeight = 320
        let scrollPerFrame = 34
        let frameCount = 6
        let documentHeight = frameHeight + scrollPerFrame * (frameCount - 1)

        func documentShade(x: Int, y: Int) -> UInt8 {
            let paragraph = y / 47
            let line = y % 47
            let left = 18 + (paragraph % 4) * 7
            let textWidth = 74 + (paragraph * 19 % 38)
            let onTextLine = (7...9).contains(line) ||
                             (18...20).contains(line) ||
                             (30...31).contains(line)
            let glyph = x >= left && x < min(width - 12, left + textWidth) && ((x + paragraph * 5 + y) % 13) < 8
            if onTextLine && glyph { return UInt8(36 + ((x * 3 + y * 5) & 0x1F)) }
            if line == 0 && x >= left && x < left + 28 { return 94 }
            return 248
        }

        func makeFrame(topRow: Int, phase: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    var shade = Int(documentShade(x: x, y: topRow + y))
                    let localStripe = (x + (y / 5) * 3) % 24
                    if localStripe < 9 { shade = (shade * 3 + 220) / 4 }
                    if (x + 6) % 32 < 3 { shade = min(shade, 208) }
                    if (x * 13 + y * 7 + phase) % 101 == 0 { shade = max(0, shade - 8) }
                    let i = (y * width + x) * 4
                    pixels[i] = UInt8(shade)
                    pixels[i + 1] = UInt8(shade)
                    pixels[i + 2] = UInt8(shade)
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let first = makeFrame(topRow: 0, phase: 0)
        let second = makeFrame(topRow: scrollPerFrame, phase: 17)
        let axisDecision = PanoramaStitcher.axisScan(prev: PanoramaStitcher.luma(first),
                                                     cur: PanoramaStitcher.luma(second),
                                                     w: width, h: frameHeight,
                                                     ignoreTopRows: 0)
        try expect(axisDecision?.axis == .vertical,
                   "Expected portrait startup axis scan to choose vertical, got \(String(describing: axisDecision?.axis))")

        let frames = (0..<frameCount).map { makeFrame(topRow: $0 * scrollPerFrame, phase: $0 * 17) }
        guard let stitched = PanoramaStitcher.stitch(frames: frames) else {
            throw SelfTestError.failure("Horizontal-alias panorama stitching returned no image")
        }

        try expect(stitched.width == width, "Expected horizontal-alias stitched width \(width), got \(stitched.width)")
        try expect(abs(stitched.height - documentHeight) <= 8,
                   "Expected horizontal-alias stitched height ~\(documentHeight), got \(stitched.height)")
    }

    private static func testPanoramaLockedAxisRejectsShortFallback() throws {
        let width = 260
        let frameHeight = 300
        let actualStep = 30
        let expectedStep = 90

        func documentPixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let line = y % 31 < 7 || (x * 3 + y * 5) % 67 < 10
            var hash = UInt32(x) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ 97
            hash = ((hash >> ((hash >> 28) + 4)) ^ hash) &* 277_803_737
            hash = (hash >> 22) ^ hash
            let base = line ? 48 : 220
            return (UInt8(base + Int((hash >> 16) & 0x1F)),
                    UInt8(base + Int((hash >> 8) & 0x1F)),
                    UInt8(base + Int(hash & 0x1F)))
        }

        func makeFrame(topRow: Int) -> PanoramaStitcher.Frame {
            var pixels = [UInt8](repeating: 0, count: width * frameHeight * 4)
            for y in 0..<frameHeight {
                for x in 0..<width {
                    let p = documentPixel(x: x, y: topRow + y)
                    let i = (y * width + x) * 4
                    pixels[i] = p.0
                    pixels[i + 1] = p.1
                    pixels[i + 2] = p.2
                    pixels[i + 3] = 255
                }
            }
            return PanoramaStitcher.Frame(width: width, height: frameHeight, pixels: pixels)
        }

        let first = makeFrame(topRow: 0)
        let shortStep = makeFrame(topRow: actualStep)
        let shift = PanoramaStitcher.findShift(prevLuma: PanoramaStitcher.luma(first),
                                               curLuma: PanoramaStitcher.luma(shortStep),
                                               w: width, h: frameHeight,
                                               expected: (dx: 0, dy: expectedStep), axis: .vertical)
        try expect(shift == nil,
                   "Expected locked-axis full fallback to reject short harmonic step, got \(String(describing: shift))")
    }

    private static func makeCanvas(
        annotationController: AnnotationController
    ) throws -> ZoomCanvasView {
        let frame = try makeFrame()
        let viewportController = ZoomViewportController()
        viewportController.configure(for: frame, initialZoom: 2)
        return ZoomCanvasView(
            frame: CGRect(origin: .zero, size: frame.display.frame.size),
            capturedFrame: frame,
            viewportController: viewportController,
            annotationController: annotationController,
            smoothImage: true,
            userSelectedResourceAccess: UserDefaultsUserSelectedResourceAccess(),
            commandSink: { _ in }
        )
    }

    private static func descendantViews<View: NSView>(
        of type: View.Type,
        in root: NSView
    ) -> [View] {
        var result: [View] = []
        if let view = root as? View {
            result.append(view)
        }
        for subview in root.subviews {
            result.append(contentsOf: descendantViews(of: type, in: subview))
        }
        return result
    }

    private static func frame(
        _ view: NSView,
        convertedTo ancestor: NSView
    ) -> CGRect {
        guard let superview = view.superview else {
            return view.frame
        }
        let localFrame = view is NSTextField
            ? view.alignmentRect(forFrame: view.frame)
            : view.frame
        return superview.convert(localFrame, to: ancestor)
    }

    private static func dispatchPhysicalClick(on button: NSButton) throws {
        try dispatchPhysicalClick(in: button)
    }

    private static func dispatchPhysicalClick(in view: NSView) throws {
        let events = try physicalClickEvents(in: view)
        NSApp.postEvent(events.mouseUp, atStart: true)
        NSApp.sendEvent(events.mouseDown)
    }

    private static func dispatchPhysicalMouseClick(in view: NSView) throws {
        let events = try physicalClickEvents(in: view)
        NSApp.postEvent(events.mouseUp, atStart: true)
        NSApp.postEvent(events.mouseDown, atStart: true)
        var dispatchedTypes: [NSEvent.EventType] = []
        while let event = NSApp.nextEvent(
            matching: [.leftMouseDown, .leftMouseUp],
            until: Date().addingTimeInterval(0.1),
            inMode: .default,
            dequeue: true
        ) {
            dispatchedTypes.append(event.type)
            NSApp.sendEvent(event)
            if event.type == .leftMouseUp {
                break
            }
        }
        guard dispatchedTypes == [.leftMouseDown, .leftMouseUp] else {
            throw SelfTestError.failure(
                "Expected one queued physical mouse-down/up pair, got \(dispatchedTypes)"
            )
        }
    }

    private static func physicalClickEvents(
        in view: NSView
    ) throws -> (mouseDown: NSEvent, mouseUp: NSEvent) {
        view.layoutSubtreeIfNeeded()
        guard let window = view.window else {
            throw SelfTestError.failure(
                "Cannot dispatch a physical click to a detached view"
            )
        }
        let location = view.convert(
            CGPoint(x: view.bounds.midX, y: view.bounds.midY),
            to: nil
        )
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ), let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.001,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ) else {
            throw SelfTestError.failure(
                "Could not synthesize a physical AppKit button click"
            )
        }
        return (mouseDown, mouseUp)
    }

    private static func makeFrame(
        displayFrame: CGRect = CGRect(
            x: 0,
            y: 0,
            width: 1_000,
            height: 800
        ),
        scaleFactor: CGFloat = 2
    ) throws -> CapturedFrame {
        guard let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw SelfTestError.failure("Could not create test image")
        }

        return CapturedFrame(
            image: image,
            display: DisplayDescriptor(
                id: 1,
                frame: displayFrame,
                scaleFactor: scaleFactor
            ),
            pixelSize: CGSize(width: image.width, height: image.height),
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeSolidImage(
        width: Int,
        height: Int,
        color: NSColor
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw SelfTestError.failure("Could not create solid test image")
        }
        context.setFillColor(color.cgColor)
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let image = context.makeImage() else {
            throw SelfTestError.failure("Could not finalize solid test image")
        }
        return image
    }

    private struct RenderPixel: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    private struct ImageAlphaSignature: Hashable {
        var width: Int
        var height: Int
        var painted: [Bool]

        var paintedCentroidX: CGFloat {
            var totalX: CGFloat = 0
            var count: CGFloat = 0
            for y in 0..<height {
                for x in 0..<width where painted[y * width + x] {
                    totalX += CGFloat(x)
                    count += 1
                }
            }
            return count > 0 ? totalX / count : CGFloat(width - 1) / 2
        }

        func horizontallyMirrored() -> ImageAlphaSignature {
            var mirrored = painted
            for y in 0..<height {
                for x in 0..<width {
                    mirrored[y * width + x] = painted[y * width + (width - 1 - x)]
                }
            }
            return ImageAlphaSignature(width: width, height: height, painted: mirrored)
        }
    }

    private static func previewAlphaSignature(
        _ preview: DrawingInspectorPreview
    ) throws -> ImageAlphaSignature {
        guard let data = preview.image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data) else {
            throw SelfTestError.failure("Could not rasterize an inspector preview image")
        }
        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        let painted = (0..<height).flatMap { y in
            (0..<width).map { x in
                (representation.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
            }
        }
        return ImageAlphaSignature(width: width, height: height, painted: painted)
    }

    private static func renderPixels(
        elements: [AnnotationElement],
        renderer: AnnotationRenderer,
        activeElement: AnnotationElement? = nil,
        pendingErasureElementIDs: Set<AnnotationElementID> = [],
        decorationElements: [AnnotationElement] = [],
        selectedElementIDs: Set<AnnotationElementID> = [],
        zoomScale: CGFloat = 1,
        width: Int = 96,
        height: Int = 96,
        backgroundColor: NSColor? = nil,
        destinationPointScale: CGFloat = 1,
        backingScale: Int = 1
    ) throws -> [UInt8] {
        let scale = max(1, backingScale)
        let pixelWidth = width * scale
        let pixelHeight = height * scale
        let bytesPerPixel = 4
        var pixels = [UInt8](
            repeating: 0,
            count: pixelWidth * pixelHeight * bytesPerPixel
        )
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw SelfTestError.failure("Could not create annotation render bitmap")
            }
            context.setAllowsAntialiasing(false)
            context.setShouldAntialias(false)
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            if let backgroundColor {
                let resolvedBackground = backgroundColor.usingColorSpace(.sRGB)
                    ?? backgroundColor
                context.setFillColor(resolvedBackground.cgColor)
                context.fill(
                    CGRect(
                        x: 0,
                        y: 0,
                        width: CGFloat(width),
                        height: CGFloat(height)
                    )
                )
            }
            renderer.render(
                elements: elements,
                activeElement: activeElement,
                destinationPointScale: destinationPointScale,
                pendingErasureElementIDs: pendingErasureElementIDs,
                in: context
            )
            renderer.renderSelectionDecorations(
                for: decorationElements,
                selectedElementIDs: selectedElementIDs,
                zoomScale: zoomScale,
                in: context
            )
            context.flush()
        }
        return pixels
    }

    private static func renderArrowheadPixels(
        _ arrowhead: AnnotationArrowhead,
        size: AnnotationArrowheadSize,
        strokeWidth: CGFloat,
        width: Int = 128,
        height: Int = 128
    ) throws -> [UInt8] {
        let bytesPerPixel = 4
        var pixels = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let path = AnnotationGeometry.arrowheadPath(
                arrowhead,
                tip: CGPoint(x: 100, y: 64),
                adjacent: CGPoint(x: 20, y: 64),
                strokeWidth: strokeWidth,
                size: size
            ) else {
                throw SelfTestError.failure(
                    "Could not create arrowhead render bitmap"
                )
            }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path)
            arrowhead.isFilled ? context.fillPath() : context.strokePath()
            context.flush()
        }
        return pixels
    }

    private static func renderControllerPixels(
        _ controller: AnnotationController,
        freehandPresentationOwner: AnnotationFreehandPresentationOwner,
        includeTransientEraserFeedback: Bool = true,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        let bytesPerPixel = 4
        var pixels = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw SelfTestError.failure(
                    "Could not create annotation-controller render bitmap"
                )
            }
            context.setAllowsAntialiasing(false)
            context.setShouldAntialias(false)
            controller.render(
                in: context,
                bounds: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(width),
                    height: CGFloat(height)
                ),
                includeSmartDrawPreview: false,
                includeInProgress: true,
                includeEditorChrome: false,
                includeTransientEraserFeedback:
                    includeTransientEraserFeedback,
                freehandPresentationOwner: freehandPresentationOwner
            )
            context.flush()
        }
        return pixels
    }

    private static func renderSelectionPixels(
        annotationController: AnnotationController,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw SelfTestError.failure("Could not create selection render bitmap")
            }
            context.setAllowsAntialiasing(false)
            context.setShouldAntialias(false)
            annotationController.renderSelectionDecorations(in: context, zoomScale: 1)
            context.flush()
        }
        return pixels
    }

    private static func pixel(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> RenderPixel {
        let height = pixels.count / (width * 4)
        let index = ((height - 1 - y) * width + x) * 4
        return RenderPixel(
            red: pixels[index],
            green: pixels[index + 1],
            blue: pixels[index + 2],
            alpha: pixels[index + 3]
        )
    }

    private static func alpha(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> UInt8 {
        pixel(pixels, width: width, x: x, y: y).alpha
    }

    private static func paintedRuns(
        _ pixels: [UInt8],
        width: Int,
        y: Int,
        xRange: Range<Int>
    ) -> Int {
        var runs = 0
        var wasPainted = false
        for x in xRange {
            let isPainted = alpha(pixels, width: width, x: x, y: y) > 0
            if isPainted && !wasPainted {
                runs += 1
            }
            wasPainted = isPainted
        }
        return runs
    }

    private static func paintedVerticalRuns(
        _ pixels: [UInt8],
        width: Int,
        x: Int,
        yRange: Range<Int>
    ) -> Int {
        var runs = 0
        var wasPainted = false
        for y in yRange {
            let isPainted = alpha(pixels, width: width, x: x, y: y) > 0
            if isPainted && !wasPainted {
                runs += 1
            }
            wasPainted = isPainted
        }
        return runs
    }

    private static func paintedPixelCount(_ pixels: [UInt8]) -> Int {
        stride(from: 3, to: pixels.count, by: 4).reduce(into: 0) {
            if pixels[$1] > 0 {
                $0 += 1
            }
        }
    }

    private static func pixelDifferenceCount(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) }
        return zip(lhs, rhs).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 {
                count += 1
            }
        }
    }

    private static func alphaMaskSymmetricDifferenceRatio(
        _ lhs: [UInt8],
        _ rhs: [UInt8]
    ) -> CGFloat {
        guard lhs.count == rhs.count else { return 1 }
        var union = 0
        var difference = 0
        for index in stride(from: 3, to: lhs.count, by: 4) {
            let left = lhs[index] > 0
            let right = rhs[index] > 0
            if left || right {
                union += 1
                if left != right {
                    difference += 1
                }
            }
        }
        return union > 0 ? CGFloat(difference) / CGFloat(union) : 0
    }

    private static func expectRaster(
        _ actual: [UInt8],
        uniformlyScaling expectedSource: [UInt8],
        by multiplier: CGFloat,
        context: String
    ) throws {
        try expect(
            actual.count == expectedSource.count
                && expectedSource.contains(where: { $0 > 0 }),
            "Expected comparable nonempty rasters for \(context)"
        )
        var maximumError = 0
        var mismatchedBytes = 0
        for (actualByte, sourceByte) in zip(actual, expectedSource) {
            let expectedByte = Int(
                (CGFloat(sourceByte) * multiplier).rounded()
            )
            let error = abs(Int(actualByte) - expectedByte)
            maximumError = max(maximumError, error)
            if error > 2 {
                mismatchedBytes += 1
            }
        }
        try expect(
            mismatchedBytes == 0,
            "Expected complete \(context) raster to equal the normal composite "
                + "uniformly multiplied by \(multiplier); max error "
                + "\(maximumError), mismatched bytes \(mismatchedBytes)"
        )
    }

    private static func pixelDifferenceCount(
        _ lhs: [UInt8],
        _ rhs: [UInt8],
        width: Int,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) }
        return yRange.reduce(into: 0) { count, y in
            for x in xRange {
                let left = pixel(lhs, width: width, x: x, y: y)
                let right = pixel(rhs, width: width, x: x, y: y)
                if left != right {
                    count += 1
                }
            }
        }
    }

    private static func meanHorizontalDeviation(
        _ paths: [CGPath],
        canonicalY: CGFloat
    ) -> CGFloat {
        let deviations = paths.flatMap {
            AnnotationRoughStroke.sampledPoints(on: $0).map {
                abs($0.y - canonicalY)
            }
        }
        guard !deviations.isEmpty else { return 0 }
        return deviations.reduce(0, +) / CGFloat(deviations.count)
    }

    private static func meanHorizontalWaviness(_ paths: [CGPath]) -> CGFloat {
        let waviness = paths.map { path -> CGFloat in
            let points = AnnotationRoughStroke.sampledPoints(on: path)
            guard let minimum = points.map(\.y).min(),
                  let maximum = points.map(\.y).max() else {
                return 0
            }
            return maximum - minimum
        }
        guard !waviness.isEmpty else { return 0 }
        return waviness.reduce(0, +) / CGFloat(waviness.count)
    }

    private static func maximumHorizontalDeviation(
        _ paths: [CGPath],
        canonicalY: CGFloat
    ) -> CGFloat {
        paths.flatMap {
            AnnotationRoughStroke.sampledPoints(on: $0).map {
                abs($0.y - canonicalY)
            }
        }.max() ?? 0
    }

    private static func meanPathSeparation(
        _ first: CGPath,
        _ second: CGPath
    ) -> CGFloat {
        let firstPoints = AnnotationRoughStroke.sampledPoints(on: first)
        let secondPoints = AnnotationRoughStroke.sampledPoints(on: second)
        let distances = zip(firstPoints, secondPoints).map {
            hypot($0.x - $1.x, $0.y - $1.y)
        }
        guard !distances.isEmpty else { return 0 }
        return distances.reduce(0, +) / CGFloat(distances.count)
    }

    private static func hasPaintedPixel(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        near point: CGPoint,
        radius: Int
    ) -> Bool {
        let centerX = Int(point.x.rounded())
        let centerY = Int(point.y.rounded())
        let xRange = max(0, centerX - radius)...min(width - 1, centerX + radius)
        let yRange = max(0, centerY - radius)...min(height - 1, centerY + radius)
        return yRange.contains { y in
            xRange.contains { x in
                alpha(pixels, width: width, x: x, y: y) > 0
            }
        }
    }

    private static func paintedVerticalSpan(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        x: Int
    ) -> Int {
        let paintedRows = (0..<height).filter { alpha(pixels, width: width, x: x, y: $0) > 0 }
        guard let first = paintedRows.first, let last = paintedRows.last else { return 0 }
        return last - first + 1
    }

    private static func paintedBounds(
        _ pixels: [UInt8],
        width: Int,
        height: Int
    ) -> CGRect? {
        var painted: [CGPoint] = []
        for y in 0..<height {
            for x in 0..<width where alpha(pixels, width: width, x: x, y: y) > 0 {
                painted.append(CGPoint(x: x, y: y))
            }
        }
        guard let first = painted.first else { return nil }
        return painted.dropFirst().reduce(
            CGRect(x: first.x, y: first.y, width: 0, height: 0)
        ) { bounds, point in
            bounds.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
    }

    private static func noisyEllipsePoints(
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat,
        count: Int
    ) -> [CGPoint] {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return (0..<count).map { index in
            let angle = CGFloat(index) * 2 * .pi / CGFloat(count - 1)
            let noise = sin(CGFloat(index) * 1.73) * 1.15
            let localX = (radiusX + noise) * cos(angle)
            let localY = (radiusY + noise * 0.7) * sin(angle)
            return CGPoint(
                x: center.x + localX * cosine - localY * sine,
                y: center.y + localX * sine + localY * cosine
            )
        }
    }

    private static func imperfectEllipsePoints(
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        count: Int,
        unevenPower: CGFloat
    ) -> [CGPoint] {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return (0..<count).map { index in
            let linear = CGFloat(index) / CGFloat(max(count - 1, 1))
            let fraction = pow(linear, unevenPower)
            let angle = startAngle + (endAngle - startAngle) * fraction
            let noise = sin(CGFloat(index) * 1.57) * 1.35
            let localX = (radiusX + noise) * cos(angle)
            let localY = (radiusY + noise * 0.65) * sin(angle)
            return CGPoint(
                x: center.x + localX * cosine - localY * sine,
                y: center.y + localX * sine + localY * cosine
            )
        }
    }

    private static func rotatedRectangleCorners(
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        rotation: CGFloat
    ) -> [CGPoint] {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return [
            CGPoint(x: -width / 2, y: -height / 2),
            CGPoint(x: width / 2, y: -height / 2),
            CGPoint(x: width / 2, y: height / 2),
            CGPoint(x: -width / 2, y: height / 2)
        ].map { point in
            CGPoint(
                x: center.x + point.x * cosine - point.y * sine,
                y: center.y + point.x * sine + point.y * cosine
            )
        }
    }

    private static func unevenPolygonPoints(
        corners: [CGPoint],
        samplesPerEdge: [Int],
        close: Bool
    ) -> [CGPoint] {
        guard corners.count >= 3, samplesPerEdge.count == corners.count else {
            return corners
        }
        var result: [CGPoint] = []
        for index in corners.indices {
            let start = corners[index]
            let end = corners[(index + 1) % corners.count]
            let count = max(2, samplesPerEdge[index])
            let vector = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let length = max(hypot(vector.x, vector.y), 1)
            let normal = CGPoint(x: -vector.y / length, y: vector.x / length)
            for sample in 0..<count {
                let fraction = CGFloat(sample) / CGFloat(count)
                let noise = sin(CGFloat(index * 31 + sample) * 1.23) * 1.1
                result.append(
                    CGPoint(
                        x: start.x + vector.x * fraction + normal.x * noise,
                        y: start.y + vector.y * fraction + normal.y * noise
                    )
                )
            }
        }
        if close {
            result.append(corners[0])
        }
        return result
    }

    private static func angleDifferenceModulo(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        period: CGFloat
    ) -> CGFloat {
        var difference = (lhs - rhs).truncatingRemainder(dividingBy: period)
        if difference > period / 2 {
            difference -= period
        } else if difference < -period / 2 {
            difference += period
        }
        return abs(difference)
    }

    private static func noisyPolygonPoints(
        corners: [CGPoint],
        samplesPerEdge: Int
    ) -> [CGPoint] {
        guard corners.count >= 3 else { return corners }
        var result: [CGPoint] = []
        for index in corners.indices {
            let start = corners[index]
            let end = corners[(index + 1) % corners.count]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(hypot(dx, dy), 1)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            for sample in 0..<samplesPerEdge {
                let fraction = CGFloat(sample) / CGFloat(samplesPerEdge)
                let noise = sin(CGFloat(index * samplesPerEdge + sample) * 1.31) * 0.9
                result.append(
                    CGPoint(
                        x: start.x + dx * fraction + normal.x * noise,
                        y: start.y + dy * fraction + normal.y * noise
                    )
                )
            }
        }
        result.append(corners[0])
        return result
    }

    private static func interpolatedPoints(
        from start: CGPoint,
        to end: CGPoint,
        count: Int,
        droppingFirst: Bool = false
    ) -> [CGPoint] {
        let points = (0..<count).map { index in
            let fraction = CGFloat(index) / CGFloat(max(count - 1, 1))
            return CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
        }
        return droppingFirst ? Array(points.dropFirst()) : points
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func approximatelyEqual(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func approximatelyEqual(
        _ lhs: CGPoint,
        _ rhs: CGPoint,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
    }

    private static func approximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        approximatelyEqual(lhs.origin, rhs.origin, tolerance: tolerance)
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func colorsMatch(
        _ lhs: NSColor,
        _ rhs: NSColor,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        guard let left = lhs.usingColorSpace(.sRGB),
              let right = rhs.usingColorSpace(.sRGB) else {
            return lhs.isEqual(rhs)
        }
        return abs(left.redComponent - right.redComponent) <= tolerance
            && abs(left.greenComponent - right.greenComponent) <= tolerance
            && abs(left.blueComponent - right.blueComponent) <= tolerance
            && abs(left.alphaComponent - right.alphaComponent) <= tolerance
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SelfTestError.failure(message)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}