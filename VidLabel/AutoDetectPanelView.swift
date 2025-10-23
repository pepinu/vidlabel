//
//  AutoDetectPanelView.swift
//  VidLabel
//
//  UI for auto-detection controls and proposal management
//

import SwiftUI
import AVFoundation

struct AutoDetectPanelView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    @ObservedObject var playerVM: VideoPlayerViewModel

    @State private var startFrame: String = "0"
    @State private var endFrame: String = ""
    @State private var showDeleteRangeSheet: Bool = false
    @State private var selectedProposalForTrim: UUID?
    @State private var deleteRangeStart: String = ""
    @State private var deleteRangeEnd: String = ""

    // ROI state
    @State private var detectionROI: BoundingBox?
    @State private var isDrawingROI: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto-Detection")
                .font(.headline)

            Divider()

            // Detection controls
            if !annotationVM.isAutoDetecting {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode: Motion Consistency")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("From Frame:")
                        TextField("0", text: $startFrame)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("To Frame:")
                        TextField("\(playerVM.totalFrames - 1)", text: $endFrame)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }

                    Divider()

                    // ROI controls
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Region of Interest (ROI)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let roi = detectionROI {
                            HStack {
                                Text("ROI set")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Spacer()
                                Button("Clear ROI") {
                                    detectionROI = nil
                                    annotationVM.setDetectionROI(nil)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        } else {
                            Button("Draw ROI") {
                                isDrawingROI = true
                                annotationVM.startDrawingDetectionROI()
                            }
                            .buttonStyle(.bordered)
                            .help("Draw a region to limit detection")
                        }
                    }

                    Divider()

                    // Dead Zone controls
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dead Zones (Exclusion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !annotationVM.detectionDeadZones.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(Array(annotationVM.detectionDeadZones.enumerated()), id: \.offset) { index, _ in
                                    HStack {
                                        Text("Zone \(index + 1)")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                        Spacer()
                                        Button("Remove") {
                                            annotationVM.removeDeadZone(at: index)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }

                                Button("Clear All") {
                                    annotationVM.clearAllDeadZones()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }

                        Button("Draw Dead Zone") {
                            annotationVM.startDrawingDeadZone()
                        }
                        .buttonStyle(.bordered)
                        .help("Draw zones where detection should be blocked")
                    }

                    Divider()

                    Button("Start Detection") {
                        startDetection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(annotationVM.isAutoDetecting || !playerVM.isVideoLoaded)
                }
            } else {
                // Progress indicator
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.linear)

                    Text(annotationVM.detectionProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Cancel") {
                        annotationVM.cancelAutoDetection()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            // Proposals list
            if !annotationVM.detectionProposals.isEmpty {
                Text("Detected Objects (\(annotationVM.detectionProposals.count))")
                    .font(.headline)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(annotationVM.detectionProposals) { proposal in
                            ProposalRowView(
                                proposal: proposal,
                                currentFrame: playerVM.currentFrameNumber,
                                onAccept: {
                                    annotationVM.acceptProposal(proposalId: proposal.id)
                                },
                                onReject: {
                                    annotationVM.rejectProposal(proposalId: proposal.id)
                                },
                                onDeleteRange: {
                                    selectedProposalForTrim = proposal.id
                                    showDeleteRangeSheet = true
                                }
                            )
                        }
                    }
                }

                Divider()

                HStack {
                    Button("Accept All") {
                        annotationVM.acceptAllProposals()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reject All") {
                        annotationVM.rejectAllProposals()
                    }
                    .buttonStyle(.bordered)
                }
            } else if !annotationVM.detectionProgress.isEmpty {
                Text(annotationVM.detectionProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(width: 280)
        .sheet(isPresented: $showDeleteRangeSheet) {
            DeleteRangeSheet(
                startFrame: $deleteRangeStart,
                endFrame: $deleteRangeEnd,
                onDelete: {
                    deleteFrameRange()
                },
                onCancel: {
                    showDeleteRangeSheet = false
                }
            )
        }
    }

    private func startDetection() {
        guard let asset = playerVM.currentAsset else { return }

        let start = Int(startFrame) ?? 0
        let end = Int(endFrame) ?? playerVM.totalFrames - 1

        let validStart = max(0, min(start, playerVM.totalFrames - 1))
        let validEnd = max(validStart, min(end, playerVM.totalFrames - 1))

        // Sync local ROI state
        detectionROI = annotationVM.detectionROI

        annotationVM.startAutoDetection(
            asset: asset,
            frameRange: validStart...validEnd,
            frameRate: playerVM.getFrameRate(),
            videoSize: playerVM.videoSize,
            roi: annotationVM.detectionROI,
            deadZones: annotationVM.detectionDeadZones
        )
    }

    private func deleteFrameRange() {
        guard let proposalId = selectedProposalForTrim else { return }

        let start = Int(deleteRangeStart) ?? 0
        let end = Int(deleteRangeEnd) ?? 0

        if start <= end {
            annotationVM.deleteProposalFrames(proposalId: proposalId, range: start...end)
        }

        showDeleteRangeSheet = false
        deleteRangeStart = ""
        deleteRangeEnd = ""
        selectedProposalForTrim = nil
    }
}

struct ProposalRowView: View {
    let proposal: DetectionProposal
    let currentFrame: Int
    let onAccept: () -> Void
    let onReject: () -> Void
    let onDeleteRange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Color indicator
                Circle()
                    .fill(Color(
                        red: proposal.color.red,
                        green: proposal.color.green,
                        blue: proposal.color.blue
                    ))
                    .frame(width: 12, height: 12)

                Text("Proposal")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // Frame count
                Text("\(proposal.annotations.count) frames")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Detection state indicator
            if let state = proposal.state(at: currentFrame) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state == .detected ? Color.green : Color.blue)
                        .frame(width: 6, height: 6)

                    Text(state == .detected ? "Detected" : "Predicted")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 6) {
                Button("Accept") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Reject") {
                    onReject()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete Range...") {
                    onDeleteRange()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}

struct DeleteRangeSheet: View {
    @Binding var startFrame: String
    @Binding var endFrame: String
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Delete Frame Range")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start Frame:")
                    TextField("0", text: $startFrame)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                HStack {
                    Text("End Frame:")
                    TextField("100", text: $endFrame)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
