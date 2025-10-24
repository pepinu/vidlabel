//
//  AnnotationViewModel.swift
//  VidLabel
//
//  Manages annotations and tracked objects
//

import Foundation
import SwiftUI
import AVFoundation

class AnnotationViewModel: ObservableObject {
    @Published var trackedObjects: [TrackedObject] = []
    @Published var selectedObjectId: UUID?
    @Published var isDrawingMode: Bool = false

    // Current drawing state
    @Published var currentDrawingStart: CGPoint?
    @Published var currentDrawingEnd: CGPoint?

    // Zoom state
    @Published var isZoomed: Bool = false
    @Published var zoomCenter: CGPoint = .zero
    @Published var zoomViewSize: CGSize = .zero

    // Counter for unique object naming (never decreases)
    private var objectCounter: Int = 0

    // Tracking
    @Published var isTracking: Bool = false
    @Published var trackingProgress: String = ""
    private var trackingManager = TrackingManager()

    // Auto-detection
    @Published var detectionProposals: [DetectionProposal] = []
    @Published var isAutoDetecting: Bool = false
    @Published var detectionProgress: String = ""
    private var detectionManager: MotionDetectionManager?
    @Published var detectionROI: BoundingBox?
    @Published var isDrawingDetectionROI: Bool = false
    @Published var detectionDeadZones: [BoundingBox] = []
    @Published var isDrawingDeadZone: Bool = false

    // Segments
    @Published var segments: [VideoSegment] = []
    @Published var selectedSegmentId: UUID?

    // Undo/Redo
    @Published var undoManager = UndoRedoManager()

    // Visibility
    @Published var nonSelectedOpacity: Double = 1.0 // 0.0 to 1.0 opacity for non-selected objects

    // Clipboard for copy/paste
    @Published var copiedBoundingBox: BoundingBox?
    @Published var copiedFromFrame: Int?
    @Published var copiedFromObjectId: UUID?

    // Categories
    @Published var categories: [ObjectCategory] = ObjectCategory.defaultCategories
    @Published var selectedCategoryFilter: UUID? = nil // nil means show all

    var selectedObject: TrackedObject? {
        guard let id = selectedObjectId else { return nil }
        return trackedObjects.first { $0.id == id }
    }

    var hasClipboard: Bool {
        return copiedBoundingBox != nil
    }

    var filteredTrackedObjects: [TrackedObject] {
        guard let filterCategoryId = selectedCategoryFilter else {
            return trackedObjects
        }
        return trackedObjects.filter { $0.categoryId == filterCategoryId }
    }

    // MARK: - Object Management

    func addObject(label: String? = nil, categoryId: UUID? = nil) -> TrackedObject {
        objectCounter += 1
        let objectLabel = label ?? "Object \(objectCounter)"

        // Use category color if category is provided
        var color = CodableColor.random()
        if let catId = categoryId, let category = categories.first(where: { $0.id == catId }) {
            color = category.color
        }

        let newObject = TrackedObject(label: objectLabel, color: color, categoryId: categoryId)
        trackedObjects.append(newObject)
        selectedObjectId = newObject.id

        // Record undo action
        undoManager.recordAction(AddObjectAction(object: newObject))

        return newObject
    }

    func setObjectCategory(objectId: UUID, categoryId: UUID?) {
        if let index = trackedObjects.firstIndex(where: { $0.id == objectId }) {
            trackedObjects[index].categoryId = categoryId

            // Optionally update color to match category
            if let catId = categoryId, let category = categories.first(where: { $0.id == catId }) {
                trackedObjects[index].color = category.color
            }
        }
    }

    // MARK: - Category Management

    func addCategory(name: String, supercategory: String?, color: CodableColor) {
        let newCategory = ObjectCategory(name: name, supercategory: supercategory, color: color)
        categories.append(newCategory)
        print("✅ Added category: \(name)")
    }

    func updateCategory(id: UUID, name: String, supercategory: String?, color: CodableColor) {
        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].name = name
            categories[index].supercategory = supercategory
            categories[index].color = color

