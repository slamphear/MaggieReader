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
                    #if canImport(UIKit)
                    Button(action: pasteFromClipboard) {
                        Text("Paste from Clipboard")
                    }
                    .padding()
                    #endif

                    Button(action: {
                        inputText = ""
                    }) {
                        Text("Clear all")
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

                Button(action: {
                    #if canImport(UIKit)
                    UIApplication.shared.endEditing(true)
                    #endif
                    isLoading = true
                    guard let openAI = getOpenAIClient() else {
                        print("API Token not found")
                        isLoading = false
                        return
                    }
                    convertTextToSpeech(text: inputText, voice: selectedVoice) { urls in
                        DispatchQueue.main.async {
                            self.isLoading = false
                            if urls.isEmpty {
                                print("Failed to convert text to speech.")
                                return
                            }
                            self.audioURLs = urls
                            self.isMediaPlayerActive = true
                            saveEntry(text: inputText, urls: urls)
                            self.items.append(inputText)
                            UserDefaults.standard.set(self.items, forKey: "savedItems")
                        }
                    }
                }) {
                    Text("Convert to Speech")
                }
                .padding()

                Spacer()

                if !audioURLs.isEmpty {
                    NavigationLink(destination: MediaPlayerView(inputText: inputText, audioURLs: audioURLs), isActive: $isMediaPlayerActive) {
                        EmptyView()
                    }
                }
            }
            .navigationTitle("New Entry")
            #if canImport(UIKit)
            .navigationBarItems(trailing: Button(action: {
                isPresentingNewEntryView = false
            }) {
                Text("Cancel")
            })
            #endif
        }

        if isLoading {
            ZStack {
                Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                ProgressView("Converting...")
                    .padding()
                    #if canImport(UIKit)
                    .background(Color(.systemBackground))
                    #endif
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
}

#if canImport(UIKit)
import UIKit

extension UIApplication {
    func endEditing(_ force: Bool) {
        self.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
