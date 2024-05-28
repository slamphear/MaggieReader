//
//  ContentView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import SwiftUI
import OpenAI

struct ContentView: View {
    @State private var apiToken: String = ""
    @State private var inputText: String = ""
    @State private var audioURLs: [URL] = []
    @State private var isTokenSaved: Bool = false
    @State private var selectedVoice: AudioSpeechQuery.AudioSpeechVoice = .fable
    @State private var isLoading: Bool = false
    @State private var isMediaPlayerActive: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    if !isTokenSaved {
                        VStack {
                            TextField("Enter OpenAI API Token", text: $apiToken)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding()

                            Button("Save Token") {
                                saveAPIToken(token: apiToken)
                                isTokenSaved = true
                            }
                            .padding()
                        }
                    } else {
                        VStack {
                            TextEditor(text: $inputText)
                                .border(Color.gray, width: 1)
                                .padding()
                                .frame(height: 200)

                            Button(action: pasteFromClipboard) {
                                Text("Paste from Clipboard")
                            }
                            .padding()

                            Picker("Voice", selection: $selectedVoice) {
                                ForEach(AudioSpeechQuery.AudioSpeechVoice.allCases, id: \.self) { voice in
                                    Text(voice.rawValue.capitalized).tag(voice)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .padding()

                            Button("Convert to Speech") {
                                UIApplication.shared.endEditing(true)
                                isLoading = true
                                convertLargeTextToSpeech(text: inputText, voice: selectedVoice) { urls in
                                    DispatchQueue.main.async {
                                        self.audioURLs = urls
                                        self.isLoading = false
                                        self.isMediaPlayerActive = true
                                    }
                                }
                            }
                            .padding()
                        }
                        .navigationTitle("Text to Speech")
                        .background(
                            NavigationLink(destination: MediaPlayerView(audioURLs: $audioURLs, inputText: $inputText, selectedVoice: $selectedVoice), isActive: $isMediaPlayerActive) {
                                EmptyView()
                            }
                        )
                    }
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
            .onAppear {
                if let token = getAPIToken() {
                    apiToken = token
                    isTokenSaved = true
                }
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
