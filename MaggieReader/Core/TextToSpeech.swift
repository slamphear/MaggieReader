//
//  TextToSpeech.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import AVFoundation
import SwiftKeychainWrapper
import OpenAI

func chunkText(_ text: String, chunkSize: Int) -> [String] {
    var chunks: [String] = []
    var startIndex = text.startIndex

    while startIndex < text.endIndex {
        var endIndex = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex

        // Ensure we don't split sentences
        if endIndex < text.endIndex {
            if let periodIndex = text[..<endIndex].lastIndex(of: ".") {
                endIndex = text.index(after: periodIndex)
            }
        }

        let chunk = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        chunks.append(chunk)

        // Check if we've reached the end of the text
        if endIndex == text.endIndex {
            break
        }

        startIndex = endIndex
    }

    return chunks
}

func convertTextToSpeech(text: String, voice: AudioSpeechQuery.AudioSpeechVoice, completion: @escaping (URL?) -> Void) {
    let chunkSize = 4000  // or any appropriate chunk size
    let textChunks = chunkText(text, chunkSize: chunkSize)
    let uniqueID = UUID().uuidString
    let tempDirectory = FileManager.default.temporaryDirectory
    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var audioURLs: [(Int, URL)] = []  // Tuple to store chunk index and URL
    let dispatchGroup = DispatchGroup()

    guard let openAI = getOpenAIClient() else {
        completion(nil)
        return
    }

    for (index, chunk) in textChunks.enumerated() {
        dispatchGroup.enter()
        let query = AudioSpeechQuery(model: .tts_1_hd, input: chunk, voice: voice, responseFormat: .aac, speed: 1.0)
        openAI.audioCreateSpeech(query: query) { result in
            switch result {
            case .success(let audio):
                let tempURL = tempDirectory.appendingPathComponent("\(uniqueID)_chunk_\(index).aac")
                do {
                    try audio.audio.write(to: tempURL)
                    audioURLs.append((index, tempURL))
                    print("Chunk \(index) length: \(audio.audio.count) bytes")
                } catch {
                    print("Error writing audio to file: \(error)")
                }
            case .failure(let error):
                print("Error creating speech: \(error)")
            }
            dispatchGroup.leave()
        }
    }

    dispatchGroup.notify(queue: .main) {
        // Sort audioURLs by chunk index to ensure they are in the correct order
        audioURLs.sort { $0.0 < $1.0 }
        let sortedURLs = audioURLs.map { $0.1 }
        let outputURL = documentsDirectory.appendingPathComponent("\(uniqueID).m4a")
        stitchAudioFiles(audioURLs: sortedURLs, outputURL: outputURL) { success in
            if success {
                for (_, url) in audioURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                completion(outputURL)
            } else {
                print("Error stitching audio files")
                completion(nil)
            }
        }
    }
}

func stitchAudioFiles(audioURLs: [URL], outputURL: URL, completion: @escaping (Bool) -> Void) {
    let composition = AVMutableComposition()
    let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

    var insertTime = CMTime.zero

    for (index, url) in audioURLs.enumerated() {
        let asset = AVAsset(url: url)
        guard let assetTrack = asset.tracks(withMediaType: .audio).first else { continue }
        let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        do {
            try track?.insertTimeRange(timeRange, of: assetTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, asset.duration)
            print("Inserted chunk \(index) at time \(insertTime.seconds)")
        } catch {
            print("Error inserting time range: \(error)")
            completion(false)
            return
        }
    }

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
        completion(false)
        return
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a
    exportSession.exportAsynchronously {
        if exportSession.status == .completed {
            print("Stitched audio file successfully")
            completion(true)
        } else {
            print("Error exporting stitched audio file: \(exportSession.error?.localizedDescription ?? "unknown error")")
            completion(false)
        }
    }
}
