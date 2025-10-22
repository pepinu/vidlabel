//
//  TrackingManager.swift
//  VidLabel
//
//  Vision-based object tracking (VNTrackObjectRequest)
//

import Foundation
import AVFoundation
import Vision

class TrackingManager {

    struct TrackingResult {
        let frameNumber: Int
        let boundingBox: BoundingBox
        let confidence: Float
    }

    enum TrackingError: Error {
        case trackingFailed
        case cancelled
        case frameExtractionFailed
    }

    private var isCancelled = false

    func cancel() {
        isCancelled = true
    }

    /// Track an object forward starting from the annotated frame using Apple's Vision tracker
    func trackForward(
        asset: AVAsset,
        videoURL: URL?,
        startFrame: Int,
        endFrame: Int,
        initialBox: BoundingBox,
        frameRate: Double,
        progressCallback: @escaping (TrackingResult) -> Void,
        completionCallback: @escaping (Result<[TrackingResult], Error>) -> Void
    ) {
        isCancelled = false
        Task {
            do {
                let results = try await performVisionTracking(
                    asset: asset,
                    startFrame: startFrame,
                    endFrame: endFrame,
                    initialBox: initialBox,
                    frameRate: frameRate,
                    direction: .forward,
                    progressCallback: progressCallback
                )
                if isCancelled { completionCallback(.failure(TrackingError.cancelled)) }
                else { completionCallback(.success(results)) }
            } catch {
                completionCallback(.failure(error))
            }
        }
    }

    /// Track an object backward starting from the annotated frame using Apple's Vision tracker
    func trackBackward(
        asset: AVAsset,
        videoURL: URL?,
        startFrame: Int,
        endFrame: Int,
        initialBox: BoundingBox,
        frameRate: Double,
        progressCallback: @escaping (TrackingResult) -> Void,
        completionCallback: @escaping (Result<[TrackingResult], Error>) -> Void
    ) {
        isCancelled = false
        Task {
            do {
                let results = try await performVisionTracking(
                    asset: asset,
                    startFrame: startFrame,
                    endFrame: endFrame,
                    initialBox: initialBox,
                    frameRate: frameRate,
                    direction: .backward,
                    progressCallback: progressCallback
                )
                if isCancelled { completionCallback(.failure(TrackingError.cancelled)) }
                else { completionCallback(.success(results)) }
            } catch {
                completionCallback(.failure(error))
            }
        }
    }

    // MARK: - Private

    private enum Direction { case forward, backward }

    private func performVisionTracking(
        asset: AVAsset,
        startFrame: Int,
        endFrame: Int,
        initialBox: BoundingBox,
        frameRate: Double,
        direction: Direction,
        progressCallback: @escaping (TrackingResult) -> Void
    ) async throws -> [TrackingResult] {
        // Build list of frame numbers to track (exclude the annotated frame itself)
        let frames: [Int]
        switch direction {
        case .forward:
            frames = (max(startFrame + 1, 0)...max(endFrame, startFrame)).map { $0 }
        case .backward:
            let lower = min(endFrame, startFrame - 1)
            let upper = startFrame - 1
            frames = stride(from: upper, through: lower, by: -1).map { $0 }
        }
        if frames.isEmpty { return [] }

        // Image generator for frames
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Vision tracking setup
        let seqHandler = VNSequenceRequestHandler()
        var currentObservation = visionObservation(from: initialBox)
        var out: [TrackingResult] = []

        for frameNumber in frames {
            if isCancelled { throw TrackingError.cancelled }
            let time = CMTime(seconds: Double(frameNumber) / frameRate, preferredTimescale: 600)

            // Extract frame image
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                throw TrackingError.frameExtractionFailed
            }
            // Create tracking request from last observation
            let request = VNTrackObjectRequest(detectedObjectObservation: currentObservation)
            request.trackingLevel = .accurate

            // Perform tracking on this frame
            do {
                try seqHandler.perform([request], on: cgImage)
            } catch {
                throw TrackingError.trackingFailed
            }

            guard let newObservation = request.results?.first as? VNDetectedObjectObservation else {
                throw TrackingError.trackingFailed
            }

            // Convert Vision bbox back to our top-left normalized coords
            let ourBox = boundingBox(from: newObservation.boundingBox)
            currentObservation = newObservation
            let result = TrackingResult(
                frameNumber: frameNumber,
                boundingBox: ourBox,
                confidence: newObservation.confidence
            )
            out.append(result)

            // Progress on main thread
            Task { @MainActor in
                progressCallback(result)
            }
        }

        return out
    }

    // (All crop/preprocess helpers removed to restore the stable baseline tracker)

    // MARK: - Coordinate conversion
    // Our app stores bbox with origin at top-left (0,0) and y downward; Vision uses bottom-left origin.
    private func visionObservation(from box: BoundingBox) -> VNDetectedObjectObservation {
        let vx = CGFloat(box.x)
        let vy = CGFloat(1.0 - box.y - box.height)
        let vw = CGFloat(box.width)
        let vh = CGFloat(box.height)
        let vRect = CGRect(x: vx, y: vy, width: vw, height: vh)
        return VNDetectedObjectObservation(boundingBox: vRect)
    }

    private func boundingBox(from visionRect: CGRect) -> BoundingBox {
        // Convert Vision (bottom-left) to our top-left normalized
        let x = Double(visionRect.origin.x)
        let yTopLeft = Double(1.0 - visionRect.origin.y - visionRect.size.height)
        let w = Double(visionRect.size.width)
        let h = Double(visionRect.size.height)
        let clampedX = max(0.0, min(1.0, x))
        let clampedY = max(0.0, min(1.0, yTopLeft))
        let clampedW = max(0.0, min(1.0 - clampedX, w))
        let clampedH = max(0.0, min(1.0 - clampedY, h))
        return BoundingBox(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
    }
}
