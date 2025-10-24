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
    @State private var showSegmentPanel = false
    @State private var showProgressPanel = false
    @State private var selectedCategoryForNewObject: UUID? = nil
    @State private var showCategoryManager = false

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack {
                Text("VidLabel")
                    .font(.headline)

                Spacer()

                if viewModel.isVideoLoaded {
                    // Progress toggle
                    Button(action: {
                        showProgressPanel.toggle()
                        if showProgressPanel {
                            showObjectsSidebar = false
                            showAutoDetectPanel = false
                            showSegmentPanel = false
                        }
                    }) {
                        Image(systemName: "chart.bar.fill")
                        Text(showProgressPanel ? "Hide Progress" : "Progress")
                    }
                    .buttonStyle(.bordered)

                    // Segment toggle
                    Button(action: {
                        showSegmentPanel.toggle()
                        if showSegmentPanel {
                            showObjectsSidebar = false
                            showAutoDetectPanel = false
                            showProgressPanel = false
                        }
                    }) {
                        Image(systemName: "rectangle.3.group")
                        Text(showSegmentPanel ? "Hide Segments" : "Segments")
                    }
                    .buttonStyle(.bordered)

                    // Auto-Detect toggle
                    Button(action: {
                        showAutoDetectPanel.toggle()
                        if showAutoDetectPanel {
                            showObjectsSidebar = false
                            showSegmentPanel = false
                            showProgressPanel = false
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
                            showSegmentPanel = false
                            showProgressPanel = false
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
        .onKeyPress(.upArrow) {
            handleUpArrowKey()
            return .handled
        }
        .onKeyPress(.downArrow) {
            handleDownArrowKey()
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            // Shift + Right Arrow: Jump to next annotation
            if press.key == .rightArrow && press.modifiers.contains(.shift) {
                jumpToNextAnnotation()
                return .handled
            }
            // Shift + Left Arrow: Jump to previous annotation
            if press.key == .leftArrow && press.modifiers.contains(.shift) {
                jumpToPreviousAnnotation()
                return .handled
            }
            // Cmd + Z: Undo
            if press.key == KeyEquivalent("z") && press.modifiers.contains(.command) && !press.modifiers.contains(.shift) {
                handleUndo()
                return .handled
            }
            // Cmd + Shift + Z: Redo
            if press.key == KeyEquivalent("z") && press.modifiers.contains(.command) && press.modifiers.contains(.shift) {
                handleRedo()
                return .handled
            }
            // Cmd + C: Copy
            if press.key == KeyEquivalent("c") && press.modifiers.contains(.command) {
                handleCopy()
                return .handled
            }
            // Cmd + V: Paste
            if press.key == KeyEquivalent("v") && press.modifiers.contains(.command) {
                handlePaste()
                return .handled
            }
            return .ignored
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerView(annotationVM: annotationViewModel)
        }
    }

    // MARK: - Keyboard Shortcuts

    private func handleDeleteKey() {
        guard let selectedId = annotationViewModel.selectedObjectId else { return }

        // Delete annotation on current frame
        annotationViewModel.removeAnnotation(at: viewModel.currentFrameNumber, objectId: selectedId)
    }

    private func handleUpArrowKey() {
        // Up Arrow: Jump to previous frame with selected object's annotation
        if let frame = annotationViewModel.getPreviousFrameForSelectedObject(from: viewModel.currentFrameNumber) {
            viewModel.seekToFrame(frame)
        }
    }

    private func handleDownArrowKey() {
        // Down Arrow: Jump to next frame with selected object's annotation
        if let frame = annotationViewModel.getNextFrameForSelectedObject(from: viewModel.currentFrameNumber) {
            viewModel.seekToFrame(frame)
        }
    }

    private func jumpToNextAnnotation() {
        if let frame = annotationViewModel.getNextAnnotatedFrame(from: viewModel.currentFrameNumber, totalFrames: viewModel.totalFrames) {
            viewModel.seekToFrame(frame)
        }
    }

    private func jumpToPreviousAnnotation() {
        if let frame = annotationViewModel.getPreviousAnnotatedFrame(from: viewModel.currentFrameNumber) {
            viewModel.seekToFrame(frame)
        }
    }

    private func handleUndo() {
        annotationViewModel.undoManager.undo(viewModel: annotationViewModel)
    }

    private func handleRedo() {
        annotationViewModel.undoManager.redo(viewModel: annotationViewModel)
    }

    private func handleCopy() {
        guard let selectedId = annotationViewModel.selectedObjectId else { return }
        annotationViewModel.copyAnnotation(objectId: selectedId, frameNumber: viewModel.currentFrameNumber)
    }

    private func handlePaste() {
        guard let selectedId = annotationViewModel.selectedObjectId else { return }
        guard annotationViewModel.hasClipboard else { return }
        annotationViewModel.pasteAnnotation(toObjectId: selectedId, toFrame: viewModel.currentFrameNumber)
    }

    // MARK: - Video Content View

    private var videoContentView: some View {
        HStack(spacing: 0) {
            // Progress panel (left side)
            if showProgressPanel {
                ProgressStatsView(
                    annotationVM: annotationViewModel,
                    totalFrames: viewModel.totalFrames
                )
                Divider()
            }

            // Segment panel (left side)
            if showSegmentPanel {
                SegmentPanelView(
                    annotationVM: annotationViewModel,
                    currentFrame: viewModel.currentFrameNumber,
                    totalFrames: viewModel.totalFrames,
                    onJumpToFrame: { frame in
                        viewModel.seekToFrame(frame)
                    }
                )
                Divider()
            }

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
                        .allowsHitTesting(annotationViewModel.selectedObjectId != nil || annotationViewModel.isDrawingDetectionROI || annotationViewModel.isDrawingDeadZone)

                        // Video info overlay
                        VStack {
                            // Top-right: Frame info
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Frame: \(viewModel.currentFrameNumber) / \(viewModel.totalFrames)")
                                    Text("Size: \(Int(viewModel.videoSize.width))×\(Int(viewModel.videoSize.height))")
                                    if annotationViewModel.isDrawingDetectionROI {
                                        Divider()
                                            .background(Color.white)
                                        Text("Drawing: Detection ROI")
                                            .foregroundColor(.purple)
                                        Text("Drag to draw ROI box")
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray)
                                    } else if annotationViewModel.isDrawingDeadZone {
                                        Divider()
                                            .background(Color.white)
                                        Text("Drawing: Dead Zone")
                                            .foregroundColor(.red)
                                        Text("Drag to draw exclusion zone")
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray)
                                    } else if let selectedObject = annotationViewModel.selectedObject {
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
            // Timeline Heatmap with Segments
            TimelineHeatmapView(
                annotationVM: annotationViewModel,
                currentFrame: viewModel.currentFrameNumber,
                totalFrames: viewModel.totalFrames,
                onSeek: { frame in
                    viewModel.seekToFrame(frame)
                }
            )
            .padding(.horizontal)

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

                Divider()
                    .frame(height: 30)

                // Volume controls
                HStack(spacing: 8) {
                    // Mute/Unmute button
                    Button(action: { viewModel.toggleMute() }) {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isMuted ? "Unmute (M)" : "Mute (M)")
                    .keyboardShortcut("m", modifiers: [])

                    // Volume slider
                    Slider(value: Binding(
                        get: { Double(viewModel.volume) },
                        set: { viewModel.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(width: 100)
                    .disabled(viewModel.isMuted)
                    .help("Volume")
                }
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

            // Visibility controls
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Opacity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $annotationViewModel.nonSelectedOpacity, in: 0.1...1.0)
                        .frame(maxWidth: 120)
                    Text("\(Int(annotationViewModel.nonSelectedOpacity * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                    Button("Show All") {
                        annotationViewModel.showAllObjects()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Show all hidden objects")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color.secondary.opacity(0.1))

            Divider()

            // Category filter
            HStack(spacing: 8) {
                Text("Category:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $annotationViewModel.selectedCategoryFilter) {
                    Text("All").tag(nil as UUID?)
                    ForEach(annotationViewModel.categories) { category in
                        Text(category.name).tag(category.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)

                Button(action: {
                    showCategoryManager = true
                }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Manage categories")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Objects list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(annotationViewModel.filteredTrackedObjects) { object in
                        let category = object.categoryId.flatMap { catId in
                            annotationViewModel.categories.first(where: { $0.id == catId })
                        }

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
                            },
                            onDeleteFrame: {
                                annotationViewModel.deleteAnnotationAtFrame(objectId: object.id, frameNumber: viewModel.currentFrameNumber)
                            },
                            onInterpolate: { fromFrame, toFrame in
                                annotationViewModel.interpolate(objectId: object.id, fromFrame: fromFrame, toFrame: toFrame)
                            },
                            onToggleVisibility: {
                                annotationViewModel.toggleObjectVisibility(id: object.id)
                            },
                            onSolo: {
                                annotationViewModel.soloObject(id: object.id)
                            },
                            onCopy: object.boundingBox(at: viewModel.currentFrameNumber) != nil ? {
                                annotationViewModel.copyAnnotation(objectId: object.id, frameNumber: viewModel.currentFrameNumber)
                            } : nil,
                            onPaste: annotationViewModel.hasClipboard ? {
                                annotationViewModel.pasteAnnotation(toObjectId: object.id, toFrame: viewModel.currentFrameNumber)
                            } : nil,
                            onPasteToRange: annotationViewModel.hasClipboard ? { fromFrame, toFrame in
                                annotationViewModel.pasteAnnotationToRange(toObjectId: object.id, fromFrame: fromFrame, toFrame: toFrame)
                            } : nil,
                            hasClipboard: annotationViewModel.hasClipboard,
                            category: category
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

            // Category selection for new object
            VStack(alignment: .leading, spacing: 8) {
                Text("New Object Category:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Category", selection: $selectedCategoryForNewObject) {
                    Text("None").tag(nil as UUID?)
                    ForEach(annotationViewModel.categories) { category in
                        HStack {
                            Text(category.name)
                            if let supercategory = category.supercategory {
                                Text("(\(supercategory))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(category.id as UUID?)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal)
            .padding(.top)

            // Add object button
            Button(action: {
                _ = annotationViewModel.addObject(categoryId: selectedCategoryForNewObject)
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
