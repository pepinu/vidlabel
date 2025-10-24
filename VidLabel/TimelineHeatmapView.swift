//
//  TimelineHeatmapView.swift
//  VidLabel
//
//  Timeline visualization with annotation density heatmap and segment markers
//

import SwiftUI

struct TimelineHeatmapView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    let currentFrame: Int
    let totalFrames: Int
    let onSeek: (Int) -> Void

    private let height: CGFloat = 60
    private let segmentMarkerHeight: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            // Segment markers
            if !annotationVM.segments.isEmpty {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color.black.opacity(0.1))

                        // Segment bars
                        ForEach(annotationVM.segments) { segment in
                            let startX = CGFloat(segment.startFrame) / CGFloat(totalFrames) * geometry.size.width
                            let endX = CGFloat(segment.endFrame + 1) / CGFloat(totalFrames) * geometry.size.width
                            let width = endX - startX

                            Rectangle()
                                .fill(Color(red: segment.color.red,
                                          green: segment.color.green,
                                          blue: segment.color.blue,
                                          opacity: 0.6))
                                .frame(width: width, height: segmentMarkerHeight)
                                .offset(x: startX)
                                .overlay(
                                    Text(segment.name)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(width: width, height: segmentMarkerHeight)
                                        .offset(x: startX)
                                    , alignment: .leading
                                )
                                .onTapGesture {
                                    onSeek(segment.startFrame)
                                }
                        }
                    }
                }
                .frame(height: segmentMarkerHeight)
            }

            // Heatmap and playhead
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.black.opacity(0.3))

                    // Heatmap bars
                    let density = annotationVM.getAnnotationDensity(totalFrames: totalFrames, bucketSize: 100)
                    let maxDensity = density.max() ?? 1
                    let bucketWidth = geometry.size.width / CGFloat(density.count)

                    ForEach(0..<density.count, id: \.self) { index in
                        let count = density[index]
                        let intensity = CGFloat(count) / CGFloat(maxDensity)

                        Rectangle()
                            .fill(Color.blue.opacity(0.3 + intensity * 0.7))
                            .frame(width: bucketWidth, height: height)
                            .offset(x: CGFloat(index) * bucketWidth)
                    }

                    // Current frame playhead
                    let playheadX = CGFloat(currentFrame) / CGFloat(totalFrames) * geometry.size.width
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: height)
                        .offset(x: playheadX)

                    // Clickable overlay for seeking
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let fraction = value.location.x / geometry.size.width
                                    let targetFrame = Int(fraction * CGFloat(totalFrames))
                                    let clampedFrame = max(0, min(totalFrames - 1, targetFrame))
                                    onSeek(clampedFrame)
                                }
                        )
                }
            }
            .frame(height: height)
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(4)
    }
}
