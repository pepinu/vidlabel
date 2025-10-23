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
                    Text(object.label)
                        .font(.system(.body, weight: isSelected ? .semibold : .regular))

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
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
    }
}
