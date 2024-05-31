//
//  NewEntryView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/28/24.
//

import SwiftUI
import OpenAI

struct NewEntryView: View {
    @Binding var items: [String]
    @Binding var isPresentingNewEntryView: Bool
    @State private var inputText: String = ""
    @State private var selectedVoice: AudioSpeechQuery.AudioSpeechVoice = .fable
    @State private var isLoading: Bool = false
    @State private var isMediaPlayerActive: Bool = false
    @State private var audioURLs: [URL] = []

    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $inputText)
                    .border(Color.gray, width: 1)
                    .padding()
                    .frame(height: 200)

                HStack {
                    Button(action: pasteFromClipboard) {
                        Text("Paste from Clipboard")
                    }
                    .padding()

                    Button("Clear all") {
                        inputText = ""
                    }
                    .padding()
                }

                Picker("Voice", selection: $selectedVoice) {
                    ForEach(AudioSpeechQuery.AudioSpeechVoice.allCases, id: \.self) { voice in
                        Text(voice.rawValue.capitalized).tag(voice)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                Spacer()

                Button("Convert to Speech") {
                    UIApplication.shared.endEditing(true)
                    isLoading = true
                    guard let openAI = getOpenAIClient() else {
                        print("API Token not found")
                        return
                    }
                    convertLargeTextToSpeech(text: inputText, voice: selectedVoice, openAI: openAI) { urls in
                        DispatchQueue.main.async {
                            self.audioURLs = urls
                            self.isLoading = false
                            self.isMediaPlayerActive = true
                            saveEntry()
                            self.items.append(inputText)
                            UserDefaults.standard.set(self.items, forKey: "savedItems")
                        }
                    }
                }
                .padding()

                Spacer()

                NavigationLink(destination: MediaPlayerView(inputText: inputText, audioURLs: audioURLs), isActive: $isMediaPlayerActive) {
                    EmptyView()
                }
            }
            .navigationTitle("New Entry")
            .navigationBarItems(trailing: Button("Cancel") {
                isPresentingNewEntryView = false
            })
        }

        if isLoading {
            ZStack {
                Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                ProgressView("Converting...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            }
        }
    }

    func pasteFromClipboard() {
        #if canImport(UIKit)
        if let clipboardContent = UIPasteboard.general.string {
            inputText = clipboardContent
        } else {
            print("No string content in the clipboard")
        }
        #endif
    }

    func saveEntry() {
        if let data = try? JSONEncoder().encode(audioURLs) {
            UserDefaults.standard.set(data, forKey: inputText)
        }
    }
}

#if canImport(UIKit)
import UIKit

extension UIApplication {
    func endEditing(_ force: Bool) {
        self.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
