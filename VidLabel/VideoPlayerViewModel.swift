//
//  VideoPlayerViewModel.swift
//  VidLabel
//
//  Video playback and control logic using AVFoundation
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

class VideoPlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentTime: CMTime = .zero
    @Published var duration: CMTime = .zero
    @Published var isPlaying: Bool = false
    @Published var currentFrameNumber: Int = 0
    @Published var totalFrames: Int = 0
    @Published var videoSize: CGSize = .zero
    @Published var isVideoLoaded: Bool = false

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var asset: AVAsset?
    private var videoURL: URL?

    // Frame rate for frame-by-frame navigation
    private var frameRate: Double = 30.0

    // MARK: - Helper Methods

    /// Safely converts Double to Int, returning 0 if the value is NaN or infinite
    private func safeIntConversion(_ value: Double) -> Int {
        guard !value.isNaN && !value.isInfinite else { return 0 }
        return Int(value)
    }

    // MARK: - Computed Properties
    var currentTimeString: String {
        let seconds = CMTimeGetSeconds(currentTime)
        let totalSecs = safeIntConversion(seconds)
        let minutes = totalSecs / 60
        let secs = totalSecs % 60
        let frames = safeIntConversion((seconds - Double(totalSecs)) * frameRate)
        return String(format: "%02d:%02d.%02d", minutes, secs, frames)
    }

    var durationString: String {
        let seconds = CMTimeGetSeconds(duration)
        let totalSecs = safeIntConversion(seconds)
        let minutes = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    var progress: Double {
        guard duration.seconds > 0, !duration.seconds.isNaN, !duration.seconds.isInfinite else { return 0 }
        let prog = currentTime.seconds / duration.seconds
        guard !prog.isNaN && !prog.isInfinite else { return 0 }
        return min(max(prog, 0), 1) // Clamp between 0 and 1
    }

    // MARK: - Public Methods

    func loadVideo(url: URL) {
        cleanup()

        self.videoURL = url
        let asset = AVURLAsset(url: url)
        self.asset = asset

        Task {
            do {
                // Load asset properties asynchronously
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else {
                    print("No video track found")
                    return
                }

                // Get video properties
                let size = try await videoTrack.load(.naturalSize)
                let frameRateValue = try await videoTrack.load(.nominalFrameRate)

                // Try to get duration from asset
                let assetDuration = try? await asset.load(.duration)

                await MainActor.run {
                    self.videoSize = size

                    // Validate frame rate - default to 60fps if invalid
                    if frameRateValue.isNaN || frameRateValue.isInfinite || frameRateValue <= 0 {
                        print("Warning: Invalid frame rate (\(frameRateValue)), defaulting to 60fps")
                        self.frameRate = 60.0
                    } else {
                        self.frameRate = Double(frameRateValue)
                    }

                    // Create player item and player
                    let item = AVPlayerItem(asset: asset)
                    self.playerItem = item
                    self.player = AVPlayer(playerItem: item)
                    self.player?.actionAtItemEnd = .none // Will loop

                    // Set duration if available
                    if let assetDuration = assetDuration {
                        self.duration = assetDuration
                        self.updateDurationDependentValues()
                    }

                    // Observe player item status for when it's ready to play
                    self.statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            if item.status == .readyToPlay {
                                self.duration = item.duration
                                self.updateDurationDependentValues()
                                print("Video ready to play. Duration: \(CMTimeGetSeconds(item.duration))s, FPS: \(self.frameRate)")
                            } else if item.status == .failed {
                                print("Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                            }
                        }
                    }

                    // Add time observer
                    self.addTimeObserver()

                    // Add observer for when video ends to loop
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { [weak self] _ in
                        guard let self = self else { return }
                        Task { @MainActor in
                            // Loop back to beginning
                            self.player?.seek(to: .zero)
                            if self.isPlaying {
                                self.player?.play()
                            }
                        }
                    }

                    self.isVideoLoaded = true
                }
            } catch {
                print("Error loading video: \(error)")
            }
        }
    }

    func togglePlayPause() {
        guard let player = player else {
            print("Warning: No player available")
            return
        }

        if isPlaying {
            print("Pausing playback")
            player.pause()
            isPlaying = false
        } else {
            print("Starting playback")
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        guard player != nil else { return }
        print("Pause called")
        player?.pause()
        isPlaying = false
    }

    func play() {
        guard player != nil else { return }
        print("Play called")
        player?.play()
        isPlaying = true
    }

    func seek(to time: CMTime) {
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stepForward() {
        guard player != nil else { return }
        pause()
        let frameTime = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let newTime = CMTimeAdd(currentTime, frameTime)
        if newTime < duration {
            seek(to: newTime)
        }
    }

    func stepBackward() {
        guard player != nil else { return }
        pause()
        let frameTime = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let newTime = CMTimeSubtract(currentTime, frameTime)
        if newTime >= .zero {
            seek(to: newTime)
        }
    }

    func seekToFrame(_ frameNumber: Int) {
        let time = CMTime(seconds: Double(frameNumber) / frameRate, preferredTimescale: 600)
        seek(to: time)
    }

    func seekToProgress(_ progress: Double) {
        let time = CMTime(seconds: duration.seconds * progress, preferredTimescale: 600)
        seek(to: time)
    }

    func getPlayer() -> AVPlayer? {
        return player
    }

    func getAsset() -> AVAsset? {
        return asset
    }

    func getFrameRate() -> Double {
        return frameRate
    }

    func getVideoURL() -> URL? {
        return videoURL
    }

    // MARK: - Private Methods

    private func updateDurationDependentValues() {
        // Calculate total frames with validation
        let durationSeconds = CMTimeGetSeconds(duration)
        if durationSeconds.isNaN || durationSeconds.isInfinite || durationSeconds <= 0 {
            print("Warning: Invalid duration (\(durationSeconds)), cannot calculate total frames")
            self.totalFrames = 0
        } else {
            let totalFramesDouble = durationSeconds * self.frameRate
            if totalFramesDouble.isNaN || totalFramesDouble.isInfinite {
                print("Warning: Invalid total frames calculation")
                self.totalFrames = 0
            } else {
                self.totalFrames = safeIntConversion(totalFramesDouble)
            }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentTime = time
                let timeSeconds = CMTimeGetSeconds(time)
                self.currentFrameNumber = self.safeIntConversion(timeSeconds * self.frameRate)
            }
        }
    }

    private func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player?.pause()
        player = nil
        playerItem = nil
        asset = nil

        currentTime = .zero
        duration = .zero
        isPlaying = false
        currentFrameNumber = 0
        totalFrames = 0
        isVideoLoaded = false
    }

    deinit {
        // Note: Cannot access MainActor-isolated properties here
        // AVPlayer and observers will be cleaned up automatically
    }
}
