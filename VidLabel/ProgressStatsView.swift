//
//  ProgressStatsView.swift
//  VidLabel
//
//  Progress tracking and statistics visualization
//

import SwiftUI

struct ProgressStatsView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    let totalFrames: Int

    var body: some View {
        let stats = annotationVM.getProgressStats(totalFrames: totalFrames)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress")
                    .font(.headline)

                Spacer()

                // Overall coverage percentage
                Text("\(Int(stats.coverage * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(coverageColor(stats.coverage))
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 20)
                        .cornerRadius(10)

                    // Progress
                    Rectangle()
                        .fill(coverageColor(stats.coverage))
                        .frame(width: geometry.size.width * CGFloat(stats.coverage), height: 20)
                        .cornerRadius(10)

                    // Text overlay
                    HStack {
                        Spacer()
                        Text("\(stats.annotatedFrames) / \(stats.totalFrames) frames")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        Spacer()
                    }
                }
            }
            .frame(height: 20)

            Divider()

            // Per-object statistics
            if !annotationVM.trackedObjects.isEmpty {
                Text("Objects")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(annotationVM.trackedObjects) { object in
                    if let objectStats = stats.objectStats[object.id] {
                        ObjectProgressRow(
                            stats: objectStats,
                            color: object.color
                        )
                    }
                }
            }

            Divider()

            // Quick stats
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Total Objects:")
                    Spacer()
                    Text("\(stats.objectCount)")
                        .fontWeight(.semibold)
                }
                .font(.caption)

                HStack {
                    Text("Annotated Frames:")
                    Spacer()
                    Text("\(stats.annotatedFrames)")
                        .fontWeight(.semibold)
                }
                .font(.caption)

                HStack {
                    Text("Remaining:")
                    Spacer()
                    Text("\(stats.totalFrames - stats.annotatedFrames)")
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .font(.caption)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            Spacer()
        }
        .padding()
        .frame(width: 280)
    }

    private func coverageColor(_ coverage: Double) -> Color {
        if coverage >= 0.8 {
            return .green
        } else if coverage >= 0.5 {
            return .blue
        } else if coverage >= 0.25 {
            return .orange
        } else {
            return .red
        }
    }
}

struct ObjectProgressRow: View {
    let stats: ObjectStats
    let color: CodableColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 8, height: 8)

                Text(stats.label)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text("\(stats.frameCount) frames")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(Color(red: color.red, green: color.green, blue: color.blue))
                        .frame(width: geometry.size.width * CGFloat(stats.coverage), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}
