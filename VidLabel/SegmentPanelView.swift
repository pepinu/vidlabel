//
//  SegmentPanelView.swift
//  VidLabel
//
//  UI for managing video segments (chunks)
//

import SwiftUI

struct SegmentPanelView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    let currentFrame: Int
    let totalFrames: Int
    let onJumpToFrame: (Int) -> Void

    @State private var showAddSegmentSheet = false
    @State private var newSegmentName = ""
    @State private var newSegmentStart = ""
    @State private var newSegmentEnd = ""
    @State private var autoSegmentFrames = "3000"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Segments")
                    .font(.headline)

                Spacer()

                Button(action: {
                    newSegmentName = "Segment \(annotationVM.segments.count + 1)"
                    newSegmentStart = "\(currentFrame)"
                    newSegmentEnd = ""
                    showAddSegmentSheet = true
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.bordered)
                .help("Add new segment")
            }

            Divider()

            // Auto-segmentation
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-Segment")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    TextField("3000", text: $autoSegmentFrames)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Text("frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Create Equal Segments") {
                    autoSegment()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Automatically divide video into equal segments")
            }
            .padding(8)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(6)

            Divider()

            // Current segment info
            if let currentSegment = annotationVM.getSegment(at: currentFrame) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Segment")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Circle()
                            .fill(Color(red: currentSegment.color.red,
                                      green: currentSegment.color.green,
                                      blue: currentSegment.color.blue))
                            .frame(width: 8, height: 8)

                        Text(currentSegment.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Text("\(currentSegment.frameCount) frames")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            // Segments list
            if !annotationVM.segments.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(annotationVM.segments) { segment in
                            SegmentRowView(
                                segment: segment,
                                currentFrame: currentFrame,
                                onJump: {
                                    onJumpToFrame(segment.startFrame)
                                },
                                onDelete: {
                                    annotationVM.deleteSegment(id: segment.id)
                                }
                            )
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No segments yet")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Break your video into manageable chunks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }

            Spacer()
        }
        .padding()
        .frame(width: 280)
        .sheet(isPresented: $showAddSegmentSheet) {
            AddSegmentSheet(
                name: $newSegmentName,
                startFrame: $newSegmentStart,
                endFrame: $newSegmentEnd,
                onAdd: {
                    addSegment()
                },
                onCancel: {
                    showAddSegmentSheet = false
                }
            )
        }
    }

    private func addSegment() {
        let start = Int(newSegmentStart) ?? 0
        let end = Int(newSegmentEnd) ?? 0

        guard !newSegmentName.isEmpty, start >= 0, end >= start else {
            return
        }

        annotationVM.addSegment(name: newSegmentName, startFrame: start, endFrame: end)
        showAddSegmentSheet = false
    }

    private func autoSegment() {
        guard let framesPerSegment = Int(autoSegmentFrames), framesPerSegment > 0 else {
            return
        }

        annotationVM.autoSegment(totalFrames: totalFrames, framesPerSegment: framesPerSegment)
    }
}

struct SegmentRowView: View {
    let segment: VideoSegment
    let currentFrame: Int
    let onJump: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color(red: segment.color.red,
                              green: segment.color.green,
                              blue: segment.color.blue))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Frames \(segment.startFrame) - \(segment.endFrame)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete segment")
            }

            HStack(spacing: 4) {
                Button("Jump to Start") {
                    onJump()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("\(segment.frameCount) frames")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Show if current frame is in this segment
            if segment.contains(frame: currentFrame) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text("You are here")
                        .font(.caption2)
                }
                .foregroundColor(.blue)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}

struct AddSegmentSheet: View {
    @Binding var name: String
    @Binding var startFrame: String
    @Binding var endFrame: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Segment")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name:")
                TextField("Segment name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Text("Start Frame:")
                TextField("0", text: $startFrame)
                    .textFieldStyle(.roundedBorder)

                Text("End Frame:")
                TextField("100", text: $endFrame)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}
