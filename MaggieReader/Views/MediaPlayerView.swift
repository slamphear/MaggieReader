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
    @State private var duration: CMTime = .zero

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
        }
        .onAppear {
            setupPlayer()
            setupRemoteTransportControls()
            setupNowPlaying()
        }
        .onDisappear {
            player.pause()
            updateNowPlaying(isPlaying: false)
        }
    }

    @MainActor
    func setupPlayer() {
        player.removeAllItems()
        for url in audioURLs {
            let item = AVPlayerItem(url: url)
            player.insert(item, after: nil)
        }
        player.actionAtItemEnd = .advance
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { _ in
            if self.currentItemIndex < self.audioURLs.count - 1 {
                self.currentItemIndex += 1
            } else {
                self.isPlaying = false
                updateNowPlaying(isPlaying: false)
            }
        }
        player.play()
        isPlaying = true
        if let currentItem = player.currentItem {
            Task {
                let duration = try await currentItem.asset.load(.duration)
                print("Duration of completed file: \(CMTimeGetSeconds(duration)) seconds")
                self.duration = duration
                updateNowPlaying(isPlaying: true)
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlaying(isPlaying: isPlaying)
    }

    func startOver() {
        player.seek(to: .zero) { _ in
            self.updateNowPlaying(isPlaying: self.isPlaying)
        }
        player.play()
        isPlaying = true
        updateNowPlaying(isPlaying: true)
    }

    func skipForward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(30, preferredTimescale: 1))
        player.seek(to: newTime) { _ in
            self.updateNowPlaying(isPlaying: self.isPlaying)
        }
    }

    func skipBackward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(30, preferredTimescale: 1))
        player.seek(to: newTime) { _ in
            self.updateNowPlaying(isPlaying: self.isPlaying)
        }
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
            self.player.seek(to: CMTimeMakeWithSeconds(event.positionTime, preferredTimescale: 1)) { _ in
                self.updateNowPlaying(isPlaying: self.isPlaying)
            }
            return .success
        }
    }

    func setupNowPlaying() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Maggie Reader"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = CMTimeGetSeconds(self.duration)

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
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = CMTimeGetSeconds(self.duration)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
