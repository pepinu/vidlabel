//
//  AnnotationModels.swift
//  VidLabel
//
//  Data models for annotations and regions of interest
//

import Foundation
import CoreGraphics

/// Represents a bounding box (Region of Interest)
struct BoundingBox: Identifiable, Codable, Equatable {
    let id: UUID
    var x: Double // Normalized coordinates (0.0 - 1.0)
    var y: Double
    var width: Double
    var height: Double

    init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Create a bounding box from two corner points (normalized coordinates)
    static func from(startPoint: CGPoint, endPoint: CGPoint) -> BoundingBox {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        return BoundingBox(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// Convert to CGRect in normalized coordinates
    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Convert to CGRect in actual pixel coordinates
    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

/// Represents a category for tracked objects
struct ObjectCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var supercategory: String?
    var color: CodableColor

    init(id: UUID = UUID(), name: String, supercategory: String? = nil, color: CodableColor = CodableColor.random()) {
        self.id = id
        self.name = name
        self.supercategory = supercategory
        self.color = color
    }

    // Default categories
    static let defaultCategories: [ObjectCategory] = [
        ObjectCategory(name: "Object", supercategory: nil, color: CodableColor(red: 0.5, green: 0.5, blue: 0.5)),
        ObjectCategory(name: "Person", supercategory: nil, color: CodableColor(red: 1.0, green: 0.5, blue: 0.5)),
        ObjectCategory(name: "Vehicle", supercategory: nil, color: CodableColor(red: 0.5, green: 0.5, blue: 1.0)),
        ObjectCategory(name: "Car", supercategory: "Vehicle", color: CodableColor(red: 0.3, green: 0.3, blue: 0.9)),
        ObjectCategory(name: "Truck", supercategory: "Vehicle", color: CodableColor(red: 0.4, green: 0.4, blue: 0.8)),
        ObjectCategory(name: "Animal", supercategory: nil, color: CodableColor(red: 0.5, green: 1.0, blue: 0.5)),
        ObjectCategory(name: "Dog", supercategory: "Animal", color: CodableColor(red: 0.3, green: 0.9, blue: 0.3)),
        ObjectCategory(name: "Cat", supercategory: "Animal", color: CodableColor(red: 0.4, green: 0.8, blue: 0.4))
    ]
}

/// Represents an object being tracked with annotations across frames
struct TrackedObject: Identifiable, Codable {
    let id: UUID
    var label: String
    var color: CodableColor
    var annotations: [Int: BoundingBox] // Frame number -> BoundingBox
    var isTracking: Bool // Whether this object is currently being tracked
    var isVisible: Bool // Whether this object is visible in the overlay
    var categoryId: UUID? // Optional category assignment

    init(id: UUID = UUID(), label: String = "Object", color: CodableColor = CodableColor.random(), categoryId: UUID? = nil) {
        self.id = id
        self.label = label
        self.color = color
        self.annotations = [:]
        self.isTracking = false
        self.isVisible = true
        self.categoryId = categoryId
    }

    /// Get bounding box for a specific frame
    func boundingBox(at frame: Int) -> BoundingBox? {
        return annotations[frame]
    }

    /// Set bounding box for a specific frame
    mutating func setBoundingBox(_ box: BoundingBox, at frame: Int) {
        annotations[frame] = box
    }

    /// Remove annotation at a specific frame
    mutating func removeAnnotation(at frame: Int) {
        annotations.removeValue(forKey: frame)
    }
}

/// Detection state for auto-detected objects
enum DetectionState: Codable, Equatable {
    case detected   // Detected via motion analysis
    case predicted  // Predicted position based on velocity
}

/// Represents a proposed detection from auto-detection (pending user review)
struct DetectionProposal: Identifiable, Codable {
    let id: UUID
    var annotations: [Int: BoundingBox]
    var confidence: [Int: Float]
    var detectionState: [Int: DetectionState]
    var color: CodableColor
    var isAccepted: Bool

    init(
        id: UUID = UUID(),
        annotations: [Int: BoundingBox] = [:],
        confidence: [Int: Float] = [:],
        detectionState: [Int: DetectionState] = [:],
        color: CodableColor = CodableColor.random(),
        isAccepted: Bool = false
    ) {
        self.id = id
        self.annotations = annotations
        self.confidence = confidence
        self.detectionState = detectionState
        self.color = color
        self.isAccepted = isAccepted
    }

    /// Get bounding box for a specific frame
    func boundingBox(at frame: Int) -> BoundingBox? {
        return annotations[frame]
    }

    /// Get detection state for a specific frame
    func state(at frame: Int) -> DetectionState? {
        return detectionState[frame]
    }

    /// Remove annotations in a frame range
    mutating func deleteFrames(in range: ClosedRange<Int>) {
        for frame in range {
            annotations.removeValue(forKey: frame)
            confidence.removeValue(forKey: frame)
            detectionState.removeValue(forKey: frame)
        }
    }

    /// Convert to TrackedObject (when user accepts)
    func toTrackedObject(label: String) -> TrackedObject {
        var obj = TrackedObject(id: UUID(), label: label, color: color)
        obj.annotations = annotations
        return obj
    }
}

/// Represents a video segment (chunk) for organizing long videos
struct VideoSegment: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var startFrame: Int
    var endFrame: Int
    var color: CodableColor
    var notes: String

    init(id: UUID = UUID(), name: String, startFrame: Int, endFrame: Int, color: CodableColor = CodableColor.randomPastel(), notes: String = "") {
        self.id = id
        self.name = name
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.color = color
        self.notes = notes
    }

    /// Check if a frame is within this segment
    func contains(frame: Int) -> Bool {
        return frame >= startFrame && frame <= endFrame
    }

    /// Get the duration of this segment in frames
    var frameCount: Int {
        return endFrame - startFrame + 1
    }
}

/// Codable wrapper for NSColor
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static func random() -> CodableColor {
        let colors: [CodableColor] = [
            CodableColor(red: 1.0, green: 0.3, blue: 0.3), // Red
            CodableColor(red: 0.3, green: 1.0, blue: 0.3), // Green
            CodableColor(red: 0.3, green: 0.3, blue: 1.0), // Blue
            CodableColor(red: 1.0, green: 1.0, blue: 0.3), // Yellow
            CodableColor(red: 1.0, green: 0.3, blue: 1.0), // Magenta
            CodableColor(red: 0.3, green: 1.0, blue: 1.0), // Cyan
        ]
        return colors.randomElement() ?? colors[0]
    }

    static func randomPastel() -> CodableColor {
        let colors: [CodableColor] = [
            CodableColor(red: 1.0, green: 0.7, blue: 0.7), // Pastel Red
            CodableColor(red: 0.7, green: 1.0, blue: 0.7), // Pastel Green
            CodableColor(red: 0.7, green: 0.7, blue: 1.0), // Pastel Blue
            CodableColor(red: 1.0, green: 1.0, blue: 0.7), // Pastel Yellow
            CodableColor(red: 1.0, green: 0.7, blue: 1.0), // Pastel Magenta
            CodableColor(red: 0.7, green: 1.0, blue: 1.0), // Pastel Cyan
            CodableColor(red: 1.0, green: 0.85, blue: 0.7), // Pastel Orange
        ]
        return colors.randomElement() ?? colors[0]
    }
}
