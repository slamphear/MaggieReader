//
//  AudioFileHandling.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/31/24.
//

import AVFoundation
import Foundation

func saveEntry(text: String, urls: [URL]) {
    let fileNames = urls.map { $0.lastPathComponent }
    if let data = try? JSONEncoder().encode(fileNames) {
        UserDefaults.standard.set(data, forKey: text)
    }
}

func getAudioURLs(for item: String) -> [URL] {
    if let data = UserDefaults.standard.data(forKey: item),
       let fileNames = try? JSONDecoder().decode([String].self, from: data) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return fileNames.map { documentsDirectory.appendingPathComponent($0) }
    }
    return []
}
