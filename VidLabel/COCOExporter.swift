//
//  COCOExporter.swift
//  VidLabel
//
//  Export annotations to COCO format
//

import Foundation
import CoreGraphics

class COCOExporter {

    struct COCODataset: Codable {
        let info: Info
        let images: [Image]
        let annotations: [Annotation]
        let categories: [Category]

        struct Info: Codable {
            let description: String
            let version: String
            let year: Int
            let contributor: String
            let date_created: String
        }

        struct Image: Codable {
            let id: Int
            let width: Int
            let height: Int
            let file_name: String
            let frame_number: Int
        }

        struct Annotation: Codable {
            let id: Int
            let image_id: Int
            let category_id: Int
            let bbox: [Double]  // [x, y, width, height] in pixels
            let area: Double
            let iscrowd: Int
        }

        struct Category: Codable {
            let id: Int
            let name: String
            let supercategory: String
        }
    }

    /// Export tracked objects to COCO format JSON
    static func exportToCOCO(
        trackedObjects: [TrackedObject],
        videoSize: CGSize,
        videoFileName: String,
        outputURL: URL
    ) throws {
        // Info
        let dateFormatter = ISO8601DateFormatter()
        let info = COCODataset.Info(
            description: "Video annotations from VidLabel",
            version: "1.0",
            year: Calendar.current.component(.year, from: Date()),
            contributor: "VidLabel",
            date_created: dateFormatter.string(from: Date())
        )

        // Categories - all objects are class 1
        let categories = [
            COCODataset.Category(id: 1, name: "object", supercategory: "object")
        ]

        // Collect all frames that have annotations
        var frameSet = Set<Int>()
        for obj in trackedObjects {
            frameSet.formUnion(obj.annotations.keys)
        }
        let sortedFrames = frameSet.sorted()

        // Create images (one per frame with annotations)
        var images: [COCODataset.Image] = []
        var frameToImageId: [Int: Int] = [:]
        for (index, frameNumber) in sortedFrames.enumerated() {
            let imageId = index + 1
            frameToImageId[frameNumber] = imageId

            images.append(COCODataset.Image(
                id: imageId,
                width: Int(videoSize.width),
                height: Int(videoSize.height),
                file_name: "\(videoFileName)_frame_\(String(format: "%06d", frameNumber)).jpg",
                frame_number: frameNumber
            ))
        }

        // Create annotations
        var annotations: [COCODataset.Annotation] = []
        var annotationId = 1

        for obj in trackedObjects {
            for (frameNumber, box) in obj.annotations {
                guard let imageId = frameToImageId[frameNumber] else { continue }

                // Convert normalized bbox to pixel coordinates
                let pixelRect = box.rect(in: videoSize)

                // COCO bbox format: [x, y, width, height]
                let cocoBox = [
                    Double(pixelRect.origin.x),
                    Double(pixelRect.origin.y),
                    Double(pixelRect.size.width),
                    Double(pixelRect.size.height)
                ]

                let area = Double(pixelRect.size.width * pixelRect.size.height)

                annotations.append(COCODataset.Annotation(
                    id: annotationId,
                    image_id: imageId,
                    category_id: 1,  // All objects are class 1
                    bbox: cocoBox,
                    area: area,
                    iscrowd: 0
                ))

                annotationId += 1
            }
        }

        // Create final dataset
        let dataset = COCODataset(
            info: info,
            images: images,
            annotations: annotations,
            categories: categories
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(dataset)

        // Write to file
        try jsonData.write(to: outputURL)
    }

    /// Export frame-by-frame annotations (one JSON per frame)
    static func exportFrameByFrame(
        trackedObjects: [TrackedObject],
        videoSize: CGSize,
        outputDirectory: URL
    ) throws {
        // Create output directory if needed
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Collect all frames
        var frameAnnotations: [Int: [(TrackedObject, BoundingBox)]] = [:]
        for obj in trackedObjects {
            for (frameNumber, box) in obj.annotations {
                if frameAnnotations[frameNumber] == nil {
                    frameAnnotations[frameNumber] = []
                }
                frameAnnotations[frameNumber]?.append((obj, box))
            }
        }

        // Write one file per frame
        for (frameNumber, annotations) in frameAnnotations {
            var frameData: [[String: Any]] = []

            for (obj, box) in annotations {
                let pixelRect = box.rect(in: videoSize)

                let annotation: [String: Any] = [
                    "category_id": 1,
                    "label": obj.label,
                    "bbox": [
                        Double(pixelRect.origin.x),
                        Double(pixelRect.origin.y),
                        Double(pixelRect.size.width),
                        Double(pixelRect.size.height)
                    ]
                ]
                frameData.append(annotation)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: frameData, options: .prettyPrinted)
            let fileName = "frame_\(String(format: "%06d", frameNumber)).json"
            let fileURL = outputDirectory.appendingPathComponent(fileName)
            try jsonData.write(to: fileURL)
        }
    }
}
