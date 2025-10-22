//
//  DrawingOverlayView.swift
//  VidLabel
//
//  Overlay for drawing and displaying ROIs
//

import SwiftUI
import AVKit
import AVFoundation

struct DrawingOverlayView: View {
    @ObservedObject var annotationViewModel: AnnotationViewModel
    let currentFrame: Int
    let videoSize: CGSize
    let videoPlayer: AVPlayer?

    @State private var hoveredBoxId: UUID?

    var body: some View {
        GeometryReader { geometry in
            let annotations = annotationViewModel.getAnnotations(at: currentFrame)
            let proposals = annotationViewModel.getProposalAnnotations(at: currentFrame)

            // Debug logging
            let _ = {
                print("📺 VIEW SIZE: \(Int(geometry.size.width))x\(Int(geometry.size.height)), VIDEO SIZE: \(Int(videoSize.width))x\(Int(videoSize.height))")
                if !annotations.isEmpty {
                    for item in annotations {
                        let pixelRect = item.box.rect(in: videoSize)
                        print("🎨 DISPLAY Frame \(currentFrame): \(item.object.label) at x=\(Int(pixelRect.minX))px, y=\(Int(pixelRect.minY))px (normalized: x=\(String(format: "%.4f", item.box.x)), y=\(String(format: "%.4f", item.box.y)))")
                    }
                }
            }()

            ZStack {
                // Detection proposals (dashed, semi-transparent)
                ForEach(proposals, id: \.proposal.id) { item in
                    let state = item.proposal.state(at: currentFrame)
                    ProposalBoxView(
                        box: item.box,
                        color: item.proposal.color,
                        state: state ?? .detected,
                        geometry: geometry,
                        videoSize: videoSize
                    )
                }

                // Existing annotations
                ForEach(annotations, id: \.object.id) { item in
                    BoundingBoxView(
                        box: item.box,
                        color: item.object.color,
                        label: item.object.label,
                        isSelected: annotationViewModel.selectedObjectId == item.object.id,
                        isHovered: hoveredBoxId == item.object.id,
                        geometry: geometry,
                        videoSize: videoSize
                    )
                    .onTapGesture {
                        annotationViewModel.selectObject(id: item.object.id)
                    }
                }

                // Current drawing preview
                if annotationViewModel.isDrawingMode,
                   let start = annotationViewModel.currentDrawingStart,
                   let end = annotationViewModel.currentDrawingEnd,
                   let selectedObject = annotationViewModel.selectedObject {
                    let box = BoundingBox.from(startPoint: start, endPoint: end)
                    BoundingBoxView(
                        box: box,
                        color: selectedObject.color,
                        label: selectedObject.label,
                        isSelected: true,
                        isHovered: false,
                        geometry: geometry,
                        videoSize: videoSize,
                        isDraft: true
                    )
                }

                // Invisible overlay for mouse events
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let normalizedPoint = normalizePoint(value.location, in: geometry.size, videoSize: videoSize)

                                if annotationViewModel.isDrawingMode {
                                    annotationViewModel.updateDrawing(to: normalizedPoint)
                                } else {
                                    // Start new drawing - pass actual view coordinates for zoom
                                    annotationViewModel.startDrawing(
                                        at: normalizedPoint,
                                        viewCoordinate: value.location,
                                        viewSize: geometry.size
                                    )
                                }
                            }
                            .onEnded { value in
                                let normalizedPoint = normalizePoint(value.location, in: geometry.size, videoSize: videoSize)
                                annotationViewModel.updateDrawing(to: normalizedPoint)

                                if let box = annotationViewModel.finishDrawing(),
                                   let selectedId = annotationViewModel.selectedObjectId {
                                    annotationViewModel.addAnnotation(
                                        boundingBox: box,
                                        frameNumber: currentFrame,
                                        objectId: selectedId
                                    )
                                }
                            }
                    )
            }
        }
    }

    /// Normalize a point from view coordinates to 0.0-1.0 range (relative to video, not view)
    private func normalizePoint(_ point: CGPoint, in viewSize: CGSize, videoSize: CGSize) -> CGPoint {
        // Calculate actual video display rect (accounting for aspect ratio)
        let videoRect = AVMakeRect(aspectRatio: videoSize, insideRect: CGRect(origin: .zero, size: viewSize))

        // Convert point from view coordinates to video-relative coordinates
        let videoX = (point.x - videoRect.minX) / videoRect.width
        let videoY = (point.y - videoRect.minY) / videoRect.height

        return CGPoint(
            x: max(0, min(1, videoX)),
            y: max(0, min(1, videoY))
        )
    }
}

/// View for rendering a single bounding box
struct BoundingBoxView: View {
    let box: BoundingBox
    let color: CodableColor
    let label: String
    let isSelected: Bool
    let isHovered: Bool
    let geometry: GeometryProxy
    let videoSize: CGSize
    var isDraft: Bool = false

    var body: some View {
        // Calculate actual video display rect (accounting for aspect ratio)
        let videoRect = AVMakeRect(aspectRatio: videoSize, insideRect: CGRect(origin: .zero, size: geometry.size))

        // Convert normalized coordinates to video pixels
        let videoPixelRect = box.rect(in: videoSize)

        // Scale to displayed size
        let scale = videoRect.width / videoSize.width
        let displayRect = CGRect(
            x: videoRect.minX + videoPixelRect.minX * scale,
            y: videoRect.minY + videoPixelRect.minY * scale,
            width: videoPixelRect.width * scale,
            height: videoPixelRect.height * scale
        )

        let rect = displayRect
        let nsColor = Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )

        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            Rectangle()
                .strokeBorder(
                    nsColor,
                    lineWidth: isSelected ? 3 : (isHovered ? 2.5 : 2)
                )
                .background(
                    nsColor.opacity(isDraft ? 0.15 : (isSelected ? 0.1 : 0.05))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Label
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(nsColor.opacity(0.9))
                .cornerRadius(4)
                .offset(x: rect.minX, y: rect.minY - 20)
        }
    }
}

/// View for rendering a detection proposal (dashed box)
struct ProposalBoxView: View {
    let box: BoundingBox
    let color: CodableColor
    let state: DetectionState
    let geometry: GeometryProxy
    let videoSize: CGSize

    var body: some View {
        // Calculate actual video display rect (accounting for aspect ratio)
        let videoRect = AVMakeRect(aspectRatio: videoSize, insideRect: CGRect(origin: .zero, size: geometry.size))

        // Convert normalized coordinates to video pixels
        let videoPixelRect = box.rect(in: videoSize)

        // Scale to displayed size
        let scale = videoRect.width / videoSize.width
        let displayRect = CGRect(
            x: videoRect.minX + videoPixelRect.minX * scale,
            y: videoRect.minY + videoPixelRect.minY * scale,
            width: videoPixelRect.width * scale,
            height: videoPixelRect.height * scale
        )

        let rect = displayRect

        // Green for detected, blue for predicted
        let boxColor = state == .detected ? Color.green : Color.blue

        ZStack(alignment: .topLeading) {
            // Dashed bounding box
            Rectangle()
                .stroke(
                    boxColor,
                    style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                )
                .background(
                    boxColor.opacity(0.1)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // State indicator
            Text(state == .detected ? "DETECTED" : "PREDICTED")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(boxColor.opacity(0.8))
                .cornerRadius(3)
                .offset(x: rect.minX, y: rect.minY - 18)
        }
    }
}
