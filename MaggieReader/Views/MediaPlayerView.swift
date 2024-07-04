//
//  MediaPlayerView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import SwiftUI
import AVFoundation
import MediaPlayer

struct MediaPlayerView: View {
    let inputText: String
    let audioURLs: [URL]

    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var isPlaying: Bool = false
    @State private var currentItemIndex: Int = 0
    @State private var totalDuration: CMTime = .zero
    @State private var chunkDurations: [CMTime] = []
    @State private var timer: Timer?
    @State private var progress: Double = 0.0
    @State private var playbackRate: Float = 1.0

    var body: some View {
        VStack {
            ScrollView {
                Text(inputText)
                    .padding()
            }

            HStack {
                Spacer()

                Button(action: skipBackward) {
                    Image(systemName: "gobackward.30")
                        .scaleEffect(1.5)
                }
                .padding()

                Spacer()

                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .scaleEffect(1.5)
                }
                .padding()

                Spacer()

                Button(action: skipForward) {
                    Image(systemName: "goforward.30")
                        .scaleEffect(1.5)
                }
                .padding()

                Spacer()
            }

            HStack {
                Text(formatTime(currentPlayerTime()))
                ProgressView(value: progress)
                    .padding()
                Text("-\(formatTime(CMTimeSubtract(totalDuration, currentPlayerTime())))")
            }
            .padding()

            DisclosureGroup(
                content: {
                    VStack(spacing: 4) {
                        Slider(
                            value: self.$playbackRate,
                            in: 0.5...3.5,
                            step: 0.05,
                            label: { Text("Playback Speed") },
                            minimumValueLabel: {
                                Button(action: {
                                    self.playbackRate -= 0.05
                                    updatePlaybackRate()
                                }, label: {
                                    Image(systemName: "minus")
                                })
                            },
                            maximumValueLabel: {
                                Button(action: {
                                    self.playbackRate += 0.05
                                    updatePlaybackRate()
                                }, label: {
                                    Image(systemName: "plus")
                                })
                            }
                        ) { _ in
                            updatePlaybackRate()
                        }

                        Picker("Playback Rate", selection: $playbackRate) {
                            Text("0.7").tag(Float(0.7))
                            Text("1.0").tag(Float(1.0))
                            Text("1.2").tag(Float(1.2))
                            Text("1.5").tag(Float(1.5))
                            Text("1.7").tag(Float(1.7))
                            Text("2.0").tag(Float(2.0))
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: playbackRate) {
                            updatePlaybackRate()
                        }
                    }
                },
                label: {
                    HStack {
                        Text("Playback speed")
                        Spacer()
                        Text("\(String(format: "%.2f", self.playbackRate))x")
                    }
                }
            )
            .padding()
        }
        .onAppear {
            setupPlayer()
            setupRemoteTransportControls()
            setupNowPlaying()
            startTimer()
        }
        .onDisappear {
            player.pause()
            updateNowPlaying(isPlaying: false)
            stopTimer()
        }
    }

    private var progressValue: Double {
        let currentTimeSeconds = CMTimeGetSeconds(currentPlayerTime())
        let totalDurationSeconds = CMTimeGetSeconds(totalDuration)
        return totalDurationSeconds > 0 ? currentTimeSeconds / totalDurationSeconds : 0
    }

    private func updatePlaybackRate() {
        player.rate = self.playbackRate
        if isPlaying {
            player.playImmediately(atRate: self.playbackRate)
        }
    }

    @MainActor
    func setupPlayer() {
        player.removeAllItems()
        chunkDurations = []

        let group = DispatchGroup()

        for url in audioURLs {
            group.enter()
            let item = AVPlayerItem(url: url)
            player.insert(item, after: nil)

            Task {
                let duration = try await item.asset.load(.duration)
                DispatchQueue.main.async {
                    self.chunkDurations.append(duration)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.totalDuration = self.chunkDurations.reduce(.zero, +)
            self.player.actionAtItemEnd = .advance
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { _ in
                print("AVPlayerItemDidPlayToEndTime triggered at duration \(self.currentPlayerTime().seconds) seconds out of a total \(self.totalDuration.seconds) seconds")
                if self.currentItemIndex < self.audioURLs.count - 1 {
                    self.currentItemIndex += 1
                } else {
                    self.isPlaying = false
                    self.updateNowPlaying(isPlaying: false)
                    self.stopTimer()
                }
            }
            self.player.playImmediately(atRate: self.playbackRate)
            self.isPlaying = true
            self.updateNowPlaying(isPlaying: true)
        }
    }

    func togglePlayPause() {
        print("togglePlayPause called")
        if isPlaying {
            player.pause()
        } else {
            player.playImmediately(atRate: playbackRate)
        }
        isPlaying.toggle()
        updateNowPlaying(isPlaying: isPlaying)
    }

    func skipForward() {
        let currentTime = currentPlayerTime()
        print("skipForward called, currentTime: \(currentTime.seconds)")
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(30, preferredTimescale: 1))
        seek(to: newTime)
    }

    func skipBackward() {
        let currentTime = currentPlayerTime()
        print("skipBackward called, currentTime: \(currentTime.seconds)")
        let newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(30, preferredTimescale: 1))
        seek(to: newTime)
    }

    func seek(to time: CMTime) {
        print("seek called, time: \(time.seconds)")
        var accumulatedTime: CMTime = .zero

        for (index, chunkDuration) in chunkDurations.enumerated() {
            let nextAccumulatedTime = CMTimeAdd(accumulatedTime, chunkDuration)
            if time < nextAccumulatedTime {
                let seekTimeInChunk = CMTimeSubtract(time, accumulatedTime)
                print("Seeking to chunk \(index), seekTimeInChunk: \(seekTimeInChunk.seconds)")

                // Move to the correct chunk
                if index != currentItemIndex {
                    // Ensure the current item is correct and update the queue accordingly
                    player.removeAllItems()
                    for i in index..<audioURLs.count {
                        let item = AVPlayerItem(url: audioURLs[i])
                        player.insert(item, after: nil)
                    }
                    currentItemIndex = index
                }

                player.seek(to: seekTimeInChunk) { _ in
                    self.updateNowPlaying(isPlaying: self.isPlaying)
                    if self.isPlaying {
                        self.player.playImmediately(atRate: self.playbackRate)
                    }
                }
                return
            }
            accumulatedTime = nextAccumulatedTime
        }
    }

    func currentPlayerTime() -> CMTime {
        let currentTime = player.currentTime()
        let elapsedTime = chunkDurations.prefix(currentItemIndex).reduce(0.0) { $0 + CMTimeGetSeconds($1) }
        print("currentPlayerTime called, elapsedTime: \(elapsedTime), currentTime: \(currentTime.seconds)")
        return CMTimeMakeWithSeconds(elapsedTime + CMTimeGetSeconds(currentTime), preferredTimescale: currentTime.timescale)
    }

    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { event in
            if !self.isPlaying {
                self.player.playImmediately(atRate: self.playbackRate)
                self.isPlaying = true
                self.updateNowPlaying(isPlaying: true)
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { event in
            if self.isPlaying {
                self.player.pause()
                self.isPlaying = false
                self.updateNowPlaying(isPlaying: false)
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { event in
            self.skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [30]
        commandCenter.skipBackwardCommand.addTarget { event in
            self.skipBackward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let seekTime = CMTimeMakeWithSeconds(event.positionTime, preferredTimescale: 1)
            self.seek(to: seekTime)
            return .success
        }
    }

    func setupNowPlaying() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Maggie Reader"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = CMTimeGetSeconds(self.totalDuration)

        // Add App Icon as artwork
        #if canImport(UIKit)
        if let appIcon = UIImage(named: "AppIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: appIcon.size) { size in
                return appIcon
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func updateNowPlaying(isPlaying: Bool) {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        let currentPlayerSeconds = CMTimeGetSeconds(currentPlayerTime())
        let totalDurationSeconds = CMTimeGetSeconds(self.totalDuration)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentPlayerSeconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = totalDurationSeconds

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        progress = progressValue
    }

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.updateNowPlaying(isPlaying: self.isPlaying)
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ time: CMTime) -> String {
        print("Calling formatTime with time \(time.seconds) seconds")
        let totalSeconds: Float64
        if !time.isValid {
            totalSeconds = 0.0
        } else {
            totalSeconds = CMTimeGetSeconds(time)
        }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
