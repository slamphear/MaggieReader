//
//  MediaPlayerView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import SwiftUI
import AVKit
import MediaPlayer
import OpenAI

struct MediaPlayerView: View {
    @Binding var audioURLs: [URL]
    @Binding var inputText: String
    @Binding var selectedVoice: AudioSpeechQuery.AudioSpeechVoice
    @State private var player: AVQueuePlayer?
    @State private var isLoading: Bool = false
    @State private var timeObserverToken: Any?
    @State private var timeControlStatusObserver: NSKeyValueObservation?
    @State private var isPlaying: Bool = false

    var body: some View {
        ZStack {
            VStack {
                if let player = player {
                    VStack {
                        Text("Now Playing")
                            .font(.title)
                            .padding()

                        HStack {
                            Button(action: {
                                player.seek(to: .zero)
                                updateNowPlayingInfo()
                            }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.title)
                            }
                            .padding(.trailing, 20)

                            Button(action: {
                                player.seek(to: CMTime(seconds: max(player.currentTime().seconds - 10, 0), preferredTimescale: 1))
                                updateNowPlayingInfo()
                            }) {
                                Image(systemName: "gobackward.10")
                                    .font(.title)
                            }
                            .padding(.trailing, 20)

                            Button(action: {
                                if player.timeControlStatus == .playing {
                                    player.pause()
                                } else {
                                    player.play()
                                }
                                updateNowPlayingInfo()
                            }) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                            }
                            .padding(.trailing, 20)

                            Button(action: {
                                player.seek(to: CMTime(seconds: player.currentTime().seconds + 10, preferredTimescale: 1))
                                updateNowPlayingInfo()
                            }) {
                                Image(systemName: "goforward.10")
                                    .font(.title)
                            }
                        }
                        .padding()

                        Picker("Voice", selection: $selectedVoice) {
                            ForEach(AudioSpeechQuery.AudioSpeechVoice.allCases, id: \.self) { voice in
                                Text(voice.rawValue.capitalized).tag(voice)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding()
                        .onChange(of: selectedVoice) { oldVoice, newVoice in
                            switchVoice(to: newVoice)
                        }
                    }
                } else {
                    Text("Loading...")
                        .onAppear {
                            setupPlayer()
                        }
                }
            }

            if isLoading {
                ZStack {
                    Color(.systemBackground).opacity(0.8).edgesIgnoringSafeArea(.all)
                    ProgressView("Loading...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        }
        .onDisappear {
            if let timeObserverToken = timeObserverToken {
                player?.removeTimeObserver(timeObserverToken)
                self.timeObserverToken = nil
            }
            timeControlStatusObserver?.invalidate()
        }
    }

    func setupPlayer() {
        if !audioURLs.isEmpty {
            let firstItem = AVPlayerItem(url: audioURLs.removeFirst())
            player = AVQueuePlayer(playerItem: firstItem)
            player?.play()
            setupNowPlaying()
            addPeriodicTimeObserver()
            observePlayerStatus()

            // Add remaining items to the player
            for url in audioURLs {
                let item = AVPlayerItem(url: url)
                player?.insert(item, after: nil)
            }
        }
    }

    func switchVoice(to newVoice: AudioSpeechQuery.AudioSpeechVoice) {
        isLoading = true
        // Stop and dispose of the previous player
        player?.pause()
        player?.removeAllItems()

        convertLargeTextToSpeech(text: inputText, voice: newVoice) { urls in
            DispatchQueue.main.async {
                self.audioURLs = urls
                setupPlayer()
                self.isLoading = false
            }
        }
    }

    func setupNowPlaying() {
        guard let player = player else { return }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Maggie Reader"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.currentItem?.asset.duration.seconds ?? 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate

        if let appIcon = UIImage(named: "AppIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: appIcon.size) { size in
                return appIcon
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { event in
            if player.timeControlStatus != .playing {
                player.play()
                updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { event in
            if player.timeControlStatus == .playing {
                player.pause()
                updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipForwardCommand.addTarget { event in
            let currentTime = player.currentTime().seconds
            let newTime = currentTime + 10
            player.seek(to: CMTime(seconds: newTime, preferredTimescale: 1))
            updateNowPlayingInfo()
            return .success
        }

        commandCenter.skipBackwardCommand.addTarget { event in
            let currentTime = player.currentTime().seconds
            let newTime = currentTime - 10
            player.seek(to: CMTime(seconds: newTime, preferredTimescale: 1))
            updateNowPlayingInfo()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                player.seek(to: CMTime(seconds: positionEvent.positionTime, preferredTimescale: 1))
                updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }
    }

    func updateNowPlayingInfo() {
        guard let player = player else { return }

        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.currentItem?.asset.duration.seconds ?? 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func addPeriodicTimeObserver() {
        guard let player = player else { return }

        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 1.0, preferredTimescale: timeScale)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) { _ in
            self.updateNowPlayingInfo()
        }
    }

    func observePlayerStatus() {
        timeControlStatusObserver = player?.observe(\.timeControlStatus, options: [.new, .initial]) { player, _ in
            DispatchQueue.main.async {
                self.isPlaying = player.timeControlStatus == .playing
            }
        }
    }
}