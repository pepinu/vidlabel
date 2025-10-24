//
//  ObjectRowView.swift
//  VidLabel
//
//  Row view for displaying a tracked object in the sidebar
//

import SwiftUI

struct ObjectRowView: View {
    let object: TrackedObject
    let isSelected: Bool
    let currentFrame: Int
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTrackForward: (() -> Void)?
    let onTrackBackward: (() -> Void)?
    let onTrimAfter: (() -> Void)?
    let onTrimBefore: (() -> Void)?
    let onDeleteFrame: (() -> Void)?
    let onInterpolate: ((Int, Int) -> Void)?
    let onToggleVisibility: (() -> Void)?
    let onSolo: (() -> Void)?
    let onCopy: (() -> Void)?
    let onPaste: (() -> Void)?
    let onPasteToRange: ((Int, Int) -> Void)?
    let hasClipboard: Bool
    let category: ObjectCategory? // Pass the category to display

    @State private var showInterpolateSheet = false
    @State private var interpolateFromFrame = ""
    @State private var interpolateToFrame = ""
    @State private var showPasteRangeSheet = false
    @State private var pasteRangeFrom = ""
    @State private var pasteRangeTo = ""

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Color indicator
                Circle()
                    .fill(Color(red: object.color.red,
                              green: object.color.green,
                              blue: object.color.blue))
                    .frame(width: 12, height: 12)

                // Label and annotation count
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(object.label)
                            .font(.system(.body, weight: isSelected ? .semibold : .regular))

                        // Category badge
                        if let category = category {
                            Text(category.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: category.color.red,
                                                green: category.color.green,
                                                blue: category.color.blue).opacity(0.3))
                                .cornerRadius(4)
                        }
                    }

                    Text("\(object.annotations.count) frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Indicator if current frame has annotation
                if object.boundingBox(at: currentFrame) != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                // Visibility toggle
                if let onToggleVisibility = onToggleVisibility {
                    Button(action: onToggleVisibility) {
                        Image(systemName: object.isVisible ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(object.isVisible ? .blue : .gray)
                    }
                    .buttonStyle(.plain)
                    .help(object.isVisible ? "Hide object" : "Show object")
                }

                // Solo button
                if let onSolo = onSolo, object.isVisible {
                    Button(action: onSolo) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Solo this object (hide all others)")
                }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete object")
            }

            // Tracking buttons (only show if annotation exists at current frame)
            if object.boundingBox(at: currentFrame) != nil {
                HStack(spacing: 4) {
                    if let onTrackBackward = onTrackBackward {
                        Button(action: onTrackBackward) {
                            HStack(spacing: 2) {
                                Image(systemName: "backward.fill")
                                Text("Track Back")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Track backward from this frame")
                    }

                    if let onTrackForward = onTrackForward {
                        Button(action: onTrackForward) {
                            HStack(spacing: 2) {
                                Image(systemName: "forward.fill")
                                Text("Track Forward")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Track forward from this frame")
                    }
                }

                // Delete current frame button
                if let onDeleteFrame = onDeleteFrame {
                    Button(action: onDeleteFrame) {
                        HStack(spacing: 2) {
                            Image(systemName: "minus.circle")
                            Text("Delete Frame")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
                    .help("Delete annotation for this frame only")
                }

                // Trimming controls
                HStack(spacing: 4) {
                    if let onTrimBefore = onTrimBefore {
                        Button(action: onTrimBefore) {
                            HStack(spacing: 2) {
                                Image(systemName: "scissors")
                                Text("Trim Before")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Remove annotations before current frame")
                    }
                    if let onTrimAfter = onTrimAfter {
                        Button(action: onTrimAfter) {
                            HStack(spacing: 2) {
                                Image(systemName: "scissors")
                                Text("Trim After")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Remove annotations after current frame")
                    }
                }

                // Interpolation button
                if let onInterpolate = onInterpolate {
                    Button(action: {
                        interpolateFromFrame = "\(currentFrame)"
                        interpolateToFrame = ""
                        showInterpolateSheet = true
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "waveform.path")
                            Text("Interpolate")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Interpolate between keyframes")
                }

                // Copy/Paste buttons
                HStack(spacing: 4) {
                    // Copy button (only show if annotation exists)
                    if let onCopy = onCopy {
                        Button(action: onCopy) {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Copy annotation (Cmd+C)")
                    }
                }
            }

            // Paste buttons (show even if no annotation at current frame)
            if hasClipboard {
                HStack(spacing: 4) {
                    if let onPaste = onPaste {
                        Button(action: onPaste) {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.clipboard")
                                Text("Paste")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Paste annotation to current frame (Cmd+V)")
                    }

                    if let onPasteToRange = onPasteToRange {
                        Button(action: {
                            pasteRangeFrom = "\(currentFrame)"
                            pasteRangeTo = ""
                            showPasteRangeSheet = true
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.clipboard.fill")
                                Text("Paste to Range")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Paste annotation to frame range")
                    }
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
        .sheet(isPresented: $showInterpolateSheet) {
            InterpolateSheet(
                fromFrame: $interpolateFromFrame,
                toFrame: $interpolateToFrame,
                onInterpolate: {
                    if let from = Int(interpolateFromFrame),
                       let to = Int(interpolateToFrame),
                       to > from {
                        onInterpolate?(from, to)
                        showInterpolateSheet = false
                    }
                },
                onCancel: {
                    showInterpolateSheet = false
                }
            )
        }
        .sheet(isPresented: $showPasteRangeSheet) {
            PasteRangeSheet(
                fromFrame: $pasteRangeFrom,
                toFrame: $pasteRangeTo,
                onPaste: {
                    if let from = Int(pasteRangeFrom),
                       let to = Int(pasteRangeTo),
                       to >= from {
                        onPasteToRange?(from, to)
                        showPasteRangeSheet = false
                    }
                },
                onCancel: {
                    showPasteRangeSheet = false
                }
            )
        }
    }
}

struct InterpolateSheet: View {
    @Binding var fromFrame: String
    @Binding var toFrame: String
    let onInterpolate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Interpolate Between Keyframes")
                .font(.headline)

            Text("Create smooth motion between two annotated frames")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("From Frame (keyframe):")
                TextField("Start frame", text: $fromFrame)
                    .textFieldStyle(.roundedBorder)

                Text("To Frame (keyframe):")
                TextField("End frame", text: $toFrame)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Interpolate") {
                    onInterpolate()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 250)
    }
}

struct PasteRangeSheet: View {
    @Binding var fromFrame: String
    @Binding var toFrame: String
    let onPaste: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Paste Annotation to Frame Range")
                .font(.headline)

            Text("Paste the copied annotation to all frames in the specified range")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("From Frame:")
                TextField("Start frame", text: $fromFrame)
                    .textFieldStyle(.roundedBorder)

                Text("To Frame:")
                TextField("End frame", text: $toFrame)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Paste") {
                    onPaste()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 250)
    }
}
