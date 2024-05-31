//
//  TextToSpeech.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import Foundation
import SwiftKeychainWrapper
import OpenAI

func chunkText(_ text: String, chunkSize: Int) -> [String] {
    var chunks: [String] = []
    var startIndex = text.startIndex

    while startIndex < text.endIndex {
        var endIndex = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex

        // Ensure we don't split words
        if endIndex < text.endIndex {
            if let spaceIndex = text[..<endIndex].lastIndex(of: " ") {
                endIndex = spaceIndex
            }
        }

        let chunk = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        chunks.append(chunk)

        // Check if we've reached the end of the text
        if endIndex == text.endIndex {
            break
        }

        startIndex = text.index(after: endIndex)
    }

    return chunks
}

func convertTextToSpeech(text: String, voice: AudioSpeechQuery.AudioSpeechVoice, completion: @escaping (URL?) -> Void) {
    guard let openAI = getOpenAIClient() else {
        completion(nil)
        return
    }

    let query = AudioSpeechQuery(
        model: .tts_1_hd,
        input: text,
        voice: voice,
        responseFormat: .mp3,
        speed: 1.0
    )

    openAI.audioCreateSpeech(query: query) { result in
        switch result {
        case .success(let response):
            let data = response.audio
            let fileURL = saveAudioFile(data: data, voice: voice.rawValue)
            completion(fileURL)
        case .failure(let error):
            print("Error: \(error)")
            completion(nil)
        }
    }
}

func saveAudioFile(data: Data, voice: String) -> URL? {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(voice)_output.mp3")
    do {
        try data.write(to: fileURL)
        return fileURL
    } catch {
        print("Error saving audio file: \(error)")
        return nil
    }
}

func convertLargeTextToSpeech(text: String, voice: AudioSpeechQuery.AudioSpeechVoice, openAI: OpenAI, completion: @escaping ([URL]) -> Void) {
    let chunkSize = 4000  // or any appropriate chunk size
    let textChunks = chunkText(text, chunkSize: chunkSize)
    var audioURLs: [URL] = []
    let dispatchGroup = DispatchGroup()

    for chunk in textChunks {
        dispatchGroup.enter()
        let query = AudioSpeechQuery(model: .tts_1_hd, input: chunk, voice: voice, responseFormat: .mp3, speed: 1.0)
        openAI.audioCreateSpeech(query: query) { result in
            switch result {
            case .success(let audio):
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp3")
                do {
                    try audio.audio.write(to: tempURL)
                    audioURLs.append(tempURL)
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
        completion(audioURLs)
    }
}
