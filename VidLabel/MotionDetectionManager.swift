//
//  MotionDetectionManager.swift
//  VidLabel
//
//  Motion-based object detection using OpenCV (Mode 2: Motion Consistency)
//  Exact implementation of track_motion2.py
//

import Foundation
import AVFoundation
import CoreGraphics

class MotionDetectionManager {

    // MARK: - Configuration
    struct Config {
        var minArea: Double = 100.0           // Minimum object area in pixels (~10×10)
        var maxJumpDistance: Double = 100.0   // Maximum allowed motion between frames
        var maxMisses: Int = 15               // Frames before reset
        var smoothAlpha: Double = 0.5         // Velocity smoothing factor (0-1)
        var history: Int = 500                // MOG2 history
        var varThreshold: Double = 25.0       // MOG2 variance threshold
    }

    struct DetectionResult {
        let frameNumber: Int
        let boundingBox: BoundingBox
        let confidence: Float
        let state: DetectionState
    }

    struct DetectedObject {
        let id: UUID
        var annotations: [Int: BoundingBox]
        var confidence: [Int: Float]
        var detectionState: [Int: DetectionState]
    }

    enum DetectionError: Error {
        case frameExtractionFailed
        case cancelled
        case noObjectsDetected
    }

    private var isCancelled = false
    private let config: Config
    private var detector: MotionDetector?

    init(config: Config = Config()) {
        self.config = config
    }

    func cancel() {
        isCancelled = true
    }

    // MARK: - Main Detection Method

    /// Performs motion-based object detection across a range of frames using OpenCV
    func autoDetect(
        asset: AVAsset,
        frameRange: ClosedRange<Int>,
        frameRate: Double,
        videoSize: CGSize,
        progressCallback: @escaping (Int, Int, Int) -> Void // (current, total, frameNumber)
    ) async throws -> [DetectedObject] {
        isCancelled = false

        let frames = Array(frameRange)
        guard !frames.isEmpty else { return [] }

        // Create OpenCV detector (MOG2 background subtractor)
        detector = MotionDetector(history: Int32(config.history), varThreshold: config.varThreshold)
        detector?.minArea = config.minArea
        detector?.maxJumpDistance = config.maxJumpDistance
        detector?.maxMisses = Int32(config.maxMisses)
        detector?.smoothAlpha = config.smoothAlpha

        // Image generator for frame extraction
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var results: [DetectionResult] = []

        // Process each frame
        for (index, frameNumber) in frames.enumerated() {
            if isCancelled { throw DetectionError.cancelled }

            let time = CMTime(seconds: Double(frameNumber) / frameRate, preferredTimescale: 600)

            // Extract frame
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                continue
            }

            // Process frame through OpenCV detector
            guard let detectionResult = detector?.processFrame(cgImage) else {
                continue
            }

            // Store result if valid
            if detectionResult.isValid {
                // Convert to normalized coordinates
                let normalizedBox = BoundingBox(
                    x: Double(detectionResult.boundingBox.origin.x / videoSize.width),
                    y: Double(detectionResult.boundingBox.origin.y / videoSize.height),
                    width: Double(detectionResult.boundingBox.size.width / videoSize.width),
                    height: Double(detectionResult.boundingBox.size.height / videoSize.height)
                )

                let state: DetectionState = detectionResult.isDetected ? .detected : .predicted
                let confidence: Float = detectionResult.isDetected ? 0.9 : 0.5

                let result = DetectionResult(
                    frameNumber: frameNumber,
                    boundingBox: normalizedBox,
                    confidence: confidence,
                    state: state
                )
                results.append(result)
            }

            // Progress callback
            await MainActor.run {
                progressCallback(index + 1, frames.count, frameNumber)
            }
        }

        // Convert results to DetectedObject
        if results.isEmpty {
            throw DetectionError.noObjectsDetected
        }

        var annotations: [Int: BoundingBox] = [:]
        var confidences: [Int: Float] = [:]
        var states: [Int: DetectionState] = [:]

        for result in results {
            annotations[result.frameNumber] = result.boundingBox
            confidences[result.frameNumber] = result.confidence
            states[result.frameNumber] = result.state
        }

        let detectedObject = DetectedObject(
            id: UUID(),
            annotations: annotations,
            confidence: confidences,
            detectionState: states
        )

        return [detectedObject]
    }
}
