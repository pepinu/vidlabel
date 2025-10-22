//
//  ContentView.swift
//  VidLabel
//
//  Main application interface
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = VideoPlayerViewModel()
    @StateObject private var annotationViewModel = AnnotationViewModel()
    @State private var isDraggingTimeline = false
    @State private var showObjectsSidebar = true
    @State private var showAutoDetectPanel = false

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack {
                Text("VidLabel")
                    .font(.headline)

                Spacer()

                if viewModel.isVideoLoaded {
                    // Auto-Detect toggle
                    Button(action: {
                        showAutoDetectPanel.toggle()
                        if showAutoDetectPanel {
                            showObjectsSidebar = false
                        }
                    }) {
                        Image(systemName: "wand.and.stars")
                        Text(showAutoDetectPanel ? "Hide Auto-Detect" : "Auto-Detect")
                    }
                    .buttonStyle(.bordered)

                    // Export COCO
                    Button(action: {
                        exportCOCO()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export COCO")
                    }
                    .buttonStyle(.bordered)
                    .disabled(annotationViewModel.trackedObjects.isEmpty)

                    if !showObjectsSidebar {
                        Button(action: {
                            showObjectsSidebar = true
                            showAutoDetectPanel = false
                        }) {
                            Image(systemName: "sidebar.right")
                            Text("Show Objects")
                        }
                    }
                }

                Button("Load Video") {
                    loadVideo()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Main content area
            if viewModel.isVideoLoaded {
                videoContentView
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 1280, minHeight: 720)
        .onKeyPress(.delete) {
            handleDeleteKey()
            return .handled
        }
    }

    // MARK: - Keyboard Shortcuts

    private func handleDeleteKey() {
        guard let selectedId = annotationViewModel.selectedObjectId else { return }

        // Delete annotation on current frame
        annotationViewModel.removeAnnotation(at: viewModel.currentFrameNumber, objectId: selectedId)
    }

    // MARK: - Video Content View

    private var videoContentView: some View {
        HStack(spacing: 0) {
            // Auto-Detect panel (left side)
            if showAutoDetectPanel {
                AutoDetectPanelView(
                    annotationVM: annotationViewModel,
                    playerVM: viewModel
                )
                Divider()
            }

            // Main video area
            VStack(spacing: 0) {
                // Video canvas with drawing overlay
                GeometryReader { geometry in
                    ZStack {
                        Color.black

                        let zoomScale: CGFloat = annotationViewModel.isZoomed ? 1.7 : 1.0
                        let zoomOffset = calculateZoomOffset(
                            center: annotationViewModel.zoomCenter,
                            scale: zoomScale,
                            viewSize: annotationViewModel.zoomViewSize
                        )

                        if let player = viewModel.getPlayer() {
                            VideoPlayerView(player: player)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .scaleEffect(zoomScale, anchor: .topLeading)
                                .offset(x: zoomOffset.width, y: zoomOffset.height)
                        }

                        // Drawing overlay

                        DrawingOverlayView(
                            annotationViewModel: annotationViewModel,
                            currentFrame: viewModel.currentFrameNumber,
                            videoSize: viewModel.videoSize,
                            videoPlayer: viewModel.getPlayer()
                        )
                        .scaleEffect(zoomScale, anchor: .topLeading)
                        .offset(x: zoomOffset.width, y: zoomOffset.height)
                        .allowsHitTesting(annotationViewModel.selectedObjectId != nil)

                        // Video info overlay
                        VStack {
                            // Top-right: Frame info
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Frame: \(viewModel.currentFrameNumber) / \(viewModel.totalFrames)")
                                    Text("Size: \(Int(viewModel.videoSize.width))×\(Int(viewModel.videoSize.height))")
                                    if let selectedObject = annotationViewModel.selectedObject {
                                        Divider()
                                            .background(Color.white)
                                        Text("Drawing: \(selectedObject.label)")
                                            .foregroundColor(Color(red: selectedObject.color.red,
                                                                 green: selectedObject.color.green,
                                                                 blue: selectedObject.color.blue))
                                        Text("Delete: ⌫")
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray)
                                    }
                                }
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .padding()
                            }

                            Spacer()

                            // Bottom-left: Instructions
                            if annotationViewModel.trackedObjects.isEmpty {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Click 'Add Object' to start")
                                        Text("2. Drag on video to draw ROI")
                                        Text("3. Use ← → to navigate frames")
                                    }
                                    .font(.system(.caption))
                                    .padding(8)
                                    .background(Color.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                    .padding()
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // Playback controls
                playbackControlsView
            }

            // Objects sidebar
            if showObjectsSidebar {
                objectsSidebarView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 72))
                .foregroundColor(.gray)

            Text("No Video Loaded")
                .font(.title2)

            Text("Click 'Load Video' or drag and drop a video file")
                .foregroundColor(.secondary)

            Button("Load Video") {
                loadVideo()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Playback Controls

    private var playbackControlsView: some View {
        VStack(spacing: 12) {
            // Timeline slider
            HStack(spacing: 12) {
                Text(viewModel.currentTimeString)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                            .cornerRadius(3)

                        // Progress
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * viewModel.progress, height: 6)
                            .cornerRadius(3)

                        // Playhead
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .shadow(radius: 2)
                            .offset(x: geometry.size.width * viewModel.progress - 8)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingTimeline = true
                                let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                viewModel.seekToProgress(progress)
                            }
                            .onEnded { _ in
                                isDraggingTimeline = false
                            }
                    )
                }
                .frame(height: 20)

                Text(viewModel.durationString)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 70, alignment: .leading)
            }
            .padding(.horizontal)

            // Transport controls
            HStack(spacing: 20) {
                // Step backward
                Button(action: { viewModel.stepBackward() }) {
                    Image(systemName: "backward.frame.fill")
                        .font(.title2)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Previous frame (←)")

                // Play/Pause
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 30)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Play/Pause (Space)")

                // Step forward
                Button(action: { viewModel.stepForward() }) {
                    Image(systemName: "forward.frame.fill")
                        .font(.title2)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Next frame (→)")
            }
            .padding(.bottom, 8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Objects Sidebar

    private var objectsSidebarView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Objects")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showObjectsSidebar = false
                }) {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
                .help("Hide sidebar")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Tracking progress indicator
            if annotationViewModel.isTracking {
                VStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text(annotationViewModel.trackingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Cancel") {
                        annotationViewModel.cancelTracking()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))

                Divider()
            }

            // Objects list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(annotationViewModel.trackedObjects) { object in
                        ObjectRowView(
                            object: object,
                            isSelected: annotationViewModel.selectedObjectId == object.id,
                            currentFrame: viewModel.currentFrameNumber,
                            onSelect: {
                                annotationViewModel.selectObject(id: object.id)
                            },
                            onDelete: {
                                annotationViewModel.deleteObject(id: object.id)
                            },
                            onTrackForward: annotationViewModel.isTracking ? nil : {
                                guard let asset = viewModel.getAsset() else { return }
                                annotationViewModel.startTrackingForward(
                                    objectId: object.id,
                                    fromFrame: viewModel.currentFrameNumber,
                                    toFrame: viewModel.totalFrames - 1,
                                    asset: asset,
                                    videoURL: viewModel.getVideoURL(),
                                    frameRate: viewModel.getFrameRate()
                                )
                            },
                            onTrackBackward: annotationViewModel.isTracking ? nil : {
                                guard let asset = viewModel.getAsset() else { return }
                                annotationViewModel.startTrackingBackward(
                                    objectId: object.id,
                                    fromFrame: viewModel.currentFrameNumber,
                                    toFrame: 0,
                                    asset: asset,
                                    videoURL: viewModel.getVideoURL(),
                                    frameRate: viewModel.getFrameRate()
                                )
                            },
                            onTrimAfter: {
                                annotationViewModel.trimAnnotationsAfter(objectId: object.id, frameNumber: viewModel.currentFrameNumber)
                            },
                            onTrimBefore: {
                                annotationViewModel.trimAnnotationsBefore(objectId: object.id, frameNumber: viewModel.currentFrameNumber)
                            }
                        )
                    }
                }
                .padding(8)
            }

            Divider()

            // Tracker info (Vision only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tracker")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text("Apple Vision (VNTrackObjectRequest)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Expand boxes control
            ExpandBoxesControl(annotationViewModel: annotationViewModel, videoSize: viewModel.videoSize)

            Divider()

            // Add object button
            Button(action: {
                _ = annotationViewModel.addObject()
                viewModel.pause() // Pause video when adding a new object
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Object")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 250)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helper Methods

    private func calculateZoomOffset(center: CGPoint, scale: CGFloat, viewSize: CGSize) -> CGSize {
        if scale <= 1.0 {
            return .zero
        }

        // To keep the clicked point visually in the same position after scaling:
        // If we click at (x, y) and scale by S with anchor topLeading,
        // we need to offset by (x*(1-S), y*(1-S))
        let offsetX = center.x * (1.0 - scale)
        let offsetY = center.y * (1.0 - scale)

        // Clamp the offset so we don't scroll beyond video bounds
        let scaledWidth = viewSize.width * scale
        let scaledHeight = viewSize.height * scale

        let maxOffsetX = scaledWidth - viewSize.width
        let maxOffsetY = scaledHeight - viewSize.height

        let clampedX = max(-maxOffsetX, min(0, offsetX))
        let clampedY = max(-maxOffsetY, min(0, offsetY))

        return CGSize(width: clampedX, height: clampedY)
    }

    private func loadVideo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Select a video file to annotate"

        // Set initial directory to test_footage if it exists
        let testFootageURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("test_footage")
        if FileManager.default.fileExists(atPath: testFootageURL.path) {
            panel.directoryURL = testFootageURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadVideo(url: url)
        }
    }

    private func exportCOCO() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "annotations.json"
        panel.message = "Export annotations to COCO format"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let videoFileName = viewModel.getVideoURL()?.deletingPathExtension().lastPathComponent ?? "video"
                try COCOExporter.exportToCOCO(
                    trackedObjects: annotationViewModel.trackedObjects,
                    videoSize: viewModel.videoSize,
                    videoFileName: videoFileName,
                    outputURL: url
                )
                print("✅ COCO export successful: \(url.path)")
            } catch {
                print("❌ COCO export failed: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Expand Boxes Control

private struct ExpandBoxesControl: View {
    @ObservedObject var annotationViewModel: AnnotationViewModel
    let videoSize: CGSize
    @State private var pixels: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adjust Boxes")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text("Pixels:")
                    .font(.caption)
                TextField("px", value: $pixels, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Button("Apply to Selected") {
                    if let id = annotationViewModel.selectedObjectId {
                        annotationViewModel.expandAllBoxes(objectId: id, byPixels: pixels, videoSize: videoSize)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(annotationViewModel.selectedObjectId == nil)
            }

            // Nudge controls
            HStack(spacing: 8) {
                Text("Nudge by")
                    .font(.caption)
                Text("\(Int(pixels)) px")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Group {
                    Button { nudge(dx: -pixels, dy: 0) } label: {
                        Image(systemName: "arrow.left")
                    }
                    Button { nudge(dx: pixels, dy: 0) } label: {
                        Image(systemName: "arrow.right")
                    }
                    Button { nudge(dx: 0, dy: -pixels) } label: {
                        Image(systemName: "arrow.up")
                    }
                    Button { nudge(dx: 0, dy: pixels) } label: {
                        Image(systemName: "arrow.down")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(annotationViewModel.selectedObjectId == nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func nudge(dx: Double, dy: Double) {
        guard let id = annotationViewModel.selectedObjectId else { return }
        annotationViewModel.shiftAllBoxes(objectId: id, dxPixels: dx, dyPixels: dy, videoSize: videoSize)
    }
}
