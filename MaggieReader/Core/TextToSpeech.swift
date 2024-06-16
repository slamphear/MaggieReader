//
//  TextToSpeech.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import Foundation
import AVFoundation
import Combine
import OpenAI

func convertTextToSpeech(text: String, voice: AudioSpeechQuery.AudioSpeechVoice, completion: @escaping (URL?) -> Void) {
    print("Starting convertTextToSpeech")
    let chunks = chunkText(text, chunkSize: 4096)
    print("Text split into \(chunks.count) chunks")

    let chunkProcessingPublishers = chunks.enumerated().map { index, chunk -> AnyPublisher<(Int, URL?), Never> in
        return processChunk(chunk: chunk, voice: voice)
            .map { (index, $0) }
            .eraseToAnyPublisher()
    }

    Publishers.MergeMany(chunkProcessingPublishers)
        .collect()
        .flatMap { indexedURLs -> AnyPublisher<URL?, Never> in
            let sortedURLs = indexedURLs.sorted(by: { $0.0 < $1.0 }).compactMap { $0.1 }
            return joinAudioFiles(urls: sortedURLs)
                .eraseToAnyPublisher()
        }
        .sink { finalURL in
            print("Completed with final URL: \(String(describing: finalURL))")
            completion(finalURL)
        }
        .store(in: &cancellables)
}

var cancellables = Set<AnyCancellable>()

func processChunk(chunk: String, voice: AudioSpeechQuery.AudioSpeechVoice) -> AnyPublisher<URL?, Never> {
    return Future<URL?, Never> { promise in
        print("Processing chunk: \(chunk.prefix(50))...")
        textToSpeechAPI(text: chunk, voice: voice) { url in
            print("Chunk processed with URL: \(String(describing: url))")
            promise(.success(url))
        }
    }.eraseToAnyPublisher()
}

func textToSpeechAPI(text: String, voice: AudioSpeechQuery.AudioSpeechVoice, completion: @escaping (URL?) -> Void) {
    print("Calling textToSpeechAPI")
    guard let openAI = getOpenAIClient() else {
        print("Failed to get OpenAI client")
        completion(nil)
        return
    }

    let query = AudioSpeechQuery(model: .tts_1_hd, input: text, voice: voice, responseFormat: .aac, speed: 1.0)

    openAI.audioCreateSpeech(query: query) { result in
        switch result {
        case .success(let audio):
            let tempAACURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("aac")
            do {
                print("Audio data size: \(audio.audio.count) bytes")
                try audio.audio.write(to: tempAACURL)
                print("Audio written to \(tempAACURL)")

                // Verify if the file can be opened as an AVAsset
                let asset = AVURLAsset(url: tempAACURL)
                asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
                    var error: NSError?
                    let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)
                    let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
                    if tracksStatus == .loaded && durationStatus == .loaded {
                        print("Successfully verified audio file at \(tempAACURL)")
                        completion(tempAACURL)
                    } else {
                        print("Failed to verify audio file at \(tempAACURL): \(String(describing: error))")
                        completion(nil)
                    }
                }
            } catch {
                print("Error writing audio: \(error)")
                completion(nil)
            }
        case .failure(let error):
            print("API call failed with error: \(error)")
            completion(nil)
        }
    }
}

func joinAudioFiles(urls: [URL]) -> AnyPublisher<URL?, Never> {
    return Future<URL?, Never> { promise in
        print("Joining audio files")
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outputURL = documentDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")

        let composition = AVMutableComposition()
        let loadAssetPublisher = urls.publisher.flatMap { url -> AnyPublisher<(AVAsset, [AVAssetTrack], CMTime), Error> in
            let asset = AVURLAsset(url: url)
            let tracksPublisher = asset.loadTracksPublisher(withMediaType: .audio)
            let durationPublisher = asset.loadDurationPublisher()

            return Publishers.Zip3(Just(asset).setFailureType(to: Error.self), tracksPublisher, durationPublisher)
                .eraseToAnyPublisher()
        }

        loadAssetPublisher
            .collect()
            .sink(receiveCompletion: { completion in
                print("Finished loading assets with completion: \(completion)")
                if case let .failure(error) = completion {
                    print("Failed with error: \(error)")
                    promise(.success(nil))
                }
            }, receiveValue: { assetTracksAndDurations in
                print("Received asset tracks and durations")
                for (asset, tracks, duration) in assetTracksAndDurations {
                    if let assetTrack = tracks.first {
                        let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                        try? compositionTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: duration), of: assetTrack, at: composition.duration)
                    }
                }

                let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)!
                exporter.outputFileType = .m4a
                exporter.outputURL = outputURL

                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        print("Export completed: \(outputURL)")
                        promise(.success(outputURL))
                    default:
                        print("Export failed with status: \(exporter.status)")
                        promise(.success(nil))
                    }
                }
            })
            .store(in: &cancellables)
    }.eraseToAnyPublisher()
}

extension AVAsset {
    func loadTracksPublisher(withMediaType mediaType: AVMediaType) -> AnyPublisher<[AVAssetTrack], Error> {
        return Future<[AVAssetTrack], Error> { promise in
            print("Loading tracks for media type: \(mediaType)")
            self.loadTracks(withMediaType: mediaType) { tracks, error in
                if let tracks = tracks {
                    print("Loaded tracks: \(tracks.count)")
                    promise(.success(tracks))
                } else if let error = error {
                    print("Error loading tracks: \(error)")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }

    func loadDurationPublisher() -> AnyPublisher<CMTime, Error> {
        return Future<CMTime, Error> { promise in
            print("Loading duration")
            Task {
                do {
                    let duration: CMTime = try await self.load(.duration)
                    print("Loaded duration: \(duration)")
                    promise(.success(duration))
                } catch {
                    print("Error loading duration: \(error)")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
}

// Debugging function to inspect file headers
func printFileHeader(at url: URL) {
    do {
        let data = try Data(contentsOf: url)
        let header = data.prefix(32) // Read the first 32 bytes
        print("File header: \(header.map { String(format: "%02x", $0) }.joined(separator: " "))")
    } catch {
        print("Failed to read file header: \(error)")
    }
}

func chunkText(_ text: String, chunkSize: Int) -> [String] {
    var chunks: [String] = []
    var startIndex = text.startIndex

    while startIndex < text.endIndex {
        var endIndex = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex

        // Ensure we don't split sentences
        if endIndex < text.endIndex {
            if let periodIndex = text[..<endIndex].lastIndex(of: ".") {
                endIndex = text.index(after: periodIndex)
            } else if let spaceIndex = text[..<endIndex].lastIndex(of: " ") {
                endIndex = spaceIndex
            }
        }

        let chunk = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        chunks.append(chunk)
        print("\nCreated chunk (\(chunk.count) characters): \(chunk)")

        // Check if we've reached the end of the text
        if endIndex == text.endIndex {
            break
        }

        // Move startIndex to the character after the last character used to avoid overlapping
        startIndex = endIndex
    }

    return chunks
}
