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

    var body: some View {
        VStack {
            Text("Now Playing")
                .font(.headline)
                .padding()

            ScrollView {
                Text(inputText)
                    .padding()
            }
            .frame(height: 200)

            HStack {
                Button(action: skipBackward) {
                    Image(systemName: "backward.fill")
                }
                .padding()

                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .padding()

                Button(action: skipForward) {
                    Image(systemName: "forward.fill")
                }
                .padding()
            }

            ProgressView(value: progressValue)
                .padding()
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
    }

    private var progressValue: Double {
        let currentTimeSeconds = CMTimeGetSeconds(currentPlayerTime())
        let totalDurationSeconds = CMTimeGetSeconds(totalDuration)
        return totalDurationSeconds > 0 ? currentTimeSeconds / totalDurationSeconds : 0
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

            item.asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                var error: NSError?
                let status = item.asset.statusOfValue(forKey: "duration", error: &error)
                if status == .loaded {
                    let duration = item.asset.duration
                    DispatchQueue.main.async {
                        self.chunkDurations.append(duration)
                        group.leave()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.chunkDurations.append(.zero)
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            self.totalDuration = self.chunkDurations.reduce(.zero, +)
            self.player.actionAtItemEnd = .advance
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { _ in
                if self.currentItemIndex < self.audioURLs.count - 1 {
                    self.currentItemIndex += 1
                } else {
                    self.isPlaying = false
                    self.updateNowPlaying(isPlaying: false)
                    self.stopTimer()
                }
            }
            self.player.play()
            self.isPlaying = true
            self.updateNowPlaying(isPlaying: true)
        }
    }

    func togglePlayPause() {
        print("togglePlayPause called")
        if isPlaying {
            player.pause()
        } else {
            player.play()
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
                        self.player.play()
                    }
                }
                return
            }
            accumulatedTime = nextAccumulatedTime
        }
    }

    func currentPlayerTime() -> CMTime {
        guard let currentItem = player.currentItem else { return .zero }
        let currentTime = player.currentTime()
        let elapsedTime = chunkDurations.prefix(currentItemIndex).reduce(0.0) { $0 + CMTimeGetSeconds($1) }
        print("currentPlayerTime called, elapsedTime: \(elapsedTime), currentTime: \(currentTime.seconds)")
        return CMTimeMakeWithSeconds(elapsedTime + CMTimeGetSeconds(currentTime), preferredTimescale: currentTime.timescale)
    }

    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { event in
            if !self.isPlaying {
                self.player.play()
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
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
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
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = totalDurationSeconds

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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
}
