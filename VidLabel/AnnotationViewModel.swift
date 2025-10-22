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

    var selectedObject: TrackedObject? {
        guard let id = selectedObjectId else { return nil }
        return trackedObjects.first { $0.id == id }
    }

    // MARK: - Object Management

    func addObject(label: String? = nil) -> TrackedObject {
        objectCounter += 1
        let objectLabel = label ?? "Object \(objectCounter)"
        let newObject = TrackedObject(label: objectLabel)
        trackedObjects.append(newObject)
        selectedObjectId = newObject.id
        return newObject
    }

    func deleteObject(id: UUID) {
        trackedObjects.removeAll { $0.id == id }
        if selectedObjectId == id {
            selectedObjectId = trackedObjects.first?.id
        }
    }

    func selectObject(id: UUID) {
        selectedObjectId = id
    }

    // MARK: - Annotation Management

    func addAnnotation(boundingBox: BoundingBox, frameNumber: Int, objectId: UUID) {
        if let index = trackedObjects.firstIndex(where: { $0.id == objectId }) {
            trackedObjects[index].setBoundingBox(boundingBox, at: frameNumber)
            print("💾 SAVE Frame \(frameNumber): x=\(String(format: "%.4f", boundingBox.x)), y=\(String(format: "%.4f", boundingBox.y)), w=\(String(format: "%.4f", boundingBox.width)), h=\(String(format: "%.4f", boundingBox.height))")
        } else {
            print("ERROR: Could not find object with id \(objectId)")
        }
    }

    func removeAnnotation(at frameNumber: Int, objectId: UUID) {
        if let index = trackedObjects.firstIndex(where: { $0.id == objectId }) {
            trackedObjects[index].removeAnnotation(at: frameNumber)
        }
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

    func startDrawing(at point: CGPoint, viewCoordinate: CGPoint, viewSize: CGSize) {
        currentDrawingStart = point
        currentDrawingEnd = point
        isDrawingMode = true

        // Enable zoom centered on click point (store view coordinates for zoom)
        zoomCenter = viewCoordinate
        zoomViewSize = viewSize
        isZoomed = true
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

        return box
    }

    func cancelDrawing() {
        currentDrawingStart = nil
        currentDrawingEnd = nil
        isDrawingMode = false
        isZoomed = false
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
        obj.annotations = obj.annotations.filter { $0.key <= frameNumber }
        trackedObjects[idx] = obj
    }

    /// Remove all annotations for an object with frame < frameNumber
    func trimAnnotationsBefore(objectId: UUID, frameNumber: Int) {
        guard let idx = trackedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        var obj = trackedObjects[idx]
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
        videoSize: CGSize
    ) {
        isAutoDetecting = true
        detectionProgress = "Starting detection..."

        let config = MotionDetectionManager.Config()
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
}