            // Update all objects with this category to use new color
            for objIndex in trackedObjects.indices {
                if trackedObjects[objIndex].categoryId == id {
                    trackedObjects[objIndex].color = color
                }
            }
            print("✅ Updated category: \(name)")
        }
    }

    func deleteCategory(id: UUID) {
        // Remove category assignments from objects
        for index in trackedObjects.indices {
            if trackedObjects[index].categoryId == id {
                trackedObjects[index].categoryId = nil
            }
        }

        // Remove the category
        categories.removeAll { $0.id == id }
        print("✅ Deleted category")
    }

    func resetCategoriesToDefault() {
        categories = ObjectCategory.defaultCategories
        print("✅ Reset categories to default")
    }

    func addExistingObject(_ object: TrackedObject) {
        trackedObjects.append(object)
        // Don't record undo - this is called by undo/redo itself
    }

    func deleteObject(id: UUID) {
        guard let object = trackedObjects.first(where: { $0.id == id }) else { return }

        // Record undo action before deleting
        undoManager.recordAction(DeleteObjectAction(object: object))

        trackedObjects.removeAll { $0.id == id }
        if selectedObjectId == id {
            selectedObjectId = trackedObjects.first?.id
        }
    }

    func selectObject(id: UUID) {
        selectedObjectId = id
    }

    // MARK: - Visibility Control

    func toggleObjectVisibility(id: UUID) {
        if let index = trackedObjects.firstIndex(where: { $0.id == id }) {
            trackedObjects[index].isVisible.toggle()
        }
    }

    func setObjectVisibility(id: UUID, isVisible: Bool) {
        if let index = trackedObjects.firstIndex(where: { $0.id == id }) {
            trackedObjects[index].isVisible = isVisible
        }
    }

    func soloObject(id: UUID) {
        // Hide all objects except the selected one
        for index in trackedObjects.indices {
            trackedObjects[index].isVisible = (trackedObjects[index].id == id)
        }
    }

    func showAllObjects() {
        // Show all objects
        for index in trackedObjects.indices {
            trackedObjects[index].isVisible = true
        }
    }

    // MARK: - Copy/Paste Annotations

    func copyAnnotation(objectId: UUID, frameNumber: Int) {
        guard let object = trackedObjects.first(where: { $0.id == objectId }),
              let box = object.boundingBox(at: frameNumber) else {
            print("No annotation to copy at frame \(frameNumber)")
            return
        }

        copiedBoundingBox = box
        copiedFromFrame = frameNumber
        copiedFromObjectId = objectId
        print("📋 Copied annotation from frame \(frameNumber)")
    }

    func pasteAnnotation(toObjectId: UUID, toFrame: Int) {
        guard let box = copiedBoundingBox else {
            print("No annotation in clipboard")
            return
        }

        addAnnotation(boundingBox: box, frameNumber: toFrame, objectId: toObjectId, recordUndo: true)
        print("📋 Pasted annotation to frame \(toFrame)")
    }

    func pasteAnnotationToRange(toObjectId: UUID, fromFrame: Int, toFrame: Int) {
        guard let box = copiedBoundingBox else {
            print("No annotation in clipboard")
            return
        }

        guard fromFrame <= toFrame else {
            print("Invalid frame range")
            return
        }

        var pastedAnnotations: [Int: BoundingBox] = [:]
        for frame in fromFrame...toFrame {
            pastedAnnotations[frame] = box
            addAnnotation(boundingBox: box, frameNumber: frame, objectId: toObjectId, recordUndo: false)
        }

        // Record as batch undo
        undoManager.recordAction(BatchAddAnnotationsAction(
            objectId: toObjectId,
            annotations: pastedAnnotations
        ))

        print("📋 Pasted annotation to frames \(fromFrame)-\(toFrame) (\(pastedAnnotations.count) frames)")
    }

    func clearClipboard() {
        copiedBoundingBox = nil
        copiedFromFrame = nil
        copiedFromObjectId = nil
    }

    // MARK: - Annotation Management

    func addAnnotation(boundingBox: BoundingBox, frameNumber: Int, objectId: UUID, recordUndo: Bool = true) {
        if let index = trackedObjects.firstIndex(where: { $0.id == objectId }) {
            trackedObjects[index].setBoundingBox(boundingBox, at: frameNumber)
            print("💾 SAVE Frame \(frameNumber): x=\(String(format: "%.4f", boundingBox.x)), y=\(String(format: "%.4f", boundingBox.y)), w=\(String(format: "%.4f", boundingBox.width)), h=\(String(format: "%.4f", boundingBox.height))")

            // Record undo action
            if recordUndo {
                undoManager.recordAction(AddAnnotationAction(objectId: objectId, frameNumber: frameNumber, boundingBox: boundingBox))
            }
        } else {
            print("ERROR: Could not find object with id \(objectId)")
        }
    }

    func removeAnnotation(at frameNumber: Int, objectId: UUID, recordUndo: Bool = true) {
        if let index = trackedObjects.firstIndex(where: { $0.id == objectId }) {
            // Get the box before removing for undo
            if recordUndo, let box = trackedObjects[index].boundingBox(at: frameNumber) {
                undoManager.recordAction(RemoveAnnotationAction(objectId: objectId, frameNumber: frameNumber, boundingBox: box))
            }

            trackedObjects[index].removeAnnotation(at: frameNumber)
        }
    }

    func deleteAnnotationAtFrame(objectId: UUID, frameNumber: Int) {
        guard let idx = trackedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        var obj = trackedObjects[idx]
        obj.annotations.removeValue(forKey: frameNumber)
        trackedObjects[idx] = obj
        print("🗑️ Deleted annotation for \(obj.label) at frame \(frameNumber)")
    }

    func getAnnotations(at frameNumber: Int) -> [(object: TrackedObject, box: BoundingBox)] {
        var results: [(TrackedObject, BoundingBox)] = []
        for object in trackedObjects {
            if let box = object.boundingBox(at: frameNumber) {
                print("📖 RETRIEVE Frame \(frameNumber): \(object.label) x=\(String(format: "%.4f", box.x)), y=\(String(format: "%.4f", box.y))")
                results.append((object, box))
            }
        }
        return results
    }

    // MARK: - Drawing State

    func startDrawingDetectionROI() {
        isDrawingDetectionROI = true
    }

    func setDetectionROI(_ roi: BoundingBox?) {
        detectionROI = roi
        isDrawingDetectionROI = false
    }

    func startDrawingDeadZone() {
        isDrawingDeadZone = true
    }

    func addDeadZone(_ zone: BoundingBox) {
        detectionDeadZones.append(zone)
        isDrawingDeadZone = false
    }

    func removeDeadZone(at index: Int) {
        guard index >= 0 && index < detectionDeadZones.count else { return }
        detectionDeadZones.remove(at: index)
    }

    func clearAllDeadZones() {
        detectionDeadZones.removeAll()
    }

    func startDrawing(at point: CGPoint, viewCoordinate: CGPoint, viewSize: CGSize) {
        currentDrawingStart = point
        currentDrawingEnd = point
        isDrawingMode = true

        // Only enable zoom for normal annotation drawing, NOT for ROI or dead zone drawing
        if !isDrawingDetectionROI && !isDrawingDeadZone {
            zoomCenter = viewCoordinate
            zoomViewSize = viewSize
            isZoomed = true
        }
    }

    func updateDrawing(to point: CGPoint) {
        currentDrawingEnd = point
    }

    func finishDrawing() -> BoundingBox? {
        defer {
            currentDrawingStart = nil
            currentDrawingEnd = nil
            isDrawingMode = false

            // Disable zoom when done drawing
            isZoomed = false
        }

        guard let start = currentDrawingStart,
              let end = currentDrawingEnd else {
            return nil
        }

        // Minimum size threshold to avoid accidental tiny boxes
        let minSize: CGFloat = 0.01
        let box = BoundingBox.from(startPoint: start, endPoint: end)
        guard box.width >= minSize && box.height >= minSize else {
            return nil
        }

        // If drawing ROI, set it and finish
        if isDrawingDetectionROI {
            detectionROI = box
            isDrawingDetectionROI = false
        }

        // If drawing dead zone, add it to the list
        if isDrawingDeadZone {
            detectionDeadZones.append(box)
            isDrawingDeadZone = false
        }

        return box
    }

    func cancelDrawing() {
        currentDrawingStart = nil
        currentDrawingEnd = nil
        isDrawingMode = false
        isZoomed = false
        isDrawingDetectionROI = false
        isDrawingDeadZone = false
    }

    // MARK: - Tracking

    func startTrackingForward(
        objectId: UUID,
        fromFrame: Int,
        toFrame: Int,
        asset: AVAsset,
        videoURL: URL?,
        frameRate: Double
    ) {
        guard let index = trackedObjects.firstIndex(where: { $0.id == objectId }),
              let initialBox = trackedObjects[index].boundingBox(at: fromFrame) else {
            print("No bounding box at frame \(fromFrame)")
            return
        }

        isTracking = true
        trackingProgress = "Tracking forward from frame \(fromFrame)..."

        trackingManager.trackForward(
            asset: asset,
            videoURL: videoURL,
            startFrame: fromFrame, // Include current frame as initial
            endFrame: toFrame,
            initialBox: initialBox,
            frameRate: frameRate
        ) { [weak self] result in
            // Progress callback
            Task { @MainActor in
                self?.trackingProgress = "Tracking frame \(result.frameNumber)..."
                self?.addAnnotation(
                    boundingBox: result.boundingBox,
                    frameNumber: result.frameNumber,
                    objectId: objectId
                )
            }
        } completionCallback: { [weak self] result in
            Task { @MainActor in
                self?.isTracking = false
                switch result {
                case .success(let results):
                    self?.trackingProgress = "Tracked \(results.count) frames"
                    print("Tracking completed: \(results.count) frames")
                case .failure(let error):
                    self?.trackingProgress = "Tracking failed: \(error.localizedDescription)"
                    print("Tracking error: \(error)")
                }
            }
        }
    }

    func startTrackingBackward(
        objectId: UUID,
        fromFrame: Int,
        toFrame: Int,
        asset: AVAsset,
        videoURL: URL?,
        frameRate: Double
    ) {
        guard let index = trackedObjects.firstIndex(where: { $0.id == objectId }),
              let initialBox = trackedObjects[index].boundingBox(at: fromFrame) else {
            print("No bounding box at frame \(fromFrame)")
            return
        }

        isTracking = true
        trackingProgress = "Tracking backward from frame \(fromFrame)..."

        trackingManager.trackBackward(
            asset: asset,
            videoURL: videoURL,
            startFrame: fromFrame, // Start from the current annotated frame
            endFrame: toFrame,
            initialBox: initialBox,
            frameRate: frameRate
        ) { [weak self] result in
            // Progress callback
            Task { @MainActor in
                self?.trackingProgress = "Tracking frame \(result.frameNumber)..."
                self?.addAnnotation(
                    boundingBox: result.boundingBox,
                    frameNumber: result.frameNumber,
                    objectId: objectId
                )
            }
        } completionCallback: { [weak self] result in
            Task { @MainActor in
                self?.isTracking = false
                switch result {
                case .success(let results):
                    self?.trackingProgress = "Tracked \(results.count) frames"
                    print("Tracking completed: \(results.count) frames")
                case .failure(let error):
                    self?.trackingProgress = "Tracking failed: \(error.localizedDescription)"
                    print("Tracking error: \(error)")
                }
            }
        }
    }

    func cancelTracking() {
        trackingManager.cancel()
        isTracking = false
        trackingProgress = "Tracking cancelled"
    }

    // MARK: - Utility

    func clearAllAnnotations() {
        trackedObjects.removeAll()
        selectedObjectId = nil
    }

    // MARK: - QoL Operations

    /// Remove all annotations for an object with frame > frameNumber
    func trimAnnotationsAfter(objectId: UUID, frameNumber: Int) {
        guard let idx = trackedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        var obj = trackedObjects[idx]

        // Record removed annotations for undo
        let removedAnnotations = obj.annotations.filter { $0.key > frameNumber }
        if !removedAnnotations.isEmpty {
            undoManager.recordAction(TrimAnnotationsAction(
                objectId: objectId,
                removedAnnotations: removedAnnotations,
                isBefore: false,
                cutFrame: frameNumber
            ))
        }

        obj.annotations = obj.annotations.filter { $0.key <= frameNumber }
        trackedObjects[idx] = obj
    }

    /// Remove all annotations for an object with frame < frameNumber
    func trimAnnotationsBefore(objectId: UUID, frameNumber: Int) {
        guard let idx = trackedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        var obj = trackedObjects[idx]

        // Record removed annotations for undo
        let removedAnnotations = obj.annotations.filter { $0.key < frameNumber }
        if !removedAnnotations.isEmpty {
            undoManager.recordAction(TrimAnnotationsAction(
                objectId: objectId,
                removedAnnotations: removedAnnotations,
                isBefore: true,
                cutFrame: frameNumber
            ))
        }

        obj.annotations = obj.annotations.filter { $0.key >= frameNumber }
        trackedObjects[idx] = obj
    }

    /// Expand all bounding boxes for an object by a pixel amount in all directions
    func expandAllBoxes(objectId: UUID, byPixels: Double, videoSize: CGSize) {
        guard byPixels > 0, videoSize.width > 0, videoSize.height > 0 else { return }
        let dx = byPixels / videoSize.width
        let dy = byPixels / videoSize.height
        guard let idx = trackedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        var obj = trackedObjects[idx]

        var newAnnotations: [Int: BoundingBox] = [:]
        for (frame, box) in obj.annotations {
            var nx = max(0.0, box.x - dx)
            var ny = max(0.0, box.y - dy)
            var nw = box.width + 2*dx
            var nh = box.height + 2*dy
            // Clamp width/height so box remains inside [0,1]
            if nx + nw > 1.0 { nw = 1.0 - nx }
            if ny + nh > 1.0 { nh = 1.0 - ny }
            // Ensure non-negative
            nw = max(0.0, nw)
            nh = max(0.0, nh)
            newAnnotations[frame] = BoundingBox(x: nx, y: ny, width: nw, height: nh)
        }
        obj.annotations = newAnnotations
        trackedObjects[idx] = obj
    }

    /// Shift (move) all bounding boxes for an object by a pixel offset
    func shiftAllBoxes(objectId: UUID, dxPixels: Double, dyPixels: Double, videoSize: CGSize) {
        guard videoSize.width > 0, videoSize.height > 0 else { return }
        let dx = dxPixels / videoSize.width
        let dy = dyPixels / videoSize.height
        guard let idx = trackedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        var obj = trackedObjects[idx]

        var newAnnotations: [Int: BoundingBox] = [:]
        for (frame, box) in obj.annotations {
            var nx = box.x + dx
            var ny = box.y + dy
            // Clamp so the box stays within bounds
            nx = max(0.0, min(1.0 - box.width, nx))
            ny = max(0.0, min(1.0 - box.height, ny))
            newAnnotations[frame] = BoundingBox(x: nx, y: ny, width: box.width, height: box.height)
        }
        obj.annotations = newAnnotations
        trackedObjects[idx] = obj
    }

    // MARK: - Auto-Detection

    func startAutoDetection(
        asset: AVAsset,
        frameRange: ClosedRange<Int>,
        frameRate: Double,
        videoSize: CGSize,
        roi: BoundingBox? = nil,
        deadZones: [BoundingBox] = []
    ) {
        isAutoDetecting = true
        detectionProgress = "Starting detection..."

        var config = MotionDetectionManager.Config()
        config.roi = roi
        config.deadZones = deadZones
        detectionManager = MotionDetectionManager(config: config)

        Task {
            do {
                let detectedObjects = try await detectionManager?.autoDetect(
                    asset: asset,
                    frameRange: frameRange,
                    frameRate: frameRate,
                    videoSize: videoSize
                ) { current, total, frameNumber in
                    Task { @MainActor in
                        self.detectionProgress = "Processing frame \(frameNumber) (\(current)/\(total))"
                    }
                }

                await MainActor.run {
                    // Convert to proposals
                    if let objects = detectedObjects {
                        for obj in objects {
                            let proposal = DetectionProposal(
                                id: obj.id,
                                annotations: obj.annotations,
                                confidence: obj.confidence,
                                detectionState: obj.detectionState
                            )
                            detectionProposals.append(proposal)
                        }
                        detectionProgress = "Detection complete: \(objects.count) object(s) found"
                    }
                    isAutoDetecting = false
                }
            } catch {
                await MainActor.run {
                    detectionProgress = "Detection failed: \(error.localizedDescription)"
                    isAutoDetecting = false
                }
            }
        }
    }

    func cancelAutoDetection() {
        detectionManager?.cancel()
        isAutoDetecting = false
        detectionProgress = "Detection cancelled"
    }

    func acceptProposal(proposalId: UUID) {
        guard let proposal = detectionProposals.first(where: { $0.id == proposalId }) else { return }

        objectCounter += 1
        let trackedObject = proposal.toTrackedObject(label: "Object \(objectCounter)")
        trackedObjects.append(trackedObject)

        // Remove from proposals
        detectionProposals.removeAll { $0.id == proposalId }
    }

    func rejectProposal(proposalId: UUID) {
        detectionProposals.removeAll { $0.id == proposalId }
    }

    func acceptAllProposals() {
        for proposal in detectionProposals {
            objectCounter += 1
            let trackedObject = proposal.toTrackedObject(label: "Object \(objectCounter)")
            trackedObjects.append(trackedObject)
        }
        detectionProposals.removeAll()
    }

    func rejectAllProposals() {
        detectionProposals.removeAll()
    }

    func deleteProposalFrames(proposalId: UUID, range: ClosedRange<Int>) {
        guard let index = detectionProposals.firstIndex(where: { $0.id == proposalId }) else { return }
        detectionProposals[index].deleteFrames(in: range)

        // Remove proposal if no frames left
        if detectionProposals[index].annotations.isEmpty {
            detectionProposals.remove(at: index)
        }
    }

    func getProposalAnnotations(at frameNumber: Int) -> [(proposal: DetectionProposal, box: BoundingBox)] {
        var results: [(DetectionProposal, BoundingBox)] = []
        for proposal in detectionProposals {
            if let box = proposal.boundingBox(at: frameNumber) {
                results.append((proposal, box))
            }
        }
        return results
    }

    // MARK: - Segment Management

    func addSegment(name: String, startFrame: Int, endFrame: Int) {
        let segment = VideoSegment(name: name, startFrame: startFrame, endFrame: endFrame)
        segments.append(segment)
        segments.sort { $0.startFrame < $1.startFrame }
    }

    func deleteSegment(id: UUID) {
        segments.removeAll { $0.id == id }
        if selectedSegmentId == id {
            selectedSegmentId = nil
        }
    }

    func updateSegment(id: UUID, name: String, startFrame: Int, endFrame: Int, notes: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].name = name
        segments[index].startFrame = startFrame
        segments[index].endFrame = endFrame
        segments[index].notes = notes
        segments.sort { $0.startFrame < $1.startFrame }
    }

    func getSegment(at frame: Int) -> VideoSegment? {
        return segments.first { $0.contains(frame: frame) }
    }

    func selectSegment(id: UUID) {
        selectedSegmentId = id
    }

    func autoSegment(totalFrames: Int, framesPerSegment: Int) {
        guard framesPerSegment > 0 else { return }

        // Clear existing segments
        segments.removeAll()

        var segmentNumber = 1
        var currentFrame = 0

        while currentFrame < totalFrames {
            let endFrame = min(currentFrame + framesPerSegment - 1, totalFrames - 1)
            let name = "Segment \(segmentNumber)"

            let segment = VideoSegment(
                name: name,
                startFrame: currentFrame,
                endFrame: endFrame
            )
            segments.append(segment)

            currentFrame = endFrame + 1
            segmentNumber += 1
        }

        print("Auto-created \(segments.count) segments with \(framesPerSegment) frames each")
    }

    // MARK: - Navigation

    /// Get the next frame with any annotation
    func getNextAnnotatedFrame(from currentFrame: Int, totalFrames: Int) -> Int? {
        let allFrames = Set(trackedObjects.flatMap { $0.annotations.keys })
        let futureFrames = allFrames.filter { $0 > currentFrame }.sorted()
        return futureFrames.first
    }

    /// Get the previous frame with any annotation
    func getPreviousAnnotatedFrame(from currentFrame: Int) -> Int? {
        let allFrames = Set(trackedObjects.flatMap { $0.annotations.keys })
        let pastFrames = allFrames.filter { $0 < currentFrame }.sorted(by: >)
        return pastFrames.first
    }

    /// Get the next frame with annotation for selected object
    func getNextFrameForSelectedObject(from currentFrame: Int) -> Int? {
        guard let object = selectedObject else { return nil }
        let frames = object.annotations.keys.filter { $0 > currentFrame }.sorted()
        return frames.first
    }

    /// Get the previous frame with annotation for selected object
    func getPreviousFrameForSelectedObject(from currentFrame: Int) -> Int? {
        guard let object = selectedObject else { return nil }
        let frames = object.annotations.keys.filter { $0 < currentFrame }.sorted(by: >)
        return frames.first
    }

    /// Calculate annotation density for heatmap
    func getAnnotationDensity(totalFrames: Int, bucketSize: Int = 100) -> [Int] {
        let bucketCount = (totalFrames + bucketSize - 1) / bucketSize
        var density = Array(repeating: 0, count: bucketCount)

        for object in trackedObjects {
            for frame in object.annotations.keys {
                let bucket = frame / bucketSize
                if bucket < bucketCount {
                    density[bucket] += 1
                }
            }
        }

        return density
    }

    // MARK: - Interpolation

    /// Interpolate bounding boxes between two keyframes
    func interpolate(objectId: UUID, fromFrame: Int, toFrame: Int) {
        guard let object = trackedObjects.first(where: { $0.id == objectId }),
              let startBox = object.boundingBox(at: fromFrame),
              let endBox = object.boundingBox(at: toFrame),
              toFrame > fromFrame else {
            print("Cannot interpolate: missing keyframes or invalid range")
            return
        }

        let frameCount = toFrame - fromFrame + 1
        var interpolatedAnnotations: [Int: BoundingBox] = [:]

        // Linear interpolation for each frame
        for i in 0..<frameCount {
            let currentFrame = fromFrame + i
            let t = Double(i) / Double(frameCount - 1) // 0.0 to 1.0

            // Interpolate each property
            let x = startBox.x + (endBox.x - startBox.x) * t
            let y = startBox.y + (endBox.y - startBox.y) * t
            let width = startBox.width + (endBox.width - startBox.width) * t
            let height = startBox.height + (endBox.height - startBox.height) * t

            let interpolatedBox = BoundingBox(x: x, y: y, width: width, height: height)
            interpolatedAnnotations[currentFrame] = interpolatedBox
        }

        // Add all interpolated annotations (don't record individual undo actions)
        for (frame, box) in interpolatedAnnotations {
            addAnnotation(boundingBox: box, frameNumber: frame, objectId: objectId, recordUndo: false)
        }

        // Record batch undo action
        undoManager.recordAction(BatchAddAnnotationsAction(
            objectId: objectId,
            annotations: interpolatedAnnotations
        ))

        print("✨ Interpolated \(interpolatedAnnotations.count) frames from \(fromFrame) to \(toFrame)")
    }

    /// Get list of frames with annotations for an object (sorted)
    func getKeyframes(objectId: UUID) -> [Int] {
        guard let object = trackedObjects.first(where: { $0.id == objectId }) else { return [] }
        return object.annotations.keys.sorted()
    }

    /// Get next keyframe after current frame
    func getNextKeyframe(objectId: UUID, afterFrame: Int) -> Int? {
        let keyframes = getKeyframes(objectId: objectId)
        return keyframes.first(where: { $0 > afterFrame })
    }

    /// Get previous keyframe before current frame
    func getPreviousKeyframe(objectId: UUID, beforeFrame: Int) -> Int? {
        let keyframes = getKeyframes(objectId: objectId)
        return keyframes.last(where: { $0 < beforeFrame })
    }

    // MARK: - Progress Tracking

    /// Get annotation coverage statistics
    func getProgressStats(totalFrames: Int) -> ProgressStats {
        var annotatedFrames = Set<Int>()
        var objectStats: [UUID: ObjectStats] = [:]

        for object in trackedObjects {
            let frames = Set(object.annotations.keys)
            annotatedFrames.formUnion(frames)

            objectStats[object.id] = ObjectStats(
                label: object.label,
                frameCount: frames.count,
                coverage: Double(frames.count) / Double(totalFrames)
            )
        }

        let coverage = Double(annotatedFrames.count) / Double(totalFrames)

        return ProgressStats(
            totalFrames: totalFrames,
            annotatedFrames: annotatedFrames.count,
            coverage: coverage,
            objectCount: trackedObjects.count,
            objectStats: objectStats
        )
    }
}

// MARK: - Progress Stats Models

struct ProgressStats {
    let totalFrames: Int
    let annotatedFrames: Int
    let coverage: Double // 0.0 to 1.0
    let objectCount: Int
    let objectStats: [UUID: ObjectStats]
}

struct ObjectStats {
    let label: String
    let frameCount: Int
    let coverage: Double // 0.0 to 1.0
}
